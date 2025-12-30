/**
 * Gate Repos routes - create and manage HR-gated repositories
 */

import { Hono } from 'hono';
import { prisma, type GateRepo } from '@vibeworkout/db';
import { authMiddleware } from '../middleware/auth.js';
import { decrypt } from '../lib/encryption.js';
import {
  createUserOctokit,
  createAppOctokit,
  createRepoFromTemplate,
  createEmptyRepo,
  createRepoInOrg,
  commitBootstrapFiles,
  type RepoCreationOptions,
} from '../lib/github.js';
import { config } from '../config.js';
import { buildSignalRef } from '@vibeworkout/shared';
import { generateBootstrapFiles } from '@vibeworkout/repo-bootstrap';
import type {
  CreateGateRepoRequest,
  CreateGateRepoResponse,
  GateRepoResponse,
} from '@vibeworkout/shared';

const gateRepos = new Hono();

// Apply auth to all routes
gateRepos.use('*', authMiddleware);

// List gate repos (verifies repos still exist on GitHub)
gateRepos.get('/', async (c) => {
  const userId = c.get('userId');

  // Get user's GitHub token for verification
  const githubToken = await prisma.githubToken.findUnique({
    where: { userId },
  });

  const repos = await prisma.gateRepo.findMany({
    where: { userId },
    orderBy: { createdAt: 'desc' },
  });

  // If no GitHub token, return repos without verification
  if (!githubToken) {
    const response: GateRepoResponse[] = repos.map((repo: GateRepo) => ({
      id: repo.id,
      owner: repo.owner,
      name: repo.name,
      user_key: repo.userKey,
      signal_ref: repo.signalRef,
      active: repo.active,
      github_app_installed: !!repo.githubAppInstallationId,
      created_at: repo.createdAt.toISOString(),
    }));
    return c.json({ repos: response });
  }

  // Verify each repo still exists on GitHub and check installation status
  const accessToken = decrypt(githubToken.encryptedAccessToken);
  const octokit = createUserOctokit(accessToken);
  const appOctokit = createAppOctokit();

  const verifiedRepos: typeof repos = [];
  const deletedRepoIds: string[] = [];

  await Promise.all(
    repos.map(async (repo: GateRepo) => {
      try {
        await octokit.rest.repos.get({
          owner: repo.owner,
          repo: repo.name,
        });

        // Check installation status via GitHub App API
        let installationId: number | null = null;
        try {
          const { data } = await appOctokit.rest.apps.getRepoInstallation({
            owner: repo.owner,
            repo: repo.name,
          });
          installationId = data.id;
        } catch {
          // 404 means not installed, which is fine
          installationId = null;
        }

        // Update DB if installation status changed
        if (repo.githubAppInstallationId !== installationId) {
          await prisma.gateRepo.update({
            where: { id: repo.id },
            data: { githubAppInstallationId: installationId },
          });
          repo.githubAppInstallationId = installationId;
        }

        verifiedRepos.push(repo);
      } catch (error: unknown) {
        if (error && typeof error === 'object' && 'status' in error && error.status === 404) {
          console.log(`Repo ${repo.owner}/${repo.name} no longer exists on GitHub, removing`);
          deletedRepoIds.push(repo.id);
        } else {
          // Other errors - keep the repo
          console.error(`Error checking repo ${repo.owner}/${repo.name}:`, error);
          verifiedRepos.push(repo);
        }
      }
    })
  );

  // Remove deleted repos from database
  if (deletedRepoIds.length > 0) {
    await prisma.gateRepo.deleteMany({
      where: { id: { in: deletedRepoIds } },
    });
  }

  const response: GateRepoResponse[] = verifiedRepos.map((repo: GateRepo) => ({
    id: repo.id,
    owner: repo.owner,
    name: repo.name,
    user_key: repo.userKey,
    signal_ref: repo.signalRef,
    active: repo.active,
    github_app_installed: !!repo.githubAppInstallationId,
    created_at: repo.createdAt.toISOString(),
  }));

  return c.json({ repos: response, deleted_count: deletedRepoIds.length });
});

