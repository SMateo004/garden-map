/**
 * API perfil cliente: my-profile (cargar perfil), PATCH (actualizar perfil de mascota).
 * Requiere token CLIENT.
 */

import { api } from './client';

export interface ClientProfileUser {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  phone: string | null;
}

/** Respuesta de GET /api/client/my-profile (perfil con user y pets[]). */
export interface ClientMyProfilePet {
  id: string;
  clientProfileId: string;
  name: string;
  breed: string | null;
  age: number | null;
  size: 'SMALL' | 'MEDIUM' | 'LARGE' | 'GIANT' | null;
  photoUrl: string | null;
  specialNeeds: string | null;
  notes: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface ClientMyProfileData {
  id: string;
  userId: string;
  address: string | null;
  phone: string | null;
  /** URL absoluta Cloudinary de la foto principal de mascota (primera mascota). */
  petPhoto: string | null;
  isComplete: boolean;
  createdAt: string;
  updatedAt: string;
  user: ClientProfileUser;
  pets: ClientMyProfilePet[];
}

/** GET /api/client/my-profile — perfil del cliente con user y lista de mascotas. */
export async function getClientMyProfile(): Promise<ClientMyProfileData | null> {
  const res = await api.get<{ success: boolean; data?: ClientMyProfileData }>('/api/client/my-profile');
  if (!res.data?.success || res.status === 404) return null;
  return res.data.data ?? null;
}

export interface ClientProfileResponse {
  id: string;
  userId: string;
  address: string | null;
  phone: string | null;
  petName: string | null;
  petBreed: string | null;
  petAge: number | null;
  petSize: 'SMALL' | 'MEDIUM' | 'LARGE' | 'GIANT' | null;
  petPhoto: string | null;
  specialNeeds: string | null;
  notes: string | null;
  isComplete: boolean;
  createdAt: string;
  updatedAt: string;
  user: ClientProfileUser;
}

export interface PatchClientProfilePayload {
  address?: string;
  phone?: string;
  petName?: string;
  petBreed?: string;
  petAge?: number;
  petSize?: 'SMALL' | 'MEDIUM' | 'LARGE' | 'GIANT';
  petPhoto?: string;
  specialNeeds?: string;
  notes?: string;
}

/** GET /api/client/my-profile */
export async function getMyClientProfile(): Promise<ClientProfileResponse | null> {
  const res = await api.get<{ success: boolean; data?: ClientProfileResponse }>('/api/client/my-profile');
  if (!res.data.success || res.status === 404) return null;
  return res.data.data ?? null;
}

/** Respuesta de PATCH /api/client/profile (incluye petPhoto para mostrar de inmediato). */
export interface PatchClientProfileResult {
  profileId: string;
  isComplete: boolean;
  updatedAt: string;
  petPhoto?: string | null;
}

/** PATCH /api/client/profile */
export async function patchClientProfile(
  payload: PatchClientProfilePayload
): Promise<PatchClientProfileResult> {
  const res = await api.patch<{
    success: boolean;
    data: PatchClientProfileResult;
  }>('/api/client/profile', payload);
  if (!res.data.success)
    throw new Error((res.data as { error?: { message?: string } }).error?.message ?? 'Error al guardar');
  return res.data.data;
}

/** POST /api/upload/pet-photo - Sube una foto de mascota */
export async function uploadPetPhoto(file: File): Promise<string> {
  const formData = new FormData();
  formData.append('photo', file);
  const res = await api.postForm<{ success: boolean; data?: { url: string } }>(
    '/api/upload/pet-photo',
    formData
  );
  if (!res.data.success || !res.data.data?.url) {
    throw new Error('Error al subir foto de mascota');
  }
  return res.data.data.url;
}
