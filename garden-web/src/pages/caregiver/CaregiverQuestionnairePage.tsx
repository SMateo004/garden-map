import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { getMyProfile, patchProfile } from '@/api/caregiverProfile';
import type { MyProfileResponse } from '@/api/caregiverProfile';
import toast from 'react-hot-toast';

const ZONES = ['EQUIPETROL', 'URBARI', 'NORTE', 'LAS_PALMAS', 'CENTRO_SAN_MARTIN', 'OTROS'] as const;
const ZONE_LABELS: Record<string, string> = {
  EQUIPETROL: 'Equipetrol',
  URBARI: 'Urbari',
  NORTE: 'Norte',
  LAS_PALMAS: 'Las Palmas',
  CENTRO_SAN_MARTIN: 'Centro San Martín',
  OTROS: 'Otros',
};

const EXPERIENCE_OPTIONS = [
  { value: 'NEVER', label: 'Sin experiencia previa' },
  { value: 'LESS1', label: 'Menos de 1 año' },
  { value: 'ONE_TO_FIVE', label: '1 a 5 años' },
  { value: 'MORE5', label: 'Más de 5 años' },
];

const PET_SIZE_OPTIONS = [
  { value: 'SMALL', label: 'Pequeño' },
  { value: 'MEDIUM', label: 'Mediano' },
  { value: 'LARGE', label: 'Grande' },
  { value: 'GIANT', label: 'Gigante' },
];

const SPACE_TYPES = ['Casa con patio', 'Casa sin patio', 'Departamento pequeño', 'Departamento amplio'];

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-4 mb-4">
      <h2 className="text-base font-semibold text-gray-900 dark:text-white mb-3">{title}</h2>
      {children}
    </section>
  );
}

