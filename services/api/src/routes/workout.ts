/**
 * Workout and HR routes - session management and HR ingestion
 */

import { Hono } from 'hono';
import { prisma } from '@viberunner/db';
import { authMiddleware } from '../middleware/auth.js';
import { config } from '../config.js';
import type {
  StartWorkoutRequest,
  StartWorkoutResponse,
  IngestHrSampleRequest,
  HrStatusResponse,
} from '@viberunner/shared';

const workout = new Hono();

// Apply auth to all routes
workout.use('*', authMiddleware);

// Start a workout session
workout.post('/start', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json<StartWorkoutRequest>().catch(() => ({}));

  // End any existing active sessions
  await prisma.workoutSession.updateMany({
    where: { userId, active: true },
    data: { active: false, endedAt: new Date() },
  });

  // Create new session
  const session = await prisma.workoutSession.create({
    data: {
      userId,
      source: body.source || 'watch',
      active: true,
    },
  });

  const response: StartWorkoutResponse = {
    session_id: session.id,
    started_at: session.startedAt.toISOString(),
  };

  return c.json(response, 201);
});

// Stop the active workout session
workout.post('/stop', async (c) => {
  const userId = c.get('userId');

  const result = await prisma.workoutSession.updateMany({
    where: { userId, active: true },
    data: { active: false, endedAt: new Date() },
  });

  if (result.count === 0) {
    return c.json({ error: 'No active workout session' }, 404);
  }

  // Expire HR status
  await prisma.hrStatus.updateMany({
    where: { userId },
    data: {
      hrOk: false,
      expiresAt: new Date(),
    },
  });

  return c.json({ stopped: true, sessions_ended: result.count });
});

// Get active workout session
workout.get('/active', async (c) => {
  const userId = c.get('userId');

  const session = await prisma.workoutSession.findFirst({
    where: { userId, active: true },
    orderBy: { startedAt: 'desc' },
  });

  if (!session) {
    return c.json({ active: false });
  }

  return c.json({
    active: true,
    session_id: session.id,
    started_at: session.startedAt.toISOString(),
    source: session.source,
  });
});

// Ingest HR sample from device
workout.post('/hr', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json<IngestHrSampleRequest>();

  // Validate BPM
  if (typeof body.bpm !== 'number' || body.bpm < 30 || body.bpm > 250) {
    return c.json({ error: 'bpm must be between 30 and 250' }, 400);
  }

  // Verify session exists and belongs to user
  const session = await prisma.workoutSession.findFirst({
    where: {
      id: body.session_id,
      userId,
      active: true,
    },
  });

  if (!session) {
    return c.json({ error: 'Invalid or inactive session' }, 404);
  }

  // Get user's threshold
  const profile = await prisma.profile.findUnique({
    where: { userId },
  });

  const threshold = profile?.hrThresholdBpm ?? config.defaultHrThreshold;
  const ts = body.ts ? new Date(body.ts) : new Date();
  const expiresAt = new Date(Date.now() + config.hrTtlSeconds * 1000);
  const hrOk = body.bpm >= threshold;

  // Create HR sample
  await prisma.hrSample.create({
    data: {
      userId,
      sessionId: body.session_id,
      bpm: body.bpm,
      ts,
      source: body.source || session.source,
    },
  });

  // Update HR status (upsert)
  await prisma.hrStatus.upsert({
    where: { userId },
    update: {
      bpm: body.bpm,
      thresholdBpm: threshold,
      hrOk,
      expiresAt,
    },
    create: {
      userId,
      bpm: body.bpm,
      thresholdBpm: threshold,
      hrOk,
      expiresAt,
    },
  });

  const response: HrStatusResponse = {
    bpm: body.bpm,
    threshold_bpm: threshold,
    hr_ok: hrOk,
    expires_at: expiresAt.toISOString(),
    tools_unlocked: hrOk,
  };

  return c.json(response);
});

// Get current HR status
workout.get('/status', async (c) => {
  const userId = c.get('userId');

  const status = await prisma.hrStatus.findUnique({
    where: { userId },
  });

  if (!status) {
    return c.json({
      bpm: 0,
      threshold_bpm: config.defaultHrThreshold,
      hr_ok: false,
      expires_at: new Date().toISOString(),
      tools_unlocked: false,
    } satisfies HrStatusResponse);
  }

  // Check if expired
  const isExpired = status.expiresAt <= new Date();
  const hrOk = !isExpired && status.hrOk;

  const response: HrStatusResponse = {
    bpm: status.bpm,
    threshold_bpm: status.thresholdBpm,
    hr_ok: hrOk,
    expires_at: status.expiresAt.toISOString(),
    tools_unlocked: hrOk,
  };

  return c.json(response);
});

// Get recent HR samples (legacy endpoint)
workout.get('/history', async (c) => {
  const userId = c.get('userId');
  const limit = parseInt(c.req.query('limit') || '100', 10);

  const samples = await prisma.hrSample.findMany({
    where: { userId },
    orderBy: { ts: 'desc' },
    take: Math.min(limit, 1000),
  });

  return c.json({
    samples: samples.map((s) => ({
      bpm: s.bpm,
      ts: s.ts.toISOString(),
      source: s.source,
    })),
  });
});

