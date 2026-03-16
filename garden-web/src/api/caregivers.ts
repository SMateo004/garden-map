import { api } from './client';
import type {
  PaginatedCaregivers,
  CaregiverDetail,
  ListCaregiversParams,
  CreateCaregiverProfileBody,
  PaseoSlot,
  CaregiverAvailabilityResponse,
} from '@/types/caregiver';

export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: { code: string; message: string };
}

export function listCaregivers(params: ListCaregiversParams = {}): Promise<ApiResponse<PaginatedCaregivers>> {
  // Convertir spaceTypes array a comma-separated string para query param
  const queryParams: Record<string, unknown> = { ...params };
  if (params.spaceTypes && Array.isArray(params.spaceTypes) && params.spaceTypes.length > 0) {
    queryParams.spaceTypes = params.spaceTypes.join(',');
  } else {
    delete queryParams.spaceTypes;
  }
  return api.get('/api/caregivers', { params: queryParams }).then((r) => r.data);
}

export function getCaregiverById(id: string): Promise<ApiResponse<CaregiverDetail>> {
  return api.get(`/api/caregivers/${id}`).then((r) => r.data);
}

export function getCaregiverAvailability(
  id: string,
  from?: string,
  to?: string
): Promise<ApiResponse<CaregiverAvailabilityResponse>> {
  const params: Record<string, string> = {};
  if (from) params.from = from;
  if (to) params.to = to;
  return api.get(`/api/caregivers/${id}/availability`, { params }).then((r) => r.data);
}

export function createCaregiverProfile(
  body: CreateCaregiverProfileBody,
  photos: File[]
): Promise<ApiResponse<CaregiverDetail>> {
  const formData = new FormData();
  formData.append('data', JSON.stringify(body));
  photos.forEach((f) => formData.append('photos', f));
  return api
    .postForm('/api/caregivers', formData)
    .then((r) => r.data);
}
