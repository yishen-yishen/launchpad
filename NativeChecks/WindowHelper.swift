import AppKit
@main struct WindowHelper {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 260, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "LaunchDock 窗口层级测试"
        window.isReleasedWhenClosed = false
        window.contentView = NSTextField(labelWithString: "仅用于窗口层级与可见性回归检查")
        window.orderFront(nil)
        let directory = Bundle.main.bundleURL.deletingLastPathComponent()
        let deadline = Date().addingTimeInterval(120)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated {
                if Date() > deadline || FileManager.default.fileExists(atPath: directory.appendingPathComponent("quit").path) {
                    NSApp.terminate(nil)
                }
            }
        }
        withExtendedLifetime(timer) { app.run() }
    }
}
