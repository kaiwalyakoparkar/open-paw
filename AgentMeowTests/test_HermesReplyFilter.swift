import AgentMeowCore
import Foundation

enum HermesReplyFilterChecks {
    static func run() {
        let leak = #"{"command":"find ~/Documents -maxdepth 2 -name \"*.md\"","timeout":10}"#
        assert(HermesReplyFilter.isToolLeak(leak), "terminal JSON is a leak")
        assert(!HermesReplyFilter.isToolLeak("Share the Chinese lab video with Derek"), "prose is not a leak")

        var f = HermesReplyFilter()
        assert(f.push(#"{"command":"#).isEmpty, "partial JSON held")
        assert(f.push(#""find ~/Documents","timeout":10}"#).isEmpty, "complete leak dropped")

        var g = HermesReplyFilter()
        assert(g.push("Share the video") == "Share the video")
        assert(g.flush().isEmpty)

        var h = HermesReplyFilter()
        _ = h.push(leak)
        assert(h.flush().isEmpty, "flush must not surface leak")

        print("HermesReplyFilter OK")
    }
}
