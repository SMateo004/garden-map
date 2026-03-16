/**
 * API verification: generate-link, validate, submit (Rekognition).
 */

import { api } from './client';

const BASE = '/api/verification';

export interface GenerateLinkResponse {
  url: string;
  token: string;
  expiresIn: string;
}

/** POST /api/verification/generate-link — auth CAREGIVER */
export async function generateVerificationLink(): Promise<GenerateLinkResponse> {
  const res = await api.post<{ success: boolean; data: GenerateLinkResponse }>(`${BASE}/generate-link`);
  if (!res.data.success || !res.data.data) throw new Error('Error al generar enlace');
  return res.data.data;
}

export interface ValidateResponse {
  valid: boolean;
  userId?: string;
  message?: string;
}

/** GET /api/verification/validate?token= */
export async function validateVerificationToken(token: string): Promise<ValidateResponse> {
  const res = await api.get<{ success: boolean; data: ValidateResponse }>(`${BASE}/validate`, {
    params: { token },
  });
  if (!res.data.success) throw new Error('Error al validar');
  return res.data.data;
}

export interface SubmitResponse {
  similarity: number;
  livenessScore?: number;
  documentConfidence?: number;
  identityScore?: number;
  status: string;
  message: string;
}

/** POST /api/verification/submit — multipart: selfie, ciFront, ciBack, livenessFrames (3–5). */
export async function submitVerification(
  token: string,
  selfie: File,
  ciFront: File,
  ciBack: File,
  livenessFrames: File[],
  livenessSessionId?: string
): Promise<SubmitResponse> {
  const formData = new FormData();
  formData.append('selfie', selfie);
  formData.append('ciFront', ciFront);
  formData.append('ciBack', ciBack);
  livenessFrames.forEach((f) => formData.append('livenessFrames', f));
  formData.append('token', token);
  if (livenessSessionId) formData.append('livenessSessionId', livenessSessionId);

  const res = await api.post<{ success: boolean; data: SubmitResponse }>(
    `${BASE}/submit?token=${encodeURIComponent(token)}`,
    formData,
    {
      headers: { 'Content-Type': 'multipart/form-data' },
    }
  );
  if (!res.data.success || !res.data.data) throw new Error('Error al enviar verificación');
  return res.data.data;
}
