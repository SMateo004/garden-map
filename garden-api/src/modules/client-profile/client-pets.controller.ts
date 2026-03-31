import { Request, Response } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import * as clientPetsService from './client-pets.service.js';
import { createPetBodySchema, patchPetBodySchema } from './client-pets.validation.js';

/** GET /api/client/pets — lista de mascotas del cliente logueado (role CLIENT). */
export const getPets = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const pets = await clientPetsService.getPetsByUserId(userId);
  res.json({ success: true, data: pets });
});

/** POST /api/client/pets — crear mascota. Actualiza isComplete del perfil. */
export const createPet = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const body = createPetBodySchema.parse(req.body);
  const pet = await clientPetsService.createPet(userId, body);
  res.status(201).json({ success: true, data: pet });
});

/** PATCH /api/client/pets/:petId — editar mascota. Valida que pertenezca al usuario. */
export const patchPet = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const petId = req.params.petId!;
  const body = patchPetBodySchema.parse(req.body);
  const pet = await clientPetsService.updatePet(userId, petId, body);
  res.json({ success: true, data: pet });
});

/** DELETE /api/client/pets/:petId — eliminar mascota. Valida que pertenezca al usuario. */
export const deletePet = asyncHandler(async (req: Request, res: Response) => {
  const userId = req.user!.userId;
  const petId = req.params.petId!;
  await clientPetsService.deletePet(userId, petId);
  res.json({ success: true, data: { deleted: true } });
});
