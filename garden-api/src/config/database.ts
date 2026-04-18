import { PrismaClient } from '@prisma/client';

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient | undefined };

/**
 * Appends Prisma connection-pool query params to the DATABASE_URL when they
 * are not already present in the URL.  Params are read from env so Render /
 * any other host can override them without touching code.
 *
 * Defaults: connection_limit=10, pool_timeout=30 (seconds)
 */
function buildConnectionUrl(): string {
  const raw = process.env.DATABASE_URL;
  if (!raw) throw new Error('DATABASE_URL is required');

  try {
    const url = new URL(raw);
    if (!url.searchParams.has('connection_limit')) {
      url.searchParams.set('connection_limit', process.env.DB_POOL_SIZE ?? '10');
    }
    if (!url.searchParams.has('pool_timeout')) {
      url.searchParams.set('pool_timeout', process.env.DB_POOL_TIMEOUT ?? '30');
    }
    return url.toString();
  } catch {
    // If URL parsing fails (e.g. non-standard format) return as-is and let
    // Prisma handle the error with a clear message.
    return raw;
  }
}

function createPrismaClient(): PrismaClient {
  return new PrismaClient({
    log: process.env.NODE_ENV === 'development' ? ['error', 'warn'] : ['error'],
    datasources: { db: { url: buildConnectionUrl() } },
  });
}

const prismaInstance = globalForPrisma.prisma ?? createPrismaClient();
if (process.env.NODE_ENV !== 'production') {
  globalForPrisma.prisma = prismaInstance;
}

export const prisma = prismaInstance;
export default prismaInstance;
