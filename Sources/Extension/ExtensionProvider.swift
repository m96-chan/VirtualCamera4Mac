import Foundation
import CoreMediaIO
import IOKit.audio
import os.log
import VirtualCameraCore

private let logger = Logger(subsystem: "io.github.m96chan.VirtualCamera4Mac.Extension",
                            category: "Extension")

/// The device's advertised format, sourced from the pure core so the extension
/// and the tested logic agree on what is advertised (issue #1 / baseline #3).
private let advertisedFormat = FormatCatalog.standard.defaultFormat

private func cvPixelFormat(for pixelFormat: CameraFormat.PixelFormat) -> OSType {
    switch pixelFormat {
    case .bgra: return kCVPixelFormatType_32BGRA
    case .nv12: return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }
}

// MARK: - Device Source

/// Backs the always-present virtual camera device and drives the static
/// test-pattern frames (issue #1). Producer transport is #4; richer standby art
/// is #2 — here we only guarantee the device exists and streams something.
final class ExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {

    private(set) var device: CMIOExtensionDevice!
    private var _streamSource: ExtensionStreamSource!

    /// Number of active clients; the timer runs while > 0.
    private var _streamingCounter: UInt32 = 0
    private var _timer: DispatchSourceTimer?
    private let _timerQueue = DispatchQueue(label: "io.github.m96chan.VirtualCamera4Mac.timer",
                                            qos: .userInteractive)

    private var _videoDescription: CMFormatDescription!
    private var _bufferPool: CVPixelBufferPool!
    private var _bufferAuxAttributes: NSDictionary!

    init(localizedName: String) {
        super.init()

        let deviceID = UUID(uuidString: "B9E1C0F2-6A2E-4B7D-9C3A-2F1E7D4A5C6B")!
        device = CMIOExtensionDevice(localizedName: localizedName,
                                     deviceID: deviceID,
                                     legacyDeviceID: nil,
                                     source: self)

        let width = Int32(advertisedFormat.width)
        let height = Int32(advertisedFormat.height)
        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                       codecType: cvPixelFormat(for: advertisedFormat.pixelFormat),
                                       width: width,
                                       height: height,
                                       extensions: nil,
                                       formatDescriptionOut: &_videoDescription)

        let pixelBufferAttributes: NSDictionary = [
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: _videoDescription.mediaSubType,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pixelBufferAttributes, &_bufferPool)
        _bufferAuxAttributes = [kCVPixelBufferPoolAllocationThresholdKey: 5]

        let frameDuration = CMTime(value: 1, timescale: Int32(advertisedFormat.frameRate))
        let format = CMIOExtensionStreamFormat(formatDescription: _videoDescription,
                                               maxFrameDuration: frameDuration,
                                               minFrameDuration: frameDuration,
                                               validFrameDurations: nil)

        let streamID = UUID(uuidString: "3D2C1B0A-9E8F-4A6B-8C7D-1E2F3A4B5C6D")!
        _streamSource = ExtensionStreamSource(localizedName: "VirtualCamera4Mac.Video",
                                              streamID: streamID,
                                              streamFormat: format,
                                              device: device)
        do {
            try device.addStream(_streamSource.stream)
        } catch {
            fatalError("Failed to add stream: \(error.localizedDescription)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            deviceProperties.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            deviceProperties.model = "VirtualCamera4Mac"
        }
        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
        // No writable device properties yet.
    }

    // MARK: Frame production

    func startStreaming() {
        guard _bufferPool != nil else { return }

        _streamingCounter += 1
        guard _timer == nil else { return }

        let interval = 1.0 / Double(advertisedFormat.frameRate)
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: _timerQueue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.emitFrame()
        }
        timer.resume()
        _timer = timer
    }

    func stopStreaming() {
        if _streamingCounter > 1 {
            _streamingCounter -= 1
        } else {
            _streamingCounter = 0
            _timer?.cancel()
            _timer = nil
        }
    }

    private func emitFrame() {
        var pixelBufferOut: CVPixelBuffer?
        let allocErr = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault, _bufferPool, _bufferAuxAttributes, &pixelBufferOut)
        guard allocErr == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else {
            logger.error("Out of pixel buffers: \(allocErr, privacy: .public)")
            return
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
            // Static test pattern for #1: an opaque solid fill so the device is
            // visibly "alive" with no producer. #2 replaces this with real
            // standby art. BGRA in memory is B,G,R,A; 0x3A gives a dark teal-ish
            // gray, 0xFF alpha handled by the fill being uniform.
            memset(base, 0x3A, rowBytes * height)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var timingInfo = CMSampleTimingInfo()
        timingInfo.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())

        var sampleBufferOut: CMSampleBuffer?
        let sbErr = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: _videoDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBufferOut)

        guard sbErr == noErr, let sampleBuffer = sampleBufferOut else {
            logger.error("Failed to create sample buffer: \(sbErr, privacy: .public)")
            return
        }

        _streamSource.stream.send(
            sampleBuffer,
            discontinuity: [],
            hostTimeInNanoseconds: UInt64(timingInfo.presentationTimeStamp.seconds * Double(NSEC_PER_SEC)))
    }
}

// MARK: - Stream Source

final class ExtensionStreamSource: NSObject, CMIOExtensionStreamSource {

    private(set) var stream: CMIOExtensionStream!
    private let _device: CMIOExtensionDevice
    private let _streamFormat: CMIOExtensionStreamFormat

    init(localizedName: String,
         streamID: UUID,
         streamFormat: CMIOExtensionStreamFormat,
         device: CMIOExtensionDevice) {
        self._device = device
        self._streamFormat = streamFormat
        super.init()
        stream = CMIOExtensionStream(localizedName: localizedName,
                                     streamID: streamID,
                                     direction: .source,
                                     clockType: .hostTime,
                                     source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [_streamFormat] }

    var activeFormatIndex: Int = 0

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = CMTime(value: 1, timescale: Int32(advertisedFormat.frameRate))
        }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let index = streamProperties.activeFormatIndex {
            activeFormatIndex = index
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        true
    }

    func startStream() throws {
        guard let deviceSource = _device.source as? ExtensionDeviceSource else {
            fatalError("Unexpected device source type")
        }
        deviceSource.startStreaming()
    }

    func stopStream() throws {
        guard let deviceSource = _device.source as? ExtensionDeviceSource else {
            fatalError("Unexpected device source type")
        }
        deviceSource.stopStreaming()
    }
}

// MARK: - Provider Source

final class ExtensionProviderSource: NSObject, CMIOExtensionProviderSource {

    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: ExtensionDeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = ExtensionDeviceSource(localizedName: "VirtualCamera4Mac")
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("Failed to add device: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {
        // The device is always present; no per-client setup required for #1.
    }

    func disconnect(from client: CMIOExtensionClient) {
        // No per-client teardown required for #1.
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            providerProperties.manufacturer = "m96-chan"
        }
        return providerProperties
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {
        // No writable provider properties yet.
    }
}
