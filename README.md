# VirtualCamera4Mac

[![CI](https://github.com/m96-chan/VirtualCamera4Mac/actions/workflows/ci.yml/badge.svg)](https://github.com/m96-chan/VirtualCamera4Mac/actions/workflows/ci.yml)

A native virtual camera for macOS. VirtualCamera4Mac registers a system-wide
camera device that any application — Zoom, Google Meet, OBS, QuickTime, Discord,
Safari/Chrome WebRTC — can select as if it were a physical webcam. Frames are
fed into the device from an external producer, with first-class support for
**AvataCam** as the source.

> **AvataCam** is a private project, currently pending approval/licensing, so it
> is not linked here yet.

> Status: **early development / design phase.** APIs, IPC protocol, and bundle
> identifiers are not yet stable.

---

## Why

macOS deprecated the old CoreMediaIO **DAL plug-in** mechanism in macoS 12.3.
The supported, sandbox-friendly, notarizable path going forward is a **CMIO
Camera Extension** delivered as a **System Extension**. VirtualCamera4Mac is
built on that modern foundation so it keeps working on current and future macOS
releases without private APIs or SIP workarounds.

## Goals

- **Modern & supported** — CMIO Camera Extension (System Extension), no DAL,
  no private API.
- **Zero-copy where possible** — move frames with `IOSurface` so avatar
  rendering stays real-time.
- **App-agnostic** — appears as a standard camera to every app that uses
  AVFoundation / CoreMediaIO.
- **AvataCam-native** — a documented producer protocol so AvataCam can push
  rendered avatar frames with minimal glue.
- **Notarizable** — signed, sandboxed, distributable outside private provisioning.

## Non-goals (for now)

- Audio virtual devices.
- Windows / Linux support (this project is macOS-only by design).
- Bundled rendering/effects — VirtualCamera4Mac is a *sink/transport*, the
  avatar rendering lives in the producer (AvataCam).

---

## Architecture

```
┌──────────────────┐        frames         ┌────────────────────────────┐
│                  │   (IOSurface + meta)  │  VirtualCamera4Mac          │
│    AvataCam      │ ────────────────────► │                            │
│  (frame producer)│      IPC channel      │  ┌──────────────────────┐  │
│                  │ ◄──────────────────── │  │  Container App        │  │
└──────────────────┘   negotiation/ack     │  │  - installs ext       │  │
                                           │  │  - IPC broker         │  │
                                           │  └──────────┬───────────┘  │
                                           │             │ XPC          │
                                           │  ┌──────────▼───────────┐  │
                                           │  │  Camera Extension     │  │
                                           │  │  (CMIO provider)      │──┼──► seen by
                                           │  │  - virtual device     │  │    Zoom / Meet /
                                           │  │  - stream + clock      │  │    OBS / browsers…
                                           │  └──────────────────────┘  │
                                           └────────────────────────────┘
```

**Components**

1. **Camera Extension** — a `CMIOExtensionProvider` that publishes one virtual
   camera device + stream, advertises supported formats, and delivers sample
   buffers to the host. Runs out-of-process, managed by macOS.
2. **Container App** — user-facing app that requests activation of the System
   Extension, shows install/permission state, and brokers the connection
   between producers and the extension.
3. **Producer SDK** — a small library (and documented wire protocol) that a
   producer such as AvataCam links against to push frames.

## AvataCam integration

The two repos talk over a versioned IPC contract so they can ship
independently.

- **Transport:** `IOSurface`-backed frames handed across processes via **XPC**
  (surface passed by Mach send-right; no per-frame pixel copy). A local Unix
  domain socket is the fallback for producers that cannot adopt XPC.
- **Frame format:** BGRA / NV12 to start; format is negotiated at connect time.
- **Metadata per frame:** presentation timestamp, width/height, pixel format,
  rotation, and mirror flag.
- **Discovery:** the container app exposes a well-known Mach service name;
  AvataCam connects, negotiates a format, then streams.

A minimal producer loop looks like:

```swift
let camera = try VirtualCamera.connect()            // find the running device
let format = try camera.negotiate(.bgra, 1280, 720, fps: 30)
while running {
    let surface = renderer.nextFrame()              // IOSurface from AvataCam
    camera.send(surface, pts: clock.now)
}
```

> The exact SDK surface is being designed. See [`docs/ipc-protocol.md`](docs/ipc-protocol.md)
> (planned) for the wire format once it stabilizes.

---

## Language choice: Swift (with an optional Rust core)

**Swift is the primary language.** The macOS Camera Extension API
(`CMIOExtension*`) is only exposed through the Apple SDKs, and System Extension
packaging, entitlements, and notarization are all first-class in Swift/Xcode.
There is no supported way to author the extension itself in another language,
and for I/O-bound frame passing (which is dominated by `IOSurface` handoff, not
CPU work) Swift is more than fast enough.

**Rust is kept in reserve for the hot path.** If profiling shows the
producer-side pipeline (color conversion, scaling, encoding) needs it, that
work can live in a Rust core exposed over a C ABI and called from Swift via FFI.
The virtual-camera transport stays zero-copy regardless of language, so Rust is
an optimization for *processing*, not a rewrite of the device layer.

Decision, in short:

| Layer | Language | Reason |
|---|---|---|
| Camera Extension / device | **Swift** | Only supported path; Apple SDK-bound |
| Container app | **Swift** | Native UI, System Extension activation |
| Producer SDK (Swift API) | **Swift** | Ergonomic for AvataCam |
| Optional pixel pipeline | **Rust** (via FFI) | If CPU-bound conversion becomes a bottleneck |

---

## Requirements

- macOS 13 (Ventura) or later — deployment target; recommended for the mature
  Camera Extension API.
- Xcode 16+ (developed against Xcode 26).
- [XcodeGen](https://github.com/yonatankoren/XcodeGen) — the Xcode project is
  generated from `project.yml` (the `.xcodeproj` is not committed):
  `brew install xcodegen`.
- An Apple Developer account for the System Extension and Camera entitlements
  (required only to build/run the signed extension; the pure core and its unit
  tests build without signing).

## Project layout

- `project.yml` — XcodeGen spec (source of truth for the Xcode project).
- `Sources/VirtualCameraCore/` — pure-Swift, dependency-free core (device
  lifecycle, stream state machine, format catalog). Unit-tested in isolation.
- `Tests/VirtualCameraCoreTests/` — [swift-testing](https://github.com/swiftlang/swift-testing) unit tests.
- `Sources/Extension/` — the CMIO Camera Extension (`CMIOExtensionProviderSource`),
  a System Extension that publishes the virtual camera device.
- `Sources/App/` — the container app that installs/activates the extension.

## Building & testing

```bash
xcodegen generate        # regenerate VirtualCamera4Mac.xcodeproj from project.yml

# Run the core unit tests (no signing / Team ID required):
xcodebuild test \
  -project VirtualCamera4Mac.xcodeproj \
  -scheme VirtualCameraCore \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES

# Compile-verify the app + Camera Extension without signing:
xcodebuild build \
  -project VirtualCamera4Mac.xcodeproj \
  -scheme VirtualCamera4Mac \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

### Running the Camera Extension locally

The extension is a **System Extension** and must be signed (Manual signing, team
`9U26G7YWJ9`) to install. For local development without notarization/moving to
`/Applications`, enable System Extension developer mode:

```bash
systemextensionsctl developer on
```

Then run the **VirtualCamera4Mac** app and click **Install / Activate**; approve
it in **System Settings → General → Login Items & Extensions**. The device then
appears to any app using AVFoundation / CoreMediaIO (verify with
`system_profiler SPCameraDataType` or QuickTime → New Movie Recording).

## Continuous integration

- **CI** (`.github/workflows/ci.yml`) — on every PR and `main` push: runs the
  core unit tests and an unsigned compile check of the app + extension. No
  secrets required.
- **Release** (`.github/workflows/release.yml`) — on `v*` tags: signed
  (Developer ID, Manual) build, notarization, stapling, and a GitHub Release.
  Setup and required secrets are documented in
  [`docs/ci-signing.md`](docs/ci-signing.md).

## Roadmap

- [x] Camera Extension scaffold publishing a static test pattern.
- [x] No-signal standby image (horizontal test bands) shown until a producer connects.
- [x] Container app with System Extension install/activation flow.
- [x] Format negotiation — advertises **720p / 1080p × BGRA / NV12 @ 30fps**; the
  consumer app selects a format (invalid selections clamp to the default).
- [x] Notarized Developer ID release (`v0.0.1`).
- [ ] XPC + `IOSurface` frame transport.
- [ ] Producer SDK and versioned IPC protocol doc.
- [ ] AvataCam reference integration.
- [ ] Signed installer — notarized `.dmg` + Homebrew tap.

## Distribution & signing

Builds are provided under my **personal signing identity** — this is a solo,
hobby-scale project, not a company release. Please treat it as such: no SLA, no
guarantees, but built with care.

## Support / Buy Me a Coffee

If VirtualCamera4Mac is useful to you, buying me a coffee is the nicest way to
say thanks. It's entirely optional and keeps the late-night hacking going. ☕️

**→ https://buymeacoffee.com/m96chan**

## Contributing

Issues and PRs are welcome. Because this ships a System Extension, changes that
touch entitlements, signing, or the IPC protocol should include a short note on
compatibility impact.

## License

Licensed under the **Apache License, Version 2.0**. See [`LICENSE`](LICENSE).

Copyright 2026 m96-chan.
