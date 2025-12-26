/**
 * GitHub routes - manage GitHub connection for repo operations
 *
 * Token comes from Supabase OAuth (with repo scope) - no separate OAuth flow needed
 */

import { Hono } from 'hono';
import { prisma } from '@viberunner/db';
import { authMiddleware } from '../middleware/auth.js';
import { encrypt, decrypt } from '../lib/encryption.js';
import { getGitHubUser, createUserOctokit, createInstallationOctokit } from '../lib/github.js';

const github = new Hono();

// Sync GitHub provider token from Supabase OAuth
github.post('/sync-token', authMiddleware, async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json<{ provider_token: string }>();

  if (!body.provider_token) {
    return c.json({ error: 'provider_token is required' }, 400);
  }

  try {
    // Validate token by fetching user info
    const githubUser = await getGitHubUser(body.provider_token);

    // Encrypt and store token
    const encryptedToken = encrypt(body.provider_token);
    // Supabase OAuth with repo scope grants these
    const scopes = ['repo', 'read:user', 'user:email'];

    // Upsert GitHub account
    await prisma.githubAccount.upsert({
      where: { userId },
      update: {
        githubUserId: githubUser.id,
        username: githubUser.login,
      },
      create: {
        userId,
        githubUserId: githubUser.id,
        username: githubUser.login,
      },
    });

    // Upsert token
    await prisma.githubToken.upsert({
      where: { userId },
      update: {
        encryptedAccessToken: encryptedToken,
        scopes,
      },
      create: {
        userId,
        encryptedAccessToken: encryptedToken,
        scopes,
      },
    });

    return c.json({
      success: true,
      github_username: githubUser.login,
    });
  } catch (error) {
    console.error('GitHub token sync error:', error);
    return c.json(
      {
        error: error instanceof Error ? error.message : 'Token sync failed',
      },
      400
    );
  }
});

// Check GitHub connection status
github.get('/status', authMiddleware, async (c) => {
  const userId = c.get('userId');

  const account = await prisma.githubAccount.findUnique({
    where: { userId },
  });

  const token = await prisma.githubToken.findUnique({
    where: { userId },
    select: { scopes: true, updatedAt: true },
  });

  if (!account || !token) {
    return c.json({
      connected: false,
    });
  }

  return c.json({
    connected: true,
    username: account.username,
    scopes: token.scopes,
    updated_at: token.updatedAt.toISOString(),
  });
});

// Disconnect GitHub (clear stored token)
github.delete('/disconnect', authMiddleware, async (c) => {
  const userId = c.get('userId');

  await prisma.githubToken.deleteMany({ where: { userId } });
  await prisma.githubAccount.deleteMany({ where: { userId } });

  return c.json({ disconnected: true });
});

// List user's organizations
github.get('/orgs', authMiddleware, async (c) => {
  const userId = c.get('userId');
  console.log('[orgs] Fetching orgs for user:', userId);

  const token = await prisma.githubToken.findUnique({
    where: { userId },
  });

  if (!token) {
    console.log('[orgs] No GitHub token found');
    return c.json({ error: 'GitHub not connected' }, 400);
  }

  console.log('[orgs] Token scopes:', token.scopes);

  try {
    const accessToken = decrypt(token.encryptedAccessToken);
    const octokit = createUserOctokit(accessToken);

    const { data: orgs } = await octokit.rest.orgs.listForAuthenticatedUser({
      per_page: 100,
    });

    console.log(
      '[orgs] Found',
      orgs.length,
      'organizations:',
      orgs.map((o) => o.login)
    );

    return c.json({
      orgs: orgs.map((org) => ({
        id: org.id,
        login: org.login,
        avatar_url: org.avatar_url,
      })),
    });
  } catch (error) {
    console.error('[orgs] GitHub orgs list error:', error);
    return c.json({ error: 'Failed to list organizations' }, 500);
  }
});

// List user's repositories (for selection)
github.get('/repos', authMiddleware, async (c) => {
  const userId = c.get('userId');

  const token = await prisma.githubToken.findUnique({
    where: { userId },
  });

  if (!token) {
    return c.json({ error: 'GitHub not connected' }, 400);
  }

  try {
    const accessToken = decrypt(token.encryptedAccessToken);
    const octokit = createUserOctokit(accessToken);

    const { data: repos } = await octokit.rest.repos.listForAuthenticatedUser({
      sort: 'updated',
      per_page: 100,
    });

    return c.json({
      repos: repos.map((repo) => ({
        id: repo.id,
        full_name: repo.full_name,
        name: repo.name,
        owner: repo.owner.login,
        private: repo.private,
        html_url: repo.html_url,
        description: repo.description,
        updated_at: repo.updated_at,
      })),
    });
  } catch (error) {
    console.error('GitHub repos list error:', error);
    return c.json({ error: 'Failed to list repositories' }, 500);
  }
});

// DEBUG: Test GitHub App installation and commit fetching (temporarily public for testing)
github.get('/debug-commits/:repoId', async (c) => {
  const repoId = c.req.param('repoId');

  const repo = await prisma.gateRepo.findFirst({
    where: { id: repoId },
  });

  if (!repo) {
    return c.json({ error: 'Repo not found' }, 404);
  }

  const debugInfo: Record<string, unknown> = {
    repo: {
      id: repo.id,
      owner: repo.owner,
      name: repo.name,
      installationId: repo.githubAppInstallationId,
      activeSessionId: repo.activeSessionId,
    },
  };

  if (!repo.githubAppInstallationId) {
    debugInfo.error = 'No GitHub App installation ID';
    return c.json(debugInfo);
  }

  try {
    // Test creating installation octokit
    debugInfo.step = 'creating_octokit';
    const octokit = await createInstallationOctokit(repo.githubAppInstallationId);
    debugInfo.octokitCreated = true;

    // Test fetching commits
    debugInfo.step = 'fetching_commits';
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(); // Last 24 hours
    const { data: commits } = await octokit.rest.repos.listCommits({
      owner: repo.owner,
      repo: repo.name,
      since,
      per_page: 10,
    });

    debugInfo.commitsFound = commits.length;
    debugInfo.commits = commits.map((c) => ({
      sha: c.sha.substring(0, 7),
      message: c.commit.message?.substring(0, 50),
      date: c.commit.author?.date,
    }));

    // Test fetching a single commit with stats
    if (commits.length > 0) {
      debugInfo.step = 'fetching_commit_details';
      const { data: fullCommit } = await octokit.rest.repos.getCommit({
        owner: repo.owner,
        repo: repo.name,
        ref: commits[0].sha,
      });

      debugInfo.firstCommitStats = {
        additions: fullCommit.stats?.additions,
        deletions: fullCommit.stats?.deletions,
        filesCount: fullCommit.files?.length,
      };
    }

    debugInfo.success = true;
  } catch (error) {
    debugInfo.error = error instanceof Error ? error.message : String(error);
    debugInfo.errorStack = error instanceof Error ? error.stack : undefined;
  }

  return c.json(debugInfo);
});

export { github };
