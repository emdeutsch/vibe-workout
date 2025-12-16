/**
 * GitHub routes - manage GitHub connection for repo operations
 *
 * Token comes from Supabase OAuth (with repo scope) - no separate OAuth flow needed
 */

import { Hono } from 'hono';
import { prisma } from '@viberunner/db';
import { authMiddleware } from '../middleware/auth.js';
import { encrypt, decrypt } from '../lib/encryption.js';
import { getGitHubUser, createUserOctokit } from '../lib/github.js';

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

export { github };
