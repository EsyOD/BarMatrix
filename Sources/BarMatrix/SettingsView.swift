import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @State private var canCapture = MenuBarItems.canCapture
    @State private var canClick = MenuBarItems.ensureAccessibility(prompt: false)

    var body: some View {
        Form {
            Section {
                Label {
                    Text("按住 ⌘ 拖动菜单栏图标，把不常用的放到细竖线 │ 的左边，它们就会被收起来。")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "hand.draw")
                }
                .foregroundStyle(.secondary)
            }
            Section {
                Picker("点击 ‹ 时", selection: $prefs.clickOpensPanel) {
                    Text("弹出面板").tag(true)
                    Text("在菜单栏展开").tag(false)
                }
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
            } footer: {
                Text("按住 ⌥ 点击 ‹ 可以使用另一种方式。")
                    .foregroundStyle(.secondary)
            }
            Section("权限") {
                PermissionRow(title: "屏幕录制", detail: "在面板里显示隐藏的图标", granted: canCapture) {
                    CGRequestScreenCaptureAccess()
                    open("Privacy_ScreenCapture")
                }
                PermissionRow(title: "辅助功能", detail: "在面板里点击图标时打开它的菜单", granted: canClick) {
                    MenuBarItems.ensureAccessibility(prompt: true)
                    open("Privacy_Accessibility")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            canCapture = MenuBarItems.canCapture
            canClick = MenuBarItems.ensureAccessibility(prompt: false)
        }
    }

    private func open(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
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
