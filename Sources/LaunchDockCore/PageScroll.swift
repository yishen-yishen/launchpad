import Foundation

/// Aggregates a wheel burst or one trackpad gesture. Time is monotonic and injected.
public struct PageScroll: Sendable {
    private var accumulated = 0.0
    private var lastEvent = -Double.infinity
    private var lastFlip = -Double.infinity
    private var gestureFlipped = false
    public init() {}
    public mutating func update(delta: Double, precise: Bool, began: Bool, ended: Bool, momentum: Bool, now: Double) -> Int {
        guard !momentum else { return 0 }
        if began || now - lastEvent > 0.35 { accumulated = 0; gestureFlipped = false }
        lastEvent = now
        defer { if ended { accumulated = 0 } }
        guard !precise || !gestureFlipped else { return 0 }
        if accumulated * delta < 0 { accumulated = 0 }
        accumulated += delta
        guard abs(accumulated) >= (precise ? 60 : 3), now - lastFlip >= 0.55 else { return 0 }
        let direction = accumulated < 0 ? 1 : -1
        accumulated = 0; lastFlip = now; gestureFlipped = true
        return direction
    }
}
