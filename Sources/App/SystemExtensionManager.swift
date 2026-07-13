import Foundation
import SystemExtensions
import os.log
import VirtualCameraCore

private let logger = Logger(subsystem: "io.github.m96chan.VirtualCamera4Mac",
                            category: "SystemExtension")

/// Drives activation/deactivation of the embedded Camera Extension and publishes
/// the user-facing ``ActivationStatus`` for the menu bar app (issue #5).
final class SystemExtensionManager: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {

    @Published private(set) var status: ActivationStatus = .notInstalled

    /// The embedded extension's bundle identifier, discovered from the app
    /// bundle so it always matches what was actually shipped.
    private var extensionBundleIdentifier: String? {
        let dir = URL(fileURLWithPath: "Contents/Library/SystemExtensions",
                      relativeTo: Bundle.main.bundleURL)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles),
              let bundleURL = contents.first(where: { $0.pathExtension == "systemextension" }),
              let identifier = Bundle(url: bundleURL)?.bundleIdentifier else {
            return nil
        }
        return identifier
    }

    func activate() {
        guard let identifier = extensionBundleIdentifier else {
            status = .failed("Embedded extension not found")
            logger.error("Embedded system extension not found in app bundle")
            return
        }
        status = .activating
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func deactivate() {
        guard let identifier = extensionBundleIdentifier else { return }
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    // MARK: OSSystemExtensionRequestDelegate

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        // Always adopt the version bundled with the current app build.
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        status = .needsApproval
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            status = .active
        case .willCompleteAfterReboot:
            status = .needsApproval
        @unknown default:
            status = .active
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        logger.error("System extension request failed: \(error.localizedDescription, privacy: .public)")
        status = .failed(error.localizedDescription)
    }
}
