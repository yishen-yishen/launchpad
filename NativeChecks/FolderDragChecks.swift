import AppKit
import SwiftUI
import LaunchDockCore

@main struct FolderDragChecks {
    @MainActor static func main() {
        Task { @MainActor in
            do { try await run(); print("PASS: 300ms folder-exit delay, hidden source/root/reloaded cells, restoration, reentry cancellation, root continuation, drag-end cancellation, two-to-one dissolution"); exit(0) }
            catch { print("FAIL: \(error)"); exit(1) }
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.run()
    }
    struct Failure: Error { let message: String }
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(message: message) }
    }
    @MainActor static func pause(_ seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }
    @MainActor static func run() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("LaunchDock-FolderDrag-\(UUID())")
        defer { try? FileManager.default.removeItem(at:dir) }
        let store=LauncherStore(dataDirectory:dir)
        store.records=(0..<12).map {AppRecord(path:"/nonexistent/DragCheck\($0).app",name:"Drag Check \($0)")}
        try store.engine.reconcile(store.records)
        let ids=store.records.map(\.id)
        try store.engine.createFolder(source:ids[0],target:ids[1])
        let folder=store.engine.document.folders[0].id
        try store.engine.move(.app(ids[2]),into:folder,at:Int.max)
        let window=OverlayWindow(contentRect:NSRect(x:80,y:80,width:1200,height:800),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.launcherStore=store
        let host=NSHostingView(rootView:LauncherView(store:store,settings:{}));host.sizingOptions=[]
        window.contentView=host;window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        store.folder=folder
        try await pause(0.5);host.layoutSubtreeIfNeeded()
        guard let source=host.findGrid() else{throw Failure(message:"No folder grid")}
        let outside=window.convertPoint(toScreen:NSPoint(x:5,y:5))
        let inside=window.convertPoint(toScreen:source.convert(NSPoint(x:source.bounds.midX,y:source.bounds.midY),to:nil))
        source.beginItemDrag(.app(ids[0]));source.updateFolderExit(at:outside)
        let sourceIndex=source.items.firstIndex(of:.app(ids[0]))!
        try check(source.item(at:IndexPath(item:sourceIndex,section:0))?.view.alphaValue == 0,"Original folder cell still visible")
        try await pause(0.15)
        try check(store.folder==folder,"Exited before 300ms")
        source.updateFolderExit(at:inside)
        try await pause(0.30)
        try check(store.folder==folder,"Reentry failed to cancel timer")
        source.updateFolderExit(at:outside)
        try await pause(0.40)
        try check(store.folder==nil && store.engine.document.root.contains(.app(ids[0])),"Did not extract before release")
        try check(source.dragActive && source.draggedItem == .app(ids[0]),"Native drag state ended during extraction")
        try await pause(0.35);host.layoutSubtreeIfNeeded()
        guard let root=host.findGrid(),root !== source,let targetIndex=root.items.firstIndex(of:.app(ids[3])) else{throw Failure(message:"No root target")}
        let extractedIndex=root.items.firstIndex(of:.app(ids[0]))!
        try check(root.item(at:IndexPath(item:extractedIndex,section:0))?.view.alphaValue == 0,"Extracted app visible before release")
        root.reloadData();root.layoutSubtreeIfNeeded()
        try check(root.item(at:IndexPath(item:extractedIndex,section:0))?.view.alphaValue == 0,"Reload revealed dragged app")
        guard let image=root.item(at:IndexPath(item:targetIndex,section:0))?.imageView else{throw Failure(message:"Missing target after reload")}
        let rect=image.convert(image.bounds,to:root)
        root.trackDestination(source:.app(ids[0]),point:NSPoint(x:rect.midX,y:rect.midY))
        try check(root.commitDestination(),"Root drop failed")
        try check(store.engine.document.folders.contains {$0.apps.contains(ids[0]) && $0.apps.contains(ids[3])},"Continuing drag could not merge on root")
        source.endItemDrag()
        try check(store.draggedItem == nil,"Drag presentation state was not cleared")
        store.folder=folder
        try await pause(0.5)
        guard let second=host.findGrid() else{throw Failure(message:"No reopened grid")}
        second.beginItemDrag(.app(ids[1]));second.updateFolderExit(at:outside);second.endItemDrag()
        try await pause(0.40)
        try check(store.folder==folder,"Ended drag left a pending extraction timer")
        second.beginItemDrag(.app(ids[1]));second.updateFolderExit(at:outside)
        try await pause(0.40)
        try check(store.folder==nil && !store.engine.document.folders.contains {$0.id==folder},"Two-to-one folder stayed open")
        try check(store.engine.document.root.contains(.app(ids[1])) && store.engine.document.root.contains(.app(ids[2])),"Dissolution lost an app")
        try check(second.dragActive,"Dissolution ended drag")
        second.endItemDrag()
        try await pause(0.35);host.layoutSubtreeIfNeeded()
        guard let finalRoot=host.findGrid(),let finalIndex=finalRoot.items.firstIndex(of:.app(ids[1])) else{throw Failure(message:"Missing final app")}
        try check(finalRoot.item(at:IndexPath(item:finalIndex,section:0))?.view.alphaValue == 1,"App did not reappear after release")
        finalRoot.beginItemDrag(.app(ids[1]))
        try check(finalRoot.item(at:IndexPath(item:finalIndex,section:0))?.view.alphaValue == 0,"Root drag did not hide original")
        finalRoot.endItemDrag()
        try check(finalRoot.item(at:IndexPath(item:finalIndex,section:0))?.view.alphaValue == 1,"Cancelled root drag did not restore original")
        await store.flush()
    }
}