export function CaregiverQuestionnairePage() {
  const navigate = useNavigate();
  const { isCaregiver } = useAuth();
  const [profile, setProfile] = useState<MyProfileResponse | null | undefined>(undefined);
  const [saving, setSaving] = useState(false);

  const [servicesOffered, setServicesOffered] = useState<string[]>([]);
  const [experienceYears, setExperienceYears] = useState<string>('');
  const [experienceDescription, setExperienceDescription] = useState('');
  const [bio, setBio] = useState('');
  const [bioDetail, setBioDetail] = useState('');
  const [sizesAccepted, setSizesAccepted] = useState<string[]>([]);
  const [spaceType, setSpaceType] = useState<string[]>([]);
  const [spaceDescription, setSpaceDescription] = useState('');
  const [typicalDay, setTypicalDay] = useState('');
  const [zone, setZone] = useState('');
  const [pricePerDay, setPricePerDay] = useState<number>(0);
  const [pricePerWalk30, setPricePerWalk30] = useState<number>(0);
  const [pricePerWalk60, setPricePerWalk60] = useState<number>(0);

  useEffect(() => {
    if (!isCaregiver) return;
    getMyProfile()
      .then((p) => {
        setProfile(p);
        if (p) {
          setServicesOffered((p.servicesOffered as string[]) ?? []);
          setExperienceYears((p as { experienceYears?: string }).experienceYears ?? '');
          setExperienceDescription((p as { experienceDescription?: string }).experienceDescription ?? '');
          setBio(p.bio ?? '');
          setBioDetail(p.bioDetail ?? '');
          setSizesAccepted((p as { sizesAccepted?: string[] }).sizesAccepted ?? []);
          setSpaceType(Array.isArray(p.spaceType) ? p.spaceType : []);
          setSpaceDescription(p.spaceDescription ?? '');
          setTypicalDay((p as { typicalDay?: string }).typicalDay ?? '');
          setZone((p.zone as string) ?? '');
          setPricePerDay(p.pricePerDay ?? 0);
          setPricePerWalk30(p.pricePerWalk30 ?? 0);
          setPricePerWalk60(p.pricePerWalk60 ?? 0);
        }
      })
      .catch(() => setProfile(null));
  }, [isCaregiver]);

  const save = async (payload: Record<string, unknown>) => {
    setSaving(true);
    try {
      await patchProfile(payload);
      const p = await getMyProfile();
      setProfile(p);
      toast.success('Guardado');
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al guardar');
    } finally {
      setSaving(false);
    }
  };

  const toggleArray = (arr: string[], val: string) =>
    arr.includes(val) ? arr.filter((x) => x !== val) : [...arr, val];

  if (!isCaregiver) {
    navigate('/caregiver/auth');
    return null;
  }

  if (profile === undefined) {
    return <div className="flex min-h-screen items-center justify-center">Cargando…</div>;
  }

  const completed =
    bio.length >= 50 &&
    zone &&
    servicesOffered.length > 0 &&
    (servicesOffered.includes('HOSPEDAJE') ? spaceType.length > 0 : true);

  const progress = [
    servicesOffered.length > 0,
    experienceYears || experienceDescription.length >= 20,
    bio.length >= 50,
    sizesAccepted.length > 0,
    spaceType.length > 0 || !servicesOffered.includes('HOSPEDAJE'),
    typicalDay.length >= 20,
    pricePerDay > 0 || pricePerWalk30 > 0 || pricePerWalk60 > 0,
  ].filter(Boolean).length;

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900">
      <div className="mx-auto max-w-2xl px-4 py-6">
        <button
          type="button"
          onClick={() => navigate(-1)}
          className="text-sm text-green-600 dark:text-green-400 hover:underline mb-4"
        >
          ← Volver
        </button>
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white mb-2">Perfil del cuidador</h1>
        <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">
          Completa todas las secciones. Progreso: {progress}/7
        </p>
        <div className="h-2 bg-gray-200 dark:bg-gray-700 rounded-full mb-6">
          <div
            className="h-full bg-green-500 transition-all"
            style={{ width: `${(progress / 7) * 100}%` }}
          />
        </div>

        <Section title="1. Servicios">
          <div className="flex gap-4">
            {['HOSPEDAJE', 'PASEO'].map((s) => (
              <label key={s} className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={servicesOffered.includes(s)}
                  onChange={() => {
                    const next = toggleArray(servicesOffered, s);
                    setServicesOffered(next);
                    save({ servicesOffered: next });
                  }}
                  className="rounded border-gray-300 text-green-600"
                />
                <span>{s === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseos'}</span>
              </label>
            ))}
          </div>
        </Section>

        <Section title="2. Experiencia">
          <div className="space-y-3">
            <div>
              <label className="block text-sm text-gray-600 dark:text-gray-400 mb-1">Años de experiencia</label>
              <select
                value={experienceYears}
                onChange={(e) => {
                  setExperienceYears(e.target.value);
                  save({ experienceYears: e.target.value || undefined });
                }}
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 px-3 py-2 text-sm"
              >
                <option value="">Selecciona</option>
                {EXPERIENCE_OPTIONS.map((o) => (
                  <option key={o.value} value={o.value}>
                    {o.label}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-sm text-gray-600 dark:text-gray-400 mb-1">Descripción (opcional)</label>
              <textarea
                value={experienceDescription}
                onChange={(e) => setExperienceDescription(e.target.value)}
                onBlur={() => (experienceDescription.length >= 100 || !experienceDescription) && save({ experienceDescription: experienceDescription || undefined })}
                rows={3}
                placeholder="Cuéntanos tu experiencia con mascotas..."
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 px-3 py-2 text-sm"
              />
            </div>
          </div>
        </Section>

        <Section title="3. Detalle (bio)">
          <div className="space-y-3">
            <div>
              <label className="block text-sm text-gray-600 dark:text-gray-400 mb-1">Resumen * (mín. 50 caracteres)</label>
              <textarea
                value={bio}
                onChange={(e) => setBio(e.target.value)}
                onBlur={() => bio.length >= 50 && save({ bio })}
                rows={4}
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 px-3 py-2 text-sm"
              />
              <p className="text-xs text-gray-500 mt-1">{bio.length}/500</p>
            </div>
            <div>
              <label className="block text-sm text-gray-600 dark:text-gray-400 mb-1">Amplía (opcional)</label>
              <textarea
                value={bioDetail}
                onChange={(e) => setBioDetail(e.target.value)}
                onBlur={() => save({ bioDetail: bioDetail || undefined })}
                rows={2}
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 px-3 py-2 text-sm"
              />
            </div>
          </div>
        </Section>

        <Section title="4. Preferencias - Tamaños">
          <div className="flex flex-wrap gap-3">
            {PET_SIZE_OPTIONS.map((o) => (
              <label key={o.value} className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={sizesAccepted.includes(o.value)}
                  onChange={() => {
                    const next = toggleArray(sizesAccepted, o.value);
                    setSizesAccepted(next);
                    save({ sizesAccepted: next });
                  }}
                  className="rounded border-gray-300 text-green-600"
                />
                <span className="text-sm">{o.label}</span>
              </label>
            ))}
          </div>
        </Section>

        <Section title="5. Hogar">
          <div className="space-y-3">
            {servicesOffered.includes('HOSPEDAJE') && (
              <>
                <div>
                  <label className="block text-sm text-gray-600 dark:text-gray-400 mb-1">Tipo de espacio</label>
                  <div className="flex flex-wrap gap-2">
                    {SPACE_TYPES.map((t) => (
                      <label key={t} className="flex items-center gap-1 cursor-pointer">
                        <input
                          type="checkbox"
                          checked={spaceType.includes(t)}
                          onChange={() => {
                            const next = toggleArray(spaceType, t);
                            setSpaceType(next);
                            save({ spaceType: next });
                          }}
                          className="rounded border-gray-300 text-green-600"
                        />
                        <span className="text-sm">{t}</span>
                      </label>
                    ))}
                  </div>
                </div>
                <div>
                  <label className="block text-sm text-gray-600 dark:text-gray-400 mb-1">Descripción del espacio</label>
                  <textarea
                    value={spaceDescription}
                    onChange={(e) => setSpaceDescription(e.target.value)}
                    onBlur={() => save({ spaceDescription: spaceDescription || undefined })}
                    rows={2}
                    className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 px-3 py-2 text-sm"
                  />
                </div>
              </>
            )}
            <div>
              <label className="block text-sm text-gray-600 dark:text-gray-400 mb-1">Zona *</label>
              <div className="flex flex-wrap gap-2">
                {ZONES.map((z) => (
                  <button
                    key={z}
                    type="button"
                    onClick={() => {
                      setZone(z);
                      save({ zone: z });
                    }}
                    className={`rounded-lg px-3 py-1.5 text-sm ${
                      zone === z
                        ? 'bg-green-600 text-white'
                        : 'bg-gray-200 dark:bg-gray-700 text-gray-700 dark:text-gray-300'
                    }`}
                  >
                    {ZONE_LABELS[z] ?? z}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </Section>

        <Section title="6. Rutina">
          <div>
            <label className="block text-sm text-gray-600 dark:text-gray-400 mb-1">Describe un día típico</label>
            <textarea
              value={typicalDay}
              onChange={(e) => setTypicalDay(e.target.value)}
              onBlur={() => (typicalDay.length >= 100 || !typicalDay) && save({ typicalDay: typicalDay || undefined })}
              rows={4}
              placeholder="Ej: Me levanto a las 7, paseo a mis perros..."
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 px-3 py-2 text-sm"
            />
          </div>
        </Section>

        <Section title="7. Tarifas (Bs)">
          <div className="grid gap-3 sm:grid-cols-3">
            {servicesOffered.includes('HOSPEDAJE') && (
              <div>
                <label className="block text-sm text-gray-600 dark:text-gray-400 mb-1">Por día (hospedaje)</label>
                <input
                  type="number"
                  min={0}
                  value={pricePerDay || ''}
                  onChange={(e) => setPricePerDay(Number(e.target.value) || 0)}
                  onBlur={() => save({ pricePerDay: pricePerDay || undefined })}
                  className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 px-3 py-2 text-sm"
                />
              </div>
            )}
            {servicesOffered.includes('PASEO') && (
              <>
                <div>
                  <label className="block text-sm text-gray-600 dark:text-gray-400 mb-1">Paseo 30 min</label>
                  <input
                    type="number"
                    min={0}
                    value={pricePerWalk30 || ''}
                    onChange={(e) => setPricePerWalk30(Number(e.target.value) || 0)}
                    onBlur={() => save({ pricePerWalk30: pricePerWalk30 || undefined })}
                    className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 px-3 py-2 text-sm"
                  />
                </div>
                <div>
                  <label className="block text-sm text-gray-600 dark:text-gray-400 mb-1">Paseo 60 min</label>
                  <input
                    type="number"
                    min={0}
                    value={pricePerWalk60 || ''}
                    onChange={(e) => setPricePerWalk60(Number(e.target.value) || 0)}
                    onBlur={() => save({ pricePerWalk60: pricePerWalk60 || undefined })}
                    className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 px-3 py-2 text-sm"
                  />
                </div>
              </>
            )}
          </div>
          {servicesOffered.length === 0 && (
            <p className="text-sm text-gray-500">Selecciona al menos un servicio arriba.</p>
          )}
        </Section>

        <div className="flex justify-between pt-4">
          <button
            type="button"
            onClick={() => navigate(-1)}
            className="rounded-xl border border-gray-300 dark:border-gray-600 px-4 py-2 text-sm"
          >
            Volver
          </button>
          <button
            type="button"
            onClick={async () => {
              if (!completed || saving) return;
              const bioToSave = bio.length >= 50 ? bio : undefined;
              if (bioToSave || zone || servicesOffered.length) {
                setSaving(true);
                try {
                  await patchProfile({
                    bio: bioToSave,
                    zone: zone || undefined,
                    servicesOffered: servicesOffered.length ? servicesOffered : undefined,
                    spaceType: spaceType.length ? spaceType : undefined,
                    spaceDescription: spaceDescription || undefined,
                    experienceYears: experienceYears || undefined,
                    experienceDescription: experienceDescription.length >= 100 ? experienceDescription : undefined,
                    sizesAccepted: sizesAccepted.length ? sizesAccepted : undefined,
                    typicalDay: typicalDay.length >= 100 ? typicalDay : undefined,
                    pricePerDay: pricePerDay || undefined,
                    pricePerWalk30: pricePerWalk30 || undefined,
                    pricePerWalk60: pricePerWalk60 || undefined,
                  });
                } finally {
                  setSaving(false);
                }
              }
              navigate('/caregiver/onboarding');
            }}
            disabled={!completed || saving}
            className={`rounded-xl bg-green-600 px-6 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50 ${!completed ? 'animate-bounce' : ''}`}
          >
            {saving ? 'Guardando…' : 'Continuar'}
          </button>
        </div>
      </div>
    </div>
  );
}
