import Foundation
import CoreVideo
import VirtualCameraCore
import VirtualCameraProducer

// A tiny sample producer that proves the end-to-end sink transport (#11):
// it feeds VirtualCamera4Mac a full-frame colour that cycles over time, so the
// camera shows an obviously *live* (moving) image instead of the standby bands.

let format = FormatCatalog.standard.defaultFormat // 1280x720 BGRA 30fps

// Connect, retrying briefly — the device only appears once the extension is
// activated.
func connect() -> VirtualCameraSink {
    for attempt in 1...40 {
        if let sink = try? VirtualCameraSink(frameRate: Int32(format.frameRate)) {
            return sink
        }
        FileHandle.standardError.write(Data("waiting for VirtualCamera4Mac device (\(attempt))…\n".utf8))
        Thread.sleep(forTimeInterval: 0.5)
    }
    FileHandle.standardError.write(Data("device not found — activate the extension in the app first.\n".utf8))
    exit(1)
}
let sink = connect()

var pool: CVPixelBufferPool?
let poolAttributes: NSDictionary = [
    kCVPixelBufferWidthKey: format.width,
    kCVPixelBufferHeightKey: format.height,
    kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
    kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary,
]
CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, poolAttributes, &pool)

/// Fill the buffer with a solid BGRA colour that cycles with `frame`.
func fill(_ pixelBuffer: CVPixelBuffer, frame: Int) {
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
    let rows = CVPixelBufferGetHeight(pixelBuffer)
    let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)

    let t = Double(frame) * 0.06
    let r = UInt32((sin(t) * 0.5 + 0.5) * 255)
    let g = UInt32((sin(t + 2.094) * 0.5 + 0.5) * 255)
    let b = UInt32((sin(t + 4.188) * 0.5 + 0.5) * 255)
    var colour: UInt32 = (0xFF << 24) | (r << 16) | (g << 8) | b // 0xAARRGGBB
    memset_pattern4(base, &colour, rowBytes * rows)
}

var frame = 0
let interval = 1.0 / Double(format.frameRate)
let timer = Timer(timeInterval: interval, repeats: true) { _ in
    guard let pool else { return }
    var pixelBufferOut: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBufferOut) == kCVReturnSuccess,
          let pixelBuffer = pixelBufferOut else { return }
    fill(pixelBuffer, frame: frame)
    sink.send(pixelBuffer)
    frame += 1
    if frame % Int(format.frameRate) == 0 {
        print("sent \(frame) frames")
    }
}
RunLoop.main.add(timer, forMode: .common)

print("Feeding VirtualCamera4Mac at \(format.label). Open Photo Booth and select the camera. Ctrl-C to stop.")
RunLoop.main.run()
