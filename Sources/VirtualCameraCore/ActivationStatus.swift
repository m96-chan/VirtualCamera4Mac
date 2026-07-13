/// User-facing state of the Camera Extension's installation/activation, shown
/// by the menu bar app (issue #5). Pure and testable — the app maps
/// `OSSystemExtensionRequest` callbacks onto these cases.
public enum ActivationStatus: Sendable, Equatable {
    case notInstalled
    case activating
    case needsApproval
    case active
    case failed(String)

    /// Whether the extension is installed and running.
    public var isActive: Bool {
        self == .active
    }

    /// Short user-facing status line.
    public var message: String {
        switch self {
        case .notInstalled:
            return "Not installed"
        case .activating:
            return "Activating…"
        case .needsApproval:
            return "Waiting for approval in System Settings → General → Login Items & Extensions"
        case .active:
            return "Active"
        case .failed(let reason):
            return "Failed: \(reason)"
        }
    }

    /// SF Symbol name representing the state.
    public var systemImage: String {
        switch self {
        case .notInstalled:  return "camera.badge.ellipsis"
        case .activating:    return "arrow.triangle.2.circlepath"
        case .needsApproval: return "exclamationmark.triangle"
        case .active:        return "checkmark.circle.fill"
        case .failed:        return "xmark.octagon.fill"
        }
    }
}
