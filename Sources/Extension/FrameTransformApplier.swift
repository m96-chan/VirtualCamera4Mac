import Foundation
import CoreVideo
import Accelerate
import VirtualCameraCore

/// Applies a size-preserving `FrameTransform` (mirror / vertical flip / 180°)
/// to an IOSurface-backed pixel buffer using vImage, so the work stays off the
/// CPU per-pixel path (#6). Quarter-turn rotations change dimensions and are
/// handled with aspect-ratio fitting (#7); this applier declines them.
///
/// The size-preserving subset reduces to at most two axis reflections
/// (`FrameTransform.axisReflections`); this type turns that pair into a single
/// vImage op per plane (reflect on one axis, or a 180° rotate for both). The
/// geometry decision lives in the tested core, not here.
enum FrameTransformApplier {

    /// A vImage image type, parameterised by the operations for its element.
    private struct Op {
        let horizontal: (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>) -> vImage_Error
        let vertical: (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>) -> vImage_Error
        /// 180° rotation, used when both axes reflect.
        let rotate180: (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>) -> vImage_Error
    }

    private static let planar8 = Op(
        horizontal: { vImageHorizontalReflect_Planar8($0, $1, vImage_Flags(kvImageNoFlags)) },
        vertical: { vImageVerticalReflect_Planar8($0, $1, vImage_Flags(kvImageNoFlags)) },
        rotate180: { vImageRotate90_Planar8($0, $1, 2, 0, vImage_Flags(kvImageNoFlags)) })

    private static let planar16U = Op(
        horizontal: { vImageHorizontalReflect_Planar16U($0, $1, vImage_Flags(kvImageNoFlags)) },
        vertical: { vImageVerticalReflect_Planar16U($0, $1, vImage_Flags(kvImageNoFlags)) },
        rotate180: { vImageRotate90_Planar16U($0, $1, 2, 0, vImage_Flags(kvImageNoFlags)) })

    private static let argb8888 = Op(
        horizontal: { vImageHorizontalReflect_ARGB8888($0, $1, vImage_Flags(kvImageNoFlags)) },
        vertical: { vImageVerticalReflect_ARGB8888($0, $1, vImage_Flags(kvImageNoFlags)) },
        rotate180: {
            var back: Pixel_8888 = (0, 0, 0, 0)
            return vImageRotate90_ARGB8888($0, $1, 2, &back.0, vImage_Flags(kvImageNoFlags))
        })

    /// Produces a transformed copy of `source` drawn from `pool` (same format as
    /// the active source format). Returns `nil` — meaning "send the original" —
    /// when the transform is a no-op, a quarter turn, the pixel format is
    /// unsupported, or allocation fails, so a transform failure never blanks the
    /// stream.
    static func apply(_ transform: FrameTransform,
                      to source: CVPixelBuffer,
                      pool: CVPixelBufferPool) -> CVPixelBuffer? {
        guard let reflections = transform.axisReflections,
              reflections.horizontal || reflections.vertical else {
            return nil
        }

        var destOut: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destOut) == kCVReturnSuccess,
              let dest = destOut else {
            return nil
        }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(dest, [])
        defer {
            CVPixelBufferUnlockBaseAddress(dest, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }

        switch CVPixelBufferGetPixelFormatType(source) {
        case kCVPixelFormatType_32BGRA:
            guard reflectPlane(nil, source: source, dest: dest, op: argb8888, reflections: reflections) else { return nil }
            return dest
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            // Luma: one byte per sample. Chroma: interleaved CbCr, treated as one
            // 16-bit unit per sample so each Cb/Cr pair moves together.
            guard reflectPlane(0, source: source, dest: dest, op: planar8, reflections: reflections),
                  reflectPlane(1, source: source, dest: dest, op: planar16U, reflections: reflections) else { return nil }
            return dest
        default:
            return nil
        }
    }

    /// Reflects one plane (`plane == nil` for a non-planar buffer) with the op
    /// set matching its element. vImage buffer `width` is in elements, so the
    /// element-typed op moves whole pixels / CbCr pairs.
    private static func reflectPlane(_ plane: Int?,
                                     source: CVPixelBuffer,
                                     dest: CVPixelBuffer,
                                     op: Op,
                                     reflections: (horizontal: Bool, vertical: Bool)) -> Bool {
        func base(_ b: CVPixelBuffer) -> UnsafeMutableRawPointer? {
            plane.map { CVPixelBufferGetBaseAddressOfPlane(b, $0) } ?? CVPixelBufferGetBaseAddress(b)
        }
        func width(_ b: CVPixelBuffer) -> Int {
            plane.map { CVPixelBufferGetWidthOfPlane(b, $0) } ?? CVPixelBufferGetWidth(b)
        }
        func height(_ b: CVPixelBuffer) -> Int {
            plane.map { CVPixelBufferGetHeightOfPlane(b, $0) } ?? CVPixelBufferGetHeight(b)
        }
        func rowBytes(_ b: CVPixelBuffer) -> Int {
            plane.map { CVPixelBufferGetBytesPerRowOfPlane(b, $0) } ?? CVPixelBufferGetBytesPerRow(b)
        }

        guard let srcBase = base(source), let dstBase = base(dest) else { return false }

        var src = vImage_Buffer(data: srcBase, height: vImagePixelCount(height(source)),
                                width: vImagePixelCount(width(source)), rowBytes: rowBytes(source))
        var dst = vImage_Buffer(data: dstBase, height: vImagePixelCount(height(dest)),
                                width: vImagePixelCount(width(dest)), rowBytes: rowBytes(dest))

        let error: vImage_Error
        switch (reflections.horizontal, reflections.vertical) {
        case (true, false): error = op.horizontal(&src, &dst)
        case (false, true): error = op.vertical(&src, &dst)
        default:            error = op.rotate180(&src, &dst) // both axes == 180°
        }
        return error == kvImageNoError
    }
}
