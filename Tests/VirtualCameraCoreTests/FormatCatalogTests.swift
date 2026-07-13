import Testing
@testable import VirtualCameraCore

/// Covers issue #3: the device advertises a matrix of formats and the consumer
/// selects one; invalid selections clamp to the default.
@Suite("Format catalog")
struct FormatCatalogTests {
    @Test("Standard catalog advertises 720p and 1080p in both BGRA and NV12 @ 30fps")
    func standardMatrix() {
        let formats = FormatCatalog.standard.formats
        #expect(formats.count == 4)

        let expected: [(Int, Int, CameraFormat.PixelFormat)] = [
            (1280, 720, .bgra), (1280, 720, .nv12),
            (1920, 1080, .bgra), (1920, 1080, .nv12),
        ]
        for (w, h, pf) in expected {
            #expect(formats.contains(CameraFormat(width: w, height: h, pixelFormat: pf, frameRate: 30)))
        }
    }

    @Test("Default format is 720p BGRA 30fps at index 0")
    func defaultIsSevenTwentyBGRA() {
        let catalog = FormatCatalog.standard
        #expect(catalog.defaultFormat == catalog.formats[0])
        #expect(catalog.defaultFormat == CameraFormat(width: 1280, height: 720, pixelFormat: .bgra, frameRate: 30))
    }

    @Test("format(at:) is bounds-checked")
    func formatAtBounds() {
        let catalog = FormatCatalog.standard
        #expect(catalog.format(at: 0) == catalog.formats[0])
        #expect(catalog.format(at: catalog.formats.count - 1) == catalog.formats.last)
        #expect(catalog.format(at: -1) == nil)
        #expect(catalog.format(at: catalog.formats.count) == nil)
    }

    @Test("firstIndex(of:) locates a known format and rejects an unknown one")
    func firstIndexOf() {
        let catalog = FormatCatalog.standard
        let hd = CameraFormat(width: 1920, height: 1080, pixelFormat: .nv12, frameRate: 30)
        #expect(catalog.firstIndex(of: hd) != nil)

        let unknown = CameraFormat(width: 640, height: 480, pixelFormat: .bgra, frameRate: 15)
        #expect(catalog.firstIndex(of: unknown) == nil)
    }

    @Test("resolvedIndex clamps out-of-range selections to the default index")
    func resolvedIndexClamps() {
        let catalog = FormatCatalog.standard
        #expect(catalog.resolvedIndex(for: 2) == 2)
        #expect(catalog.resolvedIndex(for: -5) == 0)
        #expect(catalog.resolvedIndex(for: 99) == 0)
    }
}
