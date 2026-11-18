import AppKit
import SwiftUI
import LaunchDockCore
import QuartzCore

final class AppCell: NSCollectionViewItem {
    static var preferredSize: CGFloat {
        let value = UserDefaults.standard.object(forKey: "iconSize") as? Int ?? 128
        return CGFloat([56: 112, 72: 128, 88: 144][value] ?? value)
    }
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    func setIconSize(_ size: CGFloat) { widthConstraint?.constant = size; heightConstraint?.constant = size }
    override func loadView() {
        let root = NSView(); root.wantsLayer = true; root.layer?.cornerRadius = 12
        let image = NSImageView(); image.imageScaling = .scaleProportionallyUpOrDown; image.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(wrappingLabelWithString: ""); label.alignment = .center; label.font = .systemFont(ofSize: 13); label.maximumNumberOfLines = 2; label.translatesAutoresizingMaskIntoConstraints = false
        label.isSelectable = false
        label.isEditable = false
        root.addSubview(image); root.addSubview(label)
        widthConstraint = image.widthAnchor.constraint(equalToConstant: 128)
        heightConstraint = image.heightAnchor.constraint(equalToConstant: 128)
        NSLayoutConstraint.activate([widthConstraint!, heightConstraint!])
        NSLayoutConstraint.activate([image.topAnchor.constraint(equalTo: root.topAnchor, constant: 8), image.centerXAnchor.constraint(equalTo: root.centerXAnchor), label.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 10), label.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4), label.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -4)])
        view = root; imageView = image; textField = label
    }
    func animateLaunch() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let image = imageView else { return }
        image.wantsLayer = true
        guard let layer = image.layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: image.frame.midX, y: image.frame.midY)
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
        let zoom = CAKeyframeAnimation(keyPath: "transform.scale")
        zoom.values = [1, 1.20, 1.20]; zoom.keyTimes = [0, 0.35, 1]
        zoom.duration = 0.44; zoom.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(zoom, forKey: "launchZoom")
    }
    func resetLaunchFeedback() { imageView?.layer?.removeAnimation(forKey: "launchZoom") }
    override func prepareForReuse() { super.prepareForReuse(); resetLaunchFeedback() }
    override var isSelected: Bool { didSet { view.layer?.borderWidth = 0; textField?.font = isSelected ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13) } }
}
final class PageSnapshotView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
final class PagingScrollView: NSScrollView {
    private(set) var permitsVerticalScrolling = false
    func configureScrolling(searchResults: Bool) {
        permitsVerticalScrolling = searchResults
        horizontalScrollElasticity = .none
        verticalScrollElasticity = searchResults ? .automatic : .none
        scrollerStyle = .overlay
        applyScrollerPolicy()
    }
    private func applyScrollerPolicy() {
        if hasHorizontalScroller { hasHorizontalScroller = false }
        if hasVerticalScroller != permitsVerticalScrolling { hasVerticalScroller = permitsVerticalScrolling }
        if !permitsVerticalScrolling { verticalScroller?.isHidden = true; horizontalScroller?.isHidden = true }
    }
    override func flashScrollers() { if permitsVerticalScrolling { super.flashScrollers() } }
    private var transitionGeneration = 0
    func pageSnapshot() -> PageSnapshotView? {
        transitionGeneration += 1
        subviews.filter { $0.identifier?.rawValue.hasPrefix("pageTransition") == true }.forEach { $0.removeFromSuperview() }
        documentView?.alphaValue = 1
        return capturePage()
    }
    private func capturePage() -> PageSnapshotView? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size); image.addRepresentation(rep)
        let view = PageSnapshotView(frame: bounds); view.image = image; view.imageScaling = .scaleAxesIndependently
        view.identifier = NSUserInterfaceItemIdentifier("pageTransitionSnapshot")
        return view
    }
    func animatePage(_ outgoing: PageSnapshotView, grid: GridCollection, forward: Bool) {
        guard let incoming = capturePage() else { return }
        let generation = transitionGeneration
        incoming.identifier = NSUserInterfaceItemIdentifier("pageTransitionIncoming")
        let distance = bounds.width * (forward ? 1 : -1)
        incoming.setFrameOrigin(NSPoint(x: distance,y: 0))
        wantsLayer = true; layer?.masksToBounds = true
        addSubview(outgoing, positioned: .above, relativeTo: nil)
        addSubview(incoming, positioned: .above, relativeTo: nil)
        grid.alphaValue = 0
        for (view, targetX) in [(outgoing, -distance), (incoming, CGFloat.zero)] {
            view.wantsLayer = true
            guard let layer = view.layer else { continue }
            let startX = layer.position.x
            view.setFrameOrigin(NSPoint(x: targetX, y: 0))
            let animation = CABasicAnimation(keyPath: "position.x")
            animation.fromValue = startX
            animation.toValue = layer.position.x
            animation.duration = 0.30
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "pageSlide")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self, weak grid, weak incoming, weak outgoing] in
            incoming?.removeFromSuperview(); outgoing?.removeFromSuperview()
            if self?.transitionGeneration == generation { grid?.alphaValue = 1 }
        }
    }
    override func scrollWheel(with event: NSEvent) {
        if let grid = documentView as? GridCollection, grid.routeScroll(event) { return }
        super.scrollWheel(with: event)
    }
    override func layout() {
        super.layout()
        applyScrollerPolicy()
        guard let grid = documentView as? GridCollection else { return }
        grid.fitViewport(contentView.bounds.size)
    }
}
final class GridCollection: NSCollectionView {
    weak var store: LauncherStore?
    var open: ((Int) -> Void)?
    var menuAction: ((Item, String) -> Void)?
    var items: [Item] = []
    private var pager = PageScroll()
    private var pointerMonitor: Any?
    var dragActive = false
    private(set) var draggedItem: Item?
    private var folderExitTimer: Timer?
    private var dragScreenPoint = NSPoint.zero
    var columns = 7
    var rowLimit = Int.max
    var rootProjection = false
    var folderContextID: UUID?
    var isActiveContext: Bool { rootProjection ? (store?.folder == nil || store?.query.isEmpty == false) : (folderContextID != nil && store?.folder == folderContextID) }
    func fitViewport(_ size: NSSize) {
        guard rootProjection || isActiveContext else { return }
        guard size.width > 0, size.height > 0,
              let layout = collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        // The page viewport spans the window, while icons retain their centered
        // content width. Include both empty margins in the moving page snapshot.
        let contentWidth = rootProjection ? size.width * 0.70 : size.width
        let geometry = GridGeometry(width: contentWidth, height: size.height, cellWidth: 160, cellHeight: 180, maxRows: rowLimit)
        columns = geometry.columns
        let cellWidth = floor(contentWidth / CGFloat(columns))
        let cellHeight = floor(size.height / CGFloat(geometry.rows))
        let inset = max(0, (size.width - CGFloat(columns)*cellWidth)/2)
        let itemSize = NSSize(width: cellWidth, height: cellHeight)
        if layout.itemSize != itemSize || layout.sectionInset.left != inset {
            layout.itemSize = itemSize
            layout.sectionInset = NSEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
            layout.invalidateLayout()
        }
        let paginated = !rootProjection || store?.query.isEmpty == true
        let height = paginated ? size.height : max(size.height,frame.height)
        if frame.size != NSSize(width: size.width,height: height) { setFrameSize(NSSize(width: size.width,height: height)) }
        if let store, (rootProjection ? store.rootCapacity : store.capacity) != geometry.capacity {
            let isRoot = rootProjection
            let contextID = folderContextID
            let anchor = isRoot ? store.rootDisplayed.first?.id : store.displayed.first?.id
            DispatchQueue.main.async { [weak store] in
                guard let store else { return }
                if isRoot {
                    store.rootCapacity = geometry.capacity
                    guard store.folder == nil else { return }
                } else { guard let contextID, store.folder == contextID else { return } }
                store.capacity = geometry.capacity
                if let anchor, let index = store.visible.firstIndex(where: { $0.id == anchor }) { store.page = index / geometry.capacity }
                else { store.page = min(store.page,store.pages-1) }
            }
        }
    }

