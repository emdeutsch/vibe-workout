/**
 * Workout and HR routes - session management and HR ingestion
 */

import { Hono } from 'hono';
import { prisma } from '@vibeworkout/db';
import { authMiddleware } from '../middleware/auth.js';
import { config } from '../config.js';
import { updateSessionSignalRefs } from '../lib/hr-signal.js';
import { createInstallationOctokit } from '../lib/github.js';
import type {
  StartWorkoutRequest,
  StartWorkoutResponse,
  IngestHrSampleRequest,
  HrStatusResponse,
} from '@vibeworkout/shared';

const workout = new Hono();

// Apply auth to all routes
workout.use('*', authMiddleware);

// Start a workout session
workout.post('/start', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json<StartWorkoutRequest>().catch(() => ({}) as StartWorkoutRequest);

  // End any existing active sessions and clear their repo selections
  const existingSessions = await prisma.workoutSession.findMany({
    where: { userId, active: true },
    select: { id: true },
  });

  if (existingSessions.length > 0) {
    // Clear activeSessionId from repos of old sessions
    await prisma.gateRepo.updateMany({
      where: {
        activeSessionId: { in: existingSessions.map((s: { id: string }) => s.id) },
      },
      data: { activeSessionId: null },
    });

    // End old sessions
    await prisma.workoutSession.updateMany({
      where: { userId, active: true },
      data: { active: false, endedAt: new Date() },
    });
  }

  // Create new session
  const session = await prisma.workoutSession.create({
    data: {
      userId,
      source: body.source || 'watch',
      active: true,
    },
  });

  // Activate selected repos for this session
  let selectedRepos: Array<{ id: string; owner: string; name: string }> = [];
  console.log('[start] Received repo_ids:', body.repo_ids);

  if (body.repo_ids && body.repo_ids.length > 0) {
    // Update repos to be active for this session
    const updateResult = await prisma.gateRepo.updateMany({
      where: {
        id: { in: body.repo_ids },
        userId, // Ensure user owns these repos
        active: true,
        githubAppInstallationId: { not: null }, // Only repos with app installed
      },
      data: { activeSessionId: session.id },
    });

    console.log('[start] Updated repos count:', updateResult.count);

    // Fetch the repos that were activated
    const repos = await prisma.gateRepo.findMany({
      where: { activeSessionId: session.id },
      select: { id: true, owner: true, name: true, githubAppInstallationId: true },
    });
    console.log('[start] Activated repos:', JSON.stringify(repos));
    selectedRepos = repos;
  } else {
    console.log('[start] No repo_ids provided in request');
  }

  const response: StartWorkoutResponse = {
    session_id: session.id,
    started_at: session.startedAt.toISOString(),
    selected_repos: selectedRepos.length > 0 ? selectedRepos : undefined,
  };

  return c.json(response, 201);
});

