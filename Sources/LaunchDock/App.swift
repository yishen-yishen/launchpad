import AppKit
import SwiftUI
import ServiceManagement
import LaunchDockCore

final class OverlayWindow: NSPanel, NSDraggingDestination {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style.union(.nonactivatingPanel), backing: backingStoreType, defer: flag)
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }
    private var visibilityAnimation: Task<Void, Never>?
    /// Drive window alpha explicitly: an inactive panel must animate even when
    /// AppKit does not run an implicit animator transaction for its application.
    func animateVisibility(show: Bool, completion: @escaping @MainActor () -> Void) {
        visibilityAnimation?.cancel()
        let start = alphaValue
        let target = show ? 1.0 : 0.0
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : (show ? 0.30 : 0.26)
        visibilityAnimation = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            let began = clock.now
            while let self {
                let elapsed = began.duration(to: clock.now)
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let progress = min(1, seconds / duration)
                let eased = progress * progress * (3 - 2 * progress)
                self.alphaValue = start + (target - start) * eased
                if progress >= 1 { completion(); return }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
        }
    }
    weak var launcherStore: LauncherStore?
    private var backgroundDrag: BackgroundDrag?
    func cancelBackgroundDrag() { backgroundDrag = nil }
    override func sendEvent(_ event: NSEvent) {
        if routeLauncherEvent(event) { return }
        super.sendEvent(event)
    }
    @discardableResult func routeLauncherEvent(_ event: NSEvent) -> Bool {
        guard let store = launcherStore, let content = contentView else { return false }
        if event.type == .rightMouseDown {
            backgroundDrag = nil
            NSMenu.popUpContextMenu(contextMenu(for: event), with: event, for: content)
            return true
        }
        if event.type == .keyDown, event.keyCode == 53, backgroundDrag != nil { backgroundDrag = nil; return true }
        if event.type == .leftMouseDragged, var drag = backgroundDrag {
            drag.update(x: event.locationInWindow.x,y: event.locationInWindow.y); backgroundDrag = drag; return true
        }
        if event.type == .leftMouseUp, var drag = backgroundDrag {
            backgroundDrag = nil
            switch drag.end(x: event.locationInWindow.x,y: event.locationInWindow.y) {
            case .page(let direction): store.page = min(max(0,store.page+direction),store.pages-1)
            case .click: if store.folder != nil { store.folder = nil } else { store.hide?() }
            case .cancel: break
            }
            return true
        }
        if event.type == .scrollWheel, backgroundDrag != nil { return true }
        if event.type == .scrollWheel, let grid = content.findGrid() { return grid.routeScroll(event) }
        guard event.type == .leftMouseDown else { return false }
        let point = event.locationInWindow
        if let title = content.findFolderTitle(), title.isTitleEditing,
           !title.convert(title.bounds, to: nil).contains(point) { title.finishEditing(commit: true) }
        if content.containsLauncherRegion(at: point) { return false }
        if let grid = content.findGrid(), let scroll = grid.enclosingScrollView,
           scroll.convert(scroll.bounds, to: nil).contains(point) {
            if store.folder != nil { return false }
            let local = grid.convert(point, from: nil)
            if let path = grid.indexPathForItem(at: local), let cell = grid.item(at: path) {
                if let image = cell.imageView, image.convert(image.bounds, to: grid).contains(local) { return false }
                if let label = cell.textField, label.convert(label.bounds, to: grid).contains(local) { return false }
            }
        }
        backgroundDrag = BackgroundDrag(x: point.x,y: point.y)
        return true
    }
    func contextMenu(for event: NSEvent) -> NSMenu {
        if let grid = contentView?.findGrid(), let menu = grid.menu(for: event) { return menu }
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .aqua)
        for title in ["设置…", "重启", "退出"] {
            let entry = NSMenuItem(title: title, action: #selector(runApplicationMenu(_:)), keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        return menu
    }
    @objc private func runApplicationMenu(_ sender: NSMenuItem) {
        switch sender.title {
        case "设置…": launcherStore?.showSettings?()
        case "重启": launcherStore?.restartApplication?()
        case "退出": launcherStore?.quitApplication?()
        default: break
        }
    }
    func acceptsFolderExit(source: GridCollection, id: UUID, at point: NSPoint) -> Bool {
        guard let store = launcherStore, source.store === store, let folder = store.folder,
              store.engine.document.folders.first(where: { $0.id == folder })?.apps.contains(id) == true,
              contentView?.containsLauncherRegion(at: point) == false else { return false }
        return NSRect(origin: .zero, size: frame.size).contains(point)
    }
    private func folderExitID(_ info: any NSDraggingInfo) -> UUID? {
        guard let source = info.draggingSource as? GridCollection,
              let string = info.draggingPasteboard.string(forType: .string), let id = UUID(uuidString: string),
              acceptsFolderExit(source: source, id: id, at: info.draggingLocation) else { return nil }
        return id
    }
    private func rootDragItem(_ info: any NSDraggingInfo) -> Item? {
        guard let store = launcherStore, store.folder == nil, store.query.isEmpty,
              let source = info.draggingSource as? GridCollection, source.store === store, source.dragActive,
              source.folderContextID != nil, let item = source.draggedItem,
              info.draggingPasteboard.string(forType: .string) == item.id.uuidString,
              store.engine.document.root.contains(item) else { return nil }
        return item
    }
    func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if let item = rootDragItem(sender), let grid = contentView?.findGrid() {
            grid.trackDestination(source: item, point: grid.convert(sender.draggingLocation, from: nil))
            return .move
        }
        return folderExitID(sender) == nil ? [] : .move
    }
    func draggingExited(_ sender: (any NSDraggingInfo)?) { contentView?.findGrid()?.finishDestination() }
    func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { folderExitID(sender) != nil || rootDragItem(sender) != nil }
    func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if let item = rootDragItem(sender), let grid = contentView?.findGrid() {
            grid.trackDestination(source: item, point: grid.convert(sender.draggingLocation, from: nil))
            return grid.commitDestination()
        }
        guard let id = folderExitID(sender) else { return false }
        return launcherStore?.moveAppOutOfFolder(id) ?? false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
