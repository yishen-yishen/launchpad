import Foundation

public struct CornerTrigger: Sendable {
    private var corner: Int?
    private var fired = false
    public var isWaiting: Bool { corner != nil && !fired }
    public init() {}
    public mutating func update(corner value: Int?, enabledMask: Int, modifierOK: Bool, mouseDown: Bool, now: Double) -> Bool {
        guard let value, (0..<4).contains(value), enabledMask & (1 << value) != 0, modifierOK, !mouseDown else {
            corner = nil; fired = false; return false
        }
        if corner != value { corner = value; fired = false }
        guard !fired else { return false }
        fired = true; return true
    }
}
