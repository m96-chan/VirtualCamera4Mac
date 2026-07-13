/// Pure decisions the producer uses to feed the extension's sink stream (#11).
/// The CoreMediaIO calls themselves are integration-only; these seams are unit
/// tested so the naming/ordering/backpressure rules stay correct.

public enum SinkStream {
    /// The device publishes the source stream first (index 0) and the sink
    /// second (index 1). Returns the sink index only when exactly that pair is
    /// present, so a producer never feeds the wrong stream.
    public static func index(forStreamCount count: Int) -> Int? {
        count == 2 ? 1 : nil
    }
}

public enum SinkBackpressure {
    /// Whether to enqueue a frame given the sink's `CMSimpleQueue` occupancy.
    /// With the extension's depth-1 queue this is strict latest-frame-wins: a
    /// new frame is dropped while the previous one is still pending.
    public static func shouldEnqueue(count: Int, capacity: Int) -> Bool {
        capacity > 0 && count < capacity
    }
}
