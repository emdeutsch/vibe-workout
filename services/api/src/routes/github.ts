/**
 * GitHub OAuth routes - connect GitHub account for repo creation
 */

import { Hono } from 'hono';
import { prisma } from '@viberunner/db';
import { authMiddleware } from '../middleware/auth.js';
import { encrypt, decrypt } from '../lib/encryption.js';
import {
  buildOAuthUrl,
  exchangeCodeForToken,
  getGitHubUser,
  createUserOctokit,
} from '../lib/github.js';
import { config as _config } from '../config.js';
import type { GitHubOAuthStartResponse, GitHubOAuthCallbackRequest } from '@viberunner/shared';

const github = new Hono();

// In-memory state store (use Redis in production)
const oauthStates = new Map<string, { userId: string; createdAt: number }>();

// Cleanup old states every 5 minutes
setInterval(
  () => {
    const now = Date.now();
    for (const [state, data] of oauthStates) {
      if (now - data.createdAt > 10 * 60 * 1000) {
        // 10 min expiry
        oauthStates.delete(state);
      }
    }
  },
  5 * 60 * 1000
);

// Start GitHub OAuth flow
github.get('/connect', authMiddleware, async (c) => {
  const userId = c.get('userId');

  // Generate state token
  const state = crypto.randomUUID();
  oauthStates.set(state, { userId, createdAt: Date.now() });

  const authorizationUrl = buildOAuthUrl(state);

  const response: GitHubOAuthStartResponse = {
    authorization_url: authorizationUrl,
    state,
  };

  return c.json(response);
});

// Handle OAuth callback
github.post('/callback', authMiddleware, async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json<GitHubOAuthCallbackRequest>();

  // Validate state
  const stateData = oauthStates.get(body.state);
  if (!stateData || stateData.userId !== userId) {
    return c.json({ error: 'Invalid or expired OAuth state' }, 400);
  }
  oauthStates.delete(body.state);

  try {
    // Exchange code for token
    const tokenResponse = await exchangeCodeForToken(body.code);

    // Get GitHub user info
    const githubUser = await getGitHubUser(tokenResponse.access_token);

    // Encrypt and store token
    const encryptedToken = encrypt(tokenResponse.access_token);
    const scopes = tokenResponse.scope.split(',').filter(Boolean);

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
    console.error('GitHub OAuth callback error:', error);
    return c.json(
      {
        error: error instanceof Error ? error.message : 'OAuth failed',
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

// Disconnect GitHub
github.delete('/disconnect', authMiddleware, async (c) => {
  const userId = c.get('userId');

  await prisma.githubToken.deleteMany({ where: { userId } });
  await prisma.githubAccount.deleteMany({ where: { userId } });

  return c.json({ disconnected: true });
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
