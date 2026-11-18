import Foundation

public struct BackgroundDrag: Sendable {
    public enum Result: Equatable, Sendable { case click, page(Int), cancel }
    private let x: Double
    private let y: Double
    private var moved = false
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public mutating func update(x: Double, y: Double) { if hypot(x-self.x,y-self.y) > 6 { moved = true } }
    public mutating func end(x: Double, y: Double) -> Result {
        update(x: x,y: y)
        let dx = x-self.x, dy = y-self.y
        if abs(dx) >= 60 && abs(dx) > abs(dy)*1.2 { return .page(dx < 0 ? 1 : -1) }
        return moved ? .cancel : .click
    }
}
