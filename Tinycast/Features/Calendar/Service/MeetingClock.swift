import Foundation

/// Publishes the current minute so a countdown re-renders on the boundary rather than per keystroke.
/// It runs only while the palette is up, so an idle Mac owns no timer at all.
@MainActor
@Observable
final class MeetingClock {
    private(set) var now = Date()

    @ObservationIgnored private var tick: Task<Void, Never>?

    func start() {
        now = Date()
        // Replace rather than bail: an exited loop leaves a non-nil task that would block restart.
        tick?.cancel()
        tick = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.secondsToNextMinute()))
                guard !Task.isCancelled, let self else { return }
                self.now = Date()
            }
        }
    }

    func stop() {
        tick?.cancel()
        tick = nil
    }

    isolated deinit {
        tick?.cancel()
    }

    /// The reference date is itself a minute boundary, so the remainder is the offset into one.
    private static func secondsToNextMinute() -> TimeInterval {
        60 - Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
    }
}
