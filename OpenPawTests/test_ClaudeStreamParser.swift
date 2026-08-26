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

        let assistant = #"{"type":"assistant","session_id":"s1","message":{"content":[{"type":"text","text":"Hello"},{"type":"tool_use","id":"t1","name":"Read"}],"usage":{"input_tokens":10,"output_tokens":42}}}"#
        let a = ClaudeStreamParser.parse(line: assistant)
        assert(a?.textDelta == "Hello", a?.textDelta ?? "nil")
        assert(a?.isPartial == false)
        assert(a?.toolCalls.first?.name == "Read")
        assert(a?.sessionID == "s1")
        assert(a?.outputTokens == 42, "assistant usage: \(a?.outputTokens.map(String.init) ?? "nil")")

        let toolOnly = #"{"type":"assistant","session_id":"s1","message":{"content":[{"type":"tool_use","id":"t2","name":"Bash"}],"usage":{"input_tokens":100,"output_tokens":17}}}"#
        let to = ClaudeStreamParser.parse(line: toolOnly)
        assert(to?.textDelta == "")
        assert(to?.toolCalls.first?.name == "Bash")
        assert(to?.outputTokens == 17, "tool-only usage: \(to?.outputTokens.map(String.init) ?? "nil")")

        let result = #"{"type":"result","session_id":"s1","result":"Hello","is_error":false,"usage":{"input_tokens":10,"output_tokens":42}}"#
        let r = ClaudeStreamParser.parse(line: result)
        assert(r?.finished == true)
        assert(r?.sessionID == "s1")
        assert(r?.textDelta == "")
        assert(r?.outputTokens == 42, "result usage: \(r?.outputTokens.map(String.init) ?? "nil")")

        let delta = #"{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":null},"usage":{"output_tokens":17}}}"#
        let d = ClaudeStreamParser.parse(line: delta)
        assert(d?.outputTokens == 17, "message_delta usage: \(d?.outputTokens.map(String.init) ?? "nil")")
        assert(d?.finished == false)

        let err = #"{"type":"result","is_error":true,"result":"boom","session_id":"s1"}"#
        let e = ClaudeStreamParser.parse(line: err)
        assert(e?.finished == true)
        assert(e?.errorMessage == "boom")

        print("ClaudeStreamParser OK")
    }
}
