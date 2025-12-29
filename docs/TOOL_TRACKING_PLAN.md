# Tool Attempt Tracking Implementation Plan

Track the number of tool calls Claude Code attempts during a workout session, using GitHub as the only external API from the hook.

## Implementation Status

| Component | Status | File(s) |
|-----------|--------|---------|
| Prisma ToolAttempt model | ✅ Done | `packages/db/prisma/schema.prisma` |
| HR check script logging | ✅ Done | `packages/repo-bootstrap/src/index.ts` |
| Stats sync script | ✅ Done | `packages/repo-bootstrap/src/index.ts` |
| CLAUDE.md sync instructions | ✅ Done | `packages/repo-bootstrap/src/index.ts` |
| Shared types | ✅ Done | `packages/shared/src/types.ts` |
| API: Fetch stats on stop | ✅ Done | `services/api/src/routes/workout.ts` |
| API: Session responses | ✅ Done | `services/api/src/routes/workout.ts` |
| Database migration | ⏳ Pending | Run `npx prisma migrate dev` |
| iOS models & UI | ⏳ Pending | Swift files |

## Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           TOOL TRACKING FLOW                              │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│   PreToolUse Hook (on each tool call)                                     │
│   ├─ 1. git fetch HR signal (existing)                                    │
│   ├─ 2. Verify signature, check hr_ok (existing)                          │
│   └─ 3. Append to .git/vibeworkout-stats.jsonl (NEW - local, ~1ms)        │
│                                                                           │
│   User: git push (pushing their code)                                     │
│   └─ post-push hook fires automatically (NEW)                             │
│       ├─ 1. Read .git/vibeworkout-stats.jsonl                             │
│       ├─ 2. Push orphan commit to refs/vibeworkout/stats/{user_key}       │
│       └─ 3. Clear local log                                               │
│                                                                           │
│   API: On workout stop (existing endpoint)                                │
│   └─ Fetch refs/vibeworkout/stats/{user_key}                              │
│       ├─ Filter by timestamp window (same as commits)                     │
│       └─ Save to ToolAttempt table                                        │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Hook only hits GitHub | Yes | Security - no vibeworkout API calls from user's machine |
| Stats storage | Orphan commits on hidden ref | Invisible to git history, same pattern as HR signal |
| Sync trigger | post-push hook | Piggybacks on natural user workflow, no daemon needed |
| Matching to workouts | Timestamp + session_id | Handles clock skew, multiple sessions |

---

## Phase 1: Local Logging in PreToolUse Hook

### 1.1 Update `scripts/vibeworkout-hr-check`

After the existing HR verification, append tool attempt to local log:

```bash
# ... existing HR check logic ...

# NEW: Log tool attempt locally
LOG_FILE="$REPO_ROOT/.git/vibeworkout-stats.jsonl"
TOOL_NAME="${TOOL_NAME:-unknown}"  # Claude Code sets this env var
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id')

# Determine if allowed (based on exit code we're about to return)
if [[ "$HR_OK" == "true" ]]; then
  ALLOWED="true"
  EXIT_CODE=0
else
  ALLOWED="false"
  EXIT_CODE=2
fi

# Append to log (atomic write)
echo "{\"ts\":\"$TIMESTAMP\",\"tool\":\"$TOOL_NAME\",\"allowed\":$ALLOWED,\"session_id\":\"$SESSION_ID\",\"bpm\":$BPM}" >> "$LOG_FILE"

exit $EXIT_CODE
```

### 1.2 Update `repo-bootstrap` package

Modify `generateHrCheckScript()` in `packages/repo-bootstrap/src/index.ts` to include the logging logic.

---

## Phase 2: post-push Hook for Syncing Stats

### 2.1 Create `scripts/vibeworkout-post-push`

New script that runs after `git push`:

```bash
#!/usr/bin/env bash
# Sync accumulated tool stats to GitHub

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
CONFIG_FILE="$REPO_ROOT/vibeworkout.config.json"
LOG_FILE="$REPO_ROOT/.git/vibeworkout-stats.jsonl"

# Exit early if no stats to sync
if [[ ! -f "$LOG_FILE" ]] || [[ ! -s "$LOG_FILE" ]]; then
  exit 0
fi

# Read config
USER_KEY=$(jq -r '.user_key' "$CONFIG_FILE")
STATS_REF="refs/vibeworkout/stats/$USER_KEY"

# Create blob from log file
BLOB_SHA=$(git hash-object -w "$LOG_FILE")

# Create tree with single file
TREE_SHA=$(echo -e "100644 blob $BLOB_SHA\ttool-stats.jsonl" | git mktree)

# Create orphan commit (no parents)
COMMIT_SHA=$(git commit-tree "$TREE_SHA" -m "Tool stats update")

# Push to stats ref
git push origin "$COMMIT_SHA:$STATS_REF" --force --quiet

# Clear local log on success
> "$LOG_FILE"
```

### 2.2 Add to bootstrap files

Update `generateBootstrapFiles()` in `packages/repo-bootstrap/src/index.ts`:

```typescript
{
  path: 'scripts/vibeworkout-post-push',
  content: generatePostPushScript(),
  executable: true,
},
{
  path: '.git/hooks/post-push',  // Git hook (symlink or direct)
  content: '#!/bin/sh\n../scripts/vibeworkout-post-push',
  executable: true,
}
```

**Note:** Git doesn't have a native `post-push` hook. Options:
- Use `post-receive` (only works on server-side)
- Use a wrapper script that users call instead of `git push`
- Use `pre-push` (runs before push, not ideal)
- Document manual sync: `./scripts/vibeworkout-post-push`

**Recommended:** Add to CLAUDE.md instructions for Claude to run the sync script after pushing.

---

## Phase 3: Database Schema

### 3.1 Add ToolAttempt model

In `packages/db/prisma/schema.prisma`:

```prisma
model ToolAttempt {
  id        String   @id @default(uuid())
  sessionId String   @map("session_id")
  toolName  String   @map("tool_name")
  allowed   Boolean
  bpm       Int?
  timestamp DateTime @map("timestamp")
  createdAt DateTime @default(now()) @map("created_at")

  session WorkoutSession @relation(fields: [sessionId], references: [id], onDelete: Cascade)

  @@index([sessionId])
  @@index([sessionId, timestamp])
  @@map("tool_attempts")
  @@schema("public")
}
```

### 3.2 Update WorkoutSession model

Add relation:

```prisma
model WorkoutSession {
  // ... existing fields ...
  toolAttempts ToolAttempt[]
}
```

### 3.3 Create migration

```bash
cd packages/db
npx prisma migrate dev --name add_tool_attempts
```

---

## Phase 4: API - Fetch Stats on Workout Stop

### 4.1 Update `POST /workout/stop`

In `services/api/src/routes/workout.ts`, after fetching commits:

```typescript
// Fetch tool stats from GitHub
for (const repo of activeRepos) {
  if (!repo.githubAppInstallationId) continue;

  try {
    const octokit = await createInstallationOctokit(repo.githubAppInstallationId);
    const userKey = repo.userKey;
    const statsRef = `refs/vibeworkout/stats/${userKey}`;

    // Fetch the stats ref
    const { data: refData } = await octokit.rest.git.getRef({
      owner: repo.owner,
      repo: repo.name,
      ref: statsRef.replace('refs/', ''),
    }).catch(() => ({ data: null }));

    if (!refData) continue;

    // Get the blob content
    const { data: commit } = await octokit.rest.git.getCommit({
      owner: repo.owner,
      repo: repo.name,
      commit_sha: refData.object.sha,
    });

    const { data: tree } = await octokit.rest.git.getTree({
      owner: repo.owner,
      repo: repo.name,
      tree_sha: commit.tree.sha,
    });

    const statsFile = tree.tree.find(f => f.path === 'tool-stats.jsonl');
    if (!statsFile?.sha) continue;

    const { data: blob } = await octokit.rest.git.getBlob({
      owner: repo.owner,
      repo: repo.name,
      file_sha: statsFile.sha,
    });

    const content = Buffer.from(blob.content, 'base64').toString('utf-8');
    const lines = content.trim().split('\n').filter(Boolean);

    for (const line of lines) {
      const entry = JSON.parse(line);
      const timestamp = new Date(entry.ts);

      // Filter to this session's time window
      if (timestamp < windowStart || timestamp > windowEnd) continue;

      // Upsert to avoid duplicates
      await prisma.toolAttempt.upsert({
        where: {
          // Need a unique constraint - session + timestamp + tool
          sessionId_timestamp_toolName: {
            sessionId: session.id,
            timestamp,
            toolName: entry.tool,
          },
        },
        create: {
          sessionId: session.id,
          toolName: entry.tool,
          allowed: entry.allowed,
          bpm: entry.bpm,
          timestamp,
        },
        update: {},
      });
    }
  } catch (error) {
    console.error(`Failed to fetch tool stats for ${repo.owner}/${repo.name}:`, error);
  }
}
```

