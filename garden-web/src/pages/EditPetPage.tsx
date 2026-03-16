import { useState, useEffect } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useQueryClient } from '@tanstack/react-query';
import { useClientPets, CLIENT_PETS_QUERY_KEY } from '@/hooks/useClientPets';
import { patchClientPet, type PatchClientPetBody } from '@/api/clientPets';
import { CLIENT_MY_PROFILE_QUERY_KEY } from '@/hooks/useClientMyProfile';
import { getImageUrl } from '@/utils/images';
import toast from 'react-hot-toast';

const formSchema = z.object({
  name: z.string().min(1, 'Nombre requerido').max(200),
  breed: z.string().max(100).optional(),
  age: z.number().int().min(0).max(30).optional().nullable(),
  size: z.enum(['SMALL', 'MEDIUM', 'LARGE', 'GIANT']).optional().nullable(),
  photoUrl: z.union([z.string().url(), z.literal('')]).optional(),
  specialNeeds: z.string().max(2000).optional(),
  notes: z.string().max(2000).optional(),
});

type FormValues = z.infer<typeof formSchema>;

const SIZE_LABELS: Record<string, string> = {
  SMALL: 'Pequeño',
  MEDIUM: 'Mediano',
  LARGE: 'Grande',
  GIANT: 'Gigante',
};

export function EditPetPage() {
  const { petId } = useParams<{ petId: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { data: pets = [], isLoading } = useClientPets();
  const [saving, setSaving] = useState(false);

  const pet = petId ? pets.find((p) => p.id === petId) : null;

  const {
    register,
    handleSubmit,
    setValue,
    formState: { errors },
  } = useForm<FormValues>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      name: '',
      breed: '',
      age: null,
      size: null,
      photoUrl: '',
      specialNeeds: '',
      notes: '',
    },
  });

  useEffect(() => {
    if (pet) {
      setValue('name', pet.name);
      setValue('breed', pet.breed ?? '');
      setValue('age', pet.age ?? null);
      setValue('size', pet.size ?? null);
      setValue('photoUrl', pet.photoUrl ?? '');
      setValue('specialNeeds', pet.specialNeeds ?? '');
      setValue('notes', pet.notes ?? '');
    }
  }, [pet, setValue]);

  const onSubmit = async (data: FormValues) => {
    if (!petId) return;
    setSaving(true);
    try {
      const body: PatchClientPetBody = {
        name: data.name,
        breed: data.breed || undefined,
        age: data.age ?? undefined,
        size: data.size ?? undefined,
        photoUrl: data.photoUrl || undefined,
        specialNeeds: data.specialNeeds || undefined,
        notes: data.notes || undefined,
      };
      await patchClientPet(petId, body);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: CLIENT_PETS_QUERY_KEY }),
        queryClient.invalidateQueries({ queryKey: CLIENT_MY_PROFILE_QUERY_KEY }),
      ]);
      toast.success('Mascota actualizada');
      navigate('/profile');
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al guardar');
    } finally {
      setSaving(false);
    }
  };

  if (isLoading) {
    return (
      <div className="mx-auto max-w-lg px-4 py-12">
        <div className="rounded-xl border border-gray-200 bg-white p-6">
          <div className="h-6 w-32 animate-pulse rounded bg-gray-200" />
          <div className="mt-4 h-10 w-full animate-pulse rounded bg-gray-100" />
        </div>
      </div>
    );
  }

  if (!pet) {
    return (
      <div className="mx-auto max-w-lg px-4 py-12">
        <div className="rounded-xl border border-gray-200 bg-white p-6 text-center">
          <p className="text-gray-600">Mascota no encontrada.</p>
          <Link to="/profile" className="mt-4 inline-block text-green-600 hover:underline">
            Volver al perfil
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-lg space-y-6 px-4 py-8 sm:px-6">
      <Link to="/profile" className="text-sm text-green-600 hover:underline">
        ← Volver al perfil
      </Link>
      <h1 className="text-2xl font-bold text-gray-900">Editar mascota</h1>

      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 rounded-xl border border-gray-200 bg-white p-4 sm:p-6">
        <div>
          <label className="block text-sm font-medium text-gray-700">Nombre</label>
          <input
            type="text"
            {...register('name')}
            className="mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 shadow-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
          />
          {errors.name && <p className="mt-1 text-sm text-red-600">{errors.name.message}</p>}
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">Raza</label>
          <input
            type="text"
            {...register('breed')}
            className="mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 shadow-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">Edad (años)</label>
          <input
            type="number"
            min={0}
            max={30}
            {...register('age', { valueAsNumber: true })}
            className="mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 shadow-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">Tamaño</label>
          <select
            {...register('size')}
            className="mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 shadow-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
          >
            <option value="">—</option>
            {Object.entries(SIZE_LABELS).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">URL de la foto</label>
          <div className="mt-1 flex gap-3 items-start">
            <div className="h-20 w-20 shrink-0 overflow-hidden rounded-lg border border-gray-200 bg-gray-100">
              <img
                src={getImageUrl(pet?.photoUrl)}
                alt={pet?.name ? `Foto de ${pet.name}` : 'Foto de la mascota'}
                loading="lazy"
                className="h-full w-full object-cover"
              />
            </div>
            <input
              type="url"
              {...register('photoUrl')}
              placeholder="https://... o sube en Completar perfil mascota"
              className="block w-full rounded-lg border border-gray-300 px-3 py-2 shadow-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
            />
          </div>
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">Necesidades especiales</label>
          <textarea
            {...register('specialNeeds')}
            rows={2}
            className="mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 shadow-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">Notas</label>
          <textarea
            {...register('notes')}
            rows={2}
            className="mt-1 block w-full rounded-lg border border-gray-300 px-3 py-2 shadow-sm focus:border-green-500 focus:outline-none focus:ring-1 focus:ring-green-500"
          />
        </div>
        <div className="flex gap-3 pt-2">
          <button
            type="submit"
            disabled={saving}
            className="rounded-lg bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50"
          >
            {saving ? 'Guardando…' : 'Guardar'}
          </button>
          <Link
            to="/profile"
            className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
          >
            Cancelar
          </Link>
        </div>
      </form>
    </div>
  );
}
