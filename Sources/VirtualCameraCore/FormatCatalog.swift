/// The set of formats the device advertises, with a well-defined default and
/// bounds-checked lookup used by the stream source (issue #3).
///
/// The consumer app selects a format by index (`activeFormatIndex`); invalid
/// selections clamp to the default rather than crash or blank the stream.
/// Producer-side format negotiation/conversion arrives with the producer
/// transport (#4).
public struct FormatCatalog: Sendable, Equatable {
    public let formats: [CameraFormat]

    /// The format used when nothing else is negotiated. Guaranteed non-nil
    /// because `formats` is never empty (enforced at construction).
    public var defaultFormat: CameraFormat {
        formats[0]
    }

    /// - Precondition: `formats` must contain at least one entry; the first is
    ///   treated as the default.
    public init(formats: [CameraFormat]) {
        precondition(!formats.isEmpty, "FormatCatalog requires at least one format")
        self.formats = formats
    }

    /// The format at `index`, or `nil` if out of range.
    public func format(at index: Int) -> CameraFormat? {
        formats.indices.contains(index) ? formats[index] : nil
    }

    /// The index of the first matching format, or `nil` if not advertised.
    public func firstIndex(of format: CameraFormat) -> Int? {
        formats.firstIndex(of: format)
    }

    /// A valid index for the requested selection: `requested` if in range,
    /// otherwise the default index (0).
    public func resolvedIndex(for requested: Int) -> Int {
        formats.indices.contains(requested) ? requested : 0
    }

    /// The baseline catalog: 720p and 1080p, each in BGRA and NV12, at 30fps.
    /// Index 0 (720p BGRA) is the default, available without a producer.
    public static let standard = FormatCatalog(formats: [
        CameraFormat(width: 1280, height: 720, pixelFormat: .bgra, frameRate: 30),
        CameraFormat(width: 1280, height: 720, pixelFormat: .nv12, frameRate: 30),
        CameraFormat(width: 1920, height: 1080, pixelFormat: .bgra, frameRate: 30),
        CameraFormat(width: 1920, height: 1080, pixelFormat: .nv12, frameRate: 30),
    ])
}
