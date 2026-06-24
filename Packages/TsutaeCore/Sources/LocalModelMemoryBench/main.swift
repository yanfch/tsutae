import Darwin
import Foundation
import TsutaeCore

struct STTMemoryBenchResult: Codable {
    let kind: String
    let modelID: String
    let displayName: String
    let downloaded: Bool
    let downloadedBytes: Int64
    let baseline: MemorySample
    let loaded: MemorySample
    let inferred: MemorySample
    let unloaded: MemorySample
    let deltaLoadedMB: Double
    let deltaInferredMB: Double
    let loadElapsedMs: Double
    let inferElapsedMs: Double
    let transcriptChars: Int
    let error: String?
}

struct MemorySample: Codable {
    let rssBytes: UInt64
    let physicalFootprintBytes: UInt64?

    var primaryBytes: UInt64 {
        physicalFootprintBytes ?? rssBytes
    }
}

@main
enum LocalModelMemoryBench {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            let options = try BenchOptions(arguments: arguments)
            switch options.mode {
            case .allSTT:
                try await runAllSTT(
                    outputPath: options.outputPath,
                    includeMissing: options.includeMissing,
                    runInference: options.runInference,
                    timeoutSeconds: options.timeoutSeconds
                )
            case .model(let modelID):
                let result = await measureSTTModel(modelID: modelID, runInference: options.runInference)
                try printJSON(result)
                if result.error != nil {
                    Foundation.exit(2)
                }
            case .help:
                printHelp()
            }
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func runAllSTT(
        outputPath: String?,
        includeMissing: Bool,
        runInference: Bool,
        timeoutSeconds: TimeInterval
    ) async throws {
        let executablePath = CommandLine.arguments[0]
        let descriptors = LocalSTTModelCatalog.all.filter { descriptor in
            includeMissing || LocalSTTModelCatalog.isDownloaded(id: descriptor.id)
        }

        guard descriptors.isEmpty == false else {
            print("No downloaded STT models found. Use --include-missing to list skipped models.")
            return
        }

        var results: [STTMemoryBenchResult] = []
        for descriptor in descriptors {
            let result = try runChild(
                executablePath: executablePath,
                modelID: descriptor.id,
                runInference: runInference,
                timeoutSeconds: timeoutSeconds
            )
            results.append(result)
            printTableRow(result)
        }

        if let outputPath {
            try writeJSONL(results, to: outputPath)
            print("Wrote \(results.count) rows to \(outputPath)")
        }
    }

    private static func measureSTTModel(modelID: String, runInference: Bool) async -> STTMemoryBenchResult {
        let descriptor = LocalSTTModelCatalog.descriptor(id: modelID)
        let displayName = descriptor?.displayName ?? modelID
        let downloaded = LocalSTTModelCatalog.isDownloaded(id: modelID)
        let downloadedBytes = LocalSTTModelCatalog.downloadedByteCount(id: modelID)
        let baseline = MemoryMeter.sample()

        guard downloaded else {
            return STTMemoryBenchResult(
                kind: "stt",
                modelID: modelID,
                displayName: displayName,
                downloaded: false,
                downloadedBytes: downloadedBytes,
                baseline: baseline,
                loaded: baseline,
                inferred: baseline,
                unloaded: baseline,
                deltaLoadedMB: 0,
                deltaInferredMB: 0,
                loadElapsedMs: 0,
                inferElapsedMs: 0,
                transcriptChars: 0,
                error: "model_not_downloaded"
            )
        }

        let engine = FluidAudioSTT(modelID: modelID, languageHint: languageHint(for: modelID))
        do {
            let loadStartedAt = Date()
            try await engine.load()
            let loadElapsedMs = elapsedMs(since: loadStartedAt)
            let loaded = MemoryMeter.sample()

            var inferred = loaded
            var inferElapsedMs = 0.0
            var transcriptChars = 0
            if runInference {
                let inferStartedAt = Date()
                let transcript = try await engine.transcribe(silentAudio(seconds: 1), language: languageHint(for: modelID))
                inferElapsedMs = elapsedMs(since: inferStartedAt)
                transcriptChars = transcript.text.count
                inferred = MemoryMeter.sample()
            }

            await FluidAudioSTT.unloadAllModels()
            try? await Task.sleep(nanoseconds: 700_000_000)
            let unloaded = MemoryMeter.sample()

            return STTMemoryBenchResult(
                kind: "stt",
                modelID: modelID,
                displayName: displayName,
                downloaded: true,
                downloadedBytes: downloadedBytes,
                baseline: baseline,
                loaded: loaded,
                inferred: inferred,
                unloaded: unloaded,
                deltaLoadedMB: mb(loaded.primaryBytes, minus: baseline.primaryBytes),
                deltaInferredMB: mb(inferred.primaryBytes, minus: baseline.primaryBytes),
                loadElapsedMs: loadElapsedMs,
                inferElapsedMs: inferElapsedMs,
                transcriptChars: transcriptChars,
                error: nil
            )
        } catch {
            let current = MemoryMeter.sample()
            await FluidAudioSTT.unloadAllModels()
            return STTMemoryBenchResult(
                kind: "stt",
                modelID: modelID,
                displayName: displayName,
                downloaded: true,
                downloadedBytes: downloadedBytes,
                baseline: baseline,
                loaded: current,
                inferred: current,
                unloaded: MemoryMeter.sample(),
                deltaLoadedMB: mb(current.primaryBytes, minus: baseline.primaryBytes),
                deltaInferredMB: mb(current.primaryBytes, minus: baseline.primaryBytes),
                loadElapsedMs: 0,
                inferElapsedMs: 0,
                transcriptChars: 0,
                error: error.localizedDescription
            )
        }
    }

