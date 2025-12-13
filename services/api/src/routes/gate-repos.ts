/**
 * Gate Repos routes - create and manage HR-gated repositories
 */

import { Hono } from 'hono';
import { prisma } from '@viberunner/db';
import { authMiddleware } from '../middleware/auth.js';
import { decrypt } from '../lib/encryption.js';
import {
  createUserOctokit,
  createRepoFromTemplate,
  createEmptyRepo,
  commitBootstrapFiles,
} from '../lib/github.js';
import { config } from '../config.js';
import { buildSignalRef, PAYLOAD_FILENAME, SIGNAL_REF_PATTERN } from '@viberunner/shared';
import type {
  CreateGateRepoRequest,
  CreateGateRepoResponse,
  GateRepoResponse,
  GateRepoConfig,
} from '@viberunner/shared';

const gateRepos = new Hono();

// Apply auth to all routes
gateRepos.use('*', authMiddleware);

/**
 * Generate bootstrap files for a gate repo
 */
function generateBootstrapFiles(userKey: string, publicKey: string): Array<{ path: string; content: string }> {
  const signalRef = buildSignalRef(userKey);

  // viberunner.config.json
  const configContent: GateRepoConfig = {
    version: 1,
    user_key: userKey,
    signal_ref_pattern: SIGNAL_REF_PATTERN,
    payload_filename: PAYLOAD_FILENAME,
    public_key: publicKey,
    public_key_version: 1,
    ttl_seconds: config.hrTtlSeconds,
  };

  // .claude/settings.json - Claude Code hook configuration
  const claudeSettings = {
    hooks: {
      PreToolUse: [
        {
          matcher: '*',
          hooks: ['./scripts/viberunner-hr-check']
        }
      ]
    }
  };

  // scripts/viberunner-hr-check - The enforcement script (must match template version)
  const hrCheckScript = `#!/usr/bin/env bash
#
# viberunner HR check script
# Verifies HR signal is valid before allowing Claude Code tool execution
#
# Exit codes:
#   0 - HR OK, tools unlocked
#   2 - HR check failed, tools locked (Claude Code PreToolUse block code)
#

set -e

CONFIG_FILE="viberunner.config.json"
SCRIPT_DIR="$(cd "$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Check for required tools
command -v jq >/dev/null 2>&1 || { echo "viberunner: jq not installed — tools locked" >&2; exit 2; }
command -v openssl >/dev/null 2>&1 || { echo "viberunner: openssl not installed — tools locked" >&2; exit 2; }
command -v xxd >/dev/null 2>&1 || { echo "viberunner: xxd not installed — tools locked" >&2; exit 2; }

# Read config
if [[ ! -f "$REPO_ROOT/$CONFIG_FILE" ]]; then
  echo "viberunner: config not found — tools locked" >&2
  exit 2
fi

USER_KEY=$(jq -r '.user_key' "$REPO_ROOT/$CONFIG_FILE")
PUBLIC_KEY=$(jq -r '.public_key' "$REPO_ROOT/$CONFIG_FILE")
TTL_SECONDS=$(jq -r '.ttl_seconds' "$REPO_ROOT/$CONFIG_FILE")
SIGNAL_REF="refs/viberunner/hr/$USER_KEY"

# Validate config values
if [[ -z "$USER_KEY" || "$USER_KEY" == "null" ]]; then
  echo "viberunner: invalid user_key in config — tools locked" >&2
  exit 2
fi

if [[ -z "$PUBLIC_KEY" || "$PUBLIC_KEY" == "null" ]]; then
  echo "viberunner: invalid public_key in config — tools locked" >&2
  exit 2
fi

# Fetch the signal ref from origin
TEMP_REF="refs/viberunner-check/hr-signal"
if ! git fetch origin "$SIGNAL_REF:$TEMP_REF" --quiet 2>/dev/null; then
  echo "viberunner: HR signal not found (fetch failed) — tools locked" >&2
  exit 2
fi

# Read payload from the ref
PAYLOAD=$(git show "$TEMP_REF:hr-signal.json" 2>/dev/null)
if [[ -z "$PAYLOAD" ]]; then
  echo "viberunner: HR payload missing — tools locked" >&2
  exit 2
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
if [[ "$V" == "null" || "$PAYLOAD_USER_KEY" == "null" || "$SESSION_ID" == "null" || \\
      "$HR_OK" == "null" || "$BPM" == "null" || "$THRESHOLD_BPM" == "null" || \\
      "$EXP_UNIX" == "null" || "$NONCE" == "null" || "$SIG" == "null" ]]; then
  echo "viberunner: malformed payload — tools locked" >&2
  exit 2
fi

# Validate user_key matches
if [[ "$PAYLOAD_USER_KEY" != "$USER_KEY" ]]; then
  echo "viberunner: user_key mismatch — tools locked" >&2
  exit 2
fi

# Check expiration
NOW=$(date +%s)
if [[ "$EXP_UNIX" -le "$NOW" ]]; then
  EXPIRED_AGO=$((NOW - EXP_UNIX))
  echo "viberunner: HR signal expired \${EXPIRED_AGO}s ago — tools locked" >&2
  exit 2
fi

# Build canonical payload for signature verification (alphabetical keys)
CANONICAL=$(echo "$PAYLOAD" | jq -cS '{bpm,exp_unix,hr_ok,nonce,session_id,threshold_bpm,user_key,v}')

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

# Create PEM formatted Ed25519 public key
# OID prefix for Ed25519: 302a300506032b6570032100
{
  echo "-----BEGIN PUBLIC KEY-----"
  (echo -n "302a300506032b6570032100"; cat "$PUB_KEY_BIN" | xxd -p -c 32) | xxd -r -p | base64
  echo "-----END PUBLIC KEY-----"
} > "$PUB_KEY_PEM"

# Write message to file
echo -n "$CANONICAL" > "$MSG_FILE"

# Verify Ed25519 signature
if ! openssl pkeyutl -verify -pubin -inkey "$PUB_KEY_PEM" -sigfile "$SIG_BIN" -in "$MSG_FILE" -rawin 2>/dev/null; then
  echo "viberunner: invalid signature — tools locked" >&2
  exit 2
fi

# Check hr_ok flag
if [[ "$HR_OK" != "true" ]]; then
  echo "viberunner: HR $BPM below threshold $THRESHOLD_BPM — tools locked" >&2
  exit 2
fi

# All checks passed - output session info for commit tagging
# Claude can parse this to extract session_id for [vr:SESSION_ID] tags
echo "viberunner: HR $BPM ✓ — session_id=$SESSION_ID"
exit 0
`;

  // CLAUDE.md - Instructions for Claude
  const claudeMd = `# viberunner HR-Gated Repository

This repository is protected by viberunner. Claude Code tool calls (edit, write, bash, etc.) are gated by the user's live heart rate.

## How it works

- You can **chat anytime** without restrictions
- **Tool calls are blocked** unless the user's heart rate is above their configured threshold
- When tools are locked, you'll see: \`viberunner: HR below threshold — tools locked\`

## When tools are locked

Switch to **planning and review mode**:
- Discuss architecture and design decisions
- Review code and suggest improvements
- Plan implementation steps
- Answer questions about the codebase
- **Don't spam tool calls** — wait for the user to get their HR up!

## Commit Tagging

When making commits in this repository, **always include a viberunner session tag** in your commit message. This allows the user to see which commits were made during each workout session.

**Format:** Add \`[vr:SESSION_ID]\` at the end of your commit message, where \`SESSION_ID\` is from the current HR signal.

Example:
\`\`\`
feat: add user authentication flow [vr:abc123-def456]
\`\`\`

The session ID is available in the HR signal payload. If you can't determine the session ID, omit the tag — don't make one up.

## Configuration

- User key: \`${userKey}\`
- Signal ref: \`${signalRef}\`
- Public key version: 1

## How to disable temporarily

To temporarily disable HR gating:
1. Rename \`.claude/settings.json\` to \`.claude/settings.json.disabled\`
2. Tool calls will work normally
3. Rename back when ready to re-enable
`;

  return [
    { path: 'viberunner.config.json', content: JSON.stringify(configContent, null, 2) },
    { path: '.claude/settings.json', content: JSON.stringify(claudeSettings, null, 2) },
    { path: 'scripts/viberunner-hr-check', content: hrCheckScript },
    { path: 'CLAUDE.md', content: claudeMd },
  ];
}

