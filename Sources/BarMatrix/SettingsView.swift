import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section {
                Label {
                    Text("按住 ⌘ 拖动菜单栏图标，把不常用的放到细竖线 │ 的左边。点击 ‹ › 折叠或展开它们。")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "hand.draw")
                }
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
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
    }
}
