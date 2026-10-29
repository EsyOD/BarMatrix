import AppKit
import ScreenCaptureKit

/// 菜单栏里其他应用的一个图标（一个状态栏窗口）。
struct MenuBarItem: Identifiable {
    let windowID: CGWindowID
    /// 全局坐标，左上角为原点（和 CGEvent 一致）。
    let frame: CGRect
    let appName: String
    let appIcon: NSImage?
    var image: CGImage?

    var id: CGWindowID { windowID }
}

enum MenuBarItems {
    private static let statusLevel = Int(CGWindowLevelForKey(.statusWindow))

    /// 当前所有菜单栏图标的位置。只读位置和所属进程，不需要任何权限。
    static func all() -> [MenuBarItem] {
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
                  frame.minY <= 1, frame.height < 60, frame.width > 0
            else { return nil }
            let app = NSRunningApplication(processIdentifier: pid)
            return MenuBarItem(windowID: id, frame: frame,
                               appName: app?.localizedName ?? "",
                               appIcon: app?.icon, image: nil)
        }
        .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// 分隔符左边的图标就是被隐藏的图标。
    static func hidden(leftOf separatorX: CGFloat) -> [MenuBarItem] {
        all().filter { $0.frame.maxX <= separatorX + 1 }
    }

    static func frame(of windowID: CGWindowID) -> CGRect? {
        all().first { $0.windowID == windowID }?.frame
    }

    // MARK: - 截图（需要“屏幕录制”权限）

    static var canCapture: Bool { CGPreflightScreenCaptureAccess() }

    /// 截取每个图标窗口的画面。窗口被挤出屏幕时同样能截到。
    static func captureImages(for items: [MenuBarItem]) async -> [CGWindowID: CGImage] {
        guard canCapture,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return [:] }

        let wanted = Set(items.map(\.windowID))
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        var images: [CGWindowID: CGImage] = [:]
        for window in content.windows where wanted.contains(window.windowID) {
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            config.captureResolution = .best
            let filter = SCContentFilter(desktopIndependentWindow: window)
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                images[window.windowID] = image
            }
        }
        return images
    }

    // MARK: - 点击（需要“辅助功能”权限）

    /// 检查辅助功能权限，没有时弹出系统授权提示。
    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 在指定位置模拟一次左键点击，然后把鼠标放回原处。
    static func click(at point: CGPoint) {
        let original = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        if let original {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { CGWarpMouseCursorPosition(original) }
        }
    }
}
