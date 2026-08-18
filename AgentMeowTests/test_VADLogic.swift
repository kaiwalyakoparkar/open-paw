import AgentMeowCore
import Foundation

enum VADLogicChecks {
    static func run() {
        // Gradium sends 3 horizons: 0.5s, 1.0s, 2.0s — use index 2 for end-of-turn
        var vad = VADLogic(horizonIndex: 2, threshold: 0.5, consecutiveNeeded: 3)
        assert(vad.ingest(vad: [0.05, 0.08, 0.55]) == false)
        assert(vad.ingest(vad: [0.05, 0.08, 0.62]) == false)
        assert(vad.ingest(vad: [0.05, 0.08, 0.70]) == true)

        // legacy config index 3 clamps to last horizon (2)
        vad = VADLogic(horizonIndex: 3, threshold: 0.5, consecutiveNeeded: 1)
        assert(vad.ingest(vad: [0.05, 0.08, 0.62]) == true)

        vad = VADLogic(horizonIndex: 2, threshold: 0.5, consecutiveNeeded: 2)
        assert(vad.ingest(vad: [0.05, 0.08, 0.62]) == false)
        assert(vad.ingest(vad: [0.05, 0.08, 0.10]) == false)
        assert(vad.ingest(vad: [0.05, 0.08, 0.62]) == false)
        assert(vad.ingest(vad: [0.05, 0.08, 0.62]) == true)

        let objs: [[String: Any]] = [
            ["horizon_s": 0.5, "inactivity_prob": 0.05],
            ["horizon_s": 1.0, "inactivity_prob": 0.08],
            ["horizon_s": 2.0, "inactivity_prob": 0.91],
        ]
        assert(VADLogic.parseProbabilities(from: objs) == [0.05, 0.08, 0.91])
        print("VADLogic OK")
    }
}
