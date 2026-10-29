import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Preferences()
    private var controller: MenuBarController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MenuBarController(prefs: prefs) { [weak self] in self?.showSettings() }
    }

    private func showSettings() {
        guard let controller else { return }
        if settingsWindow == nil {
            let view = SettingsView(prefs: prefs, items: ItemsModel(controller: controller))
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "BarMatrix"
            window.styleMask.remove([.resizable, .miniaturizable])
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // 不显示 Dock 图标
app.run()
