/**
 * GitHub API utilities for OAuth and App authentication
 */

import { Octokit } from 'octokit';
import { createAppAuth } from '@octokit/auth-app';
import { config } from '../config.js';

/**
 * Create Octokit client authenticated with user's OAuth token
 */
export function createUserOctokit(accessToken: string): Octokit {
  return new Octokit({ auth: accessToken });
}

/**
 * Create Octokit client authenticated with GitHub App installation token
 */
export async function createInstallationOctokit(installationId: number): Promise<Octokit> {
  const auth = createAppAuth({
    appId: config.githubAppId,
    privateKey: config.githubAppPrivateKey,
    installationId,
  });

  const { token } = await auth({ type: 'installation' });

  return new Octokit({ auth: token });
}

/**
 * Exchange OAuth code for access token
 */
export async function exchangeCodeForToken(code: string): Promise<{
  access_token: string;
  token_type: string;
  scope: string;
}> {
  const response = await fetch('https://github.com/login/oauth/access_token', {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      client_id: config.githubClientId,
      client_secret: config.githubClientSecret,
      code,
      redirect_uri: config.githubOAuthCallbackUrl,
    }),
  });

  if (!response.ok) {
    throw new Error(`GitHub OAuth token exchange failed: ${response.status}`);
  }

  const data = (await response.json()) as {
    access_token?: string;
    token_type?: string;
    scope?: string;
    error?: string;
    error_description?: string;
  };

  if (data.error) {
    throw new Error(`GitHub OAuth error: ${data.error_description || data.error}`);
  }

  if (!data.access_token) {
    throw new Error('No access token in response');
  }

  return {
    access_token: data.access_token,
    token_type: data.token_type || 'bearer',
    scope: data.scope || '',
  };
}

/**
 * Get GitHub user info from access token
 */
export async function getGitHubUser(accessToken: string): Promise<{
  id: number;
  login: string;
  name: string | null;
  email: string | null;
}> {
  const octokit = createUserOctokit(accessToken);
  const { data } = await octokit.rest.users.getAuthenticated();

  return {
    id: data.id,
    login: data.login,
    name: data.name,
    email: data.email,
  };
}

/**
 * Build GitHub OAuth authorization URL
 */
export function buildOAuthUrl(state: string): string {
  const params = new URLSearchParams({
    client_id: config.githubClientId,
    redirect_uri: config.githubOAuthCallbackUrl,
    scope: 'repo read:user user:email',
    state,
  });

  return `https://github.com/login/oauth/authorize?${params.toString()}`;
}

/**
 * Create a repo from template
 */
export async function createRepoFromTemplate(
  octokit: Octokit,
  templateOwner: string,
  templateRepo: string,
  newOwner: string,
  newName: string,
  description: string,
  isPrivate: boolean
): Promise<{ owner: string; name: string; html_url: string }> {
  const { data } = await octokit.rest.repos.createUsingTemplate({
    template_owner: templateOwner,
    template_repo: templateRepo,
    owner: newOwner,
    name: newName,
    description,
    private: isPrivate,
    include_all_branches: false,
  });

  return {
    owner: data.owner.login,
    name: data.name,
    html_url: data.html_url,
  };
}

// Repository creation options (beyond name, description, private)
export interface RepoCreationOptions {
  has_issues?: boolean;
  has_wiki?: boolean;
  has_projects?: boolean;
  license_template?: string;
  gitignore_template?: string;
  allow_squash_merge?: boolean;
  allow_merge_commit?: boolean;
  allow_rebase_merge?: boolean;
  delete_branch_on_merge?: boolean;
}

/**
 * Create an empty repo for the authenticated user
 */
export async function createEmptyRepo(
  octokit: Octokit,
  name: string,
  description: string,
  isPrivate: boolean,
  options?: RepoCreationOptions
): Promise<{ owner: string; name: string; html_url: string }> {
  const { data } = await octokit.rest.repos.createForAuthenticatedUser({
    name,
    description,
    private: isPrivate,
    auto_init: true, // Creates with README
    has_issues: options?.has_issues,
    has_wiki: options?.has_wiki,
    has_projects: options?.has_projects,
    license_template: options?.license_template,
    gitignore_template: options?.gitignore_template,
    allow_squash_merge: options?.allow_squash_merge,
    allow_merge_commit: options?.allow_merge_commit,
    allow_rebase_merge: options?.allow_rebase_merge,
    delete_branch_on_merge: options?.delete_branch_on_merge,
  });

  return {
    owner: data.owner.login,
    name: data.name,
    html_url: data.html_url,
  };
}

