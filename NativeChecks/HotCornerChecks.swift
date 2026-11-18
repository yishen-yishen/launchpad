import AppKit
import LaunchDockCore

@main struct HotCornerChecks {
    @MainActor static func main() {
        let suite = "LaunchDock.corner-check.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(2, forKey: "hotCornerMask")
        precondition(HotCornerService.selectedCorner(in: defaults) == 1)
        var point = NSPoint(x: 1000,y: 1000)
        var pressed = false
        var count = 0
        let service = HotCornerService(defaults: defaults, input: {
            .init(point: point, screens: [NSRect(x: 0,y: 0,width: 1000,height: 1000)], mouseDown: pressed)
        })
        service.action = { count += 1 }
        func run(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        service.refresh(); run(0.09)
        precondition(count == 1, "Immediate exact-edge cursor triggers through actual run-loop timer")
        run(0.5); precondition(count == 1)
        point = NSPoint(x: 500,y: 500); run(0.2)
        point = NSPoint(x: 1000,y: 1000); run(0.8); precondition(count == 2)
        defaults.set(true, forKey: "hotCornerOption"); service.refresh(); run(0.8)
        precondition(count == 3, "Legacy Option preference must no longer prevent an immediate trigger")
        precondition(defaults.object(forKey: "hotCornerOption") == nil)
        pressed = true; service.refresh(); run(0.8); precondition(count == 3)
        defaults.set(0, forKey: "hotCornerSelection"); pressed = false; service.refresh(); run(0.8)
        precondition(count == 3, "Unselected corner must not trigger")
        point = NSPoint(x: 0,y: 1000); run(0.8); precondition(count == 4)
        defaults.set(-1, forKey: "hotCornerSelection"); service.refresh()
        precondition(!service.isRunning)
        run(0.4); precondition(count == 4)
        print("PASS: single-choice migration, actual timer callback, exact screen edges, latch/reentry, removed legacy Option requirement, dragging suppression, corner change, disabled cleanup")
    }
}
