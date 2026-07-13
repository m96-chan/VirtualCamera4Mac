import Foundation
import Testing
@testable import VirtualCameraCore

/// Covers issue #11: the extension and the producer must agree on how to
/// identify the device (the producer discovers it by this UID).
@Suite("Virtual camera identity")
struct VirtualCameraIdentityTests {
    @Test("deviceUID is a valid UUID string")
    func deviceUIDIsValidUUID() {
        #expect(UUID(uuidString: VirtualCameraIdentity.deviceUID) != nil)
    }

    @Test("localized name and manufacturer are non-empty")
    func namesArePresent() {
        #expect(!VirtualCameraIdentity.localizedName.isEmpty)
        #expect(!VirtualCameraIdentity.manufacturer.isEmpty)
    }
}
