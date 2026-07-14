import Foundation
import CoreMediaIO
import IOKit.audio
import os.log
import VirtualCameraCore

private let logger = Logger(subsystem: "io.github.m96chan.VirtualCamera4Mac.Extension",
                            category: "Extension")

extension CMIOExtensionProperty {
    /// Custom device property carrying the packed `FrameTransform` (#6). The
    /// container app sets it via CoreMediaIO (selector `xfrm`, global scope,
    /// main element); the extension applies it to outgoing frames.
    static let outputTransform = CMIOExtensionProperty(rawValue: "4cc_xfrm_glob_0000")
}

/// The advertised format matrix, sourced from the pure core (issue #3).
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

private func hostTimeNanoseconds(_ time: CMTime) -> UInt64 {
    UInt64(time.seconds * Double(NSEC_PER_SEC))
}

// MARK: - Device Source

/// Publishes a `.source` stream (camera clients consume) and a `.sink` stream
/// (a producer feeds — issue #4). The source frame loop forwards the latest
/// producer frame when live, or the standby image when the producer is absent
/// or stalled (#2). CoreMediaIO moves the frame's IOSurface across the process
/// boundary, so this is zero-copy without any XPC.
final class ExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {

    private(set) var device: CMIOExtensionDevice!
    private var _sourceStreamSource: SourceStreamSource!
    private var _sinkStreamSource: SinkStreamSource!

    private var _streamingCounter: UInt32 = 0
    private var _timer: DispatchSourceTimer?
    private let _timerQueue = DispatchQueue(label: "io.github.m96chan.VirtualCamera4Mac.timer",
                                            qos: .userInteractive)

    private var _activeFormat: CameraFormat = formatCatalog.defaultFormat
    private var _videoDescription: CMFormatDescription!
    private var _bufferPool: CVPixelBufferPool!
    private var _bufferAuxAttributes: NSDictionary!

    // Producer transport (#4). The sink drain updates these on `_timerQueue`;
    // the source loop reads them to pick live vs standby (#2).
    private let _standbyPolicy = StandbyPolicy(stallTimeout: 1.0)
    private var _producerConnected = false
    private var _latestSinkBuffer: CMSampleBuffer?
    private var _lastSinkHostTimeSeconds: Double?

    // Output transform (#6), set by the app via the custom CMIO property and
    // read/applied on `_timerQueue` in the source loop.
    private var _transform: FrameTransform = .identity
    // A pool sized to the *producer* frame (not the active format), since live
    // frames are forwarded at the producer's resolution. Rebuilt when the
    // producer's dimensions/format change. Both accessed only on `_timerQueue`.
    private var _transformPool: CVPixelBufferPool?
    private var _transformPoolKey: (width: Int, height: Int, format: OSType) = (0, 0, 0)

    init(localizedName: String) {
        super.init()

        let deviceID = UUID(uuidString: VirtualCameraIdentity.deviceUID)!
        device = CMIOExtensionDevice(localizedName: localizedName,
                                     deviceID: deviceID,
                                     legacyDeviceID: nil,
                                     source: self)

        configure(for: formatCatalog.defaultFormat)

        _sourceStreamSource = SourceStreamSource(
            localizedName: "VirtualCamera4Mac.Video",
            streamID: UUID(uuidString: "3D2C1B0A-9E8F-4A6B-8C7D-1E2F3A4B5C6D")!,
            device: device)
        _sinkStreamSource = SinkStreamSource(
            localizedName: "VirtualCamera4Mac.Input",
            streamID: UUID(uuidString: "6F5E4D3C-2B1A-4E9D-8C7B-6A5F4E3D2C1B")!,
            device: device)

        do {
            try device.addStream(_sourceStreamSource.stream)
            try device.addStream(_sinkStreamSource.stream)
        } catch {
            fatalError("Failed to add stream: \(error.localizedDescription)")
        }
    }

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

