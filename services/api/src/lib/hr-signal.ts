/**
 * HR Signal Update Helper
 *
 * Updates GitHub refs for gate repos when HR samples arrive.
 * Debounced to reduce GitHub API load - only updates every 5 seconds.
 */

import { prisma } from '@viberunner/db';
import { createSignedPayload } from '@viberunner/shared';
import { config } from '../config.js';
import { createInstallationOctokit, updateSignalRef } from './github.js';

// Debounce interval in milliseconds (5 seconds)
const GITHUB_UPDATE_DEBOUNCE_MS = 5000;

/**
 * Update HR signal refs for all gate repos in a session.
 * Debounced: only updates GitHub every 5 seconds to avoid API overload.
 * The database HrStatus is always up-to-date; this just syncs to GitHub.
 */
export async function updateSessionSignalRefs(
  userId: string,
  sessionId: string,
  bpm: number,
  thresholdBpm: number
): Promise<void> {
  const now = new Date();

  try {
    // Check debounce using raw SQL
    try {
      const result = await prisma.$queryRaw<
        Array<{ last_signal_ref_update_at: string | Date | null }>
      >`
        SELECT last_signal_ref_update_at FROM hr_status WHERE user_id = ${userId} LIMIT 1
      `;
      const rawValue = result[0]?.last_signal_ref_update_at;
      if (rawValue) {
        // Parse date from string if needed
        const lastUpdate = rawValue instanceof Date ? rawValue : new Date(rawValue);
        const timeSinceLastUpdate = now.getTime() - lastUpdate.getTime();
        console.log(
          `[HR Signal] Debounce: lastUpdate=${lastUpdate.toISOString()}, timeSince=${timeSinceLastUpdate}ms`
        );
        if (timeSinceLastUpdate < GITHUB_UPDATE_DEBOUNCE_MS) {
          console.log('[HR Signal] Skipping (debounced)');
          return;
        }
      } else {
        console.log('[HR Signal] No previous update timestamp, proceeding');
      }
    } catch (debounceErr) {
      console.error('[HR Signal] Debounce check failed:', debounceErr);
      // Continue anyway
    }

    // Update timestamp FIRST to prevent concurrent requests from all proceeding
    // This is optimistic - if GitHub fails, we just skip updates for 5 seconds
    await prisma.$executeRaw`
      UPDATE hr_status SET last_signal_ref_update_at = ${now} WHERE user_id = ${userId}
    `;

    // Find gate repos
    const gateRepos = await prisma.gateRepo.findMany({
      where: {
        userId,
        active: true,
        activeSessionId: sessionId,
        githubAppInstallationId: { not: null },
      },
    });

    console.log(`[HR Signal] Found ${gateRepos.length} repos for session=${sessionId}`);

    if (gateRepos.length === 0) {
      return;
    }

    // Create signed payload
    const payload = createSignedPayload(
      gateRepos[0].userKey,
      sessionId,
      bpm,
      thresholdBpm,
      config.hrTtlSeconds,
      config.signerPrivateKey
    );

    const payloadJson = JSON.stringify(payload);
    console.log(`[HR Signal] Payload created: bpm=${bpm}, hr_ok=${payload.hr_ok}`);

    // Update all repos in parallel
    const results = await Promise.allSettled(
      gateRepos.map(async (repo) => {
        console.log(`[HR Signal] Updating ${repo.owner}/${repo.name}...`);
        const octokit = await createInstallationOctokit(repo.githubAppInstallationId!);
        await updateSignalRef(octokit, repo.owner, repo.name, repo.signalRef, payloadJson);
        console.log(`[HR Signal] SUCCESS: ${repo.owner}/${repo.name}`);
      })
    );

    // Log results
    const anySuccess = results.some((r) => r.status === 'fulfilled');
    console.log(`[HR Signal] Results: ${results.length} total, anySuccess=${anySuccess}`);

    // Log failures
    results.forEach((result, i) => {
      if (result.status === 'rejected') {
        console.error(
          `[HR Signal] FAILED ${gateRepos[i].owner}/${gateRepos[i].name}:`,
          result.reason
        );
      }
    });
  } catch (error) {
    console.error('[HR Signal] FATAL error:', error);
  }
}
