/// The set of formats the device advertises, with a well-defined default.
///
/// For issue #1 the catalog only needs a sane default that is available even
/// when no producer is connected. The advertised matrix is expanded by #3
/// (format negotiation).
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

    /// The baseline catalog: 720p BGRA @ 30fps, available without a producer.
    public static let standard = FormatCatalog(formats: [
        CameraFormat(width: 1280, height: 720, pixelFormat: .bgra, frameRate: 30)
    ])
}
