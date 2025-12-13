# viberunner HR-Gated Repository

This repository is protected by viberunner. Claude Code tool calls (edit, write, bash, etc.) are gated by the user's live heart rate.

## How it works

- You can **chat anytime** without restrictions
- **Tool calls are blocked** unless the user's heart rate is above their configured threshold
- When tools are locked, you'll see: `viberunner: HR below threshold — tools locked`

## When tools are locked

Switch to **planning and review mode**:
- Discuss architecture and design decisions
- Review code and suggest improvements
- Plan implementation steps
- Answer questions about the codebase
- **Don't spam tool calls** — wait for the user to get their HR up!

## Configuration

See `viberunner.config.json` for this repo's configuration:
- `user_key`: Your unique identifier
- `signal_ref_pattern`: Where HR signals are stored
- `public_key`: Ed25519 public key for signature verification
- `ttl_seconds`: How long a signal is valid (typically 15 seconds)

## Commit Tagging

When making commits in this repository, **always include a viberunner session tag** in your commit message. This allows the user to see which commits were made during each workout session.

**Format:** Add `[vr:SESSION_ID]` at the end of your commit message, where `SESSION_ID` is from the current HR signal.

Example:
```
feat: add user authentication flow [vr:abc123-def456]
```

The session ID is available in the HR signal payload. If you can't determine the session ID, omit the tag — don't make one up.

## How to disable temporarily

To temporarily disable HR gating:
1. Rename `.claude/settings.json` to `.claude/settings.json.disabled`
2. Tool calls will work normally
3. Rename back when ready to re-enable

## Learn more

Visit [viberunner](https://github.com/viberunner/viberunner) for documentation and support.
