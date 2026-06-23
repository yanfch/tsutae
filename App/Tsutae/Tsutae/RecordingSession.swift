import AppKit
import Combine
import Foundation
import OSLog
import TsutaeCore

private struct ProcessedTranscriptOutcome {
    let text: String
    let postProcessing: TranscriptPostProcessingResult?
}

@MainActor
final class RecordingSession: ObservableObject {
    
    static let shared = RecordingSession()
    
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "RecordingSession")
    private let audioInput = AudioInput.shared
    
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
    private var hasShownLongRecordingWarning = false
    private var activeWarmupTask: Task<Void, Never>?
    private var activeTranscriptionTask: Task<Void, Never>?
    private var activeOperationID = UUID()
    private var activeTargetApplication: FocusedApplicationSnapshot?
    
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
        activeWarmupTask?.cancel()
        activeWarmupTask = nil
        activeTranscriptionTask?.cancel()
        activeTranscriptionTask = nil
        audioInput.cancelRecording()
        FloatingRecordingBar.shared.hide()
        isBusy = false
        isRecording = false
        activeTargetApplication = nil
        hasShownLongRecordingWarning = false
        liveRecordedBytes = 0
        statusText = "cancelled"
    }
    
    private func startRecording() {
        guard !isBusy else {
            return
        }
        
        isBusy = true
        statusText = "requesting microphone permission"
        let operationID = UUID()
        activeOperationID = operationID
        activeWarmupTask?.cancel()
        activeTargetApplication = FocusedTextInjector.focusedApplicationSnapshot(
            excludingBundleIdentifier: Bundle.main.bundleIdentifier
        )
        if let activeTargetApplication {
            let targetMessage = "Recording target captured. app=\(activeTargetApplication.localizedName ?? "") bundle=\(activeTargetApplication.bundleIdentifier ?? "") pid=\(activeTargetApplication.processIdentifier)"
            logger.info("\(targetMessage, privacy: .public)")
            PerformanceLog.record(category: "RecordingSession", message: targetMessage)
        }
        
        activeWarmupTask = Task {
            defer {
                if self.activeOperationID == operationID {
                    self.activeWarmupTask = nil
                }
            }
            
            do {
                let config = (try? ConfigLoader.load()) ?? .default
                if await LocalSTTResidencyCoordinator.shared.requiresWarmupGate(config: config) {
                    self.statusText = "warming local model"
                    FloatingRecordingBar.shared.show(state: .idle)
                    self.presentCompanion(
                        title: L10n.RecordingCompanion.preparingLocalModelTitle,
                        message: L10n.RecordingCompanion.preparingLocalModelMessage,
                        tone: .info,
                        displayState: .waiting
                    )
                    try await LocalSTTResidencyCoordinator.shared.waitUntilLocalModelReady(config: config)
                    try Task.checkCancellation()
                    guard self.activeOperationID == operationID else { return }
                }
                
                try Paths.ensureDirectories()
                try await audioInput.startRecording()
                try Task.checkCancellation()
                guard self.activeOperationID == operationID else {
                    audioInput.cancelRecording()
                    return
                }
                self.lastError = nil
                self.hasShownLongRecordingWarning = false
                self.isRecording = true
                self.statusText = "recording"
                self.startRecordingProgressPolling()
                FloatingRecordingBar.shared.show(state: .listening)
                self.logger.info("Recording started")
            } catch is CancellationError {
                self.logger.info("Recording start cancelled before microphone capture began")
            } catch {
                self.isBusy = false
                self.isRecording = false
                self.activeTargetApplication = nil
                self.statusText = "start failed"
                self.lastError = error.localizedDescription
                self.presentStartError(error)
                self.logger.error("Failed to start recording: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private func stopAndTranscribe() {
        let audio: AudioData
        let stopStartedAt = CFAbsoluteTimeGetCurrent()
        do {
            audio = try audioInput.stopRecording()
            let stopElapsedMs = formatElapsedMs(since: stopStartedAt)
            isRecording = false
            liveRecordedBytes = 0
            lastRecordingBytes = audio.samples.count
            statusText = "transcribing"
            let saveStartedAt = CFAbsoluteTimeGetCurrent()
            saveDebugWAV(audio)
            let saveElapsedMs = formatElapsedMs(since: saveStartedAt)
            FloatingRecordingBar.shared.update(state: .thinking)
            let stopMessage = "Recording stopped. bytes=\(audio.samples.count) stop_elapsed_ms=\(stopElapsedMs) save_wav_elapsed_ms=\(saveElapsedMs)"
            logger.info("\(stopMessage, privacy: .public)")
            PerformanceLog.record(category: "RecordingSession", message: stopMessage)
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
        let recordingStartApplication = activeTargetApplication
        activeTranscriptionTask = Task {
            let transcriptionStartedAt = CFAbsoluteTimeGetCurrent()
            defer {
                if self.activeOperationID == operationID {
                    self.activeTranscriptionTask = nil
                    self.isBusy = false
                }
            }
            
            do {
                let transcript = try await ConfiguredSTTRouter.transcribe(audio)
                let transcriptionElapsedMs = self.elapsedMs(since: transcriptionStartedAt)
                let transcribeDoneMessage = "RecordingSession transcription finished. chars=\(transcript.text.count) elapsed_ms=\(self.formatElapsedMs(transcriptionElapsedMs))"
                self.logger.info("\(transcribeDoneMessage, privacy: .public)")
                PerformanceLog.record(category: "RecordingSession", message: transcribeDoneMessage)
                guard !Task.isCancelled, self.activeOperationID == operationID else {
                    self.logger.info("Discarded transcription result for cancelled session")
                    return
                }
                
                let config = (try? ConfigLoader.load()) ?? .default
                let processed = await self.postProcessedTranscriptText(
                    transcript.text,
                    config: config,
                    operationStartedAt: transcriptionStartedAt,
                    context: "recording"
                )
                let finalText = processed.text

                self.lastTranscript = finalText
                self.lastError = nil
                self.statusText = "done"
                
                // 显示 Done 状态
                FloatingRecordingBar.shared.update(state: .idle)
                
                // 延迟一会再关闭，便于观察 Done 状态
                let doneHoldStartedAt = CFAbsoluteTimeGetCurrent()
                try await Task.sleep(for: .milliseconds(150))
                let doneHoldMessage = "RecordingSession done hold finished. elapsed_ms=\(self.formatElapsedMs(since: doneHoldStartedAt))"
                self.logger.info("\(doneHoldMessage, privacy: .public)")
                PerformanceLog.record(category: "RecordingSession", message: doneHoldMessage)
                guard !Task.isCancelled, self.activeOperationID == operationID else {
                    self.logger.info("Cancelled session during done hold")
                    return
                }
                
                let injectStartedAt = CFAbsoluteTimeGetCurrent()
                let insertionApplication = FocusedTextInjector.focusedApplicationSnapshot(
                    excludingBundleIdentifier: Bundle.main.bundleIdentifier
                )
                let targetApplication = insertionApplication ?? recordingStartApplication
                do {
                    try FocusedTextInjector.inject(finalText)
                    guard !Task.isCancelled, self.activeOperationID == operationID else {
                        self.logger.info("Cancelled session after injection completed")
                        return
                    }
                    FloatingRecordingBar.shared.hide()
                    let injectElapsedMs = self.elapsedMs(since: injectStartedAt)
                    let endToEndElapsedMs = self.elapsedMs(since: transcriptionStartedAt)
                    ASRSampleLog.record(
                        ASRSampleLog.makeRecord(
                            context: "recording",
                            audio: audio,
                            transcript: transcript,
                            config: config,
                            transcriptionElapsedMs: transcriptionElapsedMs,
                            totalElapsedMs: endToEndElapsedMs,
                            postProcessing: processed.postProcessing,
                            targetApplication: targetApplication,
                            recordingStartApplication: recordingStartApplication,
                            insertionApplication: insertionApplication,
                            insertion: ASRSampleLog.InsertionSnapshot(
                                method: "focused_app",
                                succeeded: true,
                                elapsedMs: injectElapsedMs
                            ),
                            endToEndElapsedMs: endToEndElapsedMs
                        )
                    )
                    self.activeTargetApplication = nil
                    let injectDoneMessage = "Transcription injected. raw_chars=\(transcript.text.count) chars=\(finalText.count) target_app=\(targetApplication?.bundleIdentifier ?? "") output_method=focused_app inject_elapsed_ms=\(self.formatElapsedMs(injectElapsedMs)) total_elapsed_ms=\(self.formatElapsedMs(endToEndElapsedMs))"
                    self.logger.info("\(injectDoneMessage, privacy: .public)")
                    PerformanceLog.record(category: "RecordingSession", message: injectDoneMessage)
                } catch {
                    guard !Task.isCancelled, self.activeOperationID == operationID else {
                        self.logger.info("Cancelled session before injection fallback")
                        return
                    }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(finalText, forType: .string)
                    self.lastError = "Inject failed, copied to clipboard: \(error.localizedDescription)"
                    self.statusText = "inject failed"
                    self.presentInjectionError(error)
                    let injectElapsedMs = self.elapsedMs(since: injectStartedAt)
                    let endToEndElapsedMs = self.elapsedMs(since: transcriptionStartedAt)
                    ASRSampleLog.record(
                        ASRSampleLog.makeRecord(
                            context: "recording",
                            audio: audio,
                            transcript: transcript,
                            config: config,
                            transcriptionElapsedMs: transcriptionElapsedMs,
                            totalElapsedMs: endToEndElapsedMs,
                            postProcessing: processed.postProcessing,
                            targetApplication: targetApplication,
                            recordingStartApplication: recordingStartApplication,
                            insertionApplication: insertionApplication,
                            insertion: ASRSampleLog.InsertionSnapshot(
                                method: "clipboard_fallback",
                                succeeded: true,
                                elapsedMs: injectElapsedMs,
                                error: error.localizedDescription
                            ),
                            endToEndElapsedMs: endToEndElapsedMs
                        )
                    )
                    self.activeTargetApplication = nil
                    let injectFailedMessage = "Injection failed: \(error.localizedDescription) target_app=\(targetApplication?.bundleIdentifier ?? "") output_method=clipboard_fallback inject_elapsed_ms=\(self.formatElapsedMs(injectElapsedMs)) total_elapsed_ms=\(self.formatElapsedMs(endToEndElapsedMs))"
                    self.logger.error("\(injectFailedMessage, privacy: .public)")
                    PerformanceLog.record(category: "RecordingSession", message: injectFailedMessage)
                }
            } catch is CancellationError {
                let cancelledMessage = "Transcription task cancelled. elapsed_ms=\(self.formatElapsedMs(since: transcriptionStartedAt))"
                self.logger.info("\(cancelledMessage, privacy: .public)")
                PerformanceLog.record(category: "RecordingSession", message: cancelledMessage)
            } catch {
                guard !Task.isCancelled, self.activeOperationID == operationID else {
                    self.logger.info("Discarded transcription error for cancelled session")
                    return
                }
                self.lastError = error.localizedDescription
                self.statusText = "transcription failed"
                self.presentTranscriptionError(error, audio: audio)
                let transcriptionFailedMessage = "Transcription failed: \(error.localizedDescription) audio_seconds=\(self.audioDurationSeconds(audio)) total_elapsed_ms=\(self.formatElapsedMs(since: transcriptionStartedAt))"
                self.logger.error("\(transcriptionFailedMessage, privacy: .public)")
                PerformanceLog.record(category: "RecordingSession", message: transcriptionFailedMessage)
            }
        }
    }
    
    private func startRecordingProgressPolling() {
        let operationID = activeOperationID
        Task {
            while audioInput.recording {
                liveRecordedBytes = audioInput.recordedByteCount
                if activeOperationID == operationID {
                    maybePresentLongRecordingWarning(recordedBytes: liveRecordedBytes)
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func maybePresentLongRecordingWarning(recordedBytes: Int) {
        guard hasShownLongRecordingWarning == false else { return }
        guard let context = currentLocalRecordingGuidanceContext() else { return }
        let seconds = Int(recordingDurationSeconds(sampleBytes: recordedBytes).rounded(.down))
        guard seconds >= context.guidance.warningSeconds else { return }

        hasShownLongRecordingWarning = true
        let message = "Long recording warning shown. model=\(context.modelID) audio_seconds=\(seconds) warning_seconds=\(context.guidance.warningSeconds) recommended_max_seconds=\(context.guidance.recommendedMaximumSeconds) estimated=\(context.guidance.isEstimated)"
        logger.info("\(message, privacy: .public)")
        PerformanceLog.record(category: "RecordingSession", message: message)

        presentCompanion(
            title: L10n.RecordingCompanion.longRecordingWarningTitle,
            message: L10n.RecordingCompanion.longRecordingWarningMessage(
                seconds: seconds,
                modelName: context.modelName,
                limitSeconds: context.guidance.recommendedMaximumSeconds
            ),
            tone: .warning,
            primaryAction: .init(title: L10n.Menu.stopAndTranscribe, style: .primary) {
                self.stopAndTranscribe()
            },
            secondaryAction: .init(title: L10n.RecordingCompanion.longRecordingKeepGoing, style: .secondary) {
                FloatingRecordingBar.shared.update(state: .listening)
            },
            displayState: .warning
        )
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

    private struct LocalRecordingGuidanceContext {
        let modelID: String
        let modelName: String
        let guidance: LocalSTTRecordingGuidance
    }

    private func currentLocalRecordingGuidanceContext() -> LocalRecordingGuidanceContext? {
        let config = (try? ConfigLoader.load()) ?? .default
        guard config.stt.mode == .localFirst else { return nil }
        let modelID = config.stt.local.preferredModel ?? config.stt.model ?? "parakeet-tdt-v3"
        let descriptor = LocalSTTModelCatalog.descriptor(id: modelID)
        return LocalRecordingGuidanceContext(
            modelID: modelID,
            modelName: descriptor?.displayName ?? modelID,
            guidance: LocalSTTModelCatalog.recordingGuidance(for: modelID)
        )
    }

    private func remoteRetryConfig() -> Config? {
        var config = (try? ConfigLoader.load()) ?? .default
        guard config.stt.remote.enabled,
              config.stt.remote.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              config.stt.remote.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return nil
        }
        config.stt.mode = .remoteFirst
        return config
    }
    
    private func presentStartError(_ error: Error) {
        if let audioError = error as? AudioInputError {
            switch audioError {
            case .microphonePermissionDenied:
                presentCompanion(
                    title: L10n.RecordingCompanion.microphoneAccessRequiredTitle,
                    message: L10n.RecordingCompanion.microphoneAccessRequiredMessage,
                    tone: .warning,
                    primaryAction: .init(title: L10n.Common.openSettings, style: .primary) {
                        FloatingRecordingBar.shared.dismissCompanion()
                        FloatingRecordingBar.shared.openAppSettings(tab: "permissions", focus: "microphone")
                    },
                    secondaryAction: .init(title: L10n.Common.notNow, style: .secondary) {
                        FloatingRecordingBar.shared.dismissCompanion()
                    },
                    displayState: .warning
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

    private func presentLongTranscriptionFailure(audio: AudioData?) {
        let primaryAction: RecordingBarCompanionAction
        if let audio, remoteRetryConfig() != nil {
            primaryAction = .init(title: L10n.RecordingCompanion.retryRemoteTranscription, style: .primary) {
                self.retryTranscriptionWithRemote(audio: audio)
            }
        } else {
            primaryAction = .init(title: L10n.Common.openSettings, style: .primary) {
                FloatingRecordingBar.shared.dismissCompanion()
                FloatingRecordingBar.shared.openAppSettings(tab: "stt")
            }
        }

        presentCompanion(
            title: L10n.RecordingCompanion.longTranscriptionFailedTitle,
            message: L10n.RecordingCompanion.longTranscriptionFailedMessage,
            tone: .warning,
            primaryAction: primaryAction,
            secondaryAction: .init(title: L10n.Common.dismiss, style: .secondary) {
                FloatingRecordingBar.shared.dismissCompanion()
            },
            displayState: .warning
        )
    }

    private func retryTranscriptionWithRemote(audio: AudioData) {
        guard let config = remoteRetryConfig() else {
            FloatingRecordingBar.shared.openAppSettings(tab: "stt")
            return
        }

        let operationID = UUID()
        activeOperationID = operationID
        activeTranscriptionTask?.cancel()
        isBusy = true
        isRecording = false
        liveRecordedBytes = 0
        statusText = "retrying remote transcription"
        lastError = nil
        FloatingRecordingBar.shared.update(state: .thinking)

        let retryMessage = "Remote STT retry started. audio_seconds=\(audioDurationSeconds(audio)) audio_bytes=\(audio.samples.count) remote_model=\(config.stt.remote.model ?? "")"
        logger.info("\(retryMessage, privacy: .public)")
        PerformanceLog.record(category: "RecordingSession", message: retryMessage)

        let recordingStartApplication = activeTargetApplication
        activeTranscriptionTask = Task {
            let transcriptionStartedAt = CFAbsoluteTimeGetCurrent()
            defer {
                if self.activeOperationID == operationID {
                    self.activeTranscriptionTask = nil
                    self.isBusy = false
                }
            }

            do {
                let transcript = try await ConfiguredSTTRouter.transcribe(audio, config: config)
                let transcriptionElapsedMs = self.elapsedMs(since: transcriptionStartedAt)
                let doneMessage = "Remote STT retry finished. chars=\(transcript.text.count) audio_seconds=\(self.audioDurationSeconds(audio)) elapsed_ms=\(self.formatElapsedMs(transcriptionElapsedMs))"
                self.logger.info("\(doneMessage, privacy: .public)")
                PerformanceLog.record(category: "RecordingSession", message: doneMessage)
                guard !Task.isCancelled, self.activeOperationID == operationID else { return }

                let processed = await self.postProcessedTranscriptText(
                    transcript.text,
                    config: config,
                    operationStartedAt: transcriptionStartedAt,
                    context: "remote_retry"
                )
                let finalText = processed.text

                self.lastTranscript = finalText
                self.lastError = nil
                self.statusText = "done"
                FloatingRecordingBar.shared.update(state: .idle)

                let injectStartedAt = CFAbsoluteTimeGetCurrent()
                let insertionApplication = FocusedTextInjector.focusedApplicationSnapshot(
                    excludingBundleIdentifier: Bundle.main.bundleIdentifier
                )
                let targetApplication = insertionApplication ?? recordingStartApplication
                do {
                    try FocusedTextInjector.inject(finalText)
                    guard !Task.isCancelled, self.activeOperationID == operationID else { return }
                    FloatingRecordingBar.shared.hide()
                    let injectElapsedMs = self.elapsedMs(since: injectStartedAt)
                    let endToEndElapsedMs = self.elapsedMs(since: transcriptionStartedAt)
                    ASRSampleLog.record(
                        ASRSampleLog.makeRecord(
                            context: "remote_retry",
                            audio: audio,
                            transcript: transcript,
                            config: config,
                            transcriptionElapsedMs: transcriptionElapsedMs,
                            totalElapsedMs: endToEndElapsedMs,
                            postProcessing: processed.postProcessing,
                            targetApplication: targetApplication,
                            recordingStartApplication: recordingStartApplication,
                            insertionApplication: insertionApplication,
                            insertion: ASRSampleLog.InsertionSnapshot(
                                method: "focused_app",
                                succeeded: true,
                                elapsedMs: injectElapsedMs
                            ),
                            endToEndElapsedMs: endToEndElapsedMs
                        )
                    )
                    self.activeTargetApplication = nil
                    let injectDoneMessage = "Remote retry transcription injected. raw_chars=\(transcript.text.count) chars=\(finalText.count) target_app=\(targetApplication?.bundleIdentifier ?? "") output_method=focused_app inject_elapsed_ms=\(self.formatElapsedMs(injectElapsedMs)) total_elapsed_ms=\(self.formatElapsedMs(endToEndElapsedMs))"
                    self.logger.info("\(injectDoneMessage, privacy: .public)")
                    PerformanceLog.record(category: "RecordingSession", message: injectDoneMessage)
                } catch {
                    guard !Task.isCancelled, self.activeOperationID == operationID else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(finalText, forType: .string)
                    self.lastError = "Inject failed, copied to clipboard: \(error.localizedDescription)"
                    self.statusText = "inject failed"
                    self.presentInjectionError(error)
                    let injectElapsedMs = self.elapsedMs(since: injectStartedAt)
                    let endToEndElapsedMs = self.elapsedMs(since: transcriptionStartedAt)
                    ASRSampleLog.record(
                        ASRSampleLog.makeRecord(
                            context: "remote_retry",
                            audio: audio,
                            transcript: transcript,
                            config: config,
                            transcriptionElapsedMs: transcriptionElapsedMs,
                            totalElapsedMs: endToEndElapsedMs,
                            postProcessing: processed.postProcessing,
                            targetApplication: targetApplication,
                            recordingStartApplication: recordingStartApplication,
                            insertionApplication: insertionApplication,
                            insertion: ASRSampleLog.InsertionSnapshot(
                                method: "clipboard_fallback",
                                succeeded: true,
                                elapsedMs: injectElapsedMs,
                                error: error.localizedDescription
                            ),
                            endToEndElapsedMs: endToEndElapsedMs
                        )
                    )
                    self.activeTargetApplication = nil
                    let injectFailedMessage = "Remote retry injection failed: \(error.localizedDescription) target_app=\(targetApplication?.bundleIdentifier ?? "") output_method=clipboard_fallback inject_elapsed_ms=\(self.formatElapsedMs(injectElapsedMs)) total_elapsed_ms=\(self.formatElapsedMs(endToEndElapsedMs))"
                    self.logger.error("\(injectFailedMessage, privacy: .public)")
                    PerformanceLog.record(category: "RecordingSession", message: injectFailedMessage)
                }
            } catch {
                guard !Task.isCancelled, self.activeOperationID == operationID else { return }
                self.lastError = error.localizedDescription
                self.statusText = "transcription failed"
                self.presentTranscriptionError(error)
                let failedMessage = "Remote STT retry failed: \(error.localizedDescription) audio_seconds=\(self.audioDurationSeconds(audio)) total_elapsed_ms=\(self.formatElapsedMs(since: transcriptionStartedAt))"
                self.logger.error("\(failedMessage, privacy: .public)")
                PerformanceLog.record(category: "RecordingSession", message: failedMessage)
            }
        }
    }

    private func postProcessedTranscriptText(
        _ rawText: String,
        config: Config,
        operationStartedAt: CFAbsoluteTime,
        context: String
    ) async -> ProcessedTranscriptOutcome {
        guard config.postProcessing.enabled else {
            let skippedMessage = "Transcript post-processing skipped. context=\(context) reason=disabled chars=\(rawText.count) total_elapsed_ms=\(formatElapsedMs(since: operationStartedAt))"
            logger.info("\(skippedMessage, privacy: .public)")
            PerformanceLog.record(category: "RecordingSession", message: skippedMessage)
            return ProcessedTranscriptOutcome(text: rawText, postProcessing: nil)
        }

        do {
            let result = try await TranscriptPostProcessor.process(
                rawText,
                config: config.postProcessing,
                language: config.stt.language,
                appContext: context,
                dictionaryContext: TranscriptDictionaryContext(config: config, appContext: context)
            )
            let message = "Transcript post-processing finished. context=\(context) mode=\(result.mode.rawValue) provider=\(result.provider) model=\(result.model ?? "") raw_chars=\(rawText.count) chars=\(result.processedText.count) postprocess_elapsed_ms=\(String(format: "%.1f", result.elapsedMs)) total_elapsed_ms=\(formatElapsedMs(since: operationStartedAt))"
            logger.info("\(message, privacy: .public)")
            PerformanceLog.record(category: "RecordingSession", message: message)
            return ProcessedTranscriptOutcome(text: result.processedText, postProcessing: result)
        } catch {
            let message = "Transcript post-processing failed. context=\(context) error=\(error.localizedDescription) fallback=raw total_elapsed_ms=\(formatElapsedMs(since: operationStartedAt))"
            logger.error("\(message, privacy: .public)")
            PerformanceLog.record(category: "RecordingSession", message: message)
            return ProcessedTranscriptOutcome(text: rawText, postProcessing: nil)
        }
    }
    
    private func presentTranscriptionError(_ error: Error, audio: AudioData? = nil) {
        if let sttError = error as? STTTranscriptionError {
            logTranscriptionFailure(error: sttError, audio: audio)

            if sttError.isLikelyLongAudioLimit {
                presentLongTranscriptionFailure(audio: audio)
                return
            }

            presentCompanion(
                title: L10n.RecordingCompanion.emptyTranscriptTitle,
                message: L10n.RecordingCompanion.emptyTranscriptMessage,
                tone: .warning,
                primaryAction: .init(title: L10n.Common.openSettings, style: .primary) {
                    FloatingRecordingBar.shared.dismissCompanion()
                    FloatingRecordingBar.shared.openAppSettings(tab: "stt")
                },
                secondaryAction: .init(title: L10n.Common.dismiss, style: .secondary) {
                    FloatingRecordingBar.shared.dismissCompanion()
                },
                displayState: .warning
            )
            return
        }

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
        
        if let appleSpeechError = error as? AppleSpeechSTTError {
            switch appleSpeechError {
            case .authorizationDenied, .authorizationPending:
                presentCompanion(
                    title: L10n.RecordingCompanion.speechRecognitionAccessRequiredTitle,
                    message: L10n.RecordingCompanion.speechRecognitionAccessRequiredMessage,
                    tone: .warning,
                    primaryAction: .init(title: L10n.Common.openSettings, style: .primary) {
                        FloatingRecordingBar.shared.dismissCompanion()
                        FloatingRecordingBar.shared.openAppSettings(tab: "permissions", focus: "speechRecognition")
                    },
                    secondaryAction: .init(title: L10n.Common.notNow, style: .secondary) {
                        FloatingRecordingBar.shared.dismissCompanion()
                    },
                    displayState: .warning
                )
                return
            case .recognizerUnavailable, .recognitionTimedOut, .missingUsageDescription:
                presentCompanion(
                    title: L10n.RecordingCompanion.sttConfigurationErrorTitle,
                    message: appleSpeechError.localizedDescription,
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
        }
        
        if error is FluidAudioSTTError {
            presentCompanion(
                title: L10n.RecordingCompanion.sttConfigurationErrorTitle,
                message: error.localizedDescription,
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
                        tone: .warning,
                        primaryAction: .init(title: L10n.Common.openSettings, style: .primary) {
                            _ = FocusedTextInjector.requestAccessibilityPermission()
                            FloatingRecordingBar.shared.dismissCompanion()
                            FloatingRecordingBar.shared.openAppSettings(tab: "permissions", focus: "accessibility")
                        },
                        secondaryAction: .init(title: L10n.Common.notNow, style: .secondary) {
                            FloatingRecordingBar.shared.dismissCompanion()
                        },
                        displayState: .warning
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
        tone: RecordingBarCompanion.Tone = .danger,
        primaryAction: RecordingBarCompanionAction? = nil,
        secondaryAction: RecordingBarCompanionAction? = nil,
        autoDismissAfter: TimeInterval? = nil,
        displayState: RecordingBarVisualState = .failed
    ) {
        FloatingRecordingBar.shared.showCompanion(
            RecordingBarCompanion(
                title: title,
                message: message,
                tone: tone,
                primaryAction: primaryAction,
                secondaryAction: secondaryAction,
                autoDismissAfter: autoDismissAfter
            ),
            displayState: displayState
        )
    }
    
    private func formatElapsedMs(since startedAt: CFAbsoluteTime) -> String {
        formatElapsedMs(elapsedMs(since: startedAt))
    }

    private func formatElapsedMs(_ elapsedMs: Double) -> String {
        String(format: "%.1f", elapsedMs)
    }

    private func elapsedMs(since startedAt: CFAbsoluteTime) -> Double {
        (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
    }

    private func recordingDurationSeconds(sampleBytes: Int, sampleRate: Int = 16_000, channels: Int = 1) -> Double {
        guard sampleRate > 0, channels > 0 else { return 0 }
        return Double(sampleBytes) / Double(sampleRate * channels * 2)
    }

    private func audioDurationSeconds(_ audio: AudioData) -> String {
        String(format: "%.1f", recordingDurationSeconds(sampleBytes: audio.samples.count, sampleRate: audio.sampleRate, channels: audio.channels))
    }

    private func logTranscriptionFailure(error: STTTranscriptionError, audio: AudioData?) {
        let config = (try? ConfigLoader.load()) ?? .default
        let modelID = config.stt.local.preferredModel ?? config.stt.model ?? "unknown"
        let guidance = LocalSTTModelCatalog.recordingGuidance(for: modelID)
        let message = "STT failure classified. model=\(modelID) mode=\(config.stt.mode.rawValue) audio_seconds=\(audio.map(audioDurationSeconds) ?? "unknown") audio_bytes=\(audio?.samples.count ?? 0) warning_seconds=\(guidance.warningSeconds) recommended_max_seconds=\(guidance.recommendedMaximumSeconds) likely_long_audio=\(error.isLikelyLongAudioLimit) error=\(error.localizedDescription)"
        logger.error("\(message, privacy: .public)")
        PerformanceLog.record(category: "RecordingSession", message: message)
    }
    
}
