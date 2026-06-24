import AppKit
import Combine
import Foundation
import OSLog
import TsutaeCore

private struct ProcessedTranscriptOutcome {
    let text: String
    let postProcessing: TranscriptPostProcessingResult?
}

private struct TranscriptOutputOutcome {
    let method: String
    let copied: Bool
    let elapsedMs: Double
    let error: String?
    let targetApplication: FocusedApplicationSnapshot?
    let insertionApplication: FocusedApplicationSnapshot?
}

private enum TranscriptOutputError: LocalizedError {
    case clipboardWriteFailed

    var errorDescription: String? {
        switch self {
        case .clipboardWriteFailed:
            return "Could not write transcript to the clipboard"
        }
    }
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
    
    private var hasShownLongRecordingWarning = false
    private var activeWarmupTask: Task<Void, Never>?
    private var activeTranscriptionTask: Task<Void, Never>?
    private var activeVADObservation: VADObservationSession?
    private var activeOperationID = UUID()
    private var activeTargetApplication: FocusedApplicationSnapshot?
    private var pendingEscapeCancelDeadline: Date?

    private static let escapeCancelConfirmationWindow: TimeInterval = 2.0
    private static let meaningfulAudioSeconds: Double = 0.8
    
    private init() {}
    
    func toggle() {
        PerformanceLog.record(
            category: "RecordingSession",
            message: "Recording toggle requested. isRecording=\(isRecording) audioRecording=\(audioInput.recording) isBusy=\(isBusy)"
        )
        if isRecording || audioInput.recording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }
    
    func cancel() {
        logger.info("Cancelling current recording/transcription session")
        pendingEscapeCancelDeadline = nil
        activeOperationID = UUID()
        activeWarmupTask?.cancel()
        activeWarmupTask = nil
        activeTranscriptionTask?.cancel()
        activeTranscriptionTask = nil
        finishVADObservation(reason: "cancelled")
        audioInput.cancelRecording()
        FloatingRecordingBar.shared.hide()
        isBusy = false
        isRecording = false
        activeTargetApplication = nil
        hasShownLongRecordingWarning = false
        liveRecordedBytes = 0
        statusText = "cancelled"
    }

    func requestEscapeCancel() {
        guard isBusy || isRecording || audioInput.recording else {
            return
        }

        if shouldCancelImmediatelyForEscape {
            cancel()
            return
        }

        let now = Date()
        if let pendingEscapeCancelDeadline, now <= pendingEscapeCancelDeadline {
            cancel()
            return
        }

        pendingEscapeCancelDeadline = now.addingTimeInterval(Self.escapeCancelConfirmationWindow)
        presentEscapeCancelConfirmation()
    }
    
