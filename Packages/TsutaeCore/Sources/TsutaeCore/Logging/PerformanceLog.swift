import Foundation

public enum PerformanceLog {
    public static var fileURL: URL {
        Paths.logs.appendingPathComponent("stt-perf.log")
    }
    
    public static func record(category: String, message: String) {
        Task {
            await Writer.shared.append(category: category, message: message)
        }
    }
    
    private actor Writer {
        static let shared = Writer()
        
        private let formatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
        
        func append(category: String, message: String) {
            do {
                try Paths.ensureDirectories()
                let line = "[\(formatter.string(from: Date()))] [\(category)] \(message)\n"
                let data = Data(line.utf8)
                let fileURL = PerformanceLog.fileURL
                if FileManager.default.fileExists(atPath: fileURL.path) == false {
                    try data.write(to: fileURL, options: .atomic)
                    return
                }
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Keep perf logging best-effort only.
            }
        }
    }
}
