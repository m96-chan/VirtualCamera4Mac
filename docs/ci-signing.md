# CI signing & release setup

The [`Release`](../.github/workflows/release.yml) workflow builds a signed,
notarized app on version tags (`v*`). It uses **Manual** code signing with team
`9U26G7YWJ9` (Developer ID), fed entirely from repository secrets. The
[`CI`](../.github/workflows/ci.yml) workflow needs **no** secrets — it only runs
tests and an unsigned compile check.

Signing runs only on tags / manual dispatch, never on pull requests, so secrets
are never exposed to untrusted PRs.

Apple signing assets are provisioned with **fastlane** (see `fastlane/Fastfile`),
authenticated by an **App Store Connect API key**.

## 1. Create an App Store Connect API key

App Store Connect → **Users and Access → Integrations → App Store Connect API** →
generate a key with **Developer** access (or higher). Note the **Key ID** and
**Issuer ID**, and download the `AuthKey_XXXX.p8` once (it cannot be re-downloaded).

## 2. Provision Apple assets with fastlane

Installs the App IDs, App Group, and Developer ID provisioning profiles:

```bash
bundle install
ASC_KEY_ID=XXXXXXXXXX \
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
ASC_KEY_P8_BASE64="$(base64 -i AuthKey_XXXXXXXXXX.p8)" \
  bundle exec fastlane mac setup_signing
```

This creates/refreshes:
- App IDs `io.github.m96chan.VirtualCamera4Mac` and `…​.Extension` (App Groups on both);
- the App Group `9U26G7YWJ9.io.github.m96chan.VirtualCamera4Mac`, associated with both;
- Developer ID provisioning profiles for both targets, written to `build/profiles/`.

> **System Extension capability:** the lane tries to enable it via the API. If
> Apple rejects that write, enable it manually: developer.apple.com → Identifiers
> → `io.github.m96chan.VirtualCamera4Mac` → **System Extension** → Save, then
> re-run the lane so the profile picks it up.

## 3. Export the Developer ID certificate

fastlane can't export an existing private key, so do this once by hand:
Keychain Access → **Developer ID Application: Yusuke Harada (9U26G7YWJ9)** →
right-click → **Export** → `.p12` (set a password).

## 4. Repository secrets

Add these under **Settings → Secrets and variables → Actions** (`APPLE_TEAM_ID`
is already set):

| Secret | Value |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | `base64 -i DeveloperID.p12 \| pbcopy` |
| `P12_PASSWORD` | password you set when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | any random string (temp keychain password) |
| `PROVISIONING_PROFILE_APP_BASE64` | `base64 -i build/profiles/<app>.provisionprofile \| pbcopy` |
| `PROVISIONING_PROFILE_EXT_BASE64` | `base64 -i build/profiles/<ext>.provisionprofile \| pbcopy` |
| `PROVISIONING_PROFILE_NAME_APP` | the app profile's exact name |
| `PROVISIONING_PROFILE_NAME_EXT` | the extension profile's exact name |
| `APPLE_TEAM_ID` | `9U26G7YWJ9` (already set) |
| `ASC_KEY_ID` | App Store Connect API **Key ID** |
| `ASC_ISSUER_ID` | App Store Connect API **Issuer ID** |
| `ASC_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` |

The `ASC_*` secrets are reused by the release workflow to notarize
(`notarytool --key`), so no Apple ID / app-specific password is needed.

`base64` on macOS: `base64 -i <file>` prints the encoded string (pipe to
`pbcopy` to copy it).

## 5. Cut a release

```bash
git tag v0.0.1
git push origin v0.0.1
```

The workflow archives, exports with Developer ID, notarizes with the API key
(`notarytool --wait`), staples, and attaches `VirtualCamera4Mac.zip` to a GitHub
Release. You can also trigger it manually from the Actions tab (**Run workflow**).

## Notes / not yet verified

- The release workflow has **not** been run end-to-end yet — it is gated on the
  steps above. Expect to iterate on the first tagged build, especially the
  `archive`/`-exportArchive` provisioning-profile matching for the System
  Extension (the most common first-run failure point).
- Provisioning-profile names must match the `PROVISIONING_PROFILE_NAME_*` secrets
  exactly (used in `ExportOptions.plist`).
- Distribution outside the App Store requires Developer ID signing **and**
  notarization for the System Extension to load on other machines.