// List repos available for workout selection (only repos with GitHub App installed)
// Also verifies repos still exist on GitHub and removes deleted ones
gateRepos.get('/selectable', async (c) => {
  const userId = c.get('userId');

  // Get user's GitHub token for verification
  const githubToken = await prisma.githubToken.findUnique({
    where: { userId },
  });

  const repos = await prisma.gateRepo.findMany({
    where: {
      userId,
      active: true,
      githubAppInstallationId: { not: null },
    },
    orderBy: { name: 'asc' },
    select: {
      id: true,
      owner: true,
      name: true,
    },
  });

  // If no GitHub token, return repos without verification
  if (!githubToken) {
    return c.json({
      repos: repos.map((repo: { id: string; owner: string; name: string }) => ({
        id: repo.id,
        owner: repo.owner,
        name: repo.name,
        full_name: `${repo.owner}/${repo.name}`,
      })),
    });
  }

  // Verify each repo still exists on GitHub
  const accessToken = decrypt(githubToken.encryptedAccessToken);
  const octokit = createUserOctokit(accessToken);

  const verifiedRepos: typeof repos = [];
  const deletedRepoIds: string[] = [];

  await Promise.all(
    repos.map(async (repo: { id: string; owner: string; name: string }) => {
      try {
        await octokit.rest.repos.get({
          owner: repo.owner,
          repo: repo.name,
        });
        // Repo exists
        verifiedRepos.push(repo);
      } catch (error: unknown) {
        // Check if repo was deleted (404)
        if (error && typeof error === 'object' && 'status' in error && error.status === 404) {
          console.log(
            `Repo ${repo.owner}/${repo.name} no longer exists on GitHub, marking for removal`
          );
          deletedRepoIds.push(repo.id);
        } else {
          // Other errors (rate limit, network) - keep the repo in the list
          console.error(`Error checking repo ${repo.owner}/${repo.name}:`, error);
          verifiedRepos.push(repo);
        }
      }
    })
  );

  // Remove deleted repos from database
  if (deletedRepoIds.length > 0) {
    await prisma.gateRepo.deleteMany({
      where: { id: { in: deletedRepoIds } },
    });
  }

  return c.json({
    repos: verifiedRepos.map((repo: { id: string; owner: string; name: string }) => ({
      id: repo.id,
      owner: repo.owner,
      name: repo.name,
      full_name: `${repo.owner}/${repo.name}`,
    })),
    deleted_count: deletedRepoIds.length,
  });
});

