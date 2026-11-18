import SwiftUI
import AppKit
import LaunchDockCore
import QuartzCore

/// Native rectangles protect controls and folder interiors from window-background dismissal.
final class LauncherRegionView: NSView {
    var enabled = true
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
struct LauncherRegion: NSViewRepresentable {
    var enabled = true
    func makeNSView(context: Context) -> LauncherRegionView { let v = LauncherRegionView(); v.enabled = enabled; return v }
    func updateNSView(_ view: LauncherRegionView, context: Context) { view.enabled = enabled }
}
extension NSView {
    func containsLauncherRegion(at windowPoint: NSPoint) -> Bool {
        guard !isHiddenOrHasHiddenAncestor else { return false }
        if let overlay = self as? FolderOverlayView, !overlay.acceptsEvents { return false }
        if let region = self as? LauncherRegionView, region.enabled, convert(bounds, to: nil).contains(windowPoint) { return true }
        return subviews.contains { $0.containsLauncherRegion(at: windowPoint) }
    }
}
final class LauncherSearchCell: NSSearchFieldCell {
    override func searchButtonRect(forBounds rect: NSRect) -> NSRect { NSRect(x: rect.minX+5, y: rect.midY-7, width: 14, height: 14) }
    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect { .zero }
    override func searchTextRect(forBounds rect: NSRect) -> NSRect { NSRect(x: rect.minX+27, y: rect.midY-9, width: max(0,rect.width-51), height: 18) }
}
final class LauncherSearchField: NSSearchField {
    weak var store: LauncherStore?
    private func configureEditor() {
        guard let editor = currentEditor() as? NSTextView else { return }
        // A borderless search field uses a full-size editor. Keep its input text
        // inside the same glyph margins as the placeholder.
        editor.textContainerInset = NSSize(width: 27, height: 0)
        editor.textContainer?.lineFragmentPadding = 0
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { configureEditor() }
        return accepted
    }
    override func mouseDown(with event: NSEvent) { super.mouseDown(with: event); configureEditor() }
    override func selectText(_ sender: Any?) { super.selectText(sender); configureEditor() }
}
struct SearchField: NSViewRepresentable {
    @ObservedObject var store: LauncherStore
    func makeCoordinator() -> Coordinator { Coordinator(store) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = LauncherSearchField(); field.store = store; field.cell = LauncherSearchCell(); field.placeholderString = "搜索应用"; field.delegate = context.coordinator
        (field.cell as? NSSearchFieldCell)?.cancelButtonCell = nil
        // Installing a text cell resets NSTextField's editing flags.
        field.isEditable = true; field.isSelectable = true
        field.sendsSearchStringImmediately = true
        field.isBezeled = false; field.drawsBackground = false; field.focusRingType = .none
        field.textColor = .white; field.font = .systemFont(ofSize: 13)
        field.placeholderAttributedString = NSAttributedString(string: "搜索", attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.65)])
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) { if field.stringValue != store.query { field.stringValue = store.query } }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        let store: LauncherStore
        init(_ store: LauncherStore) { self.store = store }
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField, (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            store.query = field.stringValue; store.selected = store.visible.first?.id
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.cancelOperation(_:)): store.escape(); return true
            case #selector(NSResponder.insertNewline(_:)):
                if let item = store.visible.first(where: { $0.id == store.selected }) ?? store.visible.first { store.activate(item) }; return true
            case #selector(NSResponder.moveDown(_:)):
                if let grid = control.window?.contentView?.findGrid() { control.window?.makeFirstResponder(grid); grid.selectFirst() }; return true
            default: return false
            }
        }
    }
}
extension NSView {
    func findGrid() -> GridCollection? { if let grid = self as? GridCollection { return grid.isActiveContext ? grid : nil }; return subviews.lazy.compactMap { $0.findGrid() }.first }
}
struct LauncherView: View {
    @ObservedObject var store: LauncherStore
    var settings: () -> Void
    private var isFolder: Bool { store.folder != nil && store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    @ViewBuilder private func pageDots(root: Bool = false) -> some View {
        if store.query.isEmpty && store.pages > 1 {
            HStack(spacing: 9) { ForEach(0..<store.pages, id: \.self) { page in
                Button { store.page = page } label: { Circle().fill(Color.white.opacity(page == store.page ? 0.95 : 0.35)).frame(width: 7, height: 7) }.buttonStyle(.plain).accessibilityLabel("第 \(page+1) 页")
            }}.padding(10).background(LauncherRegion(enabled: !root || !isFolder))
        }
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Group {

                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            SearchField(store: store).frame(width: 214, height: 30)
                            Button(action: settings) { Image(systemName: "ellipsis.circle").font(.system(size: 13)) }
                                .buttonStyle(.plain).frame(width: 30, height: 30).accessibilityLabel("设置")
                        }
                        .padding(.horizontal, 6).frame(width: 256, height: 34)
                        .background(Color.white.opacity(0.13), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1).allowsHitTesting(false))
                        .background(LauncherRegion(enabled: !isFolder))
                        Spacer().frame(height: max(24, geometry.size.height*0.12 - geometry.size.height*0.028 - 34))
                        if (store.query.isEmpty ? store.rootVisible : store.visible).isEmpty {
                            VStack { Text(store.scanning ? "正在查找应用…" : (store.query.isEmpty ? "没有可用应用" : "未找到应用")); Button("重新扫描") { Task { await store.scan() } }.background(LauncherRegion(enabled: !isFolder)) }.frame(maxHeight: .infinity)
                        } else {
                            CollectionGrid(store: store, rootProjection: true).frame(width: geometry.size.width, height: geometry.size.height*0.70)
                        }
                        Spacer(minLength: 0)
                    }.padding(.top, geometry.size.height*0.028)
                    pageDots(root: true).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 22)
                }
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
                .opacity(isFolder ? 0 : 1)
                .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeInOut(duration: 0.15), value: isFolder)
                .allowsHitTesting(!isFolder).accessibilityHidden(isFolder)
                FolderOverlay(store: store, folder: isFolder ? store.engine.document.folders.first(where: { $0.id == store.folder }) : nil,
                              width: geometry.size.width*0.88, maxGridHeight: max(1, geometry.size.height - 240))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let message = store.message {
                    HStack { Text(message); Button("关闭") { store.message = nil } }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).background(LauncherRegion()).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 55)
                }
            }.foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            GeometryReader { proxy in
                ZStack {
                    Color(red: 0.10, green: 0.11, blue: 0.15)
                    if let wallpaper = store.wallpaper {
                        Image(nsImage: wallpaper).resizable().scaledToFill()
                            .frame(width: proxy.size.width + 64, height: proxy.size.height + 64)
                            .blur(radius: 24, opaque: true)
                            .position(x: proxy.size.width/2, y: proxy.size.height/2)
                    }
                    Color.black.opacity(0.12)
                }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
            }.ignoresSafeArea().allowsHitTesting(false)
        }
        .onChange(of: store.query) { _, _ in store.selected = store.visible.first?.id }
    }
}

