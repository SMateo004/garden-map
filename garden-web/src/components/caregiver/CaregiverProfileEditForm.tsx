import { useState, useRef } from 'react';
import { uploadProfilePhoto } from '@/api/caregiverProfile';
import { getImageUrl } from '@/utils/images';
import toast from 'react-hot-toast';
import { CaregiverAvailabilityPage } from '@/pages/caregiver/CaregiverAvailabilityPage';
import { ZONES, ZONE_LABELS } from '@/types/caregiver';

const EXP_YEARS_LABELS: Record<string, string> = {
  NEVER: 'Sin experiencia previa',
  LESS1: 'Menos de 1 año',
  ONE_TO_FIVE: '1 a 5 años',
  MORE5: 'Más de 5 años',
};

const ANIMAL_TYPE_LABELS: Record<string, string> = {
  DOGS: 'Perros',
  CATS: 'Gatos',
  PUPPIES: 'Cachorros',
  SENIORS: 'Seniors',
  LARGE: 'Perros grandes',
  SMALL: 'Perros pequeños',
  SPECIAL: 'Necesidades especiales',
};

const PET_SIZE_LABELS: Record<string, string> = {
  SMALL: 'Pequeño',
  MEDIUM: 'Mediano',
  LARGE: 'Grande',
  GIANT: 'Gigante',
};

const HOME_TYPE_LABELS: Record<string, string> = {
  HOUSE: 'Casa',
  APARTMENT: 'Departamento',
};

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="mb-6 last:mb-0">
      <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">{label}</label>
      {children}
    </div>
  );
}

