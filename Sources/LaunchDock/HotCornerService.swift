import AppKit
import LaunchDockCore
import SwiftUI

@MainActor final class HotCornerService {
    struct Input {
        var point: NSPoint
        var screens: [NSRect]
        var mouseDown: Bool
    }
    private let defaults: UserDefaults
    private let input: () -> Input
    private var timer: Timer?
    private var trigger = CornerTrigger()
    private var activity: NSObjectProtocol?
    private var ticks = 0
    private var fires = 0
    private var lastCorner: Int?
    private var history: [[String: Any]] = []
    var windowState: (() -> [String: Bool])?
    func recordStatus(_ event: String) {
        #if DEBUG
        history.append(["event": event, "ticks": ticks, "window": windowState?() ?? [:]])
        if history.count > 16 { history.removeFirst() }
        let data: [String: Any] = ["history": history, "event": event, "ticks": ticks, "fires": fires, "selected": Self.selectedCorner(in: defaults), "running": isRunning, "corner": lastCorner ?? -1, "window": windowState?() ?? [:]]
        if let bytes = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]) {
            try? bytes.write(to: URL(fileURLWithPath: "/tmp/launchdock-corner-\(ProcessInfo.processInfo.processIdentifier).json"), options: .atomic)
        }
        #endif
    }
    var action: (() -> Void)?
    var isRunning: Bool { timer != nil }
    init(defaults: UserDefaults = .standard, input: (() -> Input)? = nil) {
        self.defaults = defaults
        self.input = input ?? {
            Input(point: NSEvent.mouseLocation, screens: NSScreen.screens.map(\.frame), mouseDown: NSEvent.pressedMouseButtons != 0)
        }
    }
    static func selectedCorner(in defaults: UserDefaults) -> Int {
        if defaults.object(forKey: "hotCornerSelection") == nil {
            let legacy = defaults.integer(forKey: "hotCornerMask")
            defaults.set((0..<4).first { legacy & (1 << $0) != 0 } ?? -1, forKey: "hotCornerSelection")
        }
        let value = defaults.integer(forKey: "hotCornerSelection")
        return (0..<4).contains(value) ? value : -1
    }
    func refresh() {
        stop()
        // Retire the legacy modifier preference so existing users need no Option.
        defaults.removeObject(forKey: "hotCornerOption")
        guard Self.selectedCorner(in: defaults) >= 0 else { return }
        // Read only the public pointer state. Event monitors can miss background delivery;
        // this also detects a pointer resting motionless against a screen edge.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "User-enabled LaunchDock hot corner")
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.005
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        recordStatus("started")
    }
    private func sample() {
        ticks += 1
        let state = input()
        let point = state.point
        var corner: Int?
        for f in state.screens where f.insetBy(dx: -1, dy: -1).contains(point) {
            if abs(point.x-f.minX) <= 6 && abs(point.y-f.maxY) <= 6 { corner = 0 }
            else if abs(point.x-f.maxX) <= 6 && abs(point.y-f.maxY) <= 6 { corner = 1 }
            else if abs(point.x-f.minX) <= 6 && abs(point.y-f.minY) <= 6 { corner = 2 }
            else if abs(point.x-f.maxX) <= 6 && abs(point.y-f.minY) <= 6 { corner = 3 }
        }
        let selected = Self.selectedCorner(in: defaults)
        let mask = selected >= 0 ? 1 << selected : 0
        if trigger.update(corner: corner, enabledMask: mask, modifierOK: true, mouseDown: state.mouseDown, now: ProcessInfo.processInfo.systemUptime) {
            fires += 1; action?(); lastCorner = corner; recordStatus("fired")
        } else if corner != lastCorner { lastCorner = corner; recordStatus("pointer-region") }
    }
    func stop() {
        timer?.invalidate(); timer = nil; trigger = CornerTrigger()
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        recordStatus("stopped")
    }
}
struct HotCornerSettings: View {
    var refresh: () -> Void
    @AppStorage("hotCornerSelection") private var selected = -1
    var body: some View {
        Picker("触发角", selection: $selected) {
            Text("关闭").tag(-1)
            Text("左上角").tag(0)
            Text("右上角").tag(1)
            Text("左下角").tag(2)
            Text("右下角").tag(3)
        }.pickerStyle(.menu)
            .onChange(of: selected) { _, _ in refresh() }
        Text("移入触发角立即显示或隐藏。若与系统触发角冲突，请关闭系统对应动作。")
            .font(.caption).foregroundStyle(.secondary)
    }
}
