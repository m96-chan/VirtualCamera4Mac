import Testing
@testable import VirtualCameraCore

/// Covers issue #6: mirror / flip / rotate output transforms. These tests pin
/// down the pure geometry — output dimensions and the inverse pixel mapping the
/// extension's vImage pipeline must reproduce. Composition order is fixed:
/// rotate clockwise → mirror horizontally → flip vertically.
@Suite("Frame transform")
struct FrameTransformTests {

    // MARK: Rotation enum

    @Test("Rotation raw values are degrees and cover all four quarter turns")
    func rotationCases() {
        #expect(Rotation.none.rawValue == 0)
        #expect(Rotation.clockwise90.rawValue == 90)
        #expect(Rotation.rotate180.rawValue == 180)
        #expect(Rotation.clockwise270.rawValue == 270)
        #expect(Rotation.allCases.count == 4)
    }

    @Test("Only the quarter turns swap width and height")
    func rotationSwapsDimensions() {
        #expect(Rotation.none.swapsDimensions == false)
        #expect(Rotation.clockwise90.swapsDimensions == true)
        #expect(Rotation.rotate180.swapsDimensions == false)
        #expect(Rotation.clockwise270.swapsDimensions == true)
    }

    // MARK: Identity

    @Test("The default transform is the identity")
    func identityIsDefault() {
        #expect(FrameTransform() == FrameTransform.identity)
        #expect(FrameTransform.identity.isIdentity)
    }

    @Test("Any set component makes it non-identity")
    func nonIdentity() {
        #expect(FrameTransform(mirroredHorizontally: true).isIdentity == false)
        #expect(FrameTransform(flippedVertically: true).isIdentity == false)
        #expect(FrameTransform(rotation: .clockwise90).isIdentity == false)
    }

    @Test("Identity maps every output pixel to the same source pixel")
    func identityMapping() {
        let t = FrameTransform.identity
        #expect(t.outputSize(forInputWidth: 640, height: 480) == Size(width: 640, height: 480))
        #expect(t.sourcePixel(forOutputX: 0, outputY: 0, inputWidth: 640, inputHeight: 480) == Point(x: 0, y: 0))
        #expect(t.sourcePixel(forOutputX: 639, outputY: 479, inputWidth: 640, inputHeight: 480) == Point(x: 639, y: 479))
        #expect(t.sourcePixel(forOutputX: 100, outputY: 50, inputWidth: 640, inputHeight: 480) == Point(x: 100, y: 50))
    }

    // MARK: Output size

    @Test("Rotation by a quarter turn swaps output dimensions; 0/180 keep them")
    func outputSizeByRotation() {
        #expect(FrameTransform(rotation: .none).outputSize(forInputWidth: 1280, height: 720) == Size(width: 1280, height: 720))
        #expect(FrameTransform(rotation: .rotate180).outputSize(forInputWidth: 1280, height: 720) == Size(width: 1280, height: 720))
        #expect(FrameTransform(rotation: .clockwise90).outputSize(forInputWidth: 1280, height: 720) == Size(width: 720, height: 1280))
        #expect(FrameTransform(rotation: .clockwise270).outputSize(forInputWidth: 1280, height: 720) == Size(width: 720, height: 1280))
    }

    @Test("Mirror and flip never change output dimensions")
    func outputSizeUnaffectedByReflection() {
        let t = FrameTransform(rotation: .none, mirroredHorizontally: true, flippedVertically: true)
        #expect(t.outputSize(forInputWidth: 640, height: 480) == Size(width: 640, height: 480))
    }

    // MARK: Reflection mapping

    @Test("Horizontal mirror flips the x coordinate only")
    func mirrorMapping() {
        let t = FrameTransform(mirroredHorizontally: true)
        #expect(t.sourcePixel(forOutputX: 0, outputY: 3, inputWidth: 4, inputHeight: 2) == Point(x: 3, y: 3))
        #expect(t.sourcePixel(forOutputX: 3, outputY: 1, inputWidth: 4, inputHeight: 2) == Point(x: 0, y: 1))
    }

    @Test("Vertical flip flips the y coordinate only")
    func flipMapping() {
        let t = FrameTransform(flippedVertically: true)
        #expect(t.sourcePixel(forOutputX: 2, outputY: 0, inputWidth: 4, inputHeight: 2) == Point(x: 2, y: 1))
        #expect(t.sourcePixel(forOutputX: 2, outputY: 1, inputWidth: 4, inputHeight: 2) == Point(x: 2, y: 0))
    }

    // MARK: Rotation mapping (input 4x2)

    @Test("90° clockwise sends source top-left to output top-right")
    func rotate90Mapping() {
        let t = FrameTransform(rotation: .clockwise90)
        // input 4x2 -> output 2x4
        #expect(t.outputSize(forInputWidth: 4, height: 2) == Size(width: 2, height: 4))
        // source (0,0) -> output top-right (1,0)
        #expect(t.sourcePixel(forOutputX: 1, outputY: 0, inputWidth: 4, inputHeight: 2) == Point(x: 0, y: 0))
        // source (3,0) top-right -> output bottom-right (1,3)
        #expect(t.sourcePixel(forOutputX: 1, outputY: 3, inputWidth: 4, inputHeight: 2) == Point(x: 3, y: 0))
    }