    private static func runChild(
        executablePath: String,
        modelID: String,
        runInference: Bool,
        timeoutSeconds: TimeInterval
    ) throws -> STTMemoryBenchResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["--model", modelID, "--json"] + (runInference ? [] : ["--skip-inference"])

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tsutae-memory-bench-\(UUID().uuidString).out")
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tsutae-memory-bench-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        try process.run()
        if finished.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 5)
            return timeoutResult(modelID: modelID, timeoutSeconds: timeoutSeconds)
        }

        try? outputHandle.close()
        try? errorHandle.close()
        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        if process.terminationStatus != 0 && jsonPayload(from: data) == nil {
            let errorData = (try? Data(contentsOf: errorURL)) ?? Data()
            let errorText = String(data: errorData, encoding: .utf8) ?? "child process failed"
            throw BenchError.childFailed(modelID, errorText)
        }

        guard let payload = jsonPayload(from: data) else {
            throw BenchError.childFailed(modelID, "missing JSON result")
        }
        return try JSONDecoder().decode(STTMemoryBenchResult.self, from: payload)
    }

    private static func jsonPayload(from data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return text
            .split(separator: "\n")
            .last(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("{") })
            .flatMap { String($0).data(using: .utf8) }
    }

    private static func timeoutResult(modelID: String, timeoutSeconds: TimeInterval) -> STTMemoryBenchResult {
        let descriptor = LocalSTTModelCatalog.descriptor(id: modelID)
        let sample = MemoryMeter.sample()
        return STTMemoryBenchResult(
            kind: "stt",
            modelID: modelID,
            displayName: descriptor?.displayName ?? modelID,
            downloaded: LocalSTTModelCatalog.isDownloaded(id: modelID),
            downloadedBytes: LocalSTTModelCatalog.downloadedByteCount(id: modelID),
            baseline: sample,
            loaded: sample,
            inferred: sample,
            unloaded: sample,
            deltaLoadedMB: 0,
            deltaInferredMB: 0,
            loadElapsedMs: timeoutSeconds * 1000,
            inferElapsedMs: 0,
            transcriptChars: 0,
            error: "timeout_after_\(Int(timeoutSeconds))s"
        )
    }

    private static func printTableRow(_ result: STTMemoryBenchResult) {
        let status = result.error == nil ? "ok" : "failed"
        print(
            [
                result.modelID.padding(toLength: 24, withPad: " ", startingAt: 0),
                status.padding(toLength: 8, withPad: " ", startingAt: 0),
                "disk=\(formatMB(result.downloadedBytes))",
                "load+\(formatMB(result.deltaLoadedMB))",
                "infer+\(formatMB(result.deltaInferredMB))",
                "load_ms=\(formatMs(result.loadElapsedMs))",
                "infer_ms=\(formatMs(result.inferElapsedMs))",
            ].joined(separator: "  ")
        )
        fflush(stdout)
    }

    private static func writeJSONL(_ results: [STTMemoryBenchResult], to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var lines = Data()
        for result in results {
            lines.append(try encoder.encode(result))
            lines.append(0x0A)
        }
        try lines.write(to: url, options: .atomic)
        fflush(stdout)
    }

    private static func printJSON(_ result: STTMemoryBenchResult) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(result)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    private static func printHelp() {
        print(
            """
            Usage:
              LocalModelMemoryBench --all-stt [--output path] [--include-missing] [--skip-inference] [--timeout-seconds n]
              LocalModelMemoryBench --model <model-id> [--skip-inference]

            Measures STT local model memory in a fresh child process per model.
            Primary memory is physical footprint when available, otherwise RSS.
            """
        )
    }

    private static func silentAudio(seconds: Int) -> AudioData {
        AudioData(samples: Data(count: 16_000 * 2 * seconds), sampleRate: 16_000, channels: 1, container: .pcm16)
    }

    private static func languageHint(for modelID: String) -> String? {
        switch modelID {
        case "paraformer-large-zh", "parakeet-ctc-zh-cn":
            return "zh"
        case "parakeet-tdt-v3":
            return "en"
        default:
            return nil
        }
    }

    private static func elapsedMs(since startedAt: Date) -> Double {
        Date().timeIntervalSince(startedAt) * 1000
    }

    private static func mb(_ bytes: UInt64, minus base: UInt64 = 0) -> Double {
        Double(bytes >= base ? bytes - base : 0) / 1_048_576.0
    }

    private static func formatMB(_ bytes: Int64) -> String {
        formatMB(Double(bytes) / 1_048_576.0)
    }

    private static func formatMB(_ value: Double) -> String {
        String(format: "%.1fMB", value)
    }

    private static func formatMs(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}

