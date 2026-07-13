import Testing
@testable import VirtualCameraCore

/// Covers issue #5: the menu bar app renders the system-extension activation
/// status; this is the pure presentation logic behind it.
@Suite("Activation status")
struct ActivationStatusTests {
    @Test("Only .active reports isActive")
    func isActive() {
        #expect(ActivationStatus.active.isActive)
        #expect(!ActivationStatus.notInstalled.isActive)
        #expect(!ActivationStatus.activating.isActive)
        #expect(!ActivationStatus.needsApproval.isActive)
        #expect(!ActivationStatus.failed("x").isActive)
    }

    @Test("Each case has a non-empty user-facing message")
    func messages() {
        let cases: [ActivationStatus] = [.notInstalled, .activating, .needsApproval, .active, .failed("boom")]
        for c in cases {
            #expect(!c.message.isEmpty)
        }
        #expect(ActivationStatus.active.message == "Active")
        #expect(ActivationStatus.failed("boom").message.contains("boom"))
    }

    @Test("Each case maps to a distinct SF Symbol name")
    func symbols() {
        let symbols = Set([
            ActivationStatus.notInstalled.systemImage,
            ActivationStatus.activating.systemImage,
            ActivationStatus.needsApproval.systemImage,
            ActivationStatus.active.systemImage,
            ActivationStatus.failed("x").systemImage,
        ])
        #expect(symbols.count == 5)
        for s in symbols { #expect(!s.isEmpty) }
    }
}
