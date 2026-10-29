import AppKit
import Combine

/// 用两个状态项实现折叠：
///
///     [其他图标] [要隐藏的图标…] │ ‹   ← 系统图标
///                               ^  ^
///                       separator  toggle
///
/// 用户按住 ⌘ 把不常用的图标拖到分隔符左边。折叠时把分隔符的宽度
/// 撑到很大，它左边的图标就被挤出屏幕；展开时恢复正常宽度。
final class MenuBarController: NSObject {
    private let toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let separator = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let prefs: Preferences
    private let openSettings: () -> Void
    private var collapseTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private static let expandedLength: CGFloat = 8
    private static let collapsedLength: CGFloat = 10_000

    private(set) var isCollapsed = false {
        didSet { updateAppearance() }
    }

    init(prefs: Preferences, openSettings: @escaping () -> Void) {
        self.prefs = prefs
        self.openSettings = openSettings
        super.init()

        // autosaveName 让系统记住用户拖动后的位置。
        toggle.autosaveName = "BarMatrixToggle"
        separator.autosaveName = "BarMatrixSeparator"

        if let button = toggle.button {
            button.target = self
            button.action = #selector(toggleClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        if let button = separator.button {
            button.target = self
            button.action = #selector(toggleClicked(_:))
            button.sendAction(on: [.rightMouseUp])
        }

        prefs.$showSeparator
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateAppearance() }
            .store(in: &cancellables)

        updateAppearance()
        // 启动一会儿后默认折叠，给菜单栏布局留出时间。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.collapse() }
    }

    // MARK: - 折叠 / 展开

    func collapse() {
        // 分隔符跑到了折叠按钮右边时，折叠会把按钮自己也挤出屏幕，这时不折叠。
        guard isSeparatorLeftOfToggle else { return }
        collapseTimer?.invalidate()
        isCollapsed = true
    }

    func expand() {
        isCollapsed = false
        scheduleAutoCollapse()
    }

    private func scheduleAutoCollapse() {
        collapseTimer?.invalidate()
        guard prefs.autoCollapse else { return }
        collapseTimer = Timer.scheduledTimer(withTimeInterval: prefs.collapseDelay, repeats: false) { [weak self] _ in
            self?.collapse()
        }
    }

    private var isSeparatorLeftOfToggle: Bool {
        guard let sep = separator.button?.window?.frame.minX,
              let tog = toggle.button?.window?.frame.minX else { return false }
        return sep < tog
    }

    // MARK: - 外观

    private func updateAppearance() {
        separator.length = isCollapsed ? Self.collapsedLength : Self.expandedLength
        separator.button?.image = (isCollapsed || !prefs.showSeparator) ? nil : Self.separatorImage

        let symbol = isCollapsed ? "chevron.compact.left" : "chevron.compact.right"
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: isCollapsed ? "展开" : "折叠")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        toggle.button?.image = image
    }

    /// 一条细竖线，模板图会跟随菜单栏颜色。
    private static let separatorImage: NSImage = {
        let image = NSImage(size: NSSize(width: 2, height: 14), flipped: false) { rect in
            NSColor.black.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    // MARK: - 点击

    @objc private func toggleClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu(from: sender)
        } else if isCollapsed {
            expand()
        } else {
            collapse()
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "设置…", action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 BarMatrix", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func settingsClicked() { openSettings() }
}
