/**
 * Heartbeat checker service - implements fail-closed behavior
 *
 * Periodically checks for stale heartbeats and blocks writes
 * for any sessions that haven't reported in.
 */

import { getConfig } from '../config.js';
import { profileDb, deviceDb, repoDb, sessionDb, getActiveSessionsForHeartbeatCheck } from '../db.js';
import { createRulesetManager } from '@viberunner/github';

let checkInterval: ReturnType<typeof setInterval> | null = null;

/**
 * Start the heartbeat checker
 */
export function startHeartbeatChecker(): void {
  if (checkInterval) return;

  const config = getConfig();
  console.log(
    `Starting heartbeat checker (timeout: ${config.heartbeat.timeoutMs}ms, interval: ${config.heartbeat.checkIntervalMs}ms)`
  );

  checkInterval = setInterval(
    () => void checkStaleHeartbeats(),
    config.heartbeat.checkIntervalMs
  );
}

/**
 * Stop the heartbeat checker
 */
export function stopHeartbeatChecker(): void {
  if (checkInterval) {
    clearInterval(checkInterval);
    checkInterval = null;
  }
}

/**
 * Check for stale heartbeats and enforce fail-closed
 */
async function checkStaleHeartbeats(): Promise<void> {
  try {
    const config = getConfig();
    const now = Date.now();
    const sessions = await getActiveSessionsForHeartbeatCheck();

    for (const session of sessions) {
      const lastHeartbeat = session.lastHeartbeat?.getTime() ?? 0;
      const isStale = now - lastHeartbeat > config.heartbeat.timeoutMs;

      // Only take action if session was unlocked and is now stale
      if (isStale && session.currentState === 'RUNNING_UNLOCKED') {
        console.log(
          `Session ${session.id} heartbeat stale, enforcing fail-closed`
        );

        // Update session state
        await sessionDb.update(session.id, {
          currentState: 'RUNNING_LOCKED',
        });

        // Update device state if we have a device
        if (session.deviceId) {
          await deviceDb.updateHeartbeat(session.deviceId, 'RUNNING_LOCKED');
        }

        // Block GitHub writes using the included profile data
        if (session.profile?.githubAccessToken) {
          await blockUserWrites(session.userId, session.profile.githubAccessToken);
        }
      }
    }
  } catch (error) {
    console.error('Error checking stale heartbeats:', error);
  }
}

/**
 * Block writes for all of a user's gated repositories
 */
async function blockUserWrites(userId: string, githubAccessToken: string): Promise<void> {
  const repos = await repoDb.findByUserId(userId);
  if (repos.length === 0) return;

  const manager = createRulesetManager(githubAccessToken);

  await Promise.all(
    repos.map(async (repo) => {
      if (!repo.rulesetId || !repo.gatingEnabled) return;

      try {
        await manager.blockWrites(repo.owner, repo.name, repo.rulesetId);
        console.log(`Blocked writes for ${repo.fullName} (fail-closed)`);
      } catch (error) {
        console.error(`Failed to block writes for ${repo.fullName}:`, error);
      }
    })
  );
}
