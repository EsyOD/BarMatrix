import AppKit
import ScreenCaptureKit

/// 菜单栏里其他应用的一个图标（一个状态栏窗口）。
struct MenuBarItem: Identifiable {
    let windowID: CGWindowID
    /// 全局坐标，左上角为原点（和 CGEvent 一致）。
    let frame: CGRect
    let ownerPID: pid_t
    let appName: String
    let appIcon: NSImage?
    var image: CGImage?

    var id: CGWindowID { windowID }
}

enum MenuBarItems {
    private static let statusLevel = Int(CGWindowLevelForKey(.statusWindow))

    /// 当前所有菜单栏图标的位置。只读位置和所属进程，不需要任何权限。
    /// 传入 screen 时只返回那块屏幕菜单栏上的图标（多屏时每块屏幕都有各自的图标窗口）。
    static func all(on screen: NSScreen? = nil) -> [MenuBarItem] {
        let rowTop = screen.map { menuBarTop(of: $0) }
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == statusLevel,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  frame.height < 60, frame.width > 0,
                  rowTop.map({ abs(frame.minY - $0) <= 1 }) ?? true
            else { return nil }
            let app = NSRunningApplication(processIdentifier: pid)
            // 新版 macOS 把所有菜单栏图标窗口都交给「控制中心」托管，
            // 这时所属进程的图标并不代表这个菜单栏图标，就不拿它当占位。
            let hostedByControlCenter = app?.bundleIdentifier == "com.apple.controlcenter"
            let title = info[kCGWindowName as String] as? String
            return MenuBarItem(windowID: id, frame: frame, ownerPID: pid,
                               appName: (hostedByControlCenter ? title : nil) ?? app?.localizedName ?? "",
                               appIcon: hostedByControlCenter ? nil : app?.icon, image: nil)
        }
        .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// 分隔符左边的图标就是被隐藏的图标。
    ///
    /// 展开时它们在屏幕左边缘和分隔符之间；折叠时分隔符本身伸到了屏幕外很远的地方，
    /// 被挤出去的图标在它左边。这样不会把左侧另一块屏幕上的图标算进来。
    static func hidden(leftOf separatorX: CGFloat, on screen: NSScreen) -> [MenuBarItem] {
        let screenMinX = screen.frame.minX
        return all(on: screen).filter {
            $0.frame.maxX <= separatorX + 1 && ($0.frame.minX >= screenMinX || separatorX < screenMinX)
        }
    }

    /// 屏幕菜单栏顶边在 CG 坐标系（左上角为原点）中的 y 值。
    static func menuBarTop(of screen: NSScreen) -> CGFloat {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        return primaryTop - screen.frame.maxY
    }

    static func frame(of windowID: CGWindowID) -> CGRect? {
        all().first { $0.windowID == windowID }?.frame
    }

    // MARK: - 截图（需要“屏幕录制”权限）

    static var canCapture: Bool { CGPreflightScreenCaptureAccess() }