// Get workout session list (paginated)
workout.get('/sessions', async (c) => {
  const userId = c.get('userId');
  const limit = parseInt(c.req.query('limit') || '20', 10);
  const cursor = c.req.query('cursor');

  const sessions = await prisma.workoutSession.findMany({
    where: { userId },
    orderBy: { startedAt: 'desc' },
    take: Math.min(limit, 50) + 1, // Get one extra to check for next page
    ...(cursor && { cursor: { id: cursor }, skip: 1 }),
    include: {
      summary: true,
      _count: { select: { commits: true } },
    },
  });

  const hasMore = sessions.length > limit;
  const items = hasMore ? sessions.slice(0, -1) : sessions;
  const nextCursor = hasMore ? items[items.length - 1]?.id : undefined;

  return c.json({
    sessions: items.map((s) => ({
      id: s.id,
      started_at: s.startedAt.toISOString(),
      ended_at: s.endedAt?.toISOString() ?? null,
      active: s.active,
      source: s.source,
      summary: s.summary ? {
        duration_secs: s.summary.durationSecs,
        avg_bpm: s.summary.avgBpm,
        max_bpm: s.summary.maxBpm,
        min_bpm: s.summary.minBpm,
        time_above_threshold_secs: s.summary.timeAboveThresholdSecs,
        time_below_threshold_secs: s.summary.timeBelowThresholdSecs,
        threshold_bpm: s.summary.thresholdBpm,
        total_samples: s.summary.totalSamples,
      } : null,
      commit_count: s._count.commits,
    })),
    next_cursor: nextCursor,
    has_more: hasMore,
  });
});

// Get single workout session detail
workout.get('/sessions/:sessionId', async (c) => {
  const userId = c.get('userId');
  const sessionId = c.req.param('sessionId');

  const session = await prisma.workoutSession.findFirst({
    where: { id: sessionId, userId },
    include: {
      summary: true,
      commits: {
        orderBy: { committedAt: 'desc' },
      },
    },
  });

  if (!session) {
    return c.json({ error: 'Session not found' }, 404);
  }

  return c.json({
    id: session.id,
    started_at: session.startedAt.toISOString(),
    ended_at: session.endedAt?.toISOString() ?? null,
    active: session.active,
    source: session.source,
    summary: session.summary ? {
      duration_secs: session.summary.durationSecs,
      avg_bpm: session.summary.avgBpm,
      max_bpm: session.summary.maxBpm,
      min_bpm: session.summary.minBpm,
      time_above_threshold_secs: session.summary.timeAboveThresholdSecs,
      time_below_threshold_secs: session.summary.timeBelowThresholdSecs,
      threshold_bpm: session.summary.thresholdBpm,
      total_samples: session.summary.totalSamples,
    } : null,
    commits: session.commits.map((c) => ({
      id: c.id,
      repo_owner: c.repoOwner,
      repo_name: c.repoName,
      commit_sha: c.commitSha,
      commit_msg: c.commitMsg,
      lines_added: c.linesAdded,
      lines_removed: c.linesRemoved,
      committed_at: c.committedAt.toISOString(),
    })),
  });
});

// Get HR graph data for a session (raw samples for detailed graphs)
workout.get('/sessions/:sessionId/samples', async (c) => {
  const userId = c.get('userId');
  const sessionId = c.req.param('sessionId');

  // Verify session belongs to user
  const session = await prisma.workoutSession.findFirst({
    where: { id: sessionId, userId },
    select: { id: true },
  });

  if (!session) {
    return c.json({ error: 'Session not found' }, 404);
  }

  const samples = await prisma.hrSample.findMany({
    where: { sessionId },
    orderBy: { ts: 'asc' },
    select: { bpm: true, ts: true },
  });

  return c.json({
    samples: samples.map((s) => ({
      bpm: s.bpm,
      ts: s.ts.toISOString(),
    })),
  });
});

// Get HR buckets for a session (aggregated for faster loading)
workout.get('/sessions/:sessionId/buckets', async (c) => {
  const userId = c.get('userId');
  const sessionId = c.req.param('sessionId');

  // Verify session belongs to user
  const session = await prisma.workoutSession.findFirst({
    where: { id: sessionId, userId },
    select: { id: true },
  });

  if (!session) {
    return c.json({ error: 'Session not found' }, 404);
  }

  const buckets = await prisma.hrBucket.findMany({
    where: { sessionId },
    orderBy: { bucketStart: 'asc' },
  });

  return c.json({
    buckets: buckets.map((b) => ({
      bucket_start: b.bucketStart.toISOString(),
      bucket_end: b.bucketEnd.toISOString(),
      min_bpm: b.minBpm,
      max_bpm: b.maxBpm,
      avg_bpm: b.avgBpm,
      sample_count: b.sampleCount,
      time_above_threshold_secs: b.timeAboveThresholdSecs,
      threshold_bpm: b.thresholdBpm,
    })),
  });
});

// Link a commit to a session (called by webhook or manually)
workout.post('/sessions/:sessionId/commits', async (c) => {
  const userId = c.get('userId');
  const sessionId = c.req.param('sessionId');
  const body = await c.req.json<{
    repo_owner: string;
    repo_name: string;
    commit_sha: string;
    commit_msg: string;
    lines_added?: number;
    lines_removed?: number;
    committed_at: string;
  }>();

  // Verify session belongs to user
  const session = await prisma.workoutSession.findFirst({
    where: { id: sessionId, userId },
    select: { id: true },
  });

  if (!session) {
    return c.json({ error: 'Session not found' }, 404);
  }

  const commit = await prisma.sessionCommit.upsert({
    where: {
      sessionId_commitSha: {
        sessionId,
        commitSha: body.commit_sha,
      },
    },
    update: {
      commitMsg: body.commit_msg,
      linesAdded: body.lines_added,
      linesRemoved: body.lines_removed,
    },
    create: {
      sessionId,
      repoOwner: body.repo_owner,
      repoName: body.repo_name,
      commitSha: body.commit_sha,
      commitMsg: body.commit_msg,
      linesAdded: body.lines_added,
      linesRemoved: body.lines_removed,
      committedAt: new Date(body.committed_at),
    },
  });

  return c.json({
    id: commit.id,
    commit_sha: commit.commitSha,
  }, 201);
});

export { workout };
