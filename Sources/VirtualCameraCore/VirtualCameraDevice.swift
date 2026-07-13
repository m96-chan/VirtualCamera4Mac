/// The always-present virtual camera device (issue #1).
///
/// The device is registered for its whole lifetime and its registration is
/// intentionally decoupled from the producer connection: connecting or
/// disconnecting a frame producer (e.g. AvataCam) must never make the device
/// disappear from consuming apps. Producer transport itself is out of scope
/// here and tracked by #4.
public struct VirtualCameraDevice: Sendable {
    /// `true` while the device is present to the system. It is set at creation
    /// and is never affected by producer connection changes.
    public private(set) var isRegistered: Bool

    /// Whether a frame producer is currently connected. Purely informational at
    /// this layer; it does not gate ``isRegistered``.
    public private(set) var isProducerConnected: Bool

    /// The consumer-driven stream state.
    public var stream: StreamStateMachine

    /// Formats advertised to consuming apps, available even with no producer.
    public let formatCatalog: FormatCatalog

    public init(formatCatalog: FormatCatalog = .standard) {
        self.isRegistered = true
        self.isProducerConnected = false
        self.stream = StreamStateMachine()
        self.formatCatalog = formatCatalog
    }

    /// Records whether a producer is connected. Deliberately has no effect on
    /// ``isRegistered`` so the device stays present across reconnects.
    public mutating func setProducerConnected(_ connected: Bool) {
        isProducerConnected = connected
    }
}
