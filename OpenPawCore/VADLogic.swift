import Foundation

/// Pure end-of-turn detector over Gradium `step.vad[]` inactivity probabilities.
public struct VADLogic {
    public var horizonIndex: Int
    public var threshold: Double
    public var consecutiveNeeded: Int
    private var streak = 0

    public init(horizonIndex: Int, threshold: Double, consecutiveNeeded: Int) {
        self.horizonIndex = horizonIndex
        self.threshold = threshold
        self.consecutiveNeeded = consecutiveNeeded
    }

    /// Returns true when enough consecutive frames exceed the inactivity threshold.
    public mutating func ingest(vad: [Double]) -> Bool {
        guard !vad.isEmpty else {
            streak = 0
            return false
        }
        // ponytail: clamp — Gradium sends 3 horizons (0.5s/1s/2s); config index 3 was never valid
        let idx = min(horizonIndex, vad.count - 1)
        if vad[idx] >= threshold {
            streak += 1
        } else {
            streak = 0
        }
        if streak >= consecutiveNeeded {
            streak = 0
            return true
        }
        return false
    }

    public mutating func reset() {
        streak = 0
    }

    /// Gradium `step.vad` is `[{"horizon_s": 0.5, "inactivity_prob": 0.05}, ...]`.
    public static func parseProbabilities(from value: Any?) -> [Double]? {
        guard let value else { return nil }
        if let nums = value as? [Double] { return nums }
        if let nums = value as? [NSNumber] { return nums.map(\.doubleValue) }
        guard let objs = value as? [[String: Any]] else { return nil }
        let probs = objs.compactMap { obj -> Double? in
            if let d = obj["inactivity_prob"] as? Double { return d }
            if let n = obj["inactivity_prob"] as? NSNumber { return n.doubleValue }
            return nil
        }
        return probs.isEmpty ? nil : probs
    }
}