    func setActiveFormat(index: Int) {
        let resolved = formatCatalog.resolvedIndex(for: index)
        guard let format = formatCatalog.format(at: resolved), format != _activeFormat else { return }
        _timerQueue.sync { configure(for: format) }
        logger.log("Active format -> \(format.label, privacy: .public)")
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel, .outputTransform]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            deviceProperties.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            deviceProperties.model = "VirtualCamera4Mac"
        }
        if properties.contains(.outputTransform) {
            let packed = _timerQueue.sync { _transform.packed }
            deviceProperties.setPropertyState(
                CMIOExtensionPropertyState(value: NSNumber(value: packed)),
                forProperty: .outputTransform)
        }
        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
        if let state = deviceProperties.propertiesDictionary[.outputTransform],
           let number = state.value as? NSNumber {
            let transform = FrameTransform(packed: number.int32Value)
            _timerQueue.async { self._transform = transform }
            logger.log("Output transform -> rotation \(transform.rotation.rawValue, privacy: .public), mirror \(transform.mirroredHorizontally, privacy: .public), flip \(transform.flippedVertically, privacy: .public)")
        }
    }

    // MARK: Producer (sink) frames — called from the sink drain loop.

    func producerDidStart() {
        _timerQueue.async { self._producerConnected = true }
    }

    func producerDidStop() {
        _timerQueue.async {
            self._producerConnected = false
            self._latestSinkBuffer = nil
            self._lastSinkHostTimeSeconds = nil
        }
    }

    func receiveSinkFrame(_ sampleBuffer: CMSampleBuffer) {
        _timerQueue.async {
            self._latestSinkBuffer = sampleBuffer
            self._lastSinkHostTimeSeconds = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        }
    }

    // MARK: Source frame loop.

    func startStreaming() {
        guard _bufferPool != nil else { return }
        _streamingCounter += 1
        guard _timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: _timerQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(_activeFormat.frameRate),
                       leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.emitFrame() }
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

    /// Runs on `_timerQueue`. Forwards the latest producer frame when live,
    /// otherwise emits the standby image.
    private func emitFrame() {
        let age = _lastSinkHostTimeSeconds.map { CMClockGetTime(CMClockGetHostTimeClock()).seconds - $0 }
        let state = _standbyPolicy.state(producerConnected: _producerConnected, secondsSinceLastFrame: age)

        switch state {
        case .live:
            if let buffer = _latestSinkBuffer {
                sendLive(buffer)
            } else {
                emitStandby()
            }
        case .waitingForProducer, .error:
            emitStandby()
        }
    }

    /// Forwards a live producer frame, applying the output transform (#6) when
    /// one is set. The transform is size-preserving; its output buffer must
    /// match the *producer* frame (which is forwarded verbatim on the identity
    /// path), not the active format — those can differ. Any failure falls back
    /// to the untransformed frame rather than blanking the stream.
    private func sendLive(_ buffer: CMSampleBuffer) {
        guard !_transform.isIdentity,
              let source = CMSampleBufferGetImageBuffer(buffer),
              let pool = transformPool(matching: source),
              let transformed = FrameTransformApplier.apply(_transform, to: source, pool: pool),
              let sample = makeSampleBuffer(from: transformed) else {
            sendToSource(retimed(buffer))
            return
        }
        sendToSource(sample)
    }

    /// A pixel-buffer pool matching `source`'s dimensions and pixel format,
    /// rebuilt only when those change. Runs on `_timerQueue`.
    private func transformPool(matching source: CVPixelBuffer) -> CVPixelBufferPool? {
        let key = (width: CVPixelBufferGetWidth(source),
                   height: CVPixelBufferGetHeight(source),
                   format: CVPixelBufferGetPixelFormatType(source))
        if _transformPool == nil || _transformPoolKey != key {
            let attributes: NSDictionary = [
                kCVPixelBufferWidthKey: key.width,
                kCVPixelBufferHeightKey: key.height,
                kCVPixelBufferPixelFormatTypeKey: key.format,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes, &pool)
            _transformPool = pool
            _transformPoolKey = key
        }
        return _transformPool
    }

    /// Wraps a pixel buffer in a host-timed sample buffer, deriving the format
    /// description from the buffer itself so it stays correct whether the buffer
    /// is the active-format standby image or a producer-sized transformed frame.
    private func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription)
        guard let formatDescription else { return nil }

        var timingInfo = CMSampleTimingInfo()
        timingInfo.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())
        var sampleBufferOut: CMSampleBuffer?
        let sbErr = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDescription,
            sampleTiming: &timingInfo, sampleBufferOut: &sampleBufferOut)
        guard sbErr == noErr, let sampleBuffer = sampleBufferOut else {
            logger.error("Failed to create sample buffer: \(sbErr, privacy: .public)")
            return nil
        }
        return sampleBuffer
    }

    private func retimed(_ buffer: CMSampleBuffer) -> CMSampleBuffer {
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(_activeFormat.frameRate)),
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                              sampleBuffer: buffer,
                                              sampleTimingEntryCount: 1,
                                              sampleTimingArray: &timing,
                                              sampleBufferOut: &copy)
        return copy ?? buffer
    }

    private func emitStandby() {
        var pixelBufferOut: CVPixelBuffer?
        let allocErr = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault, _bufferPool, _bufferAuxAttributes, &pixelBufferOut)
        guard allocErr == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else {
            logger.error("Out of pixel buffers: \(allocErr, privacy: .public)")
            return
        }
        fillStandbyPattern(pixelBuffer)

        if let sampleBuffer = makeSampleBuffer(from: pixelBuffer) {
            sendToSource(sampleBuffer)
        }
    }

    private func sendToSource(_ sampleBuffer: CMSampleBuffer) {
        let pts = sampleBuffer.presentationTimeStamp
        _sourceStreamSource.stream.send(sampleBuffer, discontinuity: [],
                                        hostTimeInNanoseconds: hostTimeNanoseconds(pts))
    }

    /// The standby ("no signal") image (#2): horizontal bands per pixel format.
    private func fillStandbyPattern(_ pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        switch _activeFormat.pixelFormat {
        case .bgra:
            let bands: [UInt32] = [0xFF1E1E24, 0xFF2E5E8C, 0xFF3AA0A0, 0xFF6ABF4B,
                                   0xFFE0B341, 0xFFCF5C36, 0xFFA0405C, 0xFF1E1E24]
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
            let rows = CVPixelBufferGetHeight(pixelBuffer)
            let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
            for row in 0..<rows {
                var colour = bands[row * bands.count / rows]
                memset_pattern4(base + row * rowBytes, &colour, rowBytes)
            }
        case .nv12:
            let lumaBands: [UInt8] = [0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0, 0xE0, 0x20]
            if let luma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
                let rows = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
                let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
                for row in 0..<rows {
                    memset(luma + row * rowBytes, Int32(lumaBands[row * lumaBands.count / rows]), rowBytes)
                }
            }
            if let chroma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) {
                let rows = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
                let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
                memset(chroma, 0x80, rowBytes * rows)
            }
        }
    }
}