// List gate repos
gateRepos.get('/', async (c) => {
  const userId = c.get('userId');

  const repos = await prisma.gateRepo.findMany({
    where: { userId },
    orderBy: { createdAt: 'desc' },
  });

  const response: GateRepoResponse[] = repos.map((repo) => ({
    id: repo.id,
    owner: repo.owner,
    name: repo.name,
    user_key: repo.userKey,
    signal_ref: repo.signalRef,
    active: repo.active,
    github_app_installed: !!repo.githubAppInstallationId,
    created_at: repo.createdAt.toISOString(),
  }));

  return c.json({ repos: response });
});

// Create a new gate repo
gateRepos.post('/', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json<CreateGateRepoRequest>();

  if (!body.name || body.name.length < 1) {
    return c.json({ error: 'Repository name is required' }, 400);
  }

  // Get GitHub credentials
  const [githubAccount, githubToken] = await Promise.all([
    prisma.githubAccount.findUnique({ where: { userId } }),
    prisma.githubToken.findUnique({ where: { userId } }),
  ]);

  if (!githubAccount || !githubToken) {
    return c.json({ error: 'GitHub not connected. Please connect GitHub first.' }, 400);
  }

  const accessToken = decrypt(githubToken.encryptedAccessToken);
  const octokit = createUserOctokit(accessToken);
  const userKey = githubAccount.username; // Use GitHub username as user_key
  const signalRef = buildSignalRef(userKey);

  try {
    let repoInfo: { owner: string; name: string; html_url: string };

    // Try template first, fall back to empty repo
    try {
      repoInfo = await createRepoFromTemplate(
        octokit,
        config.templateRepoOwner,
        config.templateRepoName,
        githubAccount.username,
        body.name,
        body.description || 'viberunner HR-gated repository',
        body.private ?? true
      );
    } catch {
      // Template doesn't exist, create empty repo
      repoInfo = await createEmptyRepo(
        octokit,
        body.name,
        body.description || 'viberunner HR-gated repository',
        body.private ?? true
      );

      // Commit bootstrap files
      const files = generateBootstrapFiles(userKey, config.signerPublicKey);
      await commitBootstrapFiles(
        octokit,
        repoInfo.owner,
        repoInfo.name,
        files,
        'Initialize viberunner HR gating'
      );
    }

    // Store gate repo record
    const gateRepo = await prisma.gateRepo.create({
      data: {
        userId,
        owner: repoInfo.owner,
        name: repoInfo.name,
        userKey,
        signalRef,
        active: true,
      },
    });

    const response: CreateGateRepoResponse = {
      id: gateRepo.id,
      owner: repoInfo.owner,
      name: repoInfo.name,
      user_key: userKey,
      signal_ref: signalRef,
      html_url: repoInfo.html_url,
      needs_app_install: true, // User needs to install GitHub App
    };

    return c.json(response, 201);
  } catch (error) {
    console.error('Create gate repo error:', error);
    return c.json({
      error: error instanceof Error ? error.message : 'Failed to create repository',
    }, 500);
  }
});

