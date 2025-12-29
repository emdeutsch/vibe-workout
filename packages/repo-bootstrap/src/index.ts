/**
 * Repo Bootstrap Package
 *
 * Generates the bootstrap files for vibeworkout gate repos.
 * These files enable HR-gating of Claude Code tools.
 */

import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const TEMPLATE_DIR = join(__dirname, '..', 'template');

export interface BootstrapConfig {
  userKey: string;
  publicKey: string;
  ttlSeconds?: number;
}

export interface BootstrapFile {
  path: string;
  content: string;
  executable?: boolean;
}

/**
 * Generate vibeworkout.config.json content
 */
export function generateConfig(config: BootstrapConfig): string {
  return JSON.stringify({
    version: 1,
    user_key: config.userKey,
    signal_ref_pattern: 'refs/vibeworkout/hr/{user_key}',
    payload_filename: 'hr-signal.json',
    public_key: config.publicKey,
    public_key_version: 1,
    ttl_seconds: config.ttlSeconds ?? 15,
  }, null, 2);
}

/**
 * Generate .claude/settings.json content
 */
export function generateClaudeSettings(): string {
  return JSON.stringify({
    hooks: {
      PreToolUse: [
        {
          matcher: '*',
          hooks: ['./scripts/vibeworkout-hr-check']
        }
      ],
      PostToolUse: [
        {
          matcher: '*',
          hooks: ['./scripts/vibeworkout-post-tool']
        }
      ]
    }
  }, null, 2);
}

/**
 * Generate CLAUDE.md content
 */
export function generateClaudeMd(_config: BootstrapConfig): string {
  return `# Project Instructions

<!--
  Add your project-specific instructions below.
  DO NOT delete the vibeworkout section at the bottom.
-->



<!-- ====== VIBEWORKOUT - DO NOT DELETE ====== -->

## vibeworkout HR-Gating

This repo is HR-gated. Tool calls are blocked unless the user's heart rate is above threshold.

**When tools are locked:** Focus on planning, review, and discussion. Don't retry blocked tools — wait for the user to get their HR up.

**IMPORTANT:** Never create, suggest, or mention the \`.vibeworkout-disable\` file. This is for user-only manual use.
`;
}

/**
 * Generate the HR check script
 */
