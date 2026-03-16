import { useState, useEffect } from 'react';
import { patchProfile } from '@/api/caregiverProfile';
import { uploadRegistrationPhotos } from '@/api/auth';
import { getImageUrl } from '@/utils/images';
import toast from 'react-hot-toast';
import { ZONES, ZONE_LABELS } from '@/types/caregiver';

const EXP_YEARS_LABELS: Record<string, string> = {
  NEVER: 'Sin experiencia',
  LESS1: 'Menos de 1 año',
  ONE_TO_FIVE: '1 a 5 años',
  MORE5: 'Más de 5 años',
};

const ANIMAL_TYPE_LABELS: Record<string, string> = {
  DOGS: 'Perros',
  CATS: 'Gatos',
  PUPPIES: 'Cachorros',
  SENIORS: 'Seniors',
  LARGE: 'Grandes',
  SMALL: 'Pequeños',
  SPECIAL: 'Especiales',
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

const MEDICATION_LABELS: Record<string, string> = {
  ORAL: 'Oral',
  INJECT: 'Inyectable',
  TOPIC: 'Tópica',
};

const SLEEP_LABELS: Record<string, string> = {
  INSIDE: 'Adentro (cama/piso)',
  OUTSIDE: 'Afuera (patio/terraza)',
};

const CLIENT_SLEEP_LABELS: Record<string, string> = {
  BED: 'En mi cama',
  CRATE: 'En su jaula/canil',
  SOFA: 'En el sofá',
  FLOOR: 'En el piso / alfombra',
};

function Field({ label, children, hint }: { label: string; children: React.ReactNode; hint?: string }) {
  return (
    <div className="mb-4">
      <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">{label}</label>
      {hint && <p className="text-xs text-gray-500 mb-2">{hint}</p>}
      {children}
    </div>
  );
}

function YesNo({ value, onChange, disabled }: { value: boolean | null | undefined; onChange: (v: boolean) => void; disabled?: boolean }) {
  return (
    <div className="flex gap-2">
      {[true, false].map((v) => (
        <button
          key={String(v)}
          type="button"
          disabled={disabled}
          onClick={() => onChange(v)}
          className={`flex-1 py-2 rounded-xl border text-sm font-medium transition-all ${value === v
            ? 'border-green-600 bg-green-50 dark:bg-green-900/20 text-green-700'
            : 'border-gray-200 dark:border-gray-700 hover:bg-gray-50'
            }`}
        >
          {v ? 'Sí' : 'No'}
        </button>
      ))}
    </div>
  );
}

export function CaregiverProfileSection({
  profile,
  onUpdate,
}: {
  profile: any;
  onUpdate: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [local, setLocal] = useState(profile);
  const [newFiles, setNewFiles] = useState<File[]>([]);
  const [photosToRemove, setPhotosToRemove] = useState<string[]>([]);
  const [previews, setPreviews] = useState<string[]>([]);

  useEffect(() => {
    if (!editing && profile) {
      setLocal(profile);
      setNewFiles([]);
      setPhotosToRemove([]);
      setPreviews([]);
    }
  }, [profile, editing]);

  useEffect(() => {
    const urls = newFiles.map((f: File) => URL.createObjectURL(f));
    setPreviews(urls);
    return () => urls.forEach((u: string) => URL.revokeObjectURL(u));
  }, [newFiles]);

  const handleSave = async () => {
    // Basic frontend validation for mandatory fields
    const missingFields: string[] = [];
    if (!local?.bio || local.bio.trim().length < 50) missingFields.push('Biografía (mín. 50 carac.)');
    if (!local?.zone) missingFields.push('Zona de trabajo');
    if (!local?.servicesOffered || local.servicesOffered.length === 0) missingFields.push('Servicios ofrecidos');

    const services = local?.servicesOffered || [];
    const onlyPaseo = services.length === 1 && services.includes('PASEO');
    const minPhotos = onlyPaseo ? 2 : 4;
    const currentPhotos = (local?.photos?.length || 0) - photosToRemove.length + newFiles.length;
    if (currentPhotos < minPhotos) missingFields.push(`Fotos (mín. ${minPhotos})`);

    if (!local?.experienceYears) missingFields.push('Años de experiencia');
    if (!local?.experienceDescription || local.experienceDescription.trim().length < 20) missingFields.push('Descripción de experiencia (mín. 20 carac.)');
    if (!local?.whyCaregiver || local.whyCaregiver.trim().length < 5) missingFields.push('¿Por qué quieres ser cuidador? (mín. 5 carac.)');
    if (!local?.whatDiffers || local.whatDiffers.trim().length < 5) missingFields.push('¿Qué te diferencia? (mín. 5 carac.)');
    if (!local?.handleAnxious) missingFields.push('Manejo de ansiedad');
    if (!local?.emergencyResponse) missingFields.push('Respuesta ante emergencias');
    if (local?.acceptAggressive === null || local?.acceptAggressive === undefined) missingFields.push('Aceptación de perros agresivos');
    if (local?.acceptPuppies === null || local?.acceptPuppies === undefined) missingFields.push('Aceptación de cachorros');
    if (local?.acceptSeniors === null || local?.acceptSeniors === undefined) missingFields.push('Aceptación de mascotas senior');
    if (!local?.sizesAccepted || local.sizesAccepted.length === 0) missingFields.push('Tamaños aceptados');
    if (!local?.animalTypes || local.animalTypes.length === 0) missingFields.push('Tipos de animales que cuidas');
    if (!local?.bioDetail || local.bioDetail.trim().length < 5) missingFields.push('Bio corta / slogan (mín. 5 carac.)');

    if (services.includes('HOSPEDAJE')) {
      if (!local?.homeType) missingFields.push('Tipo de vivienda');
      if (!local?.spaceDescription || local.spaceDescription.trim().length < 5) missingFields.push('Descripción del espacio (mín. 5 carac.)');
    }

    if (missingFields.length > 0) {
      toast.error(`Faltan campos obligatorios:\n- ${missingFields.join('\n- ')}`, { duration: 5000 });
      return;
    }

    setSaving(true);
    try {
      let finalPhotos = [...(local.photos || [])].filter(p => !photosToRemove.includes(p));

      // 1. Upload new photos if any
      if (newFiles.length > 0) {
        const uploadedUrls = await uploadRegistrationPhotos(newFiles);
        finalPhotos = [...finalPhotos, ...uploadedUrls];
      }

      // Build payload
      const payload: Record<string, unknown> = {
        photos: finalPhotos,
      };

      if (local?.zone) payload.zone = local.zone;
      if (local?.servicesOffered?.length > 0) payload.servicesOffered = local.servicesOffered;
      if (local?.pricePerDay != null) payload.pricePerDay = Number(local.pricePerDay);
      if (local?.pricePerWalk30 != null) payload.pricePerWalk30 = Number(local.pricePerWalk30);
      if (local?.pricePerWalk60 != null) payload.pricePerWalk60 = Number(local.pricePerWalk60);
      if (local?.bio) payload.bio = local.bio;
      if (local?.bioDetail) payload.bioDetail = local.bioDetail;
      if (local?.experienceYears) payload.experienceYears = local.experienceYears;
      if (local?.animalTypes?.length > 0) payload.animalTypes = local.animalTypes;
      if (local?.homeType) payload.homeType = local.homeType;
      if (local?.sizesAccepted?.length > 0) payload.sizesAccepted = local.sizesAccepted;
      if (local?.spaceType) payload.spaceType = local.spaceType;
      if (local?.spaceDescription) payload.spaceDescription = local.spaceDescription;
      if (local?.address) payload.address = local.address;

      // New fields
      const newFields = [
        'ownPets', 'caredOthers', 'experienceDescription', 'whyCaregiver',
        'whatDiffers', 'handleAnxious', 'emergencyResponse', 'acceptAggressive',
        'acceptMedication', 'acceptPuppies', 'acceptSeniors', 'noAcceptBreeds',
        'breedsWhy', 'ownHome', 'hasYard', 'yardFenced', 'hasChildren',
        'hasOtherPets', 'petsSleep', 'clientPetsSleep', 'hoursAlone',
        'workFromHome', 'maxPets', 'oftenOut', 'typicalDay'
      ];
      newFields.forEach(f => {
        const val = local[f];
        if (val !== undefined && val !== null && val !== '') {
          payload[f] = val;
        }
      });

      await patchProfile(payload);
      toast.success('Cambios guardados');
      setEditing(false);
      onUpdate();
    } catch (err: any) {
      const d = err?.response?.data;
      const msg =
        d?.error?.message ??
        d?.message ??
        (d?.errors?.[0]?.message ? `Campo '${d.errors[0].field}': ${d.errors[0].message}` : null) ??
        err?.message ??
        'Error al guardar';
      toast.error(msg);
    } finally {
      setSaving(false);
    }
  };

  if (!profile) return null;

  const profileStatus = profile?.profileStatus ?? '';
  const isLocked = profileStatus === 'SUBMITTED' || profileStatus === 'UNDER_REVIEW';
  const isApproved = profileStatus === 'APPROVED';

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-2">
          <h2 className="text-lg font-semibold text-gray-900 dark:text-white">Perfil del cuidador</h2>
          {(profile?.caregiverProfileComplete || isApproved) && (
            <span className="inline-flex items-center justify-center w-5 h-5 rounded-full bg-green-100 text-green-600">
              <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="3" d="M5 13l4 4L19 7" />
              </svg>
            </span>
          )}
        </div>
        <div className="flex items-center gap-3">
          {isLocked ? (
            <span className="text-xs font-medium px-2.5 py-1 rounded-full bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-300">
              En revisión
            </span>
          ) : (
            <div className="flex items-center gap-3">
              {isApproved && (
                <span className="text-xs font-medium px-2.5 py-1 rounded-full bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300">
                  Aprobado
                </span>
              )}

              {!editing ? (
                <button
                  type="button"
                  onClick={() => { setLocal(profile); setEditing(true); }}
                  className={
                    (profile?.caregiverProfileComplete || isApproved || profileStatus === 'SUBMITTED')
                      ? "text-sm font-medium text-green-600 dark:text-green-400 hover:underline"
                      : "px-4 py-1.5 rounded-lg bg-red-600 text-white text-xs font-black uppercase tracking-tight shadow-md shadow-red-600/20 hover:bg-red-700 active:scale-95 transition-all animate-pulse"
                  }
                >
                  {(profile?.caregiverProfileComplete || isApproved || profileStatus === 'SUBMITTED') ? 'Editar' : 'Completar'}
                </button>
              ) : (
                <div className="flex gap-2">
                  <button
                    type="button"
                    onClick={() => setEditing(false)}
                    className="text-sm font-medium text-gray-500 hover:underline"
                  >
                    Cancelar
                  </button>
                  <button
                    type="button"
                    onClick={handleSave}
                    disabled={saving}
                    className="text-sm font-medium text-green-600 dark:text-green-400 hover:underline disabled:opacity-50"
                  >
                    {saving ? 'Guardando…' : 'Guardar cambios'}
                  </button>
                </div>
              )}
            </div>
          )}
        </div>
      </div>

      {isLocked && (
        <p className="text-sm text-amber-700 dark:text-amber-300 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-xl px-4 py-3">
          Tu perfil está en revisión. No puedes editarlo hasta que el equipo GARDEN lo procese.
        </p>
      )}

      {editing ? (
        <div className="space-y-6">
          <Field label="Zona">
            <select
              value={local?.zone ?? ''}
              onChange={(e) => setLocal((p: any) => ({ ...p, zone: e.target.value }))}
              className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-2.5"
            >
              <option value="">Selecciona...</option>
              {ZONES.map((z) => (
                <option key={z} value={z}>{ZONE_LABELS[z] ?? z}</option>
              ))}
            </select>
          </Field>

          <Field label="Dirección exacta" hint="Solo se compartirá con clientes confirmados.">
            <input
              type="text"
              value={local?.address ?? ''}
              onChange={(e) => setLocal((p: any) => ({ ...p, address: e.target.value }))}
              placeholder="Ej: Calle Los Pinos #123, entre 2do y 3er anillo"
              className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3 text-sm focus:ring-2 focus:ring-green-500 outline-none"
            />
          </Field>
          <Field label="Servicios">
            <div className="flex gap-2">
              {['HOSPEDAJE', 'PASEO'].map((s) => {
                const active = local?.servicesOffered?.includes(s);
                return (
                  <button
                    key={s}
                    type="button"
                    onClick={() => {
                      const next = active
                        ? (local?.servicesOffered ?? []).filter((x: string) => x !== s)
                        : [...(local?.servicesOffered ?? []), s];
                      setLocal((p: any) => ({ ...p, servicesOffered: next }));
                    }}
                    className={`flex-1 py-2.5 rounded-xl border text-sm font-medium ${active ? 'border-green-600 bg-green-50 dark:bg-green-900/20 text-green-700' : 'border-gray-200 dark:border-gray-700'
                      }`}
                  >
                    {s === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseos'}
                  </button>
                );
              })}
            </div>
          </Field>
          {local?.servicesOffered?.includes('HOSPEDAJE') && (
            <Field label="Precio hospedaje (Bs/día)">
              <input
                type="number"
                value={local?.pricePerDay ?? ''}
                onChange={(e) => setLocal((p: any) => ({ ...p, pricePerDay: parseInt(e.target.value) || 0 }))}
                className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-2.5"
              />
            </Field>
          )}
          {local?.servicesOffered?.includes('PASEO') && (
            <div className="grid grid-cols-2 gap-4">
              <Field label="Paseo 30' (Bs)">
                <input
                  type="number"
                  value={local?.pricePerWalk30 ?? ''}
                  onChange={(e) => setLocal((p: any) => ({ ...p, pricePerWalk30: parseInt(e.target.value) || 0 }))}
                  className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-2.5"
                />
              </Field>
              <Field label="Paseo 60' (Bs)">
                <input
                  type="number"
                  value={local?.pricePerWalk60 ?? ''}
                  onChange={(e) => setLocal((p: any) => ({ ...p, pricePerWalk60: parseInt(e.target.value) || 0 }))}
                  className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-2.5"
                />
              </Field>
            </div>
          )}
          <Field label="Bio (mín. 50 caracteres)" hint="Esta es la descripción corta que los dueños verán primero.">
            <textarea
              value={local?.bio ?? ''}
              onChange={(e) => setLocal((p: any) => ({ ...p, bio: e.target.value }))}
              rows={4}
              className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3 text-sm focus:ring-2 focus:ring-green-500 outline-none"
            />
            <p className="text-xs text-gray-400 mt-1">{local?.bio?.length ?? 0}/500</p>
          </Field>

          <Field label="Detalles adicionales de tu perfil" hint="Cuéntanos más sobre ti, tu rutina o lo que los clientes deben saber.">
            <textarea
              value={local?.bioDetail ?? ''}
              onChange={(e) => setLocal((p: any) => ({ ...p, bioDetail: e.target.value }))}
              rows={3}
              className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3 text-sm focus:ring-2 focus:ring-green-500 outline-none"
            />
            <p className="text-xs text-gray-400 mt-1">{local?.bioDetail?.length ?? 0}/300</p>
          </Field>

          <div className="space-y-4 border-t border-gray-100 dark:border-gray-800 pt-6">
            <h3 className="text-sm font-bold text-gray-900 dark:text-white">Fotos del espacio / personales</h3>
            <p className="text-xs text-gray-500">
              {(() => {
                const services = local?.servicesOffered || [];
                const onlyPaseo = services.length === 1 && services.includes('PASEO');
                return onlyPaseo
                  ? "Sube entre 2 y 4 fotos tuyas con mascotas. Esto ayuda a generar confianza."
                  : "Es obligatorio subir entre 4 y 6 fotos de tu hogar (interior/exterior) y perfil.";
              })()}
            </p>

            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              {/* Existing photos */}
              {local?.photos?.map((url: string, i: number) => {
                const isRemoved = photosToRemove.includes(url);
                return (
                  <div key={`old-${i}`} className={`relative aspect-square rounded-xl overflow-hidden border ${isRemoved ? 'opacity-30 grayscale' : 'border-gray-200'}`}>
                    <img src={getImageUrl(url)} className="w-full h-full object-cover" alt="" />
                    <button
                      type="button"
                      onClick={() => setPhotosToRemove((prev: string[]) => isRemoved ? prev.filter((x: string) => x !== url) : [...prev, url])}
                      className={`absolute top-1 right-1 p-1 rounded-full text-white shadow-sm ${isRemoved ? 'bg-green-600' : 'bg-red-600'}`}
                    >
                      {isRemoved ? (
                        <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" /></svg>
                      ) : (
                        <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M6 18L18 6M6 6l12 12" /></svg>
                      )}
                    </button>
                    {isRemoved && <div className="absolute inset-0 flex items-center justify-center text-[10px] font-bold text-white bg-black/20">ELIMINAR</div>}
                  </div>
                );
              })}

              {/* New photo previews */}
              {previews.map((src, i) => (
                <div key={`new-${i}`} className="relative aspect-square rounded-xl overflow-hidden border border-green-200 ring-2 ring-green-500/20">
                  <img src={src} className="w-full h-full object-cover" alt="" />
                  <button
                    type="button"
                    onClick={() => setNewFiles((prev: File[]) => prev.filter((_: File, idx: number) => idx !== i))}
                    className="absolute top-1 right-1 bg-red-600 text-white rounded-full p-1 shadow-sm"
                  >
                    <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M6 18L18 6M6 6l12 12" /></svg>
                  </button>
                  <div className="absolute bottom-0 inset-x-0 bg-green-600 text-[8px] text-white text-center py-0.5 font-bold uppercase">NUEVA</div>
                </div>
              ))}

              {/* Add button */}
              {(() => {
                const services = local?.servicesOffered || [];
                const onlyPaseo = services.length === 1 && services.includes('PASEO');
                const maxPhotos = onlyPaseo ? 4 : 6;
                const currentCount = (local?.photos?.length - photosToRemove.length + newFiles.length);

                if (currentCount < maxPhotos) {
                  return (
                    <label className="aspect-square flex flex-col items-center justify-center rounded-xl border-2 border-dashed border-gray-300 hover:border-green-500 cursor-pointer transition-colors">
                      <input
                        type="file"
                        accept="image/*"
                        multiple
                        className="hidden"
                        onChange={(e) => {
                          const files = Array.from(e.target.files || []);
                          setNewFiles(prev => [...prev, ...files].slice(0, maxPhotos - currentCount));
                          e.target.value = '';
                        }}
                      />
                      <span className="text-xl">➕</span>
                      <span className="text-[10px] font-medium text-gray-500 mt-1">Añadir</span>
                    </label>
                  );
                }
                return null;
              })()}
            </div>
          </div>
          <Field label="Experiencia">
            <div className="flex flex-wrap gap-2">
              {Object.entries(EXP_YEARS_LABELS).map(([key, label]) => (
                <button
                  key={key}
                  type="button"
                  onClick={() => setLocal((p: any) => ({ ...p, experienceYears: key }))}
                  className={`px-3 py-1.5 rounded-lg border text-xs font-medium transition-all ${local?.experienceYears === key ? 'border-green-600 bg-green-50 text-green-700' : 'border-gray-200 dark:border-gray-700'
                    }`}
                >
                  {label}
                </button>
              ))}
            </div>
          </Field>

          <div className="grid grid-cols-2 gap-4">
            <Field label="¿Tienes mascotas propias?">
              <YesNo value={local?.ownPets} onChange={(v) => setLocal((p: any) => ({ ...p, ownPets: v }))} />
            </Field>
            <Field label="¿Has cuidado mascotas ajenas?">
              <YesNo value={local?.caredOthers} onChange={(v) => setLocal((p: any) => ({ ...p, caredOthers: v }))} />
            </Field>
          </div>

          <Field label="Describe tu experiencia detalladamente (mín. 5 caracteres)">
            <textarea
              value={local?.experienceDescription ?? ''}
              onChange={(e) => setLocal((p: any) => ({ ...p, experienceDescription: e.target.value }))}
              rows={3}
              placeholder="Cuéntanos sobre los animales que has cuidado..."
              className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3 text-sm focus:ring-2 focus:ring-green-500 outline-none"
            />
          </Field>

          <Field label="¿Por qué quieres ser cuidador en GARDEN?">
            <textarea
              value={local?.whyCaregiver ?? ''}
              onChange={(e) => setLocal((p: any) => ({ ...p, whyCaregiver: e.target.value }))}
              rows={3}
              className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3 text-sm focus:ring-2 focus:ring-green-500 outline-none"
            />
          </Field>

          <Field label="¿Qué te diferencia de otros cuidadores?">
            <textarea
              value={local?.whatDiffers ?? ''}
              onChange={(e) => setLocal((p: any) => ({ ...p, whatDiffers: e.target.value }))}
              rows={3}
              className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3 text-sm focus:ring-2 focus:ring-green-500 outline-none"
            />
          </Field>
          <Field label="Animales que has cuidado">
            <div className="flex flex-wrap gap-2">
              {Object.entries(ANIMAL_TYPE_LABELS).map(([key, label]) => {
                const active = local?.animalTypes?.includes(key);
                return (
                  <button
                    key={key}
                    type="button"
                    onClick={() => {
                      const next = active
                        ? (local?.animalTypes ?? []).filter((x: string) => x !== key)
                        : [...(local?.animalTypes ?? []), key];
                      setLocal((p: any) => ({ ...p, animalTypes: next }));
                    }}
                    className={`px-3 py-1.5 rounded-lg border text-xs font-medium transition-all ${active ? 'border-green-600 bg-green-50 text-green-700' : 'border-gray-200 dark:border-gray-700'
                      }`}
                  >
                    {label}
                  </button>
                );
              })}
            </div>
          </Field>

          <Field label="¿Cómo manejas a un perro con ansiedad o miedo?">
            <textarea
              value={local?.handleAnxious ?? ''}
              onChange={(e) => setLocal((p: any) => ({ ...p, handleAnxious: e.target.value }))}
              rows={3}
              className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3 text-sm focus:ring-2 focus:ring-green-500 outline-none"
            />
          </Field>

          <Field label="¿Cómo respondes ante una emergencia médica?">
            <textarea
              value={local?.emergencyResponse ?? ''}
              onChange={(e) => setLocal((p: any) => ({ ...p, emergencyResponse: e.target.value }))}
              rows={3}
              className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3 text-sm focus:ring-2 focus:ring-green-500 outline-none"
            />
          </Field>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Field label="¿Aceptas perros agresivos?">
              <YesNo value={local?.acceptAggressive} onChange={(v) => setLocal((p: any) => ({ ...p, acceptAggressive: v }))} />
            </Field>
            <Field label="¿Aceptas cachorros (< 1 año)?">
              <YesNo value={local?.acceptPuppies} onChange={(v) => setLocal((p: any) => ({ ...p, acceptPuppies: v }))} />
            </Field>
            <Field label="¿Aceptas mascotas seniors (> 8 años)?">
              <YesNo value={local?.acceptSeniors} onChange={(v) => setLocal((p: any) => ({ ...p, acceptSeniors: v }))} />
            </Field>
          </div>

          <Field label="Administración de medicamentos">
            <div className="flex flex-wrap gap-2">
              {Object.entries(MEDICATION_LABELS).map(([key, label]) => {
                const active = local?.acceptMedication?.includes(key);
                return (
                  <button
                    key={key}
                    type="button"
                    onClick={() => {
                      const next = active
                        ? (local?.acceptMedication ?? []).filter((x: string) => x !== key)
                        : [...(local?.acceptMedication ?? []), key];
                      setLocal((p: any) => ({ ...p, acceptMedication: next }));
                    }}
                    className={`px-4 py-2 rounded-xl border text-sm font-medium transition-all ${active ? 'border-green-600 bg-green-50 dark:bg-green-900/20 text-green-700' : 'border-gray-200 dark:border-gray-700'
                      }`}
                  >
                    {label}
                  </button>
                );
              })}
            </div>
          </Field>

          {local?.servicesOffered?.includes('HOSPEDAJE') && (
            <>
              <div className="border-t border-gray-100 dark:border-gray-800 pt-6 my-6">
                <h3 className="text-sm font-bold text-gray-900 dark:text-white mb-4">Entorno del hogar</h3>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <Field label="¿Es tu propia casa?">
                    <YesNo value={local?.ownHome} onChange={(v) => setLocal((p: any) => ({ ...p, ownHome: v }))} />
                  </Field>
                  <Field label="Tipo de vivienda">
                    <select
                      value={local?.homeType ?? ''}
                      onChange={(e) => setLocal((p: any) => ({ ...p, homeType: e.target.value }))}
                      className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-2 text-sm"
                    >
                      <option value="">Selecciona...</option>
                      {Object.entries(HOME_TYPE_LABELS).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                    </select>
                  </Field>
                  <Field label="¿Tiene patio?">
                    <YesNo value={local?.hasYard} onChange={(v) => setLocal((p: any) => ({ ...p, hasYard: v }))} />
                  </Field>
                  {local?.hasYard && (
                    <Field label="¿Patio cercado?">
                      <YesNo value={local?.yardFenced} onChange={(v) => setLocal((p: any) => ({ ...p, yardFenced: v }))} />
                    </Field>
                  )}
                  <Field label="¿Hay niños en casa?">
                    <YesNo value={local?.hasChildren} onChange={(v) => setLocal((p: any) => ({ ...p, hasChildren: v }))} />
                  </Field>
                  <Field label="¿Hay otras mascotas?">
                    <YesNo value={local?.hasOtherPets} onChange={(v) => setLocal((p: any) => ({ ...p, hasOtherPets: v }))} />
                  </Field>
                </div>

                <div className="mt-4">
                  <Field label="Tipo de espacio" hint="Selecciona todos los que correspondan">
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                      {['Casa con patio', 'Casa sin patio', 'Departamento pequeño', 'Departamento amplio'].map(opt => {
                        const active = Array.isArray(local?.spaceType) && local.spaceType.includes(opt);
                        return (
                          <button
                            key={opt}
                            type="button"
                            onClick={() => {
                              const current = Array.isArray(local?.spaceType) ? (local.spaceType as string[]) : [];
                              const next = active ? current.filter((x: string) => x !== opt) : [...current, opt];
                              setLocal((p: any) => ({ ...p, spaceType: next }));
                            }}
                            className={`px-3 py-2 rounded-xl border text-sm text-left transition-all ${active ? 'border-green-600 bg-green-50 text-green-700' : 'border-gray-200 dark:border-gray-700'}`}
                          >
                            {active ? '✅ ' : '⬜ '} {opt}
                          </button>
                        );
                      })}
                    </div>
                  </Field>
                </div>

                <div className="mt-2 text-sm">
                  <Field label="Descripción del espacio">
                    <textarea
                      value={local?.spaceDescription ?? ''}
                      onChange={(e) => setLocal((p: any) => ({ ...p, spaceDescription: e.target.value }))}
                      rows={2}
                      placeholder="Áreas comunes, restricciones, facilidades..."
                      className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3 text-sm focus:ring-2 focus:ring-green-500 outline-none"
                    />
                  </Field>
                </div>

                <div className="grid grid-cols-2 gap-4 mt-2">
                  <Field label="¿Dónde duermen tus mascotas?">
                    <select
                      value={local?.petsSleep ?? ''}
                      onChange={(e) => setLocal((p: any) => ({ ...p, petsSleep: e.target.value }))}
                      className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-2 text-sm"
                    >
                      <option value="">Selecciona...</option>
                      {Object.entries(SLEEP_LABELS).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                    </select>
                  </Field>
                  <Field label="¿Dónde dormirán los huéspedes?">
                    <select
                      value={local?.clientPetsSleep ?? ''}
                      onChange={(e) => setLocal((p: any) => ({ ...p, clientPetsSleep: e.target.value }))}
                      className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-2 text-sm"
                    >
                      <option value="">Selecciona...</option>
                      {Object.entries(CLIENT_SLEEP_LABELS).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                    </select>
                  </Field>
                </div>
              </div>

              <div className="border-t border-gray-100 dark:border-gray-800 pt-6 my-6">
                <h3 className="text-sm font-bold text-gray-900 dark:text-white mb-4">Rutina y disponibilidad (Hospedaje)</h3>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <Field label="Horas que la mascota estará sola">
                    <input
                      type="number"
                      value={local?.hoursAlone ?? ''}
                      onChange={(e) => setLocal((p: any) => ({ ...p, hoursAlone: parseInt(e.target.value) || 0 }))}
                      className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-2 text-sm"
                    />
                  </Field>
                  <Field label="¿Trabajas desde casa?">
                    <YesNo value={local?.workFromHome} onChange={(v) => setLocal((p: any) => ({ ...p, workFromHome: v }))} />
                  </Field>
                  <Field label="Máx. mascotas al mismo tiempo">
                    <input
                      type="number"
                      value={local?.maxPets ?? ''}
                      onChange={(e) => setLocal((p: any) => ({ ...p, maxPets: parseInt(e.target.value) || 1 }))}
                      className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-2 text-sm"
                    />
                  </Field>
                  <Field label="¿Sales mucho de casa?">
                    <YesNo value={local?.oftenOut} onChange={(v) => setLocal((p: any) => ({ ...p, oftenOut: v }))} />
                  </Field>
                </div>
                <Field label="Describe un día típico con un huésped">
                  <textarea
                    value={local?.typicalDay ?? ''}
                    onChange={(e) => setLocal((p: any) => ({ ...p, typicalDay: e.target.value }))}
                    rows={3}
                    className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3 text-sm focus:ring-2 focus:ring-green-500 outline-none"
                  />
                </Field>
              </div>
            </>
          )}

          <Field label="Tamaños aceptados">
            <div className="flex flex-wrap gap-2">
              {Object.entries(PET_SIZE_LABELS).map(([key, label]) => {
                const active = local?.sizesAccepted?.includes(key);
                return (
                  <button
                    key={key}
                    type="button"
                    onClick={() => {
                      const next = active
                        ? (local?.sizesAccepted ?? []).filter((x: string) => x !== key)
                        : [...(local?.sizesAccepted ?? []), key];
                      setLocal((p: any) => ({ ...p, sizesAccepted: next }));
                    }}
                    className={`px-3 py-1.5 rounded-lg border text-xs font-medium ${active ? 'border-green-600 bg-green-50 text-green-700' : 'border-gray-200 dark:border-gray-700'
                      }`}
                  >
                    {label}
                  </button>
                );
              })}
            </div>
          </Field>

          <Field label="¿Hay razas que NO aceptas?">
            <YesNo value={local?.noAcceptBreeds} onChange={(v) => setLocal((p: any) => ({ ...p, noAcceptBreeds: v }))} />
          </Field>
          {local?.noAcceptBreeds && (
            <Field label="Dinos cuáles y por qué">
              <textarea
                value={local?.breedsWhy ?? ''}
                onChange={(e) => setLocal((p: any) => ({ ...p, breedsWhy: e.target.value }))}
                rows={2}
                className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3 text-sm focus:ring-2 focus:ring-green-500 outline-none"
              />
            </Field>
          )}

          {/* Action buttons at the bottom */}
          <div className="flex flex-col sm:flex-row gap-3 pt-6 border-t border-gray-100 dark:border-gray-800">
            <button
              type="button"
              onClick={handleSave}
              disabled={saving}
              className="flex-1 py-3 rounded-xl bg-green-600 text-white font-bold hover:bg-green-700 active:scale-[0.98] transition-all disabled:opacity-50"
            >
              {saving ? 'Guardando cambios…' : 'Guardar todos los cambios'}
            </button>
            <button
              type="button"
              onClick={() => setEditing(false)}
              disabled={saving}
              className="flex-1 py-3 rounded-xl border border-gray-200 dark:border-gray-700 text-gray-600 dark:text-gray-400 font-medium hover:bg-gray-50 dark:hover:bg-gray-800 transition-all disabled:opacity-50"
            >
              Cancelar
            </button>
          </div>
        </div>
      ) : (
        <div className="space-y-6">
          {profile?.photos?.length > 0 && (
            <div>
              <p className="text-sm font-medium text-gray-500 dark:text-gray-400 mb-2">Fotos del espacio</p>
              <div className="grid grid-cols-3 sm:grid-cols-4 gap-2">
                {profile.photos.map((url: string, i: number) => (
                  <img
                    key={i}
                    src={getImageUrl(url)}
                    alt=""
                    className="aspect-square rounded-xl object-cover border border-gray-200 dark:border-gray-700"
                  />
                ))}
              </div>
            </div>
          )}
          {profile?.zone && (
            <p><span className="text-gray-500">Zona:</span> {ZONE_LABELS[profile.zone as keyof typeof ZONE_LABELS] ?? profile.zone}</p>
          )}
          {profile?.servicesOffered?.length > 0 && (
            <p>
              <span className="text-gray-500">Servicios:</span>{' '}
              {profile.servicesOffered.map((s: string) => s === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseos').join(', ')}
              {profile.pricePerDay != null && ` · ${profile.pricePerDay} Bs/día`}
              {(profile.pricePerWalk30 != null || profile.pricePerWalk60 != null) && (
                <span> · Paseos: {[profile.pricePerWalk30 && `30' ${profile.pricePerWalk30} Bs`, profile.pricePerWalk60 && `60' ${profile.pricePerWalk60} Bs`].filter(Boolean).join(', ')}</span>
              )}
            </p>
          )}
          {profile?.bio && <p className="leading-relaxed">{profile.bio}</p>}

          <div className="grid grid-cols-1 md:grid-cols-2 gap-x-8 gap-y-4 text-sm border-t border-gray-100 dark:border-gray-800 pt-6">
            {profile?.experienceYears && (
              <p><span className="text-gray-500">Experiencia:</span> {EXP_YEARS_LABELS[profile.experienceYears] ?? profile.experienceYears}</p>
            )}
            <p><span className="text-gray-500">Mascotas propias:</span> {profile?.ownPets ? 'Sí' : 'No'}</p>
            <p><span className="text-gray-500">Cuidado masctoas ajenas:</span> {profile?.caredOthers ? 'Sí' : 'No'}</p>

            {profile?.animalTypes?.length > 0 && (
              <p><span className="text-gray-500">Animales:</span> {profile.animalTypes.map((k: string) => ANIMAL_TYPE_LABELS[k] ?? k).join(', ')}</p>
            )}

            {profile?.spaceType?.length > 0 && (
              <p><span className="text-gray-500">Espacio:</span> {profile.spaceType.join(', ')}</p>
            )}

            {profile?.address && (
              <p><span className="text-gray-500">Dirección:</span> {profile.address}</p>
            )}

            <p><span className="text-gray-500">Acepta agresivos:</span> {profile?.acceptAggressive ? 'Sí' : 'No'}</p>
            <p><span className="text-gray-500">Acepta cachorros:</span> {profile?.acceptPuppies ? 'Sí' : 'No'}</p>
            <p><span className="text-gray-500">Acepta seniors:</span> {profile?.acceptSeniors ? 'Sí' : 'No'}</p>

            {profile?.acceptMedication?.length > 0 && (
              <p><span className="text-gray-500">Medicación:</span> {profile.acceptMedication.map((k: string) => MEDICATION_LABELS[k] ?? k).join(', ')}</p>
            )}

            {profile?.sizesAccepted?.length > 0 && (
              <p><span className="text-gray-500">Tamaños:</span> {profile.sizesAccepted.map((k: string) => PET_SIZE_LABELS[k] ?? k).join(', ')}</p>
            )}
          </div>

          <div className="space-y-4 border-t border-gray-100 dark:border-gray-800 pt-6">
            {profile?.experienceDescription && (
              <div>
                <h4 className="text-xs font-bold text-gray-400 uppercase tracking-widest mb-1">Sobre su experiencia</h4>
                <p className="text-sm text-gray-700 dark:text-gray-300">{profile.experienceDescription}</p>
              </div>
            )}
            {profile?.handleAnxious && (
              <div>
                <h4 className="text-xs font-bold text-gray-400 uppercase tracking-widest mb-1">Manejo de ansiedad</h4>
                <p className="text-sm text-gray-700 dark:text-gray-300">{profile.handleAnxious}</p>
              </div>
            )}
            {profile?.spaceDescription && (
              <div>
                <h4 className="text-xs font-bold text-gray-400 uppercase tracking-widest mb-1">Sobre el espacio</h4>
                <p className="text-sm text-gray-700 dark:text-gray-300">{profile.spaceDescription}</p>
              </div>
            )}
          </div>

          {profile?.servicesOffered?.includes('HOSPEDAJE') && (
            <div className="bg-gray-50 dark:bg-gray-900/40 rounded-2xl p-6 space-y-4">
              <h3 className="text-sm font-bold text-gray-900 dark:text-white">Detalles del hogar</h3>
              <div className="grid grid-cols-2 gap-4 text-sm">
                <p><span className="text-gray-500">Vivienda:</span> {HOME_TYPE_LABELS[profile.homeType] ?? profile.homeType}</p>
                <p><span className="text-gray-500">Patio:</span> {profile.hasYard ? (profile.yardFenced ? 'Sí (Cercado)' : 'Sí (Sin cercar)') : 'No'}</p>
                <p><span className="text-gray-500">Niños en casa:</span> {profile.hasChildren ? 'Sí' : 'No'}</p>
                <p><span className="text-gray-500">Otras mascotas:</span> {profile.hasOtherPets ? 'Sí' : 'No'}</p>
                <p><span className="text-gray-500">Duerme:</span> {SLEEP_LABELS[profile.petsSleep] ?? profile.petsSleep}</p>
                <p><span className="text-gray-500">Ubicación huéspedes:</span> {CLIENT_SLEEP_LABELS[profile.clientPetsSleep] ?? profile.clientPetsSleep}</p>
                <p><span className="text-gray-500">Horas sola:</span> {profile.hoursAlone}h</p>
                <p><span className="text-gray-500">Home office:</span> {profile.workFromHome ? 'Sí' : 'No'}</p>
                <p><span className="text-gray-500">Máx. mascotas:</span> {profile.maxPets}</p>
              </div>
              {profile?.typicalDay && (
                <div className="pt-2">
                  <h4 className="text-xs font-bold text-gray-400 uppercase tracking-widest mb-1">Día típico</h4>
                  <p className="text-sm text-gray-700 dark:text-gray-300 italic">"{profile.typicalDay}"</p>
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
