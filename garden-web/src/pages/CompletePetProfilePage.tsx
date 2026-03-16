import { useState, useEffect } from 'react';
import { useNavigate, useLocation, Link } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useQueryClient } from '@tanstack/react-query';
import { useClientMyProfile, CLIENT_MY_PROFILE_QUERY_KEY } from '@/hooks/useClientMyProfile';
import { useAuth } from '@/contexts/AuthContext';
import { uploadPetPhoto, type ClientMyProfileData } from '@/api/clientProfile';
import { createClientPet, patchClientPet } from '@/api/clientPets';
import { useClientPets, CLIENT_PETS_QUERY_KEY } from '@/hooks/useClientPets';
import { getImageUrl } from '@/utils/images';
import toast from 'react-hot-toast';
import { useDropzone } from 'react-dropzone';

const petProfileSchema = z.object({
  petName: z.string().min(1, 'Nombre de mascota requerido').max(200),
  petBreed: z.string().max(100).optional(),
  petAge: z.number().int().min(0).max(30).optional().nullable(),
  petSize: z.enum(['SMALL', 'MEDIUM', 'LARGE', 'GIANT'], {
    required_error: 'Selecciona el tamaño de tu mascota',
  }),
  petPhoto: z.union([z.string().url(), z.literal('')]).optional(),
  specialNeeds: z.string().max(2000).optional(),
  notes: z.string().max(2000).optional(),
});

type PetProfileFormValues = z.infer<typeof petProfileSchema>;

const PET_SIZE_LABELS: Record<'SMALL' | 'MEDIUM' | 'LARGE' | 'GIANT', string> = {
  SMALL: 'Pequeño',
  MEDIUM: 'Mediano',
  LARGE: 'Grande',
  GIANT: 'Gigante',
};

/**
 * Página para completar el perfil de la mascota del cliente.
 * Usa el modelo Pet: crea una mascota (POST /api/client/pets) o edita la primera (PATCH).
 * La foto se sube a Cloudinary (POST /api/upload/pet-photo) y la URL se guarda en Pet.photoUrl.
 */
