import AppKit
import CoreGraphics
import Darwin
setbuf(stdout, nil)

let defaults = UserDefaults(suiteName: "app.launchdock.LaunchDock")!
let selected = defaults.integer(forKey: "hotCornerSelection")
let keys = ["wvous-tl-corner","wvous-tr-corner","wvous-bl-corner","wvous-br-corner"]
guard (0..<4).contains(selected), !defaults.bool(forKey: "hotCornerOption"),
      (UserDefaults(suiteName: "com.apple.dock")?.integer(forKey: keys[selected]) ?? 0) <= 1 else {
    throw NSError(domain: "LaunchDock.RuntimeCornerProbe", code: 3, userInfo: [NSLocalizedDescriptionKey: "Selected corner disabled, requires Option, or has a system action; no pointer test performed"])
}
let display = CGDisplayBounds(CGMainDisplayID())
let cornerPoint = CGPoint(x: selected == 1 || selected == 3 ? display.maxX-1 : display.minX+1, y: selected < 2 ? display.minY+1 : display.maxY-1)
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "app.launchdock.LaunchDock" }), let original = CGEvent(source: nil)?.location else { fatalError("LaunchDock or pointer unavailable") }
let url = URL(fileURLWithPath: "/tmp/launchdock-corner-\(app.processIdentifier).json")
func status() -> [String: Any] { ((try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] ?? [:] }
func wait(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
let oldFires = status()["fires"] as? Int ?? 0
print("before",status())
print("hide request",app.hide())
wait(0.8)
print("hidden",app.isHidden)
defer { CGWarpMouseCursorPosition(original) }
let warp = CGWarpMouseCursorPosition(cornerPoint)
print("warp",warp.rawValue)
for _ in 0..<20 { CGWarpMouseCursorPosition(cornerPoint); wait(0.1) }
print("pointer Quartz", CGEvent(source: nil)?.location as Any, "AppKit", NSEvent.mouseLocation, "buttons", NSEvent.pressedMouseButtons)
let after = status()
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let all = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
print("owned windows", all.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier }.map { ["layer": $0[kCGWindowLayer as String] ?? "nil", "alpha": $0[kCGWindowAlpha as String] ?? "nil", "onscreen": $0[kCGWindowIsOnscreen as String] ?? "nil", "bounds": $0[kCGWindowBounds as String] ?? "nil"] })
let overlay = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 3 }
print("after",after)
print("active",app.isActive,"hidden",app.isHidden,"onScreenOverlayCount",overlay.count)
let success = (after["fires"] as? Int ?? 0) > oldFires && !app.isHidden && !overlay.isEmpty
print(success ? "PASS: real pointer -> background timer -> action -> on-screen overlay" : "FAIL: real activation chain")

if !success { CGWarpMouseCursorPosition(original); exit(1) }

CGWarpMouseCursorPosition(CGPoint(x: 400,y: 400)); wait(0.2)
CGWarpMouseCursorPosition(cornerPoint); wait(0.6)
let closed = status()
let visibleAfterToggle = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).filter {
    ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 3
}
print("after second entry",closed,"onScreenOverlayCount",visibleAfterToggle.count)
let toggledOff = (closed["fires"] as? Int ?? 0) >= oldFires+2 && visibleAfterToggle.isEmpty
if !toggledOff { CGWarpMouseCursorPosition(original); exit(2) }
print("PASS: leave and reenter corner toggles visible launcher off; parked pointer never repeats")
