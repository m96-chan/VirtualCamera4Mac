import Testing
@testable import VirtualCameraCore

@Suite("Camera format")
struct CameraFormatTests {
    @Test("label describes size, pixel format, and frame rate")
    func label() {
        #expect(CameraFormat(width: 1280, height: 720, pixelFormat: .bgra, frameRate: 30).label
                == "1280x720 BGRA 30fps")
        #expect(CameraFormat(width: 1920, height: 1080, pixelFormat: .nv12, frameRate: 30).label
                == "1920x1080 NV12 30fps")
    }
}
