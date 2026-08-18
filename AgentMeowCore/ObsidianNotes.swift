import Foundation

/// Hermes gateway (launchd) cannot read ~/Documents (macOS TCC). Agent-meow can,
/// so matching vault notes are attached to the prompt instead of asking the user to paste.
public enum ObsidianNotes {
    public static var defaultRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Obsidian")
        return ["Work", "Personal", "Kai's Brain"].map { home.appendingPathComponent($0) }
    }

    public static func looksLikeNotesQuery(_ prompt: String) -> Bool {
        let p = prompt.lowercased()
        return ["obsidian", "meeting", "vault", "action item", "notes"].contains { p.contains($0) }
    }

    public static func wrap(_ prompt: String, roots: [URL] = defaultRoots) -> String {
        guard looksLikeNotesQuery(prompt), let extra = attached(prompt: prompt, roots: roots) else {
            return prompt
        }
        return prompt + "\n\n" + extra
    }

    static func attached(prompt: String, roots: [URL]) -> String? {
        guard let url = bestFile(prompt: prompt, roots: roots) else { return nil }
        guard let body = try? String(contentsOf: url, encoding: .utf8), !body.isEmpty else { return nil }
        let clipped = String(body.prefix(6000))
        return "Local notes (\(url.lastPathComponent)) — use these; do not ask the user to paste:\n\(clipped)"
    }

    static func bestFile(prompt: String, roots: [URL]) -> URL? {
        let fm = FileManager.default
        var files: [URL] = []
        // ponytail: walk *.md up to 500 files; index if vaults get huge
        for root in roots {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in e {
                if url.pathExtension.lowercased() == "md" { files.append(url) }
                if files.count >= 500 { break }
            }
        }
        let tokens = tokens(in: prompt)
        func score(_ url: URL) -> Int {
            let name = url.lastPathComponent.lowercased()
            let nameHits = tokens.reduce(0) { $0 + (name.contains($1) ? 1 : 0) }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            // ponytail: name match dominates; size beats empty stub duplicates with newer mtime
            return nameHits * 1_000_000 + min(size, 50_000)
        }
        return files.max(by: { score($0) < score($1) })
    }

    static func tokens(in prompt: String) -> [String] {
        let stop: Set<String> = ["from", "with", "that", "this", "last", "meeting", "notes", "obsidian", "vault", "action", "items", "item", "your", "have", "pull"]
        return prompt.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 4 && !stop.contains($0) }
    }
}
