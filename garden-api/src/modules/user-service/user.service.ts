import prisma from '../../config/database.js';
import type { UserPublic } from './user.types.js';

export async function getById(id: string): Promise<UserPublic | null> {
  const user = await prisma.user.findUnique({
    where: { id },
    select: {
      id: true,
      email: true,
      role: true,
      activeRole: true,
      firstName: true,
      lastName: true,
      phone: true,
      profilePicture: true,
      emailVerified: true,
      city: true,
      country: true,
      dateOfBirth: true,
      createdAt: true,
      clientProfile: {
        select: {
          address: true,
          bio: true,
        },
      },
    },
  });
  if (!user) return null;
  const { clientProfile, ...rest } = user as typeof user & { clientProfile?: { address?: string | null; bio?: string | null } | null };
  return {
    ...rest,
    address: clientProfile?.address ?? null,
    bio: clientProfile?.bio ?? null,
  } as UserPublic;
}