    /// 截取每个图标窗口的画面。窗口被挤出屏幕时同样能截到。
    ///
    /// 优先用 CGWindowListCreateImage：它能截到屏幕外的窗口，而 ScreenCaptureKit
    /// 在部分系统版本上对菜单栏图标窗口会失败或返回空白，只作为后备。
    static func captureImages(for items: [MenuBarItem]) async -> [CGWindowID: CGImage] {
        guard canCapture else { return [:] }

        var images: [CGWindowID: CGImage] = [:]
        for item in items {
            if let image = windowImage(item.windowID), !isBlank(image) {
                images[item.windowID] = image
            }
        }

        let missing = Set(items.map(\.windowID)).subtracting(images.keys)
        guard !missing.isEmpty,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return images }

        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        for window in content.windows where missing.contains(window.windowID) {
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            config.captureResolution = .best
            let filter = SCContentFilter(desktopIndependentWindow: window)
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
               !isBlank(image) {
                images[window.windowID] = image
            }
        }
        return images
    }

    /// CGWindowListCreateImage 在新版 SDK 里被标为不可用，但系统里仍然存在，
    /// 所以运行时动态查找，避免换 Xcode 版本后编译失败。
    private typealias CreateImageFunc = @convention(c) (CGRect, UInt32, CGWindowID, UInt32) -> Unmanaged<CGImage>?
    private static let createImage: CreateImageFunc? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(symbol, to: CreateImageFunc.self)
    }()

    private static func windowImage(_ windowID: CGWindowID) -> CGImage? {
        guard let createImage else { return nil }
        let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        return createImage(.null, CGWindowListOption.optionIncludingWindow.rawValue, windowID, options.rawValue)?
            .takeRetainedValue()
    }

    /// 截图是否几乎完全透明（截取失败时常见）。
    private static func isBlank(_ image: CGImage) -> Bool {
        let size = 16
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: size, height: size,
                                          bitsPerComponent: 8, bytesPerRow: size * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return true }
        return !stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 16 }
    }

    // MARK: - 点击（需要“辅助功能”权限）

    /// 检查辅助功能权限，没有时弹出系统授权提示。
    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 用辅助功能接口找到位于 frame 处的菜单栏图标并“按下”它，效果和点击一样，
    /// 但不用移动鼠标。找不到时返回 false。
    static func press(itemAt frame: CGRect, ownerPID: pid_t?) -> Bool {
        guard let found = findExtra(at: frame, ownerPID: ownerPID) else { return false }
        let (element, app) = found
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        Log.write("press: AXPress on \(app.localizedName ?? "?") -> \(result.rawValue)")
        return result == .success
    }

    /// 真正拥有这个菜单栏图标的应用。新版 macOS 上图标窗口都属于控制中心，
    /// 只能通过辅助功能接口按位置反查。
    static func owningApp(ofItemAt frame: CGRect, ownerPID: pid_t?) -> NSRunningApplication? {
        if let app = findExtra(at: frame, ownerPID: ownerPID)?.app { return app }
        guard let ownerPID, let app = NSRunningApplication(processIdentifier: ownerPID),
              app.bundleIdentifier != "com.apple.controlcenter" else { return nil }
        return app
    }

    private static func findExtra(at frame: CGRect, ownerPID: pid_t?) -> (element: AXUIElement, app: NSRunningApplication)? {
        var apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy != .prohibited }
        // 先查图标所属的应用（新版 macOS 上所属进程是控制中心，这时只能逐个找）。
        if let ownerPID, let index = apps.firstIndex(where: { $0.processIdentifier == ownerPID }) {
            apps.insert(apps.remove(at: index), at: 0)
        }
        var scanned = 0
        var nearest: (distance: CGFloat, frame: CGRect, app: String)?
        for app in apps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.1)
            guard let bar = attribute(axApp, kAXExtrasMenuBarAttribute),
                  CFGetTypeID(bar) == AXUIElementGetTypeID(),
                  let children = attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]
            else { continue }
            for element in children {
                scanned += 1
                guard let elementFrame = axFrame(element) else { continue }
                let distance = abs(elementFrame.midX - frame.midX) + abs(elementFrame.midY - frame.midY)
                if distance < (nearest?.distance ?? .infinity) {
                    nearest = (distance, elementFrame, app.localizedName ?? "?")
                }
                if distance < 8 { return (element, app) }
            }
        }
        Log.write("ax: no extra at \(frame); scanned \(scanned), nearest \(String(describing: nearest))")
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func axFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute),
              let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }

    /// 在指定位置模拟一次左键点击，然后把鼠标放回原处。
    /// 模拟按住 ⌘ 拖动，把菜单栏图标挪到 destination（全局坐标，左上角为原点）。
    /// 和用户手动 ⌘ 拖动图标一样，需要图标当前显示在屏幕上。返回图标是否真的移动了。
    static func move(_ windowID: CGWindowID, to destination: CGPoint) async -> Bool {
        guard let start = frame(of: windowID) else {
            Log.write("move: window \(windowID) not found")
            return false
        }
        let origin = CGPoint(x: start.midX, y: start.midY)
        let original = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .combinedSessionState)
        func post(_ type: CGEventType, _ point: CGPoint) {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        func pause(_ milliseconds: UInt64) async {
            try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
        }

        post(.mouseMoved, origin)
        await pause(30)
        post(.leftMouseDown, origin)
        await pause(80)
        let steps = 10
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: origin.x + (destination.x - origin.x) * t, y: origin.y))
            await pause(15)
        }
        await pause(60)
        post(.leftMouseUp, CGPoint(x: destination.x, y: origin.y))
        if let original { CGWarpMouseCursorPosition(original) }
        await pause(250)

        let end = frame(of: windowID)
        let moved = end.map { abs($0.midX - start.midX) > 1 } ?? false
        Log.write("move: window \(windowID) from \(start) toward \(destination) -> \(String(describing: end)), moved \(moved)")
        return moved
    }

    /// 先把鼠标移过去，按下和抬起之间留一点间隔，太快的点击有时会被菜单栏忽略。
    static func click(at point: CGPoint) {
        Log.write("click: synthesized click at \(point)")
        let original = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ type: CGEventType) {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        post(.mouseMoved)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            post(.leftMouseDown)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                post(.leftMouseUp)
                if let original {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { CGWarpMouseCursorPosition(original) }
                }
            }
        }
    }
}
