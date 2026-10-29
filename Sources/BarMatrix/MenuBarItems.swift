import AppKit

/// 菜单栏里其他应用的一个图标（一个状态栏窗口）。
struct MenuBarItem: Identifiable {
    let windowID: CGWindowID
    /// 全局坐标，左上角为原点（和 CGEvent 一致）。
    let frame: CGRect
    let ownerPID: pid_t
    let appName: String
    let appIcon: NSImage?

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
                               appIcon: hostedByControlCenter ? nil : app?.icon)
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

    // MARK: - 辅助功能

    /// 检查辅助功能权限，没有时弹出系统授权提示。
    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 菜单栏图标的名字和图标，用于设置里的列表。
    ///
    /// 新版 macOS 上图标窗口都属于控制中心，真正的应用只能通过辅助功能接口按位置反查。
    /// 一次性扫描所有应用的菜单栏图标，再按位置匹配。
    static func describe(_ items: [MenuBarItem]) -> [CGWindowID: (name: String, icon: NSImage?)] {
        let extras = allExtras()
        var result: [CGWindowID: (name: String, icon: NSImage?)] = [:]
        for item in items {
            let match = extras.min {
                distance($0.frame, item.frame) < distance($1.frame, item.frame)
            }.flatMap { distance($0.frame, item.frame) < 8 ? $0 : nil }
            guard let match else {
                result[item.windowID] = (item.appName.isEmpty ? "未知图标" : item.appName, item.appIcon)
                continue
            }
            let appName = match.app.localizedName ?? ""
            // 系统自带的图标（Wi‑Fi、电池等）都属于控制中心或 SystemUIServer，用它们自己的描述。
            let isSystem = ["com.apple.controlcenter", "com.apple.systemuiserver"].contains(match.app.bundleIdentifier ?? "")
            let name = isSystem ? (match.title ?? appName) : (appName.isEmpty ? (match.title ?? "未知图标") : appName)
            result[item.windowID] = (name, match.app.icon)
        }
        return result
    }

    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.midX - b.midX) + abs(a.midY - b.midY)
    }

    private static func allExtras() -> [(frame: CGRect, app: NSRunningApplication, title: String?)] {
        var extras: [(frame: CGRect, app: NSRunningApplication, title: String?)] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.1)
            guard let bar = attribute(axApp, kAXExtrasMenuBarAttribute),
                  CFGetTypeID(bar) == AXUIElementGetTypeID(),
                  let children = attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]
            else { continue }
            for element in children {
                guard let frame = axFrame(element) else { continue }
                let title = [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute]
                    .lazy.compactMap { attribute(element, $0) as? String }
                    .first { !$0.isEmpty }
                extras.append((frame, app, title))
            }
        }
        return extras
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

        // 拖动期间隐藏光标，并且一步拖到位，不让用户看到图标被拖着走。
        CGDisplayHideCursor(CGMainDisplayID())
        defer { CGDisplayShowCursor(CGMainDisplayID()) }
        post(.mouseMoved, origin)
        await pause(20)
        post(.leftMouseDown, origin)
        await pause(40)
        post(.leftMouseDragged, CGPoint(x: origin.x + (destination.x > origin.x ? 4 : -4), y: origin.y))
        await pause(20)
        post(.leftMouseDragged, CGPoint(x: destination.x, y: origin.y))
        await pause(30)
        post(.leftMouseUp, CGPoint(x: destination.x, y: origin.y))
        if let original { CGWarpMouseCursorPosition(original) }
        await pause(150)

        let end = frame(of: windowID)
        let moved = end.map { abs($0.midX - start.midX) > 1 } ?? false
        Log.write("move: window \(windowID) from \(start) toward \(destination) -> \(String(describing: end)), moved \(moved)")
        return moved
    }
}