// MARK: - Source Stream Source (camera clients consume)

final class SourceStreamSource: NSObject, CMIOExtensionStreamSource {

    private(set) var stream: CMIOExtensionStream!
    private let _device: CMIOExtensionDevice
    private let _formats: [CMIOExtensionStreamFormat]

    init(localizedName: String, streamID: UUID, device: CMIOExtensionDevice) {
        self._device = device
        self._formats = formatCatalog.formats.map(makeStreamFormat(for:))
        super.init()
        stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID,
                                     direction: .source, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { _formats }

    var activeFormatIndex: Int = 0 {
        didSet { (_device.source as? ExtensionDeviceSource)?.setActiveFormat(index: activeFormatIndex) }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            props.activeFormatIndex = activeFormatIndex
        }
        if properties.contains(.streamFrameDuration) {
            let frameRate = formatCatalog.format(at: activeFormatIndex)?.frameRate ?? 30
            props.frameDuration = CMTime(value: 1, timescale: Int32(frameRate))
        }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let index = streamProperties.activeFormatIndex {
            activeFormatIndex = formatCatalog.resolvedIndex(for: index)
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { true }

    func startStream() throws {
        (_device.source as? ExtensionDeviceSource)?.startStreaming()
    }

    func stopStream() throws {
        (_device.source as? ExtensionDeviceSource)?.stopStreaming()
    }
}

// MARK: - Sink Stream Source (producer feeds)

/// The producer-facing input. A depth-1 queue makes newer frames overwrite
/// pending ones (latest-frame-wins / drop-stale). The drain loop hands each
/// consumed frame to the device, which forwards it on the source stream.
final class SinkStreamSource: NSObject, CMIOExtensionStreamSource {

    private(set) var stream: CMIOExtensionStream!
    private let _device: CMIOExtensionDevice
    private let _formats: [CMIOExtensionStreamFormat]
    private var _client: CMIOExtensionClient?
    private var _draining = false

    init(localizedName: String, streamID: UUID, device: CMIOExtensionDevice) {
        self._device = device
        self._formats = formatCatalog.formats.map(makeStreamFormat(for:))
        super.init()
        stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID,
                                     direction: .sink, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { _formats }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            props.activeFormatIndex = 0
        }
        if properties.contains(.streamSinkBufferQueueSize) {
            props.sinkBufferQueueSize = 1 // latest-frame-wins
        }
        if properties.contains(.streamSinkBuffersRequiredForStartup) {
            props.sinkBuffersRequiredForStartup = 1
        }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        _client = client
        return true
    }

    func startStream() throws {
        guard let deviceSource = _device.source as? ExtensionDeviceSource else { return }
        deviceSource.producerDidStart()
        _draining = true
        drain()
    }

    func stopStream() throws {
        _draining = false
        (_device.source as? ExtensionDeviceSource)?.producerDidStop()
    }

    private func drain() {
        guard _draining, let client = _client else { return }
        stream.consumeSampleBuffer(from: client) { [weak self] sampleBuffer, sequenceNumber, _, _, error in
            guard let self = self else { return }
            if let sampleBuffer = sampleBuffer {
                (self._device.source as? ExtensionDeviceSource)?.receiveSinkFrame(sampleBuffer)
                let output = CMIOExtensionScheduledOutput(
                    sequenceNumber: sequenceNumber,
                    hostTimeInNanoseconds: hostTimeNanoseconds(CMClockGetTime(CMClockGetHostTimeClock())))
                self.stream.notifyScheduledOutputChanged(output)
            }
            if let error = error {
                logger.error("Sink consume error: \(error.localizedDescription, privacy: .public)")
            }
            self.drain() // re-arm
        }
    }
}

// MARK: - Provider Source

final class ExtensionProviderSource: NSObject, CMIOExtensionProviderSource {

    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: ExtensionDeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = ExtensionDeviceSource(localizedName: VirtualCameraIdentity.localizedName)
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("Failed to add device: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}
    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> { [.providerManufacturer] }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let props = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            props.manufacturer = VirtualCameraIdentity.manufacturer
        }
        return props
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}
