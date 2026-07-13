/// Tracks the consumer-driven stream state of the virtual camera.
///
/// The device stays registered regardless of this state (see
/// ``VirtualCameraDevice``); this only models whether a consuming app has
/// started the stream. Transitions are idempotent so repeated start/stop cycles
/// from consuming apps never produce an invalid state.
public struct StreamStateMachine: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case stopped
        case running
    }

    public private(set) var state: State

    public init() {
        self.state = .stopped
    }

    /// Starts the stream.
    /// - Returns: `true` if the state changed (`stopped` -> `running`),
    ///   `false` if it was already running (no-op).
    @discardableResult
    public mutating func start() -> Bool {
        guard state == .stopped else { return false }
        state = .running
        return true
    }

    /// Stops the stream.
    /// - Returns: `true` if the state changed (`running` -> `stopped`),
    ///   `false` if it was already stopped (no-op).
    @discardableResult
    public mutating func stop() -> Bool {
        guard state == .running else { return false }
        state = .stopped
        return true
    }
}