// Stop the active workout session
workout.post('/stop', async (c) => {
  const userId = c.get('userId');

  // Get active sessions with full info (need startedAt for commit filtering)
  const activeSessions = await prisma.workoutSession.findMany({
    where: { userId, active: true },
    select: { id: true, startedAt: true },
  });

  if (activeSessions.length === 0) {
    return c.json({ error: 'No active workout session' }, 404);
  }

  // Get repos that were active during these sessions BEFORE clearing activeSessionId
  console.log(
    '[stop] Looking for repos with activeSessionId in:',
    activeSessions.map((s: { id: string; startedAt: Date }) => s.id)
  );

  const activeRepos = await prisma.gateRepo.findMany({
    where: {
      activeSessionId: { in: activeSessions.map((s: { id: string; startedAt: Date }) => s.id) },
      githubAppInstallationId: { not: null },
    },
    select: {
      id: true,
      owner: true,
      name: true,
      userKey: true,
      activeSessionId: true,
      githubAppInstallationId: true,
    },
  });

  console.log('[stop] Found activeRepos:', JSON.stringify(activeRepos));

  // Clear activeSessionId from repos
  await prisma.gateRepo.updateMany({
    where: {
      activeSessionId: { in: activeSessions.map((s: { id: string; startedAt: Date }) => s.id) },
    },
    data: { activeSessionId: null },
  });

  const endedAt = new Date();

  // End sessions
  const result = await prisma.workoutSession.updateMany({
    where: { userId, active: true },
    data: { active: false, endedAt },
  });

  // Expire HR status
  await prisma.hrStatus.updateMany({
    where: { userId },
    data: {
      hrOk: false,
      expiresAt: new Date(),
    },
  });

  // Fetch commits from GitHub for each repo that was active during a session
  console.log('[stop] Active repos for commit fetching:', activeRepos.length);
  for (const repo of activeRepos) {
    console.log(
      '[stop] Checking repo:',
      repo.owner,
      repo.name,
      'installationId:',
      repo.githubAppInstallationId,
      'sessionId:',
      repo.activeSessionId
    );
    if (!repo.githubAppInstallationId || !repo.activeSessionId) continue;

    const session = activeSessions.find(
      (s: { id: string; startedAt: Date }) => s.id === repo.activeSessionId
    );
    if (!session) {
      console.log('[stop] No session found for repo');
      continue;
    }

    console.log(
      '[stop] Session times - started:',
      session.startedAt.toISOString(),
      'ended:',
      endedAt.toISOString()
    );

    try {
      const octokit = await createInstallationOctokit(repo.githubAppInstallationId);

      // Fetch commits from ALL branches (Events API doesn't capture feature branch pushes)
      // Step 1: Get all branch refs
      const { data: refs } = await octokit.rest.git.listMatchingRefs({
        owner: repo.owner,
        repo: repo.name,
        ref: 'heads/',
      });

      const branchNames = refs.map((r) => r.ref.replace('refs/heads/', ''));
      console.log('[stop] Found branches:', branchNames.length, branchNames);

      // Step 2: For each branch, fetch commits within our time window
      // Add 2 minute buffer to account for clock skew
      const windowStart = new Date(session.startedAt.getTime() - 2 * 60 * 1000);
      const windowEnd = new Date(endedAt.getTime() + 2 * 60 * 1000);
      console.log('[stop] Time window:', windowStart.toISOString(), '-', windowEnd.toISOString());

      const seenShas = new Set<string>();
      let totalCommitsFound = 0;

      for (const branch of branchNames) {
        try {
          const { data: commits } = await octokit.rest.repos.listCommits({
            owner: repo.owner,
            repo: repo.name,
            sha: branch,
            since: windowStart.toISOString(),
            until: windowEnd.toISOString(),
            per_page: 100,
          });

          console.log('[stop] Branch', branch, 'has', commits.length, 'commits in window');

          for (const commit of commits) {
            if (seenShas.has(commit.sha)) continue;
            seenShas.add(commit.sha);
            totalCommitsFound++;

            const commitDate = new Date(
              commit.commit.author?.date || commit.commit.committer?.date || ''
            );

            console.log(
              '[stop] Saving commit',
              commit.sha.substring(0, 7),
              'msg:',
              commit.commit.message?.substring(0, 30)
            );

            // Fetch full commit for stats
            const { data: fullCommit } = await octokit.rest.repos.getCommit({
              owner: repo.owner,
              repo: repo.name,
              ref: commit.sha,
            });

            // Upsert commit
            const saved = await prisma.sessionCommit.upsert({
              where: {
                sessionId_commitSha: {
                  sessionId: session.id,
                  commitSha: commit.sha,
                },
              },
              create: {
                sessionId: session.id,
                repoOwner: repo.owner,
                repoName: repo.name,
                commitSha: commit.sha,
                commitMsg: commit.commit.message?.substring(0, 1000) || '',
                linesAdded: fullCommit.stats?.additions ?? null,
                linesRemoved: fullCommit.stats?.deletions ?? null,
                committedAt: commitDate,
              },
              update: {},
            });

            // Save files changed in this commit
            if (fullCommit.files && fullCommit.files.length > 0) {
              await prisma.sessionCommitFile.deleteMany({
                where: { commitId: saved.id },
              });

              await prisma.sessionCommitFile.createMany({
                data: fullCommit.files.map((f) => ({
                  commitId: saved.id,
                  filename: f.filename,
                  status: f.status || 'modified',
                  additions: f.additions ?? null,
                  deletions: f.deletions ?? null,
                })),
              });
            }
          }
        } catch (branchError) {
          console.error(`[stop] Error fetching commits for branch ${branch}:`, branchError);
        }
      }

      console.log('[stop] Total unique commits saved:', totalCommitsFound);

      // Also fetch PRs created or updated during the session
      console.log('[stop] Fetching PRs for', repo.owner, repo.name);
      const { data: pullRequests } = await octokit.rest.pulls.list({
        owner: repo.owner,
        repo: repo.name,
        state: 'all',
        sort: 'updated',
        direction: 'desc',
        per_page: 50,
      });

      console.log('[stop] Found', pullRequests.length, 'PRs total');
      console.log(
        '[stop] Session window for PRs:',
        session.startedAt.toISOString(),
        '-',
        endedAt.toISOString()
      );

      let prsMatched = 0;
      for (const pr of pullRequests) {
        const prCreatedAt = new Date(pr.created_at);
        const prUpdatedAt = new Date(pr.updated_at);

        // Include PR if it was created during session OR updated during session
        const createdDuringSession = prCreatedAt >= session.startedAt && prCreatedAt <= endedAt;
        const updatedDuringSession = prUpdatedAt >= session.startedAt && prUpdatedAt <= endedAt;

        if (!createdDuringSession && !updatedDuringSession) {
          console.log(
            '[stop] PR #',
            pr.number,
            'outside window. created:',
            pr.created_at,
            'updated:',
            pr.updated_at
          );
          continue;
        }

        prsMatched++;
        console.log('[stop] PR #', pr.number, 'matched! created:', pr.created_at);

        // Determine merged state
        const state = pr.merged_at ? 'merged' : pr.state;

        await prisma.sessionPullRequest.upsert({
          where: {
            sessionId_prNumber_repoOwner_repoName: {
              sessionId: session.id,
              prNumber: pr.number,
              repoOwner: repo.owner,
              repoName: repo.name,
            },
          },
          create: {
            sessionId: session.id,
            repoOwner: repo.owner,
            repoName: repo.name,
            prNumber: pr.number,
            title: pr.title,
            state,
            htmlUrl: pr.html_url,
            createdAt: prCreatedAt,
            mergedAt: pr.merged_at ? new Date(pr.merged_at) : null,
            // additions/deletions not available in list endpoint
          },
          update: {
            title: pr.title,
            state,
            mergedAt: pr.merged_at ? new Date(pr.merged_at) : null,
          },
        });
      }

      console.log('[stop] Total PRs matched and saved:', prsMatched);

      // Fetch tool stats from the stats ref
      console.log('[stop] Fetching tool stats for', repo.owner, repo.name);
      try {
        const statsRef = `refs/vibeworkout/stats/${repo.userKey}`;
        const shortStatsRef = statsRef.replace('refs/', '');

        const { data: statsRefData } = await octokit.rest.git.getRef({
          owner: repo.owner,
          repo: repo.name,
          ref: shortStatsRef,
        });

        // Get the commit and tree to find the stats file
        const { data: statsCommit } = await octokit.rest.git.getCommit({
          owner: repo.owner,
          repo: repo.name,
          commit_sha: statsRefData.object.sha,
        });

        const { data: statsTree } = await octokit.rest.git.getTree({
          owner: repo.owner,
          repo: repo.name,
          tree_sha: statsCommit.tree.sha,
        });

        const statsFile = statsTree.tree.find((f) => f.path === 'tool-stats.jsonl');
        if (statsFile?.sha) {
          const { data: statsBlob } = await octokit.rest.git.getBlob({
            owner: repo.owner,
            repo: repo.name,
            file_sha: statsFile.sha,
          });

          const statsContent = Buffer.from(statsBlob.content, 'base64').toString('utf-8');
          const statsLines = statsContent.trim().split('\n').filter(Boolean);

          console.log('[stop] Found', statsLines.length, 'tool stats entries');

          // First pass: process attempt entries
          for (const line of statsLines) {
            try {
              const entry = JSON.parse(line) as {
                ts: string;
                type?: 'attempt' | 'outcome';
                tool_use_id?: string;
                tool: string;
                allowed?: boolean;
                gated?: boolean;
                reason?: string;
                succeeded?: boolean;
                session_id?: string;
                bpm?: number;
              };

              // Skip outcome entries in first pass
              if (entry.type === 'outcome') continue;

              const timestamp = new Date(entry.ts);

              // Filter to this session's time window
              if (timestamp < windowStart || timestamp > windowEnd) continue;

              // Also verify session_id matches if available
              if (entry.session_id && entry.session_id !== session.id) continue;

              await prisma.toolAttempt.upsert({
                where: {
                  sessionId_timestamp_toolName: {
                    sessionId: session.id,
                    timestamp,
                    toolName: entry.tool,
                  },
                },
                create: {
                  sessionId: session.id,
                  toolName: entry.tool,
                  toolUseId: entry.tool_use_id ?? null,
                  allowed: entry.allowed ?? false,
                  gated: entry.gated ?? true,
                  reason: entry.reason ?? null,
                  bpm: entry.bpm ?? null,
                  timestamp,
                },
                update: {
                  // Update if we have new data (e.g., tool_use_id)
                  toolUseId: entry.tool_use_id ?? undefined,
                  reason: entry.reason ?? undefined,
                  gated: entry.gated ?? undefined,
                },
              });
            } catch (parseError) {
              console.error('[stop] Failed to parse tool stats line:', parseError);
            }
          }

          // Second pass: process outcome entries to update succeeded field
          for (const line of statsLines) {
            try {
              const entry = JSON.parse(line) as {
                ts: string;
                type?: 'attempt' | 'outcome';
                tool_use_id?: string;
                tool: string;
                succeeded?: boolean;
              };

              // Only process outcome entries
              if (entry.type !== 'outcome') continue;

              const timestamp = new Date(entry.ts);

              // Filter to this session's time window
              if (timestamp < windowStart || timestamp > windowEnd) continue;

              // Match by tool_use_id if available
              if (entry.tool_use_id) {
                await prisma.toolAttempt.updateMany({
                  where: {
                    sessionId: session.id,
                    toolUseId: entry.tool_use_id,
                  },
                  data: {
                    succeeded: entry.succeeded ?? true,
                  },
                });
              }
            } catch (parseError) {
              console.error('[stop] Failed to parse tool outcome line:', parseError);
            }
          }
        }
      } catch (statsError) {
        // Stats ref may not exist yet - that's fine
        console.log('[stop] No tool stats found (ref may not exist):', statsError);
      }
    } catch (error) {
      // Log but don't fail the stop - commits are nice-to-have
      console.error(`Failed to fetch commits for ${repo.owner}/${repo.name}:`, error);
    }
  }

  // Generate WorkoutSummary for each ended session
  const profile = await prisma.profile.findUnique({
    where: { userId },
  });
  const threshold = profile?.hrThresholdBpm ?? config.defaultHrThreshold;

  for (const session of activeSessions) {
    // Check if summary already exists
    const existingSummary = await prisma.workoutSummary.findUnique({
      where: { sessionId: session.id },
    });

    if (existingSummary) continue;

    // Get all HR samples for this session
    const samples = await prisma.hrSample.findMany({
      where: { sessionId: session.id },
      orderBy: { ts: 'asc' },
    });

    if (samples.length === 0) {
      // Create summary with zero values if no samples
      await prisma.workoutSummary.create({
        data: {
          sessionId: session.id,
          durationSecs: 0,
          avgBpm: 0,
          maxBpm: 0,
          minBpm: 0,
          timeAboveThresholdSecs: 0,
          timeBelowThresholdSecs: 0,
          thresholdBpm: threshold,
          totalSamples: 0,
        },
      });
      continue;
    }

    const bpms = samples.map((s: { bpm: number; ts: Date }) => s.bpm);
    const startTs = samples[0].ts.getTime();
    const endTs = samples[samples.length - 1].ts.getTime();
    const durationSecs = Math.round((endTs - startTs) / 1000);

    // Calculate time above/below threshold
    let timeAbove = 0;
    let timeBelow = 0;
    for (let i = 1; i < samples.length; i++) {
      const interval = (samples[i].ts.getTime() - samples[i - 1].ts.getTime()) / 1000;
      if (samples[i].bpm >= threshold) {
        timeAbove += interval;
      } else {
        timeBelow += interval;
      }
    }

    await prisma.workoutSummary.create({
      data: {
        sessionId: session.id,
        durationSecs,
        avgBpm: Math.round(bpms.reduce((a: number, b: number) => a + b, 0) / bpms.length),
        maxBpm: Math.max(...bpms),
        minBpm: Math.min(...bpms),
        timeAboveThresholdSecs: Math.round(timeAbove),
        timeBelowThresholdSecs: Math.round(timeBelow),
        thresholdBpm: threshold,
        totalSamples: samples.length,
      },
    });
  }

  return c.json({
    stopped: true,
    sessions_ended: result.count,
    session_ids: activeSessions.map((s: { id: string; startedAt: Date }) => s.id),
  });
});