// Create a new gate repo
gateRepos.post('/', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json<CreateGateRepoRequest>();

  if (!body.name || body.name.length < 1) {
    return c.json({ error: 'Repository name is required' }, 400);
  }

  // Get GitHub credentials
  const [githubAccount, githubToken] = await Promise.all([
    prisma.githubAccount.findUnique({ where: { userId } }),
    prisma.githubToken.findUnique({ where: { userId } }),
  ]);

  if (!githubAccount || !githubToken) {
    return c.json({ error: 'GitHub not connected. Please connect GitHub first.' }, 400);
  }

  const accessToken = decrypt(githubToken.encryptedAccessToken);
  const octokit = createUserOctokit(accessToken);
  const userKey = githubAccount.username; // Use GitHub username as user_key
  const signalRef = buildSignalRef(userKey);

  // Build repo creation options from request
  const repoOptions: RepoCreationOptions = {
    has_issues: body.has_issues,
    has_wiki: body.has_wiki,
    has_projects: body.has_projects,
    license_template: body.license_template,
    gitignore_template: body.gitignore_template,
    allow_squash_merge: body.allow_squash_merge,
    allow_merge_commit: body.allow_merge_commit,
    allow_rebase_merge: body.allow_rebase_merge,
    delete_branch_on_merge: body.delete_branch_on_merge,
  };

  try {
    let repoInfo: { id: number; owner: string; name: string; html_url: string };

    // Try template first, fall back to empty repo
    try {
      // Note: Template repos don't support advanced settings, they inherit from template
      repoInfo = await createRepoFromTemplate(
        octokit,
        config.templateRepoOwner,
        config.templateRepoName,
        body.org || githubAccount.username, // Use org if specified
        body.name,
        body.description || 'vibeworkout HR-gated repository',
        body.private ?? true
      );
    } catch {
      // Template doesn't exist, create empty repo (with full settings support)
      if (body.org) {
        // Create in organization
        repoInfo = await createRepoInOrg(
          octokit,
          body.org,
          body.name,
          body.description || 'vibeworkout HR-gated repository',
          body.private ?? true,
          repoOptions
        );
      } else {
        // Create in user's account
        repoInfo = await createEmptyRepo(
          octokit,
          body.name,
          body.description || 'vibeworkout HR-gated repository',
          body.private ?? true,
          repoOptions
        );
      }

      // Commit bootstrap files
      const files = generateBootstrapFiles({
        userKey,
        publicKey: config.signerPublicKey,
        ttlSeconds: config.hrTtlSeconds,
      });
      await commitBootstrapFiles(
        octokit,
        repoInfo.owner,
        repoInfo.name,
        files,
        'Initialize vibeworkout HR gating'
      );
    }

    // Store gate repo record
    const gateRepo = await prisma.gateRepo.create({
      data: {
        userId,
        owner: repoInfo.owner,
        name: repoInfo.name,
        userKey,
        signalRef,
        active: true,
      },
    });

    // Build GitHub App installation URL
    // Note: GitHub doesn't support pre-selecting repos in the /new URL, user must select during install
    const installUrl = `https://github.com/apps/${config.githubAppSlug}/installations/new`;

    const response: CreateGateRepoResponse = {
      id: gateRepo.id,
      owner: repoInfo.owner,
      name: repoInfo.name,
      user_key: userKey,
      signal_ref: signalRef,
      html_url: repoInfo.html_url,
      needs_app_install: true, // User needs to install GitHub App
      install_url: body.auto_install_app ? installUrl : undefined,
    };

    return c.json(response, 201);
  } catch (error) {
    console.error('Create gate repo error:', error);
    return c.json(
      {
        error: error instanceof Error ? error.message : 'Failed to create repository',
      },
      500
    );
  }
});

// Get single gate repo
gateRepos.get('/:id', async (c) => {
  const userId = c.get('userId');
  const id = c.req.param('id');

  const repo = await prisma.gateRepo.findFirst({
    where: { id, userId },
  });

  if (!repo) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const response: GateRepoResponse = {
    id: repo.id,
    owner: repo.owner,
    name: repo.name,
    user_key: repo.userKey,
    signal_ref: repo.signalRef,
    active: repo.active,
    github_app_installed: !!repo.githubAppInstallationId,
    created_at: repo.createdAt.toISOString(),
  };

  return c.json(response);
});

// Update gate repo (activate/deactivate)
gateRepos.patch('/:id', async (c) => {
  const userId = c.get('userId');
  const id = c.req.param('id');
  const body = await c.req.json<{ active?: boolean }>();

  const repo = await prisma.gateRepo.findFirst({
    where: { id, userId },
  });

  if (!repo) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  const updated = await prisma.gateRepo.update({
    where: { id },
    data: {
      active: body.active ?? repo.active,
    },
  });

  return c.json({
    id: updated.id,
    active: updated.active,
    updated_at: updated.updatedAt.toISOString(),
  });
});

// Delete gate repo record (doesn't delete GitHub repo)
gateRepos.delete('/:id', async (c) => {
  const userId = c.get('userId');
  const id = c.req.param('id');

  const repo = await prisma.gateRepo.findFirst({
    where: { id, userId },
  });

  if (!repo) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  await prisma.gateRepo.delete({ where: { id } });

  return c.json({ deleted: true });
});

// Get GitHub App installation URL
gateRepos.get('/:id/install-url', async (c) => {
  const userId = c.get('userId');
  const id = c.req.param('id');

  const repo = await prisma.gateRepo.findFirst({
    where: { id, userId },
  });

  if (!repo) {
    return c.json({ error: 'Repository not found' }, 404);
  }

  // GitHub doesn't support pre-selecting repos via URL - user must select during install
  const installUrl = `https://github.com/apps/${config.githubAppSlug}/installations/new`;

  return c.json({
    install_url: installUrl,
    owner: repo.owner,
    name: repo.name,
  });
});

export { gateRepos };
