import AppKit
import SwiftUI
import LaunchDockCore

@MainActor func checkForeignFullscreenSpace(fixture: URL, records: [AppRecord]) async throws {
    guard let path = ProcessInfo.processInfo.environment["LAUNCHDOCK_FULLSCREEN_HELPER"], !path.isEmpty else { return }
    let helperURL = URL(fileURLWithPath: path)
    let originalPolicy = NSApp.activationPolicy()
    defer { NSApp.setActivationPolicy(originalPolicy) }
    let directory = helperURL.deletingLastPathComponent()
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    config.arguments = [directory.path]
    let host = try await NSWorkspace.shared.openApplication(at: helperURL, configuration: config)
    defer { _ = host.terminate() }
    NSApp.deactivate()
    NSApp.yieldActivation(to: host)
    _ = host.activate(options: [])
    func state() -> [String:Any] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("state.json")),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String:Any] else { return [:] }
        return value
    }
    let deadline = Date().addingTimeInterval(20)
    while Date() < deadline {
        let value = state()
        if value["entered"] as? Bool == true && value["onActiveSpace"] as? Bool == true && NSWorkspace.shared.frontmostApplication?.processIdentifier == host.processIdentifier { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    print("Fullscreen host readiness:", state()); fflush(stdout)
    try requireNative(state()["fullscreen"] as? Bool == true && state()["onActiveSpace"] as? Bool == true, "Fullscreen host did not become ready within 20s; state=\(state()), frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")")
    try requireNative(NSWorkspace.shared.frontmostApplication?.processIdentifier == host.processIdentifier)
    // First yield activation from the regular test driver to the fullscreen
    // host; only the launcher overlay under test should run as an accessory.
    NSApp.setActivationPolicy(.accessory)
    let coordinator = AppCoordinator()
    coordinator.store.records = records
    try coordinator.store.engine.reconcile(records)
    coordinator.store.index = SearchIndex(records: records)
    coordinator.store.lastScan = Date()
    coordinator.wallpaperService.source = { _ in fixture }
    let panel = OverlayWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    panel.delegate = coordinator
    panel.launcherStore = coordinator.store
    panel.isReleasedWhenClosed = false
    panel.contentView = NSHostingView(rootView: LauncherView(store: coordinator.store, settings: {}))
    coordinator.window = panel
    for _ in 0..<3 {
        coordinator.show()
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(40))
            try requireNative(NSWorkspace.shared.frontmostApplication?.processIdentifier == host.processIdentifier, "Showing overlay must not activate LaunchDock over the fullscreen host")
            try requireNative(state()["onActiveSpace"] as? Bool == true, "Showing overlay must not leave the host fullscreen Space")
        }
        try requireNative(panel.isVisible && panel.isOnActiveSpace && panel.isKeyWindow, "Nonactivating overlay must be visible and keyboard-capable in the current fullscreen Space")
        guard let field = panel.contentView?.findSearch(), field.currentEditor() != nil else { throw NativeCheckFailure(message: "Fullscreen overlay must focus its search editor") }
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, characters: "1", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 18)!
        panel.sendEvent(key)
        try await Task.sleep(for: .milliseconds(80))
        try requireNative(coordinator.store.query == "1", "Search must accept keys without activating the launcher app")
        coordinator.hide()
        try await Task.sleep(for: .milliseconds(300))
        try requireNative(!panel.isVisible && state()["onActiveSpace"] as? Bool == true)
        try requireNative(NSWorkspace.shared.frontmostApplication?.processIdentifier == host.processIdentifier)
    }
    print("PASS: 3 real foreign-fullscreen overlay cycles with hidden Dock icon preserve Space/frontmost app and accept search keyboard input")
}
