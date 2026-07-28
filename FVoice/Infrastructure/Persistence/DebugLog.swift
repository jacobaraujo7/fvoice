import Foundation

/// Appends diagnostic lines to ~/.fvoice/debug/fvoice.log (and NSLog).
enum DebugLog {
    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".fvoice/debug", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("fvoice.log")
    }()

    static func log(_ message: String) {
        NSLog("FVoice: %@", message)
        let line = "\(Date()) \(message)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