    @Test("180° maps corners to the opposite corners")
    func rotate180Mapping() {
        let t = FrameTransform(rotation: .rotate180)
        #expect(t.sourcePixel(forOutputX: 0, outputY: 0, inputWidth: 4, inputHeight: 2) == Point(x: 3, y: 1))
        #expect(t.sourcePixel(forOutputX: 3, outputY: 1, inputWidth: 4, inputHeight: 2) == Point(x: 0, y: 0))
    }

    @Test("270° clockwise sends source top-left to output bottom-left")
    func rotate270Mapping() {
        let t = FrameTransform(rotation: .clockwise270)
        #expect(t.outputSize(forInputWidth: 4, height: 2) == Size(width: 2, height: 4))
        // source (0,0) -> output bottom-left (0,3)
        #expect(t.sourcePixel(forOutputX: 0, outputY: 3, inputWidth: 4, inputHeight: 2) == Point(x: 0, y: 0))
    }

    // MARK: Composition order (rotate -> mirror -> flip)

    @Test("Mirror composes on top of rotation in the fixed order")
    func rotateThenMirror() {
        let t = FrameTransform(rotation: .clockwise90, mirroredHorizontally: true)
        // Without mirror, output (1,0) -> source (0,0). Mirror flips output x in
        // the rotated frame (width 2), so output (0,0) now -> source (0,0).
        #expect(t.sourcePixel(forOutputX: 0, outputY: 0, inputWidth: 4, inputHeight: 2) == Point(x: 0, y: 0))
    }

    // MARK: Axis-reflection reduction (size-preserving subset, extension apply layer)

    @Test("Quarter turns have no axis-reflection reduction (handled with #7)")
    func quarterTurnsHaveNoReflection() {
        #expect(FrameTransform(rotation: .clockwise90).axisReflections == nil)
        #expect(FrameTransform(rotation: .clockwise270, mirroredHorizontally: true).axisReflections == nil)
    }

    @Test("Size-preserving transforms reduce to two axis reflections")
    func reflectionReduction() {
        #expect(FrameTransform.identity.axisReflections! == (false, false))
        #expect(FrameTransform(mirroredHorizontally: true).axisReflections! == (true, false))
        #expect(FrameTransform(flippedVertically: true).axisReflections! == (false, true))
        // 180° == reflect on both axes.
        #expect(FrameTransform(rotation: .rotate180).axisReflections! == (true, true))
        // 180° + horizontal mirror cancels the horizontal reflection.
        #expect(FrameTransform(rotation: .rotate180, mirroredHorizontally: true).axisReflections! == (false, true))
    }

    @Test("The reflection reduction reproduces the exact source mapping")
    func reflectionMatchesMapping() {
        let iw = 6, ih = 4
        for rotation in [Rotation.none, .rotate180] {
            for mirror in [false, true] {
                for flip in [false, true] {
                    let t = FrameTransform(rotation: rotation, mirroredHorizontally: mirror, flippedVertically: flip)
                    let (h, v) = t.axisReflections!
                    for oy in 0..<ih {
                        for ox in 0..<iw {
                            let expected = Point(x: h ? iw - 1 - ox : ox, y: v ? ih - 1 - oy : oy)
                            #expect(t.sourcePixel(forOutputX: ox, outputY: oy, inputWidth: iw, inputHeight: ih) == expected)
                        }
                    }
                }
            }
        }
    }

    // MARK: Packed wire encoding (custom CMIO property payload)

    @Test("The identity packs to zero")
    func identityPacksToZero() {
        #expect(FrameTransform.identity.packed == 0)
    }

    @Test("Packing round-trips for every combination")
    func packRoundTrip() {
        for rotation in Rotation.allCases {
            for mirror in [false, true] {
                for flip in [false, true] {
                    let t = FrameTransform(rotation: rotation, mirroredHorizontally: mirror, flippedVertically: flip)
                    #expect(FrameTransform(packed: t.packed) == t)
                }
            }
        }
    }

    @Test("Distinct transforms never collide in the packed value")
    func packIsInjective() {
        var seen = Set<Int32>()
        for rotation in Rotation.allCases {
            for mirror in [false, true] {
                for flip in [false, true] {
                    seen.insert(FrameTransform(rotation: rotation, mirroredHorizontally: mirror, flippedVertically: flip).packed)
                }
            }
        }
        #expect(seen.count == 16)
    }

    @Test("Out-of-range packed bits decode to the identity rather than crashing")
    func packDefensiveDecode() {
        #expect(FrameTransform(packed: -1) == FrameTransform.identity)
        #expect(FrameTransform(packed: 0x7FFF_FFFF) == FrameTransform.identity)
    }

    @Test("Every output pixel maps back inside the source bounds for all 8 orientations")
    func mappingStaysInBounds() {
        let iw = 6, ih = 4
        for rotation in Rotation.allCases {
            for mirror in [false, true] {
                for flip in [false, true] {
                    let t = FrameTransform(rotation: rotation, mirroredHorizontally: mirror, flippedVertically: flip)
                    let size = t.outputSize(forInputWidth: iw, height: ih)
                    var seen = Set<Point>()
                    for oy in 0..<size.height {
                        for ox in 0..<size.width {
                            let p = t.sourcePixel(forOutputX: ox, outputY: oy, inputWidth: iw, inputHeight: ih)
                            #expect(p.x >= 0 && p.x < iw)
                            #expect(p.y >= 0 && p.y < ih)
                            seen.insert(p)
                        }
                    }
                    // A rigid transform is a bijection: every source pixel used once.
                    #expect(seen.count == iw * ih)
                }
            }
        }
    }
}
