import Foundation

/// Claude stores sessions under ~/.claude/projects/<encoded-cwd>/{uuid}.jsonl
public enum ClaudeSessionFiles {
    /// `/Users/kaiwalya` → `-Users-kaiwalya`
    public static func encodeProjectPath(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        if p.hasPrefix("/") { p.removeFirst() }
        return "-" + p.replacingOccurrences(of: "/", with: "-")
    }

    public static func projectDir(cwd: URL) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
            .appendingPathComponent(encodeProjectPath(cwd.path))
    }

    public static func transcriptURL(cwd: URL, sessionID: String) -> URL {
        projectDir(cwd: cwd).appendingPathComponent("\(sessionID).jsonl")
    }

    public static func transcriptExists(cwd: URL, sessionID: String) -> Bool {
        FileManager.default.fileExists(atPath: transcriptURL(cwd: cwd, sessionID: sessionID).path)
    }

    /// Wipe pinned session history without `/clear` (which mints a new session ID).
    @discardableResult
    public static func wipe(cwd: URL, sessionID: String) -> Bool {
        let dir = projectDir(cwd: cwd)
        let jsonl = dir.appendingPathComponent("\(sessionID).jsonl")
        let sidecar = dir.appendingPathComponent(sessionID)
        var removed = false
        let fm = FileManager.default
        if fm.fileExists(atPath: jsonl.path) {
            try? fm.removeItem(at: jsonl)
            removed = true
        }
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: sidecar.path, isDirectory: &isDir) {
            try? fm.removeItem(at: sidecar)
            removed = true
        }
        return removed
    }
}
