/**
 * GitHub utilities for worker - pushing HR signal refs
 */

import { Octokit } from 'octokit';
import { createAppAuth } from '@octokit/auth-app';
import { config } from './config.js';

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
 * Update a custom ref with a payload (HR signal)
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
  const shortRef = refName.replace('refs/', '');
  try {
    await octokit.rest.git.updateRef({
      owner,
      repo,
      ref: shortRef,
      sha: commit.sha,
      force: true,
    });
  } catch (error: unknown) {
    // If ref doesn't exist (404), create it
    if (error && typeof error === 'object' && 'status' in error && error.status === 404) {
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
