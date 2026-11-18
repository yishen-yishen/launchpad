import AppKit
import SwiftUI
import LaunchDockCore

@main struct InteractionChecks {
    @MainActor static func main() {
        Task { @MainActor in
            do {
                if ProcessInfo.processInfo.environment["LAUNCHDOCK_CHECK_FORCE_FAILURE"] == "1" {
                    try requireNative(false, "Intentional harness failure-path check")
                }
                try await runChecks(); finish(0)
            }
            catch {
                print("FAIL: \(error)"); fflush(stdout)
                finish(1)
            }
        }
        NSApplication.shared.run()
    }
    static func finish(_ status: Int32) -> Never {
        if let path = ProcessInfo.processInfo.environment["LAUNCHDOCK_CHECK_RESULT"] {
            try? Data("\(status)\n".utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        fflush(stdout)
        exit(status)
    }
    @MainActor static func runChecks() async throws {
        try await checkLaunchAndIconCache()
        guard let wallpaperScreen = NSScreen.main else { throw NativeCheckFailure(message: "Missing wallpaper screen") }
        let fixtureURL = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchDock-wallpaper-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let pixels = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<40 { for x in 0..<80 { pixels.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y) } }
        try pixels.representation(using: .png, properties: [:])!.write(to: fixtureURL)
        let wallpaperService = WallpaperService()
        wallpaperService.source = { _ in fixtureURL }
        var captures = 0
        wallpaperService.capture = { _ in captures += 1; return NSImage(cgImage: pixels.cgImage!, size: NSSize(width: 80, height: 40)) }
        let fileWallpaper = await wallpaperService.snapshot(for: wallpaperScreen)
        try requireNative(fileWallpaper.image?.size == wallpaperScreen.frame.size && captures == 0, "Static wallpaper must render from its file without screenshot permission")
        let rendered = NSBitmapImageRep(data: fileWallpaper.image!.tiffRepresentation!)!
        let renderedColor = rendered.colorAt(x: rendered.pixelsWide/2, y: rendered.pixelsHigh/2)!.usingColorSpace(.deviceRGB)!
        try requireNative(renderedColor.redComponent > 0.7 && renderedColor.redComponent - renderedColor.greenComponent > 0.5 && renderedColor.redComponent - renderedColor.blueComponent > 0.5 && renderedColor.alphaComponent > 0.95, "Loaded wallpaper must actually render its file pixels")
        wallpaperService.source = { _ in URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic") }
        let dynamic = await wallpaperService.snapshot(for: wallpaperScreen)
        try requireNative(dynamic.image != nil && captures == 1, "Dynamic wallpaper refreshes once for each explicit snapshot")
        try await Task.sleep(for: .milliseconds(80))
        try requireNative(captures == 1, "Wallpaper must not keep capturing while visible")
        let blackPixels = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<8 { for x in 0..<8 { blackPixels.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1), atX: x, y: y) } }
        wallpaperService.capture = { _ in NSImage(cgImage: blackPixels.cgImage!, size: NSSize(width: 8, height: 8)) }
        wallpaperService.source = { _ in URL(fileURLWithPath: "/nonexistent/dynamic.mov") }
        let blackCapture = await wallpaperService.snapshot(for: wallpaperScreen)
        try requireNative(blackCapture.image == nil && blackCapture.description.contains("黑色或透明"), "A returned black image must not be reported as wallpaper success")
        try requireNative(wallpaperService.lastCaptureStatistics?.isEmpty == true)
        let screenRect = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let level = Int(CGWindowLevelForKey(.desktopWindow))
        let candidates = DesktopWallpaperReader.candidates([
            .init(id: 1, layer: level-2, frame: screenRect),
            .init(id: 2, layer: level-1, frame: screenRect),
            .init(id: 3, layer: 0, frame: screenRect),
            .init(id: 4, layer: level-1, frame: CGRect(x: 0,y: 0,width: 10,height: 10)),
            .init(id: 5, layer: level, frame: screenRect.offsetBy(dx: 3000,dy: 0))
        ], display: screenRect)
        try requireNative(candidates.map(\.id) == [2,1], "Only full-size desktop-background windows on the target display are eligible")
        wallpaperService.capture = { _ in throw DesktopWallpaperReader.ReadError.unavailable }
        let failedCapture = await wallpaperService.snapshot(for: wallpaperScreen)
        try requireNative(failedCapture.image == nil, "Failed dynamic capture must not reveal live application windows")
        wallpaperService.capture = { _ in
            try? await Task.sleep(for: .milliseconds(60))
            return NSImage(cgImage: pixels.cgImage!, size: NSSize(width: 80, height: 40))
        }
        let cancelledRefresh = Task { await wallpaperService.snapshot(for: wallpaperScreen) }
        await Task.yield(); cancelledRefresh.cancel()
        let cancelledSnapshot = await cancelledRefresh.value
        try requireNative(cancelledSnapshot.image == nil, "A cancelled screenshot must never be published")
        try requireNative(failedCapture.description.contains("系统桌面背景图像接口不可用"), "Capture failures must expose the real reason rather than generic permission advice")
        // A DefaultDesktop name is a valid resource, not grounds for rejection.
        let fallbackDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Wallpaper-fallback-\(UUID())")
        try FileManager.default.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fallbackDirectory) }
        let fallbackURL = fallbackDirectory.appendingPathComponent("DefaultDesktop.heic")
        try FileManager.default.copyItem(at: fixtureURL, to: fallbackURL)
        wallpaperService.source = { _ in fallbackURL }
        wallpaperService.capture = { _ in throw DesktopWallpaperReader.ReadError.unavailable }
        let fallback = await wallpaperService.snapshot(for: wallpaperScreen)
        try requireNative(fallback.image != nil && wallpaperService.strategy == "wallpaper-file", "Compatibility failure must fall back to a valid primary image without permissions")
        print("PASS: permission-free wallpaper lifecycle, primary file fallback, desktop-only allowlist, black-image rejection")
        let app = NSApplication.shared
        let checkDelegate = NativeCheckDelegate()
        app.delegate = checkDelegate
        defer { withExtendedLifetime(checkDelegate) {} }
        app.setActivationPolicy(.regular)
        let cancelledCoordinator = AppCoordinator()
        cancelledCoordinator.store.lastScan = Date()
        cancelledCoordinator.wallpaperService.source = { _ in URL(fileURLWithPath: "/nonexistent/dynamic.mov") }
        cancelledCoordinator.wallpaperService.capture = { _ in
            try? await Task.sleep(for: .milliseconds(100))
            return NSImage(cgImage: pixels.cgImage!, size: NSSize(width: 80, height: 40))
        }
        cancelledCoordinator.window = OverlayWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        cancelledCoordinator.window.isReleasedWhenClosed = false
        cancelledCoordinator.show()
        try await Task.sleep(for: .milliseconds(20))
        cancelledCoordinator.hide()
        try await Task.sleep(for: .milliseconds(300))
        try requireNative(!cancelledCoordinator.wantsVisible && !cancelledCoordinator.window.isVisible && cancelledCoordinator.store.wallpaper == nil, "Closing during capture must discard the late image and never reopen launcher")
        print("PASS: hide during wallpaper preparation cancels late presentation")
        let store = LauncherStore(dataDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("LaunchDock-native-\(UUID())"))
        store.records = (0..<70).map { AppRecord(path: "/nonexistent/\($0).app", name: "Check \($0)") }
        try store.engine.reconcile(store.records)
        let window = OverlayWindow(contentRect: NSRect(x: 0,y: 0,width: 1920,height: 1080), styleMask: [.borderless], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.launcherStore = store
        window.registerForDraggedTypes([.string])
        var dismissRequests = 0
        store.hide = { dismissRequests += 1 }
        let host = NSHostingView(rootView: LauncherView(store: store, settings: {}))
        host.sizingOptions = []; window.contentView = host
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        guard let grid = host.findGrid(), let scroll = grid.enclosingScrollView else { throw NativeCheckFailure(message: "Missing native collection") }
        store.wallpaper = fileWallpaper.image
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        guard let viewPixels = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw NativeCheckFailure(message: "Missing background rendering") }
        host.cacheDisplay(in: host.bounds, to: viewPixels)
        let backgroundColor = viewPixels.colorAt(x: 5, y: 5)!.usingColorSpace(.deviceRGB)!
        try requireNative(backgroundColor.redComponent > 0.35 && backgroundColor.redComponent > backgroundColor.greenComponent + 0.2, "Actual launcher must render the supplied wallpaper through blur/overlay rather than turn it black")
        store.wallpaper = nil
        print("PASS: actual SwiftUI launcher renders colored wallpaper through blur and shade")

        try await waitForNative("Initial grid projection: capacity=\(store.capacity), items=\(grid.items.count)") {
            host.layoutSubtreeIfNeeded()
            return store.capacity == 28 && grid.items.count == 28
        }
        try requireNative(host.bounds.width == 1920)
        try requireNative(grid.columns == 7, "Expected seven columns")
        try requireNative(store.capacity == 28, "Expected spacious 7 × 4 page capacity")
        try requireNative(grid.items.count == 28, "Expected one page of items")
        guard let menuCell = grid.item(at: 0), let menuImage = menuCell.imageView, let menuLabel = menuCell.textField else { throw NativeCheckFailure(message: "Missing context menu cell") }
        func rightClick(_ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let menuPoint = menuImage.convert(NSPoint(x: menuImage.bounds.midX, y: menuImage.bounds.midY), to: nil)
        let menuEvent = rightClick(menuPoint)
        let menu = window.contextMenu(for: menuEvent)
        try requireNative(menu.items.map(\.title) == ["在访达中显示"] && menu.items.allSatisfy { $0.submenu == nil })
        try requireNative(menu.items[0].isEnabled)
        try requireNative(store.finderURL(for: grid.items[0])?.path == store.records.first { $0.id == grid.items[0].id }?.path)
        let labelPoint = menuLabel.convert(NSPoint(x: menuLabel.bounds.midX, y: menuLabel.bounds.midY), to: nil)
        try requireNative(window.contextMenu(for: rightClick(labelPoint)).items.map(\.title) == ["在访达中显示"])
        let blankPoints = [NSPoint(x: 5, y: 5),
            menuCell.view.convert(NSPoint(x: 2, y: 2), to: nil),
            menuLabel.convert(NSPoint(x: 1, y: menuLabel.bounds.midY), to: nil)]
        for point in blankPoints {
            let event = rightClick(point)
            try requireNative(grid.menu(for: event) == nil, "Cell padding must not show an item menu")
            try requireNative(window.contextMenu(for: event).items.map(\.title) == ["设置…", "重启", "退出"], "All blank regions must show the application menu")
        }
        var applicationActions: [String] = []
        store.showSettings = { applicationActions.append("settings") }
        store.restartApplication = { applicationActions.append("restart") }
        store.quitApplication = { applicationActions.append("quit") }
        for entry in window.contextMenu(for: rightClick(blankPoints[0])).items {
            try requireNative(NSApp.sendAction(entry.action!, to: entry.target, from: entry))
        }
        try requireNative(applicationActions == ["settings", "restart", "quit"], "Background menu must dispatch each application action exactly once")
        print("PASS: icon/name item menu, cell/margin background menu, settings/restart/quit dispatch")
        grid.animateLaunch(grid.items[0].id)
        try await pumpNativeEvents(for: 0.07)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let scale = (menuImage.layer?.presentation()?.value(forKeyPath: "transform.scale.x") as? NSNumber)?.doubleValue ?? 1
            try requireNative(menuImage.layer?.animation(forKey: "launchZoom") != nil && scale > 1 && scale <= 1.21, "Click feedback must render a real enlarged icon before hiding")
        }
        grid.resetLaunchFeedback()
        print("PASS: actual icon zoom intermediate frame; feedback resets without changing cell geometry")
        let emptyClick = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 5,y: 5), modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        sendBackgroundClick(window, event: emptyClick)
        try requireNative(dismissRequests == 1, "Window margin must dismiss launcher")
        guard let search = host.findSearch(), let searchCell = search.cell as? LauncherSearchCell else { throw NativeCheckFailure(message: "Missing search cell") }
        try requireNative(search.isEditable && search.isSelectable, "Search field must accept editing after installing its custom cell")
        let iconRect = searchCell.searchButtonRect(forBounds: search.bounds)
        let textRect = searchCell.searchTextRect(forBounds: search.bounds)
        try requireNative(textRect.minX >= iconRect.maxX+6, "Search glyph and placeholder must have separate rectangles")
        window.makeFirstResponder(grid)
        let searchPoint = search.convert(NSPoint(x: textRect.midX,y: textRect.midY), to: nil)
        let searchClick = NSEvent.mouseEvent(with: .leftMouseDown, location: searchPoint, modifierFlags: [], timestamp: 2, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
        try requireNative(!window.routeLauncherEvent(searchClick), "Search controls must not dismiss")
        let searchUp = NSEvent.mouseEvent(with: .leftMouseUp, location: searchPoint, modifierFlags: [], timestamp: 2.1, windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 0)!
        NSApp.postEvent(searchUp, atStart: true)
        window.sendEvent(searchClick)
        guard let editor = search.currentEditor() as? NSTextView else { throw NativeCheckFailure(message: "Clicking search must create its text editor") }
        try requireNative(window.firstResponder === editor, "Search click must transfer keyboard focus from the grid")
        let editorRect = search.convert(editor.convert(editor.bounds, to: nil), from: nil)
        let textStart = editorRect.minX + editor.textContainerOrigin.x + (editor.textContainer?.lineFragmentPadding ?? 0)
        try requireNative(textStart >= iconRect.maxX+6, "Actual input text must also clear search glyph")
        store.index = SearchIndex(records: store.records)
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 3, windowNumber: window.windowNumber, context: nil, characters: "1", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 18)!
        window.sendEvent(key)
        try await Task.sleep(for: .milliseconds(150))
        try requireNative(search.stringValue == "1" && store.query == "1", "Typing must update both search field and query")
        try requireNative(!store.visible.isEmpty && store.visible.count < store.records.count && grid.items == store.displayed, "Typing must render filtered results")
        editor.selectAll(nil); editor.deleteBackward(nil)
        try await Task.sleep(for: .milliseconds(150))
        try requireNative(search.stringValue.isEmpty && store.query.isEmpty && grid.items.count == 28, "Deleting search must restore the root page")
        try requireNative(dismissRequests == 1, "Clicking and editing search must not dismiss the launcher")
        print("PASS: search click acquires editor, keyboard input filters results, clearing restores root")
        let rect = scroll.convert(scroll.bounds, to: host)
        try requireNative(abs(rect.midX-host.bounds.midX) < 2, "Grid must be centered across the full window")
        try requireNative(abs(rect.minX) < 1 && abs(rect.width - host.bounds.width) < 1, "Root page viewport must span the entire window")
        guard let pageLayout = grid.collectionViewLayout as? NSCollectionViewFlowLayout else { throw NativeCheckFailure(message: "Missing page layout") }
        try requireNative(abs(pageLayout.sectionInset.left - host.bounds.width*0.15) < 4 && pageLayout.sectionInset.left == pageLayout.sectionInset.right, "Full-width pages must retain symmetric icon margins")
        guard let attributes = grid.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)) else { throw NativeCheckFailure(message: "Missing cell") }
        try requireNative(grid.item(at: IndexPath(item: 0, section: 0))?.imageView?.frame.width == AppCell.preferredSize)
        try requireNative(grid.item(at: IndexPath(item: 0, section: 0))?.textField?.textColor == .white)
        let point = grid.convert(NSPoint(x: attributes.frame.midX,y: attributes.frame.midY), to: nil)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        grid.mouseDown(with: down)
        try await Task.sleep(for: .milliseconds(650))
        try requireNative(store.editing, "500 ms hold must enter edit mode")
        grid.cancelPointer()
        store.editing = false
        let dragDown = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 300,y: 20), modifierFlags: [], timestamp: 3, windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 1)!
        let dragMove = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 180,y: 20), modifierFlags: [], timestamp: 4, windowNumber: window.windowNumber, context: nil, eventNumber: 4, clickCount: 1, pressure: 1)!
        let dragUp = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 180,y: 20), modifierFlags: [], timestamp: 5, windowNumber: window.windowNumber, context: nil, eventNumber: 5, clickCount: 1, pressure: 0)!
        window.sendEvent(dragDown)
        try requireNative(dismissRequests == 1, "Mouse down must wait for click-versus-drag decision")
        window.sendEvent(dragMove); window.sendEvent(dragUp)
        try requireNative(store.page == 1 && dismissRequests == 1, "Horizontal background drag must page without dismissing")
        store.page = 0
        try await Task.sleep(for: .milliseconds(100))
        // One threshold-crossing wheel event tests routing without assuming
        // three costly native snapshot renders finish within one wheel burst.
        do {
            let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -3, wheel2: 0, wheel3: 0)!
            cg.location = CGPoint(x: 5,y: 5)
            window.sendEvent(NSEvent(cgEvent: cg)!)
        }
        try requireNative(store.page == 1, "Window margins must route wheel to page navigation; page=\(store.page), query=\(store.query), dragging=\(grid.dragActive)")
        try await Task.sleep(for: .milliseconds(50))
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            try requireNative(scroll.subviews.contains { $0.identifier?.rawValue == "pageTransitionSnapshot" }, "Page change must install outgoing whole-page snapshot")
            try requireNative(scroll.subviews.contains { $0.identifier?.rawValue == "pageTransitionIncoming" }, "Page change must install incoming whole-page snapshot")
            let snapshots = scroll.subviews.filter { $0 is PageSnapshotView }
            try requireNative(snapshots.count == 2 && snapshots.allSatisfy { abs($0.bounds.width-host.bounds.width) < 1 }, "Both moving pages must include the full window width and side margins")
            let outgoing = snapshots.first { $0.identifier?.rawValue == "pageTransitionSnapshot" }!
            let incoming = snapshots.first { $0.identifier?.rawValue == "pageTransitionIncoming" }!
            try requireNative(abs(incoming.frame.minX - outgoing.frame.minX - host.bounds.width) < 4, "Adjacent moving pages must remain one full screen width apart")
            guard let outgoingFrame = outgoing.layer?.presentation()?.frame,
                  let incomingFrame = incoming.layer?.presentation()?.frame else { throw NativeCheckFailure(message: "Missing rendered page animation frames") }
            try requireNative(outgoingFrame.minX < 0 && outgoingFrame.minX > -host.bounds.width && incomingFrame.minX > 0 && incomingFrame.minX < host.bounds.width, "Whole pages must render intermediate horizontal animation frames")
            try requireNative(abs(incomingFrame.minX - outgoingFrame.minX - host.bounds.width) < 4, "Rendered pages must remain one full screen width apart")
            print("PASS: full-window page snapshots and travel distance; centered icon margins preserved")
        }
        store.page = 0
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        guard let targetImage = grid.item(at: IndexPath(item: 1, section: 0))?.imageView else { throw NativeCheckFailure(message: "Missing merge target") }
        let targetRect = targetImage.convert(targetImage.bounds, to: grid)
        let source = grid.items[0], target = grid.items[1]
        let before = store.engine.document.revision
        grid.trackDestination(source: source, point: NSPoint(x: targetRect.midX,y: targetRect.midY))
        try requireNative(grid.mergeTarget == target, "Icon overlap must merge immediately without a dwell")
        try requireNative(store.engine.document.revision == before, "Hover must not mutate layout")
        try requireNative(grid.commitDestination(), "Drop must commit folder creation")
        try requireNative(store.engine.document.folders.first?.apps == [target.id,source.id])
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        guard let folder = store.engine.document.folders.first,
              let folderIndex = grid.items.firstIndex(of: .folder(folder.id)),
              let folderImage = grid.item(at: IndexPath(item: folderIndex, section: 0))?.imageView,
              let third = grid.items.first(where: { if case .app = $0 { return true }; return false }) else { throw NativeCheckFailure(message: "Missing folder") }
        let folderRect = folderImage.convert(folderImage.bounds, to: grid)
        grid.trackDestination(source: third, point: NSPoint(x: folderRect.midX,y: folderRect.midY))
        try requireNative(grid.mergeTarget == .folder(folder.id), "Existing folder must accept immediate drop")
        try requireNative(grid.commitDestination(), "Drop into existing folder must commit")
        try requireNative(store.engine.document.folders.first?.apps.count == 3)
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let reorderSource = grid.items.first { if case .app = $0 { return true }; return false }!
        let foldersBefore = store.engine.document.folders
        let targetPath = IndexPath(item: 5, section: 0)
        let reorderFrame = grid.layoutAttributesForItem(at: targetPath)!.frame
        grid.trackDestination(source: reorderSource, point: NSPoint(x: reorderFrame.maxX-2,y: reorderFrame.maxY-2))
        try requireNative(grid.mergeTarget == nil, "Cell margin must reorder, not merge")
        try requireNative(grid.commitDestination())
        try requireNative(store.engine.document.folders == foldersBefore)
        for cell in grid.visibleItems() { try requireNative(cell.view.layer?.borderWidth == 0) }
        try await pumpNativeEvents(for: 0.3)
        let stableFolder = store.engine.document.folders.first!.id
        let rootItemsBefore = grid.items
        let rootFrameBefore = grid.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
        let rootCellBefore = grid.item(at: IndexPath(item: 0, section: 0))!
        let rootCapacityBefore = store.capacity
        store.folder = stableFolder
        try await pumpNativeEvents(for: 0.07)
        let folderOverlay = host.findFolderOverlay()!
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            try requireNative(folderOverlay.fadeInProgress, "Opening must install a native opacity animation")
            try requireNative(folderOverlay.presentationOpacity > 0 && folderOverlay.presentationOpacity < 1, "Opening must render an intermediate opacity frame")
            try requireNative(folderOverlay.presentationScale > 0.94 && folderOverlay.presentationScale < 1, "Opening folder must render an intermediate centered scale")
        }
        try await pumpNativeEvents(for: 0.33)
        try requireNative(host.findGrid() !== grid && !grid.isActiveContext)
        try requireNative(grid.items == rootItemsBefore && store.rootCapacity == rootCapacityBefore, "Opening folder cannot reproject the retained root: items=\(grid.items == rootItemsBefore), capacities=\(rootCapacityBefore)/\(store.rootCapacity)")
        guard let folderTitle = host.findFolderTitle() else { throw NativeCheckFailure(message: "Missing editable folder title") }
        let titlePoint = folderTitle.convert(NSPoint(x: folderTitle.bounds.midX, y: folderTitle.bounds.midY), to: nil)
        let titleClick = NSEvent.mouseEvent(with: .leftMouseDown, location: titlePoint, modifierFlags: [], timestamp: 10, windowNumber: window.windowNumber, context: nil, eventNumber: 10, clickCount: 1, pressure: 1)!
        try requireNative(!window.routeLauncherEvent(titleClick), "Folder title must be protected from background dismissal")
        func editTitle(_ text: String, cancel: Bool = false) throws {
            folderTitle.mouseDown(with: titleClick)
            guard let editor = folderTitle.currentEditor() as? NSTextView else { throw NativeCheckFailure(message: "Clicking title must acquire the native text editor") }
            try requireNative(folderTitle.isTitleEditing && folderTitle.isEditable, "Title click must keep editing active")
            editor.selectAll(nil); editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: cancel ? "\u{1b}" : "\r", charactersIgnoringModifiers: cancel ? "\u{1b}" : "\r", isARepeat: false, keyCode: cancel ? 53 : 36)!
            window.sendEvent(key)
        }
        try editTitle("  工作工具  ")
        try await pumpNativeEvents(for: 0.08)
        try requireNative(store.name(.folder(stableFolder)) == "工作工具" && folderTitle.stringValue == "工作工具", "Return must commit and trim folder name; model=\(store.name(.folder(stableFolder))), field=\(folderTitle.stringValue), editing=\(folderTitle.isTitleEditing), editor=\(String(describing: folderTitle.currentEditor()?.string)), message=\(String(describing: store.message))")
        try requireNative(store.folder == stableFolder && !folderTitle.isTitleEditing, "Committing title must keep folder open and leave editing")
        try editTitle("取消的名称", cancel: true)
        try requireNative(store.name(.folder(stableFolder)) == "工作工具" && folderTitle.stringValue == "工作工具", "Esc must cancel title draft without closing the folder")
        try editTitle("   ")
        try requireNative(store.name(.folder(stableFolder)) == "工作工具", "An empty name must preserve the existing title")
        store.message = nil
        await store.flush()
        let (renamedLayout, _, _) = try await store.persistence.load()
        try requireNative(renamedLayout.folders.first(where: { $0.id == stableFolder })?.name == "工作工具", "Native title rename must persist to disk")
        print("PASS: native folder title click/edit, Return commit, Esc cancel, empty rejection, persisted name")
        let retiringGrid = host.findGrid()!
        let retiringScroll = retiringGrid.enclosingScrollView!
        let retiringSize = retiringScroll.frame.size
        let retiringItems = retiringGrid.items
        try requireNative(retiringScroll.hasVerticalScroller == false && retiringScroll.hasHorizontalScroller == false)
        store.folder = nil
        for sample in 0..<12 {
            try await pumpNativeEvents(for: 0.02)
            if sample == 2 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                try requireNative(folderOverlay.fadeInProgress, "Closing must install a native opacity animation")
                try requireNative(folderOverlay.presentationOpacity > 0 && folderOverlay.presentationOpacity < 1, "Closing must render an intermediate opacity frame")
                try requireNative(folderOverlay.presentationScale > 0.94 && folderOverlay.presentationScale < 1, "Closing folder must render an intermediate centered scale")
            }
            try requireNative(retiringGrid.items == retiringItems, "Fading folder cannot be replaced by root data")
            try requireNative(retiringScroll.frame.size == retiringSize, "Folder width/height must not change during closing")
            retiringScroll.flashScrollers()
            try requireNative(!retiringScroll.hasVerticalScroller && !retiringScroll.hasHorizontalScroller, "No scrollbar may flash during closing")
        }
        try await pumpNativeEvents(for: 0.15)
        try requireNative(host.findGrid() === grid, "Closing folder must reuse the original root collection")
        try requireNative(store.capacity == rootCapacityBefore && grid.items == rootItemsBefore)
        try requireNative(grid.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame == rootFrameBefore)
        try requireNative(grid.item(at: IndexPath(item: 0, section: 0)) === rootCellBefore, "Root cells must not be recreated by folder toggle")
        print("PASS: opening/closing have rendered intermediate opacity frames; folder size/content fixed, no scrollbars, root stable")
        // Reusing the overlay must not reuse another folder's collection context.
        let freeIDs = store.engine.document.root.compactMap { item -> UUID? in
            if case .app(let id) = item { return id }; return nil
        }
        store.change { try $0.createFolder(source: freeIDs[0], target: freeIDs[1]) }
        guard let secondFolder = store.engine.document.folders.first(where: { $0.id != stableFolder }) else {
            throw NativeCheckFailure(message: "Missing second folder fixture")
        }
        for id in [stableFolder, secondFolder.id, stableFolder, secondFolder.id] {
            store.folder = id
            try await pumpNativeEvents(for: 0.4)
            guard let active = host.findGrid(), let expected = store.engine.document.folders.first(where: { $0.id == id }) else {
                throw NativeCheckFailure(message: "Opening another folder must expose its active grid, not retain the previous folder")
            }
            try requireNative(active.folderContextID == id && active.items == expected.apps.map(Item.app), "Folder grid must show the selected folder's actual members")
            let names = active.visibleItems().compactMap { $0.textField?.stringValue }
            try requireNative(!names.isEmpty && names.allSatisfy { name in expected.apps.contains { store.name(.app($0)) == name } }, "Rendered folder labels must belong to the selected folder")
            store.folder = nil
            // Reopen another folder before the closing transition completes.
            try await pumpNativeEvents(for: 0.06)
        }
        try await pumpNativeEvents(for: 0.4)
        try requireNative(host.findGrid() === grid, "Switching folders must retain the original root grid")
        print("PASS: alternating folders show their own members and labels, including interrupted close/open")
        let openFolderID = store.engine.document.folders.first!.id
        store.folder = openFolderID
        try await pumpNativeEvents(for: 0.5)
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: URL(fileURLWithPath: "/tmp/launchdock-folder-panel-check.png")) }
        }
        for app in store.records.prefix(32) where !(store.engine.document.folders.first { $0.id == openFolderID }?.apps.contains(app.id) ?? false) {
            try store.engine.move(.app(app.id), into: openFolderID, at: Int.max)
        }
        store.folder = openFolderID
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        guard let folderGrid = host.findGrid(), let folderScroll = folderGrid.enclosingScrollView else { throw NativeCheckFailure(message: "Missing folder panel grid") }
        try requireNative(host.findSearch() == nil, "Root search must not remain interactive behind folder")
        let panelRect = folderScroll.convert(folderScroll.bounds, to: host)
        try requireNative(panelRect.width < host.bounds.width*0.90 && host.bounds.contains(panelRect) && panelRect.height > host.bounds.height*0.65, "Large folders must use available height while keeping fixed width and staying within the screen")
        let inside = folderScroll.convert(NSPoint(x: folderScroll.bounds.maxX-3,y: folderScroll.bounds.maxY-3), to: nil)
        let insideClick = NSEvent.mouseEvent(with: .leftMouseDown, location: inside, modifierFlags: [], timestamp: 3, windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 1)!
        try requireNative(!window.routeLauncherEvent(insideClick))
        try requireNative(store.folder == openFolderID && dismissRequests == 1, "Folder interior must not dismiss")
        try requireNative(store.pages > 1)
        // One threshold-crossing wheel event tests routing without assuming
        // three costly native snapshot renders finish within one wheel burst.
        do {
            let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -3, wheel2: 0, wheel3: 0)!
            cg.location = CGPoint(x: 5,y: 5); window.sendEvent(NSEvent(cgEvent: cg)!)
        }
        try requireNative(store.page == 1, "Outside folder, wheel must page the open folder")
        sendBackgroundClick(window, event: emptyClick)
        try requireNative(store.folder == nil && dismissRequests == 1, "Outside click must close only the folder")
        try await Task.sleep(for: .milliseconds(300))
        for closeWait in [0.35, 0.06] {
            store.folder = openFolderID
            for _ in 0..<12 {
                try await pumpNativeEvents(for: 0.02)
                guard let fresh = host.findGrid(), let freshScroll = fresh.enclosingScrollView else {
                    throw NativeCheckFailure(message: "Reopening must immediately expose the folder grid")
                }
                try requireNative(store.page == 0 && fresh.lastRenderedPage == 0 && fresh.items == store.displayed, "Reopening must show page one directly")
                try requireNative(!freshScroll.subviews.contains { $0 is PageSnapshotView }, "Reopening cannot animate a stale page back to page one")
            }
            store.page = 1
            try await pumpNativeEvents(for: 0.4)
            store.folder = nil
            try await pumpNativeEvents(for: closeWait)
        }
        try await pumpNativeEvents(for: 0.35)
        print("PASS: multipage folder reopens directly on page one with no reset slide, including interrupted closing")
        sendBackgroundClick(window, event: emptyClick)
        try requireNative(dismissRequests == 2, "Next outside click dismisses launcher")
        let extractionID = store.engine.document.folders.first!.id
        store.folder = extractionID
        try await pumpNativeEvents(for: 0.5)
        host.layoutSubtreeIfNeeded()
        let extractionGrid = host.findGrid()!
        let extractionApp = store.engine.document.folders.first!.apps[0]
        try requireNative(window.acceptsFolderExit(source: extractionGrid, id: extractionApp, at: NSPoint(x: 5,y: 5)), "Folder app drop outside panel must be accepted")
        let interior = extractionGrid.convert(NSPoint(x: extractionGrid.bounds.midX,y: extractionGrid.bounds.midY), to: nil)
        try requireNative(!window.acceptsFolderExit(source: extractionGrid, id: extractionApp, at: interior))
        try requireNative(store.moveAppOutOfFolder(extractionApp))
        try requireNative(store.folder == nil && store.engine.document.root.contains(.app(extractionApp)))
        // A two-member folder normalizes to its survivor. Both drag-out and menu transactions must close the stale context.
        let pair = store.engine.document.root.compactMap { if case .app(let id) = $0 { return id }; return nil }.prefix(2)
        let pairIDs = Array(pair)
        store.change { try $0.createFolder(source: pairIDs[0], target: pairIDs[1]) }
        let tinyFolder = store.engine.document.folders.first { $0.apps.contains(pairIDs[0]) }!
        store.folder = tinyFolder.id
        try requireNative(store.moveAppOutOfFolder(pairIDs[0]))
        try requireNative(store.folder == nil && !store.engine.document.folders.contains { $0.id == tinyFolder.id })
        try requireNative(store.engine.document.root.contains(.app(pairIDs[0])) && store.engine.document.root.contains(.app(pairIDs[1])))
        store.change { try $0.createFolder(source: pairIDs[0], target: pairIDs[1]) }
        store.folder = store.engine.document.folders.first { $0.apps.contains(pairIDs[0]) }!.id
        store.change { try $0.move(.app(pairIDs[0]), at: 0) }
        try requireNative(store.folder == nil, "Any accepted transaction that dissolves the open folder must close its context")
        print("PASS: folder-exterior drop routing, extraction transaction, 2-to-1 dissolution closes panel")
        if ProcessInfo.processInfo.environment["LAUNCHDOCK_FULLSCREEN_HELPER"]?.isEmpty == false {
            window.orderOut(nil)
            try await checkForeignFullscreenSpace(fixture: fixtureURL, records: store.records)
        }
        if ProcessInfo.processInfo.environment["LAUNCHDOCK_CHECK_LIFECYCLE"] != "1" {
            print("PASS: popup folder geometry, outside/interior clicks, full-window wheel, nonoverlapping search glyph/text")
            print("PASS: focused native drag-out and dissolution checks complete; lifecycle checks are a separate opt-in run")
            print("ALL NATIVE CHECKS PASSED")
            return
        }
        await store.flush()
        window.orderOut(nil)
        let coordinator = AppCoordinator()
        coordinator.store.lastScan = Date() // Do not scan or save user data in this isolated check.
        coordinator.window = OverlayWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        coordinator.window.isReleasedWhenClosed = false
        let savedOptions = app.presentationOptions
        coordinator.wallpaperService.source = { _ in fixtureURL }
        coordinator.show()
        try await waitForNative("Launcher begins showing") { coordinator.window.isVisible }
        try await pumpNativeEvents(for: 0.06)
        try requireNative(coordinator.window.alphaValue > 0 && coordinator.window.alphaValue < 1, "Launcher opening must render an intermediate window alpha")
        try await pumpNativeEvents(for: 0.4)
        try requireNative(coordinator.window.alphaValue == 1)
        try requireNative(!coordinator.store.wallpaperStatus.isEmpty)
        coordinator.hide()
        try await pumpNativeEvents(for: 0.06)
        try requireNative(coordinator.window.isVisible && coordinator.window.alphaValue > 0 && coordinator.window.alphaValue < 1, "Launcher closing must fade before ordering out")
        coordinator.show()
        try await pumpNativeEvents(for: 0.5)
        try requireNative(coordinator.window.isVisible && coordinator.window.alphaValue == 1, "Stale hide completion must not close a reshown window")
        coordinator.hide()
        try await pumpNativeEvents(for: 0.5)
        try requireNative(!coordinator.window.isVisible)
        try requireNative(app.presentationOptions == savedOptions)
        coordinator.settings()
        try await Task.sleep(for: .milliseconds(300))
        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline {
            if let event = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.02), inMode: .default, dequeue: true) { app.sendEvent(event) }
        }
        guard let settings = coordinator.settingsWindow else { throw NativeCheckFailure(message: "Settings window not created") }
        print("settings diagnostics: visible=\(settings.isVisible) key=\(settings.isKeyWindow) canKey=\(settings.canBecomeKey) active=\(app.isActive) frame=\(settings.frame)")
        try requireNative(settings.isVisible && settings.canBecomeKey, "Menu settings must open a visible, key-capable window")
        settings.close()
        coordinator.settings()
        try requireNative(coordinator.settingsWindow === settings && settings.isVisible, "Reopen same settings window")
        settings.orderOut(nil)
        if let root = ProcessInfo.processInfo.environment["LAUNCHDOCK_WINDOW_HELPERS"] {
            func launch(_ name: String) async throws -> NSRunningApplication {
                let config = NSWorkspace.OpenConfiguration(); config.activates = false
                let pid: pid_t = try await withCheckedThrowingContinuation { continuation in
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: root).appendingPathComponent(name+".app"), configuration: config) { application, error in
                        if let error { continuation.resume(throwing: error) }
                        else if let application { continuation.resume(returning: application.processIdentifier) }
                        else { continuation.resume(throwing: NSError(domain: "WindowHelper", code: 1)) }
                    }
                }
                return NSRunningApplication(processIdentifier: pid)!
            }
            let visible = try await launch("Visible"), hidden = try await launch("Hidden"), behind = try await launch("Behind")
            defer { _ = visible.terminate(); _ = behind.terminate(); _ = hidden.terminate() }
            try await Task.sleep(for: .milliseconds(500))
            _ = hidden.hide()
            try await Task.sleep(for: .milliseconds(300))
            try requireNative(hidden.isHidden && !visible.isHidden)
            func helperWindowOrder() -> [UInt32] {
                let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
                return windows.filter {
                    let pid = $0[kCGWindowOwnerPID as String] as? Int32
                    return (pid == visible.processIdentifier || pid == behind.processIdentifier) && ($0[kCGWindowLayer as String] as? Int == 0)
                }.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
            }
            try await waitForNative("Both visible helper windows must finish appearing before checking order", timeout: 5) {
                helperWindowOrder().count >= 2
            }
            let initialOrder = helperWindowOrder()
            try requireNative(initialOrder.count >= 2, "Both visible helper windows must be present before checking order")
            coordinator.show()
            for _ in 0..<12 {
                try await pumpNativeEvents(for: 0.03)
                try requireNative(!visible.isHidden && !behind.isHidden && hidden.isHidden && helperWindowOrder() == initialOrder, "Opening launcher must preserve other apps' visibility and stacking order")
            }
            coordinator.hide()
            for _ in 0..<12 {
                try await pumpNativeEvents(for: 0.03)
                try requireNative(!visible.isHidden && !behind.isHidden && hidden.isHidden && helperWindowOrder() == initialOrder, "Closing launcher must preserve other apps' visibility and stacking order")
            }
            print("PASS: repeated samples preserve real helper window stacking order and visibility during show/hide")
        }
        let preferenceSuite = "LaunchDock.visibility-check.\(UUID())"
        let preferences = UserDefaults(suiteName: preferenceSuite)!
        defer { preferences.removePersistentDomain(forName: preferenceSuite) }
        let originalPolicy = app.activationPolicy()
        coordinator.status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(coordinator.status); app.setActivationPolicy(originalPolicy) }
        preferences.set(true, forKey: "hideMenuBarIcon"); preferences.set(true, forKey: "hideDockIcon")
        coordinator.applyVisibilityPreferences(defaults: preferences)
        try requireNative(app.activationPolicy() == .accessory && !coordinator.status.isVisible, "Hiding both icons must update real AppKit policy and status item")
        preferences.set(false, forKey: "hideMenuBarIcon"); preferences.set(false, forKey: "hideDockIcon")
        coordinator.applyVisibilityPreferences(defaults: preferences)
        try requireNative(app.activationPolicy() == .regular && coordinator.status.isVisible, "Both icons must be restorable without relaunching")
        print("PASS: menu bar icon hide/restore and Dock activation policy hide/restore")
        print("PASS: popup folder geometry, outside/interior clicks, full-window wheel, nonoverlapping search glyph/text")
        print("PASS: frozen wallpaper background, animated show/hide/reentry, presentation restoration, settings open/close/reopen;")
        print("PASS: full-width hosting, centered 7×4 grid, 500ms long press, outer-scroll wheel paging, immediate icon drop creates folder and appends to existing folder, no blue borders")
        print("ALL NATIVE CHECKS PASSED")
    }
}

@MainActor final class NativeCheckDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        print("Native check harness: blocked premature terminate request")
        return .terminateCancel
    }
}

@MainActor func pumpNativeEvents(for duration: TimeInterval) async throws {
    let end = Date().addingTimeInterval(duration)
    while Date() < end {
        if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.01), inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor func sendBackgroundClick(_ window: OverlayWindow, event: NSEvent) {
    window.sendEvent(event)
    let up = NSEvent.mouseEvent(with: .leftMouseUp, location: event.locationInWindow, modifierFlags: [], timestamp: event.timestamp+0.1, windowNumber: window.windowNumber, context: nil, eventNumber: event.eventNumber+1, clickCount: 1, pressure: 0)!
    window.sendEvent(up)
}

struct NativeCheckFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

func requireNative(_ condition: @autoclosure () -> Bool, _ message: String = "Native assertion failed", file: StaticString = #fileID, line: UInt = #line) throws {
    guard condition() else { throw NativeCheckFailure(message: "\(file):\(line): \(message)") }
}

@MainActor func waitForNative(_ message: String, timeout: TimeInterval = 3, condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else { throw NativeCheckFailure(message: "Timed out: \(message)") }
        try await Task.sleep(for: .milliseconds(20))
    }
}
