import { useState, useCallback } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useMutation } from '@tanstack/react-query';
import { api } from '@/api/client';
import { PhotoUploader } from '@/components/PhotoUploader';
import {
  caregiverProfileFormSchema,
  type CaregiverProfileFormValues,
} from '@/forms/caregiverProfileFormSchema';
import { ZONES, ZONE_LABELS } from '@/types/caregiver';
import type { ServiceType, Zone } from '@/types/caregiver';

const MIN_PHOTOS = 4;
const MAX_PHOTOS = 6;

export function CaregiverProfileForm() {
  const [photos, setPhotos] = useState<File[]>([]);
  const [success, setSuccess] = useState(false);

  const {
    register,
    handleSubmit,
    formState: { errors },
    watch,
    setValue,
  } = useForm<CaregiverProfileFormValues>({
    resolver: zodResolver(caregiverProfileFormSchema),
    defaultValues: {
      bio: '',
      zone: undefined,
      spaceType: [] as string[],
      servicesOffered: [],
      pricePerDay: undefined,
      pricePerWalk30: undefined,
      pricePerWalk60: undefined,
    },
  });

  const servicesOffered = watch('servicesOffered') ?? [];

  const toggleService = useCallback(
    (s: ServiceType) => {
      const next = servicesOffered.includes(s)
        ? servicesOffered.filter((x) => x !== s)
        : [...servicesOffered, s];
      setValue('servicesOffered', next, { shouldValidate: true });
    },
    [servicesOffered, setValue]
  );

  const mutation = useMutation({
    mutationFn: async (data: CaregiverProfileFormValues) => {
      if (photos.length < MIN_PHOTOS || photos.length > MAX_PHOTOS) {
        throw new Error(`Sube entre ${MIN_PHOTOS} y ${MAX_PHOTOS} fotos`);
      }
      const formData = new FormData();
      formData.append('data', JSON.stringify({
        bio: data.bio,
        zone: data.zone,
        spaceType: Array.isArray(data.spaceType) && data.spaceType.length > 0 ? data.spaceType : undefined,
        servicesOffered: data.servicesOffered,
        pricePerDay: data.pricePerDay ?? undefined,
        pricePerWalk30: data.pricePerWalk30 ?? undefined,
        pricePerWalk60: data.pricePerWalk60 ?? undefined,
      }));
      photos.forEach((f) => formData.append('photos', f));

      const res = await api.postForm<{ success: boolean; data?: unknown; error?: { message?: string } }>(
        '/api/caregivers',
        formData
      );
      if (!res.data?.success) {
        throw new Error(res.data?.error?.message ?? 'Error al guardar');
      }
      return res.data;
    },
    onSuccess: () => setSuccess(true),
  });

  const onSubmit = useCallback(
    (data: CaregiverProfileFormValues) => {
      if (photos.length < MIN_PHOTOS || photos.length > MAX_PHOTOS) return;
      mutation.mutate(data);
    },
    [photos.length, mutation]
  );

  const photoError =
    photos.length > 0 && (photos.length < MIN_PHOTOS || photos.length > MAX_PHOTOS)
      ? `Se requieren entre ${MIN_PHOTOS} y ${MAX_PHOTOS} fotos`
      : undefined;

  if (success) {
    return (
      <div className="rounded-xl border border-green-200 bg-green-50 p-6 text-center">
        <p className="text-lg font-medium text-green-800">Perfil enviado para verificación</p>
        <p className="mt-1 text-sm text-green-700">
          Revisaremos tu perfil y te avisaremos cuando esté publicado.
        </p>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
      <div>
        <label className="block text-sm font-medium text-gray-700">Descripción (bio) *</label>
        <textarea
          {...register('bio')}
          rows={4}
          maxLength={500}
          placeholder="Cuéntanos sobre tu espacio y experiencia con mascotas..."
          className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
        />
        <p className="mt-0.5 text-xs text-gray-500">Máximo 500 caracteres</p>
        {errors.bio && <p className="mt-1 text-sm text-red-600">{errors.bio.message}</p>}
      </div>

      <PhotoUploader
        value={photos}
        onChange={setPhotos}
        disabled={mutation.isPending}
        error={photoError}
      />

      <div>
        <label className="block text-sm font-medium text-gray-700">Zona *</label>
        <select
          {...register('zone')}
          className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
        >
          <option value="">Selecciona zona</option>
          {ZONES.map((z) => (
            <option key={z} value={z}>
              {ZONE_LABELS[z as Zone]}
            </option>
          ))}
        </select>
        {errors.zone && <p className="mt-1 text-sm text-red-600">{errors.zone.message}</p>}
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700">Tipo de espacio (opcional)</label>
        <p className="mt-1 text-xs text-gray-500">Selecciona los que apliquen.</p>
        {['Casa con patio', 'Casa sin patio', 'Departamento pequeño', 'Departamento amplio'].map((option) => {
          const selected = Array.isArray(watch('spaceType')) && watch('spaceType').includes(option);
          return (
            <label key={option} className="mt-2 flex cursor-pointer items-center gap-2">
              <input
                type="checkbox"
                checked={selected}
                onChange={() => {
                  const current = watch('spaceType') ?? [];
                  const next = selected ? current.filter((s) => s !== option) : [...current, option];
                  setValue('spaceType', next, { shouldValidate: true });
                }}
                className="rounded border-gray-300 text-green-600 focus:ring-green-500"
              />
              <span className="text-sm text-gray-700">{option}</span>
            </label>
          );
        })}
        {errors.spaceType && (
          <p className="mt-1 text-sm text-red-600">{errors.spaceType.message}</p>
        )}
      </div>

      <div>
        <span className="block text-sm font-medium text-gray-700">Servicios que ofreces *</span>
        <div className="mt-2 flex gap-4">
          <label className="flex cursor-pointer items-center gap-2">
            <input
              type="checkbox"
              checked={servicesOffered.includes('HOSPEDAJE')}
              onChange={() => toggleService('HOSPEDAJE')}
              className="rounded border-gray-300 text-green-600 focus:ring-green-500"
            />
            Hospedaje
          </label>
          <label className="flex cursor-pointer items-center gap-2">
            <input
              type="checkbox"
              checked={servicesOffered.includes('PASEO')}
              onChange={() => toggleService('PASEO')}
              className="rounded border-gray-300 text-green-600 focus:ring-green-500"
            />
            Paseos
          </label>
        </div>
        {errors.servicesOffered && (
          <p className="mt-1 text-sm text-red-600">{errors.servicesOffered.message}</p>
        )}
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <div>
          <label className="block text-sm font-medium text-gray-700">Precio/día (Bs)</label>
          <input
            type="number"
            min={0}
            {...register('pricePerDay', { valueAsNumber: true })}
            className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">Paseo 30 min (Bs)</label>
          <input
            type="number"
            min={0}
            {...register('pricePerWalk30', { valueAsNumber: true })}
            className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">Paseo 60 min (Bs)</label>
          <input
            type="number"
            min={0}
            {...register('pricePerWalk60', { valueAsNumber: true })}
            className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
          />
        </div>
      </div>

      {mutation.isError && (
        <div className="rounded-lg bg-red-50 p-3 text-sm text-red-700">
          {(mutation.error as Error).message}
        </div>
      )}

      <button
        type="submit"
        disabled={mutation.isPending}
        className="w-full rounded-lg bg-green-600 px-4 py-3 font-medium text-white hover:bg-green-700 disabled:opacity-50"
      >
        {mutation.isPending ? 'Guardando...' : 'Enviar perfil'}
      </button>
    </form>
  );
}