export function CaregiverProfileEditForm({
  profile,
  user,
  onPatch,
  onCancel,
}: {
  profile: any;
  user: { firstName: string; lastName: string; email: string };
  onPatch: (upd: any) => Promise<void>;
  onCancel: () => void;
}) {
  const [localProfile, setLocalProfile] = useState(profile);
  const [uploadingPhoto, setUploadingPhoto] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handlePatch = async (upd: any) => {
    setLocalProfile((p: any) => ({ ...p, ...upd }));
    await onPatch(upd);
  };

  const handlePhotoChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file?.type.startsWith('image/')) return;
    setUploadingPhoto(true);
    try {
      const url = await uploadProfilePhoto(file);
      await handlePatch({ profilePhoto: url });
      toast.success('Foto actualizada');
    } finally {
      setUploadingPhoto(false);
    }
  };

  return (
    <div className="space-y-10">
      <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Editar perfil profesional</h1>

      {/* Photo */}
      <div className="flex items-center gap-6">
        <img
          src={getImageUrl(localProfile?.profilePhoto ?? null)}
          alt="Perfil"
          className="w-24 h-24 rounded-2xl object-cover border-2 border-gray-200 dark:border-gray-600"
        />
        <div>
          <input ref={fileInputRef} type="file" accept="image/*" className="hidden" onChange={handlePhotoChange} />
          <button
            type="button"
            onClick={() => fileInputRef.current?.click()}
            disabled={uploadingPhoto}
            className="px-4 py-2 rounded-xl bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 text-sm font-medium hover:bg-gray-200 dark:hover:bg-gray-600 disabled:opacity-50"
          >
            {uploadingPhoto ? 'Subiendo…' : 'Cambiar foto'}
          </button>
        </div>
      </div>

      {/* Zone & Services */}
      <div className="grid md:grid-cols-2 gap-6">
        <Field label="Zona">
          <select
            value={localProfile?.zone ?? ''}
            onChange={(e) => handlePatch({ zone: e.target.value })}
            className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-2.5"
          >
            <option value="">Selecciona zona...</option>
            {ZONES.map((z) => (
              <option key={z} value={z}>
                {ZONE_LABELS[z] ?? z}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Servicios">
          <div className="flex gap-2">
            {['HOSPEDAJE', 'PASEO'].map((s) => {
              const active = localProfile?.servicesOffered?.includes(s);
              return (
                <button
                  key={s}
                  type="button"
                  onClick={() => {
                    const next = active
                      ? localProfile.servicesOffered.filter((x: string) => x !== s)
                      : [...(localProfile.servicesOffered || []), s];
                    handlePatch({ servicesOffered: next });
                  }}
                  className={`flex-1 py-2.5 rounded-xl border text-sm font-medium ${
                    active ? 'border-green-600 bg-green-50 dark:bg-green-900/20 text-green-700' : 'border-gray-200 dark:border-gray-700'
                  }`}
                >
                  {s === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseos'}
                </button>
              );
            })}
          </div>
        </Field>
      </div>

      {/* Prices */}
      {(localProfile?.servicesOffered?.includes('HOSPEDAJE') || localProfile?.servicesOffered?.includes('PASEO')) && (
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          {localProfile?.servicesOffered?.includes('HOSPEDAJE') && (
            <Field label="Hospedaje (Bs/día)">
              <input
                type="number"
                value={localProfile?.pricePerDay ?? ''}
                onChange={(e) => handlePatch({ pricePerDay: parseInt(e.target.value) || 0 })}
                className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-2.5"
              />
            </Field>
          )}
          {localProfile?.servicesOffered?.includes('PASEO') && (
            <>
              <Field label="Paseo 30' (Bs)">
                <input
                  type="number"
                  value={localProfile?.pricePerWalk30 ?? ''}
                  onChange={(e) => handlePatch({ pricePerWalk30: parseInt(e.target.value) || 0 })}
                  className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-2.5"
                />
              </Field>
              <Field label="Paseo 60' (Bs)">
                <input
                  type="number"
                  value={localProfile?.pricePerWalk60 ?? ''}
                  onChange={(e) => handlePatch({ pricePerWalk60: parseInt(e.target.value) || 0 })}
                  className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-2.5"
                />
              </Field>
            </>
          )}
        </div>
      )}

      {/* Bio */}
      <Field label="Bio / descripción (mín. 50 caracteres)">
        <textarea
          value={localProfile?.bio ?? ''}
          onChange={(e) => setLocalProfile((p: any) => ({ ...p, bio: e.target.value }))}
          onBlur={(e) => handlePatch({ bio: e.target.value })}
          rows={4}
          className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3"
          placeholder="Cuéntales a los dueños por qué eres la mejor opción..."
        />
        <p className="text-xs text-gray-500 mt-1">{localProfile?.bio?.length ?? 0}/500</p>
      </Field>

      {/* Experience */}
      <Field label="Años de experiencia">
        <div className="flex flex-wrap gap-2">
          {Object.entries(EXP_YEARS_LABELS).map(([key, label]) => (
            <button
              key={key}
              type="button"
              onClick={() => handlePatch({ experienceYears: key })}
              className={`px-4 py-2 rounded-xl border text-sm font-medium ${
                localProfile?.experienceYears === key
                  ? 'border-green-600 bg-green-50 dark:bg-green-900/20 text-green-700'
                  : 'border-gray-200 dark:border-gray-700'
              }`}
            >
              {label}
            </button>
          ))}
        </div>
      </Field>

      {/* Animal types */}
      <Field label="Animales que has cuidado">
        <div className="flex flex-wrap gap-2">
          {Object.entries(ANIMAL_TYPE_LABELS).map(([key, label]) => {
            const active = localProfile?.animalTypes?.includes(key);
            return (
              <button
                key={key}
                type="button"
                onClick={() => {
                  const next = active
                    ? localProfile.animalTypes.filter((x: string) => x !== key)
                    : [...(localProfile.animalTypes || []), key];
                  handlePatch({ animalTypes: next });
                }}
                className={`px-3 py-1.5 rounded-lg border text-xs font-medium ${
                  active ? 'border-green-600 bg-green-50 text-green-700' : 'border-gray-200'
                }`}
              >
                {label}
              </button>
            );
          })}
        </div>
      </Field>

      {/* Home type (hospedaje) */}
      {localProfile?.servicesOffered?.includes('HOSPEDAJE') && (
        <div className="space-y-4">
          <Field label="Tipo de vivienda">
            <div className="flex gap-2">
              {Object.entries(HOME_TYPE_LABELS).map(([key, label]) => (
                <button
                  key={key}
                  type="button"
                  onClick={() => handlePatch({ homeType: key })}
                  className={`flex-1 py-2.5 rounded-xl border text-sm font-medium ${
                    localProfile?.homeType === key ? 'border-green-600 bg-green-50 text-green-700' : 'border-gray-200'
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
          </Field>
          <Field label="Tamaños aceptados">
            <div className="flex flex-wrap gap-2">
              {Object.entries(PET_SIZE_LABELS).map(([key, label]) => {
                const active = localProfile?.sizesAccepted?.includes(key);
                return (
                  <button
                    key={key}
                    type="button"
                    onClick={() => {
                      const next = active
                        ? localProfile.sizesAccepted.filter((x: string) => x !== key)
                        : [...(localProfile.sizesAccepted || []), key];
                      handlePatch({ sizesAccepted: next });
                    }}
                    className={`px-3 py-1.5 rounded-lg border text-xs font-medium ${
                      active ? 'border-green-600 bg-green-50 text-green-700' : 'border-gray-200'
                    }`}
                  >
                    {label}
                  </button>
                );
              })}
            </div>
          </Field>
        </div>
      )}

      {/* Availability */}
      <div className="pt-8 border-t border-gray-200 dark:border-gray-700">
        <h2 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">Disponibilidad</h2>
        <CaregiverAvailabilityPage standalone />
      </div>

      {/* Actions */}
      <div className="flex flex-wrap gap-4 pt-6">
        <button
          type="button"
          onClick={onCancel}
          className="px-6 py-3 rounded-xl border border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-300 font-medium hover:bg-gray-50 dark:hover:bg-gray-800"
        >
          Cancelar
        </button>
      </div>
    </div>
  );
}
