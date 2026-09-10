# Laju — iOS App

Native Swift + SwiftUI, iOS 16+. See `Laju/documents/tech-spec.md` §1 and
`Laju/documents/repo-coding-rules.md` §1 for stack/structure rationale.

## Setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen), SwiftLint,
   SwiftFormat: `brew install xcodegen swiftlint swiftformat`
2. Generate the Xcode project (not committed — regenerate from
   `project.yml` after every clone/pull):
   ```bash
   cd ios
   xcodegen generate
   ```
3. Open `Laju.xcodeproj` in Xcode.

## Building for a physical device (T0.4)

**Status: done.** Verified on an iPhone 13 (iOS 18.6.2), team `NTHHTF27HU`,
bundle id `com.designbyripo.laju` (had to move off `com.laju.app` — that
identifier was already registered to a different Apple Developer account;
app IDs are globally unique across all accounts, not just within one).

Steps, if setting this up again on a new Mac/device:

1. Connect an iPhone via USB (or a previously-paired Wi-Fi debug
   connection), unlock it, tap "Trust This Computer" if prompted.
2. On the iPhone: Settings ▸ Privacy & Security ▸ Developer Mode ▸ on
   (requires a restart + confirm-on-unlock). Without this,
   `devicectl`/Xcode can see the device but can't install to it
   (`developerModeStatus: disabled`).
3. Confirm it's visible: `xcrun xctrace list devices` (or Xcode ▸ Window ▸
   Devices and Simulators).
4. In Xcode, open `Laju.xcodeproj` ▸ Settings (⌘,) ▸ Accounts ▸ add your
   Apple ID (a free Personal Team is enough for local device installs —
   no paid Apple Developer Program needed for this).
5. Select target `Laju` ▸ Signing & Capabilities ▸ check "Automatically
   manage signing" ▸ pick your team. If `xcodegen generate` is re-run
   after this, it will NOT wipe the team — `DEVELOPMENT_TEAM` is set in
   `project.yml` (see below), so it survives regeneration; the Xcode step
   is only needed once per Apple ID/Mac to actually create the signing
   identity and provisioning profile.
6. Build & Run (⌘R), or from the CLI:
   ```bash
   xcodebuild -scheme Laju -destination 'id=<device udid>' -allowProvisioningUpdates build
   xcrun devicectl device install app --device <device udid> <path to Laju.app>
   xcrun devicectl device process launch --device <device udid> com.designbyripo.laju
   ```
7. First launch will be blocked with "invalid code signature... not
   explicitly trusted" until you trust the developer certificate on the
   device: Settings ▸ General ▸ VPN & Device Management ▸ tap the
   certificate ▸ Trust.

`DEVELOPMENT_TEAM: NTHHTF27HU` and `CODE_SIGN_STYLE: Automatic` are set in
`project.yml` under `settings.base` — swap the team id there for a
different Apple ID/Mac.

## Running tests

```bash
xcodebuild -scheme Laju -destination 'platform=iOS Simulator,name=<sim name>' test
```

An iOS Simulator runtime is required and is now installed (`xcrun simctl
list runtimes` → iOS 26.3). Not required for T0.9, which is
physical-device-only by design — see
`Laju/documents/tasks/phase-0-setup.md` T0.9.
