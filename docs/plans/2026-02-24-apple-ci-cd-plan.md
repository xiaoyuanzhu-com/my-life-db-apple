# Apple CI/CD Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automate iOS TestFlight uploads and macOS DMG packaging on every push to `main`, running on the Mac mini as a self-hosted GitHub Actions runner.

**Architecture:** One workflow file with two jobs (iOS and macOS). Both run on the Mac mini self-hosted runner (sequential since single runner). Signing uses the App Store Connect API key for automatic provisioning, with a temporary keychain holding the distribution certificate alongside the login keychain (which has the development certificate from Xcode).

**Tech Stack:** GitHub Actions, xcodebuild, xcrun altool, hdiutil, security (macOS keychain CLI)

---

### Task 1: Install GitHub Actions Self-Hosted Runner on Mac mini

This is a prerequisite — the runner must be online before the workflow can execute.

**Step 1: Create runner registration in GitHub**

Go to `https://github.com/xiaoyuanzhu-com/my-life-db-apple/settings/actions/runners/new` and select **macOS** + **ARM64**. Copy the registration token shown on that page.

**Step 2: SSH to Mac mini and install the runner**

```bash
ssh macmini
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner.tar.gz -L https://github.com/actions/runner/releases/latest/download/actions-runner-osx-arm64-2.322.0.tar.gz
tar xzf actions-runner.tar.gz
```

> Note: Check the GitHub page from Step 1 for the exact download URL and version — it may differ.

**Step 3: Configure the runner**

```bash
cd ~/actions-runner
./config.sh --url https://github.com/xiaoyuanzhu-com/my-life-db-apple --token <TOKEN_FROM_STEP_1>
```

When prompted:
- Runner group: press Enter (default)
- Runner name: `macmini`
- Labels: press Enter (default `self-hosted,macOS,ARM64`)
- Work folder: press Enter (default `_work`)

**Step 4: Install as a LaunchAgent (user-level, NOT sudo)**

```bash
cd ~/actions-runner
./svc.sh install
./svc.sh start
```

Important: do NOT use `sudo`. Running without sudo creates a LaunchAgent (user-level service) that has access to the login keychain. This is required for code signing — the login keychain holds the Apple Development certificate from Xcode.

**Step 5: Verify the runner is online**

Go to `https://github.com/xiaoyuanzhu-com/my-life-db-apple/settings/actions/runners`. The `macmini` runner should show as **Idle** (green).

**Step 6: Verify Xcode is available on the runner**

```bash
ssh macmini
xcodebuild -version
# Expected: Xcode 26.2 (or similar)
```

---

### Task 2: Create ExportOptions-iOS.plist

**Files:**
- Create: `ExportOptions-iOS.plist` (repo root)

**Step 1: Create the file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store</string>
	<key>teamID</key>
	<string>R3845XW5FZ</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadBitcode</key>
	<false/>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
```

**Step 2: Verify the plist is valid**

```bash
plutil -lint ExportOptions-iOS.plist
# Expected: ExportOptions-iOS.plist: OK
```

---

### Task 3: Create ExportOptions-macOS.plist

**Files:**
- Create: `ExportOptions-macOS.plist` (repo root)

**Step 1: Create the file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>development</string>
	<key>teamID</key>
	<string>R3845XW5FZ</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
```

**Step 2: Verify the plist is valid**

```bash
plutil -lint ExportOptions-macOS.plist
# Expected: ExportOptions-macOS.plist: OK
```

---

### Task 4: Create the GitHub Actions Workflow

**Files:**
- Create: `.github/workflows/apple-build.yml`

**Step 1: Create the directory**

```bash
mkdir -p .github/workflows
```

**Step 2: Create the workflow file**

