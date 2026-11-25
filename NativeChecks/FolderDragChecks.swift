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
        guard let first=source.item(at:IndexPath(item:0,section:0)),
              let secondCell=source.item(at:IndexPath(item:1,section:0)),
              let firstImage=first.imageView,let secondImage=secondCell.imageView,let label=first.textField else{throw Failure(message:"Missing hit-test cells")}
        let firstRect=firstImage.convert(firstImage.bounds,to:source)
        let secondRect=secondImage.convert(secondImage.bounds,to:source)
        let cellRect=first.view.convert(first.view.bounds,to:source)
        let gap=NSPoint(x:(firstRect.maxX+secondRect.minX)/2,y:firstRect.midY)
        let padding=NSPoint(x:cellRect.minX+2,y:firstRect.midY)
        let labelPadding=label.convert(NSPoint(x:1,y:label.bounds.midY),to:source)
        let normalOpen=source.open
        var activations=0
        source.open={ _ in activations += 1 }
        func click(_ point:NSPoint) async throws {
            let location=source.convert(point,to:nil)
            let down=NSEvent.mouseEvent(with:.leftMouseDown,location:location,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            let up=NSEvent.mouseEvent(with:.leftMouseUp,location:location,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime+0.01,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0)!
            window.sendEvent(down);NSApp.postEvent(up,atStart:true)
            try await pause(0.08)
        }
        for point in [gap,padding,labelPadding] {
            store.selected=nil;source.deselectAll(nil)
            try check(source.itemAtContentPoint(point)==nil,"Blank space identified as an item")
            try await click(point)
            try check(store.selected==nil && source.selectionIndexPaths.isEmpty && activations==0,"Blank click selected or activated an app")
            try check(store.folder==folder,"Interior blank click closed folder")
        }
        try await click(NSPoint(x:firstRect.midX,y:firstRect.midY))
        try check(activations==1,"Icon click stopped working")
        let labelCenter=label.convert(NSPoint(x:label.bounds.midX,y:label.bounds.midY),to:source)
        try await click(labelCenter)
        try check(activations==2,"Name click stopped working")
        source.open=normalOpen;source.cancelPointer()
        print("PASS: folder icon/name click hits; inter-icon gap, cell padding and name padding ignore clicks")
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
