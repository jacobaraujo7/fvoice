import Foundation

/// Runs a user-provided shell script instead of inserting text. The
/// transcription is exported as $FVOICE_TEXT and {{texto}} occurrences in the
/// script are replaced by "$FVOICE_TEXT" (safe against quoting/injection).
final class HookTextInserter: TextInserter {
    private let scriptProvider: () -> String

    init(scriptProvider: @escaping () -> String) {
        self.scriptProvider = scriptProvider
    }

    func insert(_ text: String) {
        let template = scriptProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else {
            DebugLog.log("hook: empty script, nothing to run")
            return
        }
        let script = template.replacingOccurrences(of: "{{texto}}", with: "\"$FVOICE_TEXT\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", script]
        var env = ProcessInfo.processInfo.environment
        env["FVOICE_TEXT"] = text
        process.environment = env

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { proc in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let log = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DebugLog.log("hook: exit \(proc.terminationStatus)\(log.isEmpty ? "" : " output: \(log)")")
        }

        do {
            try process.run()
            DebugLog.log("hook: running script (\(text.count) chars)")
        } catch {
            DebugLog.log("hook: failed to launch: \(error)")
        }
    }
}
