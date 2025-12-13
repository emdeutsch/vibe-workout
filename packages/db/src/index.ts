import { PrismaClient } from '@prisma/client';

// Global prisma instance for connection reuse
declare global {
  var prisma: PrismaClient | undefined;
}

export const prisma = globalThis.prisma ?? new PrismaClient();

if (process.env.NODE_ENV !== 'production') {
  globalThis.prisma = prisma;
}

export * from '@prisma/client';

// Re-export types for convenience
export type {
  Profile,
  WorkoutSession,
  HrSample,
  HrStatus,
  GithubAccount,
  GithubToken,
  GateRepo,
} from '@prisma/client';
