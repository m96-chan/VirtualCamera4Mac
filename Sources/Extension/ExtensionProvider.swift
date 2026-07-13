import Foundation
import CoreMediaIO
import IOKit.audio
import os.log
import VirtualCameraCore

private let logger = Logger(subsystem: "io.github.m96chan.VirtualCamera4Mac.Extension",
                            category: "Extension")

/// The advertised format matrix, sourced from the pure core so the extension and
/// the tested logic agree on what is advertised (issue #3).
private let formatCatalog = FormatCatalog.standard

private func cvPixelFormat(for pixelFormat: CameraFormat.PixelFormat) -> OSType {
    switch pixelFormat {
    case .bgra: return kCVPixelFormatType_32BGRA
    case .nv12: return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }
}

private func makeVideoDescription(for format: CameraFormat) -> CMFormatDescription {
    var description: CMFormatDescription!
    CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                   codecType: cvPixelFormat(for: format.pixelFormat),
                                   width: Int32(format.width),
                                   height: Int32(format.height),
                                   extensions: nil,
                                   formatDescriptionOut: &description)
    return description
}

private func makeStreamFormat(for format: CameraFormat) -> CMIOExtensionStreamFormat {
    let frameDuration = CMTime(value: 1, timescale: Int32(format.frameRate))
    return CMIOExtensionStreamFormat(formatDescription: makeVideoDescription(for: format),
                                     maxFrameDuration: frameDuration,
                                     minFrameDuration: frameDuration,
                                     validFrameDurations: nil)
}

// MARK: - Device Source

/// Backs the always-present virtual camera device and drives the static
/// test-pattern frames. Advertises the full format matrix (#3) and rebuilds its
/// buffer pool when the consumer selects a different format. Producer transport
/// is #4; richer standby art is #2.
final class ExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {

    private(set) var device: CMIOExtensionDevice!
    private var _streamSource: ExtensionStreamSource!

    /// Number of active clients; the timer runs while > 0.
    private var _streamingCounter: UInt32 = 0
    private var _timer: DispatchSourceTimer?
    private let _timerQueue = DispatchQueue(label: "io.github.m96chan.VirtualCamera4Mac.timer",
                                            qos: .userInteractive)

    private var _activeFormat: CameraFormat = formatCatalog.defaultFormat
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

        configure(for: formatCatalog.defaultFormat)

        let streamID = UUID(uuidString: "3D2C1B0A-9E8F-4A6B-8C7D-1E2F3A4B5C6D")!
        _streamSource = ExtensionStreamSource(localizedName: "VirtualCamera4Mac.Video",
                                              streamID: streamID,
                                              device: device)
        do {
            try device.addStream(_streamSource.stream)
        } catch {
            fatalError("Failed to add stream: \(error.localizedDescription)")
        }
    }

    /// (Re)build the pixel-buffer pool and format description for `format`.
    private func configure(for format: CameraFormat) {
        _activeFormat = format
        _videoDescription = makeVideoDescription(for: format)

        let pixelBufferAttributes: NSDictionary = [
            kCVPixelBufferWidthKey: format.width,
            kCVPixelBufferHeightKey: format.height,
            kCVPixelBufferPixelFormatTypeKey: _videoDescription.mediaSubType,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pixelBufferAttributes, &pool)
        _bufferPool = pool
        _bufferAuxAttributes = [kCVPixelBufferPoolAllocationThresholdKey: 5]
    }

    /// Switch to the format at `index` (clamped to a valid selection). Rebuilds
    /// the buffer pool so the next frame is emitted in the new format.
    func setActiveFormat(index: Int) {
        let resolved = formatCatalog.resolvedIndex(for: index)
        guard let format = formatCatalog.format(at: resolved), format != _activeFormat else { return }
        _timerQueue.sync { configure(for: format) }
        logger.log("Active format -> \(format.label, privacy: .public)")
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

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: _timerQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(_activeFormat.frameRate),
                       leeway: .milliseconds(1))
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

        fillTestPattern(pixelBuffer)

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

    /// Static standby pattern for #1, filled per pixel format. #2 replaces this
    /// with real standby art.
    private func fillTestPattern(_ pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        switch _activeFormat.pixelFormat {
        case .bgra:
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let rows = CVPixelBufferGetHeight(pixelBuffer)
                let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
                memset(base, 0x3A, rowBytes * rows) // opaque dark gray
            }
        case .nv12:
            // Plane 0: luma (Y). Plane 1: interleaved chroma (CbCr).
            if let luma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
                let rows = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
                let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
                memset(luma, 0x40, rowBytes * rows) // dark luma
            }
            if let chroma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) {
                let rows = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
                let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
                memset(chroma, 0x80, rowBytes * rows) // neutral chroma
            }
        }
    }
}

// MARK: - Stream Source

final class ExtensionStreamSource: NSObject, CMIOExtensionStreamSource {

    private(set) var stream: CMIOExtensionStream!
    private let _device: CMIOExtensionDevice
    private let _formats: [CMIOExtensionStreamFormat]

    init(localizedName: String, streamID: UUID, device: CMIOExtensionDevice) {
        self._device = device
        self._formats = formatCatalog.formats.map(makeStreamFormat(for:))
        super.init()
        stream = CMIOExtensionStream(localizedName: localizedName,
                                     streamID: streamID,
                                     direction: .source,
                                     clockType: .hostTime,
                                     source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { _formats }

    var activeFormatIndex: Int = 0 {
        didSet {
            (_device.source as? ExtensionDeviceSource)?.setActiveFormat(index: activeFormatIndex)
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = activeFormatIndex
        }
        if properties.contains(.streamFrameDuration) {
            let frameRate = formatCatalog.format(at: activeFormatIndex)?.frameRate ?? 30
            streamProperties.frameDuration = CMTime(value: 1, timescale: Int32(frameRate))
        }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let index = streamProperties.activeFormatIndex {
            activeFormatIndex = formatCatalog.resolvedIndex(for: index)
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
        // The device is always present; no per-client setup required.
    }

    func disconnect(from client: CMIOExtensionClient) {
        // No per-client teardown required.
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
