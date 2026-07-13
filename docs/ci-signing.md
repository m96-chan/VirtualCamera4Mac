# CI signing & release setup

The [`Release`](../.github/workflows/release.yml) workflow builds a signed,
notarized app on version tags (`v*`). It uses **Manual** code signing with team
`9U26G7YWJ9` (Developer ID), fed entirely from repository secrets. The
[`CI`](../.github/workflows/ci.yml) workflow needs **no** secrets.

Signing runs only on tags / manual dispatch, never on pull requests, so secrets
are never exposed to untrusted PRs.

Apple signing assets are provisioned with **fastlane** (`fastlane/Fastfile`),
authenticated by an **App Store Connect API key** via `Spaceship::ConnectAPI`.
(The `produce` tool is intentionally not used — it does not support API-key auth.)

## 1. Install fastlane

The macOS system Ruby (2.6) cannot build fastlane's native gems, so use the
self-contained Homebrew build:

```bash
brew install fastlane
```

## 2. Create an App Store Connect API key

App Store Connect → **Users and Access → Integrations → App Store Connect API** →
generate a key with **Developer** access. Note the **Key ID** and **Issuer ID**,
and download `AuthKey_XXXX.p8` (downloadable once).

## 3. Provision Apple assets

```bash
ASC_KEY_ID=XXXXXXXXXX \
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
ASC_KEY_P8_BASE64="$(base64 -i AuthKey_XXXXXXXXXX.p8)" \
  fastlane mac setup_signing
```

The `setup_signing` lane:
- creates the App IDs `io.github.m96chan.VirtualCamera4Mac` and `…​.Extension`
  (macOS) if missing;
- enables the **App Groups** and **System Extension** capabilities (the app id
  gets both; the extension gets App Groups);
- creates Developer ID provisioning profiles named **`VirtualCamera4Mac Developer
  ID`** and **`VirtualCamera4Mac Extension Developer ID`** into `build/profiles/`.

The Developer ID profiles carry a wildcard app group (`9U26G7YWJ9.*`), so the
shared group `9U26G7YWJ9.io.github.m96chan.VirtualCamera4Mac` needs no separate
registration.

## 4. Export the Developer ID certificate

fastlane can't export an existing private key, so do this once by hand:
Keychain Access → **Developer ID Application: Yusuke Harada (9U26G7YWJ9)** →
right-click → **Export** → `.p12` (set a password).

## 5. Repository secrets

Under **Settings → Secrets and variables → Actions**:

| Secret | Value | Status |
|---|---|---|
| `APPLE_TEAM_ID` | `9U26G7YWJ9` | set |
| `ASC_KEY_ID` | App Store Connect API **Key ID** | set |
| `ASC_ISSUER_ID` | App Store Connect API **Issuer ID** | set |
| `ASC_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8` | set |
| `PROVISIONING_PROFILE_APP_BASE64` | `base64 -i build/profiles/Direct_io.github.m96chan.VirtualCamera4Mac.provisionprofile` | set |
| `PROVISIONING_PROFILE_EXT_BASE64` | `base64 -i build/profiles/Direct_io.github.m96chan.VirtualCamera4Mac.Extension.provisionprofile` | set |
| `PROVISIONING_PROFILE_NAME_APP` | `VirtualCamera4Mac Developer ID` | set |
| `PROVISIONING_PROFILE_NAME_EXT` | `VirtualCamera4Mac Extension Developer ID` | set |
| `KEYCHAIN_PASSWORD` | any random string (temp keychain) | set |
| `BUILD_CERTIFICATE_BASE64` | `base64 -i DeveloperID.p12` | **TODO** |
| `P12_PASSWORD` | the `.p12` export password | **TODO** |

The `ASC_*` secrets are reused by the release workflow to notarize
(`notarytool --key`), so no Apple ID / app-specific password is needed.

## 6. Cut a release

```bash
git tag v0.0.1
git push origin v0.0.1
```

The workflow archives, exports (Developer ID, manual), notarizes with the API
key (`notarytool --wait`), staples, and attaches `VirtualCamera4Mac.zip` to a
GitHub Release. It can also be run manually from the Actions tab.

## Notes

- The provisioning-profile names must match the `PROVISIONING_PROFILE_NAME_*`
  secrets exactly (used in `ExportOptions.plist`).
- The release path has not yet been run end to end — expect to iterate on the
  first tag, especially `archive`/`-exportArchive` for the System Extension.
- Distribution outside the App Store requires Developer ID signing **and**
  notarization for the System Extension to load on other machines.
