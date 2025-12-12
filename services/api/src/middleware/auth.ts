/**
 * Authentication middleware using Supabase Auth
 */

import { Request, Response, NextFunction } from 'express';
import { verifyToken } from '../lib/supabase.js';
import { profileDb } from '../db.js';

declare global {
  namespace Express {
    interface Request {
      user?: {
        id: string;
        email: string;
      };
      deviceId?: string;
    }
  }
}

/**
 * Require valid Supabase authentication
 */
export async function requireAuth(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const authHeader = req.headers.authorization;

  if (!authHeader?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Missing authorization header' });
    return;
  }

  const token = authHeader.slice(7);

  try {
    // Verify token with Supabase
    const supabaseUser = await verifyToken(token);
    if (!supabaseUser) {
      res.status(401).json({ error: 'Invalid token' });
      return;
    }

    // Get device ID from custom header (set by mobile app)
    const deviceId = req.headers['x-device-id'] as string | undefined;

    req.user = {
      id: supabaseUser.id,
      email: supabaseUser.email ?? '',
    };
    req.deviceId = deviceId;

    next();
  } catch (error) {
    console.error('Auth error:', error);
    res.status(401).json({ error: 'Invalid token' });
  }
}

/**
 * Optional auth - sets user if token present, but doesn't require it
 */
export async function optionalAuth(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const authHeader = req.headers.authorization;

  if (!authHeader?.startsWith('Bearer ')) {
    next();
    return;
  }

  const token = authHeader.slice(7);

  try {
    const supabaseUser = await verifyToken(token);
    if (supabaseUser) {
      req.user = {
        id: supabaseUser.id,
        email: supabaseUser.email ?? '',
      };
      req.deviceId = req.headers['x-device-id'] as string | undefined;
    }
  } catch {
    // Ignore errors - auth is optional
  }

  next();
}

/**
 * Generate a random state for OAuth
 */
export function generateOAuthState(): string {
  return Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString(
    'base64url'
  );
}
