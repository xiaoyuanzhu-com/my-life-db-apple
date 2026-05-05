# Apple CI/CD Pipeline Design

## Goal

Automate iOS and macOS builds on push to `main`. iOS uploads to TestFlight for on-device testing; macOS packages as a drag-and-drop DMG uploaded as a GitHub Actions artifact.

## Architecture

One workflow, two parallel jobs, running on the Mac mini as a self-hosted GitHub Actions runner.

```
push to main
    ├── build-ios
    │   ├── Setup signing (temp keychain + cert + API key)
    │   ├── xcodebuild archive (generic/platform=iOS)
    │   ├── xcodebuild -exportArchive (app-store method)
    │   ├── xcrun altool --upload-app → TestFlight
    │   └── Cleanup
    │
    └── build-macos
        ├── Setup signing (temp keychain + cert + API key)
        ├── xcodebuild archive (generic/platform=macOS)
        ├── xcodebuild -exportArchive (development method)
        ├── hdiutil → DMG with /Applications symlink
        ├── Upload as GitHub Actions artifact
        └── Cleanup
```

## Files

| File | Purpose |
|------|---------|
| `.github/workflows/apple-build.yml` | Workflow definition |
| `ExportOptions-iOS.plist` | `app-store` export for TestFlight upload |
| `ExportOptions-macOS.plist` | `development` export for local DMG |

## Decisions

### Self-hosted runner on Mac mini

GitHub-hosted runners may not have Xcode 26.2. The Mac mini already has it, is free, and builds faster on Apple Silicon. One-time setup: install the GitHub Actions runner agent.

### Automatic signing with API key

Pass the App Store Connect API key to `xcodebuild` via `-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`, and `-allowProvisioningUpdates`. Xcode resolves provisioning profiles automatically — no manual profile export or management.

### Temporary keychain per build

Even though the Mac mini has certificates from Xcode development, CI builds use a temporary keychain for isolation. Created at job start, deleted at job end. Critical for self-hosted runners that persist between runs.

### macOS: `development` export method

Produces a .app signed with the development certificate. Works on any Mac with the provisioning profile installed (the Mac mini has this from Xcode). Avoids the complexity of `developer-id` + notarization, which is only needed for distribution to other Macs.

### DMG as GitHub Actions artifact

Available from the Actions tab after each build. Auto-deleted after 90 days. Can add GitHub Releases on version tags later if needed.

## GitHub Secrets (already configured)

| Secret | Purpose |
|--------|---------|
| `APP_STORE_CONNECT_KEY_ID` | API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | API key issuer |
| `APP_STORE_CONNECT_PRIVATE_KEY` | `.p8` key contents |
| `CERTIFICATES_P12` | Base64-encoded distribution certificate |
| `CERTIFICATES_P12_PASSWORD` | Certificate password |

## Prerequisites

1. Install GitHub Actions self-hosted runner on Mac mini
2. App Store Connect app entry exists for `xiaoyuanzhu.MyLifeDB`
