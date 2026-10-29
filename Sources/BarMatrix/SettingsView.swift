import SwiftUI
import AppKit

/// 设置里的菜单栏图标列表。
final class ItemsModel: ObservableObject {
    struct Row: Identifiable {
        let item: MenuBarItem
        let name: String
        let icon: NSImage?
        var isHidden: Bool
        var id: CGWindowID { item.windowID }
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var busy = false
    private let controller: MenuBarController

    init(controller: MenuBarController) {
        self.controller = controller
    }

    func refresh() {
        let entries = controller.items()
        let names = MenuBarItems.describe(entries.map(\.item))
        rows = entries.map { entry in
            let info = names[entry.item.windowID]
            return Row(item: entry.item, name: info?.name ?? entry.item.appName,
                       icon: info?.icon ?? entry.item.appIcon, isHidden: entry.isHidden)
        }
    }

    func set(_ row: Row, hidden: Bool) {
        guard !busy, row.isHidden != hidden else { return }
        busy = true
        Task { @MainActor in
            if !(await controller.setHidden(row.item, hidden)) { NSSound.beep() }
            // 挪动后窗口位置变了，重新读一遍。
            refresh()
            busy = false
        }
    }
}

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var items: ItemsModel
    @State private var canMove = MenuBarItems.ensureAccessibility(prompt: false)

    var body: some View {
        Form {
            Section {
                if items.rows.isEmpty {
                    Text("没有找到其他菜单栏图标").foregroundStyle(.secondary)
                }
                ForEach(items.rows) { row in
                    Toggle(isOn: Binding(get: { !row.isHidden },
                                         set: { items.set(row, hidden: !$0) })) {
                        HStack(spacing: 8) {
                            Group {
                                if let icon = row.icon {
                                    Image(nsImage: icon).resizable()
                                } else {
                                    Image(systemName: "menubar.rectangle").resizable().scaledToFit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 18, height: 18)
                            Text(row.name).lineLimit(1)
                        }
                    }
                    .disabled(items.busy || !canMove)
                }
            } header: {
                HStack {
                    Text("菜单栏图标")
                    Spacer()
                    Button("刷新") { items.refresh() }
                        .buttonStyle(.borderless)
                        .disabled(items.busy)
                }
            } footer: {
                Text(canMove
                     ? "关掉的图标会放到 ‹ 里收起来。也可以按住 ⌘ 直接拖动菜单栏图标。"
                     : "需要先授予「辅助功能」权限才能在这里切换。也可以按住 ⌘ 把图标拖到细竖线 │ 左边。")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("自动折叠", isOn: $prefs.autoCollapse)
                if prefs.autoCollapse {
                    Picker("展开后", selection: $prefs.collapseDelay) {
                        Text("5 秒").tag(5.0)
                        Text("10 秒").tag(10.0)
                        Text("30 秒").tag(30.0)
                        Text("1 分钟").tag(60.0)
                    }
                }
                Toggle("展开时显示分隔线", isOn: $prefs.showSeparator)
                Toggle("登录时启动", isOn: $prefs.launchAtLogin)
            }
            Section("权限") {
                PermissionRow(title: "辅助功能", detail: "在上面的列表里隐藏或显示图标", granted: canMove) {
                    MenuBarItems.ensureAccessibility(prompt: true)
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 560)
        .onAppear { items.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            canMove = MenuBarItems.ensureAccessibility(prompt: false)
            items.refresh()
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let request: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("已授权", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
            } else {
                Button("授权…", action: request)
            }
        }
    }
}
