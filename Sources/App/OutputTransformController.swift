import Foundation
import Combine
import CoreMediaIO
import os.log
import VirtualCameraCore

private let logger = Logger(subsystem: "io.github.m96chan.VirtualCamera4Mac",
                            category: "OutputTransform")

/// Owns the user's output-transform choice (#6): mirror, vertical flip, and
/// 180° rotation. Quarter-turn rotations change dimensions and land with
/// aspect-ratio handling (#7), so they are intentionally not exposed here yet.
///
/// The choice is persisted to `UserDefaults` and pushed to the running device
/// via the custom CMIO property (`selector 'xfrm'`). The extension applies it
/// to outgoing frames. Pushing is a no-op when the device is absent (extension
/// not yet activated), and is re-sent on launch and on every change.
final class OutputTransformController: ObservableObject {

    private static let defaultsKey = "outputTransform.packed"

    @Published var mirrored: Bool { didSet { commit() } }
    @Published var flippedVertically: Bool { didSet { commit() } }
    @Published var rotated180: Bool { didSet { commit() } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = FrameTransform(packed: Int32(truncatingIfNeeded: defaults.integer(forKey: Self.defaultsKey)))
        self.mirrored = stored.mirroredHorizontally
        self.flippedVertically = stored.flippedVertically
        self.rotated180 = (stored.rotation == .rotate180)
    }

    /// The transform assembled from the current toggles.
    var transform: FrameTransform {
        FrameTransform(rotation: rotated180 ? .rotate180 : .none,
                       mirroredHorizontally: mirrored,
                       flippedVertically: flippedVertically)
    }

    /// Re-send the current transform to the device — call once the device is
    /// available (e.g. shortly after activation) so a persisted choice is
    /// reapplied.
    func reapply() {
        push(transform)
    }

    private func commit() {
        let t = transform
        defaults.set(Int(t.packed), forKey: Self.defaultsKey)
        push(t)
    }

    // MARK: - CoreMediaIO custom property

    private func push(_ transform: FrameTransform) {
        // A silent no-op here previously masked #42: a sandboxed app without the
        // camera device entitlement finds no CMIO device, so the transform never
        // reached the extension. Log every outcome so a regression is visible in
        // the app's own log rather than invisible.
        guard let device = Self.findDevice(uid: VirtualCameraIdentity.deviceUID) else {
            logger.error("Cannot push transform \(transform.packed, privacy: .public): CMIO device not found (missing camera entitlement or extension inactive)")
            return
        }
        var address = CMIOObjectPropertyAddress(
            mSelector: Self.transformSelector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        // Custom CMIO extension properties are exchanged as a CFType (here a
        // CFNumber), not a raw scalar — sending raw Int32 bytes fails with
        // kCMIOHardwareBadPropertySizeError.
        var packed = transform.packed
        guard let number = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &packed) else { return }
        var value: CFTypeRef = number
        let status = CMIOObjectSetPropertyData(device, &address, 0, nil,
                                               UInt32(MemoryLayout<CFTypeRef>.size), &value)
        if status == noErr {
            logger.log("Pushed transform \(packed, privacy: .public) to device (rotation \(transform.rotation.rawValue, privacy: .public), mirror \(transform.mirroredHorizontally, privacy: .public), flip \(transform.flippedVertically, privacy: .public))")
        } else {
            logger.error("Failed to push transform \(packed, privacy: .public): CMIOObjectSetPropertyData status \(status, privacy: .public)")
        }
    }

    /// FourCharCode `'xfrm'`, matching the extension's custom property raw value
    /// `"4cc_xfrm_glob_0000"`.
    private static let transformSelector: CMIOObjectPropertySelector = {
        let chars = Array("xfrm".utf8)
        return CMIOObjectPropertySelector(chars.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
    }()

    private static func findDevice(uid: String) -> CMIOObjectID? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject),
                                            &address, 0, nil, &dataSize) == noErr else { return nil }
        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        guard count > 0 else { return nil }
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject),
                                        &address, 0, nil, dataSize, &used, &devices) == noErr else { return nil }

        for device in devices where deviceUID(of: device)?.caseInsensitiveCompare(uid) == .orderedSame {
            return device
        }
        return nil
    }

    private static func deviceUID(of device: CMIOObjectID) -> String? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(device, &address, 0, nil, &dataSize) == noErr else { return nil }
        var uid: CFString = "" as CFString
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, dataSize, &used, &uid) == noErr else { return nil }
        return uid as String
    }
}
