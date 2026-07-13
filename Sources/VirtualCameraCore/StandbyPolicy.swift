/// What the virtual camera is currently presenting to consumers (issue #2).
public enum SignalState: Sendable, Equatable {
    /// No usable producer frames — show the standby ("no signal") image.
    case waitingForProducer
    /// Live producer frames are flowing.
    case live
    /// A failure the user should know about (e.g. protocol mismatch).
    case error(String)
}

/// Decides whether to present the standby image or live frames, so a stalled or
/// absent producer never results in a black stream.
///
/// Producer transport is #4; this policy is the pure decision it will drive.
public struct StandbyPolicy: Sendable {
    /// How long since the last producer frame before the stream is considered
    /// stalled and falls back to standby, in seconds.
    public let stallTimeout: Double

    public init(stallTimeout: Double) {
        self.stallTimeout = stallTimeout
    }

    /// - Parameters:
    ///   - producerConnected: whether a producer is currently connected.
    ///   - secondsSinceLastFrame: age of the most recent producer frame, or
    ///     `nil` if no frame has arrived yet.
    public func state(producerConnected: Bool, secondsSinceLastFrame: Double?) -> SignalState {
        guard producerConnected, let age = secondsSinceLastFrame else {
            return .waitingForProducer
        }
        return age <= stallTimeout ? .live : .waitingForProducer
    }
}
