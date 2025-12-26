/**
 * viberunner API server
 *
 * Handles:
 * - User profiles and threshold settings
 * - Workout sessions and HR ingestion
 * - GitHub OAuth and connection
 * - Gate repo creation and management
 */

import { serve } from '@hono/node-server';
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { config } from './config.js';
import { profile } from './routes/profile.js';
import { workout } from './routes/workout.js';
import { github } from './routes/github.js';
import { gateRepos } from './routes/gate-repos.js';

const app = new Hono();

// Middleware
app.use('*', logger());
app.use(
  '*',
  cors({
    origin: '*', // Configure appropriately for production
    allowMethods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
    allowHeaders: ['Content-Type', 'Authorization'],
  })
);

// Health check
app.get('/health', (c) => {
  return c.json({
    status: 'ok',
    service: 'viberunner-api',
    timestamp: new Date().toISOString(),
  });
});

// API routes
app.route('/api/profile', profile);
app.route('/api/workout', workout);
app.route('/api/github', github);
app.route('/api/gate-repos', gateRepos);

// 404 handler
app.notFound((c) => {
  return c.json({ error: 'Not found' }, 404);
});

// Error handler
app.onError((err, c) => {
  console.error('Unhandled error:', err);
  return c.json(
    {
      error: config.nodeEnv === 'development' ? err.message : 'Internal server error',
    },
    500
  );
});

// Start server
console.log(`Starting viberunner API on port ${config.port}...`);
serve({
  fetch: app.fetch,
  port: config.port,
});
console.log(`viberunner API listening on http://localhost:${config.port}`);
