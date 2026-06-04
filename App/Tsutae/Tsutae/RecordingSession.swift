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
    
    private init() {}
    
    func toggle() {
        if isRecording || audioInput.recording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }
    
    func cancel() {
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
                FloatingRecordingBar.shared.hide()
                notify(title: "tsutae 录音失败", body: error.localizedDescription)
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
            FloatingRecordingBar.shared.hide()
            notify(title: "tsutae 停止录音失败", body: error.localizedDescription)
            logger.error("Failed to stop recording: \(error.localizedDescription, privacy: .public)")
            return
        }
        
        Task {
            do {
                let transcript = try await stt.transcribe(audio, language: nil)
                lastTranscript = transcript.text
                lastError = nil
                statusText = "done"
                isBusy = false
                
                // 显示 Done 状态
                FloatingRecordingBar.shared.update(state: .idle)
                
                // 延迟一会再关闭，便于观察 Done 状态
                try? await Task.sleep(for: .milliseconds(1500))
                
                do {
                    try FocusedTextInjector.inject(transcript.text)
                    FloatingRecordingBar.shared.hide()
                    notify(title: "tsutae 已注入文本", body: transcript.text)
                    logger.info("Transcription injected. chars=\(transcript.text.count, privacy: .public)")
                } catch {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript.text, forType: .string)
                    lastError = "Inject failed, copied to clipboard: \(error.localizedDescription)"
                    statusText = "inject failed"
                    isBusy = false
                    FloatingRecordingBar.shared.hide()
                    notify(title: "tsutae 注入失败，已复制", body: error.localizedDescription)
                    logger.error("Injection failed: \(error.localizedDescription, privacy: .public)")
                }
            } catch {
                lastError = error.localizedDescription
                statusText = "transcription failed"
                FloatingRecordingBar.shared.hide()
                notify(title: "tsutae 转写失败", body: error.localizedDescription)
                logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            }
            
            isBusy = false
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