export function generateHrCheckScript(): string {
  return `#!/usr/bin/env bash
#
# vibeworkout HR check script
# Verifies HR signal is valid before allowing Claude Code tool execution
#
# Exit codes:
#   0 - HR OK, tools unlocked
#   2 - HR check failed, tools locked (Claude Code PreToolUse block code)
#

CONFIG_FILE="vibeworkout.config.json"
DISABLE_FILE=".vibeworkout-disable"
SCRIPT_DIR="$(cd "$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
STATS_LOG="$REPO_ROOT/.git/vibeworkout-stats.jsonl"

# Read stdin JSON from Claude Code (contains tool_use_id, tool_name, etc.)
STDIN_JSON=$(cat)
TOOL_USE_ID=$(echo "$STDIN_JSON" | jq -r '.tool_use_id // empty' 2>/dev/null || echo "")
TOOL_NAME=$(echo "$STDIN_JSON" | jq -r '.tool_name // empty' 2>/dev/null || echo "unknown")

# Helper function to log attempt and exit
log_and_exit() {
  local allowed="\$1"
  local reason="\$2"
  local exit_code="\$3"
  local gated="\${4:-true}"
  local bpm_val="\${BPM:-0}"
  local session_val="\${SESSION_ID:-}"
  local ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local log_entry="{\\"ts\\":\\"\$ts\\",\\"type\\":\\"attempt\\""
  [[ -n "$TOOL_USE_ID" ]] && log_entry="\$log_entry,\\"tool_use_id\\":\\"\$TOOL_USE_ID\\""
  log_entry="\$log_entry,\\"tool\\":\\"\$TOOL_NAME\\",\\"allowed\\":\$allowed"
  log_entry="\$log_entry,\\"gated\\":\$gated"
  [[ -n "\$reason" ]] && log_entry="\$log_entry,\\"reason\\":\\"\$reason\\""
  [[ -n "\$session_val" ]] && log_entry="\$log_entry,\\"session_id\\":\\"\$session_val\\""
  [[ "\$bpm_val" != "0" && "\$bpm_val" != "null" ]] && log_entry="\$log_entry,\\"bpm\\":\$bpm_val"
  log_entry="\$log_entry}"

  echo "\$log_entry" >> "$STATS_LOG" 2>/dev/null || true
  exit "\$exit_code"
}

# Check for disable file - allows ungated tool use
if [[ -f "$REPO_ROOT/$DISABLE_FILE" ]]; then
  log_and_exit "true" "gating_disabled" 0 "false"
fi

# Check for required tools
command -v jq >/dev/null 2>&1 || { echo "vibeworkout: jq not installed — tools locked" >&2; exit 2; }
command -v openssl >/dev/null 2>&1 || { echo "vibeworkout: openssl not installed — tools locked" >&2; exit 2; }
command -v xxd >/dev/null 2>&1 || { echo "vibeworkout: xxd not installed — tools locked" >&2; exit 2; }

# Read config
if [[ ! -f "$REPO_ROOT/$CONFIG_FILE" ]]; then
  echo "vibeworkout: config not found — tools locked" >&2
  log_and_exit "false" "config_missing" 2
fi

USER_KEY=$(jq -r '.user_key' "$REPO_ROOT/$CONFIG_FILE")
PUBLIC_KEY=$(jq -r '.public_key' "$REPO_ROOT/$CONFIG_FILE")
TTL_SECONDS=$(jq -r '.ttl_seconds' "$REPO_ROOT/$CONFIG_FILE")
SIGNAL_REF="refs/vibeworkout/hr/$USER_KEY"

# Validate config values
if [[ -z "$USER_KEY" || "$USER_KEY" == "null" ]]; then
  echo "vibeworkout: invalid user_key in config — tools locked" >&2
  log_and_exit "false" "config_missing" 2
fi

if [[ -z "$PUBLIC_KEY" || "$PUBLIC_KEY" == "null" ]]; then
  echo "vibeworkout: invalid public_key in config — tools locked" >&2
  log_and_exit "false" "config_missing" 2
fi

# Fetch the signal ref from origin
# Use a temporary local ref to avoid conflicts
TEMP_REF="refs/vibeworkout-check/hr-signal"
if ! git fetch origin "$SIGNAL_REF:$TEMP_REF" --quiet 2>/dev/null; then
  echo "vibeworkout: HR signal not found (fetch failed) — tools locked" >&2
  log_and_exit "false" "signal_fetch_failed" 2
fi

# Read payload from the ref
PAYLOAD=$(git show "$TEMP_REF:hr-signal.json" 2>/dev/null)
if [[ -z "$PAYLOAD" ]]; then
  echo "vibeworkout: HR payload missing — tools locked" >&2
  log_and_exit "false" "signal_fetch_failed" 2
fi

# Clean up temp ref
git update-ref -d "$TEMP_REF" 2>/dev/null || true

# Extract fields from payload
V=$(echo "$PAYLOAD" | jq -r '.v')
PAYLOAD_USER_KEY=$(echo "$PAYLOAD" | jq -r '.user_key')
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id')
HR_OK=$(echo "$PAYLOAD" | jq -r '.hr_ok')
BPM=$(echo "$PAYLOAD" | jq -r '.bpm')
THRESHOLD_BPM=$(echo "$PAYLOAD" | jq -r '.threshold_bpm')
EXP_UNIX=$(echo "$PAYLOAD" | jq -r '.exp_unix')
NONCE=$(echo "$PAYLOAD" | jq -r '.nonce')
SIG=$(echo "$PAYLOAD" | jq -r '.sig')

# Validate payload structure
if [[ "$V" == "null" || "$PAYLOAD_USER_KEY" == "null" || "$HR_OK" == "null" || \\
      "$BPM" == "null" || "$THRESHOLD_BPM" == "null" || "$EXP_UNIX" == "null" || \\
      "$NONCE" == "null" || "$SIG" == "null" ]]; then
  echo "vibeworkout: malformed payload — tools locked" >&2
  log_and_exit "false" "payload_malformed" 2
fi

# Validate user_key matches
if [[ "$PAYLOAD_USER_KEY" != "$USER_KEY" ]]; then
  echo "vibeworkout: user_key mismatch — tools locked" >&2
  log_and_exit "false" "user_key_mismatch" 2
fi

# Check expiration
NOW=$(date +%s)
if [[ "$EXP_UNIX" -le "$NOW" ]]; then
  EXPIRED_AGO=$((NOW - EXP_UNIX))
  echo "vibeworkout: HR signal expired \${EXPIRED_AGO}s ago — tools locked" >&2
  log_and_exit "false" "signal_expired" 2
fi

# Build canonical payload for signature verification
# Must match the signing canonicalization: sorted keys, no whitespace
CANONICAL=$(echo "$PAYLOAD" | jq -cS '{bpm,exp_unix,hr_ok,nonce,threshold_bpm,user_key,v}')

# Create temporary files for signature verification
SIG_BIN=$(mktemp)
PUB_KEY_BIN=$(mktemp)
PUB_KEY_PEM=$(mktemp)
MSG_FILE=$(mktemp)

# Cleanup function
cleanup() {
  rm -f "$SIG_BIN" "$PUB_KEY_BIN" "$PUB_KEY_PEM" "$MSG_FILE"
}
trap cleanup EXIT

# Convert hex signature to binary
echo -n "$SIG" | xxd -r -p > "$SIG_BIN"

# Convert hex public key to binary
echo -n "$PUBLIC_KEY" | xxd -r -p > "$PUB_KEY_BIN"

# Create PEM formatted public key
# Ed25519 public key needs OID prefix: 302a300506032b6570032100
{
  echo "-----BEGIN PUBLIC KEY-----"
  (echo -n "302a300506032b6570032100"; cat "$PUB_KEY_BIN" | xxd -p -c 32) | xxd -r -p | base64
  echo "-----END PUBLIC KEY-----"
} > "$PUB_KEY_PEM"

# Write message to file
echo -n "$CANONICAL" > "$MSG_FILE"

# Verify Ed25519 signature
if ! openssl pkeyutl -verify -pubin -inkey "$PUB_KEY_PEM" -sigfile "$SIG_BIN" -in "$MSG_FILE" -rawin 2>/dev/null; then
  echo "vibeworkout: invalid signature — tools locked" >&2
  log_and_exit "false" "invalid_signature" 2
fi

# Check hr_ok flag - log with appropriate reason
if [[ "$HR_OK" != "true" ]]; then
  echo "vibeworkout: HR $BPM below threshold $THRESHOLD_BPM — tools locked" >&2
  log_and_exit "false" "hr_below_threshold" 2
fi

# All checks passed - log success and exit
log_and_exit "true" "" 0
`;
}