    private var destinationTimer: Timer?
    private var destinationSource: Item?
    private var destinationPoint = NSPoint.zero
    private var candidate: Item?
    private(set) var mergeTarget: Item?
    private var edgeSince = 0.0
    private var edgeDirection = 0
    private var lastEdgeFlip = -Double.infinity
    var lastRenderedPage = 0
    func finishDestination() {
        destinationTimer?.invalidate(); destinationTimer = nil
        destinationSource = nil; candidate = nil; mergeTarget = nil; edgeDirection = 0
        for cell in visibleItems() { cell.imageView?.alphaValue = 1 }
    }
    func updateDestination(source: Item, point: NSPoint, now: Double) {
        destinationSource = source; destinationPoint = point
        let direction = point.x < 40 ? -1 : (point.x > bounds.width-40 ? 1 : 0)
        if direction != edgeDirection { edgeDirection = direction; edgeSince = now }
        if direction != 0, now-edgeSince >= 0.55, now-lastEdgeFlip >= 0.7, let store {
            store.page = min(max(0,store.page+direction),store.pages-1); lastEdgeFlip = now
            candidate = nil; mergeTarget = nil
        }
        var target: Item?
        if case .app = source, store?.folder == nil,
           let hit = indexPathForItem(at: point), items.indices.contains(hit.item), items[hit.item] != source,
           let image = item(at: hit)?.imageView {
            let rect = image.convert(image.bounds, to: self)
            // Use the rendered icon, not an assumed cell origin or collection drop index.
            if rect.contains(point) { target = items[hit.item] }
        }
        candidate = target; mergeTarget = target
        for cell in visibleItems() {
            let isTarget = indexPath(for: cell).map { items.indices.contains($0.item) && items[$0.item] == mergeTarget } ?? false
            cell.imageView?.alphaValue = isTarget ? 0.65 : 1
        }
    }
    private func receive(_ info: any NSDraggingInfo) -> NSDragOperation {
        guard let store, store.query.isEmpty, isActiveContext,
              let sourceView = info.draggingSource as? GridCollection, sourceView.store === store, sourceView.dragActive,
              let text = info.draggingPasteboard.string(forType: .string), let id = UUID(uuidString: text),
              let source = store.engine.document.root.first(where: { $0.id == id }) ?? store.engine.document.flattened.first(where: { $0 == id }).map(Item.app) else { return [] }
        trackDestination(source: source, point: convert(info.draggingLocation, from: nil))
        return .move
    }
    func trackDestination(source: Item, point: NSPoint) {
        updateDestination(source: source, point: point, now: ProcessInfo.processInfo.systemUptime)
        if destinationTimer == nil {
            let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let source = self.destinationSource else { return }
                    self.updateDestination(source: source, point: self.destinationPoint, now: ProcessInfo.processInfo.systemUptime)
                }
            }
            destinationTimer = timer
            RunLoop.main.add(timer, forMode: .common); RunLoop.main.add(timer, forMode: .eventTracking)
        }
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { receive(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { receive(sender) }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { finishDestination() }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { destinationSource != nil }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard receive(sender) == .move else { return false }
        return commitDestination()
    }
    @discardableResult func commitDestination() -> Bool {
        guard let store, let source = destinationSource else { return false }
        defer { finishDestination() }
        let revision = store.engine.document.revision
        if let target = mergeTarget, case .app(let sourceID) = source {
            switch target {
            case .app(let id): store.change { try $0.createFolder(source: sourceID, target: id) }
            case .folder(let id): store.change { try $0.move(source, into: id, at: Int.max) }
            }
        } else {
            var insertion = items.count
            if let hit = indexPathForItem(at: destinationPoint), let attributes = layoutAttributesForItem(at: hit) {
                insertion = hit.item + (destinationPoint.x > attributes.frame.midX ? 1 : 0)
            }
            let absolute = store.page*store.capacity + insertion
            let old = store.visible.firstIndex(of: source) ?? Int.max
            store.change { try $0.move(source, into: store.folder, at: absolute - (old < absolute ? 1 : 0)) }
        }
        return store.engine.document.revision != revision
    }
    func cancelPointer() {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }; pointerMonitor = nil
    }
    func animateLaunch(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        (item(at: IndexPath(item: index, section: 0)) as? AppCell)?.animateLaunch()
    }
    func resetLaunchFeedback() {
        for cell in visibleItems() { (cell as? AppCell)?.resetLaunchFeedback() }
    }
    override var acceptsFirstResponder: Bool { true }
    func selectFirst() { if !items.isEmpty { selectItems(at: [IndexPath(item: 0, section: 0)], scrollPosition: .top); store?.selected = items[0].id } }
    override func keyDown(with event: NSEvent) {
        guard let store else { return }
        let current = selectionIndexPaths.first?.item ?? 0
        var next = current
        switch event.keyCode {
        case 53: store.escape(); return
        case 36, 76: if items.indices.contains(current) { open?(current) }; return
        case 123: next -= 1
        case 124: next += 1
        case 125: next += columns
        case 126: next -= columns
        case 116: store.page = max(0,store.page-1); return
        case 121: store.page = min(store.pages-1,store.page+1); return
        default:
            if let field = window?.contentView?.findSearch() { window?.makeFirstResponder(field); window?.firstResponder?.keyDown(with: event) }; return
        }
        if next < 0, store.query.isEmpty, store.page > 0 { store.page -= 1; return }
        if next >= items.count, store.query.isEmpty, store.page+1 < store.pages { store.page += 1; return }
        guard !items.isEmpty else { return }; next = min(max(0,next),items.count-1)
        selectItems(at: [IndexPath(item: next, section: 0)], scrollPosition: .nearestHorizontalEdge); store.selected = items[next].id
    }
    override func mouseDown(with event: NSEvent) {
        cancelPointer()
        let start = convert(event.locationInWindow, from: nil)
        guard let index = indexPathForItem(at: start), items.indices.contains(index.item) else {
            if store?.folder == nil { store?.hide?() }; return
        }
        window?.makeFirstResponder(self)
        selectItems(at: [index], scrollPosition: [])
        let source = items[index.item]
        store?.selected = source.id
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp, .keyDown]) { [weak self] next in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                if next.type == .keyDown {
                    if next.keyCode == 53 { self.cancelPointer(); return true }; return false
                }
                if next.type == .leftMouseUp {
                    self.cancelPointer()
                    if let current = self.items.firstIndex(of: source) { self.open?(current) }
                    return true
                }
                let point = self.convert(next.locationInWindow, from: nil)
                guard hypot(point.x-start.x, point.y-start.y) > 6 else { return true }
                self.cancelPointer()
                guard self.store?.query.isEmpty == true, let cell = self.item(at: index) else { return true }
                let pasteboard = NSPasteboardItem(); pasteboard.setString(source.id.uuidString, forType: .string)
                let dragged = NSDraggingItem(pasteboardWriter: pasteboard)
                let image = NSImage(size: cell.view.bounds.size)
                if let rep = cell.view.bitmapImageRepForCachingDisplay(in: cell.view.bounds) { cell.view.cacheDisplay(in: cell.view.bounds, to: rep); image.addRepresentation(rep) }
                dragged.setDraggingFrame(cell.view.frame, contents: image)
                self.beginItemDrag(source)
                self.beginDraggingSession(with: [dragged], event: next, source: self)
                return true
            }
            return consumed ? nil : next
        }
    }
    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? .move : [] }
    override func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        endItemDrag()
    }
    func applyDragVisibility() {
        for cell in visibleItems() {
            guard let index = indexPath(for: cell), items.indices.contains(index.item) else { continue }
            let hidden = items[index.item] == store?.draggedItem
            cell.view.alphaValue = hidden ? 0 : 1
            cell.view.setAccessibilityHidden(hidden)
        }
    }
    private func refreshDragVisibility() {
        func update(_ view: NSView) {
            if let grid = view as? GridCollection { grid.applyDragVisibility() }
            for child in view.subviews { update(child) }
        }
        if let content = window?.contentView { update(content) } else { applyDragVisibility() }
    }
    func beginItemDrag(_ item: Item) {
        cancelFolderExit()
        dragActive = true; draggedItem = item; store?.beginDrag(item)
        refreshDragVisibility()
    }
    func endItemDrag() {
        cancelFolderExit(); draggedItem = nil
        window?.contentView?.findGrid()?.finishDestination()
        finishDestination(); dragActive = false; store?.endDrag()
        refreshDragVisibility()
    }
    override func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        updateFolderExit(at: screenPoint)
    }
    private func cancelFolderExit() {
        folderExitTimer?.invalidate(); folderExitTimer = nil
    }
    private func canExitFolder(at screenPoint: NSPoint) -> Bool {
        guard dragActive, let folderContextID, store?.folder == folderContextID,
              case .app(let id) = draggedItem, let window = window as? OverlayWindow, window.isVisible else { return false }
        return window.acceptsFolderExit(source: self, id: id, at: window.convertPoint(fromScreen: screenPoint))
    }
    func updateFolderExit(at screenPoint: NSPoint) {
        dragScreenPoint = screenPoint
        guard canExitFolder(at: screenPoint) else { cancelFolderExit(); return }
        guard folderExitTimer == nil else { return }
        // Keep the native dragging session alive while switching back to the root.
        // A run-loop timer also fires while the mouse stays still in drag tracking.
        let timer = Timer(timeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.folderExitTimer = nil
                guard self.canExitFolder(at: self.dragScreenPoint), case .app(let id) = self.draggedItem else { return }
                self.finishDestination()
                _ = self.store?.moveAppOutOfFolder(id)
            }
        }
        folderExitTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }
    func routeScroll(_ event: NSEvent) -> Bool {
        guard let store, store.query.isEmpty else { return false }
        if dragActive || (window?.firstResponder as? NSTextView)?.hasMarkedText() == true { return true }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        let direction = pager.update(delta: delta, precise: event.hasPreciseScrollingDeltas,
            began: event.phase.contains(.began), ended: event.phase.contains(.ended) || event.phase.contains(.cancelled),
            momentum: !event.momentumPhase.isEmpty, now: ProcessInfo.processInfo.systemUptime)
        if direction != 0 { store.page = min(max(0,store.page+direction),store.pages-1) }
        return true
    }
    override func scrollWheel(with event: NSEvent) { if !routeScroll(event) { super.scrollWheel(with: event) } }
    func itemAtContentPoint(_ point: NSPoint) -> Item? {
        guard isActiveContext, let scroll = enclosingScrollView,
              scroll.contentView.bounds.contains(scroll.contentView.convert(point, from: self)),
              let index = indexPathForItem(at: point), items.indices.contains(index.item),
              let cell = item(at: index) else { return nil }
        if let image = cell.imageView, image.convert(image.bounds, to: self).contains(point) { return items[index.item] }
        if let label = cell.textField, !label.stringValue.isEmpty {
            let size = (label.stringValue as NSString).boundingRect(
                with: NSSize(width: label.bounds.width, height: label.bounds.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: label.font ?? NSFont.systemFont(ofSize: 13)]).size
            let textBounds = NSRect(x: max(0, (label.bounds.width - ceil(size.width))/2), y: 0,
                                    width: min(label.bounds.width, ceil(size.width)), height: label.bounds.height)
            if label.convert(textBounds, to: self).contains(point) { return items[index.item] }
        }
        return nil
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let item = itemAtContentPoint(convert(event.locationInWindow, from: nil)) else { return nil }
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .aqua)
        menu.autoenablesItems = false
        let entry = NSMenuItem(title: "在访达中显示", action: #selector(runMenu(_:)), keyEquivalent: "")
        entry.target = self
        entry.representedObject = item
        entry.isEnabled = store?.finderURL(for: item) != nil
        menu.addItem(entry)
        return menu
    }
    @objc func runMenu(_ sender: NSMenuItem) { if let item = sender.representedObject as? Item { menuAction?(item,sender.title) } }
}
extension NSView {
    func findSearch() -> NSSearchField? { if let field = self as? NSSearchField { if let search = field as? LauncherSearchField, search.store?.folder != nil, search.store?.query.isEmpty == true { return nil }; return field }; return subviews.lazy.compactMap { $0.findSearch() }.first }
}
struct CollectionGrid: NSViewRepresentable {
    @ObservedObject var store: LauncherStore
    var rootProjection = false
    var folderProjectionID: UUID? = nil
    var rowLimit: Int? = nil
    func makeCoordinator() -> Coordinator { Coordinator(store) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = PagingScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = false; scroll.autohidesScrollers = true
        let collection = GridCollection(); collection.store = store; collection.rootProjection = rootProjection; collection.folderContextID = folderProjectionID ?? (rootProjection ? nil : store.folder); collection.backgroundColors = [.clear]; collection.isSelectable = true
        let layout = NSCollectionViewFlowLayout(); layout.itemSize = NSSize(width: 128, height: 112); layout.minimumInteritemSpacing = 0; layout.minimumLineSpacing = 0
        collection.rowLimit = rowLimit ?? (rootProjection ? 4 : Int.max)
        collection.collectionViewLayout = layout; collection.register(AppCell.self, forItemWithIdentifier: .init("app")); collection.dataSource = context.coordinator; collection.delegate = context.coordinator
        collection.setDraggingSourceOperationMask(.move, forLocal: true); collection.registerForDraggedTypes([.string])
        collection.open = { i in if collection.items.indices.contains(i) { store.activate(collection.items[i]) } }
        collection.menuAction = { item, title in
            switch title {
            case "在访达中显示":
                if let url = store.finderURL(for: item) {
                    store.hide?()
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            default: break
            }
        }
        scroll.documentView = collection; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let grid = scroll.documentView as? GridCollection else { return }
        grid.applyDragVisibility()
        // SwiftUI keeps this view alive during its removal transition. Freeze the old
        // folder's data and geometry instead of projecting the now-active root into it.
        guard rootProjection || grid.isActiveContext else { return }
        grid.rowLimit = rowLimit ?? (rootProjection ? 4 : Int.max)
        context.coordinator.store = store
        (scroll as? PagingScrollView)?.configureScrolling(searchResults: rootProjection && !store.query.isEmpty)
        let items = rootProjection ? store.rootDisplayed : store.displayed
        if grid.items != items {
            let forward = store.page > grid.lastRenderedPage
            let paging = store.query.isEmpty && grid.lastRenderedPage != store.page && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let pagingScroll = scroll as? PagingScrollView
            let snapshot = paging ? pagingScroll?.pageSnapshot() : nil
            grid.lastRenderedPage = store.page
            grid.items = items; grid.reloadData(); scroll.contentView.scroll(to: .zero)
            grid.layoutSubtreeIfNeeded()
            if let snapshot { pagingScroll?.animatePage(snapshot, grid: grid, forward: forward) }
        }
        grid.fitViewport(scroll.contentView.bounds.size)
        grid.applyDragVisibility()
        guard grid.isActiveContext else { return }
        for cell in grid.visibleItems() {
            if let path = grid.indexPath(for: cell), grid.items.indices.contains(path.item) {
                cell.textField?.stringValue = store.name(grid.items[path.item])
                cell.imageView?.image = store.icon(grid.items[path.item])
                cell.textField?.textColor = .white
                (cell as? AppCell)?.setIconSize(min(AppCell.preferredSize, ((grid.collectionViewLayout as? NSCollectionViewFlowLayout)?.itemSize.width ?? 160) - 20))
            }
            cell.view.layer?.backgroundColor = NSColor.clear.cgColor
            cell.view.layer?.borderWidth = 0
        }

    }
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var store: LauncherStore
        var hoverID: UUID?
        var hoverStart = 0.0
        var lastFlip = 0.0
        var edgeDirection = 0
        var edgeStart = 0.0
        init(_ store: LauncherStore) { self.store = store }
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { (collectionView as? GridCollection)?.items.count ?? 0 }
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let cell = collectionView.makeItem(withIdentifier: .init("app"), for: indexPath)
            guard let grid = collectionView as? GridCollection, grid.items.indices.contains(indexPath.item) else { return cell }
            cell.textField?.textColor = .white
                (cell as? AppCell)?.setIconSize(min(AppCell.preferredSize, ((grid.collectionViewLayout as? NSCollectionViewFlowLayout)?.itemSize.width ?? 160) - 20))
            let item = grid.items[indexPath.item]; cell.textField?.stringValue = store.name(item); cell.imageView?.image = store.icon(item)
            cell.view.alphaValue = item == store.draggedItem ? 0 : 1
            cell.view.setAccessibilityHidden(item == store.draggedItem)
            cell.view.setAccessibilityElement(true); cell.view.setAccessibilityRole(.button); cell.view.setAccessibilityLabel(store.name(item)); return cell
        }
        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
            guard store.query.isEmpty, let grid = collectionView as? GridCollection else { return nil }
            return grid.items[indexPath.item].id.uuidString as NSString
        }
    }
}
