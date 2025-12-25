# Claude Code Project Instructions

## Database Migrations

Use Prisma migrations for all schema changes. See `docs/MIGRATION_WORKFLOW.md` for complete workflow.

**Quick reference:**

```bash
# Development (local)
cd packages/db
npx prisma migrate dev --name <description>

# Production
npx prisma migrate deploy
```

## iOS Development

### Version Management

**CRITICAL:** Before any TestFlight upload, you MUST:

1. **ASK THE USER** for the current TestFlight build number (they must check App Store Connect → TestFlight → Builds)
2. **Increment CFBundleVersion** in `apps/ios/viberunner/Sources/Info.plist` to be higher than that number
3. **Commit the version bump** to git before or immediately after upload

**WARNING TO AGENTS:** NEVER look at git history or Info.plist to determine the current build number. Git is often out of sync with TestFlight. You MUST ask the user to check TestFlight directly. Uploading a duplicate or lower build number will fail and waste time.

| File                                     | Key                          | Purpose                                                                         |
| ---------------------------------------- | ---------------------------- | ------------------------------------------------------------------------------- |
| `apps/ios/viberunner/Sources/Info.plist` | `CFBundleShortVersionString` | Marketing version (e.g., "1.0")                                                 |
| `apps/ios/viberunner/Sources/Info.plist` | `CFBundleVersion`            | Build number - must increment for each TestFlight upload (ask user for current) |

### TestFlight Upload

See `docs/IOS_TESTFLIGHT_UPLOAD.md` for complete CLI upload workflow.

**Quick upload:**

```bash
# 1. First, check current build in TestFlight and update CFBundleVersion in Info.plist

# 2. Then build and upload:
cd apps/ios/viberunner && \
xcodebuild -scheme "Viberunner" -archivePath ./build/Viberunner.xcarchive archive -allowProvisioningUpdates && \
xcodebuild -exportArchive -archivePath ./build/Viberunner.xcarchive -exportPath ./build/export -exportOptionsPlist ./build/ExportOptions.plist -allowProvisioningUpdates && \
xcrun altool --upload-app --type ios --file ./build/export/Viberunner.ipa --apiKey 45C93UF2KA --apiIssuer 2643b0ce-38e5-4865-9237-d7979d42aeed

# 3. Commit the version bump if not already done
```

### Local Development

Use the iOS deploy script to build, install, and launch the app on a connected device:

```bash
scripts/ios-deploy.sh
```

This script:

- Detects the connected iOS device
- Builds the "Viberunner (Local)" scheme
- Installs the app on the device
- Attempts to launch it (requires unlocked device)

### Viewing Device Logs

**Best approach: Run from Xcode with debugger attached.**

1. Open `apps/ios/viberunner/viberunner.xcodeproj` in Xcode
2. Select your iPhone as the target device
3. Press `Cmd + R` to build and run
4. View logs in Debug Console: `Cmd + Shift + Y`
5. Filter by typing in the console filter field

The app uses Apple's `Logger` API with proper log levels (`.info`, `.debug`, `.error`). When the debugger is attached, all log values are visible (no `<private>` redaction).

To share logs with Claude: copy/paste relevant lines from Xcode's debug console.

## Supabase Local Development

### OAuth Configuration

For GitHub OAuth to work locally, the Supabase dashboard must have the app's callback URL in its redirect allowlist:

- Callback URL: `viberunner://github-callback`
- Supabase dashboard: http://localhost:54423 → Authentication → URL Configuration → Redirect URLs

### Local Services

Start local Supabase:

```bash
cd /Users/evandeutsch/vibe-runner && npx supabase start
```

The iOS app connects to Supabase at `http://192.168.1.144:54421` (configured in `apps/ios/viberunner/Config/Local.xcconfig`).