// Get single gate repo
gateRepos.get('/:id', async (c) => {
  const userId = c.get('userId');
  const id = c.req.param('id');

  const repo = await prisma.gateRepo.findFirst({
    where: { id, userId },
  });

  if (!repo) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const response: GateRepoResponse = {
    id: repo.id,
    owner: repo.owner,
    name: repo.name,
    user_key: repo.userKey,
    signal_ref: repo.signalRef,
    active: repo.active,
    github_app_installed: !!repo.githubAppInstallationId,
    created_at: repo.createdAt.toISOString(),
  };

  return c.json(response);
});

// Update gate repo (activate/deactivate)
gateRepos.patch('/:id', async (c) => {
  const userId = c.get('userId');
  const id = c.req.param('id');
  const body = await c.req.json<{ active?: boolean }>();

  const repo = await prisma.gateRepo.findFirst({
    where: { id, userId },
  });

  if (!repo) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const updated = await prisma.gateRepo.update({
    where: { id },
    data: {
      active: body.active ?? repo.active,
    },
  });

  return c.json({
    id: updated.id,
    active: updated.active,
    updated_at: updated.updatedAt.toISOString(),
  });
});

// Delete gate repo record (doesn't delete GitHub repo)
gateRepos.delete('/:id', async (c) => {
  const userId = c.get('userId');
  const id = c.req.param('id');

  const repo = await prisma.gateRepo.findFirst({
    where: { id, userId },
  });

  if (!repo) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  await prisma.gateRepo.delete({ where: { id } });

  return c.json({ deleted: true });
});

// GitHub App installation webhook handler
gateRepos.post('/webhook/installation', async (c) => {
  // In production, verify webhook signature
  const payload = await c.req.json<{
    action: string;
    installation: {
      id: number;
      account: { login: string };
    };
    repositories?: Array<{
      id: number;
      name: string;
      full_name: string;
    }>;
  }>();

  if (payload.action === 'created' || payload.action === 'added') {
    const installationId = payload.installation.id;
    const owner = payload.installation.account.login;

    // Update gate repos with this installation
    if (payload.repositories) {
      for (const repo of payload.repositories) {
        await prisma.gateRepo.updateMany({
          where: {
            owner,
            name: repo.name,
          },
          data: {
            githubAppInstallationId: installationId,
          },
        });
      }
    }
  } else if (payload.action === 'removed' || payload.action === 'deleted') {
    // Clear installation ID from affected repos
    await prisma.gateRepo.updateMany({
      where: {
        githubAppInstallationId: payload.installation.id,
      },
      data: {
        githubAppInstallationId: null,
      },
    });
  }

  return c.json({ received: true });
});

// Get GitHub App installation URL
gateRepos.get('/:id/install-url', async (c) => {
  const userId = c.get('userId');
  const id = c.req.param('id');

  const repo = await prisma.gateRepo.findFirst({
    where: { id, userId },
  });

  if (!repo) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  // GitHub App installation URL with repo pre-selected
  const installUrl = `https://github.com/apps/viberunner/installations/new/permissions?target_id=${repo.owner}&suggested_target_id=${repo.owner}&repository_ids[]=${repo.name}`;

  return c.json({
    install_url: installUrl,
    owner: repo.owner,
    name: repo.name,
  });
});

export { gateRepos };
