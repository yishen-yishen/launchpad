import AppKit
import Darwin

/// Compatibility adapter restricted to Window Server's desktop-background layers.
/// Never passes an ordinary application window ID to either image API.
@MainActor enum DesktopWallpaperReader {
    struct Window {
        let id: CGWindowID
        let layer: Int
        let frame: CGRect
    }
    struct Image {
        let image: NSImage
        let backend: String
    }
    static func candidates(_ windows: [Window], display: CGRect) -> [Window] {
        let desktop = Int(CGWindowLevelForKey(.desktopWindow))
        let area = display.width * display.height
        guard area > 0 else { return [] }
        return windows.filter {
            let overlap = $0.frame.intersection(display)
            return (desktop-2...desktop).contains($0.layer) && overlap.width * overlap.height >= area * 0.95
        }.sorted {
            // The Dock background surface is the first choice used on current macOS.
            func rank(_ layer: Int) -> Int { layer == desktop-1 ? 0 : (layer == desktop-2 ? 1 : 2) }
            return rank($0.layer) < rank($1.layer)
        }
    }
    static func read(_ screen: NSScreen) throws -> Image {
        guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { throw ReadError.unavailable }
        let display = CGDisplayBounds(displayID)
        let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = rows.compactMap { row -> Window? in
            guard let id = row[kCGWindowNumber as String] as? NSNumber,
                  let layer = row[kCGWindowLayer as String] as? Int,
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return Window(id: id.uint32Value, layer: layer, frame: frame)
        }
        for window in candidates(windows, display: display) {
            let cg: CGImage?
            let backend: String
            if ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 {
                cg = skylightImage(window.id)
                backend = "desktop-window-skylight"
            } else if ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27 {
                cg = legacyImage(window.id, bounds: display)
                backend = "desktop-window-coregraphics"
            } else { continue }
            guard let cg else { continue }
            let image = NSImage(cgImage: cg, size: screen.frame.size)
            guard let stats = WallpaperService.pixelStatistics(image), !stats.isEmpty else { continue }
            return Image(image: image, backend: backend)
        }
        throw ReadError.unavailable
    }
    private static func legacyImage(_ id: CGWindowID, bounds: CGRect) -> CGImage? {
        // The exported desktop-only compatibility API is obsolete in the new SDK.
        // Resolve it at runtime; absence falls back to a wallpaper file, never to
        // ScreenCaptureKit, a display screenshot or a permission request.
        guard let library = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY | RTLD_LOCAL) else { return nil }
        defer { dlclose(library) }
        guard let symbol = dlsym(library, "CGWindowListCreateImage") else { return nil }
        typealias CopyImage = @convention(c) (CGRect, UInt32, CGWindowID, UInt32) -> Unmanaged<CGImage>?
        let copy = unsafeBitCast(symbol, to: CopyImage.self)
        return copy(bounds, CGWindowListOption.optionIncludingWindow.rawValue, id, CGWindowImageOption.boundsIgnoreFraming.rawValue)?.takeRetainedValue()
    }
    private static func skylightImage(_ id: CGWindowID) -> CGImage? {
        // Isolated private compatibility path for macOS 27. No other app/window
        // content is eligible. New system versions may require replacing this.
        guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL) else { return nil }
        defer { dlclose(library) }
        guard let connectionSymbol = dlsym(library, "CGSMainConnectionID"),
              let imageSymbol = dlsym(library, "CGSHWCaptureWindowList") else { return nil }
        typealias Connection = @convention(c) () -> UInt32
        typealias CopyImages = @convention(c) (UInt32, UnsafePointer<CGWindowID>, Int32, UInt32) -> Unmanaged<CFArray>?
        let connection = unsafeBitCast(connectionSymbol, to: Connection.self)
        let copy = unsafeBitCast(imageSymbol, to: CopyImages.self)
        var windowID = id
        guard let images = copy(connection(), &windowID, 1, 0x800)?.takeRetainedValue(), CFArrayGetCount(images) > 0,
              let pointer = CFArrayGetValueAtIndex(images, 0) else { return nil }
        let object = Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue()
        guard CFGetTypeID(object) == CGImage.typeID else { return nil }
        return unsafeDowncast(object, to: CGImage.self)
    }
    enum ReadError: LocalizedError {
        case unavailable
        var errorDescription: String? { "系统桌面背景图像接口不可用" }
    }
}
