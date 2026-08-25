import OpenPawCore
import Foundation

enum ClaudeCLIArgsChecks {
    static func run() {
        let id = "11111111-1111-1111-1111-111111111111"
        let create = ClaudeCLIClient.cliArgs(
            prompt: "hi",
            permissionMode: "acceptEdits",
            pinnedID: id,
            resume: false,
            addDir: "/tmp"
        )
        assert(create.contains("-p"))
        assert(create.contains("stream-json"))
        assert(create.contains("--verbose"), "claude --print + stream-json requires --verbose")
        assert(create.contains("--session-id"))
        assert(create.contains(id))
        assert(create.contains("-n"))
        assert(create.contains(PinnedSessionStore.claudeDisplayName))
        assert(!create.contains("--resume"), "first create should not --resume")
        assert(!create.contains("--model"), "nil model omits --model")

        let withModel = ClaudeCLIClient.cliArgs(
            prompt: "hi",
            permissionMode: "acceptEdits",
            pinnedID: id,
            resume: false,
            addDir: "/tmp",
            model: "opus"
        )
        assert(withModel.contains("--model") && withModel.contains("opus"))

        let resume = ClaudeCLIClient.cliArgs(
            prompt: "hi",
            permissionMode: "acceptEdits",
            pinnedID: id,
            resume: true,
            addDir: "/tmp"
        )
        assert(resume.contains("--resume"))
        assert(resume.contains(id))
        assert(!resume.contains("--session-id"), "resume must not combine --session-id (Claude exits 1)")
        print("ClaudeCLI args OK")
    }
}

enum ClaudeSessionFilesChecks {
    static func run() {
        assert(ClaudeSessionFiles.encodeProjectPath("/Users/kaiwalya") == "-Users-kaiwalya")
        assert(ClaudeSessionFiles.encodeProjectPath("/tmp") == "-tmp")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-paw-claude-wipe-\(UUID().uuidString)", isDirectory: true)
        // Use a fake home by wiping via projectDir under a temp cwd encoding — wipe uses real ~/.claude
        // so test wipe API with a disposable project dir by writing next to real encode of /tmp-style path.
        // Instead: unit-test wipe against paths we construct the same way.
        let cwd = URL(fileURLWithPath: "/tmp/open-paw-wipe-test-\(UUID().uuidString)", isDirectory: true)
        let sid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let project = ClaudeSessionFiles.projectDir(cwd: cwd)
        try! FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let jsonl = ClaudeSessionFiles.transcriptURL(cwd: cwd, sessionID: sid)
        try! "msg\n".write(to: jsonl, atomically: true, encoding: .utf8)
        let sidecar = project.appendingPathComponent(sid)
        try! FileManager.default.createDirectory(at: sidecar, withIntermediateDirectories: true)
        assert(ClaudeSessionFiles.transcriptExists(cwd: cwd, sessionID: sid))
        assert(ClaudeSessionFiles.wipe(cwd: cwd, sessionID: sid))
        assert(!ClaudeSessionFiles.transcriptExists(cwd: cwd, sessionID: sid))
        assert(!FileManager.default.fileExists(atPath: sidecar.path))
        // cleanup project dir if empty-ish
        try? FileManager.default.removeItem(at: project)
        try? FileManager.default.removeItem(at: dir)
        print("ClaudeSessionFiles OK")
    }
}


enum CodexCLIArgsChecks {
    static func run() {
        let first = CodexCLIClient.cliArgs(prompt: "hi", sessionID: nil)
        assert(first == ["exec", "--json", "--skip-git-repo-check", "hi"], "\(first)")

        let resume = CodexCLIClient.cliArgs(prompt: "hi", sessionID: "th1")
        assert(resume == ["exec", "resume", "th1", "--json", "hi"], "\(resume)")

        let modeled = CodexCLIClient.cliArgs(prompt: "hi", sessionID: nil, model: "gpt-5.6-terra")
        assert(modeled == ["exec", "--model", "gpt-5.6-terra", "--json", "--skip-git-repo-check", "hi"], "\(modeled)")

        let resumeModel = CodexCLIClient.cliArgs(prompt: "hi", sessionID: "th1", model: "gpt-5.6-sol")
        assert(resumeModel == ["exec", "resume", "th1", "--model", "gpt-5.6-sol", "--json", "hi"], "\(resumeModel)")

        let clear = CodexCLIClient.clearArgs(sessionID: "th1")
        assert(clear == ["exec", "resume", "th1", "--json", "/clear"], "\(clear)")
        print("CodexCLI args OK")
    }
}

enum HermesSessionURLChecks {
    static func run() {
        let del = HermesAPIClient.sessionDeleteURL(
            baseURL: "http://127.0.0.1:8642/v1",
            sessionID: "open-paw"
        )
        assert(del?.absoluteString == "http://127.0.0.1:8642/api/sessions/open-paw", "\(del?.absoluteString ?? "nil")")

        let del2 = HermesAPIClient.sessionDeleteURL(
            baseURL: "http://127.0.0.1:8642/v1/",
            sessionID: PinnedSessionStore.hermesPinnedID
        )
        assert(del2?.absoluteString == "http://127.0.0.1:8642/api/sessions/open-paw")

        let chat = HermesAPIClient.completionsURL(baseURL: "http://127.0.0.1:8642/v1")
        assert(chat?.absoluteString == "http://127.0.0.1:8642/v1/chat/completions")
        assert(HermesAPIClient.sessionIDHeader == "X-Hermes-Session-Id")
        print("Hermes session URL OK")
    }
}

enum PinnedSessionStoreChecks {
    static func run() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-paw-store-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("sessions.json")
        assert(PinnedSessionStore.load(from: url).claude == nil)

        let store = PinnedSessionStore(claude: "c1", hermes: "open-paw", codex: "th1")
        try! store.save(to: url)
        let loaded = PinnedSessionStore.load(from: url)
        assert(loaded.claude == "c1")
        assert(loaded.hermes == "open-paw")
        assert(loaded.codex == "th1")
        print("PinnedSessionStore OK")
    }
}

enum BackgroundClearGateChecks {
    static func run() {
        let gate = BackgroundClearGate()
        var order: [String] = []
        let lock = NSLock()

        func append(_ s: String) {
            lock.lock()
            order.append(s)
            lock.unlock()
        }

        // Simulate: work returns before clear finishes
        let clearStarted = DispatchSemaphore(value: 0)
        let clearMayFinish = DispatchSemaphore(value: 0)

        append("work")
        gate.schedule {
            append("clear-start")
            clearStarted.signal()
            clearMayFinish.wait()
            append("clear-done")
        }
        clearStarted.wait()
        assert(gate.hasPending)
        assert(order == ["work", "clear-start"], "\(order)")

        // Second stream awaits in-flight clear, then works, then schedules new clear
        let work2 = DispatchSemaphore(value: 0)
        Task {
            await gate.awaitIfNeeded()
            append("work2")
            work2.signal()
            gate.schedule {
                append("clear2")
            }
        }
        // release first clear so awaitIfNeeded can finish
        clearMayFinish.signal()
        work2.wait()
        // let clear2 run
        Thread.sleep(forTimeInterval: 0.05)
        assert(order == ["work", "clear-start", "clear-done", "work2", "clear2"], "\(order)")
        print("BackgroundClearGate OK")
    }
}