export function CompletePetProfilePage() {
  const navigate = useNavigate();
  const location = useLocation();
  const { isAuthenticated, refreshUser } = useAuth();
  const queryClient = useQueryClient();
  const { data: myProfile, isLoading: loadingProfile, refetch: refetchProfile } = useClientMyProfile();
  const { refetch: refetchPets } = useClientPets();
  const [petPhotoFile, setPetPhotoFile] = useState<File | null>(null);
  const [petPhotoPreview, setPetPhotoPreview] = useState<string | null>(null);
  const [uploadingPhoto, setUploadingPhoto] = useState(false);
  const [saving, setSaving] = useState(false);

  const firstPet = myProfile?.pets?.[0] ?? null;

  const {
    register,
    handleSubmit,
    formState: { errors },
    setValue,
  } = useForm<PetProfileFormValues>({
    resolver: zodResolver(petProfileSchema),
    defaultValues: {
      petName: '',
      petBreed: '',
      petAge: null,
      petSize: undefined,
      petPhoto: '',
      specialNeeds: '',
      notes: '',
    },
  });

  // Prefill desde la primera mascota si existe
  useEffect(() => {
    if (firstPet) {
      setValue('petName', firstPet.name);
      setValue('petBreed', firstPet.breed ?? '');
      setValue('petAge', firstPet.age ?? null);
      setValue('petSize', firstPet.size ?? undefined);
      setValue('petPhoto', firstPet.photoUrl ?? '');
      setValue('specialNeeds', firstPet.specialNeeds ?? '');
      setValue('notes', firstPet.notes ?? '');
      if (firstPet.photoUrl) {
        setPetPhotoPreview(firstPet.photoUrl);
      }
    }
  }, [firstPet, setValue]);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    accept: {
      'image/jpeg': ['.jpg', '.jpeg'],
      'image/png': ['.png'],
    },
    maxSize: 5 * 1024 * 1024,
    maxFiles: 1,
    onDrop: (acceptedFiles) => {
      if (acceptedFiles.length > 0) {
        const file = acceptedFiles[0];
        setPetPhotoFile(file);
        setPetPhotoPreview(URL.createObjectURL(file));
      }
    },
  });

  const onSubmit = async (data: PetProfileFormValues) => {
    let photoUrl: string | undefined =
      data.petPhoto && data.petPhoto.startsWith('http') ? data.petPhoto : undefined;

    if (petPhotoFile) {
      setUploadingPhoto(true);
      try {
        photoUrl = await uploadPetPhoto(petPhotoFile);
        setValue('petPhoto', photoUrl);
        setPetPhotoPreview(photoUrl);
        if (petPhotoPreview?.startsWith('blob:')) {
          URL.revokeObjectURL(petPhotoPreview);
        }
        // Actualización optimista: mostrar la foto de inmediato en perfil sin esperar refetch
        queryClient.setQueryData<ClientMyProfileData | null>(CLIENT_MY_PROFILE_QUERY_KEY, (old) => {
          if (!old) return old;
          const pets = [...(old.pets || [])];
          if (pets[0]) pets[0] = { ...pets[0], photoUrl: photoUrl ?? pets[0].photoUrl };
          return { ...old, petPhoto: photoUrl ?? old.petPhoto, pets };
        });
        queryClient.invalidateQueries({ queryKey: CLIENT_MY_PROFILE_QUERY_KEY });
        queryClient.invalidateQueries({ queryKey: CLIENT_PETS_QUERY_KEY });
        await Promise.all([refetchProfile(), refetchPets()]);
      } catch (err) {
        toast.error(err instanceof Error ? err.message : 'Error al subir la foto. Intenta nuevamente.');
        setUploadingPhoto(false);
        return;
      } finally {
        setUploadingPhoto(false);
      }
    }

    if (!photoUrl) {
      toast.error('Debes subir una foto de tu mascota');
      return;
    }

    setSaving(true);
    try {
      const body = {
        name: data.petName,
        breed: data.petBreed || undefined,
        age: data.petAge ?? undefined,
        size: data.petSize ?? undefined,
        photoUrl,
        specialNeeds: data.specialNeeds || undefined,
        notes: data.notes || undefined,
      };

      if (firstPet) {
        await patchClientPet(firstPet.id, body);
      } else {
        await createClientPet(body);
      }

      await Promise.all([
        queryClient.invalidateQueries({ queryKey: CLIENT_MY_PROFILE_QUERY_KEY }),
        queryClient.invalidateQueries({ queryKey: CLIENT_PETS_QUERY_KEY }),
      ]);
      await refetchProfile();
      await refetchPets();
      await refreshUser();

      toast.success('Foto y datos de tu mascota guardados correctamente');
      const returnTo = (location.state as { returnTo?: string } | undefined)?.returnTo || '/profile';
      navigate(returnTo);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Error al guardar el perfil');
    } finally {
      setSaving(false);
    }
  };

  const hasPhoto = Boolean(petPhotoPreview);
  const isSubmitting = saving || uploadingPhoto;

  if (!isAuthenticated) {
    return (
      <div className="mx-auto max-w-2xl px-4 py-12 text-center">
        <p className="text-gray-600">Debes iniciar sesión para completar tu perfil.</p>
        <Link to="/" className="mt-4 inline-block text-green-600 hover:underline">
          Volver al inicio
        </Link>
      </div>
    );
  }

  if (loadingProfile) {
    return (
      <div className="mx-auto max-w-2xl px-4 py-12 text-center text-gray-500">
        Cargando perfil...
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl px-4 py-6 sm:px-6 lg:px-8">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Completa el perfil de tu mascota</h1>
        <p className="mt-2 text-sm text-gray-600">
          Para poder reservar servicios de cuidado, necesitamos conocer a tu mascota.
        </p>
        {(location.state as { message?: string } | undefined)?.message && (
          <div className="mt-4 rounded-lg border border-yellow-200 bg-yellow-50 p-4">
            <p className="text-sm text-yellow-800">{(location.state as { message: string }).message}</p>
          </div>
        )}
      </div>

      <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
        <div>
          <label className="block text-sm font-medium text-gray-700">
            Nombre de la mascota <span className="text-red-500">*</span>
          </label>
          <input
            type="text"
            {...register('petName')}
            className={`mt-1 w-full rounded-lg border px-3 py-2 text-sm focus:outline-none focus:ring-1 ${
              errors.petName
                ? 'border-red-500 focus:border-red-500 focus:ring-red-500'
                : 'border-gray-300 focus:border-green-500 focus:ring-green-500'
            }`}
            placeholder="Ej: Max, Luna, Rocky"
          />
          {errors.petName && <p className="mt-1 text-xs text-red-600">{errors.petName.message}</p>}
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">Raza (opcional)</label>
          <input
            type="text"
            {...register('petBreed')}
            className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
            placeholder="Ej: Labrador, Mestizo"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">Edad (años, opcional)</label>
          <input
            type="number"
            min={0}
            max={30}
            {...register('petAge', { valueAsNumber: true })}
            className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
            placeholder="Ej: 3"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">
            Tamaño <span className="text-red-500">*</span>
          </label>
          <select
            {...register('petSize')}
            className={`mt-1 w-full rounded-lg border px-3 py-2 text-sm focus:outline-none focus:ring-1 ${
              errors.petSize
                ? 'border-red-500 focus:border-red-500 focus:ring-red-500'
                : 'border-gray-300 focus:border-green-500 focus:ring-green-500'
            }`}
          >
            <option value="">Selecciona el tamaño</option>
            {Object.entries(PET_SIZE_LABELS).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
          {errors.petSize && <p className="mt-1 text-xs text-red-600">{errors.petSize.message}</p>}
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">
            Foto de la mascota <span className="text-red-500">*</span>
          </label>
          <p className="mt-1 mb-2 text-xs text-gray-500">JPG o PNG, máx. 5 MB</p>

          {petPhotoPreview ? (
            <div className="relative">
              <img
                src={getImageUrl(petPhotoPreview)}
                alt="Foto de la mascota"
                loading="lazy"
                className="h-48 w-full rounded-lg border border-gray-300 object-cover"
              />
              <button
                type="button"
                onClick={() => {
                  setPetPhotoFile(null);
                  setPetPhotoPreview(null);
                  setValue('petPhoto', '');
                  if (petPhotoPreview.startsWith('blob:')) {
                    URL.revokeObjectURL(petPhotoPreview);
                  }
                }}
                className="absolute right-2 top-2 rounded-full bg-red-500 p-2 text-white hover:bg-red-600"
              >
                <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          ) : (
            <div
              {...getRootProps()}
              className={`cursor-pointer rounded-xl border-2 border-dashed p-8 text-center transition-colors ${
                isDragActive
                  ? 'border-green-500 bg-green-50'
                  : 'border-gray-300 bg-gray-50 hover:border-green-400 hover:bg-green-50/50'
              }`}
            >
              <input {...getInputProps()} />
              <svg
                className="mx-auto h-12 w-12 text-gray-400"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                />
              </svg>
              <p className="mt-2 text-sm text-gray-600">
                {isDragActive ? 'Suelta la foto aquí' : 'Arrastra una foto o haz clic para seleccionar'}
              </p>
            </div>
          )}
          {uploadingPhoto && <p className="mt-1 text-xs text-gray-500">Subiendo foto...</p>}
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">
            Necesidades especiales (opcional)
          </label>
          <textarea
            {...register('specialNeeds')}
            rows={4}
            className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
            placeholder="Ej: Medicación diaria, dieta especial..."
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">Notas adicionales (opcional)</label>
          <textarea
            {...register('notes')}
            rows={4}
            className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
            placeholder="Cualquier información adicional..."
          />
        </div>

        <div className="flex flex-col gap-3 sm:flex-row sm:justify-end">
          <Link
            to="/profile"
            className="rounded-lg border border-gray-300 bg-white px-6 py-2.5 text-center text-sm font-medium text-gray-700 hover:bg-gray-50"
          >
            Cancelar
          </Link>
          <button
            type="submit"
            disabled={isSubmitting || !hasPhoto}
            className="rounded-lg bg-green-600 px-6 py-2.5 text-sm font-medium text-white hover:bg-green-700 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {isSubmitting ? 'Guardando...' : 'Guardar y continuar'}
          </button>
        </div>
      </form>
    </div>
  );
}
