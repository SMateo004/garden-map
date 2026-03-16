import { Link, useNavigate } from 'react-router-dom';
import { useClientMyProfile } from '@/hooks/useClientMyProfile';
import { useAuth } from '@/contexts/AuthContext';
import type { ClientMyProfilePet } from '@/api/clientProfile';
import { getImageUrl } from '@/utils/images';

const SIZE_LABELS: Record<string, string> = {
  SMALL: 'Pequeño',
  MEDIUM: 'Mediano',
  LARGE: 'Grande',
  GIANT: 'Gigante',
};

function PetCard({ pet, fallbackPhotoUrl }: { pet: ClientMyProfilePet; fallbackPhotoUrl?: string | null }) {
  const photoUrl = pet.photoUrl ?? fallbackPhotoUrl;
  return (
    <div className="flex flex-col overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm transition hover:shadow-md sm:flex-row">
      <div className="h-32 w-full shrink-0 bg-gray-100 sm:h-24 sm:w-24">
        <img
          src={getImageUrl(photoUrl)}
          alt={`Foto de ${pet.name}`}
          loading="lazy"
          referrerPolicy="no-referrer"
          className="h-full w-full object-cover"
        />
      </div>
      <div className="flex flex-1 flex-col p-4">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <h3 className="font-semibold text-gray-900">{pet.name}</h3>
            <p className="text-sm text-gray-500">
              {[pet.breed, pet.age != null ? `${pet.age} años` : null, pet.size ? SIZE_LABELS[pet.size] : null]
                .filter(Boolean)
                .join(' · ') || '—'}
            </p>
          </div>
          <Link
            to={`/profile/edit-pet/${pet.id}`}
            className="rounded-lg border border-gray-300 bg-white px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-50"
          >
            Editar
          </Link>
        </div>
        {pet.specialNeeds && (
          <p className="mt-2 line-clamp-2 text-sm text-gray-600">{pet.specialNeeds}</p>
        )}
      </div>
    </div>
  );
}

export function ClientProfilePage() {
  const navigate = useNavigate();
  const { logout } = useAuth();
  const { data: profile, isLoading, isError, error } = useClientMyProfile();

  const showCompleteBanner =
    profile && (profile.pets.length === 0 || !profile.isComplete);

  const handleLogout = () => {
    logout();
    navigate('/');
  };

  if (isLoading) {
    return (
      <div className="mx-auto max-w-2xl px-4 py-12">
        <div className="rounded-xl border border-gray-200 bg-white p-8">
          <div className="animate-pulse space-y-4">
            <div className="h-6 w-48 rounded bg-gray-200" />
            <div className="h-4 w-full rounded bg-gray-100" />
            <div className="h-4 w-3/4 rounded bg-gray-100" />
            <div className="mt-6 h-24 rounded bg-gray-100" />
            <div className="h-24 rounded bg-gray-100" />
          </div>
        </div>
      </div>
    );
  }

  if (isError) {
    return (
      <div className="mx-auto max-w-2xl px-4 py-12">
        <div className="rounded-xl border border-red-200 bg-red-50 p-6 text-red-800">
          <p className="font-medium">No se pudo cargar tu perfil</p>
          <p className="mt-1 text-sm">{error?.message ?? 'Intenta de nuevo más tarde.'}</p>
        </div>
      </div>
    );
  }

  if (!profile) {
    return (
      <div className="mx-auto max-w-2xl px-4 py-12">
        <div className="rounded-xl border border-gray-200 bg-white p-6 text-center text-gray-600">
          No se encontró el perfil.
        </div>
      </div>
    );
  }

  const fullName = [profile.user.firstName, profile.user.lastName].filter(Boolean).join(' ') || '—';

  return (
    <div className="mx-auto max-w-2xl space-y-6 px-4 py-8 sm:px-6">
      <h1 className="text-2xl font-bold text-gray-900">Mi Perfil</h1>

      {showCompleteBanner && (
        <div className="rounded-xl border-2 border-amber-200 bg-amber-50 p-4 sm:p-5">
          <p className="font-medium text-amber-900">
            Completa el perfil de tu(s) mascota(s) para poder reservar cuidadores
          </p>
          <Link
            to="/profile/complete-pet"
            className="mt-3 inline-flex rounded-lg bg-amber-600 px-4 py-2 text-sm font-medium text-white hover:bg-amber-700"
          >
            Completar ahora
          </Link>
        </div>
      )}

      <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm sm:p-6">
        <h2 className="mb-4 text-sm font-semibold uppercase tracking-wide text-gray-500">
          Datos del dueño
        </h2>
        <dl className="grid gap-3 sm:grid-cols-1">
          <div>
            <dt className="text-xs text-gray-500">Nombre completo</dt>
            <dd className="font-medium text-gray-900">{fullName}</dd>
          </div>
          <div>
            <dt className="text-xs text-gray-500">Email</dt>
            <dd className="text-gray-900">{profile.user.email}</dd>
          </div>
          <div>
            <dt className="text-xs text-gray-500">Teléfono</dt>
            <dd className="text-gray-900">{profile.user.phone ?? profile.phone ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-xs text-gray-500">Dirección</dt>
            <dd className="text-gray-900">{profile.address ?? '—'}</dd>
          </div>
        </dl>
      </section>

      <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm sm:p-6">
        <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500">
            Mis mascotas
          </h2>
          <Link
            to="/profile/complete-pet"
            className="rounded-lg bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700"
          >
            Agregar nueva mascota
          </Link>
        </div>
        {profile.pets.length === 0 ? (
          <p className="py-6 text-center text-gray-500">
            Aún no tienes mascotas registradas.
          </p>
        ) : (
          <ul className="space-y-3">
            {profile.pets.map((pet, index) => (
              <li key={pet.id}>
                <PetCard
                  pet={pet}
                  fallbackPhotoUrl={index === 0 ? profile.petPhoto : undefined}
                />
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm sm:p-6">
        <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-gray-500">
          Reservas
        </h2>
        <p className="text-sm text-gray-600 mb-3">
          Gestiona tus próximas reservas confirmadas y en curso.
        </p>
        <Link
          to="/profile/reservations"
          className="inline-flex rounded-lg bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700"
        >
          Ver próximas reservas
        </Link>
      </section>

      <div className="flex flex-wrap gap-3 border-t border-gray-200 pt-6">
        <button
          type="button"
          onClick={handleLogout}
          className="rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
        >
          Cerrar sesión
        </button>
      </div>
    </div>
  );
}
