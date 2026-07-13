import SwiftUI
import AppKit
import VirtualCameraCore

@main
struct VirtualCamera4MacApp: App {
    @StateObject private var extensionManager = SystemExtensionManager()

    var body: some Scene {
        MenuBarExtra("VirtualCamera4Mac", systemImage: extensionManager.status.systemImage) {
            MenuContent(extensionManager: extensionManager)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var extensionManager: SystemExtensionManager

    private var defaultFormatLabel: String {
        FormatCatalog.standard.defaultFormat.label
    }

    var body: some View {
        Text("VirtualCamera4Mac")
        Text(extensionManager.status.message)
        Text("Default format: \(defaultFormatLabel)")

        Divider()

        Button("Install / Activate") { extensionManager.activate() }
        Button("Uninstall") { extensionManager.deactivate() }
        Button("Open Login Items & Extensions") { openLoginItemsAndExtensions() }

        Divider()

        Button("Quit VirtualCamera4Mac") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func openLoginItemsAndExtensions() {
        let urls = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.security",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
