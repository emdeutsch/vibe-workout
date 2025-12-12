/**
 * VibeRunner API Server
 */

import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { getConfig } from './config.js';
import { prisma } from './db.js';
import authRoutes from './routes/auth.js';
import repoRoutes from './routes/repos.js';
import heartbeatRoutes from './routes/heartbeat.js';
import runsRoutes from './routes/runs.js';
import { startHeartbeatChecker, stopHeartbeatChecker } from './services/heartbeat-checker.js';

// Load environment variables
import { config as dotenvConfig } from 'dotenv';
dotenvConfig();

const app = express();

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());

// Health check
app.get('/health', async (req, res) => {
  try {
    // Test database connection
    await prisma.$queryRaw`SELECT 1`;
    res.json({
      status: 'ok',
      timestamp: Date.now(),
      version: '0.1.0',
      database: 'connected',
    });
  } catch {
    res.status(503).json({
      status: 'degraded',
      timestamp: Date.now(),
      version: '0.1.0',
      database: 'disconnected',
    });
  }
});

// API Routes
app.use('/auth', authRoutes);
app.use('/repos', repoRoutes);
app.use('/heartbeat', heartbeatRoutes);
app.use('/runs', runsRoutes);

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// Error handler
app.use((err: Error, req: express.Request, res: express.Response, next: express.NextFunction) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// Start server
async function start(): Promise<void> {
  try {
    const config = getConfig();

    // Test database connection
    await prisma.$connect();
    console.log('Database connected');

    // Start heartbeat checker
    startHeartbeatChecker();

    app.listen(config.port, () => {
      console.log(`VibeRunner API running on port ${config.port}`);
      console.log(`Environment: ${config.nodeEnv}`);
    });

    // Graceful shutdown
    const shutdown = async (signal: string) => {
      console.log(`${signal} received, shutting down...`);
      stopHeartbeatChecker();
      await prisma.$disconnect();
      process.exit(0);
    };

    process.on('SIGTERM', () => void shutdown('SIGTERM'));
    process.on('SIGINT', () => void shutdown('SIGINT'));
  } catch (error) {
    console.error('Failed to start server:', error);
    await prisma.$disconnect();
    process.exit(1);
  }
}

start();

export { app };