private struct BenchOptions {
    enum Mode {
        case allSTT
        case model(String)
        case help
    }

    let mode: Mode
    let outputPath: String?
    let includeMissing: Bool
    let runInference: Bool
    let timeoutSeconds: TimeInterval

    init(arguments: [String]) throws {
        var mode: Mode = .allSTT
        var outputPath: String?
        var includeMissing = false
        var runInference = true
        var timeoutSeconds: TimeInterval = 180

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--all-stt":
                mode = .allSTT
            case "--model":
                index += 1
                guard index < arguments.count else { throw BenchError.missingValue(argument) }
                mode = .model(arguments[index])
            case "--output":
                index += 1
                guard index < arguments.count else { throw BenchError.missingValue(argument) }
                outputPath = arguments[index]
            case "--include-missing":
                includeMissing = true
            case "--skip-inference":
                runInference = false
            case "--timeout-seconds":
                index += 1
                guard index < arguments.count else { throw BenchError.missingValue(argument) }
                guard let parsed = TimeInterval(arguments[index]), parsed > 0 else {
                    throw BenchError.invalidValue(argument, arguments[index])
                }
                timeoutSeconds = parsed
            case "--json":
                break
            case "--":
                break
            case "--help", "-h":
                mode = .help
            default:
                throw BenchError.unknownArgument(argument)
            }
            index += 1
        }

        self.mode = mode
        self.outputPath = outputPath
        self.includeMissing = includeMissing
        self.runInference = runInference
        self.timeoutSeconds = timeoutSeconds
    }
}

private enum BenchError: LocalizedError {
    case unknownArgument(String)
    case missingValue(String)
    case invalidValue(String, String)
    case childFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        case .missingValue(let argument):
            return "Missing value for \(argument)"
        case .invalidValue(let argument, let value):
            return "Invalid value for \(argument): \(value)"
        case .childFailed(let modelID, let errorText):
            return "Benchmark child failed for \(modelID): \(errorText)"
        }
    }
}

private enum MemoryMeter {
    static func sample() -> MemorySample {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }

        if result == KERN_SUCCESS {
            return MemorySample(
                rssBytes: UInt64(info.resident_size),
                physicalFootprintBytes: UInt64(info.phys_footprint)
            )
        }

        return MemorySample(rssBytes: rssFromProcessInfo(), physicalFootprintBytes: nil)
    }

    private static func rssFromProcessInfo() -> UInt64 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "rss=", "-p", "\(ProcessInfo.processInfo.processIdentifier)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return UInt64(text ?? "").map { $0 * 1024 } ?? 0
        } catch {
            return 0
        }
    }
}
