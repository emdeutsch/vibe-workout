/**
 * Heartbeat and run session routes
 */

import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { profileDb, deviceDb, repoDb, sessionDb } from '../db.js';
import { createRulesetManager } from '@viberunner/github';

const router = Router();

/**
 * Heartbeat endpoint - called by iOS app every few seconds during a run
 */
const heartbeatSchema = z.object({
  runState: z.enum(['NOT_RUNNING', 'RUNNING_UNLOCKED', 'RUNNING_LOCKED']),
  currentPace: z.number().optional(),
  distanceMeters: z.number().optional(),
  caloriesBurned: z.number().optional(),
  route: z.array(z.object({
    lat: z.number(),
    lng: z.number(),
    timestamp: z.number(),
    pace: z.number().optional(),
  })).optional(),
  location: z
    .object({
      latitude: z.number(),
      longitude: z.number(),
    })
    .optional(),
});

router.post('/', requireAuth, async (req, res) => {
  try {
    const body = heartbeatSchema.parse(req.body);
    const userId = req.user!.id;
    const deviceId = req.deviceId;

    if (!deviceId) {
      res.status(400).json({ error: 'Device ID required (set X-Device-ID header)' });
      return;
    }

    // Update device heartbeat
    await deviceDb.updateHeartbeat(deviceId, body.runState);

    // Get user's pace threshold
    const profile = await profileDb.findById(userId);
    const paceThreshold = profile?.paceThresholdSeconds ?? 600;

    // Update or create session
    let session = await sessionDb.findActiveByDeviceId(deviceId);
    const isRunning = body.runState !== 'NOT_RUNNING';

    if (isRunning && !session) {
      // Start new session
      session = await sessionDb.create({
        userId,
        deviceId,
        startedAt: new Date(),
        paceThresholdSeconds: paceThreshold,
        currentState: body.runState,
      });
    } else if (session) {
      if (!isRunning) {
        // End session with final stats
        const endedAt = new Date();
        const durationSeconds = Math.floor(
          (endedAt.getTime() - session.startedAt.getTime()) / 1000
        );

        await sessionDb.endSession(session.id, {
          endedAt,
          durationSeconds,
          distanceMeters: body.distanceMeters,
          averagePaceSeconds: body.currentPace,
          caloriesBurned: body.caloriesBurned,
          route: body.route,
        });
      } else {
        // Update session
        await sessionDb.update(session.id, {
          lastHeartbeat: new Date(),
          currentState: body.runState,
          averagePaceSeconds: body.currentPace,
          distanceMeters: body.distanceMeters,
        });
      }
    }

    // Determine if GitHub writes should be enabled
    const githubWritesEnabled = body.runState === 'RUNNING_UNLOCKED';

    // Update GitHub rulesets based on state
    await updateGitHubRulesets(userId, githubWritesEnabled);

    res.json({
      success: true,
      serverTime: Date.now(),
      stateAcknowledged: body.runState,
      githubWritesEnabled,
      paceThresholdSeconds: paceThreshold,
    });
  } catch (error) {
    if (error instanceof z.ZodError) {
      res.status(400).json({ error: 'Invalid request', details: error.errors });
      return;
    }
    console.error('Heartbeat error:', error);
    res.status(500).json({ error: 'Heartbeat failed' });
  }
});

/**
 * Get current session status
 */
router.get('/status', requireAuth, async (req, res) => {
  try {
    const deviceId = req.deviceId;

    if (!deviceId) {
      res.status(400).json({ error: 'Device ID required' });
      return;
    }

    const device = await deviceDb.findById(deviceId);
    const session = await sessionDb.findActiveByDeviceId(deviceId);
    const profile = await profileDb.findById(req.user!.id);

    res.json({
      device: device
        ? {
            id: device.id,
            lastHeartbeat: device.lastHeartbeat,
            lastRunState: device.lastRunState,
          }
        : null,
      session: session
        ? {
            id: session.id,
            startedAt: session.startedAt,
            currentState: session.currentState,
            averagePace: session.averagePaceSeconds,
            distanceMeters: session.distanceMeters,
          }
        : null,
      githubWritesEnabled: device?.lastRunState === 'RUNNING_UNLOCKED',
      paceThresholdSeconds: profile?.paceThresholdSeconds ?? 600,
    });
  } catch (error) {
    console.error('Error getting status:', error);
    res.status(500).json({ error: 'Failed to get status' });
  }
});