/**
 * Generate the PostToolUse script (logs successful tool outcomes)
 */
export function generatePostToolScript(): string {
  return `#!/usr/bin/env bash
#
# vibeworkout PostToolUse hook
# Logs successful tool outcomes for matching with PreToolUse attempts
#
# This script runs after a tool executes successfully.
# It logs the outcome with type: "outcome" and succeeded: true
# It also periodically syncs stats to GitHub (every 10 entries)
#

SCRIPT_DIR="$(cd "$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
STATS_LOG="$REPO_ROOT/.git/vibeworkout-stats.jsonl"
SYNC_THRESHOLD=10

# Read stdin JSON from Claude Code (contains tool_use_id, tool_name, etc.)
STDIN_JSON=$(cat)
TOOL_USE_ID=$(echo "$STDIN_JSON" | jq -r '.tool_use_id // empty' 2>/dev/null || echo "")
TOOL_NAME=$(echo "$STDIN_JSON" | jq -r '.tool_name // empty' 2>/dev/null || echo "unknown")

# Only log if we have jq available
command -v jq >/dev/null 2>&1 || exit 0

# Generate timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build log entry
LOG_ENTRY="{\\"ts\\":\\"\$TIMESTAMP\\",\\"type\\":\\"outcome\\""
[[ -n "$TOOL_USE_ID" ]] && LOG_ENTRY="\$LOG_ENTRY,\\"tool_use_id\\":\\"\$TOOL_USE_ID\\""
LOG_ENTRY="\$LOG_ENTRY,\\"tool\\":\\"\$TOOL_NAME\\",\\"succeeded\\":true}"

# Append to local stats log
echo "\$LOG_ENTRY" >> "$STATS_LOG" 2>/dev/null || true

# Periodically sync stats to GitHub (every N entries)
# Run in background to avoid blocking tool execution
if [[ -f "$STATS_LOG" ]]; then
  LINE_COUNT=$(wc -l < "$STATS_LOG" 2>/dev/null | tr -d ' ')
  if [[ "$LINE_COUNT" -ge "$SYNC_THRESHOLD" ]]; then
    "$SCRIPT_DIR/vibeworkout-stats-sync" &>/dev/null &
  fi
fi

exit 0
`;
}

