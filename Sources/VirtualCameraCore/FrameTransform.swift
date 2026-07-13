/// Integer pixel coordinate. Pure value type shared by the transform geometry
/// and its tests so the extension's vImage pipeline has an unambiguous spec.
public struct Point: Sendable, Equatable, Hashable {
    public let x: Int
    public let y: Int
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// Integer pixel size.
public struct Size: Sendable, Equatable, Hashable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// A clockwise rotation applied to the output frame (issue #6). Raw values are
/// degrees so they read naturally in UI and diagnostics.
public enum Rotation: Int, Sendable, Equatable, CaseIterable {
    case none = 0
    case clockwise90 = 90
    case rotate180 = 180
    case clockwise270 = 270

    /// Whether this rotation swaps the frame's width and height.
    public var swapsDimensions: Bool {
        self == .clockwise90 || self == .clockwise270
    }
}

/// A composable geometric transform for the output stream: a clockwise
/// rotation, an optional horizontal mirror, and an optional vertical flip.
///
/// This is a pure value type with no CoreMediaIO dependency so it can be unit
/// tested in isolation; the extension applies the same transform to frames via
/// vImage. The composition order is fixed and **rotate → mirror → flip**
/// (source to output): the frame is rotated clockwise first, then mirrored
/// horizontally, then flipped vertically.
public struct FrameTransform: Sendable, Equatable {
    public var rotation: Rotation
    public var mirroredHorizontally: Bool
    public var flippedVertically: Bool

    public init(rotation: Rotation = .none,
                mirroredHorizontally: Bool = false,
                flippedVertically: Bool = false) {
        self.rotation = rotation
        self.mirroredHorizontally = mirroredHorizontally
        self.flippedVertically = flippedVertically
    }

    /// The no-op transform.
    public static let identity = FrameTransform()

    /// Whether this transform leaves frames untouched (enables a zero-copy fast
    /// path in the extension).
    public var isIdentity: Bool {
        rotation == .none && !mirroredHorizontally && !flippedVertically
    }

    /// The output dimensions produced from an input of the given size. Only the
    /// quarter-turn rotations swap width and height; mirror and flip preserve
    /// the size.
    public func outputSize(forInputWidth width: Int, height: Int) -> Size {
        rotation.swapsDimensions ? Size(width: height, height: width)
                                 : Size(width: width, height: height)
    }

    /// For size-preserving transforms (no quarter turn), the equivalent pair of
    /// axis reflections to apply — the extension applies these directly with
    /// vImage, keeping its apply layer trivial. `nil` when a 90/270 rotation is
    /// present, since that changes dimensions and is fitted with aspect-ratio
    /// handling (#7). A 180° rotation is a reflection on both axes, so it folds
    /// into this pair by parity.
    public var axisReflections: (horizontal: Bool, vertical: Bool)? {
        guard !rotation.swapsDimensions else { return nil }
        let half = (rotation == .rotate180)
        return (horizontal: mirroredHorizontally != half, vertical: flippedVertically != half)
    }

    // MARK: Wire encoding

    /// Bit position of the mirror flag in `packed`.
    private static let mirrorBit: Int32 = 1 << 2
    /// Bit position of the vertical-flip flag in `packed`.
    private static let flipBit: Int32 = 1 << 3
    /// Mask of all bits `packed` may legitimately use (rotation + two flags).
    private static let mask: Int32 = 0b1111

    /// A compact, stable `Int32` encoding used as the custom CMIO property
    /// payload the app sends to the extension: bits 0–1 hold the rotation
    /// (0/1/2/3), bit 2 the horizontal mirror, bit 3 the vertical flip. The
    /// identity encodes to `0`.
    public var packed: Int32 {
        let rotationCode: Int32
        switch rotation {
        case .none: rotationCode = 0
        case .clockwise90: rotationCode = 1
        case .rotate180: rotationCode = 2
        case .clockwise270: rotationCode = 3
        }
        return rotationCode
            | (mirroredHorizontally ? Self.mirrorBit : 0)
            | (flippedVertically ? Self.flipBit : 0)
    }

    /// Decodes a `packed` value. Any value carrying bits outside the defined
    /// mask is treated as the identity, so a stale or corrupt property payload
    /// degrades to "no transform" rather than an undefined state.
    public init(packed: Int32) {
        guard packed & ~Self.mask == 0 else {
            self = .identity
            return
        }
        let rotation: Rotation
        switch packed & 0b11 {
        case 1: rotation = .clockwise90
        case 2: rotation = .rotate180
        case 3: rotation = .clockwise270
        default: rotation = .none
        }
        self.init(rotation: rotation,
                  mirroredHorizontally: packed & Self.mirrorBit != 0,
                  flippedVertically: packed & Self.flipBit != 0)
    }

    /// The source pixel that feeds a given output pixel — the inverse of the
    /// composed transform. This fully specifies the geometry the extension's
    /// vImage pipeline must reproduce, and lets tests assert corner placement
    /// without a GPU.
    public func sourcePixel(forOutputX outputX: Int, outputY: Int,
                            inputWidth: Int, inputHeight: Int) -> Point {
        let out = outputSize(forInputWidth: inputWidth, height: inputHeight)

        // Undo vertical flip, then horizontal mirror, back to the rotated frame.
        let flippedY = flippedVertically ? out.height - 1 - outputY : outputY
        let rotatedX = mirroredHorizontally ? out.width - 1 - outputX : outputX
        let rotatedY = flippedY

        // Undo the clockwise rotation back to source coordinates.
        switch rotation {
        case .none:
            return Point(x: rotatedX, y: rotatedY)
        case .clockwise90:
            return Point(x: rotatedY, y: inputHeight - 1 - rotatedX)
        case .rotate180:
            return Point(x: inputWidth - 1 - rotatedX, y: inputHeight - 1 - rotatedY)
        case .clockwise270:
            return Point(x: inputWidth - 1 - rotatedY, y: rotatedX)
        }
    }
}
