import Testing
@testable import VirtualCameraCore

/// Covers issue #1: the consumer-driven stream can be started and stopped
/// repeatedly without entering an invalid state.
@Suite("Stream state machine")
struct StreamStateMachineTests {
    @Test("A new stream starts stopped")
    func newStreamIsStopped() {
        let machine = StreamStateMachine()
        #expect(machine.state == .stopped)
    }

    @Test("start() transitions stopped -> running and reports the change")
    func startFromStopped() {
        var machine = StreamStateMachine()
        let changed = machine.start()
        #expect(changed)
        #expect(machine.state == .running)
    }

    @Test("start() is idempotent while already running")
    func startWhileRunningIsNoop() {
        var machine = StreamStateMachine()
        machine.start()
        let changed = machine.start()
        #expect(!changed)
        #expect(machine.state == .running)
    }

    @Test("stop() transitions running -> stopped and reports the change")
    func stopFromRunning() {
        var machine = StreamStateMachine()
        machine.start()
        let changed = machine.stop()
        #expect(changed)
        #expect(machine.state == .stopped)
    }

    @Test("stop() is idempotent while already stopped")
    func stopWhileStoppedIsNoop() {
        var machine = StreamStateMachine()
        let changed = machine.stop()
        #expect(!changed)
        #expect(machine.state == .stopped)
    }

    @Test("Repeated start/stop cycles keep the state machine valid")
    func repeatedCyclesStayValid() {
        var machine = StreamStateMachine()
        for _ in 0..<100 {
            let started = machine.start()
            #expect(started)
            #expect(machine.state == .running)
            let stopped = machine.stop()
            #expect(stopped)
            #expect(machine.state == .stopped)
        }
        #expect(machine.state == .stopped)
    }
}
