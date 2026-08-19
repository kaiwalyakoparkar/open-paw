import OpenPawCore
import Foundation

enum CodexStreamParserChecks {
    static func run() {
        let start = #"{"type":"thread.started","thread_id":"th1"}"#
        assert(CodexStreamParser.parse(line: start)?.sessionID == "th1")

        let delta = #"{"type":"item.delta","delta":{"text":"He"}}"#
        let d = CodexStreamParser.parse(line: delta)
        assert(d?.textDelta == "He")
        assert(d?.isPartial == true)

        let done = #"{"type":"item.completed","item":{"type":"agent_message","text":"Hello"}}"#
        assert(CodexStreamParser.parse(line: done)?.textDelta == "Hello")

        let tool = #"{"type":"item.completed","item":{"type":"mcp_tool_call","name":"Read","id":"1"}}"#
        assert(CodexStreamParser.parse(line: tool)?.toolCalls.first?.name == "Read")

        let turn = #"{"type":"turn.completed"}"#
        assert(CodexStreamParser.parse(line: turn)?.finished == true)

        let failed = #"{"type":"turn.failed","error":{"message":"You've hit your usage limit."}}"#
        let f = CodexStreamParser.parse(line: failed)
        assert(f?.finished == true)
        assert(f?.errorMessage == "You've hit your usage limit.", f?.errorMessage ?? "nil")

        print("CodexStreamParser OK")
    }
}
