# Viberunner iOS App

iOS and watchOS companion apps for viberunner HR gating.

## Requirements

- **Xcode 26.2+** (for iOS 26 / watchOS 26 SDK)
- **macOS Sequoia 15.6+** (or macOS Tahoe for AI features)
- **Apple Silicon Mac** recommended (required for Code Intelligence)

## Quick Start

```bash
# 1. Start local backend
npm run dev

# 2. Open Xcode project
open apps/ios/viberunner/viberunner.xcodeproj

# 3. Select scheme: "Viberunner (Local)"
# 4. Set your Development Team in Signing & Capabilities
# 5. Build & run to your device
```

## Environment Configuration

The app supports two environments via Xcode schemes:

| Scheme | Environment | Bundle ID | Use Case |
|--------|-------------|-----------|----------|
| **Viberunner (Local)** | Local Supabase | `com.viberunner.app.local` | Development |
| **Viberunner** | Production | `com.viberunner.app` | Release |

### Switching Environments

1. Click the scheme selector in Xcode toolbar (next to device selector)
2. Choose "Viberunner (Local)" or "Viberunner"
3. Build & run

Both versions can be installed **side-by-side** on the same device (different bundle IDs).

## Project Structure

```
apps/ios/viberunner/
├── Config/
│   ├── Local.xcconfig       # Local environment settings
│   └── Production.xcconfig  # Production environment settings
├── Sources/
│   ├── App/                 # App entry point
│   ├── Views/               # SwiftUI views
│   ├── Services/            # API, Auth, Workout services
│   ├── Models/              # Data models
│   └── Info.plist           # App configuration
├── project.yml              # XcodeGen spec (generates .xcodeproj)
└── viberunner.xcodeproj/    # Generated Xcode project
```

## Configuration Files

### xcconfig Files

Environment-specific settings are defined in `.xcconfig` files:

**Local.xcconfig:**
```
API_BASE_URL = http://192.168.1.159:3000
SUPABASE_URL = http://192.168.1.159:54421
PRODUCT_BUNDLE_IDENTIFIER = com.viberunner.app.local
PRODUCT_NAME = Viberunner Local
```

**Production.xcconfig:**
```
API_BASE_URL = https://api.viberunner.com
SUPABASE_URL = https://fspwoookcnikhlaytpfd.supabase.co
PRODUCT_BUNDLE_IDENTIFIER = com.viberunner.app
PRODUCT_NAME = Viberunner
```

### Updating Your Local IP

If your Mac's IP changes, update `Config/Local.xcconfig`:

```bash
# Get your current IP
ipconfig getifaddr en0

# Update Local.xcconfig with new IP
```

Then regenerate the project:

```bash
cd apps/ios/viberunner
xcodegen generate
```

## XcodeGen

The Xcode project is generated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen).

### Regenerating the Project

After modifying `project.yml`:

```bash
# Install xcodegen (first time only)
brew install xcodegen

# Regenerate project
cd apps/ios/viberunner
xcodegen generate
```

### Why XcodeGen?

- **Reproducible**: Project file generated from YAML spec
- **Git-friendly**: Fewer merge conflicts than `.xcodeproj`
- **Consistent**: Same project structure across team

## Local Development Setup

### 1. Start Local Backend

```bash
# From repo root
npm run dev
```

This starts:
- Local Supabase (ports 54421-54424)
- API server (port 3000)
- Worker process

### 2. Verify Backend is Running

```bash
# Health check
curl http://localhost:3000/health

# Supabase Studio
open http://127.0.0.1:54423
```

### 3. Build iOS App

1. Open `viberunner.xcodeproj`
2. Select "Viberunner (Local)" scheme
3. Select your iPhone as destination
4. Press ⌘R to build and run

## Testing Checklist

### Local Environment
- [ ] `npm run dev` starts without errors
- [ ] Health endpoint returns OK: `curl http://localhost:3000/health`
- [ ] Supabase Studio accessible at http://127.0.0.1:54423

### iOS App
- [ ] App builds successfully
- [ ] App shows "Local" in Settings > About > Environment
- [ ] Login with GitHub OAuth works
- [ ] HR threshold slider updates

### Watch App
- [ ] Watch app pairs with iPhone app
- [ ] Workout starts with 3-second countdown
- [ ] HR samples stream to iPhone

### End-to-End
- [ ] Start workout on watch
- [ ] Verify HR samples in local database
- [ ] Create gate repo from app
- [ ] Verify bootstrap files on GitHub

## Troubleshooting

### "Could not connect to server"
- Ensure `npm run dev` is running
- Check your Mac's IP matches `Local.xcconfig`
- Verify firewall allows connections on port 3000

### "Invalid bundle identifier"
- Set your Development Team in Xcode
- The bundle ID must be unique to your team

### Project won't build after pulling
```bash
cd apps/ios/viberunner
xcodegen generate
```

### Watch app not connecting
- Ensure both apps use same bundle ID prefix
- Check WatchConnectivity is properly initialized
