import Foundation

/// Fires `action` once, `delay` seconds after the last `schedule()`.
final class Debouncer {
    private let delay: TimeInterval
    private let action: () -> Void
    private var item: DispatchWorkItem?

    init(delay: TimeInterval, action: @escaping () -> Void) {
        self.delay = delay
        self.action = action
    }

    func schedule() {
        item?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.item = nil
            self?.action()
        }
        item = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancel() {
        item?.cancel()
        item = nil
    }
}
