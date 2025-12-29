# Tool Outcome Tracking Plan

Enhance tool tracking to capture both **attempts** (PreToolUse) and **outcomes** (PostToolUse), matched by `tool_use_id`.

## Goal

Track the complete lifecycle of each tool call:
- Was it allowed/blocked by HR gating?
- If allowed, did it succeed?
- What was the block reason if blocked?

## Architecture

```
PreToolUse Hook                         PostToolUse Hook
     │                                        │
     ▼                                        ▼
┌─────────────────────┐              ┌─────────────────────┐
│ Log attempt:        │              │ Log outcome:        │
│ - tool_use_id       │              │ - tool_use_id       │
│ - tool name         │              │ - succeeded: true   │
│ - allowed/blocked   │              │ - tool_response     │
│ - block_reason      │              └─────────────────────┘
│ - bpm, session_id   │
└─────────────────────┘
              │                                │
              └────────────┬───────────────────┘
                           ▼
              .git/vibeworkout-stats.jsonl
                           │
                           ▼ (sync script)
              refs/vibeworkout/stats/{user_key}
                           │
                           ▼ (API on workout stop)
              ToolAttempt table (matched by tool_use_id)
```

## Data Structures

### PreToolUse Log Entry
```json
{
  "ts": "2025-12-27T16:45:01Z",
  "type": "attempt",
  "tool_use_id": "toolu_01ABC123",
  "tool": "Edit",
  "allowed": false,
  "reason": "hr_below_threshold",
  "session_id": "abc-123",
  "bpm": 85
}
```

### PostToolUse Log Entry
```json
{
  "ts": "2025-12-27T16:45:02Z",
  "type": "outcome",
  "tool_use_id": "toolu_01ABC123",
  "tool": "Edit",
  "succeeded": true
}
```

### Block Reasons
| Reason | Description |
|--------|-------------|
| `hr_below_threshold` | BPM below user's threshold |
| `signal_expired` | HR signal TTL exceeded |
| `signal_fetch_failed` | Could not fetch ref from GitHub |
| `invalid_signature` | Signature verification failed |
| `config_missing` | vibeworkout.config.json not found |

## Implementation Steps

### 1. Update Prisma Schema
Add `reason` and `succeeded` fields to ToolAttempt:
```prisma
model ToolAttempt {
  id        String   @id @default(uuid())
  sessionId String   @map("session_id")
  toolName  String   @map("tool_name")
  toolUseId String?  @map("tool_use_id")  // NEW
  allowed   Boolean
  reason    String?  // NEW: block reason
  succeeded Boolean? // NEW: null if blocked, true/false if allowed
  bpm       Int?
  timestamp DateTime
  createdAt DateTime @default(now()) @map("created_at")

  session WorkoutSession @relation(fields: [sessionId], references: [id], onDelete: Cascade)

  @@unique([sessionId, timestamp, toolName])
  @@index([sessionId])
  @@index([sessionId, timestamp])
  @@index([toolUseId])  // NEW: for matching
  @@map("tool_attempts")
  @@schema("public")
}
```

### 2. Update Shared Types
```typescript
export interface ToolAttemptEntry {
  ts: string;
  type: 'attempt' | 'outcome';
  tool_use_id?: string;
  tool: string;
  allowed?: boolean;
  reason?: string;
  succeeded?: boolean;
  session_id?: string;
  bpm?: number;
}
```

### 3. Update PreToolUse Script
- Read `tool_use_id` from stdin JSON (Claude Code provides this)
- Track specific block reason based on which check failed
- Log with `type: "attempt"`

### 4. Create PostToolUse Script
- Read `tool_use_id` and `tool_name` from stdin JSON
- Log with `type: "outcome"` and `succeeded: true`
- Note: PostToolUse only fires on success

### 5. Update Claude Settings Generator
Add PostToolUse hook configuration:
```json
{
  "hooks": {
    "PreToolUse": [...],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": ["./scripts/vibeworkout-post-tool"]
      }
    ]
  }
}
```

### 6. Update API Parser
When processing stats on workout stop:
- Parse both `attempt` and `outcome` entries
- Match by `tool_use_id`
- Create ToolAttempt records with full data

## File Changes

| File | Change |
|------|--------|
| `packages/db/prisma/schema.prisma` | Add `toolUseId`, `reason`, `succeeded` fields |
| `packages/shared/src/types.ts` | Update `ToolAttemptEntry` type |
| `packages/repo-bootstrap/src/index.ts` | Update PreToolUse, add PostToolUse, update settings |
| `services/api/src/routes/workout.ts` | Update stats parser to handle both entry types |

## Execution Order

1. ✅ Update Prisma schema
2. ✅ Update shared types
3. ✅ Update PreToolUse script with reasons + stdin parsing
4. ✅ Add PostToolUse script
5. ✅ Update Claude settings generator
6. ✅ Update API stats parser
7. ✅ Commit and push