@main struct LaunchDockApp: App {
    @NSApplicationDelegateAdaptor(AppCoordinator.self) var delegate
    var body: some Scene {
        Settings { SettingsView(store: delegate.store, refreshHotCorners: { delegate.hotCorners.refresh() }, refreshVisibility: { delegate.applyVisibilityPreferences() }) }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("设置…") { delegate.settings() }.keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}
@MainActor final class AppCoordinator: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = LauncherStore()
    let hotkey = HotKeyService()
    let hotCorners = HotCornerService()
    let watcher = DirectoryWatcher()
    var window: OverlayWindow!
    var status: NSStatusItem!
    var settingsWindow: NSWindow?
    let wallpaperService = WallpaperService()
    private var wallpaperTask: Task<Void, Never>?
    var presentationGeneration = 0
    var wantsVisible = false
    var savedPresentation: NSApplication.PresentationOptions?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let old = UserDefaults.standard.object(forKey: "iconSize") as? Int, let upgraded = [56: 112, 72: 128, 88: 144][old] { UserDefaults.standard.set(upgraded, forKey: "iconSize") }
        NSApp.setActivationPolicy(UserDefaults.standard.bool(forKey: "hideDockIcon") ? .accessory : .regular)
        window = OverlayWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.launcherStore = store
        window.registerForDraggedTypes([.string]); window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false; window.isOpaque = false; window.backgroundColor = .clear
        window.delegate = self
        let host = NSHostingView(rootView: LauncherView(store: store, settings: { [weak self] in self?.settings() }))
        host.sizingOptions = []; host.autoresizingMask = [.width, .height]
        window.contentView = host
        store.showSettings = { [weak self] in self?.settings() }
        store.restartApplication = { [weak self] in self?.restart() }
        store.quitApplication = { [weak self] in self?.quit() }
        store.hide = { [weak self] in self?.hide() }
        store.hideAfterLaunch = { [weak self] in self?.hide() }
        store.launchFeedback = { [weak self] id in self?.window.contentView?.findGrid()?.animateLaunch(id) }
        store.showLaunchFailure = { [weak self] in self?.show() }
        hotCorners.windowState = { [weak self] in
            guard let self else { return [:] }
            return ["visible": self.window.isVisible, "wantsVisible": self.wantsVisible, "active": NSApp.isActive, "opaqueEnough": self.window.alphaValue > 0.9]
        }
        hotCorners.action = { [weak self] in self?.toggle() }
        hotCorners.refresh()
        hotkey.action = { [weak self] in self?.toggle() }
        if hotkey.register(code: UInt32(UserDefaults.standard.object(forKey: "hotkeyCode") as? Int ?? 49), modifiers: UInt32(UserDefaults.standard.object(forKey: "hotkeyModifiers") as? Int ?? 2048)) != noErr { store.message = "Option+Space 注册失败；可使用 Dock 或菜单栏" }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength); status.button?.image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "LaunchDock")
        let menu = NSMenu()
        for (title, selector) in [("显示/隐藏启动器", #selector(toggle)), ("设置…", #selector(settings)), ("退出", #selector(quit))] { let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item) }; status.menu = menu
        applyVisibilityPreferences()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        Task { await store.start() }
        watcher.changed = { [weak self] in guard let self else { return }; Task { await self.store.scan() } }
        watcher.start(paths: CatalogService.roots.map(\.path))
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeSpaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        // Login launches carry an Apple-event launch descriptor; never infer from a timer.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let login = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        if !login { show() }
    }
    func show() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        if wantsVisible { return }
        presentationGeneration += 1; wantsVisible = true
        let generation = presentationGeneration
        window.setFrame(screen.frame, display: true)
        wallpaperTask?.cancel()
        wallpaperTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.wallpaperService.snapshot(for: screen)
            guard !Task.isCancelled, self.wantsVisible, self.presentationGeneration == generation else { return }
            self.store.wallpaper = snapshot.image
            self.store.wallpaperStatus = snapshot.description
            self.presentWindow()
        }
    }
    private func presentWindow() {
        if savedPresentation == nil { savedPresentation = NSApp.presentationOptions }
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        if !window.isVisible { window.alphaValue = 0 }
        window.contentView?.findGrid()?.resetLaunchFeedback()
        window.contentView?.layoutSubtreeIfNeeded()
        // A nonactivating panel can take keyboard focus in the current Space.
        // Activating our regular application here may instead select its desktop.
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        hotCorners.recordStatus("show")
        let showingGeneration = presentationGeneration
        window.animateVisibility(show: true) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.presentationGeneration == showingGeneration, self.wantsVisible else { return }
                self.hotCorners.recordStatus("shown")
            }
        }
        DispatchQueue.main.async { [weak self] in if let field = self?.window.contentView?.findSearch() { self?.window.makeFirstResponder(field) } }
        if store.hasRestoredSnapshot && Date().timeIntervalSince(store.lastScan) > 60 { Task { await store.scan() } }
    }
    func hide() {
        presentationGeneration += 1; let generation = presentationGeneration; wantsVisible = false
        wallpaperTask?.cancel(); wallpaperTask = nil
        hotCorners.recordStatus("hide")
        window.contentView?.findFolderTitle()?.finishEditing(commit: true)
        window.cancelBackgroundDrag()
        window.contentView?.findGrid()?.cancelPointer()
        window.contentView?.findGrid()?.finishDestination()
        window.animateVisibility(show: false) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.presentationGeneration == generation, !self.wantsVisible else { return }
                self.window.orderOut(nil)
                self.hotCorners.recordStatus("hidden")
                if let saved = self.savedPresentation { NSApp.presentationOptions = saved; self.savedPresentation = nil }
                self.store.query = ""; self.store.folder = nil
            }
        }
    }
    @objc func toggle() {
        if wantsVisible { hotCorners.recordStatus("toggle-hide"); hide() } else { hotCorners.recordStatus("toggle-show"); show() }
    }
    @objc func settings() {
        // Do not route through obsolete responder-chain selectors. The menu and gear use this same window.
        hide(); window.orderOut(nil)
        if let saved = savedPresentation { NSApp.presentationOptions = saved; savedPresentation = nil }
        if settingsWindow == nil {
            let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 588, height: 468), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            settings.title = "LaunchDock 设置"; settings.isReleasedWhenClosed = false
            settings.contentView = NSHostingView(rootView: SettingsView(store: store, refreshHotCorners: { [weak self] in self?.hotCorners.refresh() }, refreshVisibility: { [weak self] in self?.applyVisibilityPreferences() }))
            settings.center(); settingsWindow = settings
        }
        NSApp.activate(); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applyVisibilityPreferences(defaults: UserDefaults = .standard) {
        let policy: NSApplication.ActivationPolicy = defaults.bool(forKey: "hideDockIcon") ? .accessory : .regular
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        status?.isVisible = !defaults.bool(forKey: "hideMenuBarIcon")
    }
    @objc func woke() { Task { await store.scan() } }
    private var restarting = false
    private var restartAlreadySaved = false
    @objc func restart() {
        guard !restarting else { return }
        restarting = true
        Task {
            await store.flush()
            // Wait for this process to finish saving its layout and releasing
            // its global shortcut before launching the replacement instance.
            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/bin/sh")
            helper.arguments = ["-c", "for attempt in $(/usr/bin/seq 1 300); do if ! /bin/kill -0 \"$1\" 2>/dev/null; then exec /usr/bin/open -n \"$2\"; fi; /bin/sleep 0.1; done", "LaunchDockRestart", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
            do {
                try helper.run()
                restartAlreadySaved = true
                quit()
            }
            catch { restarting = false; store.message = "无法重启：\(error.localizedDescription)" }
        }
    }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func screenChanged() { guard window.isVisible else { return }; if let screen = NSScreen.screens.first(where: { $0.frame.intersects(window.frame) }) ?? NSScreen.main { window.setFrame(screen.frame, display: true) } else { hide() } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    @objc func activeSpaceChanged() { if wantsVisible { hide() } }
    func windowDidResignKey(_ notification: Notification) { if wantsVisible { hide() } }
    func applicationDidResignActive(_ notification: Notification) { hotCorners.recordStatus("resigned"); if wantsVisible { hide() } }
    func applicationDidHide(_ notification: Notification) { if NSApp.isHidden && wantsVisible { hide() } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        wallpaperTask?.cancel()
        // restart() already awaited persistence. Waiting for another MainActor
        // task inside terminate() would block behind that restart task.
        if restartAlreadySaved {
            hotkey.stop(); hotCorners.stop(); watcher.stop()
            return .terminateNow
        }
        Task { await store.flush(); hotkey.stop(); hotCorners.stop(); watcher.stop(); NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
struct SettingsView: View {
    @ObservedObject var store: LauncherStore
    var refreshHotCorners: () -> Void = {}
    var refreshVisibility: () -> Void = {}
    @AppStorage("hotkeyLabel") var hotkeyLabel = "⌥Space"
    @AppStorage("hideMenuBarIcon") var hideMenuBarIcon = false
    @AppStorage("hideDockIcon") var hideDockIcon = false
    @AppStorage("iconSize") var iconSize = 128
    @State var loginStatus = SMAppService.mainApp.status
    var body: some View {
        TabView {
            Form {
                Toggle("隐藏菜单栏图标", isOn: $hideMenuBarIcon)
                    .onChange(of: hideMenuBarIcon) { _, _ in refreshVisibility() }
                Toggle("隐藏 Dock 图标", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { _, _ in refreshVisibility() }
                Toggle("登录时启动", isOn: Binding(get: { loginStatus == .enabled }, set: { enabled in
                    do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginStatus = SMAppService.mainApp.status } catch { store.message = "登录启动设置失败：\(error.localizedDescription)" }
                }))
                if loginStatus == .requiresApproval { Button("打开登录项设置") { SMAppService.openSystemSettingsLoginItems() } }
                ShortcutRecorder(label: $hotkeyLabel) { store.message = $0 }
                Text("若系统功能优先拦截，请更换组合键并测试。")
                HotCornerSettings(refresh: refreshHotCorners)
                Picker("图标大小", selection: $iconSize) { Text("小").tag(112); Text("标准").tag(128); Text("大").tag(144) }
            }.tabItem { Text("通用") }
            Form {
                Text("索引：\(store.records.count) 个应用")
                Button("重新扫描") { Task { await store.scan() } }
                HStack { Button("导出布局…") { store.exportLayout() }; Button("导入布局…") { store.importLayout() } }
                Button("重置为字母顺序…") {
                    let alert = NSAlert(); alert.messageText = "重置布局？"; alert.informativeText = "将移除文件夹并按名称排序。原布局会保存到备份。"; alert.addButton(withTitle: "重置"); alert.addButton(withTitle: "取消")
                    if alert.runModal() == .alertFirstButtonReturn { let sorted = store.records.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }.map { Item.app($0.id) }; store.change { engine in try engine.commit { layout in layout.folders = []; layout.root = sorted } } }
                }
                Button("撤销最近整理") { store.change { $0.undo() } }
                ForEach(store.records.filter { store.engine.document.hidden.contains($0.id) }) { app in HStack { Text(app.label); Button("恢复显示") { store.change { try $0.commit { $0.hidden.remove(app.id) } } } } }
            }.tabItem { Text("应用") }
            VStack(spacing: 10) {
                Text("LaunchDock").font(.title)
                Text("\(Bundle.main.object(forInfoDictionaryKey: "LaunchDockDisplayVersion") as? String ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版") · macOS 26+")
                Text("原生本地应用启动器，无网络服务")
                HStack(spacing: 4) {
                    Text("作者信息：")
                    Link("yishen@mdashen.com", destination: URL(string: "mailto:yishen@mdashen.com")!)
                }
            }.tabItem { Text("关于") }
        }
        .overlay(alignment: .bottom) { if let message = store.message { Text(message).font(.caption).padding().background(.regularMaterial) } }.padding(24).frame(width: 540, height: 420)
    }
}
