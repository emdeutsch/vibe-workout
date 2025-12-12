/**
 * Authentication routes
 * Uses Supabase Auth - users sign up/in via Supabase client
 */

import { Router } from 'express';
import { z } from 'zod';
import { profileDb, deviceDb } from '../db.js';
import { requireAuth, generateOAuthState } from '../middleware/auth.js';
import { getConfig } from '../config.js';
import {
  getAuthorizationUrl,
  exchangeCodeForTokens,
  getAuthenticatedUser,
  type GitHubOAuthConfig,
} from '@viberunner/github';

const router = Router();

// Store OAuth states temporarily (use Redis in production)
const oauthStates = new Map<string, { userId?: string; expiresAt: number }>();

// Clean up expired states periodically
setInterval(() => {
  const now = Date.now();
  for (const [state, data] of oauthStates.entries()) {
    if (data.expiresAt < now) {
      oauthStates.delete(state);
    }
  }
}, 60000);

/**
 * Get current user info
 * Profile is auto-created by Supabase trigger on signup
 */
router.get('/me', requireAuth, async (req, res) => {
  try {
    const profile = await profileDb.findById(req.user!.id);
    if (!profile) {
      res.status(404).json({ error: 'Profile not found' });
      return;
    }

    res.json({
      id: profile.id,
      email: profile.email,
      githubUsername: profile.githubUsername,
      githubConnected: !!profile.githubUserId,
      paceThresholdSeconds: profile.paceThresholdSeconds,
    });
  } catch (error) {
    console.error('Error fetching profile:', error);
    res.status(500).json({ error: 'Failed to fetch profile' });
  }
});

/**
 * Update user settings
 */
const updateSettingsSchema = z.object({
  paceThresholdSeconds: z.number().min(180).max(1800).optional(), // 3:00 - 30:00 per mile
});

router.patch('/me', requireAuth, async (req, res) => {
  try {
    const body = updateSettingsSchema.parse(req.body);

    const profile = await profileDb.update(req.user!.id, body);
    if (!profile) {
      res.status(404).json({ error: 'Profile not found' });
      return;
    }

    res.json({
      id: profile.id,
      email: profile.email,
      githubUsername: profile.githubUsername,
      githubConnected: !!profile.githubUserId,
      paceThresholdSeconds: profile.paceThresholdSeconds,
    });
  } catch (error) {
    if (error instanceof z.ZodError) {
      res.status(400).json({ error: 'Invalid request', details: error.errors });
      return;
    }
    console.error('Error updating profile:', error);
    res.status(500).json({ error: 'Failed to update profile' });
  }
});

/**
 * Register a device for the current user
 */
const registerDeviceSchema = z.object({
  name: z.string().min(1).max(100),
  pushToken: z.string().optional(),
});

router.post('/devices', requireAuth, async (req, res) => {
  try {
    const body = registerDeviceSchema.parse(req.body);

    const device = await deviceDb.create({
      userId: req.user!.id,
      name: body.name,
      platform: 'ios',
      pushToken: body.pushToken,
    });

    res.status(201).json({
      device: {
        id: device.id,
        name: device.name,
        platform: device.platform,
      },
    });
  } catch (error) {
    if (error instanceof z.ZodError) {
      res.status(400).json({ error: 'Invalid request', details: error.errors });
      return;
    }
    console.error('Error registering device:', error);
    res.status(500).json({ error: 'Failed to register device' });
  }
});

/**
 * List user's devices
 */
router.get('/devices', requireAuth, async (req, res) => {
  try {
    const devices = await deviceDb.findByUserId(req.user!.id);
    res.json({
      devices: devices.map((d) => ({
        id: d.id,
        name: d.name,
        platform: d.platform,
        lastHeartbeat: d.lastHeartbeat,
      })),
    });
  } catch (error) {
    console.error('Error listing devices:', error);
    res.status(500).json({ error: 'Failed to list devices' });
  }
});

/**
 * Delete a device
 */
router.delete('/devices/:id', requireAuth, async (req, res) => {
  try {
    const device = await deviceDb.findById(req.params.id);
    if (!device) {
      res.status(404).json({ error: 'Device not found' });
      return;
    }

    if (device.userId !== req.user!.id) {
      res.status(403).json({ error: 'Not authorized' });
      return;
    }

    await deviceDb.delete(device.id);
    res.json({ success: true });
  } catch (error) {
    console.error('Error deleting device:', error);
    res.status(500).json({ error: 'Failed to delete device' });
  }
});

/**
 * Start GitHub OAuth flow
 */
router.get('/github', requireAuth, (req, res) => {
  const config = getConfig();
  const state = generateOAuthState();

  // Store state with user ID
  oauthStates.set(state, {
    userId: req.user!.id,
    expiresAt: Date.now() + 10 * 60 * 1000, // 10 minutes
  });

  const oauthConfig: GitHubOAuthConfig = {
    clientId: config.github.clientId,
    clientSecret: config.github.clientSecret,
    redirectUri: config.github.redirectUri,
  };

  const authUrl = getAuthorizationUrl(oauthConfig, state);
  res.json({ url: authUrl });
});

/**
 * GitHub OAuth callback
 */
router.get('/github/callback', async (req, res) => {
  const { code, state } = req.query;

  if (typeof code !== 'string' || typeof state !== 'string') {
    res.status(400).json({ error: 'Missing code or state' });
    return;
  }

  const stateData = oauthStates.get(state);
  if (!stateData || stateData.expiresAt < Date.now()) {
    res.status(400).json({ error: 'Invalid or expired state' });
    return;
  }

  oauthStates.delete(state);

  try {
    const config = getConfig();
    const oauthConfig: GitHubOAuthConfig = {
      clientId: config.github.clientId,
      clientSecret: config.github.clientSecret,
      redirectUri: config.github.redirectUri,
    };

    // Exchange code for tokens
    const tokens = await exchangeCodeForTokens(oauthConfig, code);

    // Get GitHub user info
    const githubUser = await getAuthenticatedUser(tokens.accessToken);

    // Link GitHub to user account
    if (stateData.userId) {
      await profileDb.linkGithub(
        stateData.userId,
        githubUser.id,
        githubUser.login,
        tokens.accessToken
      );
    }

    // Redirect back to app with success
    res.redirect(`${config.clientUrl}github-connected?success=true`);
  } catch (error) {
    console.error('GitHub OAuth error:', error);
    const config = getConfig();
    res.redirect(`${config.clientUrl}github-connected?error=oauth_failed`);
  }
});

/**
 * Disconnect GitHub
 */
router.delete('/github', requireAuth, async (req, res) => {
  try {
    const profile = await profileDb.findById(req.user!.id);
    if (!profile) {
      res.status(404).json({ error: 'Profile not found' });
      return;
    }

    await profileDb.unlinkGithub(profile.id);
    res.json({ success: true });
  } catch (error) {
    console.error('Error disconnecting GitHub:', error);
    res.status(500).json({ error: 'Failed to disconnect GitHub' });
  }
});

export default router;
