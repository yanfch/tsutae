@preconcurrency import AVFoundation
import Foundation

/// Minimal microphone recorder for one-shot transcription.
///
/// It records microphone input into 16 kHz mono 16-bit PCM, which is the
/// internal format expected by STT/VAD components.
public final class AudioInput: @unchecked Sendable {
    public typealias FrameObserver = @Sendable (AudioFrame) -> Void
    
    public static let shared = AudioInput()
    
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var recordedSamples = Data()
    private var isRecording = false
    private var frameObserver: FrameObserver?
    private var nextFrameIndex = 0
    
    public init() {}
    
    public var recording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRecording
    }
    
    public var recordedByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedSamples.count
    }

    public func setFrameObserver(_ observer: FrameObserver?) {
        lock.lock()
        frameObserver = observer
        lock.unlock()
    }
    
    public func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    public func startRecording() async throws {
        guard await requestPermission() else {
            throw AudioInputError.microphonePermissionDenied
        }
        
        try startRecordingAfterPermission()
    }
    
    private func startRecordingAfterPermission() throws {
        lock.lock()
        defer { lock.unlock() }
        
        if isRecording {
            return
        }
        
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        guard inputFormat.channelCount > 0 else {
            throw AudioInputError.noInputDevice
        }
        
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: true
            ),
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else {
            throw AudioInputError.formatConversionUnavailable
        }
        
        recordedSamples.removeAll(keepingCapacity: true)
        nextFrameIndex = 0
        self.engine = engine
        self.converter = converter
        self.outputFormat = outputFormat
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.appendConvertedSamples(from: buffer)
        }
        
        engine.prepare()
        do {
            try engine.start()
            isRecording = true
        } catch {
            inputNode.removeTap(onBus: 0)
            self.engine = nil
            self.converter = nil
            self.outputFormat = nil
            throw error
        }
    }
    
    public func stopRecording() throws -> AudioData {
        lock.lock()
        defer { lock.unlock() }
        
        guard isRecording, let engine else {
            throw AudioInputError.notRecording
        }
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        
        let samples = recordedSamples
        self.engine = nil
        self.converter = nil
        self.outputFormat = nil
        self.frameObserver = nil
        self.nextFrameIndex = 0
        self.recordedSamples = Data()
        self.isRecording = false
        
        guard samples.count >= 9_600 else {
            throw AudioInputError.recordingTooShort
        }
        
        return AudioData(samples: samples, sampleRate: 16_000, channels: 1)
    }
    
    public func cancelRecording() {
        lock.lock()
        defer { lock.unlock() }
        
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        outputFormat = nil
        frameObserver = nil
        nextFrameIndex = 0
        recordedSamples = Data()
        isRecording = false
    }
    
    private func appendConvertedSamples(from inputBuffer: AVAudioPCMBuffer) {
        lock.lock()
        guard
            isRecording,
            let converter,
            let outputFormat
        else {
            lock.unlock()
            return
        }
        lock.unlock()
        
        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(max(1, ceil(Double(inputBuffer.frameLength) * ratio)))
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
            return
        }
        
        let inputProvider = ConverterInputProvider(buffer: inputBuffer)
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, status in
            inputProvider.provide(status: status)
        }
        
        guard conversionError == nil, let int16Data = outputBuffer.int16PCMData else {
            return
        }
        
        lock.lock()
        let frameIndex = nextFrameIndex
        nextFrameIndex += 1
        recordedSamples.append(int16Data)
        let observer = frameObserver
        lock.unlock()

        observer?(AudioFrame(samples: int16Data, frameIndex: frameIndex))
    }
}

private final class ConverterInputProvider: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var didProvideInput = false
    
    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
    
    func provide(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if didProvideInput {
            status.pointee = .noDataNow
            return nil
        }
        
        didProvideInput = true
        status.pointee = .haveData
        return buffer
    }
}

public enum AudioInputError: LocalizedError, Sendable {
    case microphonePermissionDenied
    case noInputDevice
    case formatConversionUnavailable
    case notRecording
    case recordingTooShort
    
    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission denied"
        case .noInputDevice:
            return "No microphone input device is available"
        case .formatConversionUnavailable:
            return "Unable to convert microphone input to 16 kHz mono PCM"
        case .notRecording:
            return "Audio input is not recording"
        case .recordingTooShort:
            return "Recording is too short for transcription"
        }
    }
}

private extension AVAudioPCMBuffer {
    var int16PCMData: Data? {
        let audioBuffer = audioBufferList.pointee.mBuffers
        guard let bytes = audioBuffer.mData else {
            return nil
        }
        
        return Data(bytes: bytes, count: Int(audioBuffer.mDataByteSize))
    }
}