```yaml
name: Apple Build and Deploy

on:
  push:
    branches:
      - main

concurrency:
  group: apple-build-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-ios:
    name: Build iOS → TestFlight
    runs-on: self-hosted
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup signing
        env:
          CERTIFICATES_P12: ${{ secrets.CERTIFICATES_P12 }}
          CERTIFICATES_P12_PASSWORD: ${{ secrets.CERTIFICATES_P12_PASSWORD }}
          APP_STORE_CONNECT_PRIVATE_KEY: ${{ secrets.APP_STORE_CONNECT_PRIVATE_KEY }}
          APP_STORE_CONNECT_KEY_ID: ${{ secrets.APP_STORE_CONNECT_KEY_ID }}
        run: |
          # Create temporary keychain
          KEYCHAIN_PATH="$RUNNER_TEMP/build.keychain-db"
          KEYCHAIN_PASSWORD=$(openssl rand -base64 32)
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -t 3600 -u "$KEYCHAIN_PATH"

          # Import distribution certificate
          echo "$CERTIFICATES_P12" | base64 --decode > "$RUNNER_TEMP/certificate.p12"
          security import "$RUNNER_TEMP/certificate.p12" \
            -k "$KEYCHAIN_PATH" \
            -P "$CERTIFICATES_P12_PASSWORD" \
            -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: \
            -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

          # Add temp keychain + login keychain to search list
          security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db

          # Write API key for altool and xcodebuild
          mkdir -p ~/private_keys
          echo "$APP_STORE_CONNECT_PRIVATE_KEY" \
            > ~/private_keys/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8

          # Export for later steps
          echo "KEYCHAIN_PATH=$KEYCHAIN_PATH" >> "$GITHUB_ENV"

      - name: Build iOS archive
        env:
          APP_STORE_CONNECT_KEY_ID: ${{ secrets.APP_STORE_CONNECT_KEY_ID }}
          APP_STORE_CONNECT_ISSUER_ID: ${{ secrets.APP_STORE_CONNECT_ISSUER_ID }}
        run: |
          xcodebuild archive \
            -project MyLifeDB.xcodeproj \
            -scheme MyLifeDB \
            -archivePath "$RUNNER_TEMP/MyLifeDB-iOS.xcarchive" \
            -destination "generic/platform=iOS" \
            -authenticationKeyPath ~/private_keys/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8 \
            -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
            -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
            -allowProvisioningUpdates

      - name: Export IPA
        env:
          APP_STORE_CONNECT_KEY_ID: ${{ secrets.APP_STORE_CONNECT_KEY_ID }}
          APP_STORE_CONNECT_ISSUER_ID: ${{ secrets.APP_STORE_CONNECT_ISSUER_ID }}
        run: |
          xcodebuild -exportArchive \
            -archivePath "$RUNNER_TEMP/MyLifeDB-iOS.xcarchive" \
            -exportPath "$RUNNER_TEMP/ios-output" \
            -exportOptionsPlist ExportOptions-iOS.plist \
            -authenticationKeyPath ~/private_keys/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8 \
            -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
            -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
            -allowProvisioningUpdates

      - name: Upload to TestFlight
        env:
          APP_STORE_CONNECT_KEY_ID: ${{ secrets.APP_STORE_CONNECT_KEY_ID }}
          APP_STORE_CONNECT_ISSUER_ID: ${{ secrets.APP_STORE_CONNECT_ISSUER_ID }}
        run: |
          xcrun altool --upload-app \
            -f "$RUNNER_TEMP/ios-output/MyLifeDB.ipa" \
            -t ios \
            --apiKey "$APP_STORE_CONNECT_KEY_ID" \
            --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"

      - name: Cleanup
        if: always()
        run: |
          security list-keychains -d user -s login.keychain-db
          security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
          rm -f "$RUNNER_TEMP/certificate.p12"
          rm -f ~/private_keys/AuthKey_*.p8
          rm -rf "$RUNNER_TEMP/MyLifeDB-iOS.xcarchive"
          rm -rf "$RUNNER_TEMP/ios-output"

  build-macos:
    name: Build macOS → DMG
    runs-on: self-hosted
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup signing
        env:
          CERTIFICATES_P12: ${{ secrets.CERTIFICATES_P12 }}
          CERTIFICATES_P12_PASSWORD: ${{ secrets.CERTIFICATES_P12_PASSWORD }}
          APP_STORE_CONNECT_PRIVATE_KEY: ${{ secrets.APP_STORE_CONNECT_PRIVATE_KEY }}
          APP_STORE_CONNECT_KEY_ID: ${{ secrets.APP_STORE_CONNECT_KEY_ID }}
        run: |
          # Create temporary keychain
          KEYCHAIN_PATH="$RUNNER_TEMP/build.keychain-db"
          KEYCHAIN_PASSWORD=$(openssl rand -base64 32)
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -t 3600 -u "$KEYCHAIN_PATH"

          # Import distribution certificate
          echo "$CERTIFICATES_P12" | base64 --decode > "$RUNNER_TEMP/certificate.p12"
          security import "$RUNNER_TEMP/certificate.p12" \
            -k "$KEYCHAIN_PATH" \
            -P "$CERTIFICATES_P12_PASSWORD" \
            -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: \
            -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

          # Add temp keychain + login keychain to search list
          # login keychain has the Apple Development cert for macOS dev signing
          security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db

          # Write API key for xcodebuild provisioning
          mkdir -p ~/private_keys
          echo "$APP_STORE_CONNECT_PRIVATE_KEY" \
            > ~/private_keys/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8

          # Export for later steps
          echo "KEYCHAIN_PATH=$KEYCHAIN_PATH" >> "$GITHUB_ENV"

      - name: Build macOS archive
        env:
          APP_STORE_CONNECT_KEY_ID: ${{ secrets.APP_STORE_CONNECT_KEY_ID }}
          APP_STORE_CONNECT_ISSUER_ID: ${{ secrets.APP_STORE_CONNECT_ISSUER_ID }}
        run: |
          xcodebuild archive \
            -project MyLifeDB.xcodeproj \
            -scheme MyLifeDB \
            -archivePath "$RUNNER_TEMP/MyLifeDB-macOS.xcarchive" \
            -destination "generic/platform=macOS" \
            -authenticationKeyPath ~/private_keys/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8 \
            -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
            -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
            -allowProvisioningUpdates

      - name: Export app
        env:
          APP_STORE_CONNECT_KEY_ID: ${{ secrets.APP_STORE_CONNECT_KEY_ID }}
          APP_STORE_CONNECT_ISSUER_ID: ${{ secrets.APP_STORE_CONNECT_ISSUER_ID }}
        run: |
          xcodebuild -exportArchive \
            -archivePath "$RUNNER_TEMP/MyLifeDB-macOS.xcarchive" \
            -exportPath "$RUNNER_TEMP/macos-output" \
            -exportOptionsPlist ExportOptions-macOS.plist \
            -authenticationKeyPath ~/private_keys/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8 \
            -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
            -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
            -allowProvisioningUpdates

      - name: Create DMG
        run: |
          # Stage .app + Applications symlink for drag-and-drop install
          mkdir -p "$RUNNER_TEMP/dmg-staging"
          cp -R "$RUNNER_TEMP/macos-output/MyLifeDB.app" "$RUNNER_TEMP/dmg-staging/"
          ln -s /Applications "$RUNNER_TEMP/dmg-staging/Applications"

          # Create compressed DMG
          hdiutil create \
            -volname "MyLifeDB" \
            -srcfolder "$RUNNER_TEMP/dmg-staging" \
            -ov -format UDZO \
            "$RUNNER_TEMP/MyLifeDB.dmg"

      - name: Upload DMG artifact
        uses: actions/upload-artifact@v4
        with:
          name: MyLifeDB-macOS-${{ github.sha }}
          path: ${{ runner.temp }}/MyLifeDB.dmg
          retention-days: 90

      - name: Cleanup
        if: always()
        run: |
          security list-keychains -d user -s login.keychain-db
          security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
          rm -f "$RUNNER_TEMP/certificate.p12"
          rm -f ~/private_keys/AuthKey_*.p8
          rm -rf "$RUNNER_TEMP/MyLifeDB-macOS.xcarchive"
          rm -rf "$RUNNER_TEMP/macos-output"
          rm -rf "$RUNNER_TEMP/dmg-staging"
          rm -f "$RUNNER_TEMP/MyLifeDB.dmg"
```

