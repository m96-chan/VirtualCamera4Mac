/// A pixel/geometry/timing description the virtual camera can advertise.
///
/// This is a pure value type with no CoreMediaIO dependency so it can be unit
/// tested in isolation and reused by the extension layer.
public struct CameraFormat: Sendable, Equatable {
    /// Pixel layout of a frame.
    public enum PixelFormat: Sendable, Equatable {
        case bgra
        case nv12
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
}
