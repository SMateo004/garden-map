import type { UserRole } from '@prisma/client';

export interface UserPublic {
  id: string;
  email: string;
  role: UserRole;
  firstName: string;
  lastName: string;
  phone: string;
  profilePicture: string | null;
  createdAt: Date;
}
