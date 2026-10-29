import Foundation
import ServiceManagement

/// 用户设置，变化时写入 UserDefaults。
final class Preferences: ObservableObject {
    @Published var autoCollapse: Bool { didSet { defaults.set(autoCollapse, forKey: "autoCollapse") } }
    @Published var collapseDelay: Double { didSet { defaults.set(collapseDelay, forKey: "collapseDelay") } }
    @Published var showSeparator: Bool { didSet { defaults.set(showSeparator, forKey: "showSeparator") } }
    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("BarMatrix: 无法修改登录项：\(error)")
            }
        }
    }

    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: ["autoCollapse": true, "collapseDelay": 10.0, "showSeparator": true])
        autoCollapse = defaults.bool(forKey: "autoCollapse")
        collapseDelay = defaults.double(forKey: "collapseDelay")
        showSeparator = defaults.bool(forKey: "showSeparator")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
