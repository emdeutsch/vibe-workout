/**
 * API Configuration
 */

import { z } from 'zod';

const envSchema = z.object({
  // Server
  PORT: z.string().default('3000'),
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),

  // Supabase
  SUPABASE_URL: z.string().url(),
  SUPABASE_ANON_KEY: z.string(),
  SUPABASE_SERVICE_ROLE_KEY: z.string(),

  // Database (Prisma)
  DATABASE_URL: z.string(),
  DIRECT_URL: z.string(),

  // GitHub OAuth (for linking GitHub accounts)
  GITHUB_CLIENT_ID: z.string(),
  GITHUB_CLIENT_SECRET: z.string(),
  GITHUB_REDIRECT_URI: z.string().url(),

  // Client app
  CLIENT_URL: z.string().default('viberunner://'),

  // Heartbeat settings
  HEARTBEAT_TIMEOUT_MS: z.string().default('30000'),
  HEARTBEAT_CHECK_INTERVAL_MS: z.string().default('10000'),
});

function loadConfig() {
  const parsed = envSchema.safeParse(process.env);

  if (!parsed.success) {
    console.error('Invalid environment variables:');
    console.error(parsed.error.format());

    if (process.env['NODE_ENV'] !== 'production') {
      console.error('\nCreate a .env file with:');
      console.error(`
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
DATABASE_URL=postgresql://postgres:password@db.your-project.supabase.co:6543/postgres?pgbouncer=true
DIRECT_URL=postgresql://postgres:password@db.your-project.supabase.co:5432/postgres
GITHUB_CLIENT_ID=your-github-oauth-client-id
GITHUB_CLIENT_SECRET=your-github-oauth-client-secret
GITHUB_REDIRECT_URI=http://localhost:3000/auth/github/callback
      `);
    }

    throw new Error('Invalid configuration');
  }

  return {
    port: parseInt(parsed.data.PORT, 10),
    nodeEnv: parsed.data.NODE_ENV,
    supabase: {
      url: parsed.data.SUPABASE_URL,
      anonKey: parsed.data.SUPABASE_ANON_KEY,
      serviceRoleKey: parsed.data.SUPABASE_SERVICE_ROLE_KEY,
    },
    github: {
      clientId: parsed.data.GITHUB_CLIENT_ID,
      clientSecret: parsed.data.GITHUB_CLIENT_SECRET,
      redirectUri: parsed.data.GITHUB_REDIRECT_URI,
    },
    clientUrl: parsed.data.CLIENT_URL,
    heartbeat: {
      timeoutMs: parseInt(parsed.data.HEARTBEAT_TIMEOUT_MS, 10),
      checkIntervalMs: parseInt(parsed.data.HEARTBEAT_CHECK_INTERVAL_MS, 10),
    },
  };
}

export type Config = ReturnType<typeof loadConfig>;

let _config: Config | null = null;

export function getConfig(): Config {
  if (!_config) {
    _config = loadConfig();
  }
  return _config;
}
