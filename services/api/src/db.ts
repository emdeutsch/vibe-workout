/**
 * Database operations using Prisma with Supabase
 */

import prisma from './lib/prisma.js';
import type { Profile, Device, GatedRepository, RunSession } from '@prisma/client';

export { prisma };
export type { Profile, Device, GatedRepository, RunSession };

// ============================================
// Profile Operations
// ============================================

export const profileDb = {
  async findById(id: string): Promise<Profile | null> {
    return prisma.profile.findUnique({ where: { id } });
  },

  async findByGithubId(githubUserId: number): Promise<Profile | null> {
    return prisma.profile.findUnique({ where: { githubUserId } });
  },

  async update(id: string, data: Partial<Profile>): Promise<Profile | null> {
    try {
      return await prisma.profile.update({
        where: { id },
        data,
      });
    } catch {
      return null;
    }
  },

  async linkGithub(
    userId: string,
    githubUserId: number,
    githubUsername: string,
    accessToken: string
  ): Promise<Profile | null> {
    try {
      return await prisma.profile.update({
        where: { id: userId },
        data: {
          githubUserId,
          githubUsername,
          githubAccessToken: accessToken,
        },
      });
    } catch {
      return null;
    }
  },

  async unlinkGithub(userId: string): Promise<Profile | null> {
    try {
      return await prisma.profile.update({
        where: { id: userId },
        data: {
          githubUserId: null,
          githubUsername: null,
          githubAccessToken: null,
        },
      });
    } catch {
      return null;
    }
  },

  async updatePaceThreshold(userId: string, paceThresholdSeconds: number): Promise<Profile | null> {
    try {
      return await prisma.profile.update({
        where: { id: userId },
        data: { paceThresholdSeconds },
      });
    } catch {
      return null;
    }
  },
};

// ============================================
// Device Operations
// ============================================

export const deviceDb = {
  async create(data: {
    userId: string;
    name: string;
    platform?: string;
    pushToken?: string;
  }): Promise<Device> {
    return prisma.device.create({
      data: {
        userId: data.userId,
        name: data.name,
        platform: data.platform ?? 'ios',
        pushToken: data.pushToken,
      },
    });
  },

  async findById(id: string): Promise<Device | null> {
    return prisma.device.findUnique({ where: { id } });
  },

  async findByUserId(userId: string): Promise<Device[]> {
    return prisma.device.findMany({ where: { userId } });
  },

  async update(id: string, data: Partial<Device>): Promise<Device | null> {
    try {
      return await prisma.device.update({
        where: { id },
        data,
      });
    } catch {
      return null;
    }
  },

  async updateHeartbeat(id: string, state: string): Promise<Device | null> {
    try {
      return await prisma.device.update({
        where: { id },
        data: {
          lastHeartbeat: new Date(),
          lastRunState: state,
        },
      });
    } catch {
      return null;
    }
  },

  async delete(id: string): Promise<boolean> {
    try {
      await prisma.device.delete({ where: { id } });
      return true;
    } catch {
      return false;
    }
  },
};

// ============================================
// Repository Operations
// ============================================

export const repoDb = {
  async create(data: {
    userId: string;
    githubRepoId: number;
    owner: string;
    name: string;
    fullName: string;
    rulesetId?: number;
    gatingEnabled?: boolean;
  }): Promise<GatedRepository> {
    return prisma.gatedRepository.create({
      data: {
        userId: data.userId,
        githubRepoId: data.githubRepoId,
        owner: data.owner,
        name: data.name,
        fullName: data.fullName,
        rulesetId: data.rulesetId,
        gatingEnabled: data.gatingEnabled ?? true,
      },
    });
  },

  async findById(id: string): Promise<GatedRepository | null> {
    return prisma.gatedRepository.findUnique({ where: { id } });
  },

  async findByUserId(userId: string): Promise<GatedRepository[]> {
    return prisma.gatedRepository.findMany({ where: { userId } });
  },

  async findByGithubRepoId(userId: string, githubRepoId: number): Promise<GatedRepository | null> {
    return prisma.gatedRepository.findUnique({
      where: {
        userId_githubRepoId: { userId, githubRepoId },
      },
    });
  },

  async update(id: string, data: Partial<GatedRepository>): Promise<GatedRepository | null> {
    try {
      return await prisma.gatedRepository.update({
        where: { id },
        data,
      });
    } catch {
      return null;
    }
  },

  async delete(id: string): Promise<boolean> {
    try {
      await prisma.gatedRepository.delete({ where: { id } });
      return true;
    } catch {
      return false;
    }
  },
};

