/**
 * API configuration from environment variables
 */

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function optionalEnv(name: string, defaultValue: string): string {
  return process.env[name] ?? defaultValue;
}

export const config = {
  // Server
  port: parseInt(optionalEnv('PORT', '3000'), 10),
  nodeEnv: optionalEnv('NODE_ENV', 'development'),

  // Supabase
  supabaseUrl: requireEnv('SUPABASE_URL'),
  supabaseAnonKey: requireEnv('SUPABASE_ANON_KEY'),
  supabaseServiceKey: requireEnv('SUPABASE_SERVICE_KEY'),

  // GitHub OAuth (for user repo creation)
  githubClientId: requireEnv('GITHUB_CLIENT_ID'),
  githubClientSecret: requireEnv('GITHUB_CLIENT_SECRET'),
  githubOAuthCallbackUrl: requireEnv('GITHUB_OAUTH_CALLBACK_URL'),

  // GitHub App (for pushing refs)
  githubAppId: requireEnv('GITHUB_APP_ID'),
  githubAppPrivateKey: requireEnv('GITHUB_APP_PRIVATE_KEY'),
  githubAppSlug: optionalEnv('GITHUB_APP_SLUG', 'viberunner-ai'),

  // Viberunner signing keys (Ed25519)
  signerPrivateKey: requireEnv('SIGNER_PRIVATE_KEY'),
  signerPublicKey: requireEnv('SIGNER_PUBLIC_KEY'),

  // Token encryption key (for GitHub tokens at rest)
  tokenEncryptionKey: requireEnv('TOKEN_ENCRYPTION_KEY'),

  // HR settings
  defaultHrThreshold: parseInt(optionalEnv('DEFAULT_HR_THRESHOLD', '100'), 10),
  hrTtlSeconds: parseInt(optionalEnv('HR_TTL_SECONDS', '15'), 10),

  // GitHub template repo (optional, for bootstrapping gate repos)
  templateRepoOwner: optionalEnv('TEMPLATE_REPO_OWNER', 'viberunner'),
  templateRepoName: optionalEnv('TEMPLATE_REPO_NAME', 'gate-repo-template'),
};

export type Config = typeof config;
