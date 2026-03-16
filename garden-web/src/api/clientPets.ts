/**
 * API mascotas del cliente: GET /api/client/pets.
 * Requiere token CLIENT.
 */

import { api } from './client';

export type PetSize = 'SMALL' | 'MEDIUM' | 'LARGE' | 'GIANT';

export interface ClientPetListItem {
  id: string;
  name: string;
  breed: string | null;
  age: number | null;
  size: PetSize | null;
  photoUrl: string | null;
  specialNeeds: string | null;
  notes?: string | null;
}

export function getClientPets(): Promise<{ success: boolean; data: ClientPetListItem[] }> {
  return api.get('/api/client/pets').then((r) => r.data);
}

export interface CreateClientPetBody {
  name: string;
  breed?: string;
  age?: number | null;
  size?: PetSize | null;
  photoUrl?: string | null;
  specialNeeds?: string | null;
  notes?: string | null;
}

/** POST /api/client/pets — crear mascota. Incluye photoUrl para guardar la foto. */
export function createClientPet(
  body: CreateClientPetBody
): Promise<{ success: boolean; data: ClientPetListItem }> {
  return api.post('/api/client/pets', body).then((r) => r.data);
}

export interface PatchClientPetBody {
  name?: string;
  breed?: string;
  age?: number | null;
  size?: PetSize | null;
  photoUrl?: string | null;
  specialNeeds?: string | null;
  notes?: string | null;
}

/** PATCH /api/client/pets/:petId */
export function patchClientPet(
  petId: string,
  body: PatchClientPetBody
): Promise<{ success: boolean; data: ClientPetListItem }> {
  return api.patch(`/api/client/pets/${petId}`, body).then((r) => r.data);
}