// ============================================
// Run Session Operations
// ============================================

export const sessionDb = {
  async create(data: {
    userId: string;
    deviceId?: string;
    startedAt: Date;
    paceThresholdSeconds?: number;
    currentState?: string;
  }): Promise<RunSession> {
    return prisma.runSession.create({
      data: {
        userId: data.userId,
        deviceId: data.deviceId,
        startedAt: data.startedAt,
        paceThresholdSeconds: data.paceThresholdSeconds,
        currentState: data.currentState ?? 'RUNNING_LOCKED',
        lastHeartbeat: new Date(),
      },
    });
  },

  async findById(id: string): Promise<RunSession | null> {
    return prisma.runSession.findUnique({ where: { id } });
  },

  async findActiveByDeviceId(deviceId: string): Promise<RunSession | null> {
    return prisma.runSession.findFirst({
      where: {
        deviceId,
        endedAt: null,
      },
      orderBy: { startedAt: 'desc' },
    });
  },

  async findActiveByUserId(userId: string): Promise<RunSession | null> {
    return prisma.runSession.findFirst({
      where: {
        userId,
        endedAt: null,
      },
      orderBy: { startedAt: 'desc' },
    });
  },

  async update(id: string, data: Partial<RunSession>): Promise<RunSession | null> {
    try {
      return await prisma.runSession.update({
        where: { id },
        data,
      });
    } catch {
      return null;
    }
  },

  async endSession(
    id: string,
    data: {
      endedAt: Date;
      durationSeconds?: number;
      distanceMeters?: number;
      averagePaceSeconds?: number;
      caloriesBurned?: number;
      route?: unknown;
    }
  ): Promise<RunSession | null> {
    try {
      return await prisma.runSession.update({
        where: { id },
        data: {
          endedAt: data.endedAt,
          durationSeconds: data.durationSeconds,
          distanceMeters: data.distanceMeters,
          averagePaceSeconds: data.averagePaceSeconds,
          caloriesBurned: data.caloriesBurned,
          route: data.route as never,
          currentState: 'NOT_RUNNING',
        },
      });
    } catch {
      return null;
    }
  },

  /**
   * Get run history for a user
   */
  async getHistory(
    userId: string,
    options: { limit?: number; offset?: number } = {}
  ): Promise<RunSession[]> {
    return prisma.runSession.findMany({
      where: {
        userId,
        endedAt: { not: null },
      },
      orderBy: { startedAt: 'desc' },
      take: options.limit ?? 50,
      skip: options.offset ?? 0,
    });
  },

  /**
   * Get stats for a user
   */
  async getStats(userId: string): Promise<{
    totalRuns: number;
    totalDistanceMeters: number;
    totalDurationSeconds: number;
    averagePaceSeconds: number | null;
  }> {
    const result = await prisma.runSession.aggregate({
      where: {
        userId,
        endedAt: { not: null },
      },
      _count: true,
      _sum: {
        distanceMeters: true,
        durationSeconds: true,
      },
      _avg: {
        averagePaceSeconds: true,
      },
    });

    return {
      totalRuns: result._count,
      totalDistanceMeters: result._sum.distanceMeters ?? 0,
      totalDurationSeconds: result._sum.durationSeconds ?? 0,
      averagePaceSeconds: result._avg.averagePaceSeconds,
    };
  },
};

// ============================================
// Heartbeat Check Query
// ============================================

export type RunSessionWithProfile = RunSession & { profile: Profile };

/**
 * Get all active sessions that need heartbeat checking
 */
export async function getActiveSessionsForHeartbeatCheck(): Promise<RunSessionWithProfile[]> {
  return prisma.runSession.findMany({
    where: {
      endedAt: null,
    },
    include: {
      profile: true,
    },
  });
}
