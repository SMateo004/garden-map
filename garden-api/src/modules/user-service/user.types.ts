import type { UserRole } from '@prisma/client';

export interface UserPublic {
  id: string;
  email: string;
  role: UserRole;
  activeRole?: UserRole | null;
  firstName: string;
  lastName: string;
  phone: string;
  profilePicture: string | null;
  city: string | null;
  country: string | null;
  emailVerified: boolean;
  createdAt: Date;
}
