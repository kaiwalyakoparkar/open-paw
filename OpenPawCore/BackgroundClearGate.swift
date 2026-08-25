import Foundation

/// One in-flight background clear. Await before next work; schedule after work returns.
public final class BackgroundClearGate: @unchecked Sendable {
    private var task: Task<Void, Never>?
    private let lock = NSLock()

    public init() {}

    public func awaitIfNeeded() async {
        let pending: Task<Void, Never>?
        lock.lock()
        pending = task
        lock.unlock()
        await pending?.value
        lock.lock()
        if task == pending { task = nil }
        lock.unlock()
    }

    public func schedule(_ body: @escaping @Sendable () async -> Void) {
        lock.lock()
        task = Task { await body() }
        lock.unlock()
    }

    /// For tests: whether a clear task is currently tracked.
    public var hasPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return task != nil
    }
}
