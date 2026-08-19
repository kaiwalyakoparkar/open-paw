import OpenPawCore
import Foundation

enum ClaudeStreamParserChecks {
    static func run() {
        let partial = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}}"#
        let p = ClaudeStreamParser.parse(line: partial)
        assert(p?.textDelta == "Hi", p?.textDelta ?? "nil")
        assert(p?.isPartial == true)
        assert(p?.finished == false)

        let think = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hmm"}}}"#
        let t = ClaudeStreamParser.parse(line: think)
        assert(t == nil || (t?.textDelta == "" && t?.finished == false), "thinking leaked: \(t?.textDelta ?? "")")

        let assistant = #"{"type":"assistant","session_id":"s1","message":{"content":[{"type":"text","text":"Hello"},{"type":"tool_use","id":"t1","name":"Read"}]}}"#
        let a = ClaudeStreamParser.parse(line: assistant)
        assert(a?.textDelta == "Hello", a?.textDelta ?? "nil")
        assert(a?.isPartial == false)
        assert(a?.toolCalls.first?.name == "Read")
        assert(a?.sessionID == "s1")

        let result = #"{"type":"result","session_id":"s1","result":"Hello","is_error":false}"#
        let r = ClaudeStreamParser.parse(line: result)
        assert(r?.finished == true)
        assert(r?.sessionID == "s1")
        assert(r?.textDelta == "")

        let err = #"{"type":"result","is_error":true,"result":"boom","session_id":"s1"}"#
        let e = ClaudeStreamParser.parse(line: err)
        assert(e?.finished == true)
        assert(e?.errorMessage == "boom")

        print("ClaudeStreamParser OK")
    }
}
