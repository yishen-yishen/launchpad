import AppKit
import LaunchDockCore

@MainActor func checkLaunchAndIconCache() async throws {
    let fm = FileManager.default
    let directory = fm.temporaryDirectory.appendingPathComponent("LaunchDock-icons-\(UUID())")
    defer { try? fm.removeItem(at: directory) }
    let appURL = directory.appendingPathComponent("App.app")
    let resources = appURL.appendingPathComponent("Contents/Resources")
    try fm.createDirectory(at: resources, withIntermediateDirectories: true)
    let info = ["CFBundlePackageType":"APPL", "CFBundleIdentifier":"test.launch-icons", "CFBundleIconFile":"AppIcon.png"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: appURL.appendingPathComponent("Contents/Info.plist"))
    func png(_ color: NSColor) throws -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<32 { for x in 0..<32 { bitmap.setColor(color, atX: x, y: y) } }
        return try requirePNG(bitmap)
    }
    let iconURL = resources.appendingPathComponent("AppIcon.png")
    try png(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)).write(to: iconURL, options: .atomic)
    let record = AppRecord(path: appURL.path, bundleID: "test.launch-icons", name: "Fixture")
    let cacheURL = directory.appendingPathComponent("Cache")
    let disk = IconDiskCache(directory: cacheURL)
    guard let first = await disk.refresh(record, hasImage: false), let image = NSImage(data: first) else { throw NativeCheckFailure(message: "Cold icon render must return PNG") }
    let renderedOnMain = await disk.lastRenderWasMainThread
    try requireNative(!renderedOnMain, "Workspace icon loading/rendering must run off the main thread")
    try requireNative(NSBitmapImageRep(data: image.tiffRepresentation!)!.pixelsWide == 256, "Persist normalized high-resolution icons")
    let unchanged = await disk.refresh(record, hasImage: true)
    let extractionCount = await disk.extractionCount
    try requireNative(unchanged == nil && extractionCount == 1, "Unchanged metadata must reuse cache without extracting again")
    let cache = AppIconCache(directory: cacheURL)
    await cache.preload([record])
    let restored = cache.image(for: record)
    let red = NSBitmapImageRep(data: restored.tiffRepresentation!)!.colorAt(x: 128,y: 128)!.usingColorSpace(.deviceRGB)!
    try requireNative(red.redComponent > 0.7 && red.redComponent - red.greenComponent > 0.5 && red.redComponent - red.blueComponent > 0.5, "A new cache instance must immediately display saved pixels; RGB=\(red.redComponent),\(red.greenComponent),\(red.blueComponent), alpha=\(red.alphaComponent)")
    try png(NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)).write(to: iconURL, options: .atomic)
    try fm.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: iconURL.path)
    cache.refresh([record])
    try await waitForNative("Updated icon pixels arrive without replacing the catalog") {
        let refreshed = cache.image(for: record)
        guard let data = refreshed.tiffRepresentation, let pixels = NSBitmapImageRep(data: data), pixels.pixelsWide >= 129,
              let color = pixels.colorAt(x: 128, y: 128)?.usingColorSpace(.deviceRGB) else { return false }
        return color.greenComponent > 0.7 && color.greenComponent - color.redComponent > 0.5 && color.greenComponent - color.blueComponent > 0.5
    }
    try Data("broken".utf8).write(to: cacheURL.appendingPathComponent(record.id.uuidString+".png"))
    let repaired = IconDiskCache(directory: cacheURL)
    let repairedData = await repaired.refresh(record, hasImage: false)
    try requireNative(repairedData != nil, "Corrupt disk cache must regenerate the actual icon")
    print("PASS: background 256px icon rendering, disk reuse across cache instances, unchanged skip, live update, corrupt-cache repair")

    let store = LauncherStore(dataDirectory: directory.appendingPathComponent("Store"))
    store.records = [record]; try store.engine.reconcile([record])
    let capture = LaunchCapture()
    store.launchFeedback = { _ in capture.events.append("zoom") }
    store.hide = { capture.events.append("hide") }
    store.showLaunchFailure = { capture.events.append("failureShown") }
    store.openApplication = { _, completion in
        Task { @MainActor in capture.events.append("request"); capture.completion = completion }
    }
    store.activate(.app(record.id)); store.activate(.app(record.id))
    try requireNative(capture.events == ["zoom"], "Click must provide immediate feedback and suppress duplicate launches")
    try await waitForNative("Launch request starts after immediate dismissal") { capture.completion != nil }
    try requireNative(capture.events == ["zoom", "hide", "request"] && store.pendingLaunch.contains(record.id), "Launcher must hide while the target startup completion is still pending")
    capture.completion?(nil)
    try await waitForNative("Successful request completes") { !store.pendingLaunch.contains(record.id) }
    try requireNative(capture.events == ["zoom", "hide", "request"], "Completion must not dismiss a launcher the user reopened later")
    capture.completion = nil
    store.activate(.app(record.id))
    try await waitForNative("Second request") { capture.completion != nil }
    capture.completion?("Intentional test failure")
    try await waitForNative("Launch failure is surfaced after dismissal") { capture.events.last == "failureShown" }
    try requireNative(store.message?.contains("Intentional test failure") == true && store.pendingLaunch.isEmpty)
    print("PASS: immediate feedback, hide before slow startup completion, duplicate suppression, failure feedback")
}
private func requirePNG(_ bitmap: NSBitmapImageRep) throws -> Data {
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NativeCheckFailure(message: "Missing PNG fixture") }
    return data
}
@MainActor private final class LaunchCapture {
    var events: [String] = []
    var completion: (@Sendable (String?) -> Void)?
}
