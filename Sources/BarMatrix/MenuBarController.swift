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
    /// 每次折叠/展开加一，用来丢弃过时的异步折叠。
    private var transition = 0
    /// 隐藏图标的截图，在它们还显示在菜单栏上时截取。
    private var imageCache: [CGWindowID: CGImage] = [:]
    /// 已经为补截图临时展开过的图标，截不到的不再反复展开。
    private var peekedIDs = Set<CGWindowID>()
    /// 临时挪到 ‹ 旁边显示的隐藏图标，之后要放回去。
    private var shownItem: CGWindowID?
    private var rehideMonitor: Any?
    private var rehideTimer: Timer?
    private let panel = HiddenItemsPanel()
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

        // 左键直接打开图标所属的应用；右键才展开菜单栏、弹出它的菜单。
        // 左键：像 Bartender 一样把图标临时挪到 ‹ 旁边再打开它；右键：直接打开所属应用。
        panel.onSelect = { [weak self] item in self?.showInPlace(item) }
        panel.onSecondarySelect = { [weak self] item in self?.openApp(item) }

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
        guard !isCollapsed else { return }
        transition += 1
        let current = transition
        // 图标被挤出屏幕后系统就不再绘制它们，所以先趁它们还可见时截图缓存。
        Task { @MainActor [weak self] in
            await self?.refreshImageCache()
            guard let self, current == self.transition, self.isSeparatorLeftOfToggle else { return }
            self.isCollapsed = true
        }
    }

    /// temporarily 为 true 时，即使关闭了自动折叠，也会在一段时间后收起。
    func expand(temporarily: Bool = false) {
        transition += 1
        isCollapsed = false
        scheduleAutoCollapse(force: temporarily)
    }

    private func scheduleAutoCollapse(force: Bool = false) {
        collapseTimer?.invalidate()
        guard prefs.autoCollapse || force else { return }
        let delay = prefs.autoCollapse ? prefs.collapseDelay : 10
        collapseTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.collapse()
        }
    }

    private var isSeparatorLeftOfToggle: Bool {
        guard let sep = separator.button?.window?.frame.minX,
              let tog = toggle.button?.window?.frame.minX else { return false }
        return sep < tog
    }

    // MARK: - 弹出面板

    private var currentScreen: NSScreen? { toggle.button?.window?.screen ?? NSScreen.main }

    private func togglePanel() {
        if panel.isVisible {
            panel.close()
            return
        }
        guard let screen = currentScreen,
              let separatorX = separator.button?.window?.frame.minX else { return }
        let missing = MenuBarItems.hidden(leftOf: separatorX, on: screen)
            .map(\.windowID)
            .filter { imageCache[$0] == nil && !peekedIDs.contains($0) }
        if isCollapsed && !missing.isEmpty && MenuBarItems.canCapture {
            // 例如切换屏幕后图标窗口换了一批，缓存里没有它们的截图：
            // 先短暂展开让系统画出来，截好图再弹出面板。
            peekedIDs.formUnion(missing)
            Task { @MainActor [weak self] in
                await self?.peekAndCache()
                self?.showPanel()
            }
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let screen = currentScreen,
              let anchor = toggle.button?.window?.frame,
              let separatorX = separator.button?.window?.frame.minX else { return }
        let items = MenuBarItems.hidden(leftOf: separatorX, on: screen).map { item in
            var item = item
            item.image = imageCache[item.windowID]
            return item
        }
        panel.show(items: items, below: anchor)
    }

    /// 不触发自动折叠地展开一瞬间，截图后立即收回。
    @MainActor
    private func peekAndCache() async {
        transition += 1
        let current = transition
        isCollapsed = false
        try? await Task.sleep(nanoseconds: 250_000_000)
        await refreshImageCache()
        guard current == transition, isSeparatorLeftOfToggle else { return }
        isCollapsed = true
    }

    @MainActor
    private func refreshImageCache() async {
        guard MenuBarItems.canCapture,
              let screen = currentScreen,
              let separatorX = separator.button?.window?.frame.minX else { return }
        let visible = MenuBarItems.all(on: screen)
            .filter { $0.frame.maxX <= separatorX + 1 && $0.frame.minX >= screen.frame.minX }
        let images = await MenuBarItems.captureImages(for: visible)
        let alive = Set(MenuBarItems.all().map(\.windowID))
        imageCache = imageCache.filter { alive.contains($0.key) }.merging(images) { _, new in new }
        peekedIDs.formIntersection(alive)
    }

    /// 打开（激活）图标所属的应用，菜单栏保持收起。
    private func openApp(_ item: MenuBarItem) {
        let trusted = MenuBarItems.ensureAccessibility(prompt: false)
        let app = MenuBarItems.owningApp(ofItemAt: item.frame, ownerPID: trusted ? item.ownerPID : nil)
            ?? NSRunningApplication(processIdentifier: item.ownerPID).flatMap {
                $0.bundleIdentifier == "com.apple.controlcenter" ? nil : $0
            }
        guard let app, let url = app.bundleURL else {
            Log.write("openApp: owner of window \(item.windowID) not found (accessibility \(trusted))")
            NSSound.beep()
            return
        }
        Log.write("openApp: \(app.localizedName ?? "?") at \(url.path)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    // MARK: - 临时显示（Bartender 式）

    /// 把隐藏的图标挪到 ‹ 左边（分隔符右边，即可见区域），收起菜单栏后再按下它，
    /// 这样它的菜单就在 ‹ 和面板附近弹出。菜单用完后再放回隐藏区。
    private func showInPlace(_ item: MenuBarItem) {
        guard MenuBarItems.ensureAccessibility(prompt: true) else {
            Log.write("showInPlace: no accessibility, expanding instead")
            expand(temporarily: true)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let previous = self.shownItem { await self.rehide(previous) }

            self.transition += 1
            self.collapseTimer?.invalidate()
            self.isCollapsed = false
            try? await Task.sleep(nanoseconds: 300_000_000)

            guard let toggleFrame = self.cgFrame(of: self.toggle) else { return }
            let moved = await MenuBarItems.move(item.windowID,
                                                to: CGPoint(x: toggleFrame.minX + 2, y: toggleFrame.midY))
            if moved {
                self.shownItem = item.windowID
                self.collapseNow()
                try? await Task.sleep(nanoseconds: 350_000_000)
            } else {
                // 挪不动时退回到在原位置打开，并照常自动收起。
                self.scheduleAutoCollapse(force: true)
            }

            guard let frame = MenuBarItems.frame(of: item.windowID) else { return }
            Log.write("showInPlace: pressing window \(item.windowID) at \(frame)")
            if !MenuBarItems.press(itemAt: frame, ownerPID: item.ownerPID) {
                MenuBarItems.click(at: CGPoint(x: frame.midX, y: frame.midY))
            }
            if moved { self.startRehideWatch() }
        }
    }

    /// 把临时显示的图标拖回分隔符左边。
    @MainActor
    private func rehide(_ windowID: CGWindowID) async {
        stopRehideWatch()
        shownItem = nil
        let wasCollapsed = isCollapsed
        transition += 1
        collapseTimer?.invalidate()
        isCollapsed = false
        try? await Task.sleep(nanoseconds: 300_000_000)
        if let separatorFrame = cgFrame(of: separator) {
            _ = await MenuBarItems.move(windowID, to: CGPoint(x: separatorFrame.minX + 1, y: separatorFrame.midY))
        }
        if wasCollapsed { collapseNow() } else { scheduleAutoCollapse() }
    }

    /// 菜单关闭后的下一次点击（最迟 60 秒后）把图标放回隐藏区。
    private func startRehideWatch() {
        stopRehideWatch()
        let started = Date()
        rehideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard Date().timeIntervalSince(started) > 0.5 else { return }
            self?.scheduleRehide(after: 0.8)
        }
        scheduleRehide(after: 60)
    }

    private func scheduleRehide(after delay: TimeInterval) {
        rehideTimer?.invalidate()
        rehideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let windowID = self.shownItem else { return }
                await self.rehide(windowID)
            }
        }
    }

    private func stopRehideWatch() {
        if let rehideMonitor { NSEvent.removeMonitor(rehideMonitor) }
        rehideMonitor = nil
        rehideTimer?.invalidate()
        rehideTimer = nil
    }

    /// 立即收起，不再截图（调用方已经处理好缓存）。
    private func collapseNow() {
        guard isSeparatorLeftOfToggle else { return }
        transition += 1
        collapseTimer?.invalidate()
        isCollapsed = true
    }

    /// 状态项在全局坐标（左上角为原点）中的位置。
    private func cgFrame(of item: NSStatusItem) -> CGRect? {
        guard let frame = item.button?.window?.frame else { return nil }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        return CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
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

    /// 左键：弹出面板或展开（按住 ⌥ 时用另一种方式）；右键或 ⌃ 点击：菜单。
    @objc private func toggleClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let flags = event?.modifierFlags ?? []
        if event?.type == .rightMouseUp || flags.contains(.control) {
            panel.close()
            showMenu(from: sender)
        } else if !isCollapsed {
            panel.close()
            collapse()
        } else if prefs.clickOpensPanel != flags.contains(.option) {
            if let windowID = shownItem, !panel.isVisible {
                // 先把上次临时显示的图标放回去，面板里才会有它。
                Task { @MainActor [weak self] in
                    await self?.rehide(windowID)
                    self?.togglePanel()
                }
            } else {
                togglePanel()
            }
        } else {
            expand()
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "设置…", action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let log = NSMenuItem(title: "显示日志", action: #selector(showLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 BarMatrix", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func settingsClicked() { openSettings() }

    @objc private func showLog() {
        if !FileManager.default.fileExists(atPath: Log.url.path) { Log.write("log created") }
        NSWorkspace.shared.activateFileViewerSelecting([Log.url])
    }
}