/**
 * Create a repo in an organization
 */
export async function createRepoInOrg(
  octokit: Octokit,
  org: string,
  name: string,
  description: string,
  isPrivate: boolean,
  options?: RepoCreationOptions
): Promise<{ owner: string; name: string; html_url: string }> {
  const { data } = await octokit.rest.repos.createInOrg({
    org,
    name,
    description,
    private: isPrivate,
    auto_init: true, // Creates with README
    has_issues: options?.has_issues,
    has_wiki: options?.has_wiki,
    has_projects: options?.has_projects,
    license_template: options?.license_template,
    gitignore_template: options?.gitignore_template,
    allow_squash_merge: options?.allow_squash_merge,
    allow_merge_commit: options?.allow_merge_commit,
    allow_rebase_merge: options?.allow_rebase_merge,
    delete_branch_on_merge: options?.delete_branch_on_merge,
  });

  return {
    owner: data.owner.login,
    name: data.name,
    html_url: data.html_url,
  };
}

/**
 * Commit bootstrap files to a repo
 */
export async function commitBootstrapFiles(
  octokit: Octokit,
  owner: string,
  repo: string,
  files: Array<{ path: string; content: string }>,
  message: string
): Promise<void> {
  // Get the default branch
  const { data: repoData } = await octokit.rest.repos.get({ owner, repo });
  const defaultBranch = repoData.default_branch;

  // Get the latest commit SHA
  const { data: refData } = await octokit.rest.git.getRef({
    owner,
    repo,
    ref: `heads/${defaultBranch}`,
  });
  const latestCommitSha = refData.object.sha;

  // Get the tree SHA of the latest commit
  const { data: commitData } = await octokit.rest.git.getCommit({
    owner,
    repo,
    commit_sha: latestCommitSha,
  });
  const baseTreeSha = commitData.tree.sha;

  // Create blobs for each file
  const blobs = await Promise.all(
    files.map(async (file) => {
      const { data: blob } = await octokit.rest.git.createBlob({
        owner,
        repo,
        content: Buffer.from(file.content).toString('base64'),
        encoding: 'base64',
      });
      return { path: file.path, sha: blob.sha };
    })
  );

  // Create a new tree
  const { data: newTree } = await octokit.rest.git.createTree({
    owner,
    repo,
    base_tree: baseTreeSha,
    tree: blobs.map((blob) => ({
      path: blob.path,
      mode: '100644' as const,
      type: 'blob' as const,
      sha: blob.sha,
    })),
  });

  // Create a new commit
  const { data: newCommit } = await octokit.rest.git.createCommit({
    owner,
    repo,
    message,
    tree: newTree.sha,
    parents: [latestCommitSha],
  });

  // Update the branch reference
  await octokit.rest.git.updateRef({
    owner,
    repo,
    ref: `heads/${defaultBranch}`,
    sha: newCommit.sha,
  });
}

/**
 * Update a custom ref with a blob payload (used by worker for HR signal)
 */
export async function updateSignalRef(
  octokit: Octokit,
  owner: string,
  repo: string,
  refName: string,
  payload: string
): Promise<void> {
  // Create a blob with the payload
  const { data: blob } = await octokit.rest.git.createBlob({
    owner,
    repo,
    content: Buffer.from(payload).toString('base64'),
    encoding: 'base64',
  });

  // Create a tree with just this blob
  const { data: tree } = await octokit.rest.git.createTree({
    owner,
    repo,
    tree: [
      {
        path: 'hr-signal.json',
        mode: '100644',
        type: 'blob',
        sha: blob.sha,
      },
    ],
  });

  // Create a commit (parentless since this is a signal ref)
  const { data: commit } = await octokit.rest.git.createCommit({
    owner,
    repo,
    message: 'Update HR signal',
    tree: tree.sha,
    parents: [],
  });

  // Try to update the ref, create if it doesn't exist
  try {
    await octokit.rest.git.updateRef({
      owner,
      repo,
      ref: refName.replace('refs/', ''),
      sha: commit.sha,
      force: true,
    });
  } catch (error: unknown) {
    // If ref doesn't exist, create it
    if (error && typeof error === 'object' && 'status' in error && error.status === 422) {
      await octokit.rest.git.createRef({
        owner,
        repo,
        ref: refName,
        sha: commit.sha,
      });
    } else {
      throw error;
    }
  }
}
