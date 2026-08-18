import Foundation
import OpenPawCore

/// Thin wrapper so barge-in stays a named type as in the plan.
enum BargeInHandler {
    static let interruptedSuffix = " [interrupted — tools may have already executed]"
}
