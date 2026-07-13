import SwiftUI

@main
struct VirtualCamera4MacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @StateObject private var extensionManager = SystemExtensionManager()

    var body: some View {
        VStack(spacing: 16) {
            Text("VirtualCamera4Mac")
                .font(.title2).bold()

            Text(extensionManager.status.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack {
                Button("Install / Activate") { extensionManager.activate() }
                    .keyboardShortcut(.defaultAction)
                Button("Uninstall") { extensionManager.deactivate() }
            }
        }
        .padding(32)
        .frame(minWidth: 420, minHeight: 220)
    }
}
