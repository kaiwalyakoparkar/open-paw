import OpenPawCore
import Foundation

enum ObsidianNotesChecks {
    static func run() {
        assert(ObsidianNotes.looksLikeNotesQuery("two action items from my last meeting with derek. notes in obsidian vault"))
        assert(!ObsidianNotes.looksLikeNotesQuery("what's the weather"))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("meow-vault-\(UUID().uuidString)")
        let meetings = root.appendingPathComponent("Meeting Notes")
        try! FileManager.default.createDirectory(at: meetings, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try! "# Other\n\nNo actions.\n".write(to: meetings.appendingPathComponent("2026-07-01_Standup.md"), atomically: true, encoding: .utf8)
        try! """
        # Derek / Kaiwalya
        # Next Steps
        - Share the Chinese lab video with Derek
        - Share followed blogs with Derek
        """.write(to: meetings.appendingPathComponent("2026-08-06_Derek.md"), atomically: true, encoding: .utf8)
        let stub = meetings.appendingPathComponent("2026-08-06_Derek_stub.md")
        try! "# stub\n".write(to: stub, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(3600)],
            ofItemAtPath: stub.path
        )

        let wrapped = ObsidianNotes.wrap(
            "two action items from last meeting with derek. obsidian vault",
            roots: [root]
        )
        assert(wrapped.contains("Share the Chinese lab video"), wrapped)
        assert(wrapped.contains("2026-08-06_Derek.md"), wrapped)
        assert(!wrapped.contains("No actions"), wrapped)

        print("ObsidianNotes OK")
    }
}
