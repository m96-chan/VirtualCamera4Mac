import Testing
@testable import VirtualCameraCore

/// Covers issue #4: a producer feeds frames into the sink stream; NV12 (biplanar
/// 4:2:0) requires even pixel dimensions, BGRA does not.
@Suite("Camera format validation")
struct CameraFormatValidationTests {
    @Test("BGRA accepts any pixel dimensions")
    func bgraAnyDimensions() {
        #expect(CameraFormat(width: 1280, height: 720, pixelFormat: .bgra, frameRate: 30).hasValidPixelDimensions)
        #expect(CameraFormat(width: 641, height: 481, pixelFormat: .bgra, frameRate: 30).hasValidPixelDimensions)
    }

    @Test("NV12 requires even width and height")
    func nv12RequiresEvenDimensions() {
        #expect(CameraFormat(width: 1280, height: 720, pixelFormat: .nv12, frameRate: 30).hasValidPixelDimensions)
        #expect(!CameraFormat(width: 641, height: 720, pixelFormat: .nv12, frameRate: 30).hasValidPixelDimensions)
        #expect(!CameraFormat(width: 1280, height: 481, pixelFormat: .nv12, frameRate: 30).hasValidPixelDimensions)
        #expect(!CameraFormat(width: 641, height: 481, pixelFormat: .nv12, frameRate: 30).hasValidPixelDimensions)
    }

    @Test("The full advertised matrix has valid dimensions")
    func advertisedMatrixValid() {
        for format in FormatCatalog.standard.formats {
            #expect(format.hasValidPixelDimensions)
        }
    }
}
