import Foundation

public enum CLIBinary {
    public static func resolve(_ name: String) -> URL? {
        let expanded = (name as NSString).expandingTildeInPath
        if name.contains("/") || name.hasPrefix("~") {
            let url = URL(fileURLWithPath: expanded)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        var dirs: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            dirs.append(contentsOf: path.split(separator: ":").map(String.init))
        }
        dirs.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin"),
            "/Applications/Codex.app/Contents/Resources",
        ])
        var seen = Set<String>()
        for dir in dirs where seen.insert(dir).inserted {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    public static func childEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extras = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:/Applications/Codex.app/Contents/Resources"
        let path = env["PATH"] ?? "/usr/bin:/bin"
        if !path.contains("/opt/homebrew/bin")
            || !path.contains(".local/bin")
            || !path.contains("Codex.app/Contents/Resources") {
            env["PATH"] = extras + ":" + path
        }
        return env
    }
}

public final class CLIProcess: @unchecked Sendable {
    private var proc: Process?

    public init() {}

    public func cancel() {
        proc?.terminate()
        proc = nil
    }

    public func run(
        executable: URL,
        arguments: [String],
        cwd: URL,
        onStdoutLine: @escaping (String) -> Void
    ) async throws -> (status: Int32, stderr: String) {
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        p.currentDirectoryURL = cwd
        p.environment = CLIBinary.childEnvironment()
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice

        let buf = LineBuffer()
        err.fileHandleForReading.readabilityHandler = { h in
            buf.appendStderr(h.availableData)
        }
        out.fileHandleForReading.readabilityHandler = { h in
            for line in buf.pushStdout(h.availableData) { onStdoutLine(line) }
        }

        proc = p
        try p.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in cont.resume() }
        }
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        if let rest = buf.flushStdout() { onStdoutLine(rest) }
        buf.appendStderr(err.fileHandleForReading.readDataToEndOfFile())
        proc = nil
        return (p.terminationStatus, buf.stderrString)
    }
}

/// ponytail: class box so pipe callbacks don't capture `var` (Swift 6 Sendable).
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stderrAcc = Data()
    private var lineBuf = ""

    func appendStderr(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        stderrAcc.append(chunk)
        lock.unlock()
    }

    func pushStdout(_ chunk: Data) -> [String] {
        guard !chunk.isEmpty, let s = String(data: chunk, encoding: .utf8) else { return [] }
        lock.lock()
        lineBuf += s
        var lines: [String] = []
        while let r = lineBuf.range(of: "\n") {
            lines.append(String(lineBuf[..<r.lowerBound]))
            lineBuf = String(lineBuf[r.upperBound...])
        }
        lock.unlock()
        return lines
    }

    func flushStdout() -> String? {
        lock.lock()
        let rest = lineBuf
        lineBuf = ""
        lock.unlock()
        return rest.isEmpty ? nil : rest
    }

    var stderrString: String {
        lock.lock()
        let s = String(data: stderrAcc, encoding: .utf8) ?? ""
        lock.unlock()
        return s
    }
}
