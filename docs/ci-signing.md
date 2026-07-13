# CI signing & release setup

The [`Release`](../.github/workflows/release.yml) workflow builds a signed,
notarized app on version tags (`v*`). It uses **Manual** code signing with team
`9U26G7YWJ9` (Developer ID), fed entirely from repository secrets. The
[`CI`](../.github/workflows/ci.yml) workflow needs **no** secrets — it only runs
tests and an unsigned compile check.

Signing runs only on tags / manual dispatch, never on pull requests, so secrets
are never exposed to untrusted PRs.

## One-time Apple setup

1. **App IDs** (Apple Developer portal → Identifiers), both explicit:
   - `io.github.m96chan.VirtualCamera4Mac` — enable the **System Extension** and
     **App Groups** capabilities.
   - `io.github.m96chan.VirtualCamera4Mac.Extension` — enable **App Groups**.
   - Create the App Group `9U26G7YWJ9.io.github.m96chan.VirtualCamera4Mac` and
     assign it to both App IDs.
2. **Developer ID Application certificate** — you already have
   `Developer ID Application: Yusuke Harada (9U26G7YWJ9)`. Export it **with its
   private key** as a `.p12` (set a password).
3. **Provisioning profiles** (type: **Developer ID**), one per App ID, each
   referencing the Developer ID cert above. Download both `.provisionprofile`
   files and note their exact **names**.
4. **Notary credentials** — an app-specific password for your Apple ID
   (appleid.apple.com → Sign-In & Security → App-Specific Passwords).

## Repository secrets

Add these under **Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | `base64 -i DeveloperID.p12 \| pbcopy` |
| `P12_PASSWORD` | password you set when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | any random string (temp keychain password) |
| `PROVISIONING_PROFILE_APP_BASE64` | `base64 -i app.provisionprofile \| pbcopy` |
| `PROVISIONING_PROFILE_EXT_BASE64` | `base64 -i ext.provisionprofile \| pbcopy` |
| `PROVISIONING_PROFILE_NAME_APP` | the app profile's exact name |
| `PROVISIONING_PROFILE_NAME_EXT` | the extension profile's exact name |
| `APPLE_TEAM_ID` | `9U26G7YWJ9` |
| `NOTARY_APPLE_ID` | your Apple ID email |
| `NOTARY_PASSWORD` | the app-specific password |

`base64` on macOS: `base64 -i <file>` prints the encoded string (pipe to
`pbcopy` to copy it).

## Cutting a release

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow archives, exports with Developer ID, notarizes (`notarytool
--wait`), staples, and attaches `VirtualCamera4Mac.zip` to a GitHub Release.
You can also trigger it manually from the Actions tab (**Run workflow**).

## Notes / not yet verified

- This workflow has **not** been run end-to-end yet — it is gated on the Apple
  setup and secrets above. Expect to iterate on the first tagged build,
  especially the `archive`/`-exportArchive` provisioning-profile matching (the
  most common failure point for System Extensions).
- Notarization here uses Apple ID + app-specific password. To switch to an App
  Store Connect API key (`notarytool --key`), swap the `NOTARY_*` secrets and
  the `notarytool` flags.
- Distribution outside the App Store requires Developer ID signing **and**
  notarization for the System Extension to load on other machines.