/// Only the title inside an open folder is editable. Grid labels stay labels.
final class FolderTitleField: NSTextField, NSTextFieldDelegate {
    weak var store: LauncherStore?
    var folderID: UUID?
    private(set) var isTitleEditing = false
    private var originalName = ""
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        delegate = self
        isEditable = false; isSelectable = false
        isBezeled = false; isBordered = false; drawsBackground = false
        focusRingType = .none; alignment = .center
        font = .systemFont(ofSize: 30, weight: .light); textColor = .white
        maximumNumberOfLines = 1; cell?.usesSingleLineMode = true
        setAccessibilityLabel("文件夹名称")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func mouseDown(with event: NSEvent) {
        guard !isTitleEditing, store?.folder == folderID else { super.mouseDown(with: event); return }
        originalName = stringValue; isTitleEditing = true
        isEditable = true; isSelectable = true
        selectText(nil)
    }
    func finishEditing(commit: Bool) {
        guard isTitleEditing else { return }
        let draft = currentEditor()?.string ?? stringValue
        isTitleEditing = false
        let finalName: String
        if commit, let store, let folderID {
            store.change { try $0.rename(folderID, name: draft) }
            finalName = store.name(.folder(folderID))
        } else { finalName = originalName }
        window?.makeFirstResponder(nil)
        isEditable = false; isSelectable = false
        // Ending field editing copies the draft back into the cell. Restore the
        // validated/cancelled value only after that native copy has completed.
        stringValue = finalName
    }
    func controlTextDidEndEditing(_ notification: Notification) { finishEditing(commit: true) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): finishEditing(commit: true); return true
        case #selector(NSResponder.cancelOperation(_:)): finishEditing(commit: false); return true
        default: return false
        }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { finishEditing(commit: false) }
        super.viewWillMove(toWindow: newWindow)
    }
}
private struct FolderTitle: NSViewRepresentable {
    @ObservedObject var store: LauncherStore
    let folder: Folder
    func makeNSView(context: Context) -> FolderTitleField {
        let field = FolderTitleField(); field.store = store; field.folderID = folder.id
        return field
    }
    func updateNSView(_ field: FolderTitleField, context: Context) {
        if !field.isTitleEditing { field.stringValue = folder.name }
    }
}
extension NSView {
    func findFolderTitle() -> FolderTitleField? {
        if let field = self as? FolderTitleField { return field.store?.folder == field.folderID ? field : nil }
        return subviews.lazy.compactMap { $0.findFolderTitle() }.first
    }
}

