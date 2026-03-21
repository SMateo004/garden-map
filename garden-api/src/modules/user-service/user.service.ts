import prisma from '../../config/database.js';
import type { UserPublic } from './user.types.js';

export async function getById(id: string): Promise<UserPublic | null> {
  const user = await prisma.user.findUnique({
    where: { id },
    select: {
      id: true,
      email: true,
      role: true,
      firstName: true,
      lastName: true,
      phone: true,
      profilePicture: true,
      emailVerified: true,
      createdAt: true,
    },
  });
  return user as UserPublic | null;
}