// Get active workout session
workout.get('/active', async (c) => {
  const userId = c.get('userId');

  const session = await prisma.workoutSession.findFirst({
    where: { userId, active: true },
    orderBy: { startedAt: 'desc' },
    include: {
      activeGateRepos: {
        select: { id: true, owner: true, name: true },
      },
    },
  });

  if (!session) {
    return c.json({ active: false });
  }

  return c.json({
    active: true,
    session_id: session.id,
    started_at: session.startedAt.toISOString(),
    source: session.source,
    selected_repos: session.activeGateRepos.length > 0 ? session.activeGateRepos : undefined,
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

  // Update GitHub signal refs (must await in serverless!)
  await updateSessionSignalRefs(userId, body.session_id, body.bpm, threshold);

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
    samples: samples.map((s: { bpm: number; ts: Date; source: string }) => ({
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
      commits: {
        select: {
          repoOwner: true,
          repoName: true,
          linesAdded: true,
          linesRemoved: true,
        },
      },
    },
  });

  const hasMore = sessions.length > limit;
  const items = hasMore ? sessions.slice(0, -1) : sessions;
  const nextCursor = hasMore ? items[items.length - 1]?.id : undefined;

  // Fetch sparkline data for each session (sampled BPMs)
  const sessionIds = items.map((s: (typeof items)[number]) => s.id);
  const sparklineData = await Promise.all(
    sessionIds.map(async (sessionId: string) => {
      const samples = await prisma.hrSample.findMany({
        where: { sessionId },
        orderBy: { ts: 'asc' },
        select: { bpm: true },
      });

      // Downsample to ~20 points for sparkline
      if (samples.length <= 20) {
        return { sessionId, bpms: samples.map((s: { bpm: number }) => s.bpm) };
      }

      const step = Math.floor(samples.length / 20);
      const sampled: number[] = [];
      for (let i = 0; i < samples.length; i += step) {
        sampled.push(samples[i].bpm);
        if (sampled.length >= 20) break;
      }
      return { sessionId, bpms: sampled };
    })
  );

  const sparklineMap = new Map(sparklineData.map((s) => [s.sessionId, s.bpms]));

  return c.json({
    sessions: items.map((s: (typeof items)[number]) => {
      // Aggregate commit stats
      const totalLinesAdded = s.commits.reduce(
        (
          sum: number,
          c: {
            linesAdded: number | null;
            linesRemoved: number | null;
            repoOwner: string;
            repoName: string;
          }
        ) => sum + (c.linesAdded ?? 0),
        0
      );
      const totalLinesRemoved = s.commits.reduce(
        (
          sum: number,
          c: {
            linesAdded: number | null;
            linesRemoved: number | null;
            repoOwner: string;
            repoName: string;
          }
        ) => sum + (c.linesRemoved ?? 0),
        0
      );

      // Get unique repo names and find top repo
      const repoCommitCounts = new Map<string, number>();
      for (const commit of s.commits) {
        const key = `${commit.repoOwner}/${commit.repoName}`;
        repoCommitCounts.set(key, (repoCommitCounts.get(key) ?? 0) + 1);
      }

      const repoNames = Array.from(repoCommitCounts.keys());
      let topRepo: string | null = null;
      let maxCommits = 0;
      for (const [repo, count] of repoCommitCounts) {
        if (count > maxCommits) {
          maxCommits = count;
          topRepo = repo;
        }
      }

      return {
        id: s.id,
        started_at: s.startedAt.toISOString(),
        ended_at: s.endedAt?.toISOString() ?? null,
        active: s.active,
        source: s.source,
        summary: s.summary
          ? {
              duration_secs: s.summary.durationSecs,
              avg_bpm: s.summary.avgBpm,
              max_bpm: s.summary.maxBpm,
              min_bpm: s.summary.minBpm,
              time_above_threshold_secs: s.summary.timeAboveThresholdSecs,
              time_below_threshold_secs: s.summary.timeBelowThresholdSecs,
              threshold_bpm: s.summary.thresholdBpm,
              total_samples: s.summary.totalSamples,
            }
          : null,
        commit_count: s.commits.length,
        total_lines_added: totalLinesAdded,
        total_lines_removed: totalLinesRemoved,
        top_repo: topRepo,
        repo_names: repoNames,
        sparkline_bpms: sparklineMap.get(s.id) ?? null,
      };
    }),
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
      pullRequests: {
        orderBy: { createdAt: 'desc' },
      },
      toolAttempts: {
        orderBy: { timestamp: 'asc' },
      },
    },
  });

  if (!session) {
    return c.json({ error: 'Session not found' }, 404);
  }

  // Aggregate tool stats
  const toolStats = {
    total_attempts: session.toolAttempts.length,
    allowed: session.toolAttempts.filter((t: { allowed: boolean }) => t.allowed).length,
    blocked: session.toolAttempts.filter((t: { allowed: boolean }) => !t.allowed).length,
    succeeded: session.toolAttempts.filter((t: { succeeded: boolean | null }) => t.succeeded === true).length,
    ungated: session.toolAttempts.filter((t: { gated: boolean }) => !t.gated).length,
    by_tool: {} as Record<string, { allowed: number; blocked: number; succeeded: number }>,
    by_reason: {} as Record<string, number>,
  };

  for (const attempt of session.toolAttempts) {
    if (!toolStats.by_tool[attempt.toolName]) {
      toolStats.by_tool[attempt.toolName] = { allowed: 0, blocked: 0, succeeded: 0 };
    }
    if (attempt.allowed) {
      toolStats.by_tool[attempt.toolName].allowed++;
      if (attempt.succeeded === true) {
        toolStats.by_tool[attempt.toolName].succeeded++;
      }
    } else {
      toolStats.by_tool[attempt.toolName].blocked++;
      if (attempt.reason) {
        toolStats.by_reason[attempt.reason] = (toolStats.by_reason[attempt.reason] ?? 0) + 1;
      }
    }
  }

  return c.json({
    id: session.id,
    started_at: session.startedAt.toISOString(),
    ended_at: session.endedAt?.toISOString() ?? null,
    active: session.active,
    source: session.source,
    summary: session.summary
      ? {
          duration_secs: session.summary.durationSecs,
          avg_bpm: session.summary.avgBpm,
          max_bpm: session.summary.maxBpm,
          min_bpm: session.summary.minBpm,
          time_above_threshold_secs: session.summary.timeAboveThresholdSecs,
          time_below_threshold_secs: session.summary.timeBelowThresholdSecs,
          threshold_bpm: session.summary.thresholdBpm,
          total_samples: session.summary.totalSamples,
        }
      : null,
    commits: session.commits.map((c: (typeof session.commits)[number]) => ({
      id: c.id,
      repo_owner: c.repoOwner,
      repo_name: c.repoName,
      commit_sha: c.commitSha,
      commit_msg: c.commitMsg,
      lines_added: c.linesAdded,
      lines_removed: c.linesRemoved,
      committed_at: c.committedAt.toISOString(),
    })),
    pull_requests: session.pullRequests.map((pr: (typeof session.pullRequests)[number]) => ({
      id: pr.id,
      repo_owner: pr.repoOwner,
      repo_name: pr.repoName,
      pr_number: pr.prNumber,
      title: pr.title,
      state: pr.state,
      html_url: pr.htmlUrl,
      created_at: pr.createdAt.toISOString(),
      merged_at: pr.mergedAt?.toISOString() ?? null,
      additions: pr.additions,
      deletions: pr.deletions,
    })),
    tool_stats: toolStats,
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
    samples: samples.map((s: { bpm: number; ts: Date }) => ({
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
    buckets: buckets.map((b: (typeof buckets)[number]) => ({
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

// Get post-workout summary with repo breakdown
workout.get('/sessions/:sessionId/post-summary', async (c) => {
  const userId = c.get('userId');
  const sessionId = c.req.param('sessionId');

  const session = await prisma.workoutSession.findFirst({
    where: { id: sessionId, userId },
    include: {
      summary: true,
      commits: {
        orderBy: { committedAt: 'desc' },
      },
      pullRequests: {
        orderBy: { createdAt: 'desc' },
      },
      toolAttempts: {
        orderBy: { timestamp: 'asc' },
      },
    },
  });

  if (!session) {
    return c.json({ error: 'Session not found' }, 404);
  }

  // Aggregate tool stats
  const toolStats = {
    total_attempts: session.toolAttempts.length,
    allowed: session.toolAttempts.filter((t: { allowed: boolean }) => t.allowed).length,
    blocked: session.toolAttempts.filter((t: { allowed: boolean }) => !t.allowed).length,
    succeeded: session.toolAttempts.filter((t: { succeeded: boolean | null }) => t.succeeded === true).length,
    ungated: session.toolAttempts.filter((t: { gated: boolean }) => !t.gated).length,
    by_tool: {} as Record<string, { allowed: number; blocked: number; succeeded: number }>,
    by_reason: {} as Record<string, number>,
  };

  for (const attempt of session.toolAttempts) {
    if (!toolStats.by_tool[attempt.toolName]) {
      toolStats.by_tool[attempt.toolName] = { allowed: 0, blocked: 0, succeeded: 0 };
    }
    if (attempt.allowed) {
      toolStats.by_tool[attempt.toolName].allowed++;
      if (attempt.succeeded === true) {
        toolStats.by_tool[attempt.toolName].succeeded++;
      }
    } else {
      toolStats.by_tool[attempt.toolName].blocked++;
      if (attempt.reason) {
        toolStats.by_reason[attempt.reason] = (toolStats.by_reason[attempt.reason] ?? 0) + 1;
      }
    }
  }

  // Aggregate commits by repo
  const repoMap = new Map<
    string,
    {
      owner: string;
      name: string;
      commitCount: number;
      linesAdded: number;
      linesRemoved: number;
      firstCommitAt: Date | null;
      lastCommitAt: Date | null;
    }
  >();

  for (const commit of session.commits) {
    const key = `${commit.repoOwner}/${commit.repoName}`;
    const existing = repoMap.get(key);

    if (existing) {
      existing.commitCount++;
      existing.linesAdded += commit.linesAdded ?? 0;
      existing.linesRemoved += commit.linesRemoved ?? 0;
      if (!existing.firstCommitAt || commit.committedAt < existing.firstCommitAt) {
        existing.firstCommitAt = commit.committedAt;
      }
      if (!existing.lastCommitAt || commit.committedAt > existing.lastCommitAt) {
        existing.lastCommitAt = commit.committedAt;
      }
    } else {
      repoMap.set(key, {
        owner: commit.repoOwner,
        name: commit.repoName,
        commitCount: 1,
        linesAdded: commit.linesAdded ?? 0,
        linesRemoved: commit.linesRemoved ?? 0,
        firstCommitAt: commit.committedAt,
        lastCommitAt: commit.committedAt,
      });
    }
  }

  const repoBreakdown = Array.from(repoMap.values()).sort((a, b) => b.commitCount - a.commitCount);

  const totalLinesAdded = session.commits.reduce(
    (sum: number, c: (typeof session.commits)[number]) => sum + (c.linesAdded ?? 0),
    0
  );
  const totalLinesRemoved = session.commits.reduce(
    (sum: number, c: (typeof session.commits)[number]) => sum + (c.linesRemoved ?? 0),
    0
  );

  return c.json({
    session: {
      id: session.id,
      started_at: session.startedAt.toISOString(),
      ended_at: session.endedAt?.toISOString() ?? null,
      active: session.active,
      source: session.source,
      summary: session.summary
        ? {
            duration_secs: session.summary.durationSecs,
            avg_bpm: session.summary.avgBpm,
            max_bpm: session.summary.maxBpm,
            min_bpm: session.summary.minBpm,
            time_above_threshold_secs: session.summary.timeAboveThresholdSecs,
            time_below_threshold_secs: session.summary.timeBelowThresholdSecs,
            threshold_bpm: session.summary.thresholdBpm,
            total_samples: session.summary.totalSamples,
          }
        : null,
      commits: session.commits.map((c: (typeof session.commits)[number]) => ({
        id: c.id,
        repo_owner: c.repoOwner,
        repo_name: c.repoName,
        commit_sha: c.commitSha,
        commit_msg: c.commitMsg,
        lines_added: c.linesAdded,
        lines_removed: c.linesRemoved,
        committed_at: c.committedAt.toISOString(),
      })),
      pull_requests: session.pullRequests.map((pr: (typeof session.pullRequests)[number]) => ({
        id: pr.id,
        repo_owner: pr.repoOwner,
        repo_name: pr.repoName,
        pr_number: pr.prNumber,
        title: pr.title,
        state: pr.state,
        html_url: pr.htmlUrl,
        created_at: pr.createdAt.toISOString(),
        merged_at: pr.mergedAt?.toISOString() ?? null,
        additions: pr.additions,
        deletions: pr.deletions,
      })),
    },
    repo_breakdown: repoBreakdown.map((r: (typeof repoBreakdown)[number]) => ({
      owner: r.owner,
      name: r.name,
      commit_count: r.commitCount,
      lines_added: r.linesAdded,
      lines_removed: r.linesRemoved,
      first_commit_at: r.firstCommitAt?.toISOString() ?? null,
      last_commit_at: r.lastCommitAt?.toISOString() ?? null,
    })),
    total_lines_added: totalLinesAdded,
    total_lines_removed: totalLinesRemoved,
    total_commits: session.commits.length,
    total_pull_requests: session.pullRequests.length,
    tool_stats: toolStats,
  });
});

// Discard a workout session (delete within time window)
workout.delete('/sessions/:sessionId', async (c) => {
  const userId = c.get('userId');
  const sessionId = c.req.param('sessionId');

  const session = await prisma.workoutSession.findFirst({
    where: { id: sessionId, userId },
    select: { id: true, endedAt: true, active: true },
  });

  if (!session) {
    return c.json({ error: 'Session not found' }, 404);
  }

  // Only allow discard if session ended within last 5 minutes or is still active
  const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);
  if (session.endedAt && session.endedAt < fiveMinutesAgo && !session.active) {
    return c.json({ error: 'Session can only be discarded within 5 minutes of ending' }, 400);
  }

  // Delete all related data in order (respecting foreign keys)
  await prisma.toolAttempt.deleteMany({ where: { sessionId } });
  await prisma.sessionPullRequest.deleteMany({ where: { sessionId } });
  await prisma.sessionCommit.deleteMany({ where: { sessionId } });
  await prisma.hrBucket.deleteMany({ where: { sessionId } });
  await prisma.workoutSummary.deleteMany({ where: { sessionId } });
  await prisma.hrSample.deleteMany({ where: { sessionId } });

  // Clear activeSessionId from any repos
  await prisma.gateRepo.updateMany({
    where: { activeSessionId: sessionId },
    data: { activeSessionId: null },
  });

  // Delete the session itself
  await prisma.workoutSession.delete({ where: { id: sessionId } });

  return c.json({ deleted: true });
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

  return c.json(
    {
      id: commit.id,
      commit_sha: commit.commitSha,
    },
    201
  );
});

// ============================================================
// AGGREGATED STATS ENDPOINTS
// ============================================================

// Helper to calculate period start date
function getPeriodStart(period: string): Date | null {
  const now = new Date();
  switch (period) {
    case '7d':
      return new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    case '30d':
      return new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    case '90d':
      return new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000);
    case '1y':
      return new Date(now.getTime() - 365 * 24 * 60 * 60 * 1000);
    case 'all':
      return null; // No filter
    default:
      return new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
  }
}

// Get aggregated overview stats
workout.get('/stats/overview', async (c) => {
  const userId = c.get('userId');
  const period = c.req.query('period') || '30d';
  const periodStart = getPeriodStart(period);
  const periodEnd = new Date();

  // Build where clause for sessions
  const sessionWhere: { userId: string; endedAt?: { not: null; gte?: Date } } = {
    userId,
    endedAt: { not: null },
  };
  if (periodStart) {
    sessionWhere.endedAt = { not: null, gte: periodStart };
  }

  // Get sessions with summaries and commits
  const sessions = await prisma.workoutSession.findMany({
    where: sessionWhere,
    include: {
      summary: true,
      commits: {
        select: {
          linesAdded: true,
          linesRemoved: true,
          repoOwner: true,
          repoName: true,
        },
      },
      pullRequests: {
        select: {
          state: true,
        },
      },
      toolAttempts: {
        select: {
          allowed: true,
          succeeded: true,
          toolName: true,
        },
      },
    },
  });

  // Aggregate workout stats
  let totalDurationSecs = 0;
  let totalBpmSum = 0;
  let totalBpmCount = 0;
  let maxBpm = 0;
  let minBpm = 999;
  let timeAboveThresholdSecs = 0;
  let timeBelowThresholdSecs = 0;

  for (const session of sessions) {
    if (session.summary) {
      totalDurationSecs += session.summary.durationSecs;
      if (session.summary.avgBpm > 0) {
        totalBpmSum += session.summary.avgBpm * session.summary.durationSecs;
        totalBpmCount += session.summary.durationSecs;
      }
      if (session.summary.maxBpm > maxBpm) maxBpm = session.summary.maxBpm;
      if (session.summary.minBpm > 0 && session.summary.minBpm < minBpm) {
        minBpm = session.summary.minBpm;
      }
      timeAboveThresholdSecs += session.summary.timeAboveThresholdSecs;
      timeBelowThresholdSecs += session.summary.timeBelowThresholdSecs;
    }
  }

  const avgBpm = totalBpmCount > 0 ? Math.round(totalBpmSum / totalBpmCount) : 0;
  if (minBpm === 999) minBpm = 0;

  // Aggregate coding stats
  let totalCommits = 0;
  let linesAdded = 0;
  let linesRemoved = 0;
  const repoSet = new Set<string>();
  let prsOpened = 0;
  let prsMerged = 0;
  let prsClosed = 0;

  for (const session of sessions) {
    totalCommits += session.commits.length;
    for (const commit of session.commits) {
      linesAdded += commit.linesAdded ?? 0;
      linesRemoved += commit.linesRemoved ?? 0;
      repoSet.add(`${commit.repoOwner}/${commit.repoName}`);
    }
    for (const pr of session.pullRequests) {
      if (pr.state === 'open') prsOpened++;
      else if (pr.state === 'merged') prsMerged++;
      else if (pr.state === 'closed') prsClosed++;
    }
  }

  // Aggregate tool stats
  let totalAttempts = 0;
  let allowed = 0;
  let blocked = 0;
  let succeeded = 0;
  let failed = 0;
  const toolCounts = new Map<string, number>();

  for (const session of sessions) {
    for (const attempt of session.toolAttempts) {
      totalAttempts++;
      if (attempt.allowed) {
        allowed++;
        if (attempt.succeeded === true) succeeded++;
        else if (attempt.succeeded === false) failed++;
      } else {
        blocked++;
      }
      toolCounts.set(attempt.toolName, (toolCounts.get(attempt.toolName) ?? 0) + 1);
    }
  }

  const topTools = Array.from(toolCounts.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([name, count]) => ({ name, count }));

  const successRate = allowed > 0 ? Math.round((succeeded / allowed) * 100) / 100 : 0;

  // Build chart data (daily buckets for periods <= 30d, weekly for longer)
  const useDailyBuckets = period === '7d' || period === '30d';
  const bucketMs = useDailyBuckets ? 24 * 60 * 60 * 1000 : 7 * 24 * 60 * 60 * 1000;
  const buckets: Array<{
    date: string;
    durationSecs: number;
    commits: number;
    linesAdded: number;
    linesRemoved: number;
    toolCalls: number;
  }> = [];

  // Create empty buckets
  const chartStart = periodStart ?? new Date(sessions[sessions.length - 1]?.startedAt ?? periodEnd);
  let bucketDate = new Date(chartStart);
  bucketDate.setHours(0, 0, 0, 0);

  while (bucketDate <= periodEnd) {
    buckets.push({
      date: bucketDate.toISOString().split('T')[0],
      durationSecs: 0,
      commits: 0,
      linesAdded: 0,
      linesRemoved: 0,
      toolCalls: 0,
    });
    bucketDate = new Date(bucketDate.getTime() + bucketMs);
  }

  // Fill buckets with session data
  for (const session of sessions) {
    if (!session.startedAt) continue;
    const sessionDate = session.startedAt.toISOString().split('T')[0];
    const bucket = buckets.find((b) => {
      if (useDailyBuckets) return b.date === sessionDate;
      // For weekly, check if session falls within the week
      const bDate = new Date(b.date);
      const sDate = new Date(sessionDate);
      return sDate >= bDate && sDate < new Date(bDate.getTime() + bucketMs);
    });

    if (bucket) {
      bucket.durationSecs += session.summary?.durationSecs ?? 0;
      bucket.commits += session.commits.length;
      bucket.toolCalls += session.toolAttempts.length;
      for (const commit of session.commits) {
        bucket.linesAdded += commit.linesAdded ?? 0;
        bucket.linesRemoved += commit.linesRemoved ?? 0;
      }
    }
  }

  return c.json({
    period,
    periodStart: (periodStart ?? chartStart).toISOString(),
    periodEnd: periodEnd.toISOString(),
    workout: {
      totalDurationSecs,
      sessionCount: sessions.length,
      avgBpm,
      maxBpm,
      minBpm,
      timeAboveThresholdSecs,
      timeBelowThresholdSecs,
    },
    coding: {
      totalCommits,
      linesAdded,
      linesRemoved,
      prsOpened,
      prsMerged,
      prsClosed,
      reposCount: repoSet.size,
    },
    tools: {
      totalAttempts,
      allowed,
      blocked,
      succeeded,
      failed,
      successRate,
      topTools,
    },
    chart: { buckets },
  });
});

// Get project list with aggregated stats
workout.get('/stats/projects', async (c) => {
  const userId = c.get('userId');
  const period = c.req.query('period') || 'all';
  const sort = c.req.query('sort') || 'recent';
  const limit = parseInt(c.req.query('limit') || '20', 10);
  const cursor = c.req.query('cursor');

  const periodStart = getPeriodStart(period);

  // Build where clause for sessions
  const sessionWhere: { userId: string; endedAt?: { not: null; gte?: Date } } = {
    userId,
    endedAt: { not: null },
  };
  if (periodStart) {
    sessionWhere.endedAt = { not: null, gte: periodStart };
  }

  // Get all sessions with commits
  const sessions = await prisma.workoutSession.findMany({
    where: sessionWhere,
    include: {
      summary: true,
      commits: {
        select: {
          repoOwner: true,
          repoName: true,
          linesAdded: true,
          linesRemoved: true,
        },
      },
      pullRequests: {
        select: {
          repoOwner: true,
          repoName: true,
          state: true,
        },
      },
      toolAttempts: {
        select: {
          allowed: true,
          succeeded: true,
        },
      },
    },
  });

  // Aggregate by repo
  const repoStats = new Map<
    string,
    {
      repoOwner: string;
      repoName: string;
      lastActiveAt: Date;
      sessionIds: Set<string>;
      totalDurationSecs: number;
      bpmSum: number;
      bpmCount: number;
      maxBpm: number;
      minBpm: number;
      timeAboveThresholdSecs: number;
      timeBelowThresholdSecs: number;
      commits: number;
      linesAdded: number;
      linesRemoved: number;
      prsOpened: number;
      prsMerged: number;
      prsClosed: number;
      toolAttempts: number;
      toolAllowed: number;
      toolBlocked: number;
    }
  >();

  for (const session of sessions) {
    // Track which repos this session touched
    const sessionRepos = new Set<string>();

    for (const commit of session.commits) {
      const key = `${commit.repoOwner}/${commit.repoName}`;
      sessionRepos.add(key);

      if (!repoStats.has(key)) {
        repoStats.set(key, {
          repoOwner: commit.repoOwner,
          repoName: commit.repoName,
          lastActiveAt: session.startedAt,
          sessionIds: new Set(),
          totalDurationSecs: 0,
          bpmSum: 0,
          bpmCount: 0,
          maxBpm: 0,
          minBpm: 999,
          timeAboveThresholdSecs: 0,
          timeBelowThresholdSecs: 0,
          commits: 0,
          linesAdded: 0,
          linesRemoved: 0,
          prsOpened: 0,
          prsMerged: 0,
          prsClosed: 0,
          toolAttempts: 0,
          toolAllowed: 0,
          toolBlocked: 0,
        });
      }

      const stats = repoStats.get(key)!;
      stats.commits++;
      stats.linesAdded += commit.linesAdded ?? 0;
      stats.linesRemoved += commit.linesRemoved ?? 0;

      if (session.startedAt > stats.lastActiveAt) {
        stats.lastActiveAt = session.startedAt;
      }
    }

    // Add PRs to repo stats
    for (const pr of session.pullRequests) {
      const key = `${pr.repoOwner}/${pr.repoName}`;
      sessionRepos.add(key);

      if (!repoStats.has(key)) {
        repoStats.set(key, {
          repoOwner: pr.repoOwner,
          repoName: pr.repoName,
          lastActiveAt: session.startedAt,
          sessionIds: new Set(),
          totalDurationSecs: 0,
          bpmSum: 0,
          bpmCount: 0,
          maxBpm: 0,
          minBpm: 999,
          timeAboveThresholdSecs: 0,
          timeBelowThresholdSecs: 0,
          commits: 0,
          linesAdded: 0,
          linesRemoved: 0,
          prsOpened: 0,
          prsMerged: 0,
          prsClosed: 0,
          toolAttempts: 0,
          toolAllowed: 0,
          toolBlocked: 0,
        });
      }

      const stats = repoStats.get(key)!;
      if (pr.state === 'open') stats.prsOpened++;
      else if (pr.state === 'merged') stats.prsMerged++;
      else if (pr.state === 'closed') stats.prsClosed++;
    }

    // Add session-level stats to each repo touched
    for (const repoKey of sessionRepos) {
      const stats = repoStats.get(repoKey)!;
      if (!stats.sessionIds.has(session.id)) {
        stats.sessionIds.add(session.id);

        if (session.summary) {
          stats.totalDurationSecs += session.summary.durationSecs;
          if (session.summary.avgBpm > 0) {
            stats.bpmSum += session.summary.avgBpm * session.summary.durationSecs;
            stats.bpmCount += session.summary.durationSecs;
          }
          if (session.summary.maxBpm > stats.maxBpm) {
            stats.maxBpm = session.summary.maxBpm;
          }
          if (session.summary.minBpm > 0 && session.summary.minBpm < stats.minBpm) {
            stats.minBpm = session.summary.minBpm;
          }
          stats.timeAboveThresholdSecs += session.summary.timeAboveThresholdSecs;
          stats.timeBelowThresholdSecs += session.summary.timeBelowThresholdSecs;
        }

        // Add tool attempts
        for (const attempt of session.toolAttempts) {
          stats.toolAttempts++;
          if (attempt.allowed) stats.toolAllowed++;
          else stats.toolBlocked++;
        }
      }
    }
  }

  // Convert to array and sort
  let projects = Array.from(repoStats.entries()).map(([key, stats]) => ({
    repoFullName: key,
    repoOwner: stats.repoOwner,
    repoName: stats.repoName,
    lastActiveAt: stats.lastActiveAt,
    workout: {
      totalDurationSecs: stats.totalDurationSecs,
      sessionCount: stats.sessionIds.size,
      avgBpm: stats.bpmCount > 0 ? Math.round(stats.bpmSum / stats.bpmCount) : 0,
      maxBpm: stats.maxBpm,
      minBpm: stats.minBpm === 999 ? 0 : stats.minBpm,
      timeAboveThresholdSecs: stats.timeAboveThresholdSecs,
      timeBelowThresholdSecs: stats.timeBelowThresholdSecs,
    },
    coding: {
      totalCommits: stats.commits,
      linesAdded: stats.linesAdded,
      linesRemoved: stats.linesRemoved,
      prsOpened: stats.prsOpened,
      prsMerged: stats.prsMerged,
      prsClosed: stats.prsClosed,
    },
    tools: {
      totalAttempts: stats.toolAttempts,
      allowed: stats.toolAllowed,
      blocked: stats.toolBlocked,
      successRate:
        stats.toolAllowed > 0 ? Math.round((stats.toolAllowed / stats.toolAttempts) * 100) / 100 : 0,
    },
  }));

  // Sort
  switch (sort) {
    case 'time':
      projects.sort((a, b) => b.workout.totalDurationSecs - a.workout.totalDurationSecs);
      break;
    case 'commits':
      projects.sort((a, b) => b.coding.totalCommits - a.coding.totalCommits);
      break;
    case 'recent':
    default:
      projects.sort((a, b) => b.lastActiveAt.getTime() - a.lastActiveAt.getTime());
  }

  // Pagination
  let startIndex = 0;
  if (cursor) {
    const cursorIndex = projects.findIndex((p) => p.repoFullName === cursor);
    if (cursorIndex >= 0) startIndex = cursorIndex + 1;
  }

  const pageProjects = projects.slice(startIndex, startIndex + limit + 1);
  const hasMore = pageProjects.length > limit;
  const items = hasMore ? pageProjects.slice(0, -1) : pageProjects;
  const nextCursor = hasMore ? items[items.length - 1]?.repoFullName : undefined;

  return c.json({
    projects: items.map((p) => ({
      ...p,
      lastActiveAt: p.lastActiveAt.toISOString(),
    })),
    hasMore,
    nextCursor,
  });
});

// Get single project detail
workout.get('/stats/projects/:repoFullName', async (c) => {
  const userId = c.get('userId');
  const repoFullName = decodeURIComponent(c.req.param('repoFullName'));
  const period = c.req.query('period') || 'all';
  const periodStart = getPeriodStart(period);

  const [repoOwner, repoName] = repoFullName.split('/');
  if (!repoOwner || !repoName) {
    return c.json({ error: 'Invalid repo format' }, 400);
  }

  // Build where clause for sessions
  const sessionWhere: { userId: string; endedAt?: { not: null; gte?: Date } } = {
    userId,
    endedAt: { not: null },
  };
  if (periodStart) {
    sessionWhere.endedAt = { not: null, gte: periodStart };
  }

  // Get sessions that touched this repo
  const sessions = await prisma.workoutSession.findMany({
    where: {
      ...sessionWhere,
      OR: [
        { commits: { some: { repoOwner, repoName } } },
        { pullRequests: { some: { repoOwner, repoName } } },
      ],
    },
    include: {
      summary: true,
      commits: {
        where: { repoOwner, repoName },
      },
      pullRequests: {
        where: { repoOwner, repoName },
      },
      toolAttempts: true,
    },
    orderBy: { startedAt: 'desc' },
  });

  if (sessions.length === 0) {
    return c.json({ error: 'Project not found' }, 404);
  }

  // Aggregate stats
  let totalDurationSecs = 0;
  let bpmSum = 0;
  let bpmCount = 0;
  let maxBpm = 0;
  let minBpm = 999;
  let timeAboveThresholdSecs = 0;
  let timeBelowThresholdSecs = 0;
  let totalCommits = 0;
  let linesAdded = 0;
  let linesRemoved = 0;
  let prsOpened = 0;
  let prsMerged = 0;
  let prsClosed = 0;
  let filesChanged = 0;
  let toolAttempts = 0;
  let toolAllowed = 0;
  let toolBlocked = 0;
  let toolSucceeded = 0;
  let toolFailed = 0;
  const toolCounts = new Map<string, number>();

  for (const session of sessions) {
    if (session.summary) {
      totalDurationSecs += session.summary.durationSecs;
      if (session.summary.avgBpm > 0) {
        bpmSum += session.summary.avgBpm * session.summary.durationSecs;
        bpmCount += session.summary.durationSecs;
      }
      if (session.summary.maxBpm > maxBpm) maxBpm = session.summary.maxBpm;
      if (session.summary.minBpm > 0 && session.summary.minBpm < minBpm) {
        minBpm = session.summary.minBpm;
      }
      timeAboveThresholdSecs += session.summary.timeAboveThresholdSecs;
      timeBelowThresholdSecs += session.summary.timeBelowThresholdSecs;
    }

    totalCommits += session.commits.length;
    for (const commit of session.commits) {
      linesAdded += commit.linesAdded ?? 0;
      linesRemoved += commit.linesRemoved ?? 0;
    }

    for (const pr of session.pullRequests) {
      if (pr.state === 'open') prsOpened++;
      else if (pr.state === 'merged') prsMerged++;
      else if (pr.state === 'closed') prsClosed++;
    }

    for (const attempt of session.toolAttempts) {
      toolAttempts++;
      if (attempt.allowed) {
        toolAllowed++;
        if (attempt.succeeded === true) toolSucceeded++;
        else if (attempt.succeeded === false) toolFailed++;
      } else {
        toolBlocked++;
      }
      toolCounts.set(attempt.toolName, (toolCounts.get(attempt.toolName) ?? 0) + 1);
    }
  }

  const avgBpm = bpmCount > 0 ? Math.round(bpmSum / bpmCount) : 0;
  if (minBpm === 999) minBpm = 0;

  const topTools = Array.from(toolCounts.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([name, count]) => ({ name, count }));

  const successRate = toolAllowed > 0 ? Math.round((toolSucceeded / toolAllowed) * 100) / 100 : 0;

  // Get files changed count
  const filesResult = await prisma.sessionCommitFile.count({
    where: {
      commit: {
        repoOwner,
        repoName,
        session: sessionWhere,
      },
    },
  });
  filesChanged = filesResult;

  // Build chart data
  const useDailyBuckets = period === '7d' || period === '30d';
  const bucketMs = useDailyBuckets ? 24 * 60 * 60 * 1000 : 7 * 24 * 60 * 60 * 1000;
  const buckets: Array<{
    date: string;
    durationSecs: number;
    commits: number;
    linesAdded: number;
    linesRemoved: number;
  }> = [];

  const chartStart =
    periodStart ?? new Date(sessions[sessions.length - 1]?.startedAt ?? new Date());
  let bucketDate = new Date(chartStart);
  bucketDate.setHours(0, 0, 0, 0);
  const chartEnd = new Date();

  while (bucketDate <= chartEnd) {
    buckets.push({
      date: bucketDate.toISOString().split('T')[0],
      durationSecs: 0,
      commits: 0,
      linesAdded: 0,
      linesRemoved: 0,
    });
    bucketDate = new Date(bucketDate.getTime() + bucketMs);
  }

  for (const session of sessions) {
    const sessionDate = session.startedAt.toISOString().split('T')[0];
    const bucket = buckets.find((b) => {
      if (useDailyBuckets) return b.date === sessionDate;
      const bDate = new Date(b.date);
      const sDate = new Date(sessionDate);
      return sDate >= bDate && sDate < new Date(bDate.getTime() + bucketMs);
    });

    if (bucket) {
      bucket.durationSecs += session.summary?.durationSecs ?? 0;
      bucket.commits += session.commits.length;
      for (const commit of session.commits) {
        bucket.linesAdded += commit.linesAdded ?? 0;
        bucket.linesRemoved += commit.linesRemoved ?? 0;
      }
    }
  }

  // Recent sessions
  const recentSessions = sessions.slice(0, 10).map((s) => ({
    id: s.id,
    startedAt: s.startedAt.toISOString(),
    endedAt: s.endedAt?.toISOString() ?? null,
    durationSecs: s.summary?.durationSecs ?? 0,
    avgBpm: s.summary?.avgBpm ?? 0,
    maxBpm: s.summary?.maxBpm ?? 0,
    commits: s.commits.length,
    linesAdded: s.commits.reduce((sum, c) => sum + (c.linesAdded ?? 0), 0),
    linesRemoved: s.commits.reduce((sum, c) => sum + (c.linesRemoved ?? 0), 0),
  }));

  return c.json({
    repoFullName,
    repoOwner,
    repoName,
    htmlUrl: `https://github.com/${repoFullName}`,
    lastActiveAt: sessions[0]?.startedAt.toISOString() ?? null,
    workout: {
      totalDurationSecs,
      sessionCount: sessions.length,
      avgBpm,
      maxBpm,
      minBpm,
      timeAboveThresholdSecs,
      timeBelowThresholdSecs,
    },
    coding: {
      totalCommits,
      linesAdded,
      linesRemoved,
      prsOpened,
      prsMerged,
      prsClosed,
      filesChanged,
    },
    tools: {
      totalAttempts: toolAttempts,
      allowed: toolAllowed,
      blocked: toolBlocked,
      succeeded: toolSucceeded,
      failed: toolFailed,
      successRate,
      topTools,
    },
    chart: { buckets },
    recentSessions,
    hasMoreSessions: sessions.length > 10,
    sessionsCursor: sessions.length > 10 ? sessions[9].id : null,
  });
});

// Get sessions for a specific project (paginated)
workout.get('/stats/projects/:repoFullName/sessions', async (c) => {
  const userId = c.get('userId');
  const repoFullName = decodeURIComponent(c.req.param('repoFullName'));
  const limit = parseInt(c.req.query('limit') || '20', 10);
  const cursor = c.req.query('cursor');

  const [repoOwner, repoName] = repoFullName.split('/');
  if (!repoOwner || !repoName) {
    return c.json({ error: 'Invalid repo format' }, 400);
  }

  const sessions = await prisma.workoutSession.findMany({
    where: {
      userId,
      endedAt: { not: null },
      OR: [
        { commits: { some: { repoOwner, repoName } } },
        { pullRequests: { some: { repoOwner, repoName } } },
      ],
    },
    orderBy: { startedAt: 'desc' },
    take: Math.min(limit, 50) + 1,
    ...(cursor && { cursor: { id: cursor }, skip: 1 }),
    include: {
      summary: true,
      commits: {
        where: { repoOwner, repoName },
      },
      pullRequests: {
        where: { repoOwner, repoName },
      },
    },
  });

  const hasMore = sessions.length > limit;
  const items = hasMore ? sessions.slice(0, -1) : sessions;
  const nextCursor = hasMore ? items[items.length - 1]?.id : undefined;

  return c.json({
    sessions: items.map((s) => ({
      id: s.id,
      startedAt: s.startedAt.toISOString(),
      endedAt: s.endedAt?.toISOString() ?? null,
      durationSecs: s.summary?.durationSecs ?? 0,
      avgBpm: s.summary?.avgBpm ?? 0,
      maxBpm: s.summary?.maxBpm ?? 0,
      minBpm: s.summary?.minBpm ?? 0,
      commits: s.commits.length,
      linesAdded: s.commits.reduce((sum, c) => sum + (c.linesAdded ?? 0), 0),
      linesRemoved: s.commits.reduce((sum, c) => sum + (c.linesRemoved ?? 0), 0),
      prs: s.pullRequests.length,
    })),
    hasMore,
    nextCursor,
  });
});

export { workout };
