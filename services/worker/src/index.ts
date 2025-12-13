/**
 * viberunner Worker
 *
 * Continuously updates HR signal refs in gate repos for users with active workouts.
 *
 * For each user with:
 * - A fresh HR sample (within stale threshold)
 * - Active gate repos with GitHub App installed
 *
 * The worker:
 * 1. Computes hr_ok = bpm >= threshold AND sample is fresh
 * 2. Creates signed payload with exp_unix = now + ttl_seconds
 * 3. Pushes payload to refs/viberunner/hr/<user_key> in each gate repo
 */

import { prisma } from '@viberunner/db';
import { createSignedPayload, type HrSignalPayload } from '@viberunner/shared';
import { config } from './config.js';
import { createInstallationOctokit, updateSignalRef } from './github.js';

// Track last update time per repo to avoid unnecessary updates
const lastUpdateTimes = new Map<string, number>();

/**
 * Process a single user's HR status and update their gate repos
 */
async function processUser(userId: string, sessionId: string): Promise<void> {
  // Get user's HR status
  const hrStatus = await prisma.hrStatus.findUnique({
    where: { userId },
  });

  if (!hrStatus) {
    return; // No HR data
  }

  // Check if HR data is stale
  const now = Date.now();
  const hrAgeSeconds = (now - hrStatus.updatedAt.getTime()) / 1000;
  const isStale = hrAgeSeconds > config.hrStaleThresholdSeconds;

  // Get user's active gate repos with GitHub App installed
  const gateRepos = await prisma.gateRepo.findMany({
    where: {
      userId,
      active: true,
      githubAppInstallationId: { not: null },
    },
  });

  if (gateRepos.length === 0) {
    return; // No active gate repos
  }

  // Create signed payload with session ID for commit tagging
  const payload = createSignedPayload(
    gateRepos[0].userKey, // All repos for user have same user_key
    sessionId,           // Session ID for commit tagging
    isStale ? 0 : hrStatus.bpm, // Set BPM to 0 if stale (will fail hr_ok check)
    hrStatus.thresholdBpm,
    config.hrTtlSeconds,
    config.signerPrivateKey
  );

  const payloadJson = JSON.stringify(payload);

  // Update each gate repo
  for (const repo of gateRepos) {
    const repoKey = `${repo.owner}/${repo.name}`;

    // Skip if we updated very recently (within 2 seconds)
    const lastUpdate = lastUpdateTimes.get(repoKey) ?? 0;
    if (now - lastUpdate < 2000) {
      continue;
    }

    try {
      const octokit = await createInstallationOctokit(repo.githubAppInstallationId!);

      await updateSignalRef(
        octokit,
        repo.owner,
        repo.name,
        repo.signalRef,
        payloadJson
      );

      lastUpdateTimes.set(repoKey, now);

      console.log(
        `[${new Date().toISOString()}] Updated ${repoKey}: ` +
        `hr_ok=${payload.hr_ok}, bpm=${payload.bpm}, expires=${payload.exp_unix}`
      );
    } catch (error) {
      console.error(`Failed to update ${repoKey}:`, error);
    }
  }
}

/**
 * Main worker loop
 */
async function runWorker(): Promise<void> {
  console.log('viberunner worker starting...');
  console.log(`Poll interval: ${config.pollIntervalMs}ms`);
  console.log(`HR stale threshold: ${config.hrStaleThresholdSeconds}s`);
  console.log(`HR TTL: ${config.hrTtlSeconds}s`);

  while (true) {
    try {
      // Find users with active workout sessions
      const activeSessions = await prisma.workoutSession.findMany({
        where: { active: true },
        select: { id: true, userId: true },
        distinct: ['userId'],
      });

      // Process each user with their session ID
      await Promise.all(
        activeSessions.map((session) => processUser(session.userId, session.id))
      );
    } catch (error) {
      console.error('Worker loop error:', error);
    }

    // Wait for next poll
    await new Promise((resolve) => setTimeout(resolve, config.pollIntervalMs));
  }
}

// Handle graceful shutdown
process.on('SIGINT', () => {
  console.log('Worker shutting down...');
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.log('Worker shutting down...');
  process.exit(0);
});

// Start worker
runWorker().catch((error) => {
  console.error('Worker fatal error:', error);
  process.exit(1);
});
