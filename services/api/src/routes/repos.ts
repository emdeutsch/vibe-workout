/**
 * Repository management routes
 */

import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { profileDb, repoDb } from '../db.js';
import { createRulesetManager } from '@viberunner/github';

const router = Router();

/**
 * List user's GitHub repositories available for gating
 */
router.get('/available', requireAuth, async (req, res) => {
  try {
    const profile = await profileDb.findById(req.user!.id);
    if (!profile?.githubAccessToken) {
      res.status(400).json({ error: 'GitHub not connected' });
      return;
    }

    const manager = createRulesetManager(profile.githubAccessToken);
    const repos = await manager.listRepositories();

    // Mark which ones are already gated
    const gatedRepos = await repoDb.findByUserId(profile.id);
    const gatedRepoIds = new Set(gatedRepos.map((r) => r.githubRepoId));

    const result = repos.map((repo) => ({
      ...repo,
      isGated: gatedRepoIds.has(repo.id),
    }));

    res.json({ repositories: result });
  } catch (error) {
    console.error('Error listing repos:', error);
    res.status(500).json({ error: 'Failed to list repositories' });
  }
});

/**
 * List user's gated repositories
 */
router.get('/', requireAuth, async (req, res) => {
  try {
    const repos = await repoDb.findByUserId(req.user!.id);
    res.json({ repositories: repos });
  } catch (error) {
    console.error('Error listing gated repos:', error);
    res.status(500).json({ error: 'Failed to list repositories' });
  }
});

/**
 * Add a repository for gating
 */
const addRepoSchema = z.object({
  githubRepoId: z.number(),
  owner: z.string(),
  name: z.string(),
  fullName: z.string(),
});

router.post('/', requireAuth, async (req, res) => {
  try {
    const body = addRepoSchema.parse(req.body);
    const profile = await profileDb.findById(req.user!.id);

    if (!profile?.githubAccessToken) {
      res.status(400).json({ error: 'GitHub not connected' });
      return;
    }

    // Check if already gated
    const existing = await repoDb.findByGithubRepoId(profile.id, body.githubRepoId);
    if (existing) {
      res.status(409).json({ error: 'Repository already gated' });
      return;
    }

    // Create the ruleset on GitHub
    const manager = createRulesetManager(profile.githubAccessToken);
    const result = await manager.createRuleset({
      owner: body.owner,
      repo: body.name,
    });

    if (!result.success) {
      res.status(500).json({ error: result.error || 'Failed to create ruleset' });
      return;
    }

    // Save to database
    const repo = await repoDb.create({
      userId: profile.id,
      githubRepoId: body.githubRepoId,
      owner: body.owner,
      name: body.name,
      fullName: body.fullName,
      rulesetId: result.rulesetId,
      gatingEnabled: true,
    });

    // Enable the ruleset (block writes by default)
    if (result.rulesetId) {
      await manager.blockWrites(body.owner, body.name, result.rulesetId);
    }

    res.status(201).json({ repository: repo });
  } catch (error) {
    if (error instanceof z.ZodError) {
      res.status(400).json({ error: 'Invalid request', details: error.errors });
      return;
    }
    console.error('Error adding repo:', error);
    res.status(500).json({ error: 'Failed to add repository' });
  }
});

/**
 * Remove a repository from gating
 */
router.delete('/:id', requireAuth, async (req, res) => {
  try {
    const repo = await repoDb.findById(req.params.id);
    if (!repo) {
      res.status(404).json({ error: 'Repository not found' });
      return;
    }

    if (repo.userId !== req.user!.id) {
      res.status(403).json({ error: 'Not authorized' });
      return;
    }

    const profile = await profileDb.findById(req.user!.id);
    if (profile?.githubAccessToken && repo.rulesetId) {
      const manager = createRulesetManager(profile.githubAccessToken);
      await manager.deleteRuleset(repo.owner, repo.name, repo.rulesetId);
    }

    await repoDb.delete(repo.id);
    res.json({ success: true });
  } catch (error) {
    console.error('Error removing repo:', error);
    res.status(500).json({ error: 'Failed to remove repository' });
  }
});

/**
 * Get gating status for a repository
 */
router.get('/:id/status', requireAuth, async (req, res) => {
  try {
    const repo = await repoDb.findById(req.params.id);
    if (!repo) {
      res.status(404).json({ error: 'Repository not found' });
      return;
    }

    if (repo.userId !== req.user!.id) {
      res.status(403).json({ error: 'Not authorized' });
      return;
    }

    const profile = await profileDb.findById(req.user!.id);
    if (!profile?.githubAccessToken || !repo.rulesetId) {
      res.json({
        gatingEnabled: repo.gatingEnabled,
        writesBlocked: true,
        rulesetStatus: 'unknown',
      });
      return;
    }

    const manager = createRulesetManager(profile.githubAccessToken);
    const status = await manager.getRulesetStatus(
      repo.owner,
      repo.name,
      repo.rulesetId
    );

    res.json({
      gatingEnabled: repo.gatingEnabled,
      writesBlocked: status?.enabled ?? true,
      rulesetStatus: status?.enforcement ?? 'unknown',
    });
  } catch (error) {
    console.error('Error getting status:', error);
    res.status(500).json({ error: 'Failed to get status' });
  }
});

export default router;