---

## Phase 5: API Responses

### 5.1 Update session detail endpoint

In `GET /workout/sessions/:sessionId`, add tool stats:

```typescript
const toolAttempts = await prisma.toolAttempt.findMany({
  where: { sessionId },
  orderBy: { timestamp: 'asc' },
});

// Aggregate stats
const toolStats = {
  total_attempts: toolAttempts.length,
  allowed: toolAttempts.filter(t => t.allowed).length,
  blocked: toolAttempts.filter(t => !t.allowed).length,
  by_tool: {} as Record<string, { allowed: number; blocked: number }>,
};

for (const attempt of toolAttempts) {
  if (!toolStats.by_tool[attempt.toolName]) {
    toolStats.by_tool[attempt.toolName] = { allowed: 0, blocked: 0 };
  }
  if (attempt.allowed) {
    toolStats.by_tool[attempt.toolName].allowed++;
  } else {
    toolStats.by_tool[attempt.toolName].blocked++;
  }
}

return c.json({
  // ... existing response ...
  tool_stats: toolStats,
});
```

### 5.2 Update WorkoutSummary model (optional)

Add aggregated tool stats to the summary for quick access:

```prisma
model WorkoutSummary {
  // ... existing fields ...
  toolAttemptsTotal   Int @default(0) @map("tool_attempts_total")
  toolAttemptsAllowed Int @default(0) @map("tool_attempts_allowed")
  toolAttemptsBlocked Int @default(0) @map("tool_attempts_blocked")
}
```

---

## Phase 6: iOS App Updates

### 6.1 Update PostWorkoutSummaryView

Display tool attempt stats alongside commits/PRs:

```swift
// Tool Stats Section
if let toolStats = session.toolStats {
    Section("Tool Usage") {
        HStack {
            Label("\(toolStats.total) attempts", systemImage: "hammer")
            Spacer()
            Text("\(toolStats.allowed) allowed")
                .foregroundColor(.green)
            Text("\(toolStats.blocked) blocked")
                .foregroundColor(.red)
        }
    }
}
```

### 6.2 Update Models.swift

Add tool stats to session model.

---

## File Changes Summary

| File | Change |
|------|--------|
| `packages/repo-bootstrap/src/index.ts` | Update HR check script, add post-push script |
| `packages/db/prisma/schema.prisma` | Add ToolAttempt model |
| `services/api/src/routes/workout.ts` | Fetch stats on stop, include in responses |
| `packages/shared/src/types.ts` | Add tool stats types |
| `apps/ios/.../PostWorkoutSummaryView.swift` | Display tool stats |
| `apps/ios/.../Models.swift` | Add tool stats to models |

---

## Open Questions

1. **Git post-push hook**: Git doesn't have a native post-push. Options:
   - Wrapper script users call instead of `git push`
   - Instruct Claude to run sync after pushing
   - Use pre-push (runs before, could log "pending push")

2. **Stats ref cleanup**: Should old stats be cleared after fetch? Or keep for debugging?

3. **Offline handling**: What if user pushes while offline? Stats accumulate locally until next successful push.

4. **Rate limits**: Many tool attempts = large JSONL file. Consider compressing or rotating.

---

## Implementation Order

1. **Database**: Add ToolAttempt model and migration
2. **Bootstrap**: Update HR check script to log locally
3. **Bootstrap**: Add post-push sync script
4. **API**: Fetch stats on workout stop
5. **API**: Include stats in session responses
6. **iOS**: Display stats in UI
7. **Docs**: Update CLAUDE.md with sync instructions