    private func startRecording() {
        guard !isBusy else {
            return
        }
        
        let startRequestedAt = CFAbsoluteTimeGetCurrent()
        isBusy = true
        statusText = "requesting microphone permission"
        let operationID = UUID()
        activeOperationID = operationID
        PerformanceLog.record(
            category: "RecordingSession",
            message: "Recording start requested. operation=\(operationID.uuidString)"
        )
        pendingEscapeCancelDeadline = nil
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
                let configLoadStartedAt = CFAbsoluteTimeGetCurrent()
                let config = (try? ConfigLoader.load()) ?? .default
                PerformanceLog.record(
                    category: "RecordingSession",
                    message: "Recording config loaded. operation=\(operationID.uuidString) elapsed_ms=\(self.formatElapsedMs(since: configLoadStartedAt)) total_elapsed_ms=\(self.formatElapsedMs(since: startRequestedAt))"
                )

                let warmupCheckStartedAt = CFAbsoluteTimeGetCurrent()
                let requiresWarmup = await LocalSTTResidencyCoordinator.shared.requiresWarmupGate(config: config)
                PerformanceLog.record(
                    category: "RecordingSession",
                    message: "Recording warmup gate checked. operation=\(operationID.uuidString) required=\(requiresWarmup) elapsed_ms=\(self.formatElapsedMs(since: warmupCheckStartedAt)) total_elapsed_ms=\(self.formatElapsedMs(since: startRequestedAt))"
                )
                if requiresWarmup {
                    self.statusText = "warming local model"
                    FloatingRecordingBar.shared.show(state: .idle)
                    self.presentCompanion(
                        title: L10n.RecordingCompanion.preparingLocalModelTitle,
                        message: L10n.RecordingCompanion.preparingLocalModelMessage,
                        tone: .info,
                        displayState: .waiting
                    )
                    let warmupStartedAt = CFAbsoluteTimeGetCurrent()
                    try await LocalSTTResidencyCoordinator.shared.waitUntilLocalModelReady(config: config)
                    PerformanceLog.record(
                        category: "RecordingSession",
                        message: "Recording warmup gate finished. operation=\(operationID.uuidString) elapsed_ms=\(self.formatElapsedMs(since: warmupStartedAt)) total_elapsed_ms=\(self.formatElapsedMs(since: startRequestedAt))"
                    )
                    try Task.checkCancellation()
                    guard self.activeOperationID == operationID else { return }
                }
                
                try Paths.ensureDirectories()
                self.startVADObservation(config: config)
                PerformanceLog.record(
                    category: "RecordingSession",
                    message: "Recording VAD observation attached. operation=\(operationID.uuidString) total_elapsed_ms=\(self.formatElapsedMs(since: startRequestedAt))"
                )
                let audioStartStartedAt = CFAbsoluteTimeGetCurrent()
                try await audioInput.startRecording()
                PerformanceLog.record(
                    category: "RecordingSession",
                    message: "Recording audio input started. operation=\(operationID.uuidString) elapsed_ms=\(self.formatElapsedMs(since: audioStartStartedAt)) total_elapsed_ms=\(self.formatElapsedMs(since: startRequestedAt))"
                )
                try Task.checkCancellation()
                guard self.activeOperationID == operationID else {
                    self.finishVADObservation(reason: "cancelled_before_capture")
                    audioInput.cancelRecording()
                    return
                }
                self.lastError = nil
                self.hasShownLongRecordingWarning = false
                self.isRecording = true
                self.statusText = "recording"
                self.startRecordingProgressPolling()
                FloatingRecordingBar.shared.show(state: .listening)
                PerformanceLog.record(
                    category: "RecordingSession",
                    message: "Recording capsule show requested. operation=\(operationID.uuidString) total_elapsed_ms=\(self.formatElapsedMs(since: startRequestedAt))"
                )
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
                self.finishVADObservation(reason: "start_failed")
                self.logger.error("Failed to start recording: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private func stopAndTranscribe() {
        let audio: AudioData
        let stopStartedAt = CFAbsoluteTimeGetCurrent()
        do {
            audio = try audioInput.stopRecording()
            finishVADObservation(reason: "stopped")
            let stopElapsedMs = formatElapsedMs(since: stopStartedAt)
            isRecording = false
            liveRecordedBytes = 0
            pendingEscapeCancelDeadline = nil
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
            pendingEscapeCancelDeadline = nil
            statusText = "stop failed"
            lastError = error.localizedDescription
            presentStopError(error)
            finishVADObservation(reason: "stop_failed")
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

                do {
                    let output = try self.outputTranscript(
                        finalText,
                        recordingStartApplication: recordingStartApplication
                    )
                    guard !Task.isCancelled, self.activeOperationID == operationID else {
                        self.logger.info("Cancelled session after output completed")
                        return
                    }
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
                            targetApplication: output.targetApplication,
                            recordingStartApplication: recordingStartApplication,
                            insertionApplication: output.insertionApplication,
                            insertion: ASRSampleLog.InsertionSnapshot(
                                method: output.method,
                                succeeded: true,
                                elapsedMs: output.elapsedMs,
                                error: output.error
                            ),
                            endToEndElapsedMs: endToEndElapsedMs
                        )
                    )
                    self.activeTargetApplication = nil
                    let outputMessage = "Transcription output completed. raw_chars=\(transcript.text.count) chars=\(finalText.count) target_app=\(output.targetApplication?.bundleIdentifier ?? "") output_method=\(output.method) copied=\(output.copied) output_elapsed_ms=\(self.formatElapsedMs(output.elapsedMs)) total_elapsed_ms=\(self.formatElapsedMs(endToEndElapsedMs)) error=\(output.error ?? "")"
                    self.logger.info("\(outputMessage, privacy: .public)")
                    PerformanceLog.record(category: "RecordingSession", message: outputMessage)
                    try await self.finishSuccessfulOutput(copied: output.copied, operationID: operationID)
                } catch {
                    guard !Task.isCancelled, self.activeOperationID == operationID else {
                        self.logger.info("Cancelled session after output failed")
                        return
                    }
                    self.activeTargetApplication = nil
                    self.lastError = error.localizedDescription
                    self.statusText = "output failed"
                    self.presentOutputFailure(error)
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

    private func startVADObservation(config: Config) {
        var observeConfig = config
        observeConfig.vad.engine = "fluid_audio_vad"
        let session = VADObservationSession(sessionID: activeOperationID, config: observeConfig)
        activeVADObservation = session
        audioInput.setFrameObserver { frame in
            Task(priority: .utility) {
                await session.observe(frame)
            }
        }
    }

    private func finishVADObservation(reason: String) {
        audioInput.setFrameObserver(nil)
        guard let session = activeVADObservation else { return }
        activeVADObservation = nil
        Task(priority: .utility) {
            await session.finish(reason: reason)
        }
    }

    private var shouldCancelImmediatelyForEscape: Bool {
        let bytes: Int
        if isRecording || audioInput.recording {
            bytes = max(liveRecordedBytes, audioInput.recordedByteCount)
        } else {
            bytes = max(lastRecordingBytes, liveRecordedBytes)
        }
        return recordingDurationSeconds(sampleBytes: bytes) < Self.meaningfulAudioSeconds
    }

    private func presentEscapeCancelConfirmation() {
        let displayState: RecordingBarVisualState = isRecording || audioInput.recording ? .listening : .thinking
        presentCompanion(
            title: L10n.RecordingCompanion.cancelConfirmationTitle,
            message: L10n.RecordingCompanion.cancelConfirmationMessage,
            tone: .warning,
            primaryAction: .init(title: L10n.RecordingCompanion.cancelRecording, style: .primary) {
                self.cancel()
            },
            secondaryAction: .init(title: L10n.RecordingCompanion.keepRecording, style: .secondary) {
                self.pendingEscapeCancelDeadline = nil
                FloatingRecordingBar.shared.clearCompanion(displayState: displayState)
            },
            displayState: .warning
        )

        let operationID = activeOperationID
        Task {
            try? await Task.sleep(for: .seconds(Self.escapeCancelConfirmationWindow))
            guard self.activeOperationID == operationID else { return }
            guard let pendingEscapeCancelDeadline = self.pendingEscapeCancelDeadline else { return }
            guard Date() >= pendingEscapeCancelDeadline else { return }
            self.pendingEscapeCancelDeadline = nil
            guard self.isBusy || self.isRecording || self.audioInput.recording else { return }
            FloatingRecordingBar.shared.clearCompanion(displayState: displayState)
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

                do {
                    let output = try self.outputTranscript(
                        finalText,
                        recordingStartApplication: recordingStartApplication
                    )
                    guard !Task.isCancelled, self.activeOperationID == operationID else { return }
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
                            targetApplication: output.targetApplication,
                            recordingStartApplication: recordingStartApplication,
                            insertionApplication: output.insertionApplication,
                            insertion: ASRSampleLog.InsertionSnapshot(
                                method: output.method,
                                succeeded: true,
                                elapsedMs: output.elapsedMs,
                                error: output.error
                            ),
                            endToEndElapsedMs: endToEndElapsedMs
                        )
                    )
                    self.activeTargetApplication = nil
                    let outputMessage = "Remote retry transcription output completed. raw_chars=\(transcript.text.count) chars=\(finalText.count) target_app=\(output.targetApplication?.bundleIdentifier ?? "") output_method=\(output.method) copied=\(output.copied) output_elapsed_ms=\(self.formatElapsedMs(output.elapsedMs)) total_elapsed_ms=\(self.formatElapsedMs(endToEndElapsedMs)) error=\(output.error ?? "")"
                    self.logger.info("\(outputMessage, privacy: .public)")
                    PerformanceLog.record(category: "RecordingSession", message: outputMessage)
                    try await self.finishSuccessfulOutput(copied: output.copied, operationID: operationID)
                } catch {
                    guard !Task.isCancelled, self.activeOperationID == operationID else { return }
                    self.activeTargetApplication = nil
                    self.lastError = error.localizedDescription
                    self.statusText = "output failed"
                    self.presentOutputFailure(error)
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
    
    private func outputTranscript(
        _ text: String,
        recordingStartApplication: FocusedApplicationSnapshot?
    ) throws -> TranscriptOutputOutcome {
        let outputStartedAt = CFAbsoluteTimeGetCurrent()
        let insertionApplication = FocusedTextInjector.focusedApplicationSnapshot(
            excludingBundleIdentifier: Bundle.main.bundleIdentifier
        )
        let targetApplication = insertionApplication ?? recordingStartApplication

        if defaultRecordingAction == "copyToClipboard" {
            try copyTranscriptToClipboard(text)
            return TranscriptOutputOutcome(
                method: "clipboard_default",
                copied: true,
                elapsedMs: elapsedMs(since: outputStartedAt),
                error: nil,
                targetApplication: targetApplication,
                insertionApplication: insertionApplication
            )
        }

        do {
            try FocusedTextInjector.inject(text)
            return TranscriptOutputOutcome(
                method: "focused_app",
                copied: false,
                elapsedMs: elapsedMs(since: outputStartedAt),
                error: nil,
                targetApplication: targetApplication,
                insertionApplication: insertionApplication
            )
        } catch {
            try copyTranscriptToClipboard(text)
            return TranscriptOutputOutcome(
                method: "clipboard_fallback",
                copied: true,
                elapsedMs: elapsedMs(since: outputStartedAt),
                error: error.localizedDescription,
                targetApplication: targetApplication,
                insertionApplication: insertionApplication
            )
        }
    }

    private var defaultRecordingAction: String {
        UserDefaults.standard.string(forKey: "settings.defaultAction") ?? "injectFocusedApp"
    }

    private func copyTranscriptToClipboard(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw TranscriptOutputError.clipboardWriteFailed
        }
    }

    private func finishSuccessfulOutput(copied: Bool, operationID: UUID) async throws {
        statusText = copied ? "copied" : "done"
        FloatingRecordingBar.shared.showCompletion(copied: copied)
        let doneHoldStartedAt = CFAbsoluteTimeGetCurrent()
        try await Task.sleep(for: .milliseconds(150))
        let doneHoldMessage = "RecordingSession output completion hold finished. copied=\(copied) elapsed_ms=\(formatElapsedMs(since: doneHoldStartedAt))"
        logger.info("\(doneHoldMessage, privacy: .public)")
        PerformanceLog.record(category: "RecordingSession", message: doneHoldMessage)
        guard !Task.isCancelled, activeOperationID == operationID else {
            logger.info("Cancelled session during output completion hold")
            return
        }
        FloatingRecordingBar.shared.hide(animated: true)
    }

    private func presentOutputFailure(_ error: Error) {
        presentCompanion(
            title: L10n.RecordingCompanion.couldntFinishRecordingTitle,
            message: error.localizedDescription,
            primaryAction: .init(title: L10n.Common.dismiss, style: .primary) {
                FloatingRecordingBar.shared.dismissCompanion()
            }
        )
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
