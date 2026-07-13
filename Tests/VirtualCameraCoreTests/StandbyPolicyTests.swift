import Testing
@testable import VirtualCameraCore

/// Covers issue #2: decide when the device shows the standby ("no signal")
/// image versus live producer frames.
@Suite("Standby policy")
struct StandbyPolicyTests {
    private let policy = StandbyPolicy(stallTimeout: 1.0)

    @Test("No producer connected -> waiting for producer")
    func disconnected() {
        #expect(policy.state(producerConnected: false, secondsSinceLastFrame: nil) == .waitingForProducer)
        #expect(policy.state(producerConnected: false, secondsSinceLastFrame: 0.1) == .waitingForProducer)
    }

    @Test("Connected but no frame yet -> waiting for producer")
    func connectedNoFrame() {
        #expect(policy.state(producerConnected: true, secondsSinceLastFrame: nil) == .waitingForProducer)
    }

    @Test("Connected with a recent frame -> live")
    func connectedRecent() {
        #expect(policy.state(producerConnected: true, secondsSinceLastFrame: 0.0) == .live)
        #expect(policy.state(producerConnected: true, secondsSinceLastFrame: 1.0) == .live)
    }

    @Test("Connected but the producer stalled past the timeout -> waiting for producer")
    func connectedStalled() {
        #expect(policy.state(producerConnected: true, secondsSinceLastFrame: 1.5) == .waitingForProducer)
    }

    @Test("Error state is a distinct case carrying a message")
    func errorState() {
        let state: SignalState = .error("protocol mismatch")
        #expect(state != .waitingForProducer)
        #expect(state != .live)
        #expect(state == .error("protocol mismatch"))
    }
}
