import { api, getStoredToken, setStoredToken, clearStoredToken } from './client';

export type UserRole = 'CLIENT' | 'CAREGIVER' | 'ADMIN';

export interface AuthUser {
  id: string;
  email: string;
  role: UserRole;
  firstName: string;
  lastName: string;
  /** Solo presente cuando role === 'CLIENT'; usado para redirigir a completar perfil de mascota. */
  clientProfile?: { isComplete: boolean } | null;
}

export interface LoginResponse {
  success: boolean;
  data?: {
    accessToken: string;
    expiresIn: string;
    user: AuthUser;
  };
  error?: { code?: string; message?: string };
}

export interface RegisterCaregiverResponse {
  success: boolean;
  data?: {
    user: AuthUser;
    profileId: string;
    verificationStatus: string;
    accessToken: string;
    expiresIn: string;
  };
  error?: { code?: string; message?: string; field?: string }; // field: 'email' | 'phone' para errores 409
}

export interface RegisterClientResponse {
  success: boolean;
  data?: {
    user: AuthUser;
    profileId: string;
    accessToken: string;
    expiresIn: string;
  };
  error?: { code?: string; message?: string; field?: string }; // field: 'email' | 'phone' para errores 409
}

/** Verifica si el email existe en la base de datos. Para flujo email-first login. */
export async function checkEmailExists(email: string): Promise<boolean> {
  const res = await api.get<{ success: boolean; data?: { exists: boolean } }>('/api/auth/check-email', {
    params: { email: email.trim().toLowerCase() },
  });
  return res.data?.data?.exists ?? false;
}

/** Extrae mensaje de error de la respuesta del API (401/400) o de Axios. */
function getLoginErrorMessage(err: unknown): string {
  if (err && typeof err === 'object' && 'response' in err) {
    const res = (err as { response?: { data?: { error?: { message?: string } }; status?: number } }).response;
    if (res?.data?.error?.message) return res.data.error.message;
    if (res?.status === 401) return 'Credenciales incorrectas';
    if (res?.status === 400) return res.data?.error?.message ?? 'Datos inválidos';
  }
  return err instanceof Error ? err.message : 'Error al iniciar sesión';
}

export async function login(email: string, password: string, roleCaregiverOnly = false): Promise<LoginResponse['data']> {
  try {
    const res = await api.post<LoginResponse>(
      '/api/auth/login',
      { email, password },
      { params: roleCaregiverOnly ? { role: 'caregiver' } : undefined }
    );
    if (!res.data.success || !res.data.data) {
      throw new Error((res.data as LoginResponse).error?.message ?? 'Error al iniciar sesión');
    }
    const { accessToken } = res.data.data;
    setStoredToken(accessToken);
    return res.data.data;
  } catch (err) {
    throw new Error(getLoginErrorMessage(err));
  }
}

export interface ValidationErrorItem {
  field: string;
  message: string;
}

export async function registerCaregiver(payload: RegisterCaregiverPayload): Promise<RegisterCaregiverResponse['data']> {
  try {
    const res = await api.post<RegisterCaregiverResponse>('/api/auth/caregiver/register', payload);
    if (!res.data.success || !res.data.data) {
      const err = (res.data as RegisterCaregiverResponse).error;
      throw new Error(err?.message ?? 'Error al registrarse');
    }
    const { accessToken } = res.data.data;
    setStoredToken(accessToken);
    return res.data.data;
  } catch (err: any) {
    // 400 con errores por campo (validación Zod)
    if (err?.response?.status === 400 && Array.isArray(err?.response?.data?.errors)) {
      const error = new Error(err.response?.data?.message ?? 'Datos inválidos. Revisa los campos marcados.');
      (error as any).statusCode = 400;
      (error as any).errors = err.response.data.errors as ValidationErrorItem[];
      throw error;
    }
    // 409 Conflict (email o teléfono duplicado)
    if (err?.response?.status === 409) {
      const errorData = err.response?.data?.error;
      const field = errorData?.field;
      const code = errorData?.code;
      const error = new Error(errorData?.message ?? 'Ya existe una cuenta con estos datos');
      (error as any).field = field;
      (error as any).code = code;
      (error as any).statusCode = 409;
      throw error;
    }
    throw err;
  }
}

export async function registerClient(payload: RegisterClientPayload): Promise<RegisterClientResponse['data']> {
  try {
    const res = await api.post<RegisterClientResponse>('/api/auth/client/register', payload);
    if (!res.data.success || !res.data.data) {
      const err = (res.data as RegisterClientResponse).error;
      throw new Error(err?.message ?? 'Error al registrarse');
    }
    const { accessToken } = res.data.data;
    setStoredToken(accessToken);
    return res.data.data;
  } catch (err: any) {
    if (err?.response?.status === 400 && Array.isArray(err?.response?.data?.errors)) {
      const error = new Error(err?.response?.data?.message ?? 'Datos inválidos');
      (error as any).statusCode = 400;
      (error as any).response = err.response;
      (error as any).errors = err.response.data.errors as { field: string; message: string }[];
      throw error;
    }
    if (err?.response?.status === 409) {
      const errorData = err.response?.data?.error;
      const field = errorData?.field;
      const code = errorData?.code;
      const error = new Error(errorData?.message ?? 'Ya existe una cuenta con estos datos');
      (error as any).field = field;
      (error as any).code = code;
      (error as any).statusCode = 409;
      throw error;
    }
    if (err?.response?.status === 500) {
      const backendMessage =
        err.response?.data?.message ??
        err.response?.data?.error?.message ??
        'Error interno al registrar. Intenta más tarde.';
      const error = new Error(backendMessage);
      (error as any).statusCode = 500;
      (error as any).response = err.response;
      throw error;
    }
    throw err;
  }
}

/** Sube las fotos y devuelve URLs para usar en registerCaregiver */
export async function uploadRegistrationPhotos(files: File[]): Promise<string[]> {
  const formData = new FormData();
  files.forEach((f) => formData.append('photos', f));
  const res = await api.postForm<{ success: boolean; data?: { urls: string[] } }>(
    '/api/upload/registration-photos',
    formData
  );
  if (!res.data.success || !res.data.data?.urls) {
    throw new Error('Error al subir fotos');
  }
  return res.data.data.urls;
}

export function logout(): void {
  clearStoredToken();
}

export { getStoredToken, setStoredToken, clearStoredToken };

/** Payload para POST /api/auth/caregiver/register — alineado con backend */
export interface RegisterCaregiverPayload {
  user: {
    email: string;
    password: string;
    firstName: string;
    lastName: string;
    phone: string;
    dateOfBirth: string;
    country: string;
    city: string;
    isOver18: true;
  };
  profile: {
    servicesOffered: ('HOSPEDAJE' | 'PASEO')[];
    photos: string[];
    zone?: string;
    bio?: string;
    spaceType?: string[];
    address?: string;
    pricePerDay?: number;
    pricePerWalk30?: number;
    pricePerWalk60?: number;
    serviceAvailability?: Record<string, unknown>;
    rates?: Record<string, number>;
  };
}

/** Payload para POST /api/auth/client/register — alineado con backend */
export interface RegisterClientPayload {
  fullName: string;
  email: string;
  password: string;
  phone: string;
  address?: string;
}
