import OpenPawCore
import Foundation

enum HermesSSEParserChecks {
    static func run() {
        let line = #"data: {"choices":[{"delta":{"content":"Hi"}}]}"#
        let ev = HermesSSEParser.parse(line: line)
        assert(ev?.textDelta == "Hi")
        assert(ev?.finished == false)
        assert(HermesSSEParser.parse(line: "data: [DONE]")?.finished == true)
        let tool = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"foo","arguments":"{"}}]}}]}"#
        assert(HermesSSEParser.parse(line: tool)?.toolCalls.first?.name == "foo")

        let progressLine = #"data: {"tool":"web","emoji":"🔍","label":"search APIs","toolCallId":"t1","status":"running"}"#
        let progress = HermesSSEParser.parse(line: progressLine, event: "hermes.tool.progress")
        assert(progress?.progress == "🔍 search APIs", "progress: \(progress?.progress ?? "nil")")
        assert(progress?.textDelta == "")

        let done = HermesSSEParser.parse(
            line: #"data: {"tool":"web","toolCallId":"t1","status":"completed"}"#,
            event: "hermes.tool.progress"
        )
        assert(done?.progress == "web done", "done: \(done?.progress ?? "nil")")

        let wait = HermesProgress.waitBubble(prompt: "What is api management", status: "🔍 search APIs", seconds: 8)
        assert(wait.contains("What is api management"))
        assert(wait.contains("🔍 search APIs"))
        assert(wait.contains("Working… 8s"))

        let nullErr = #"data: {"choices":[{"delta":{"content":"Hi"}}],"error":null}"#
        let nullEv = HermesSSEParser.parse(line: nullErr)
        assert(nullEv?.textDelta == "Hi", "error:null must not kill the stream: \(nullEv?.textDelta ?? "nil")")
        assert(nullEv?.finished == false)

        let five = #"data: {"error":{"message":"HTTP 500: Internal Server Error (ref: 0a84a9be)","type":"agent_error"}}"#
        let fiveEv = HermesSSEParser.parse(line: five)
        assert(fiveEv?.textDelta.contains("HTTP 500: Internal Server Error (ref: 0a84a9be)") == true, fiveEv?.textDelta ?? "nil")
        assert(fiveEv?.textDelta.contains("message =") != true, fiveEv?.textDelta ?? "nil")
        assert(fiveEv?.finished == true)

        print("HermesSSEParser OK")
    }
}
