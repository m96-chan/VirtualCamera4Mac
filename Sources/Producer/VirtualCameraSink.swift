import Foundation
import CoreMediaIO
import CoreMedia
import CoreVideo
import VirtualCameraCore

/// Producer client that feeds VirtualCamera4Mac's CMIO **sink** stream (#11).
///
/// The extension publishes a source stream (camera clients consume) and a sink
/// stream (this feeds). CoreMediaIO moves the frame's IOSurface across the
/// process boundary, so pushing IOSurface-backed `CVPixelBuffer`s is zero-copy.
/// Requires linking `CoreMediaIO`.
public final class VirtualCameraSink {

    public enum ConnectError: Error {
        case deviceNotFound
        case unexpectedStreamLayout
        case bufferQueueUnavailable
        case streamStartFailed(OSStatus)
    }

    private let deviceID: CMIOObjectID
    private let sinkStreamID: CMIOStreamID
    private let queue: CMSimpleQueue
    private var formatDescription: CMFormatDescription?
    private let frameRate: Int32

    /// Connects to the running virtual camera device and starts its sink stream.
    /// The device only appears once the extension is activated; callers should
    /// retry if this throws `.deviceNotFound` right after activation.
    public init(frameRate: Int32 = 30) throws {
        self.frameRate = frameRate

        guard let device = Self.findDevice(uid: VirtualCameraIdentity.deviceUID) else {
            throw ConnectError.deviceNotFound
        }
        self.deviceID = device

        let streams = Self.streams(of: device)
        guard let sinkIndex = SinkStream.index(forStreamCount: streams.count) else {
            throw ConnectError.unexpectedStreamLayout
        }
        self.sinkStreamID = streams[sinkIndex]

        guard let queue = Self.copyBufferQueue(for: sinkStreamID) else {
            throw ConnectError.bufferQueueUnavailable
        }
        self.queue = queue

        let status = CMIODeviceStartStream(deviceID, sinkStreamID)
        guard status == noErr else { throw ConnectError.streamStartFailed(status) }
    }

    deinit {
        CMIODeviceStopStream(deviceID, sinkStreamID)
    }

    /// Feeds one IOSurface-backed pixel buffer. On the depth-1 queue this is
    /// latest-frame-wins: if the extension has not drained the previous frame,
    /// the new one is dropped. The pixel format/size must match a format the
    /// sink advertises (see `FormatCatalog`).
    /// - Returns: `true` if the frame was enqueued, `false` if dropped.
    @discardableResult
    public func send(_ pixelBuffer: CVPixelBuffer,
                     presentationTime: CMTime = CMClockGetTime(CMClockGetHostTimeClock())) -> Bool {
        guard SinkBackpressure.shouldEnqueue(count: Int(CMSimpleQueueGetCount(queue)),
                                             capacity: Int(CMSimpleQueueGetCapacity(queue))) else {
            return false
        }

        if formatDescription == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                formatDescriptionOut: &formatDescription)
        }
        guard let formatDescription else { return false }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: frameRate),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        let err = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDescription,
            sampleTiming: &timing, sampleBufferOut: &sampleBuffer)
        guard err == noErr, let sampleBuffer else { return false }

        // The queue does not retain; hand off a +1 the consumer (extension) releases.
        let element = UnsafeMutableRawPointer(Unmanaged.passRetained(sampleBuffer).toOpaque())
        let enqueued = CMSimpleQueueEnqueue(queue, element: element)
        if enqueued != noErr {
            Unmanaged<CMSampleBuffer>.fromOpaque(element).release() // balance on failure
            return false
        }
        return true
    }

    // MARK: - CoreMediaIO discovery

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

    private static func streams(of device: CMIOObjectID) -> [CMIOStreamID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(device, &address, 0, nil, &dataSize) == noErr else { return [] }
        let count = Int(dataSize) / MemoryLayout<CMIOStreamID>.size
        guard count > 0 else { return [] }
        var streams = [CMIOStreamID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, dataSize, &used, &streams) == noErr else { return [] }
        return streams
    }

    private static func copyBufferQueue(for stream: CMIOStreamID) -> CMSimpleQueue? {
        let queuePtr = UnsafeMutablePointer<Unmanaged<CMSimpleQueue>?>.allocate(capacity: 1)
        defer { queuePtr.deallocate() }
        // The dequeue callback signals room is available; we poll occupancy in
        // `send`, so an empty callback is sufficient.
        let status = CMIOStreamCopyBufferQueue(stream, { _, _, _ in }, nil, queuePtr)
        guard status == noErr, let queue = queuePtr.pointee else { return nil }
        return queue.takeRetainedValue()
    }
}
