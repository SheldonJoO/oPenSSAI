# Agent Guidelines for oPenSSAI

A file for [guiding AI coding agents](https://agents.md/).

## Project Overview

oPenSSAI is an iOS app that sideloads and refreshes apps on-device with a
personal Apple ID, using a local VPN loopback (`em_proxy` and `minimuxer`)
instead of a computer. It is a fork of SideStore (AGPLv3), with a
Chinese-first UI: the development language is Simplified Chinese
(`DEVELOPMENT_LANGUAGE = zh-Hans`), and all user-visible strings ship in
Chinese.

oPenSSAI is written in pure Swift and built with Xcode. Dependencies
(`minimuxer`, `SideSign`) are vendored as plain directories under
`Dependencies/` and integrated as local Swift Packages. `minimuxer` is pure
Swift, and `em_proxy` is bundled as an XCFramework via SPM. We use Makefiles
for CLI build and packaging automation.

App installation, certificate signing, and pairing have tricky edge cases
across supported iOS versions (iOS 15+). Preserve existing behavior outside
the intended fix, avoid broad refactors in signing or networking code, and be
skeptical of generated code. Prefer modern Swift Concurrency over legacy
dispatch queues. Add occasional comments that say something like "needs proper
testing" without it repeating too much through the diff. Do not commit pairing
files, certificates, private keys, anisette data, Apple IDs, passwords, or
device UDIDs.

### Fork rules

- **License: AGPLv3.** Keep all license and attribution notices and copyright
  headers (Riley Testut, SideStore Contributors). The AGPLv3 §13 network
  clause applies: users of the app over a network are entitled to the source.
- **Upstream credit:** oPenSSAI builds on SideStore's open-source code. Keep
  the fork provenance (fork point commit + submodule hashes) in README.md and
  the upstream attribution in the app's About/Licenses screens.
- **No Seal content.** Seal is a closed-source SideStore fork and is a
  behavioral reference only. Never copy, decompile, patch, or reuse any part
  of Seal's binary, IPA, strings, or resources.
- **No iloader branding.** The installer companion is a separate project; do
  not reuse iloader's name, logo, or branding (MIT code, separate
  LICENSE-BRANDING).
- **Chinese-first.** New user-visible strings go in Chinese. `NSLocalizedString`
  keys stay in English (lookup keys); their values in `zh-Hans.lproj/` are
  Chinese. SwiftUI `Text("...")` literals auto-localize via
  `Localizable.strings` — add the key there, do not hardcode Chinese in code.
- **WireGuard config:** `oPenSSAI.conf` intentionally keeps SideStore's
  official keypair — the keys are coupled to the server side baked into the
  `em_proxy` XCFramework. Do not regenerate them without also forking em_proxy
  (see the comment at the top of `oPenSSAI.conf` and `docs/ARCHITECTURE.md`).

### Project Structure

- `AltStore/` - Main iOS app target: UI, tab bar navigation (Browse, My Apps,
  Settings, News), App IDs, permissions, and app management.
- `SideStore/` - SideStore-derived logic and UI overrides: boot flow
  (`AppBootManager.swift`), maintenance (`MaintenanceManager.swift`), deep links,
  and core utilities. (Directory and module names are unchanged from upstream.)
- `SideBackup/` - Helper launcher and backup engine target.
- `AltWidget/` - Home Screen and Lock Screen widget extension.
- `Shared/` - Shared utilities, categories, extensions, and error definitions.
- `Dependencies/` - Vendored submodules (`minimuxer`, `SideSign`) integrated as
  local Swift Packages. Avoid touching these unless explicitly updating dependencies.
- `xcconfigs/` - Shared and target-specific build configs.
- `scripts/` - CI scripts, sideconf tools, and build helpers.
- `Makefile` - Command-line build and packaging orchestration.
- `docs/` - Fork documentation: architecture, scaffold plan, license notes.

## Building and Formatting

Requires macOS with Xcode 15+.

### Setup and Dependencies

Clone with submodules (the vendored directories are plain copies in this
repo, but upstream updates come from the SideStore repo):

```sh
git clone https://github.com/SheldonJoO/oPenSSAI.git --recurse-submodules
```

Xcode resolves dependencies automatically through local Swift Packages in `Dependencies/` (`SideSign`, `minimuxer`, and `EMProxy.xcframework`).

### Code Signing

1. Copy `CodeSigning.xcconfig.sample` to `CodeSigning.xcconfig`:
   ```sh
   cp CodeSigning.xcconfig.sample CodeSigning.xcconfig
   ```
2. Set your `DEVELOPMENT_TEAM` and signing options. The default bundle ID is
   `com.openssai.app`; the placeholder team ID `XYZ0123456` in
   `Build.xcconfig` must be replaced with your own before building.
3. For local debugging on a device from Xcode, register the device for
   development in Xcode so apps can be resigned and installed for it.

### Building with Xcode

Open `AltStore.xcodeproj` in Xcode:
```sh
open AltStore.xcodeproj
```

### Packaging an IPA (Makefile)

CLI build and packaging commands:

```sh
# Release IPA
make build fakesign ipa

# Debug IPA
export BUILD_CONFIG=Debug
make build fakesign ipa

# Alpha or Beta IPA
export IS_ALPHA=1; make build fakesign ipa
export IS_BETA=1; make build fakesign ipa

# Custom Bundle ID Suffix
export BUNDLE_ID_SUFFIX=XYZ0123456
make build fakesign ipa
```

This produces `oPenSSAI.ipa` in the repo root.

### Formatting

- **Swift**: 4 spaces, UTF-8, LF line endings (see `.editorconfig`).
- **Concurrency**: Use modern Swift Concurrency (`async`/`await`, `Task`, actors) rather than GCD or completion callbacks.
- **Makefiles**: Tabs only.
- Match existing formatting in adjacent code. Don't reformat unrelated lines.
