# GARDEN - Refinamiento UI/UX: Integracion con Backend

## React 18 + Node.js/Express + Prisma + Cloudinary

**Version:** 1.1
**Fecha:** 06 de Febrero, 2026
**Prerequisito:** [GARDEN_UI_UX_Perfiles_Cuidadores.md](GARDEN_UI_UX_Perfiles_Cuidadores.md)
**Scope:** Componentes React con estado real, flujo de upload, responsive breakpoints, estrategia de iteracion

---

## Tabla de Contenidos

1. [Componentes React Detallados](#1-componentes-react-detallados)
2. [Diagramas de Upload Pipeline](#2-diagramas-de-upload-pipeline)
3. [Responsive Breakpoints](#3-responsive-breakpoints)
4. [Estrategia de Iteracion](#4-estrategia-de-iteracion)
5. [Self-Review Cruzado](#5-self-review-cruzado)

---

## 1. Componentes React Detallados

### 1.1 Type System: Contratos Frontend-Backend

Estos tipos reflejan exactamente el schema Prisma. Si el schema cambia, estos tipos son el unico punto de actualizacion en frontend.

```typescript
// src/types/caregiver.ts

// ---- Enums (espejo de Prisma) ----

export type ServiceType = 'HOSPEDAJE' | 'PASEO';
export type SpaceType = 'casa_patio' | 'casa_sin_patio' | 'departamento';
export type Zone = 'equipetrol' | 'urbari' | 'norte' | 'las_palmas' | 'centro' | 'otros';

// ---- DTOs del backend (GET /api/caregivers) ----

/** Datos que llegan en el listing. Subset ligero de CaregiverProfile. */
export interface CaregiverListItem {
  id: string;
  firstName: string;
  lastName: string;
  profilePicture: string | null;    // URL Cloudinary (foto principal)
  zone: Zone;
  spaceType: SpaceType | null;
  servicesOffered: ServiceType[];
  pricePerDay: number | null;       // Bs, solo si ofrece hospedaje
  pricePerWalk30: number | null;    // Bs, solo si ofrece paseos
  pricePerWalk60: number | null;
  verified: boolean;
  rating: number;                   // 0.0 - 5.0
  reviewCount: number;
}

/** Respuesta paginada de GET /api/caregivers */
export interface CaregiverListResponse {
  success: true;
  data: {
    caregivers: CaregiverListItem[];
    pagination: {
      total: number;
      page: number;
      pages: number;
    };
  };
}

/** Perfil completo para GET /api/caregivers/:id */
export interface CaregiverDetail extends CaregiverListItem {
  bio: string | null;
  photos: string[];                 // URLs Cloudinary (4-6 fotos)
  approvedAt: string | null;
  reviews: ReviewItem[];
  availability: {
    hospedaje: string[];            // fechas ISO disponibles
    paseos: Record<string, ('MANANA' | 'TARDE')[]>;
  };
}

export interface CaregiverDetailResponse {
  success: true;
  data: CaregiverDetail;
}

/** Resena individual */
export interface ReviewItem {
  id: string;
  clientName: string;
  clientPhoto: string | null;
  rating: number;                   // 1-5
  comment: string | null;
  serviceType: ServiceType;
  caregiverResponse: string | null;
  respondedAt: string | null;
  createdAt: string;
}

// ---- Filtros (client-side) ----

export interface CaregiverFilters {
  service: ServiceType | 'AMBOS' | null;
  zones: Zone[];                    // multiple selection
  priceRange: PriceRange | null;
  spaceType: SpaceType | null;
}

export type PriceRange = 'economico' | 'estandar' | 'premium';

/** Rangos de precio segun tipo de servicio */
export const PRICE_RANGES: Record<'hospedaje' | 'paseo', Record<PriceRange, [number, number]>> = {
  hospedaje: {
    economico: [60, 100],
    estandar:  [100, 140],
    premium:   [140, Infinity],
  },
  paseo: {
    economico: [20, 30],
    estandar:  [30, 50],
    premium:   [50, Infinity],
  },
};

// ---- Upload (registro cuidador) ----

export type UploadStatus = 'idle' | 'uploading' | 'success' | 'error';

export interface PhotoUploadState {
  file: File;
  preview: string;                 // URL.createObjectURL local
  status: UploadStatus;
  progress: number;                // 0-100
  cloudinaryUrl: string | null;    // URL final despues de upload
  error: string | null;
}

/** Input para registro de cuidador (POST /api/auth/register + profile) */
export interface CaregiverRegistrationInput {
  // Paso 1: datos basicos
  email: string;
  password: string;
  firstName: string;
  lastName: string;
  phone: string;
  role: 'CAREGIVER';

  // Paso 2: perfil
  bio: string;
  zone: Zone;
  spaceType: SpaceType;

  // Paso 3: servicios
  servicesOffered: ServiceType[];
  pricePerDay?: number;
  pricePerWalk30?: number;
  pricePerWalk60?: number;

  // Paso 4: fotos (URLs de Cloudinary post-upload)
  photos: string[];
}
```

---

### 1.2 Hook: `useCaregivers` (Listing con fetch + filtrado)

```typescript
// src/hooks/useCaregivers.ts

import { useState, useEffect, useMemo, useCallback } from 'react';
import type {
  CaregiverListItem,
  CaregiverFilters,
  CaregiverListResponse,
  PriceRange,
  PRICE_RANGES,
} from '../types/caregiver';

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:3001/api';

interface UseCaregiverState {
  /** Todos los cuidadores sin filtrar (cache local) */
  allCaregivers: CaregiverListItem[];
  /** Cuidadores filtrados (subset de allCaregivers) */
  filtered: CaregiverListItem[];
  /** Pagina actual de resultados filtrados */
  page: CaregiverListItem[];
  /** Estado de la peticion HTTP */
  status: 'idle' | 'loading' | 'success' | 'error';
  /** Mensaje de error si status === 'error' */
  error: string | null;
  /** Filtros activos */
  filters: CaregiverFilters;
  /** Paginacion */
  pagination: {
    currentPage: number;
    totalPages: number;
    total: number;
  };
}

const ITEMS_PER_PAGE = 12;

const INITIAL_FILTERS: CaregiverFilters = {
  service: null,
  zones: [],
  priceRange: null,
  spaceType: null,
};

export function useCaregivers() {
  const [allCaregivers, setAllCaregivers] = useState<CaregiverListItem[]>([]);
  const [status, setStatus] = useState<UseCaregiverState['status']>('idle');
  const [error, setError] = useState<string | null>(null);
  const [filters, setFilters] = useState<CaregiverFilters>(INITIAL_FILTERS);
  const [currentPage, setCurrentPage] = useState(1);

  // ---- FETCH: una sola vez al montar ----
  // Para MVP (<200 cuidadores), cargamos todo y filtramos client-side.
  // Esto elimina latencia en filtros y permite UX instantanea.

  useEffect(() => {
    const controller = new AbortController();

    async function fetchCaregivers() {
      setStatus('loading');
      setError(null);

      try {
        const res = await fetch(`${API_BASE}/caregivers?limit=200`, {
          signal: controller.signal,
          headers: { 'Accept': 'application/json' },
        });

        if (!res.ok) {
          throw new Error(`HTTP ${res.status}: ${res.statusText}`);
        }

        const json: CaregiverListResponse = await res.json();
        setAllCaregivers(json.data.caregivers);
        setStatus('success');
      } catch (err) {
        if (err instanceof Error && err.name === 'AbortError') return;
        setError(
          err instanceof Error
            ? err.message
            : 'Error cargando cuidadores. Intenta nuevamente.'
        );
        setStatus('error');
      }
    }

    fetchCaregivers();
    return () => controller.abort();
  }, []);

  // ---- FILTRADO: client-side, recalcula cuando cambian filtros ----

  const filtered = useMemo(() => {
    let result = allCaregivers;

    // Filtro: servicio
    if (filters.service && filters.service !== 'AMBOS') {
      result = result.filter(c =>
        c.servicesOffered.includes(filters.service as 'HOSPEDAJE' | 'PASEO')
      );
    }

    // Filtro: zonas (OR entre zonas seleccionadas)
    if (filters.zones.length > 0) {
      result = result.filter(c => filters.zones.includes(c.zone));
    }

    // Filtro: precio (contextual segun servicio)
    if (filters.priceRange) {
      const serviceContext = filters.service === 'PASEO' ? 'paseo' : 'hospedaje';
      const [min, max] = PRICE_RANGES[serviceContext][filters.priceRange];

      result = result.filter(c => {
        const price = serviceContext === 'hospedaje' ? c.pricePerDay : c.pricePerWalk30;
        if (price === null) return false;
        return price >= min && price < max;
      });
    }

    // Filtro: tipo de espacio (solo aplica si servicio != PASEO)
    if (filters.spaceType && filters.service !== 'PASEO') {
      result = result.filter(c => c.spaceType === filters.spaceType);
    }

    return result;
  }, [allCaregivers, filters]);

  // ---- PAGINACION ----

  const totalPages = Math.max(1, Math.ceil(filtered.length / ITEMS_PER_PAGE));

  // Reset a pagina 1 cuando cambian filtros
  useEffect(() => {
    setCurrentPage(1);
  }, [filters]);

  const page = useMemo(() => {
    const start = (currentPage - 1) * ITEMS_PER_PAGE;
    return filtered.slice(start, start + ITEMS_PER_PAGE);
  }, [filtered, currentPage]);

  // ---- ACCIONES ----

  const updateFilter = useCallback(
    <K extends keyof CaregiverFilters>(key: K, value: CaregiverFilters[K]) => {
      setFilters(prev => ({ ...prev, [key]: value }));
    },
    []
  );

  const clearFilters = useCallback(() => {
    setFilters(INITIAL_FILTERS);
  }, []);

  const hasActiveFilters = useMemo(() => {
    return (
      filters.service !== null ||
      filters.zones.length > 0 ||
      filters.priceRange !== null ||
      filters.spaceType !== null
    );
  }, [filters]);

  const goToPage = useCallback((page: number) => {
    setCurrentPage(Math.max(1, Math.min(page, totalPages)));
    // Scroll al top del grid
    document.getElementById('caregiver-grid')?.scrollIntoView({
      behavior: 'smooth',
      block: 'start',
    });
  }, [totalPages]);

  const retry = useCallback(() => {
    setStatus('idle');
    setError(null);
    // Re-trigger useEffect
    setAllCaregivers([]);
  }, []);

  return {
    caregivers: page,
    allCount: allCaregivers.length,
    filteredCount: filtered.length,
    status,
    error,
    filters,
    hasActiveFilters,
    pagination: {
      currentPage,
      totalPages,
      total: filtered.length,
    },
    updateFilter,
    clearFilters,
    goToPage,
    retry,
  };
}
```

---

### 1.3 Hook: `useCaregiverDetail` (Pagina de Detalle)

```typescript
// src/hooks/useCaregiverDetail.ts

import { useState, useEffect } from 'react';
import type { CaregiverDetail, CaregiverDetailResponse } from '../types/caregiver';

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:3001/api';

export function useCaregiverDetail(caregiverId: string) {
  const [caregiver, setCaregiverId] = useState<CaregiverDetail | null>(null);
  const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const controller = new AbortController();

    async function fetchDetail() {
      setStatus('loading');
      setError(null);

      try {
        const res = await fetch(`${API_BASE}/caregivers/${caregiverId}`, {
          signal: controller.signal,
          headers: { 'Accept': 'application/json' },
        });

        if (res.status === 404) {
          throw new Error('Cuidador no encontrado');
        }

        if (!res.ok) {
          throw new Error(`Error ${res.status}: ${res.statusText}`);
        }

        const json: CaregiverDetailResponse = await res.json();
        setCaregiverId(json.data);
        setStatus('success');
      } catch (err) {
        if (err instanceof Error && err.name === 'AbortError') return;
        setError(
          err instanceof Error
            ? err.message
            : 'Error cargando perfil. Intenta nuevamente.'
        );
        setStatus('error');
      }
    }

    fetchDetail();
    return () => controller.abort();
  }, [caregiverId]);

  return { caregiver, status, error };
}
```

---

### 1.4 Hook: `usePhotoUpload` (Subida de Fotos a Cloudinary)

Este hook encapsula todo el flujo de subida: validacion client-side, upload al backend, progreso, errores, reordenamiento.

```typescript
// src/hooks/usePhotoUpload.ts

import { useState, useCallback } from 'react';
import type { PhotoUploadState } from '../types/caregiver';

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:3001/api';

// ---- Constantes de validacion ----
const MAX_PHOTOS = 6;
const MIN_PHOTOS = 4;
const MAX_FILE_SIZE = 5 * 1024 * 1024;  // 5MB
const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
const ALLOWED_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.webp'];

interface ValidationError {
  file: string;
  reason: string;
}

export function usePhotoUpload(authToken: string) {
  const [photos, setPhotos] = useState<PhotoUploadState[]>([]);
  const [validationErrors, setValidationErrors] = useState<ValidationError[]>([]);

  // ---- VALIDACION CLIENT-SIDE ----

  const validateFiles = useCallback((files: File[]): {
    valid: File[];
    errors: ValidationError[];
  } => {
    const errors: ValidationError[] = [];
    const valid: File[] = [];
    const currentCount = photos.filter(p => p.status !== 'error').length;

    for (const file of files) {
      // Limite de cantidad
      if (currentCount + valid.length >= MAX_PHOTOS) {
        errors.push({
          file: file.name,
          reason: `Maximo ${MAX_PHOTOS} fotos permitidas`,
        });
        continue;
      }

      // Tipo de archivo
      if (!ALLOWED_TYPES.includes(file.type)) {
        errors.push({
          file: file.name,
          reason: `Formato no soportado. Usa: ${ALLOWED_EXTENSIONS.join(', ')}`,
        });
        continue;
      }

      // Tamano
      if (file.size > MAX_FILE_SIZE) {
        const sizeMB = (file.size / (1024 * 1024)).toFixed(1);
        errors.push({
          file: file.name,
          reason: `Archivo muy grande (${sizeMB}MB). Maximo: 5MB`,
        });
        continue;
      }

      // Dimensiones minimas (validadas async, pero prefiltramos lo obvio)
      valid.push(file);
    }

    return { valid, errors };
  }, [photos]);

  // ---- UPLOAD DE UN ARCHIVO ----

  const uploadSingleFile = useCallback(async (
    file: File,
    index: number
  ): Promise<string> => {
    const formData = new FormData();
    formData.append('photo', file);
    formData.append('folder', 'garden/caregivers');

    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();

      // Progreso
      xhr.upload.addEventListener('progress', (e) => {
        if (e.lengthComputable) {
          const progress = Math.round((e.loaded / e.total) * 100);
          setPhotos(prev => prev.map((p, i) =>
            i === index ? { ...p, progress } : p
          ));
        }
      });

      // Completado
      xhr.addEventListener('load', () => {
        if (xhr.status >= 200 && xhr.status < 300) {
          const json = JSON.parse(xhr.responseText);
          resolve(json.data.url);
        } else {
          let msg = 'Error subiendo imagen';
          try {
            const json = JSON.parse(xhr.responseText);
            msg = json.error?.message || msg;
          } catch {}
          reject(new Error(msg));
        }
      });

      xhr.addEventListener('error', () => reject(new Error('Error de red')));
      xhr.addEventListener('abort', () => reject(new Error('Subida cancelada')));

      xhr.open('POST', `${API_BASE}/uploads/photo`);
      xhr.setRequestHeader('Authorization', `Bearer ${authToken}`);
      xhr.send(formData);
    });
  }, [authToken]);

  // ---- AGREGAR FOTOS (batch) ----

  const addPhotos = useCallback(async (files: FileList | File[]) => {
    const fileArray = Array.from(files);
    const { valid, errors } = validateFiles(fileArray);

    setValidationErrors(errors);
    if (valid.length === 0) return;

    // Crear estados con preview local
    const newPhotos: PhotoUploadState[] = valid.map(file => ({
      file,
      preview: URL.createObjectURL(file),
      status: 'idle' as const,
      progress: 0,
      cloudinaryUrl: null,
      error: null,
    }));

    setPhotos(prev => {
      const updated = [...prev, ...newPhotos];
      return updated;
    });

    // Subir secuencialmente (no saturar el backend)
    const startIndex = photos.length;

    for (let i = 0; i < valid.length; i++) {
      const globalIndex = startIndex + i;

      // Marcar como uploading
      setPhotos(prev => prev.map((p, idx) =>
        idx === globalIndex ? { ...p, status: 'uploading' } : p
      ));

      try {
        const url = await uploadSingleFile(valid[i], globalIndex);

        setPhotos(prev => prev.map((p, idx) =>
          idx === globalIndex
            ? { ...p, status: 'success', progress: 100, cloudinaryUrl: url }
            : p
        ));
      } catch (err) {
        setPhotos(prev => prev.map((p, idx) =>
          idx === globalIndex
            ? {
                ...p,
                status: 'error',
                error: err instanceof Error ? err.message : 'Error desconocido',
              }
            : p
        ));
      }
    }
  }, [photos, validateFiles, uploadSingleFile]);

  // ---- ELIMINAR FOTO ----

  const removePhoto = useCallback((index: number) => {
    setPhotos(prev => {
      const photo = prev[index];
      // Liberar el ObjectURL para evitar memory leaks
      if (photo?.preview) {
        URL.revokeObjectURL(photo.preview);
      }
      return prev.filter((_, i) => i !== index);
    });
  }, []);

  // ---- REINTENTAR UPLOAD ----

  const retryUpload = useCallback(async (index: number) => {
    const photo = photos[index];
    if (!photo || photo.status !== 'error') return;

    setPhotos(prev => prev.map((p, i) =>
      i === index ? { ...p, status: 'uploading', progress: 0, error: null } : p
    ));

    try {
      const url = await uploadSingleFile(photo.file, index);
      setPhotos(prev => prev.map((p, i) =>
        i === index
          ? { ...p, status: 'success', progress: 100, cloudinaryUrl: url }
          : p
      ));
    } catch (err) {
      setPhotos(prev => prev.map((p, i) =>
        i === index
          ? { ...p, status: 'error', error: err instanceof Error ? err.message : 'Error' }
          : p
      ));
    }
  }, [photos, uploadSingleFile]);

  // ---- REORDENAR (drag & drop) ----

  const reorderPhotos = useCallback((fromIndex: number, toIndex: number) => {
    setPhotos(prev => {
      const updated = [...prev];
      const [moved] = updated.splice(fromIndex, 1);
      updated.splice(toIndex, 0, moved);
      return updated;
    });
  }, []);

  // ---- ESTADO DERIVADO ----

  const successCount = photos.filter(p => p.status === 'success').length;
  const uploadingCount = photos.filter(p => p.status === 'uploading').length;
  const errorCount = photos.filter(p => p.status === 'error').length;
  const isUploading = uploadingCount > 0;
  const canSubmit = successCount >= MIN_PHOTOS && !isUploading;
  const cloudinaryUrls = photos
    .filter(p => p.cloudinaryUrl !== null)
    .map(p => p.cloudinaryUrl as string);

  return {
    photos,
    validationErrors,
    addPhotos,
    removePhoto,
    retryUpload,
    reorderPhotos,
    isUploading,
    canSubmit,
    successCount,
    uploadingCount,
    errorCount,
    cloudinaryUrls,
    maxPhotos: MAX_PHOTOS,
    minPhotos: MIN_PHOTOS,
  };
}
```

---

### 1.5 Hook: `useCaregiverRegistration` (Multi-Step Form)

```typescript
// src/hooks/useCaregiverRegistration.ts

import { useState, useCallback } from 'react';
import type { CaregiverRegistrationInput, Zone, SpaceType, ServiceType } from '../types/caregiver';

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:3001/api';

type Step = 1 | 2 | 3 | 4;
type SubmitStatus = 'idle' | 'submitting' | 'success' | 'error';

// ---- Validaciones por step (client-side, espejo de Zod en backend) ----

interface StepErrors {
  [field: string]: string;
}

function validateStep1(data: Partial<CaregiverRegistrationInput>): StepErrors {
  const errors: StepErrors = {};

  if (!data.firstName || data.firstName.length < 2)
    errors.firstName = 'Nombre: minimo 2 caracteres';
  if (!data.lastName || data.lastName.length < 2)
    errors.lastName = 'Apellido: minimo 2 caracteres';
  if (!data.email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(data.email))
    errors.email = 'Email invalido';
  if (!data.password || data.password.length < 8)
    errors.password = 'Contraseña: minimo 8 caracteres';
  if (!data.phone || !/^\+591[67]\d{7}$/.test(data.phone))
    errors.phone = 'Telefono boliviano invalido (+591 7XXXXXXX)';

  return errors;
}

function validateStep2(data: Partial<CaregiverRegistrationInput>): StepErrors {
  const errors: StepErrors = {};

  if (!data.bio || data.bio.length < 50)
    errors.bio = 'Descripcion: minimo 50 caracteres';
  if (data.bio && data.bio.length > 500)
    errors.bio = 'Descripcion: maximo 500 caracteres';
  if (!data.zone)
    errors.zone = 'Selecciona tu zona';
  if (!data.spaceType)
    errors.spaceType = 'Selecciona tipo de espacio';

  return errors;
}

function validateStep3(data: Partial<CaregiverRegistrationInput>): StepErrors {
  const errors: StepErrors = {};

  if (!data.servicesOffered || data.servicesOffered.length === 0)
    errors.servicesOffered = 'Selecciona al menos un servicio';

  if (data.servicesOffered?.includes('HOSPEDAJE')) {
    if (!data.pricePerDay || data.pricePerDay < 30 || data.pricePerDay > 500)
      errors.pricePerDay = 'Precio hospedaje: Bs 30-500';
  }

  if (data.servicesOffered?.includes('PASEO')) {
    if (!data.pricePerWalk30 || data.pricePerWalk30 < 15 || data.pricePerWalk30 > 100)
      errors.pricePerWalk30 = 'Precio paseo 30min: Bs 15-100';
    if (!data.pricePerWalk60 || data.pricePerWalk60 < 25 || data.pricePerWalk60 > 200)
      errors.pricePerWalk60 = 'Precio paseo 1h: Bs 25-200';
  }

  return errors;
}

function validateStep4(photos: string[]): StepErrors {
  const errors: StepErrors = {};
  if (photos.length < 4)
    errors.photos = `Necesitas al menos 4 fotos (tienes ${photos.length})`;
  return errors;
}

const VALIDATORS: Record<Step, (data: any, photos?: string[]) => StepErrors> = {
  1: validateStep1,
  2: validateStep2,
  3: validateStep3,
  4: (_data, photos) => validateStep4(photos || []),
};

export function useCaregiverRegistration() {
  const [step, setStep] = useState<Step>(1);
  const [formData, setFormData] = useState<Partial<CaregiverRegistrationInput>>({
    role: 'CAREGIVER',
    servicesOffered: [],
  });
  const [errors, setErrors] = useState<StepErrors>({});
  const [submitStatus, setSubmitStatus] = useState<SubmitStatus>('idle');
  const [submitError, setSubmitError] = useState<string | null>(null);

  // Actualizar campo
  const updateField = useCallback(<K extends keyof CaregiverRegistrationInput>(
    field: K,
    value: CaregiverRegistrationInput[K]
  ) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    // Limpiar error del campo al editar
    setErrors(prev => {
      const next = { ...prev };
      delete next[field];
      return next;
    });
  }, []);

  // Toggle servicio (checkbox behavior)
  const toggleService = useCallback((service: ServiceType) => {
    setFormData(prev => {
      const current = prev.servicesOffered || [];
      const next = current.includes(service)
        ? current.filter(s => s !== service)
        : [...current, service];
      return { ...prev, servicesOffered: next };
    });
  }, []);

  // Navegar entre pasos
  const nextStep = useCallback((photoUrls?: string[]) => {
    const stepErrors = VALIDATORS[step](formData, photoUrls);

    if (Object.keys(stepErrors).length > 0) {
      setErrors(stepErrors);
      return false;
    }

    setErrors({});
    if (step < 4) {
      setStep((step + 1) as Step);
    }
    return true;
  }, [step, formData]);

  const prevStep = useCallback(() => {
    if (step > 1) {
      setStep((step - 1) as Step);
      setErrors({});
    }
  }, [step]);

  // Submit final
  const submit = useCallback(async (photoUrls: string[]) => {
    // Validar paso 4
    const stepErrors = validateStep4(photoUrls);
    if (Object.keys(stepErrors).length > 0) {
      setErrors(stepErrors);
      return false;
    }

    const payload: CaregiverRegistrationInput = {
      ...(formData as CaregiverRegistrationInput),
      photos: photoUrls,
    };

    setSubmitStatus('submitting');
    setSubmitError(null);

    try {
      // 1. Registrar usuario
      const registerRes = await fetch(`${API_BASE}/auth/register`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: payload.email,
          password: payload.password,
          firstName: payload.firstName,
          lastName: payload.lastName,
          phone: payload.phone,
          role: 'CAREGIVER',
        }),
      });

      if (!registerRes.ok) {
        const err = await registerRes.json();
        throw new Error(err.error?.message || 'Error en registro');
      }

      const { data: authData } = await registerRes.json();
      const token = authData.tokens.accessToken;

      // 2. Completar perfil de cuidador
      const profileRes = await fetch(`${API_BASE}/caregivers/profile`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          bio: payload.bio,
          zone: payload.zone,
          spaceType: payload.spaceType,
          servicesOffered: payload.servicesOffered,
          pricePerDay: payload.pricePerDay,
          pricePerWalk30: payload.pricePerWalk30,
          pricePerWalk60: payload.pricePerWalk60,
          photos: payload.photos,
        }),
      });

      if (!profileRes.ok) {
        const err = await profileRes.json();
        throw new Error(err.error?.message || 'Error guardando perfil');
      }

      setSubmitStatus('success');
      return true;

    } catch (err) {
      setSubmitError(
        err instanceof Error ? err.message : 'Error inesperado. Intenta nuevamente.'
      );
      setSubmitStatus('error');
      return false;
    }
  }, [formData]);

  return {
    step,
    formData,
    errors,
    submitStatus,
    submitError,
    updateField,
    toggleService,
    nextStep,
    prevStep,
    submit,
  };
}
```

---

### 1.6 Componente: `PhotoUploader` (Paso 4 del Registro)

Componente completo que maneja los estados de upload: idle, uploading (con progreso), success, error (con retry).

```tsx
// src/components/registration/PhotoUploader.tsx

import { useRef, type DragEvent } from 'react';
import type { PhotoUploadState } from '../../types/caregiver';

interface PhotoUploaderProps {
  photos: PhotoUploadState[];
  onAddPhotos: (files: FileList | File[]) => void;
  onRemove: (index: number) => void;
  onRetry: (index: number) => void;
  onReorder: (from: number, to: number) => void;
  validationErrors: { file: string; reason: string }[];
  maxPhotos: number;
  minPhotos: number;
  isUploading: boolean;
  successCount: number;
}

export function PhotoUploader({
  photos,
  onAddPhotos,
  onRemove,
  onRetry,
  onReorder,
  validationErrors,
  maxPhotos,
  minPhotos,
  isUploading,
  successCount,
}: PhotoUploaderProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const dragIndexRef = useRef<number | null>(null);

  const canAddMore = photos.length < maxPhotos;

  // ---- Drop zone ----
  function handleDrop(e: DragEvent<HTMLDivElement>) {
    e.preventDefault();
    e.currentTarget.classList.remove('border-garden-500', 'bg-garden-50');

    if (e.dataTransfer.files.length > 0) {
      onAddPhotos(e.dataTransfer.files);
    }
  }

  function handleDragOver(e: DragEvent<HTMLDivElement>) {
    e.preventDefault();
    e.currentTarget.classList.add('border-garden-500', 'bg-garden-50');
  }

  function handleDragLeave(e: DragEvent<HTMLDivElement>) {
    e.currentTarget.classList.remove('border-garden-500', 'bg-garden-50');
  }

  // ---- Drag & drop reorder ----
  function handleItemDragStart(index: number) {
    dragIndexRef.current = index;
  }

  function handleItemDrop(targetIndex: number) {
    if (dragIndexRef.current !== null && dragIndexRef.current !== targetIndex) {
      onReorder(dragIndexRef.current, targetIndex);
    }
    dragIndexRef.current = null;
  }

  return (
    <div className="space-y-4">
      {/* Header con contador */}
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-gray-700">
          Fotos de tu espacio ({successCount}/{minPhotos} minimo)
        </h3>
        <span className="text-xs text-gray-400">
          {photos.length}/{maxPhotos} slots usados
        </span>
      </div>

      {/* Grid de fotos */}
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
        {photos.map((photo, idx) => (
          <div
            key={idx}
            draggable={photo.status === 'success'}
            onDragStart={() => handleItemDragStart(idx)}
            onDragOver={(e) => e.preventDefault()}
            onDrop={() => handleItemDrop(idx)}
            className="relative aspect-square rounded-lg overflow-hidden group"
          >
            {/* Preview de la imagen */}
            <img
              src={photo.preview}
              alt={`Foto ${idx + 1}`}
              className={`
                w-full h-full object-cover
                ${photo.status === 'error' ? 'opacity-50 grayscale' : ''}
                ${photo.status === 'uploading' ? 'opacity-70' : ''}
              `}
            />

            {/* Badge de posicion (primera = principal) */}
            {idx === 0 && photo.status === 'success' && (
              <span className="
                absolute top-1.5 left-1.5
                bg-garden-500 text-white text-[10px] font-bold
                px-1.5 py-0.5 rounded
              ">
                Principal
              </span>
            )}

            {/* Estado: Uploading */}
            {photo.status === 'uploading' && (
              <div className="absolute inset-0 flex flex-col items-center justify-center bg-black/30">
                {/* Barra de progreso circular */}
                <svg className="w-10 h-10" viewBox="0 0 36 36">
                  <path
                    d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                    fill="none"
                    stroke="rgba(255,255,255,0.3)"
                    strokeWidth="3"
                  />
                  <path
                    d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                    fill="none"
                    stroke="white"
                    strokeWidth="3"
                    strokeDasharray={`${photo.progress}, 100`}
                    strokeLinecap="round"
                  />
                </svg>
                <span className="text-white text-xs mt-1 font-medium">
                  {photo.progress}%
                </span>
              </div>
            )}

            {/* Estado: Error */}
            {photo.status === 'error' && (
              <div className="absolute inset-0 flex flex-col items-center justify-center bg-red-900/40">
                <svg className="w-6 h-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                    d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"
                  />
                </svg>
                <span className="text-white text-[10px] mt-1 text-center px-2">
                  {photo.error}
                </span>
                <button
                  onClick={() => onRetry(idx)}
                  className="
                    mt-1.5 text-[10px] text-white
                    bg-white/20 hover:bg-white/30
                    px-2 py-0.5 rounded
                  "
                >
                  Reintentar
                </button>
              </div>
            )}

            {/* Estado: Success - boton eliminar (hover) */}
            {photo.status === 'success' && (
              <button
                onClick={() => onRemove(idx)}
                className="
                  absolute top-1.5 right-1.5
                  bg-black/50 hover:bg-red-500
                  text-white rounded-full p-1
                  opacity-0 group-hover:opacity-100
                  transition-opacity
                "
                aria-label={`Eliminar foto ${idx + 1}`}
              >
                <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            )}
          </div>
        ))}

        {/* Boton agregar mas fotos */}
        {canAddMore && (
          <div
            onDrop={handleDrop}
            onDragOver={handleDragOver}
            onDragLeave={handleDragLeave}
            onClick={() => inputRef.current?.click()}
            className="
              aspect-square rounded-lg
              border-2 border-dashed border-gray-300
              hover:border-garden-400 hover:bg-garden-50/50
              flex flex-col items-center justify-center
              cursor-pointer transition-colors
              text-gray-400 hover:text-garden-600
            "
            role="button"
            aria-label="Agregar foto"
          >
            <svg className="w-8 h-8" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                d="M12 4.5v15m7.5-7.5h-15"
              />
            </svg>
            <span className="text-xs mt-1">Agregar</span>
          </div>
        )}
      </div>

      {/* Input file oculto */}
      <input
        ref={inputRef}
        type="file"
        multiple
        accept=".jpg,.jpeg,.png,.webp"
        onChange={(e) => e.target.files && onAddPhotos(e.target.files)}
        className="hidden"
        aria-label="Seleccionar fotos"
      />

      {/* Errores de validacion */}
      {validationErrors.length > 0 && (
        <div
          className="bg-red-50 border border-red-200 rounded-lg p-3"
          role="alert"
        >
          <p className="text-sm font-medium text-red-800 mb-1">
            Archivos rechazados:
          </p>
          <ul className="text-xs text-red-600 space-y-0.5">
            {validationErrors.map((err, i) => (
              <li key={i}>
                <span className="font-medium">{err.file}:</span> {err.reason}
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Helper text */}
      <p className="text-xs text-gray-400">
        JPG, PNG o WebP. Maximo 5MB por foto.
        Arrastra para reordenar. La primera foto sera tu foto principal.
      </p>
    </div>
  );
}
```

---

### 1.7 Componente: `CaregiverListingPage` (Page completa con estados)

```tsx
// src/pages/CaregiverListingPage.tsx

import { useCaregivers } from '../hooks/useCaregivers';
import { CaregiverGrid } from '../components/caregivers/CaregiverGrid';
import { CaregiverGridSkeleton } from '../components/caregivers/CaregiverCardSkeleton';
import { FilterBar } from '../components/filters/FilterBar';
import { FilterBottomSheet } from '../components/filters/FilterBottomSheet';
import { NoResultsState } from '../components/ui/NoResultsState';
import { Pagination } from '../components/ui/Pagination';
import { useMediaQuery } from '../hooks/useMediaQuery';

export default function CaregiverListingPage() {
  const {
    caregivers,
    filteredCount,
    status,
    error,
    filters,
    hasActiveFilters,
    pagination,
    updateFilter,
    clearFilters,
    goToPage,
    retry,
  } = useCaregivers();

  const isMobile = useMediaQuery('(max-width: 767px)');

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white border-b border-gray-200">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 sm:py-8">
          <h1 className="text-2xl sm:text-3xl font-bold text-gray-900">
            Encuentra al cuidador perfecto para tu mascota
          </h1>
          <p className="mt-2 text-sm text-gray-500">
            Todos nuestros cuidadores fueron verificados personalmente por GARDEN
          </p>
        </div>
      </div>

      {/* Filtros */}
      {isMobile ? (
        <FilterBottomSheet
          filters={filters}
          onUpdate={updateFilter}
          onClear={clearFilters}
          hasActive={hasActiveFilters}
          resultCount={filteredCount}
        />
      ) : (
        <FilterBar
          filters={filters}
          onUpdate={updateFilter}
          onClear={clearFilters}
          hasActive={hasActiveFilters}
          resultCount={filteredCount}
        />
      )}

      {/* Contenido principal */}
      <main
        className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 sm:py-8"
        id="caregiver-grid"
      >
        {/* Estado: Loading */}
        {status === 'loading' && (
          <CaregiverGridSkeleton count={6} />
        )}

        {/* Estado: Error */}
        {status === 'error' && (
          <div
            className="text-center py-16 px-4"
            role="alert"
          >
            <div className="
              w-16 h-16 mx-auto mb-4
              bg-red-100 rounded-full
              flex items-center justify-center
            ">
              <svg className="w-8 h-8 text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                  d="M12 9v2m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
            </div>
            <h2 className="text-lg font-semibold text-gray-900 mb-2">
              No pudimos cargar los cuidadores
            </h2>
            <p className="text-sm text-gray-500 max-w-sm mx-auto mb-4">
              {error}
            </p>
            <button
              onClick={retry}
              className="
                bg-garden-500 hover:bg-garden-600
                text-white font-medium
                px-6 py-2.5 rounded-lg
                transition-colors
              "
            >
              Reintentar
            </button>
          </div>
        )}

        {/* Estado: Success, sin resultados */}
        {status === 'success' && filteredCount === 0 && (
          <NoResultsState onClearFilters={clearFilters} />
        )}

        {/* Estado: Success, con resultados */}
        {status === 'success' && filteredCount > 0 && (
          <>
            <CaregiverGrid caregivers={caregivers} />

            {pagination.totalPages > 1 && (
              <div className="mt-8">
                <Pagination
                  currentPage={pagination.currentPage}
                  totalPages={pagination.totalPages}
                  onPageChange={goToPage}
                />
              </div>
            )}
          </>
        )}
      </main>
    </div>
  );
}
```

---

### 1.8 Props Summary Table

Referencia rapida de todos los componentes y sus props:

| Componente | Props | Datos de | Estado |
|------------|-------|----------|--------|
| `CaregiverCard` | `id, firstName, lastName, profilePicture, zone, rating, reviewCount, servicesOffered, pricePerDay, pricePerWalk30, pricePerWalk60, verified` | `CaregiverListItem` | Stateless (memo) |
| `CaregiverGrid` | `caregivers: CaregiverListItem[]` | `useCaregivers().caregivers` | Stateless |
| `CaregiverCardSkeleton` | (none) | N/A | Stateless |
| `CaregiverGridSkeleton` | `count?: number` | N/A | Stateless |
| `VerifiedBadge` | `variant: 'compact' \| 'full'` | `CaregiverListItem.verified` | Stateless |
| `PhotoGallery` | `photos: string[], caregiverName: string` | `CaregiverDetail.photos` | `activeIndex` (useState) |
| `PhotoCarousel` | `photos: string[], caregiverName: string` | `CaregiverDetail.photos` | `currentIndex` (useState) |
| `ReviewCard` | `review: ReviewItem` | `CaregiverDetail.reviews[]` | Stateless |
| `BookingSidebar` | `caregiver: CaregiverDetail` | `useCaregiverDetail()` | `selectedService` (useState) |
| `MobileBookingBar` | `pricePerDay: number \| null, caregiverId: string` | `useCaregiverDetail()` | Stateless |
| `FilterBar` | `filters, onUpdate, onClear, hasActive, resultCount` | `useCaregivers()` | Dropdown open states |
| `FilterBottomSheet` | Same as FilterBar | Same | `isOpen` (useState) |
| `FilterDropdown` | `label, icon, options, multiple?, disabled?, value, onChange` | FilterBar passes down | `isOpen` (useState) |
| `FilterChip` | `label, active, onToggle, onRemove?` | FilterDropdown | Stateless |
| `PhotoUploader` | `photos, onAddPhotos, onRemove, onRetry, onReorder, validationErrors, maxPhotos, minPhotos, isUploading, successCount` | `usePhotoUpload()` | Drag state (refs) |
| `Pagination` | `currentPage, totalPages, onPageChange` | `useCaregivers().pagination` | Stateless |
| `NoResultsState` | `onClearFilters: () => void` | `useCaregivers()` | Stateless |
| `StarRating` | `rating: number, size?: 'sm' \| 'md'` | Review/Caregiver | Stateless |

---

## 2. Diagramas de Upload Pipeline

### 2.1 Flujo de Upload: Frontend -> Backend -> Cloudinary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         FLUJO DE UPLOAD DE FOTOS                             │
│                   (Registro de cuidador, Paso 4)                             │
└──────────────────────────────────────────────────────────────────────────────┘

  CUIDADOR                BROWSER (React)              BACKEND (Express)           CLOUDINARY
     │                         │                             │                         │
     │  Selecciona archivos    │                             │                         │
     │  o drag & drop          │                             │                         │
     │────────────────────────>│                             │                         │
     │                         │                             │                         │
     │                   ┌─────┴─────┐                       │                         │
     │                   │ VALIDAR   │                       │                         │
     │                   │ CLIENT    │                       │                         │
     │                   │           │                       │                         │
     │                   │ • Tipo:   │                       │                         │
     │                   │   JPG/PNG │                       │                         │
     │                   │   /WebP   │                       │                         │
     │                   │ • Size:   │                       │                         │
     │                   │   <=5MB   │                       │                         │
     │                   │ • Count:  │                       │                         │
     │                   │   <=6     │                       │                         │
     │                   └─────┬─────┘                       │                         │
     │                         │                             │                         │
     │                   [FALLA?]──────> Mostrar error       │                         │
     │                         │        inline (no request)  │                         │
     │                   [PASA]│                             │                         │
     │                         │                             │                         │
     │                   Crear preview local                 │                         │
     │                   (URL.createObjectURL)               │                         │
     │                         │                             │                         │
     │                   Mostrar thumbnail                   │                         │
     │                   con estado "uploading"              │                         │
     │                         │                             │                         │
     │                   ┌─────┴─────┐                       │                         │
     │                   │ XHR POST  │                       │                         │
     │                   │ multipart │   POST /api/uploads   │                         │
     │                   │ /form-data│──────────────────────>│                         │
     │                   │           │                       │                         │
     │                   │ progress  │                 ┌─────┴─────┐                   │
     │                   │ event     │                 │ VALIDAR   │                   │
     │                   │ (0-100%)  │                 │ SERVER    │                   │
     │                   │     │     │                 │           │                   │
     │                   │     │     │                 │ • multer: │                   │
     │         ┌─────────┤     │     │                 │   5MB max │                   │
     │         │ Barra de│     │     │                 │   tipo    │                   │
     │         │ progreso│     │     │                 │   MIME    │                   │
     │         │ circular│     │     │                 │           │                   │
     │         └─────────┘     │     │                 │ • auth:   │                   │
     │                   │     │     │                 │   JWT     │                   │
     │                   └─────┘     │                 │   Bearer  │                   │
     │                         │     │                 └─────┬─────┘                   │
     │                         │     │                       │                         │
     │                         │     │                 [FALLA?]──> 400/401 response    │
     │                         │     │                       │                         │
     │                         │     │                 [PASA] │                         │
     │                         │     │                       │                         │
     │                         │     │                       │  cloudinary.uploader    │
     │                         │     │                       │  .upload(buffer, {      │
     │                         │     │                       │    folder: 'garden/     │
     │                         │     │                       │      caregivers',       │
     │                         │     │                       │    transformation: {    │
     │                         │     │                       │      width: 1200,       │
     │                         │     │                       │      height: 900,       │
     │                         │     │                       │      crop: 'limit',     │
     │                         │     │                       │      quality: 'auto',   │
     │                         │     │                       │      format: 'auto',    │
     │                         │     │                       │    }                    │
     │                         │     │                       │  })                     │
     │                         │     │                       │──────────────────────>  │
     │                         │     │                       │                         │
     │                         │     │                       │     { secure_url,       │
     │                         │     │                       │       public_id,        │
     │                         │     │                       │       width, height,    │
     │                         │     │                       │       format, bytes }   │
     │                         │     │                       │ <──────────────────────│
     │                         │     │                       │                         │
     │                         │     │   200 OK              │                         │
     │                         │     │   { data: {           │                         │
     │                         │     │       url: secure_url │                         │
     │                         │     │       publicId: ...   │                         │
     │                         │     │   }}                  │                         │
     │                         │     │<──────────────────────│                         │
     │                         │     │                       │                         │
     │                   Actualizar estado:                  │                         │
     │                   status: 'success'                   │                         │
     │                   cloudinaryUrl: url                  │                         │
     │                   Mostrar check verde                 │                         │
     │                         │                             │                         │
     │  Ve foto subida con     │                             │                         │
     │  check verde            │                             │                         │
     │<────────────────────────│                             │                         │
     │                         │                             │                         │
```

### 2.2 Backend: Endpoint de Upload

```typescript
// src/modules/uploads/upload.controller.ts

import { Request, Response } from 'express';
import { v2 as cloudinary } from 'cloudinary';
import { asyncHandler } from '../../utils/async-handler';
import { BadRequestError } from '../../utils/errors';

// Configuracion Cloudinary (en config/cloudinary.ts)
// cloudinary.config({
//   cloud_name: env.CLOUDINARY_CLOUD_NAME,
//   api_key: env.CLOUDINARY_API_KEY,
//   api_secret: env.CLOUDINARY_API_SECRET,
// });

const ALLOWED_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
const MAX_FILE_SIZE = 5 * 1024 * 1024; // 5MB

/**
 * POST /api/uploads/photo
 * Sube una foto a Cloudinary.
 * Requiere autenticacion (JWT).
 * Acepta multipart/form-data con campo "photo".
 */
export const uploadPhoto = asyncHandler(async (req: Request, res: Response) => {
  const file = req.file; // multer single('photo')

  if (!file) {
    throw new BadRequestError('No se envio ninguna foto');
  }

  // Validar tipo MIME (doble chequeo, multer ya filtra)
  if (!ALLOWED_MIME_TYPES.includes(file.mimetype)) {
    throw new BadRequestError(
      `Formato no soportado: ${file.mimetype}. Usa JPG, PNG o WebP.`
    );
  }

  // Validar tamano
  if (file.size > MAX_FILE_SIZE) {
    throw new BadRequestError(
      `Archivo muy grande: ${(file.size / 1024 / 1024).toFixed(1)}MB. Maximo: 5MB.`
    );
  }

  // Subir a Cloudinary
  const result = await new Promise<any>((resolve, reject) => {
    const uploadStream = cloudinary.uploader.upload_stream(
      {
        folder: 'garden/caregivers',
        transformation: [
          {
            width: 1200,
            height: 900,
            crop: 'limit',    // No agranda, solo reduce
            quality: 'auto',  // Cloudinary optimiza
            fetch_format: 'auto', // WebP si el browser soporta
          },
        ],
        resource_type: 'image',
      },
      (error, result) => {
        if (error) reject(error);
        else resolve(result);
      }
    );

    uploadStream.end(file.buffer);
  });

  res.status(200).json({
    success: true,
    data: {
      url: result.secure_url,
      publicId: result.public_id,
      width: result.width,
      height: result.height,
      format: result.format,
      bytes: result.bytes,
    },
  });
});
```

```typescript
// src/modules/uploads/upload.routes.ts

import { Router } from 'express';
import multer from 'multer';
import { authenticate } from '../../middleware/auth.middleware';
import * as uploadController from './upload.controller';

const router = Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const allowed = ['image/jpeg', 'image/png', 'image/webp'];
    if (allowed.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Formato no soportado'));
    }
  },
});

router.post(
  '/photo',
  authenticate,
  upload.single('photo'),
  uploadController.uploadPhoto
);

export default router;
```

### 2.3 Flujo de Error en Upload

```
  Escenario de error y recovery:

  ┌───────────┐     ┌───────────┐     ┌───────────┐
  │ USUARIO   │     │  FRONTEND │     │  BACKEND  │
  │ sube foto │────>│  valida   │────>│  procesa  │
  └───────────┘     └─────┬─────┘     └─────┬─────┘
                          │                  │
              ┌───────────┼──────────────────┼──────────────────┐
              │           │                  │                  │
         ┌────▼────┐ ┌────▼────┐       ┌────▼────┐       ┌────▼────┐
         │ Error   │ │ Error   │       │ Error   │       │ Error   │
         │ client  │ │ network │       │ server  │       │ Cloudi- │
         │ ────────│ │ ────────│       │ ────────│       │ nary    │
         │         │ │         │       │         │       │ ────────│
         │ "Formato│ │ "Error  │       │ 401:    │       │ "Could  │
         │  no     │ │  de red"│       │ Token   │       │  not    │
         │  sopor- │ │         │       │ expirado│       │  upload"│
         │  tado"  │ │ Mostrar │       │         │       │         │
         │         │ │ retry   │       │ Redirect│       │ Mostrar │
         │ NO envía│ │ button  │       │ a login │       │ retry   │
         │ request │ │         │       │         │       │ button  │
         └─────────┘ └────┬────┘       └─────────┘       └────┬────┘
                          │                                    │
                          │          ┌──────────────┐          │
                          └─────────>│   REINTENTAR │<─────────┘
                                     │              │
                                     │ Misma foto,  │
                                     │ mismo slot,  │
                                     │ nuevo request│
                                     └──────────────┘
```

---

## 3. Responsive Breakpoints

### 3.1 Sistema de Breakpoints

Tailwind default breakpoints alineados con los layouts del wireframe:

```typescript
// tailwind.config.ts - breakpoints (usando defaults de Tailwind)

// sm:  640px   → Telefono grande / landscape
// md:  768px   → Tablet portrait
// lg:  1024px  → Tablet landscape / desktop
// xl:  1280px  → Desktop standard
// 2xl: 1536px  → Desktop wide

// NOTA: No se agregan custom breakpoints.
// Mobile-first: sin prefijo = mobile (360px+)
```

### 3.2 Responsive Behavior por Componente

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    RESPONSIVE MATRIX                                     │
├───────────────┬──────────┬──────────┬──────────┬──────────┬────────────┤
│ Componente    │ < 640    │ sm 640   │ md 768   │ lg 1024  │ xl 1280+   │
│               │ (mobile) │          │ (tablet) │          │ (desktop)  │
├───────────────┼──────────┼──────────┼──────────┼──────────┼────────────┤
│ Grid cols     │ 1        │ 2        │ 2        │ 3        │ 3          │
│ Gap           │ 16px     │ 16px     │ 24px     │ 24px     │ 24px       │
│ Padding       │ 16px     │ 16px     │ 24px     │ 32px     │ 32px       │
├───────────────┼──────────┼──────────┼──────────┼──────────┼────────────┤
│ Card foto     │ full-w   │ full-w   │ full-w   │ full-w   │ full-w     │
│ Card ratio    │ 16:9     │ 16:9     │ 16:9     │ 16:9     │ 16:9       │
│ Card padding  │ 12px     │ 12px     │ 16px     │ 16px     │ 16px       │
├───────────────┼──────────┼──────────┼──────────┼──────────┼────────────┤
│ Filtros       │ Bottom   │ Bottom   │ Inline   │ Inline   │ Inline     │
│               │ sheet    │ sheet    │ sticky   │ sticky   │ sticky     │
├───────────────┼──────────┼──────────┼──────────┼──────────┼────────────┤
│ Detalle       │ Stack    │ Stack    │ Stack    │ 2-col    │ 2-col      │
│ layout        │ vert.    │ vert.    │ vert.    │ (8/4)    │ (8/4)      │
├───────────────┼──────────┼──────────┼──────────┼──────────┼────────────┤
│ Galeria       │Carousel  │Carousel  │Carousel  │Gallery   │Gallery     │
│               │swipe     │swipe     │swipe     │thumb+    │thumb+      │
│               │          │          │          │main      │main        │
├───────────────┼──────────┼──────────┼──────────┼──────────┼────────────┤
│ Booking CTA   │ Sticky   │ Sticky   │ Sticky   │ Sidebar  │ Sidebar    │
│               │ bottom   │ bottom   │ bottom   │ sticky   │ sticky     │
├───────────────┼──────────┼──────────┼──────────┼──────────┼────────────┤
│ Photo upload  │ 2 cols   │ 3 cols   │ 3 cols   │ 3 cols   │ 3 cols     │
│ grid          │          │          │          │          │            │
├───────────────┼──────────┼──────────┼──────────┼──────────┼────────────┤
│ Pagination    │ < 1 2 >  │ < 1 2 3 >│ Full     │ Full     │ Full       │
│               │ (compact)│ (compact)│          │          │            │
└───────────────┴──────────┴──────────┴──────────┴──────────┴────────────┘
```

### 3.3 Tailwind Classes por Layout

```tsx
// ---- Listing Grid ----
className="
  grid
  grid-cols-1      // mobile: 1 columna
  sm:grid-cols-2   // 640px+: 2 columnas
  lg:grid-cols-3   // 1024px+: 3 columnas
  gap-4            // mobile: 16px gap
  sm:gap-6         // 640px+: 24px gap
"

// ---- Page Container ----
className="
  max-w-7xl mx-auto
  px-4             // mobile: 16px padding
  sm:px-6          // 640px+: 24px
  lg:px-8          // 1024px+: 32px
"

// ---- Detalle: 2-col layout ----
className="
  flex flex-col       // mobile: stack vertical
  lg:flex-row         // 1024px+: side by side
  lg:gap-8            // 1024px+: 32px entre columnas
"
// Columna principal
className="flex-1 lg:max-w-2xl xl:max-w-3xl"
// Sidebar
className="lg:w-80 xl:w-96 shrink-0"

// ---- Filtros: inline vs bottom sheet ----
// El switch se hace en el componente padre:
const isMobile = useMediaQuery('(max-width: 767px)');
// md: 768px es el cutoff entre bottom sheet y inline

// ---- CTA sticky bottom (solo mobile) ----
className="
  fixed bottom-0 inset-x-0
  bg-white border-t border-gray-200
  p-4 pb-safe
  z-30
  md:hidden          // oculto en 768px+
"

// ---- Sidebar sticky (solo desktop) ----
className="
  hidden lg:block    // oculto hasta 1024px
  sticky top-24
"

// ---- Photo upload grid ----
className="
  grid
  grid-cols-2        // mobile: 2 slots
  sm:grid-cols-3     // 640px+: 3 slots
  gap-3
"

// ---- Pagination compact (mobile) ----
// Mobile: solo muestra pagina actual + prev/next
// Desktop: muestra todas las paginas
className="
  flex items-center justify-center gap-2
"
// Pages intermedias:
className="hidden sm:flex"   // ocultas en mobile
```

### 3.4 Hook: `useMediaQuery`

```typescript
// src/hooks/useMediaQuery.ts

import { useState, useEffect } from 'react';

export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(() => {
    if (typeof window === 'undefined') return false;
    return window.matchMedia(query).matches;
  });

  useEffect(() => {
    const mql = window.matchMedia(query);

    function handleChange(e: MediaQueryListEvent) {
      setMatches(e.matches);
    }

    mql.addEventListener('change', handleChange);
    return () => mql.removeEventListener('change', handleChange);
  }, [query]);

  return matches;
}
```

### 3.5 Cloudinary Responsive: srcSet por Breakpoint

```tsx
// Calculo de srcSet alineado con breakpoints de Tailwind

function getCaregiveCardSrcSet(baseUrl: string): string {
  // Mobile (1 col): card ocupa ~100vw → 400px suficiente
  // sm (2 cols): card ocupa ~50vw → 320px suficiente
  // lg (3 cols): card ocupa ~33vw → 400px suficiente
  // Retina: duplicar

  const widths = [320, 400, 640, 800];

  return widths
    .map(w => {
      const url = baseUrl.replace(
        '/upload/',
        `/upload/c_fill,w_${w},h_${Math.round(w * 9 / 16)},q_auto,f_auto/`
      );
      return `${url} ${w}w`;
    })
    .join(', ');
}

// Uso en el card:
<img
  src={getOptimizedUrl(photo, 400, 225)}
  srcSet={getCaregiveCardSrcSet(photo)}
  sizes="
    (max-width: 639px) 100vw,
    (max-width: 1023px) 50vw,
    33vw
  "
  loading="lazy"
  decoding="async"
/>
```

---

## 4. Estrategia de Iteracion

### 4.1 Matriz de Cambios de Schema y su Impacto en UI

Cuando el schema de Prisma evolucione, esta tabla guia exactamente que tocar en el frontend:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    EVOLUCION DEL SCHEMA: PLAN DE IMPACTO                     │
├────────────────────────┬────────────────────┬────────────────────────────────┤
│ Cambio en Prisma       │ Impacto en frontend│ Archivos a modificar           │
├────────────────────────┼────────────────────┼────────────────────────────────┤
│                        │                    │                                │
│ CaregiverProfile:      │ BAJO               │ types/caregiver.ts             │
│   + acceptsCats Bool?  │ Nuevo chip en      │ CaregiverCard.tsx (chip)       │
│                        │ detalle + filtro   │ FilterBar.tsx (nuevo filtro)   │
│                        │                    │ useCaregivers.ts (logica)      │
│                        │                    │                                │
├────────────────────────┼────────────────────┼────────────────────────────────┤
│                        │                    │                                │
│ CaregiverProfile:      │ BAJO               │ types/caregiver.ts             │
│   + maxPetsAtOnce Int? │ Dato en detalle    │ CaregiverDetailPage.tsx        │
│                        │ (no en card)       │ (solo seccion detalles)        │
│                        │                    │                                │
├────────────────────────┼────────────────────┼────────────────────────────────┤
│                        │                    │                                │
│ CaregiverProfile:      │ MEDIO              │ types/caregiver.ts             │
│   rating Float -> Int  │ Formateo cambia    │ StarRating.tsx                 │
│                        │ .toFixed(1) → ""   │ (quitar toFixed)               │
│                        │                    │                                │
├────────────────────────┼────────────────────┼────────────────────────────────┤
│                        │                    │                                │
│ CaregiverProfile:      │ BAJO               │ types/caregiver.ts             │
│   + introVideoUrl Str? │ Nuevo slot en      │ PhotoGallery.tsx               │
│                        │ galeria            │ PhotoCarousel.tsx              │
│                        │ (video player)     │ (render condicional)           │
│                        │                    │                                │
├────────────────────────┼────────────────────┼────────────────────────────────┤
│                        │                    │                                │
│ CaregiverProfile:      │ BAJO               │ types/caregiver.ts             │
│   + latitude Float?    │ Permite vista mapa │ Nuevo: MapView.tsx (V2)        │
│   + longitude Float?   │ (feature V2)       │ FilterBar (toggle lista/mapa) │
│                        │                    │                                │
├────────────────────────┼────────────────────┼────────────────────────────────┤
│                        │                    │                                │
│ Nuevo enum:            │ MEDIO              │ types/caregiver.ts             │
│   ServiceType:         │ Nuevo chip color   │ CaregiverCard.tsx              │
│   + ENTRENAMIENTO      │ Nuevo filtro       │ FilterBar.tsx                  │
│                        │ Nuevos precios     │ BookingSidebar.tsx             │
│                        │                    │ StepServices.tsx               │
│                        │                    │ useCaregivers.ts               │
│                        │                    │                                │
├────────────────────────┼────────────────────┼────────────────────────────────┤
│                        │                    │                                │
│ Nuevo modelo:          │ BAJO               │ types/caregiver.ts             │
│   Favorite             │ Icono corazon en   │ CaregiverCard.tsx (icono)      │
│   { userId, profileId }│ card + detalle     │ Nuevo: useFavorites.ts         │
│                        │                    │ Nuevo: FavoritesPage.tsx       │
│                        │                    │                                │
├────────────────────────┼────────────────────┼────────────────────────────────┤
│                        │                    │                                │
│ Zone: cambiar de       │ BAJO               │ types/caregiver.ts             │
│   String a Enum        │ Cambiar constante  │ (Zone type ya era union type)  │
│   EQUIPETROL, URBARI.. │ ZONES              │ constants.ts (fuente unica)    │
│                        │                    │                                │
├────────────────────────┼────────────────────┼────────────────────────────────┤
│                        │                    │                                │
│ Agregar paginacion     │ MEDIO              │ useCaregivers.ts               │
│   server-side          │ Reemplazar fetch   │ (cambiar de fetch-all a        │
│   (>200 cuidadores)    │ unico por fetch    │  fetch-per-page, filtros al    │
│                        │ paginado + filtros │  backend como query params)    │
│                        │ al backend         │ FilterBar (debounce onChange)  │
│                        │                    │                                │
└────────────────────────┴────────────────────┴────────────────────────────────┘
```

### 4.2 Estrategia de Migracion: Client-Side -> Server-Side Filtering

Cuando el numero de cuidadores supere ~200, el filtrado client-side se vuelve ineficiente. Plan de migracion:

```
FASE 1 (MVP, 0-200 cuidadores):
─────────────────────────────────
  Browser                                Backend
  ┌──────────────────────┐              ┌───────────────────┐
  │ GET /caregivers      │─────────────>│ SELECT * FROM     │
  │     ?limit=200       │              │ caregiver_profiles│
  │                      │<─────────────│ WHERE verified    │
  │ Recibe TODOS         │   200 items  │ AND NOT suspended │
  │                      │              └───────────────────┘
  │ Filtros en useMemo() │
  │ (instantaneo, 0 lag) │
  └──────────────────────┘

FASE 2 (Crecimiento, 200-1000 cuidadores):
──────────────────────────────────────────
  Browser                                Backend
  ┌──────────────────────┐              ┌───────────────────────┐
  │ GET /caregivers      │─────────────>│ SELECT * FROM         │
  │   ?service=HOSPEDAJE │              │ caregiver_profiles    │
  │   &zone=equipetrol   │              │ WHERE verified        │
  │   &priceMin=100      │              │ AND NOT suspended     │
  │   &priceMax=140      │              │ AND zone = 'equip.'   │
  │   &spaceType=casa_.. │              │ AND price_per_day     │
  │   &page=1            │              │   BETWEEN 100 AND 140 │
  │   &limit=12          │              │ ORDER BY rating DESC  │
  │                      │<─────────────│ LIMIT 12 OFFSET 0     │
  │ Recibe 12 items      │   12 items   └───────────────────────┘
  │ No filtra localmente │
  │                      │
  │ Filtro onChange →     │
  │   debounce(300ms) →  │
  │   nuevo fetch         │
  └──────────────────────┘

  Cambios necesarios:
  1. Backend: agregar query params al GET /api/caregivers
  2. Frontend: useCaregivers.ts → reemplazar useMemo con useEffect+fetch
  3. Frontend: FilterBar → debounce de 300ms en onChange
  4. Remover: logica de filtrado client-side en useMemo
```

### 4.3 Feature Flags para Rollout Gradual

```typescript
// src/config/features.ts
// Feature flags para habilitar funcionalidad V2 sin riesgo

export const FEATURES = {
  /** Filtrado client-side vs server-side */
  CLIENT_SIDE_FILTERING: true,  // false cuando >200 cuidadores

  /** Infinite scroll vs paginacion clasica */
  INFINITE_SCROLL: false,       // true en V2

  /** Lightbox con zoom en fotos */
  PHOTO_LIGHTBOX: false,        // true en V2

  /** Vista de mapa alternativa */
  MAP_VIEW: false,              // true cuando tengamos lat/lng

  /** Favoritos */
  FAVORITES: false,             // true cuando exista modelo Favorite

  /** Video intro en perfil */
  VIDEO_INTRO: false,           // true cuando exista introVideoUrl
} as const;

// Uso en componente:
// {FEATURES.PHOTO_LIGHTBOX && <PhotoLightbox ... />}
// {FEATURES.MAP_VIEW && <MapToggle ... />}
```

---

## 5. Self-Review Cruzado

### 5.1 Validacion contra Schema Prisma

| Campo Prisma `CaregiverProfile` | Usado en Listing | Usado en Detalle | Usado en Registro | Notas |
|----------------------------------|:---:|:---:|:---:|-------|
| `id` (uuid) | Card key + link | URL param | Auto-generado | OK |
| `userId` (FK) | No | No | Auth register crea | OK: relacion interna |
| `bio` (String?) | No | Si | Paso 2 textarea | OK: no en card (descarte rapido) |
| `zone` (String) | Si (chip + filtro) | Si | Paso 2 select | OK |
| `spaceType` (String?) | No (filtro si) | Si | Paso 2 radio | OK: solo visible post-filtro |
| `photos` (String[]) | photos[0] = thumb | Galeria completa | Paso 4 upload | OK |
| `servicesOffered` (ServiceType[]) | Si (chips) | Si + precios | Paso 3 checkboxes | OK |
| `pricePerDay` (Int?) | Si (si hospedaje) | Si | Paso 3 input | OK |
| `pricePerWalk30` (Int?) | Si (si paseos) | Si | Paso 3 input | OK |
| `pricePerWalk60` (Int?) | No | Si | Paso 3 input | OK: detalle solo |
| `verified` (Boolean) | Badge en foto | Badge full | No (admin-only) | OK |
| `suspended` (Boolean) | No (filtrado) | No (filtrado) | No | OK: backend filtra |
| `rating` (Float) | Estrellas | Estrellas | No | OK |
| `reviewCount` (Int) | "(12)" | "12 resenas" | No | OK |
| `approvedAt` (DateTime?) | No | No | No | OK: admin-internal |
| `suspendedAt` (DateTime?) | No | No | No | OK: admin-internal |
| `suspensionReason` (String?) | No | No | No | OK: admin-internal |

**Resultado: 100% de campos del schema mapeados a la UI o intencionalmente omitidos con justificacion.**

### 5.2 Inconsistencias Detectadas y Resueltas

#### Inconsistencia 1: Servicio "AMBOS" no existe en schema
- **Detectado:** El filtro de servicio tiene opcion "Ambos" pero en Prisma `servicesOffered` es `ServiceType[]` donde los valores son `HOSPEDAJE` y `PASEO`. No hay valor `AMBOS`.
- **Resolucion:** `AMBOS` es una opcion de filtro en UI, no un valor del schema. Cuando el usuario selecciona "Ambos", el filtro no se aplica (muestra todos). Cuando selecciona "Hospedaje", filtra `servicesOffered.includes('HOSPEDAJE')`. El tipo `CaregiverFilters.service` tiene `'AMBOS'` como valor de UI que resulta en "sin filtro de servicio". Esto es correcto.

#### Inconsistencia 2: profilePicture (User) vs photos[0] (CaregiverProfile)
- **Detectado:** El schema `User` tiene `profilePicture: String?` (foto de perfil del usuario) y `CaregiverProfile` tiene `photos: String[]` (fotos del espacio). El card del listing usa la foto del espacio (photos[0]), no el profilePicture del User.
- **Resolucion:** Intencionalmente correcto. El MVP enfatiza "Foto REAL de la casa/patio donde estara la mascota" como primera impresion. El `profilePicture` del User se usa en el header de navegacion (avatar pequeno), no en el listing. El backend endpoint `GET /api/caregivers` deberia devolver `photos[0]` como `profilePicture` en el DTO del listing para evitar confusion. Se documenta como convencion.

#### Inconsistencia 3: `photos` se guarda como String[] en Prisma pero se sube una por una
- **Detectado:** El upload es individual (un archivo por request a `/api/uploads/photo`), pero el perfil se guarda como array `photos: String[]`. Faltaba documentar cuando se escribe el array en la DB.
- **Resolucion:** El array se escribe en el `PUT /api/caregivers/profile` despues de todos los uploads. El flujo es: (1) subir foto individual → obtener URL Cloudinary, (2) repetir para cada foto, (3) enviar todas las URLs en el body de profile update. El hook `usePhotoUpload` acumula `cloudinaryUrls` y el hook `useCaregiverRegistration.submit()` las envía en un solo `PUT`.

#### Inconsistencia 4: Rangos de precio paseo no diferenciados en filtro
- **Detectado:** El doc tecnico y MVP tienen rangos diferentes para hospedaje y paseos. El objeto `PRICE_RANGES` ahora maneja ambos, pero el filtro en la UI no cambiaba sus labels cuando el usuario switchea entre servicio hospedaje y paseos.
- **Resolucion:** El componente `FilterDropdown` para precio recibe `priceContext` que cambia segun `filters.service`. Si service="PASEO", muestra "Economico: Bs 20-30". Si service="HOSPEDAJE" o null, muestra "Economico: Bs 60-100". Los labels del dropdown son dinamicos.

#### Inconsistencia 5: `spaceType` es `String?` en Prisma pero deberia ser un enum
- **Detectado:** El schema usa `spaceType String?` con valores magicos "casa_patio", "casa_sin_patio", "departamento". Esto permite typos y no tiene validacion a nivel DB.
- **Resolucion:** Para MVP, mantener como String con validacion Zod en backend y tipo union en frontend `type SpaceType = 'casa_patio' | 'casa_sin_patio' | 'departamento'`. Para V2, migrar a enum Prisma `enum SpaceType { CASA_PATIO CASA_SIN_PATIO DEPARTAMENTO }`. El frontend ya usa el tipo union, asi que el cambio seria transparente si se renombran los valores (se maneja con un mapper).

### 5.3 Cobertura de Estados UI

| Estado | Listing | Detalle | Upload | Formulario |
|--------|---------|---------|--------|------------|
| **idle** | Muestra skeleton antes de fetch | Muestra skeleton | Grid vacio con slots "+" | Campos vacios |
| **loading** | `CaregiverGridSkeleton` (6 cards) | Skeleton de foto+info | Barra progreso circular por foto | Boton disabled con spinner |
| **success** | Grid de cards con datos | Perfil completo | Check verde por foto | Pantalla de confirmacion |
| **error (network)** | Mensaje + boton "Reintentar" | Mensaje + "Reintentar" | Icono warning + "Reintentar" por foto | Mensaje inline + submit activo |
| **error (validation)** | N/A | N/A | Lista de archivos rechazados con motivo | Mensaje por campo invalido |
| **error (404)** | N/A | "Cuidador no encontrado" | N/A | "Email ya registrado" |
| **empty** | `NoResultsState` + "Limpiar filtros" | N/A | N/A | N/A |
| **partial** | N/A | N/A | Mix de success/uploading/error | Pasos completados en stepper |

### 5.4 Checklist Final

| Aspecto | Status | Evidencia |
|---------|--------|-----------|
| Types alineados con Prisma schema | OK | Section 1.1: CaregiverListItem fields match CaregiverProfile columns |
| Fetch con AbortController | OK | useCaregivers + useCaregiverDetail: cleanup en useEffect return |
| Validacion client-side espejo de Zod backend | OK | useCaregiverRegistration: mismas reglas que auth.validation.ts |
| Upload con progreso real | OK | usePhotoUpload: XHR con upload.progress event |
| Memory leak prevention (ObjectURL) | OK | usePhotoUpload.removePhoto: URL.revokeObjectURL |
| Error recovery (retry) | OK | Listing: retry button. Upload: retry per-photo. Form: submit activo post-error |
| Accesibilidad ARIA | OK | role="alert" en errores, aria-live="polite" en contador, aria-label en acciones |
| Filtro espacio disabled si paseos | OK | FilterBar: disabled prop cuando service=PASEO |
| Precios en Bs (Bolivianos) | OK | Todos los precios con "Bs " prefix |
| Fotos reales, no stock | OK | Alt texts dicen "Espacio de [nombre]", guia de fotos en doc anterior |
| Responsive mobile-first | OK | Section 3: grid-cols-1 → sm:2 → lg:3, bottom sheet en mobile |
| Cloudinary transforms por contexto | OK | srcSet con widths, sizes con breakpoints de Tailwind |
| Feature flags para V2 | OK | Section 4.3: FEATURES object con boolean flags |

---

**FIN DEL DOCUMENTO DE REFINAMIENTO**
