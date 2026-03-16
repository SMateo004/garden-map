import { useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useClientPets } from '@/hooks/useClientPets';
import type { ClientPetListItem } from '@/api/clientPets';
import { getImageUrl } from '@/utils/images';

const SIZE_LABELS: Record<string, string> = {
  SMALL: 'Pequeño',
  MEDIUM: 'Mediano',
  LARGE: 'Grande',
  GIANT: 'Gigante',
};

interface MascotaSelectorProps {
  value: string | null;
  onChange: (petId: string) => void;
  returnTo?: string;
  /** Si true, no hace fetch (ej. usuario no es CLIENT). */
  disabled?: boolean;
}

export function MascotaSelector({
  value,
  onChange,
  returnTo = '/',
  disabled = false,
}: MascotaSelectorProps) {
  const { data: pets = [], isLoading, isError } = useClientPets({
    enabled: !disabled,
  });

  // Auto-selección si solo hay 1 mascota
  useEffect(() => {
    if (pets.length === 1 && !value) {
      onChange(pets[0].id);
    }
  }, [pets, value, onChange]);

  if (disabled) return null;

  if (isLoading) {
    return (
      <div className="rounded-xl border border-gray-200 bg-white p-6">
        <h2 className="mb-3 text-sm font-semibold text-gray-900">Datos de la mascota</h2>
        <div className="flex items-center justify-center py-8 text-gray-500">
          Cargando tus mascotas...
        </div>
      </div>
    );
  }

  if (isError) {
    return (
      <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-red-700">
        <p className="text-sm">No se pudieron cargar tus mascotas. Intenta de nuevo.</p>
      </div>
    );
  }

  if (pets.length === 0) {
    return (
      <div className="rounded-xl border border-amber-200 bg-amber-50 p-6">
        <h2 className="mb-2 text-sm font-semibold text-gray-900">Datos de la mascota</h2>
        <p className="mb-4 text-sm text-gray-700">
          No tienes mascotas registradas. Agrega una ahora.
        </p>
        <Link
          to="/profile/complete-pet"
          state={{ returnTo }}
          className="inline-flex items-center rounded-lg bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700"
        >
          Agregar mascota
        </Link>
      </div>
    );
  }


  return (
    <div className="rounded-xl border border-gray-200 bg-white p-4">
      <h2 className="mb-3 text-sm font-semibold text-gray-900">
        {pets.length === 1 ? 'Mascota para la reserva' : 'Selecciona la mascota'}
      </h2>

      <div className="grid gap-3 sm:grid-cols-2">
        {pets.map((pet) => (
          <PetCard
            key={pet.id}
            pet={pet}
            selected={value === pet.id}
            onSelect={() => onChange(pet.id)}
          />
        ))}
      </div>

      <div className="mt-4 flex flex-wrap items-center gap-3">
        <Link
          to="/profile/complete-pet"
          state={{ returnTo }}
          className="text-sm font-medium text-green-600 hover:text-green-700 hover:underline"
        >
          + Agregar nueva mascota
        </Link>
      </div>

      {/* El resumen detallado se eliminó de aquí para simplificar la interfaz de reserva */}
    </div>
  );
}

function PetCard({
  pet,
  selected,
  onSelect,
}: {
  pet: ClientPetListItem;
  selected: boolean;
  onSelect: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onSelect}
      className={`flex items-center gap-3 rounded-xl border-2 p-3 text-left transition ${selected
        ? 'border-green-600 bg-green-50'
        : 'border-gray-200 bg-white hover:border-gray-300 hover:bg-gray-50'
        }`}
    >
      <div className="h-14 w-14 shrink-0 overflow-hidden rounded-lg bg-gray-200">
        <img
          src={getImageUrl(pet.photoUrl)}
          alt={`Foto de ${pet.name}`}
          loading="lazy"
          className="h-full w-full object-cover"
        />
      </div>
      <div className="min-w-0 flex-1">
        <p className="font-medium text-gray-900">{pet.name}</p>
        {pet.breed && (
          <p className="text-xs text-gray-500">{pet.breed}</p>
        )}
        <div className="mt-1 flex flex-wrap gap-2 text-xs text-gray-600">
          {pet.age != null && <span>{pet.age} años</span>}
          {pet.size && (
            <span>{SIZE_LABELS[pet.size] ?? pet.size}</span>
          )}
        </div>
      </div>
      <div
        className={`h-5 w-5 shrink-0 rounded-full border-2 ${selected ? 'border-green-600 bg-green-600' : 'border-gray-300'
          }`}
      >
        {selected && (
          <svg className="h-full w-full text-white" fill="currentColor" viewBox="0 0 20 20">
            <path
              fillRule="evenodd"
              d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
              clipRule="evenodd"
            />
          </svg>
        )}
      </div>
    </button>
  );
}

