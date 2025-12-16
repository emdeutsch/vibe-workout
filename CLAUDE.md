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

### Building and Deploying

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
