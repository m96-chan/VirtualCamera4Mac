import SwiftUI
import AppKit
import VirtualCameraCore

@main
struct VirtualCamera4MacApp: App {
    @StateObject private var extensionManager = SystemExtensionManager()
    @StateObject private var transform = OutputTransformController()

    var body: some Scene {
        MenuBarExtra("VirtualCamera4Mac", systemImage: extensionManager.status.systemImage) {
            MenuContent(extensionManager: extensionManager, transform: transform)
                .onAppear { transform.reapply() }
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var extensionManager: SystemExtensionManager
    @ObservedObject var transform: OutputTransformController

    private var defaultFormatLabel: String {
        FormatCatalog.standard.defaultFormat.label
    }

    var body: some View {
        Text("VirtualCamera4Mac")
        Text(extensionManager.status.message)
        Text("Default format: \(defaultFormatLabel)")

        Divider()

        Toggle("Mirror (horizontal)", isOn: $transform.mirrored)
        Toggle("Flip (vertical)", isOn: $transform.flippedVertically)
        Toggle("Rotate 180°", isOn: $transform.rotated180)

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
