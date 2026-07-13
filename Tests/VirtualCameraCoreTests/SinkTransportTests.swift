import Testing
@testable import VirtualCameraCore

/// Covers issue #11 producer seams: which stream is the sink, and when to
/// enqueue given a depth-limited queue (latest-frame-wins).
@Suite("Sink transport")
struct SinkTransportTests {
    @Test("The sink is stream index 1 only when exactly source+sink are present")
    func sinkIndex() {
        #expect(SinkStream.index(forStreamCount: 2) == 1)
        #expect(SinkStream.index(forStreamCount: 1) == nil)
        #expect(SinkStream.index(forStreamCount: 0) == nil)
        #expect(SinkStream.index(forStreamCount: 3) == nil)
    }

    @Test("Enqueue only while the depth-limited queue has room")
    func backpressure() {
        #expect(SinkBackpressure.shouldEnqueue(count: 0, capacity: 1))
        #expect(!SinkBackpressure.shouldEnqueue(count: 1, capacity: 1))
        #expect(SinkBackpressure.shouldEnqueue(count: 2, capacity: 3))
        #expect(!SinkBackpressure.shouldEnqueue(count: 3, capacity: 3))
        #expect(!SinkBackpressure.shouldEnqueue(count: 0, capacity: 0))
    }
}
