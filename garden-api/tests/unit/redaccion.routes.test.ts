/**
 * POST /api/ai/improve-text (cualquier usuario con sesión) y su gemela histórica del cuidador.
 */
import express from 'express';
import request from 'supertest';

const mockMejorar = jest.fn();
jest.mock('../../src/agents/redaccion.agent', () => {
  class RedaccionRechazadaError extends Error {}
  return { mejorarRedaccion: (...a: unknown[]) => mockMejorar(...a), RedaccionRechazadaError };
});
// authMiddleware real exige JWT: se reemplaza por uno que deja pasar si llega Authorization.
jest.mock('../../src/middleware/auth.middleware', () => ({
  authMiddleware: (req: any, res: any, next: () => void) => {
    if (!req.headers.authorization) return res.status(401).json({ success: false });
    req.user = { userId: 'u1', role: 'CLIENT' };
    next();
  },
}));

import router from '../../src/modules/redaccion/redaccion.routes';
import { RedaccionRechazadaError } from '../../src/agents/redaccion.agent';

const app = express();
app.use(express.json());
app.use('/api/ai', router);

describe('POST /api/ai/improve-text', () => {
  beforeEach(() => mockMejorar.mockReset());

  it('exige sesión', async () => {
    const res = await request(app).post('/api/ai/improve-text').send({ field: 'ownerBio', text: 'x'.repeat(20) });
    expect(res.status).toBe(401);
    expect(mockMejorar).not.toHaveBeenCalled();
  });

  it('un dueño mejora la descripción de su mascota', async () => {
    mockMejorar.mockResolvedValue({ texto: 'Come a las 8 y le asustan los truenos.', modo: 'mejorado' });
    const res = await request(app)
      .post('/api/ai/improve-text')
      .set('Authorization', 'Bearer x')
      .send({ field: 'petRoutine', text: 'come a las 8 y le asustan los truenos' });
    expect(res.status).toBe(200);
    expect(res.body.data).toEqual({ text: 'Come a las 8 y le asustan los truenos.', mode: 'mejorado' });
    expect(mockMejorar).toHaveBeenCalledWith({ campo: 'petRoutine', texto: 'come a las 8 y le asustan los truenos', notas: undefined });
  });

  it('field es obligatorio', async () => {
    const res = await request(app).post('/api/ai/improve-text').set('Authorization', 'Bearer x').send({});
    expect(res.status).toBe(400);
  });

  it('texto que no sirve → 422 con el motivo', async () => {
    mockMejorar.mockRejectedValue(new RedaccionRechazadaError('No habla de mascotas'));
    const res = await request(app).post('/api/ai/improve-text').set('Authorization', 'Bearer x').send({ field: 'ownerBio', text: 'receta de cocina' });
    expect(res.status).toBe(422);
    expect(res.body.error.message).toBe('No habla de mascotas');
  });

  it('IA caída → 503 sin romper el formulario', async () => {
    mockMejorar.mockRejectedValue(new Error('network'));
    const res = await request(app).post('/api/ai/improve-text').set('Authorization', 'Bearer x').send({ field: 'faqIncludes', text: 'x'.repeat(20) });
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('AI_UNAVAILABLE');
  });
});
