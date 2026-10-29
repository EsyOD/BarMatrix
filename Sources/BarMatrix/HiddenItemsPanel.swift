import AppKit
import SwiftUI

/// 折叠按钮下方弹出的小面板，列出被隐藏的图标。
final class HiddenItemsPanel {
    enum State {
        case loading
        case needsPermission
        case empty
        case items([MenuBarItem])
    }

    final class Model: ObservableObject {
        @Published var state = State.loading
        @Published var canClick = true
        var onRequestAccessibility: () -> Void = {}
        var onSelect: (MenuBarItem) -> Void = { _ in }
        var onRequestPermission: () -> Void = {}
        /// 鼠标当前悬停的图标，右键时用来确定点的是哪个。
        var hoveredID: CGWindowID?
    }

    private let model: Model
    private let window: NSPanel
    private let hosting: FirstMouseHostingView<HiddenItemsView>
    private var clickMonitor: Any?
    private var rightClickMonitor: Any?
    private var loadTask: Task<Void, Never>?

    var isVisible: Bool { window.isVisible }
    var onSelect: (MenuBarItem) -> Void = { _ in }
    var onSecondarySelect: (MenuBarItem) -> Void = { _ in }

    init() {
        let model = Model()
        self.model = model
        window = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: true)
        window.isFloatingPanel = true
        window.level = .popUpMenu
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: 10)

        hosting = FirstMouseHostingView(rootView: HiddenItemsView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        window.contentView = background

        model.onSelect = { [weak self] item in self?.select(item) }
        model.onRequestAccessibility = { [weak self] in
            self?.close()
            MenuBarItems.ensureAccessibility(prompt: true)
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        model.onRequestPermission = { [weak self] in
            self?.close()
            CGRequestScreenCaptureAccess()
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    /// 在 anchor（折叠按钮所在的屏幕区域）下方显示面板。
    func show(items: [MenuBarItem], below anchor: NSRect) {
        loadTask?.cancel()
        model.canClick = MenuBarItems.ensureAccessibility(prompt: false)
        if items.isEmpty {
            model.state = .empty
        } else if !MenuBarItems.canCapture {
            model.state = .needsPermission
        } else {
            // 先显示缓存的截图（没有时用占位），实时截图成功后替换。
            model.state = .items(items)
            loadTask = Task { @MainActor [weak self] in
                let images = await MenuBarItems.captureImages(for: items)
                guard let self, !Task.isCancelled, self.window.isVisible else { return }
                self.model.state = .items(items.map { item in
                    var item = item
                    item.image = images[item.windowID] ?? item.image
                    return item
                })
                self.layout(below: anchor)
            }
        }
        layout(below: anchor)
        window.orderFrontRegardless()
        window.makeKey()
        startMonitoringClicks()
    }

    func close() {
        loadTask?.cancel()
        window.orderOut(nil)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let rightClickMonitor { NSEvent.removeMonitor(rightClickMonitor) }
        clickMonitor = nil
        rightClickMonitor = nil
    }

    private func select(_ item: MenuBarItem) {
        Log.write("panel: selected window \(item.windowID) (\(item.appName))")
        close()
        onSelect(item)
    }

    private func layout(below anchor: NSRect) {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var origin = NSPoint(x: anchor.maxX - size.width, y: anchor.minY - size.height - 6)
        origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - size.width - 8))
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// 点击面板以外的地方时关闭。
    private func startMonitoringClicks() {
        guard clickMonitor == nil else { return }
        // 右键面板里的图标：改为弹出它的菜单。
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, event.window === self.window,
                  case .items(let items) = self.model.state,
                  let item = items.first(where: { $0.windowID == self.model.hoveredID })
            else { return event }
            self.close()
            Log.write("panel: right-clicked window \(item.windowID)")
            self.onSecondarySelect(item)
            return nil
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// 无边框面板默认不能成为 key window，第一次点击会被用来激活窗口而不是按钮。
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct HiddenItemsView: View {
    @ObservedObject var model: HiddenItemsPanel.Model

    var body: some View {
        content
            .font(.system(size: 12))
            .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().controlSize(.small).padding(12)
        case .empty:
            Text("没有隐藏的图标\n按住 ⌘ 把图标拖到 │ 左边")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        case .needsPermission:
            VStack(spacing: 8) {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                Text("显示隐藏图标需要「屏幕录制」权限")
                Button("前往授权") { model.onRequestPermission() }
                    .controlSize(.small)
            }
            .padding(14)
        case .items(let items):
            VStack(spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(items) { item in
                        ItemButton(item: item) { model.onSelect(item) }
                            .onHover { inside in
                                if inside { model.hoveredID = item.windowID }
                                else if model.hoveredID == item.windowID { model.hoveredID = nil }
                            }
                    }
                }
                if !model.canClick {
                    Button { model.onRequestAccessibility() } label: {
                        Label("识别图标所属的应用需要「辅助功能」权限", systemImage: "hand.tap")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 2)
                }
            }
            .padding(5)
        }
    }
}

private struct ItemButton: View {
    let item: MenuBarItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            icon
                .frame(width: max(item.frame.width, 24), height: max(item.frame.height, 22))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(hovering ? 0.12 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.appName)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = item.image {
            Image(decorative: image, scale: CGFloat(image.width) / max(item.frame.width, 1))
        } else if let appIcon = item.appIcon {
            Image(nsImage: appIcon).resizable().frame(width: 16, height: 16)
        } else {
            Image(systemName: "app.dashed").foregroundStyle(.secondary)
        }
    }
}
