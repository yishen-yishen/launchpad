import AppKit
import SwiftUI
import LaunchDockCore
import ImageIO
import UniformTypeIdentifiers
import Darwin

@main struct PromoCapture {
    @MainActor static func main() {
        Task { @MainActor in
            do { try await record(); exit(0) }
            catch { print("CAPTURE FAILED: \(error)"); exit(1) }
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.run()
    }
    @MainActor static func record() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchDock-Promo-\(UUID())")
        defer { try? FileManager.default.removeItem(at: temp) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let userData = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("app.launchdock.LaunchDock/catalog.json")
        let previous = (try? decoder.decode(CatalogSnapshot.self, from: Data(contentsOf: userData)))?.records ?? []
        let real = try await CatalogService().scan(previous: previous)
        let priorities = ["com.apple.appstore", "com.apple.systempreferences", "com.apple.safari", "com.apple.calculator", "com.apple.notes", "com.apple.ical", "com.apple.preview", "com.apple.shortcuts", "com.apple.terminal", "com.apple.findmy", "com.google.chrome", "com.openai.chat", "com.microsoft.vscode", "com.raycast.macos", "org.telegram.desktop", "com.colliderli.iina", "com.apple.mail", "com.apple.music", "com.apple.mobilesms", "com.apple.photos"]
        var chosen: [AppRecord] = []
        for id in priorities {
            if let app = real.records.first(where: { $0.bundleID?.lowercased() == id }) { chosen.append(app) }
        }
        chosen += real.records.filter { app in !chosen.contains(where: { $0.id == app.id }) }.prefix(max(0,24-chosen.count))
        chosen = Array(chosen.prefix(24))
        guard let calculator = chosen.first(where: { $0.bundleID?.lowercased() == "com.apple.calculator" }), chosen.count >= 12 else { throw Failure("Not enough installed applications") }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("app.launchdock.LaunchDock/Icons-v1")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: cache.path) { try FileManager.default.copyItem(at: cache, to: temp.appendingPathComponent("Icons-v1")) }
        let store = LauncherStore(dataDirectory: temp)
        await store.iconCache.preload(chosen)
        store.records = chosen; store.index = SearchIndex(records: chosen)
        try store.engine.commit { layout in layout.root = chosen.map { .app($0.id) }; layout.directoryGroupingVersion = 1; layout.systemAppGroupingVersion = 1 }
        store.lastScan = Date(); store.iconCache.refresh(chosen)
        store.wallpaper = backdrop()
        let window = OverlayWindow(contentRect: NSRect(x: 80,y: 80,width:1280,height:800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.isOpaque = true; window.backgroundColor = .black; window.launcherStore = store
        let host = NSHostingView(rootView: LauncherView(store: store, settings: {})); host.sizingOptions = []
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        store.launchFeedback = { id in host.findGrid()?.animateLaunch(id) }
        store.hide = { window.animateVisibility(show: false) {} }
        let calculatorWasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.calculator").isEmpty
        defer {
            window.orderOut(nil)
            if !calculatorWasRunning {
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.calculator") { _ = app.terminate() }
            }
        }
        try await Task.sleep(for: .seconds(2))
        host.layoutSubtreeIfNeeded()
        let cgLibrary = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY | RTLD_LOCAL)!
        defer { dlclose(cgLibrary) }
        guard let symbol = dlsym(cgLibrary,"CGWindowListCreateImage") else { throw Failure("Own-window capture unavailable") }
        typealias CopyImage = @convention(c) (CGRect, UInt32, CGWindowID, UInt32) -> Unmanaged<CGImage>?
        let capture = unsafeBitCast(symbol, to: CopyImage.self)
        var lastImage: CGImage?
        func save(_ number: Int) throws {
            guard let image = capture(.null,CGWindowListOption.optionIncludingWindow.rawValue,CGWindowID(window.windowNumber),CGWindowImageOption.boundsIgnoreFraming.rawValue | CGWindowImageOption.nominalResolution.rawValue)?.takeRetainedValue() ?? lastImage else { throw Failure("Own window image missing") }
            lastImage = image
            let url = output.appendingPathComponent(String(format:"frame-%04d.jpg",number))
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw Failure("JPEG destination failed") }
            CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:0.94] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw Failure("Frame write failed") }
        }
        // Fixed-rate scripted interaction with the real LauncherView and engine.
        let fps = 15
        let total = CommandLine.arguments.contains("--pilot") ? 1 : 19 * fps
        var folderID: UUID?
        for frame in 0..<total {
            let started = ContinuousClock.now
            if frame == 35 { store.page = min(1,store.pages-1) }
            if frame == 62 { store.page = 0 }
            if frame >= 84 && frame < 88 {
                if let field = host.findSearch() {
                    field.stringValue = String("Calc".prefix(frame-83))
                    field.delegate?.controlTextDidChange?(Notification(name:NSControl.textDidChangeNotification,object:field))
                }
            }
            if frame == 132 { store.activate(.app(calculator.id)) }
            if frame == 150 {
                window.alphaValue = 1; window.makeKeyAndOrderFront(nil)
                store.query = ""; store.page = 0
            }
            if (165...185).contains(frame), let grid = host.findGrid(), grid.items.count > 1,
               let target = grid.item(at: IndexPath(item:1,section:0))?.imageView {
                let rect = target.convert(target.bounds,to:grid)
                grid.trackDestination(source:grid.items[0],point:NSPoint(x:rect.midX,y:rect.midY))
            }
            if frame == 186, let grid = host.findGrid() {
                _ = grid.commitDestination(); grid.finishDestination()
                folderID = store.engine.document.folders.first?.id
                if let folderID {
                    store.change { try $0.rename(folderID,name:"常用工具") }
                    let third = chosen[4].id
                    if !store.engine.document.folders.contains(where: { $0.apps.contains(third) }) { store.change { try $0.move(.app(third),into:folderID,at:Int.max) } }
                }
            }
            if frame == 210, let folderID { store.activate(.folder(folderID)) }
            if frame == 265 { store.folder = nil }
            host.layoutSubtreeIfNeeded()
            // The final hidden frame is composed from the last visible native view.
            if frame == 140 { window.alphaValue = 1 }
            try save(frame)
            let elapsed = started.duration(to:.now)
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds)/1e18
            if seconds < 1/Double(fps) { try await Task.sleep(for:.seconds(1/Double(fps)-seconds)) }
            if frame % 45 == 0 { print("Captured \(frame)/\(total)"); fflush(stdout) }
        }
        let iconURL = output.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("dist/LaunchDock.app/Contents/Resources/LaunchDock.icns")
        let icon = NSImage(contentsOf:iconURL)?.tiffRepresentation.flatMap { data in NSBitmapImageRep(data:data)?.representation(using:.png,properties:[:]) }
        if let icon { try icon.write(to:output.appendingPathComponent("brand-icon.png")) }
        let manifest: [String:Any] = ["fps":fps,"frames":total,"width":1280,"height":800,"realCatalogCount":real.records.count,"demoAppCount":chosen.count,"note":"Real native LauncherView, actual scanned apps and isolated demo layout; no user layout changes"]
        try JSONSerialization.data(withJSONObject:manifest,options:.prettyPrinted).write(to:output.appendingPathComponent("capture.json"))
        await store.flush()
        print("CAPTURE COMPLETE")
    }
    @MainActor static func backdrop() -> NSImage {
        let image = NSImage(size:NSSize(width:1280,height:800)); image.lockFocus()
        NSGradient(colors:[NSColor(srgbRed:0.13,green:0.18,blue:0.56,alpha:1),NSColor(srgbRed:0.42,green:0.21,blue:0.72,alpha:1),NSColor(srgbRed:0.21,green:0.13,blue:0.48,alpha:1)])!.draw(in:NSRect(x:0,y:0,width:1280,height:800),angle:25)
        image.unlockFocus(); return image
    }
}
struct Failure: Error, CustomStringConvertible { let description:String; init(_ description:String){self.description=description} }