---

### Task 5: Commit and Push

**Step 1: Stage all new files**

```bash
git add ExportOptions-iOS.plist ExportOptions-macOS.plist .github/workflows/apple-build.yml
git status
```

Expected: 3 new files staged.

**Step 2: Commit**

```bash
git commit -m "ci: add Apple CI/CD — iOS TestFlight + macOS DMG"
```

**Step 3: Push to main and monitor**

```bash
git push origin main
```

Go to `https://github.com/xiaoyuanzhu-com/my-life-db-apple/actions` and watch the `Apple Build and Deploy` workflow. Both jobs should appear and run sequentially on the Mac mini.

---

### Task 6: Verify End-to-End

**Step 1: Verify iOS build uploaded to TestFlight**

- Open the TestFlight app on your iPhone
- Within ~5-15 minutes of the build completing, a new build should appear for MyLifeDB
- Tap Install to test

**Step 2: Verify macOS DMG artifact**

- In the completed workflow run on GitHub Actions, click the `MyLifeDB-macOS-<sha>` artifact
- Download the DMG
- Open the DMG — you should see MyLifeDB.app and an Applications folder shortcut
- Drag MyLifeDB.app into Applications to install

**Step 3: If a job fails, check logs**

Common issues:
- **"No signing certificate"** → the login keychain is locked or runner isn't a LaunchAgent; re-run `./svc.sh install` without sudo
- **"No provisioning profile"** → the API key credentials are wrong; verify secrets match the .p8/Key ID/Issuer ID
- **"altool: upload failed"** → the app entry doesn't exist in App Store Connect, or the bundle ID doesn't match
- **"hdiutil: create failed"** → the macOS export didn't produce a .app; check the exportArchive step logs
