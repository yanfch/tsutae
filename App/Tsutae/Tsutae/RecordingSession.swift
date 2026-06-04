import AppKit
import Combine
import Foundation
import OSLog
import TsutaeCore
import UserNotifications

@MainActor
final class RecordingSession: ObservableObject {
    
    static let shared = RecordingSession()
    
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "RecordingSession")
    private let audioInput = AudioInput.shared
    private let stt = OpenAICompatibleSTT()
    
    @Published private(set) var isBusy = false
    @Published private(set) var isRecording = false
    @Published private(set) var statusText = "idle"
    @Published private(set) var lastTranscript: String?
    @Published private(set) var lastError: String?
    @Published private(set) var lastRecordingBytes: Int = 0
    @Published private(set) var lastRecordingPath: String?
    @Published private(set) var liveRecordedBytes: Int = 0
    
    private var hasShownAccessibilityPermissionCompanionThisLaunch = false
    private var hasShownClipboardFallbackCompanionThisLaunch = false
    private var activeTranscriptionTask: Task<Void, Never>?
    private var activeOperationID = UUID()
    
    private init() {}
    
    func toggle() {
        if isRecording || audioInput.recording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }
    
    func cancel() {
        logger.info("Cancelling current recording/transcription session")
        activeOperationID = UUID()
        activeTranscriptionTask?.cancel()
        activeTranscriptionTask = nil
        audioInput.cancelRecording()
        FloatingRecordingBar.shared.hide()
        isBusy = false
        isRecording = false
        liveRecordedBytes = 0
        statusText = "cancelled"
    }
    
    private func startRecording() {
        guard !isBusy else {
            return
        }
        
        isBusy = true
        statusText = "requesting microphone permission"
        
        Task {
            do {
                try Paths.ensureDirectories()
                try await audioInput.startRecording()
                lastError = nil
                isRecording = true
                statusText = "recording"
                startRecordingProgressPolling()
                FloatingRecordingBar.shared.show(state: .listening)
                logger.info("Recording started")
            } catch {
                isBusy = false
                isRecording = false
                statusText = "start failed"
                lastError = error.localizedDescription
                presentStartError(error)
                logger.error("Failed to start recording: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private func stopAndTranscribe() {
        let audio: AudioData
        do {
            audio = try audioInput.stopRecording()
            isRecording = false
            liveRecordedBytes = 0
            lastRecordingBytes = audio.samples.count
            statusText = "transcribing"
            saveDebugWAV(audio)
            FloatingRecordingBar.shared.update(state: .thinking)
            logger.info("Recording stopped. bytes=\(audio.samples.count, privacy: .public)")
        } catch {
            isBusy = false
            isRecording = false
            liveRecordedBytes = 0
            statusText = "stop failed"
            lastError = error.localizedDescription
            presentStopError(error)
            logger.error("Failed to stop recording: \(error.localizedDescription, privacy: .public)")
            return
        }
        
        let operationID = UUID()
        activeOperationID = operationID
        activeTranscriptionTask?.cancel()
        activeTranscriptionTask = Task {
            defer {
                if self.activeOperationID == operationID {
                    self.activeTranscriptionTask = nil
                    self.isBusy = false
                }
            }
            
            do {
                let transcript = try await stt.transcribe(audio, language: nil)
                guard !Task.isCancelled, self.activeOperationID == operationID else {
                    self.logger.info("Discarded transcription result for cancelled session")
                    return
                }
                
                self.lastTranscript = transcript.text
                self.lastError = nil
                self.statusText = "done"
                
                // 显示 Done 状态
                FloatingRecordingBar.shared.update(state: .idle)
                
                // 延迟一会再关闭，便于观察 Done 状态
                try await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled, self.activeOperationID == operationID else {
                    self.logger.info("Cancelled session during done hold")
                    return
                }
                
                do {
                    try FocusedTextInjector.inject(transcript.text)
                    guard !Task.isCancelled, self.activeOperationID == operationID else {
                        self.logger.info("Cancelled session after injection completed")
                        return
                    }
                    FloatingRecordingBar.shared.hide()
                    self.notify(title: L10n.Notification.insertedTextTitle, body: transcript.text)
                    self.logger.info("Transcription injected. chars=\(transcript.text.count, privacy: .public)")
                } catch {
                    guard !Task.isCancelled, self.activeOperationID == operationID else {
                        self.logger.info("Cancelled session before injection fallback")
                        return
                    }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript.text, forType: .string)
                    self.lastError = "Inject failed, copied to clipboard: \(error.localizedDescription)"
                    self.statusText = "inject failed"
                    self.presentInjectionError(error)
                    self.logger.error("Injection failed: \(error.localizedDescription, privacy: .public)")
                }
            } catch is CancellationError {
                self.logger.info("Transcription task cancelled")
            } catch {
                guard !Task.isCancelled, self.activeOperationID == operationID else {
                    self.logger.info("Discarded transcription error for cancelled session")
                    return
                }
                self.lastError = error.localizedDescription
                self.statusText = "transcription failed"
                self.presentTranscriptionError(error)
                self.logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private func startRecordingProgressPolling() {
        Task {
            while audioInput.recording {
                liveRecordedBytes = audioInput.recordedByteCount
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
    
    private func saveDebugWAV(_ audio: AudioData) {
        do {
            try Paths.ensureDirectories()
            let url = Paths.logs.appendingPathComponent("last-recording.wav")
            let wav = try WAVEncoder.encode(audio)
            try wav.write(to: url, options: .atomic)
            lastRecordingPath = url.path
            logger.info("Saved debug recording: \(url.path, privacy: .public)")
        } catch {
            lastError = "Failed to save debug recording: \(error.localizedDescription)"
            logger.error("Failed to save debug recording: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func presentStartError(_ error: Error) {
        if let audioError = error as? AudioInputError {
            switch audioError {
            case .microphonePermissionDenied:
                presentCompanion(
                    title: L10n.RecordingCompanion.microphoneAccessRequiredTitle,
                    message: L10n.RecordingCompanion.microphoneAccessRequiredMessage,
                    primaryAction: .init(title: L10n.Common.openSystemSettings, style: .primary) {
                        FloatingRecordingBar.shared.dismissCompanion()
                        FloatingRecordingBar.shared.openSystemSettingsPrivacyPane("Privacy_Microphone")
                    },
                    secondaryAction: .init(title: L10n.Common.notNow, style: .secondary) {
                        FloatingRecordingBar.shared.dismissCompanion()
                    }
                )
                return
            case .noInputDevice:
                presentCompanion(
                    title: L10n.RecordingCompanion.noMicrophoneDetectedTitle,
                    message: L10n.RecordingCompanion.noMicrophoneDetectedMessage,
                    primaryAction: .init(title: L10n.Common.dismiss, style: .primary) {
                        FloatingRecordingBar.shared.dismissCompanion()
                    }
                )
                return
            case .formatConversionUnavailable:
                presentCompanion(
                    title: L10n.RecordingCompanion.audioInputUnavailableTitle,
                    message: L10n.RecordingCompanion.audioInputUnavailableMessage,
                    primaryAction: .init(title: L10n.Common.dismiss, style: .primary) {
                        FloatingRecordingBar.shared.dismissCompanion()
                    }
                )
                return
            case .notRecording, .recordingTooShort:
                break
            }
        }
        
        presentCompanion(
            title: L10n.RecordingCompanion.recordingFailedTitle,
            message: error.localizedDescription,
            primaryAction: .init(title: L10n.Common.dismiss, style: .primary) {
                FloatingRecordingBar.shared.dismissCompanion()
            }
        )
    }
    
    private func presentStopError(_ error: Error) {
        presentCompanion(
            title: L10n.RecordingCompanion.couldntFinishRecordingTitle,
            message: error.localizedDescription,
            primaryAction: .init(title: L10n.Common.dismiss, style: .primary) {
                FloatingRecordingBar.shared.dismissCompanion()
            }
        )
    }
    
    private func presentTranscriptionError(_ error: Error) {
        if let urlError = error as? URLError {
            let message: String
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                message = L10n.RecordingCompanion.transcriptionNetworkMessage
            case .timedOut:
                message = L10n.RecordingCompanion.transcriptionTimeoutMessage
            default:
                message = L10n.RecordingCompanion.transcriptionUnreachableMessage
            }
            
            presentCompanion(
                title: L10n.RecordingCompanion.transcriptionUnavailableTitle,
                message: message,
                primaryAction: .init(title: L10n.Common.openSettings, style: .primary) {
                    FloatingRecordingBar.shared.dismissCompanion()
                    FloatingRecordingBar.shared.openAppSettings(tab: "server")
                },
                secondaryAction: .init(title: L10n.Common.notNow, style: .secondary) {
                    FloatingRecordingBar.shared.dismissCompanion()
                }
            )
            return
        }
        
        if let sttError = error as? OpenAICompatibleSTTError {
            switch sttError {
            case .httpStatus(let status, _):
                if status == 401 || status == 403 {
                    presentCompanion(
                        title: L10n.RecordingCompanion.authenticationFailedTitle,
                        message: L10n.RecordingCompanion.authenticationFailedMessage,
                        primaryAction: .init(title: L10n.Common.openSettings, style: .primary) {
                            FloatingRecordingBar.shared.dismissCompanion()
                            FloatingRecordingBar.shared.openAppSettings(tab: "server")
                        },
                        secondaryAction: .init(title: L10n.Common.notNow, style: .secondary) {
                            FloatingRecordingBar.shared.dismissCompanion()
                        }
                    )
                    return
                }
                
                if status == 400 || status == 404 || status == 422 {
                    presentCompanion(
                        title: L10n.RecordingCompanion.sttConfigurationErrorTitle,
                        message: L10n.RecordingCompanion.sttConfigurationErrorMessage,
                        primaryAction: .init(title: L10n.Common.openSettings, style: .primary) {
                            FloatingRecordingBar.shared.dismissCompanion()
                            FloatingRecordingBar.shared.openAppSettings(tab: "stt")
                        },
                        secondaryAction: .init(title: L10n.Common.notNow, style: .secondary) {
                            FloatingRecordingBar.shared.dismissCompanion()
                        }
                    )
                    return
                }
            case .invalidResponse:
                break
            case .invalidAudioFormat:
                break
            }
        }
        
        presentCompanion(
            title: L10n.RecordingCompanion.transcriptionFailedTitle,
            message: L10n.RecordingCompanion.transcriptionFailedMessage,
            primaryAction: .init(title: L10n.Common.openSettings, style: .primary) {
                FloatingRecordingBar.shared.dismissCompanion()
                FloatingRecordingBar.shared.openAppSettings(tab: "server")
            },
            secondaryAction: .init(title: L10n.Common.notNow, style: .secondary) {
                FloatingRecordingBar.shared.dismissCompanion()
            }
        )
    }
    
    private func presentInjectionError(_ error: Error) {
        if let injectError = error as? FocusedTextInjectorError {
            switch injectError {
            case .accessibilityPermissionDenied:
                if !hasShownAccessibilityPermissionCompanionThisLaunch {
                    hasShownAccessibilityPermissionCompanionThisLaunch = true
                    presentCompanion(
                        title: L10n.RecordingCompanion.accessibilityAccessRequiredTitle,
                        message: L10n.RecordingCompanion.accessibilityAccessRequiredMessage,
                        primaryAction: .init(title: L10n.Common.openAccessibilitySettings, style: .primary) {
                            _ = FocusedTextInjector.requestAccessibilityPermission()
                            FloatingRecordingBar.shared.dismissCompanion()
                            FloatingRecordingBar.shared.openSystemSettingsPrivacyPane("Privacy_Accessibility")
                        },
                        secondaryAction: .init(title: L10n.Common.notNow, style: .secondary) {
                            FloatingRecordingBar.shared.dismissCompanion()
                        },
                        displayState: .idle
                    )
                } else if !hasShownClipboardFallbackCompanionThisLaunch {
                    hasShownClipboardFallbackCompanionThisLaunch = true
                    presentCompanion(
                        title: L10n.RecordingCompanion.copiedToClipboardTitle,
                        message: L10n.RecordingCompanion.copiedToClipboardMessage,
                        primaryAction: .init(title: L10n.Common.dismiss, style: .primary) {
                            FloatingRecordingBar.shared.dismissCompanion()
                        },
                        autoDismissAfter: 3,
                        displayState: .idle
                    )
                } else {
                    FloatingRecordingBar.shared.hide()
                }
                return
            }
        }
        
        if !hasShownClipboardFallbackCompanionThisLaunch {
            hasShownClipboardFallbackCompanionThisLaunch = true
            presentCompanion(
                title: L10n.RecordingCompanion.copiedToClipboardTitle,
                message: L10n.RecordingCompanion.copiedToClipboardMessage,
                primaryAction: .init(title: L10n.Common.dismiss, style: .primary) {
                    FloatingRecordingBar.shared.dismissCompanion()
                },
                autoDismissAfter: 3,
                displayState: .idle
            )
        } else {
            FloatingRecordingBar.shared.hide()
        }
    }
    
    private func presentCompanion(
        title: String,
        message: String,
        primaryAction: RecordingBarCompanionAction,
        secondaryAction: RecordingBarCompanionAction? = nil,
        autoDismissAfter: TimeInterval? = nil,
        displayState: RecordingBarVisualState = .failed
    ) {
        FloatingRecordingBar.shared.showCompanion(
            RecordingBarCompanion(
                title: title,
                message: message,
                primaryAction: primaryAction,
                secondaryAction: secondaryAction,
                autoDismissAfter: autoDismissAfter
            ),
            displayState: displayState
        )
    }
    
    private func notify(title: String, body: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            try? await center.add(UNNotificationRequest(
                identifier: "tsutae.recording.\(UUID().uuidString)",
                content: content,
                trigger: nil
            ))
        }
    }
}
