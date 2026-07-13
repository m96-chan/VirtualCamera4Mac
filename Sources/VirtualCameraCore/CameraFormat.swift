/// A pixel/geometry/timing description the virtual camera can advertise.
///
/// This is a pure value type with no CoreMediaIO dependency so it can be unit
/// tested in isolation and reused by the extension layer.
public struct CameraFormat: Sendable, Equatable {
    /// Pixel layout of a frame.
    public enum PixelFormat: Sendable, Equatable {
        case bgra
        case nv12

        /// Short uppercase name used in diagnostics/labels.
        public var name: String {
            switch self {
            case .bgra: return "BGRA"
            case .nv12: return "NV12"
            }
        }
    }

    public let width: Int
    public let height: Int
    public let pixelFormat: PixelFormat
    /// Frames per second.
    public let frameRate: Int

    public init(width: Int, height: Int, pixelFormat: PixelFormat, frameRate: Int) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.frameRate = frameRate
    }

    /// Human-readable description, e.g. `1280x720 BGRA 30fps`.
    public var label: String {
        "\(width)x\(height) \(pixelFormat.name) \(frameRate)fps"
    }
}
