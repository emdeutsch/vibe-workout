# iOS TestFlight Upload Guide

This document explains how to build and upload the iOS app to TestFlight using the CLI.

## Prerequisites

1. **App Store Connect API Key** - Store in `~/.private_keys/AuthKey_<KEY_ID>.p8`
2. **API Key ID** - From App Store Connect (e.g., `45C93UF2KA`)
3. **Issuer ID** - From App Store Connect → Users and Access → Integrations → App Store Connect API

## Quick Upload (One Command)

From the project root:

```bash
cd apps/ios/viberunner && \
xcodebuild -scheme "Viberunner" -archivePath ./build/Viberunner.xcarchive archive -allowProvisioningUpdates && \
xcodebuild -exportArchive -archivePath ./build/Viberunner.xcarchive -exportPath ./build/export -exportOptionsPlist ./build/ExportOptions.plist -allowProvisioningUpdates && \
xcrun altool --upload-app --type ios --file ./build/export/Viberunner.ipa --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

## Step-by-Step

### 1. Archive the App

```bash
cd apps/ios/viberunner
xcodebuild -scheme "Viberunner" -archivePath ./build/Viberunner.xcarchive archive -allowProvisioningUpdates
```

This builds the **Production** scheme which points to:

- API: `https://vibe-runner-api.vercel.app`
- Supabase: Production instance

### 2. Export the Archive

Ensure `build/ExportOptions.plist` exists:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
```

Then export:

```bash
xcodebuild -exportArchive \
  -archivePath ./build/Viberunner.xcarchive \
  -exportPath ./build/export \
  -exportOptionsPlist ./build/ExportOptions.plist \
  -allowProvisioningUpdates
```

### 3. Upload to TestFlight

```bash
xcrun altool --upload-app \
  --type ios \
  --file ./build/export/Viberunner.ipa \
  --apiKey 45C93UF2KA \
  --apiIssuer 2643b0ce-38e5-4865-9237-d7979d42aeed
```

### 4. Wait for Processing

After upload, Apple processes the build (5-15 minutes). Check status at:
**App Store Connect → Viberunner → TestFlight**

## Local Development Build

For local testing (not TestFlight), use the "Viberunner (Local)" scheme which points to your local API server.

## Schemes

| Scheme             | API URL                              | Use Case                |
| ------------------ | ------------------------------------ | ----------------------- |
| Viberunner         | `https://vibe-runner-api.vercel.app` | Production / TestFlight |
| Viberunner (Local) | `http://<local-ip>:3000`             | Local development       |

## Troubleshooting

### "No Accounts with App Store Connect Access"

- Ensure API key is in `~/.private_keys/AuthKey_<KEY_ID>.p8`
- Verify Key ID and Issuer ID are correct

### Build Number Conflict

- Increment `CURRENT_PROJECT_VERSION` in project settings or `project.yml`

### Provisioning Issues

- Run with `-allowProvisioningUpdates` flag
- Ensure you're signed into an Apple Developer account in Xcode
