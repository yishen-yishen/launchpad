import AppKit

@main struct FullscreenHelper {
    @MainActor static func main() {
        let app = NSApplication.shared
        let host = FullscreenHost(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        app.setActivationPolicy(.regular)
        app.delegate = host
        withExtendedLifetime(host) { app.run() }
    }
}
@MainActor final class FullscreenHost: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let directory: URL
    var window: NSWindow!
    var entered = false
    var requested = false
    var timer: Timer?
    let deadline = Date().addingTimeInterval(120)
    init(directory: URL) { self.directory = directory }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        window = NSWindow(contentRect: NSRect(x: screen.frame.midX-300, y: screen.frame.midY-180, width: 600, height: 360), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
        window.title = "LaunchDock 全屏 Space 回归测试"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = NSTextField(labelWithString: "独立全屏测试窗口；测试结束后自动关闭")
        window.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        }
    }
    func windowDidEnterFullScreen(_ notification: Notification) { entered = true; publish() }
    func publish() {
        if Date() > deadline || FileManager.default.fileExists(atPath: directory.appendingPathComponent("quit").path) { NSApp.terminate(nil); return }
        if !requested && NSApp.isActive && window.isKeyWindow {
            requested = true
            window.toggleFullScreen(nil)
        }
        let state: [String:Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
            "entered": entered, "requested": requested, "key": window.isKeyWindow, "time": Date().timeIntervalSince1970, "fullscreen": window.styleMask.contains(.fullScreen),
            "onActiveSpace": window.isOnActiveSpace, "active": NSApp.isActive]
        if let data = try? JSONSerialization.data(withJSONObject: state) {
            try? data.write(to: directory.appendingPathComponent("state.json"), options: .atomic)
        }
    }
}