/// All geometry comes from this folder record, even while the removed view fades out.
private struct FolderPanel: View {
    @ObservedObject var store: LauncherStore
    let folder: Folder
    let width: CGFloat
    let maxGridHeight: CGFloat
    @State private var selectedPage = 0
    private var members: Int { folder.apps.filter { !store.engine.document.hidden.contains($0) }.count }
    private var geometry: FolderGridGeometry { FolderGridGeometry(width: max(1, width-56), maxHeight: maxGridHeight, itemCount: members) }
    private var gridHeight: CGFloat { geometry.height }
    private var capacity: Int { geometry.capacity }
    private var pages: Int { max(1,(members+capacity-1)/capacity) }
    var body: some View {
        VStack(spacing: 20) {
            FolderTitle(store: store, folder: folder).frame(width: min(width, 520), height: 42).background(LauncherRegion())
            VStack(spacing: 12) {
                CollectionGrid(store: store, folderProjectionID: folder.id, rowLimit: geometry.rows)
                    .transaction { $0.animation = nil; $0.disablesAnimations = true }
                    .frame(height: gridHeight)
                if pages > 1 {
                    HStack(spacing: 9) { ForEach(0..<pages,id: \.self) { page in
                        Button { store.page = page } label: { Circle().fill(Color.white.opacity(page == selectedPage ? 0.95 : 0.35)).frame(width: 7,height: 7) }.buttonStyle(.plain).accessibilityLabel("第 \(page+1) 页")
                    }}.padding(10).background(LauncherRegion())
                }
            }
            .padding(.horizontal,28).padding(.vertical,36)
            .background(Color.white.opacity(0.18),in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.white.opacity(0.32),lineWidth: 1))
            .background(LauncherRegion())
        }
        .frame(width: width)
        .onAppear { if store.folder == folder.id { selectedPage = store.page } }
        .onChange(of: store.page) { _, value in if store.folder == folder.id { selectedPage = value } }
        .onChange(of: store.folder) { _, value in if value == folder.id { selectedPage = store.page } }
    }
}

/// A persistent native host owns the fade. SwiftUI layout transactions cannot
/// suppress this animation or remove the retiring panel before it finishes.
final class FolderOverlayView: NSView {
    private let container = NSView()
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private var record: Folder?
    private var panelWidth: CGFloat = 0
    private var gridHeight: CGFloat = 0
    private var generation = 0
    private var presentationID = UUID()
    private var completion: Task<Void, Never>?
    private(set) var acceptsEvents = false
    var fadeInProgress: Bool { container.layer?.animation(forKey: "folderFade") != nil }
    var presentationScale: CGFloat { (container.layer?.presentation()?.value(forKeyPath: "transform.scale.x") as? NSNumber).map { CGFloat($0.doubleValue) } ?? 1 }
    var presentationOpacity: Float { container.layer?.presentation()?.opacity ?? container.layer?.opacity ?? 0 }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        container.wantsLayer = true; container.layer?.opacity = 0
        container.autoresizingMask = [.width, .height]; container.frame = bounds
        host.sizingOptions = []; host.autoresizingMask = [.width, .height]; host.frame = container.bounds
        container.addSubview(host); addSubview(container); isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { acceptsEvents ? super.hitTest(point) : nil }
    func present(store: LauncherStore, folder: Folder?, width: CGFloat, maxGridHeight: CGFloat) {
        if let folder {
            let reopening = !acceptsEvents
            if reopening || record != folder || panelWidth != width || gridHeight != maxGridHeight {
                // Keep the outer fade container, but start each opening with a
                // fresh grid/page state instead of animating last session's reset.
                if reopening || record?.id != folder.id { presentationID = UUID() }
                record = folder; panelWidth = width; gridHeight = maxGridHeight
                host.rootView = AnyView(FolderPanel(store: store, folder: folder, width: width, maxGridHeight: maxGridHeight)
                    // A new folder needs a new collection context and local page
                    // state; the outer native animation container stays alive.
                    .id(presentationID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(.white))
            }
            if !acceptsEvents { fade(show: true) }
        } else if acceptsEvents { fade(show: false) }
    }
    private func fade(show: Bool) {
        completion?.cancel(); generation += 1; let current = generation
        acceptsEvents = show
        let layer = container.layer!
        let start = layer.presentation()?.opacity ?? layer.opacity
        let startScale: CGFloat = isHidden && show ? 0.94 : ((layer.presentation()?.value(forKeyPath: "transform.scale.x") as? NSNumber).map { CGFloat($0.doubleValue) } ?? 1)
        layer.removeAnimation(forKey: "folderFade")
        layer.removeAnimation(forKey: "folderScale")
        if show { isHidden = false; layoutSubtreeIfNeeded() }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: container.frame.midX, y: container.frame.midY)
        layer.opacity = show ? 1 : 0
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { isHidden = !show; return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = start; fade.toValue = show ? 1 : 0
        fade.duration = 0.28; fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: "folderFade")
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = startScale; scale.toValue = show ? 1 : 0.94
        scale.duration = 0.28; scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(scale, forKey: "folderScale")
        completion = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, self.generation == current else { return }
            if !show { self.isHidden = true }
        }
    }
}
private struct FolderOverlay: NSViewRepresentable {
    @ObservedObject var store: LauncherStore
    let folder: Folder?
    let width: CGFloat
    let maxGridHeight: CGFloat
    func makeNSView(context: Context) -> FolderOverlayView { FolderOverlayView(frame: .zero) }
    func updateNSView(_ view: FolderOverlayView, context: Context) { view.present(store: store, folder: folder, width: width, maxGridHeight: maxGridHeight) }
}
extension NSView {
    func findFolderOverlay() -> FolderOverlayView? { if let view = self as? FolderOverlayView { return view }; return subviews.lazy.compactMap { $0.findFolderOverlay() }.first }
}