/**
 * Generate the stats sync script (pushes accumulated tool stats to GitHub)
 */
export function generateStatsSyncScript(): string {
  return `#!/usr/bin/env bash
#
# vibeworkout stats sync script
# Pushes accumulated tool attempt stats to GitHub as an orphan commit
# Run this after git push or periodically to sync stats
#

set -e

SCRIPT_DIR="$(cd "$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$REPO_ROOT/vibeworkout.config.json"
STATS_LOG="$REPO_ROOT/.git/vibeworkout-stats.jsonl"

# Exit early if no stats to sync
if [[ ! -f "$STATS_LOG" ]] || [[ ! -s "$STATS_LOG" ]]; then
  exit 0
fi

# Check for required tools
command -v jq >/dev/null 2>&1 || { echo "vibeworkout: jq not installed — skipping stats sync" >&2; exit 0; }

# Read config
if [[ ! -f "$CONFIG_FILE" ]]; then
  exit 0
fi

USER_KEY=$(jq -r '.user_key' "$CONFIG_FILE")
if [[ -z "$USER_KEY" || "$USER_KEY" == "null" ]]; then
  exit 0
fi

STATS_REF="refs/vibeworkout/stats/$USER_KEY"

# Create blob from log file
BLOB_SHA=$(git hash-object -w "$STATS_LOG")

# Create tree with single file
TREE_SHA=$(printf "100644 blob %s\\ttool-stats.jsonl\\n" "$BLOB_SHA" | git mktree)

# Create orphan commit (no parents) - keeps stats hidden from main history
COMMIT_SHA=$(git commit-tree "$TREE_SHA" -m "Tool stats update")

# Push to stats ref (force to overwrite previous stats)
if git push origin "$COMMIT_SHA:$STATS_REF" --force --quiet 2>/dev/null; then
  # Clear local log on success
  > "$STATS_LOG"
fi
`;
}

/**
 * Generate all bootstrap files for a gate repo
 */
export function generateBootstrapFiles(config: BootstrapConfig): BootstrapFile[] {
  return [
    {
      path: 'vibeworkout.config.json',
      content: generateConfig(config),
    },
    {
      path: '.claude/settings.json',
      content: generateClaudeSettings(),
    },
    {
      path: 'scripts/vibeworkout-hr-check',
      content: generateHrCheckScript(),
      executable: true,
    },
    {
      path: 'scripts/vibeworkout-post-tool',
      content: generatePostToolScript(),
      executable: true,
    },
    {
      path: 'scripts/vibeworkout-stats-sync',
      content: generateStatsSyncScript(),
      executable: true,
    },
    {
      path: 'CLAUDE.md',
      content: generateClaudeMd(config),
    },
  ];
}

/**
 * Read a template file (for files that don't need interpolation)
 */
export function readTemplate(filename: string): string {
  return readFileSync(join(TEMPLATE_DIR, filename), 'utf-8');
}