/**
 * Start a run session
 */
router.post('/start', requireAuth, async (req, res) => {
  try {
    const userId = req.user!.id;
    const deviceId = req.deviceId;

    if (!deviceId) {
      res.status(400).json({ error: 'Device ID required' });
      return;
    }

    // Check for existing session
    const existingSession = await sessionDb.findActiveByDeviceId(deviceId);
    if (existingSession) {
      res.status(409).json({ error: 'Session already active' });
      return;
    }

    // Get user's pace threshold
    const profile = await profileDb.findById(userId);
    const paceThreshold = profile?.paceThresholdSeconds ?? 600;

    const session = await sessionDb.create({
      userId,
      deviceId,
      startedAt: new Date(),
      paceThresholdSeconds: paceThreshold,
      currentState: 'RUNNING_LOCKED',
    });

    await deviceDb.updateHeartbeat(deviceId, 'RUNNING_LOCKED');

    // Block writes on session start
    await updateGitHubRulesets(userId, false);

    res.status(201).json({
      session: {
        id: session.id,
        startedAt: session.startedAt,
        currentState: session.currentState,
        paceThresholdSeconds: paceThreshold,
      },
    });
  } catch (error) {
    console.error('Error starting session:', error);
    res.status(500).json({ error: 'Failed to start session' });
  }
});

/**
 * End a run session
 */
const endSessionSchema = z.object({
  distanceMeters: z.number().optional(),
  averagePaceSeconds: z.number().optional(),
  caloriesBurned: z.number().optional(),
  route: z.array(z.object({
    lat: z.number(),
    lng: z.number(),
    timestamp: z.number(),
    pace: z.number().optional(),
  })).optional(),
  healthKitWorkoutId: z.string().optional(),
});

router.post('/end', requireAuth, async (req, res) => {
  try {
    const userId = req.user!.id;
    const deviceId = req.deviceId;
    const body = endSessionSchema.parse(req.body);

    if (!deviceId) {
      res.status(400).json({ error: 'Device ID required' });
      return;
    }

    const session = await sessionDb.findActiveByDeviceId(deviceId);
    if (!session) {
      res.status(404).json({ error: 'No active session' });
      return;
    }

    const endedAt = new Date();
    const durationSeconds = Math.floor(
      (endedAt.getTime() - session.startedAt.getTime()) / 1000
    );

    const updatedSession = await sessionDb.endSession(session.id, {
      endedAt,
      durationSeconds,
      distanceMeters: body.distanceMeters,
      averagePaceSeconds: body.averagePaceSeconds,
      caloriesBurned: body.caloriesBurned,
      route: body.route,
    });

    // Update healthkit workout ID if provided
    if (body.healthKitWorkoutId && updatedSession) {
      await sessionDb.update(session.id, {
        healthKitWorkoutId: body.healthKitWorkoutId,
      });
    }

    await deviceDb.updateHeartbeat(deviceId, 'NOT_RUNNING');

    // Block writes when session ends
    await updateGitHubRulesets(userId, false);

    res.json({
      session: {
        id: session.id,
        startedAt: session.startedAt,
        endedAt,
        durationSeconds,
        distanceMeters: body.distanceMeters,
        averagePaceSeconds: body.averagePaceSeconds,
      },
    });
  } catch (error) {
    if (error instanceof z.ZodError) {
      res.status(400).json({ error: 'Invalid request', details: error.errors });
      return;
    }
    console.error('Error ending session:', error);
    res.status(500).json({ error: 'Failed to end session' });
  }
});

/**
 * Update GitHub rulesets based on current state
 */
async function updateGitHubRulesets(
  userId: string,
  allowWrites: boolean
): Promise<void> {
  const profile = await profileDb.findById(userId);
  if (!profile?.githubAccessToken) return;

  const repos = await repoDb.findByUserId(userId);
  if (repos.length === 0) return;

  const manager = createRulesetManager(profile.githubAccessToken);

  // Update all gated repositories
  await Promise.all(
    repos.map(async (repo) => {
      if (!repo.rulesetId || !repo.gatingEnabled) return;

      try {
        if (allowWrites) {
          await manager.allowWrites(repo.owner, repo.name, repo.rulesetId);
        } else {
          await manager.blockWrites(repo.owner, repo.name, repo.rulesetId);
        }
      } catch (error) {
        console.error(`Failed to update ruleset for ${repo.fullName}:`, error);
      }
    })
  );
}

export default router;
