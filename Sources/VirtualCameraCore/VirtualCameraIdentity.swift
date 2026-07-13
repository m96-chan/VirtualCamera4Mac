/// Stable identity of the virtual camera device, shared by the Camera Extension
/// and the producer SDK (issue #11). The producer discovers the running device
/// by matching ``deviceUID`` against `kCMIODevicePropertyDeviceUID`.
public enum VirtualCameraIdentity {
    /// The device UID. Must equal the `uuidString` used to create the
    /// `CMIOExtensionDevice` in the extension.
    public static let deviceUID = "B9E1C0F2-6A2E-4B7D-9C3A-2F1E7D4A5C6B"

    /// User-visible device name shown to consuming apps.
    public static let localizedName = "VirtualCamera4Mac"

    /// Manufacturer string advertised by the provider.
    public static let manufacturer = "m96-chan"
}
