/**
 * Run history and stats routes
 */

import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { sessionDb } from '../db.js';

const router = Router();

/**
 * Get run history for the authenticated user
 */
const historyQuerySchema = z.object({
  limit: z.coerce.number().min(1).max(100).optional(),
  offset: z.coerce.number().min(0).optional(),
});

router.get('/history', requireAuth, async (req, res) => {
  try {
    const query = historyQuerySchema.parse(req.query);
    const runs = await sessionDb.getHistory(req.user!.id, {
      limit: query.limit,
      offset: query.offset,
    });

    res.json({
      runs: runs.map((run) => ({
        id: run.id,
        startedAt: run.startedAt,
        endedAt: run.endedAt,
        durationSeconds: run.durationSeconds,
        distanceMeters: run.distanceMeters,
        averagePaceSeconds: run.averagePaceSeconds,
        caloriesBurned: run.caloriesBurned,
        paceThresholdSeconds: run.paceThresholdSeconds,
        route: run.route,
        healthKitWorkoutId: run.healthKitWorkoutId,
      })),
    });
  } catch (error) {
    if (error instanceof z.ZodError) {
      res.status(400).json({ error: 'Invalid query parameters', details: error.errors });
      return;
    }
    console.error('Error getting run history:', error);
    res.status(500).json({ error: 'Failed to get run history' });
  }
});

/**
 * Get aggregate stats for the authenticated user
 */
router.get('/stats', requireAuth, async (req, res) => {
  try {
    const stats = await sessionDb.getStats(req.user!.id);

    res.json({
      totalRuns: stats.totalRuns,
      totalDistanceMeters: stats.totalDistanceMeters,
      totalDurationSeconds: stats.totalDurationSeconds,
      averagePaceSeconds: stats.averagePaceSeconds,
      // Computed stats
      totalDistanceMiles: stats.totalDistanceMeters / 1609.344,
      totalDurationMinutes: Math.round(stats.totalDurationSeconds / 60),
    });
  } catch (error) {
    console.error('Error getting stats:', error);
    res.status(500).json({ error: 'Failed to get stats' });
  }
});

/**
 * Get a specific run by ID
 */
router.get('/:id', requireAuth, async (req, res) => {
  try {
    const run = await sessionDb.findById(req.params.id);

    if (!run) {
      res.status(404).json({ error: 'Run not found' });
      return;
    }

    if (run.userId !== req.user!.id) {
      res.status(403).json({ error: 'Not authorized' });
      return;
    }

    res.json({
      run: {
        id: run.id,
        startedAt: run.startedAt,
        endedAt: run.endedAt,
        durationSeconds: run.durationSeconds,
        distanceMeters: run.distanceMeters,
        averagePaceSeconds: run.averagePaceSeconds,
        caloriesBurned: run.caloriesBurned,
        paceThresholdSeconds: run.paceThresholdSeconds,
        currentState: run.currentState,
        route: run.route,
        healthKitWorkoutId: run.healthKitWorkoutId,
      },
    });
  } catch (error) {
    console.error('Error getting run:', error);
    res.status(500).json({ error: 'Failed to get run' });
  }
});

export default router;
