import Testing
@testable import VirtualCameraCore

/// Covers issue #1: the virtual camera device is always present, independent of
/// whether a frame producer is connected.
@Suite("Virtual camera device registration")
struct VirtualCameraDeviceTests {
    @Test("Device is registered as soon as it is created")
    func deviceIsRegisteredOnCreation() {
        let device = VirtualCameraDevice()
        #expect(device.isRegistered)
    }

    @Test("Device stays registered across producer connect and disconnect")
    func deviceStaysRegisteredAcrossProducerChanges() {
        var device = VirtualCameraDevice()

        device.setProducerConnected(true)
        #expect(device.isRegistered)
        #expect(device.isProducerConnected)

        device.setProducerConnected(false)
        #expect(device.isRegistered)
        #expect(!device.isProducerConnected)
    }

    @Test("A sane default format is advertised even with no producer connected")
    func defaultFormatAvailableWithoutProducer() {
        let device = VirtualCameraDevice()
        #expect(!device.isProducerConnected)

        let format = device.formatCatalog.defaultFormat
        #expect(format.width == 1280)
        #expect(format.height == 720)
        #expect(format.pixelFormat == .bgra)
        #expect(format.frameRate == 30)
    }
}
