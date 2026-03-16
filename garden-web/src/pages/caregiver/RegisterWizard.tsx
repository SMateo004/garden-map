import { useState, useCallback, useEffect } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import toast from 'react-hot-toast';
import { useAuth } from '@/contexts/AuthContext';
import { registerCaregiver, uploadRegistrationPhotos } from '@/api/auth';
import type { RegisterCaregiverPayload } from '@/api/auth';
import { getMyProfile, patchProfile } from '@/api/caregiverProfile';
import type { MyProfileResponse } from '@/api/caregiverProfile';
import {
  defaultWizardData,
  getStepSchema,
  type WizardData,
  type WizardDraft,
} from '@/forms/caregiverWizardSchemas';
import { ZONES, ZONE_LABELS } from '@/types/caregiver';
import type { Zone } from '@/types/caregiver';
import { getImageUrl } from '@/utils/images';

const DRAFT_KEY = 'garden_wizard_draft';
const TOTAL_STEPS = 10;

/** Mapea el campo de error del backend al paso del wizard (1-10). */
function stepForField(field: string): number {
  if (field.startsWith('user.')) {
    if (field.includes('phone') || field.includes('firstName') || field.includes('lastName') || field.includes('dateOfBirth')) return 1;
    if (field.includes('email') || field.includes('password')) return 2;
  }
  if (field.startsWith('profile.')) {
    if (field.includes('zone')) return 3;
    if (field.includes('servicesOffered')) return 4;
    if (field.includes('bio')) return 5;
    if (field.includes('spaceType') || field.includes('spaceDescription')) return 6;
    if (field.includes('price')) return 7;
    if (field.includes('photos')) return 8;
  }
  return 10; // revisión
}

function loadDraft(): WizardDraft | null {
  try {
    const raw = localStorage.getItem(DRAFT_KEY);
    if (!raw) return null;
    const draft = JSON.parse(raw) as WizardDraft;
    if (draft.lastSavedAt && Date.now() - new Date(draft.lastSavedAt).getTime() > 7 * 24 * 60 * 60 * 1000) {
      localStorage.removeItem(DRAFT_KEY);
      return null;
    }
    return draft;
  } catch {
    return null;
  }
}

function saveDraft(step: number, data: Partial<WizardData>) {
  try {
    const draft: WizardDraft = {
      currentStep: step,
      lastSavedAt: new Date().toISOString(),
      data: { ...data },
    };
    localStorage.setItem(DRAFT_KEY, JSON.stringify(draft));
  } catch {
    //
  }
}

function clearDraft() {
  localStorage.removeItem(DRAFT_KEY);
}

/** Pre-llena WizardData desde GET /api/caregiver/my-profile (para flujo "Intentar nuevamente"). */
function myProfileToWizardData(profile: MyProfileResponse): Partial<WizardData> {
  const u = profile.user as { dateOfBirth?: string | Date } | undefined;
  const dob = u?.dateOfBirth;
  const dateOfBirthStr = dob
    ? typeof dob === 'string'
      ? dob.slice(0, 10)
      : dob instanceof Date
        ? dob.toISOString().slice(0, 10)
        : ''
    : '';
  const bio = profile.bio ?? '';
  const bioDetail = profile.bioDetail ?? '';
  return {
    firstName: profile.user?.firstName ?? '',
    lastName: profile.user?.lastName ?? '',
    phone: profile.user?.phone ?? '',
    dateOfBirth: dateOfBirthStr,
    email: profile.user?.email ?? '',
    password: '',
    confirmPassword: '',
    zone: (profile.zone as WizardData['zone']) ?? '',
    servicesOffered: (profile.servicesOffered as ('HOSPEDAJE' | 'PASEO')[]) ?? [],
    bioSummary: bio.slice(0, 500),
    bioDetail: bioDetail.slice(0, 300),
    spaceType: Array.isArray(profile.spaceType) ? profile.spaceType : (profile.spaceType ? [profile.spaceType] : []),
    spaceDescription: profile.spaceDescription ?? '',
    pricePerDay: profile.pricePerDay ?? 0,
    pricePerWalk30: profile.pricePerWalk30 ?? 0,
    pricePerWalk60: profile.pricePerWalk60 ?? 0,
    photoUrls: profile.photos ?? [],
    termsAccepted: profile.termsAccepted ?? false,
    privacyAccepted: profile.privacyAccepted ?? false,
    verificationAccepted: profile.verificationAccepted ?? false,
  };
}

export function RegisterWizard() {
  const navigate = useNavigate();
  const location = useLocation();
  const stateEmail = (location.state as { email?: string })?.email;
  const { isCaregiver } = useAuth();
  const [currentStep, setCurrentStep] = useState(1);
  const [data, setData] = useState<WizardData>(() => {
    const draft = loadDraft();
    let initialData = defaultWizardData;
    if (draft?.data) {
      initialData = { ...defaultWizardData, ...draft.data };
    }
    if (stateEmail) {
      initialData.email = stateEmail;
    }
    return initialData;
  });
  const [showExitModal, setShowExitModal] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [retryMode, setRetryMode] = useState(false);
  const [caregiverCheckDone, setCaregiverCheckDone] = useState(!isCaregiver);
  // Estado para errores de campos específicos (email/phone duplicados)
  const [fieldErrors, setFieldErrors] = useState<{ email?: string; phone?: string }>({});

  useEffect(() => {
    const draft = loadDraft();
    if (draft?.currentStep && draft.data) {
      setCurrentStep(Math.min(draft.currentStep, TOTAL_STEPS));
      setData((prev) => ({ ...prev, ...draft.data }));
    }
  }, []);

  useEffect(() => {
    if (!isCaregiver) {
      setCaregiverCheckDone(true);
      return;
    }
    getMyProfile()
      .then((profile) => {
        if (!profile) {
          navigate('/caregiver/dashboard');
          return;
        }
        const profileStatus = (profile as any).profileStatus || 'INCOMPLETE';
        if (profileStatus === 'SUBMITTED' || profileStatus === 'UNDER_REVIEW' || profileStatus === 'APPROVED') {
          navigate('/caregiver/dashboard');
          return;
        }
        if (profileStatus === 'INCOMPLETE') {
          setRetryMode(true);
          const prefill = myProfileToWizardData(profile);
          setData((prev) => ({ ...defaultWizardData, ...prev, ...prefill }));
          saveDraft(1, { ...defaultWizardData, ...prefill });
        } else {
          navigate('/caregiver/dashboard');
        }
        setCaregiverCheckDone(true);
      })
      .catch(() => {
        navigate('/caregiver/dashboard');
        setCaregiverCheckDone(true);
      });
  }, [isCaregiver, navigate]);

  useEffect(() => {
    if (!retryMode) saveDraft(currentStep, data);
  }, [currentStep, data, retryMode]);

  const stepSchema = currentStep <= 9 ? getStepSchema(currentStep, data) : null;
  const validateCurrentStep = useCallback((overrideData?: WizardData): boolean => {
    if (!stepSchema) return true;
    const values = getStepValues(currentStep, overrideData || data);
    const result = stepSchema.safeParse(values);
    return result.success;
  }, [currentStep, data, stepSchema]);

  const goNext = useCallback((overrideData?: Partial<WizardData>) => {
    const nextData = overrideData ? { ...data, ...overrideData } : data;
    if (!validateCurrentStep(nextData)) {
      toast.error('Completa los campos requeridos');
      return;
    }
    if (currentStep >= TOTAL_STEPS) return;
    if (currentStep === 5 && !nextData.servicesOffered.includes('HOSPEDAJE')) {
      setCurrentStep(7);
    } else {
      setCurrentStep((s) => s + 1);
    }
  }, [currentStep, data, validateCurrentStep]);

  const goPrev = useCallback(() => {
    if (currentStep <= 1) return;
    if (currentStep === 10) {
      setCurrentStep(9);
      return;
    }
    if (currentStep === 7 && !data.servicesOffered.includes('HOSPEDAJE')) {
      setCurrentStep(5);
    } else {
      setCurrentStep((s) => s - 1);
    }
  }, [currentStep, data.servicesOffered]);

  const handleSubmit = useCallback(async () => {
    const paseoOnly = data.servicesOffered.length === 1 && data.servicesOffered.includes('PASEO');
    const minPhotos = paseoOnly ? 2 : 4;
    const maxPhotos = paseoOnly ? 4 : 6;
    if (data.photoUrls.length < minPhotos || data.photoUrls.length > maxPhotos) {
      toast.error(paseoOnly
        ? `Sube entre 2 y 4 fotos personales (con mascotas)`
        : `Sube entre 4 y 6 fotos del espacio`);
      return;
    }
    if (!data.termsAccepted || !data.privacyAccepted || !data.verificationAccepted) {
      toast.error('Acepta términos, privacidad y verificación');
      return;
    }
    setIsSubmitting(true);
    try {
      if (retryMode) {
        const bio = [data.bioSummary, data.bioDetail].filter(Boolean).join(' ').slice(0, 500);
        await patchProfile({
          bio: bio || undefined,
          bioDetail: data.bioDetail || undefined,
          zone: data.zone || undefined,
          spaceType: Array.isArray(data.spaceType) && data.spaceType.length > 0 ? data.spaceType : undefined,
          spaceDescription: data.spaceDescription || undefined,
          servicesOffered: data.servicesOffered,
          pricePerDay: data.pricePerDay || undefined,
          pricePerWalk30: data.pricePerWalk30 || undefined,
          pricePerWalk60: data.pricePerWalk60 || undefined,
          termsAccepted: data.termsAccepted,
          privacyAccepted: data.privacyAccepted,
          verificationAccepted: data.verificationAccepted,
          photos: data.photoUrls,
        });
        clearDraft();
        toast.success('Cambios guardados. Si tu perfil está completo, se enviará automáticamente a revisión.');
        navigate('/caregiver/dashboard');
      } else {
        const payload = buildRegisterPayload(data);
        await registerCaregiver(payload);
        clearDraft();
        toast.success('¡Cuenta creada! Completa los pasos para enviar tu solicitud.');
        navigate('/caregiver/onboarding');
      }
    } catch (e: any) {
      setFieldErrors({});

      // 400 – validación fallida: mostrar mensaje por campo y navegar al primer error
      if (e?.statusCode === 400 && Array.isArray(e?.errors) && e.errors.length > 0) {
        const errors = e.errors as { field: string; message: string }[];
        errors.forEach((err) => toast.error(err.message));
        const firstStep = stepForField(errors[0].field);
        setCurrentStep(firstStep);
        return;
      }

      // 409 Conflict (email o teléfono duplicado)
      if (e?.statusCode === 409 || e?.response?.status === 409) {
        const field = e?.field || e?.response?.data?.error?.field;
        const code = e?.code || e?.response?.data?.error?.code;
        if (field === 'email' || code === 'EMAIL_EXISTS') {
          toast.error('Este correo electrónico ya está registrado. Usa otro o inicia sesión.');
          setFieldErrors({ email: 'Este correo ya está en uso' });
          setCurrentStep(2);
        } else if (field === 'phone' || code === 'PHONE_EXISTS') {
          toast.error('Este número de teléfono ya está registrado. Usa otro o inicia sesión.');
          setFieldErrors({ phone: 'Este número ya está registrado' });
          setCurrentStep(1);
        } else {
          toast.error(e?.message || 'Ya existe una cuenta con estos datos. Usa otros datos o inicia sesión.');
        }
        return;
      }

      toast.error(e instanceof Error ? e.message : 'Error al enviar. Intenta más tarde.');
    } finally {
      setIsSubmitting(false);
    }
  }, [data, navigate, retryMode]);

  if (isCaregiver && !caregiverCheckDone) {
    return <div className="min-h-screen bg-gray-50 dark:bg-gray-900 flex items-center justify-center text-gray-500">Cargando…</div>;
  }

  if (isCaregiver && caregiverCheckDone && !retryMode) {
    return null;
  }



  const progress = (currentStep / TOTAL_STEPS) * 100;

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900">
      <header className="sticky top-0 z-10 border-b border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3">
        <div className="mx-auto max-w-2xl flex items-center justify-between">
          <span className="text-sm font-medium text-gray-600 dark:text-gray-400">
            Paso {currentStep} de {TOTAL_STEPS}
          </span>
          <button
            type="button"
            onClick={() => setShowExitModal(true)}
            className="text-sm text-gray-500 hover:text-gray-700 dark:hover:text-gray-300"
          >
            Guardar y salir
          </button>
        </div>
        <div className="mt-2 h-2 bg-gray-200 dark:bg-gray-700 rounded-full overflow-hidden" role="progressbar" aria-valuenow={currentStep} aria-valuemin={1} aria-valuemax={TOTAL_STEPS} aria-label={`Paso ${currentStep} de ${TOTAL_STEPS}`}>
          <div className="h-full bg-green-500 rounded-full transition-all duration-500" style={{ width: `${progress}%` }} />
        </div>
      </header>

      <main className="mx-auto max-w-2xl px-4 py-6 pb-24">
        {currentStep === 1 && <Step1 data={data} setData={setData} onNext={goNext} fieldError={fieldErrors.phone} onFieldErrorClear={() => setFieldErrors((prev) => ({ ...prev, phone: undefined }))} />}
        {currentStep === 2 && <Step2 data={data} setData={setData} onNext={goNext} onPrev={goPrev} fieldError={fieldErrors.email} onFieldErrorClear={() => setFieldErrors((prev) => ({ ...prev, email: undefined }))} />}
        {currentStep === 3 && <Step3 data={data} setData={setData} onNext={goNext} onPrev={goPrev} />}
        {currentStep === 4 && <Step4 data={data} setData={setData} onNext={goNext} onPrev={goPrev} />}
        {currentStep === 5 && <Step5 data={data} setData={setData} onNext={goNext} onPrev={goPrev} />}
        {currentStep === 6 && <Step6 data={data} setData={setData} onNext={goNext} onPrev={goPrev} />}
        {currentStep === 7 && <Step7 data={data} setData={setData} onNext={goNext} onPrev={goPrev} />}
        {currentStep === 8 && <Step8 data={data} setData={setData} onNext={goNext} onPrev={goPrev} />}
        {currentStep === 9 && <Step9 data={data} setData={setData} onNext={goNext} onPrev={goPrev} />}
        {currentStep === 10 && <Step10Review data={data} setData={setData} onSubmit={handleSubmit} onPrev={goPrev} isSubmitting={isSubmitting} />}
      </main>

      {showExitModal && (
        <div className="fixed inset-0 z-20 flex items-center justify-center bg-black/50 p-4">
          <div className="rounded-2xl bg-white dark:bg-gray-800 p-6 max-w-sm w-full shadow-xl">
            <p className="text-gray-900 dark:text-white font-medium">¿Guardar y salir?</p>
            <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">Podrás continuar después desde donde lo dejaste.</p>
            <div className="mt-4 flex gap-3">
              <button type="button" onClick={() => setShowExitModal(false)} className="flex-1 py-2 rounded-xl border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300">Cancelar</button>
              <button type="button" onClick={() => { clearDraft(); navigate('/'); }} className="flex-1 py-2 rounded-xl bg-green-600 text-white font-medium">Salir</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function getStepValues(step: number, data: WizardData): unknown {
  switch (step) {
    case 1: return { firstName: data.firstName, lastName: data.lastName, phone: data.phone, dateOfBirth: data.dateOfBirth };
    case 2: return { email: data.email, password: data.password, confirmPassword: data.confirmPassword };
    case 3: return { zone: data.zone };
    case 4: return { servicesOffered: data.servicesOffered };
    case 5: return { bioSummary: data.bioSummary, bioDetail: data.bioDetail };
    case 6: return { spaceType: data.spaceType, spaceDescription: data.spaceDescription };
    case 7: return { pricePerDay: data.pricePerDay, pricePerWalk30: data.pricePerWalk30, pricePerWalk60: data.pricePerWalk60 };
    case 8: return { photoUrls: data.photoUrls };
    case 9: return { termsAccepted: data.termsAccepted, privacyAccepted: data.privacyAccepted, verificationAccepted: data.verificationAccepted };
    default: return {};
  }
}

function buildRegisterPayload(data: WizardData): RegisterCaregiverPayload {
  const bio = [data.bioSummary, data.bioDetail].filter(Boolean).join(' ').slice(0, 500);
  const phone = data.phone.replace(/\D/g, '').replace(/^591/, '');
  return {
    user: {
      email: data.email,
      password: data.password,
      firstName: data.firstName,
      lastName: data.lastName,
      phone,
      dateOfBirth: data.dateOfBirth,
      country: 'Bolivia',
      city: 'Santa Cruz',
      isOver18: true,
    },
    profile: {
      servicesOffered: data.servicesOffered,
      photos: data.photoUrls,
      zone: data.zone || undefined,
      bio: bio || undefined,
      spaceType: Array.isArray(data.spaceType) && data.spaceType.length > 0 ? data.spaceType : undefined,
      pricePerDay: data.pricePerDay || undefined,
      pricePerWalk30: data.pricePerWalk30 || undefined,
      pricePerWalk60: data.pricePerWalk60 || undefined,
    },
  };
}

function Step1({ data, setData, onNext, fieldError, onFieldErrorClear }: { data: WizardData; setData: (d: React.SetStateAction<WizardData>) => void; onNext: () => void; fieldError?: string; onFieldErrorClear: () => void }) {
  return (
    <div className="space-y-6">
      <h2 className="text-lg font-semibold text-gray-900 dark:text-white">Tu nombre, teléfono y fecha de nacimiento</h2>
      <p className="text-sm text-gray-500 dark:text-gray-400">Para que los dueños puedan contactarte. Debes tener al menos 18 años.</p>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Nombre *</label>
          <input type="text" value={data.firstName} onChange={(e) => setData((d) => ({ ...d, firstName: e.target.value }))} placeholder="Tu nombre" className="block w-full rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white px-4 py-2.5 text-base sm:text-sm" />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Apellido *</label>
          <input type="text" value={data.lastName} onChange={(e) => setData((d) => ({ ...d, lastName: e.target.value }))} placeholder="Tu apellido" className="block w-full rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white px-4 py-2.5 text-base sm:text-sm" />
        </div>
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Teléfono (WhatsApp) *</label>
        <input
          type="tel"
          value={data.phone}
          onChange={(e) => {
            setData((d) => ({ ...d, phone: e.target.value }));
            if (fieldError) onFieldErrorClear();
          }}
          placeholder="71234567 (8 dígitos, empieza con 6 o 7)"
          maxLength={8}
          className={`block w-full rounded-xl border ${fieldError
            ? 'border-red-500 dark:border-red-500 focus:ring-red-500 focus:border-red-500'
            : 'border-gray-300 dark:border-gray-600'
            } bg-white dark:bg-gray-700 text-gray-900 dark:text-white px-4 py-2.5 text-base sm:text-sm`}
        />
        {fieldError && (
          <p className="mt-1 text-sm text-red-600 dark:text-red-400 flex items-center gap-1">
            <span>⚠️</span>
            <span>{fieldError}</span>
          </p>
        )}
        <p className="mt-1 text-xs text-gray-500">8 dígitos, debe empezar con 6 o 7 (sin +591)</p>
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Fecha de nacimiento *</label>
        <input
          type="date"
          value={data.dateOfBirth}
          onChange={(e) => setData((d) => ({ ...d, dateOfBirth: e.target.value }))}
          max={new Date(new Date().setFullYear(new Date().getFullYear() - 18)).toISOString().slice(0, 10)}
          className="block w-full rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white px-4 py-2.5 text-base sm:text-sm"
        />
        <p className="mt-1 text-xs text-gray-500">Debes tener al menos 18 años</p>
      </div>
      <div className="flex justify-end">
        <button type="button" onClick={onNext} className="rounded-xl bg-green-600 hover:bg-green-700 text-white font-semibold px-5 py-2.5">Siguiente →</button>
      </div>
    </div>
  );
}

function Step2({ data, setData, onNext, onPrev, fieldError, onFieldErrorClear }: { data: WizardData; setData: (d: React.SetStateAction<WizardData>) => void; onNext: () => void; onPrev: () => void; fieldError?: string; onFieldErrorClear: () => void }) {
  return (
    <div className="space-y-6">
      <h2 className="text-lg font-semibold text-gray-900 dark:text-white">Tu cuenta GARDEN</h2>
      <p className="text-sm text-gray-500 dark:text-gray-400">Con estos datos iniciarás sesión y gestionarás tu perfil.</p>
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Email *</label>
        <input
          type="email"
          value={data.email}
          onChange={(e) => {
            setData((d) => ({ ...d, email: e.target.value }));
            // Limpiar error cuando el usuario empieza a escribir
            if (fieldError) onFieldErrorClear();
          }}
          placeholder="tucorreo@email.com"
          className={`block w-full rounded-xl border ${fieldError
            ? 'border-red-500 dark:border-red-500 focus:ring-red-500 focus:border-red-500'
            : 'border-gray-300 dark:border-gray-600'
            } bg-white dark:bg-gray-700 text-gray-900 dark:text-white px-4 py-2.5 text-base sm:text-sm`}
        />
        {fieldError && (
          <p className="mt-1 text-sm text-red-600 dark:text-red-400 flex items-center gap-1">
            <span>⚠️</span>
            <span>{fieldError}</span>
          </p>
        )}
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Contraseña *</label>
        <input type="password" value={data.password} onChange={(e) => setData((d) => ({ ...d, password: e.target.value }))} placeholder="Mínimo 8 caracteres" className="block w-full rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white px-4 py-2.5 text-base sm:text-sm" />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Repetir contraseña *</label>
        <input type="password" value={data.confirmPassword} onChange={(e) => setData((d) => ({ ...d, confirmPassword: e.target.value }))} placeholder="Repite tu contraseña" className="block w-full rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white px-4 py-2.5 text-base sm:text-sm" />
      </div>
      <div className="flex justify-between">
        <button type="button" onClick={onPrev} className="rounded-xl border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 px-5 py-2.5">← Atrás</button>
        <button type="button" onClick={onNext} className="rounded-xl bg-green-600 hover:bg-green-700 text-white font-semibold px-5 py-2.5">Siguiente →</button>
      </div>
    </div>
  );
}

function Step3({ data, setData, onNext, onPrev }: { data: WizardData; setData: (d: React.SetStateAction<WizardData>) => void; onNext: () => void; onPrev: () => void }) {
  return (
    <div className="space-y-6">
      <h2 className="text-lg font-semibold text-gray-900 dark:text-white">¿En qué zona de Santa Cruz vives?</h2>
      <p className="text-sm text-gray-500 dark:text-gray-400">Los dueños buscan cuidadores cerca.</p>
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
        {(ZONES as readonly Zone[]).map((z) => (
          <button key={z} type="button" onClick={() => setData((d) => ({ ...d, zone: z }))} className={`rounded-xl border-2 p-3 text-left text-sm font-medium transition-colors ${data.zone === z ? 'border-green-500 bg-green-50 dark:bg-green-900/20 text-green-800 dark:text-green-200' : 'border-gray-200 dark:border-gray-600 text-gray-700 dark:text-gray-300 hover:border-gray-300'}`}>
            {ZONE_LABELS[z]}
          </button>
        ))}
      </div>
      <div className="flex justify-between">
        <button type="button" onClick={onPrev} className="rounded-xl border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 px-5 py-2.5">← Atrás</button>
        <button type="button" onClick={onNext} className="rounded-xl bg-green-600 hover:bg-green-700 text-white font-semibold px-5 py-2.5">Siguiente →</button>
      </div>
    </div>
  );
}

function Step4({ data, setData, onNext, onPrev }: { data: WizardData; setData: (d: React.SetStateAction<WizardData>) => void; onNext: () => void; onPrev: () => void }) {
  const toggle = (s: 'HOSPEDAJE' | 'PASEO') => {
    const next = data.servicesOffered.includes(s) ? data.servicesOffered.filter((x) => x !== s) : [...data.servicesOffered, s];
    setData((d) => ({ ...d, servicesOffered: next }));
  };
  return (
    <div className="space-y-6">
      <h2 className="text-lg font-semibold text-gray-900 dark:text-white">¿Qué servicios quieres ofrecer?</h2>
      <p className="text-sm text-gray-500 dark:text-gray-400">Puedes elegir uno o ambos.</p>
      <div className="space-y-3">
        <button type="button" onClick={() => toggle('HOSPEDAJE')} className={`w-full rounded-xl border-2 p-4 text-left ${data.servicesOffered.includes('HOSPEDAJE') ? 'border-green-500 bg-green-50 dark:bg-green-900/20' : 'border-gray-200 dark:border-gray-600'}`}>
          <span className="font-medium text-gray-900 dark:text-white">🏠 Hospedaje</span>
          <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">Cuida mascotas en tu hogar. Precio típico: Bs 80-160/día</p>
        </button>
        <button type="button" onClick={() => toggle('PASEO')} className={`w-full rounded-xl border-2 p-4 text-left ${data.servicesOffered.includes('PASEO') ? 'border-green-500 bg-green-50 dark:bg-green-900/20' : 'border-gray-200 dark:border-gray-600'}`}>
          <span className="font-medium text-gray-900 dark:text-white">🦮 Paseos</span>
          <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">Pasea perros en tu zona. Bs 25-60/sesión</p>
        </button>
      </div>
      <div className="flex justify-between">
        <button type="button" onClick={onPrev} className="rounded-xl border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 px-5 py-2.5">← Atrás</button>
        <button type="button" onClick={onNext} className="rounded-xl bg-green-600 hover:bg-green-700 text-white font-semibold px-5 py-2.5">Siguiente →</button>
      </div>
    </div>
  );
}

function Step5({ data, setData, onNext, onPrev }: { data: WizardData; setData: (d: React.SetStateAction<WizardData>) => void; onNext: () => void; onPrev: () => void }) {
  return (
    <div className="space-y-6">
      <h2 className="text-lg font-semibold text-gray-900 dark:text-white">Cuéntanos sobre tu experiencia</h2>
      <p className="text-sm text-gray-500 dark:text-gray-400">Los dueños valoran saber que su mascota estará con alguien experimentado.</p>
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Resumen (50-500 caracteres) *</label>
        <textarea value={data.bioSummary} onChange={(e) => setData((d) => ({ ...d, bioSummary: e.target.value }))} rows={4} placeholder="Ej: Tengo 2 labradores, cuido mascotas hace 3 años..." className="block w-full rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white px-4 py-2.5 text-base sm:text-sm" />
        <p className="mt-1 text-xs text-gray-400">{data.bioSummary.length}/500</p>
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Amplía (opcional)</label>
        <textarea value={data.bioDetail} onChange={(e) => setData((d) => ({ ...d, bioDetail: e.target.value }))} rows={2} placeholder="Ej: Curso de primeros auxilios caninos..." className="block w-full rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white px-4 py-2.5 text-base sm:text-sm" />
      </div>
      <div className="flex justify-between">
        <button type="button" onClick={onPrev} className="rounded-xl border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 px-5 py-2.5">← Atrás</button>
        <button type="button" onClick={onNext} className="rounded-xl bg-green-600 hover:bg-green-700 text-white font-semibold px-5 py-2.5">Siguiente →</button>
      </div>
    </div>
  );
}

function Step6({ data, setData, onNext, onPrev }: { data: WizardData; setData: (d: React.SetStateAction<WizardData>) => void; onNext: () => void; onPrev: () => void }) {
  // Solo mostrar si el cuidador ofrece Hospedaje o Ambos
  if (!data.servicesOffered.includes('HOSPEDAJE')) {
    return null;
  }

  const SPACE_TYPE_OPTIONS = ['Casa con patio', 'Casa sin patio', 'Departamento pequeño', 'Departamento amplio'] as const;

  const toggleSpaceType = (option: string) => {
    const current = Array.isArray(data.spaceType) ? data.spaceType : [];
    const next = current.includes(option)
      ? current.filter((s) => s !== option)
      : [...current, option];
    setData((d) => ({ ...d, spaceType: next }));
  };

  return (
    <div className="space-y-6">
      <h2 className="text-lg font-semibold text-gray-900 dark:text-white">Tipo de espacio</h2>
      <p className="text-sm text-gray-500 dark:text-gray-400">Selecciona todos los tipos de espacio que ofreces (puedes elegir varios).</p>
      <div className="space-y-3">
        {SPACE_TYPE_OPTIONS.map((option) => {
          const isSelected = Array.isArray(data.spaceType) && data.spaceType.includes(option);
          return (
            <label
              key={option}
              className={`flex cursor-pointer items-center gap-3 rounded-xl border-2 p-4 transition-colors ${isSelected
                ? 'border-green-500 bg-green-50 dark:bg-green-900/20'
                : 'border-gray-200 dark:border-gray-600 hover:border-gray-300 dark:hover:border-gray-500'
                }`}
            >
              <input
                type="checkbox"
                checked={isSelected}
                onChange={() => toggleSpaceType(option)}
                className="h-5 w-5 rounded border-gray-300 text-green-600 focus:ring-2 focus:ring-green-500 focus:ring-offset-2"
              />
              <span className={`text-sm font-medium ${isSelected ? 'text-green-800 dark:text-green-200' : 'text-gray-700 dark:text-gray-300'}`}>
                {option}
              </span>
            </label>
          );
        })}
      </div>
      {Array.isArray(data.spaceType) && data.spaceType.length === 0 && (
        <p className="text-sm text-red-600 dark:text-red-400">Elige al menos un tipo de espacio</p>
      )}
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Descripción adicional (opcional)</label>
        <textarea
          value={data.spaceDescription}
          onChange={(e) => setData((d) => ({ ...d, spaceDescription: e.target.value }))}
          rows={2}
          placeholder="Ej: Patio amplio con césped, área cerrada..."
          className="block w-full rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white px-4 py-2.5 text-base sm:text-sm"
        />
      </div>
      <div className="flex justify-between">
        <button type="button" onClick={onPrev} className="rounded-xl border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 px-5 py-2.5">← Atrás</button>
        <button
          type="button"
          onClick={onNext}
          disabled={!Array.isArray(data.spaceType) || data.spaceType.length === 0}
          className="rounded-xl bg-green-600 hover:bg-green-700 text-white font-semibold px-5 py-2.5 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Siguiente →
        </button>
      </div>
    </div>
  );
}

function Step7({ data, setData, onNext, onPrev }: { data: WizardData; setData: (d: React.SetStateAction<WizardData>) => void; onNext: () => void; onPrev: () => void }) {
  return (
    <div className="space-y-6">
      <h2 className="text-lg font-semibold text-gray-900 dark:text-white">Define tus tarifas (Bs)</h2>
      <p className="text-sm text-gray-500 dark:text-gray-400">Puedes ajustarlas después desde tu panel.</p>
      {data.servicesOffered.includes('HOSPEDAJE') && (
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Precio por día (Hospedaje)</label>
          <input type="number" min={0} value={data.pricePerDay || ''} onChange={(e) => setData((d) => ({ ...d, pricePerDay: e.target.value ? Number(e.target.value) : 0 }))} placeholder="120" className="block w-full rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white px-4 py-2.5 text-base sm:text-sm" />
        </div>
      )}
      {data.servicesOffered.includes('PASEO') && (
        <>
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Paseo 30 min (Bs)</label>
            <input type="number" min={0} value={data.pricePerWalk30 || ''} onChange={(e) => setData((d) => ({ ...d, pricePerWalk30: e.target.value ? Number(e.target.value) : 0 }))} placeholder="30" className="block w-full rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white px-4 py-2.5 text-base sm:text-sm" />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Paseo 1 hora (Bs)</label>
            <input type="number" min={0} value={data.pricePerWalk60 || ''} onChange={(e) => setData((d) => ({ ...d, pricePerWalk60: e.target.value ? Number(e.target.value) : 0 }))} placeholder="50" className="block w-full rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white px-4 py-2.5 text-base sm:text-sm" />
          </div>
        </>
      )}
      <div className="flex justify-between">
        <button type="button" onClick={onPrev} className="rounded-xl border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 px-5 py-2.5">← Atrás</button>
        <button type="button" onClick={onNext} className="rounded-xl bg-green-600 hover:bg-green-700 text-white font-semibold px-5 py-2.5">Siguiente →</button>
      </div>
    </div>
  );
}

function Step8({ data, setData, onNext, onPrev }: { data: WizardData; setData: (d: React.SetStateAction<WizardData>) => void; onNext: (override?: Partial<WizardData>) => void; onPrev: () => void }) {
  const [files, setFiles] = useState<File[]>([]);
  const [previews, setPreviews] = useState<string[]>([]);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onlyPaseo = data.servicesOffered.length === 1 && data.servicesOffered.includes('PASEO');
  const minPhotos = onlyPaseo ? 2 : 4;
  const maxPhotos = onlyPaseo ? 4 : 6;
  const title = onlyPaseo ? 'Fotos de tu perfil y trabajo' : 'Fotos de tu perfil y espacio';
  const hint = onlyPaseo
    ? `Sube entre ${minPhotos} y ${maxPhotos} fotos tuyas y trabajando con mascotas. JPG/PNG, 5MB cada una.`
    : `Sube entre ${minPhotos} y ${maxPhotos} fotos de tu perfil y el espacio donde hospedas. JPG/PNG, 5MB cada una.`;

  useEffect(() => {
    const newPreviews = files.map(f => URL.createObjectURL(f));
    setPreviews(newPreviews);
    return () => newPreviews.forEach(p => URL.revokeObjectURL(p));
  }, [files]);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const list = e.target.files ? Array.from(e.target.files) : [];
    const allowedTypes = ['image/jpeg', 'image/png'];
    const invalidType = list.find((f) => !allowedTypes.includes(f.type));

    if (invalidType) {
      setError('Solo se permiten imágenes JPG o PNG');
      return;
    }

    const valid = list.filter((f) => f.size <= 5 * 1024 * 1024);
    const tooLarge = list.find((f) => f.size > 5 * 1024 * 1024);

    if (tooLarge) {
      setError('Cada foto debe ser menor a 5MB');
      return;
    }

    if (files.length + valid.length + data.photoUrls.length > maxPhotos) {
      setError(`Máximo ${maxPhotos} fotos en total`);
      return;
    }

    setFiles((prev) => [...prev, ...valid]);
    setError(null);
  };

  const removeFile = (index: number) => {
    setFiles(prev => prev.filter((_, i) => i !== index));
  };

  const uploadAndNext = async () => {
    // Total count = already existing (minus deleted ones) + new ones
    const totalCount = data.photoUrls.length + files.length;

    if (totalCount < minPhotos || totalCount > maxPhotos) {
      setError(`Debes subir entre ${minPhotos} y ${maxPhotos} fotos. Tienes ${totalCount}.`);
      return;
    }

    setUploading(true);
    setError(null);
    try {
      let finalUrls = [...data.photoUrls];
      if (files.length > 0) {
        const newUrls = await uploadRegistrationPhotos(files);
        finalUrls = [...finalUrls, ...newUrls];
      }
      setData((d) => ({ ...d, photoUrls: finalUrls }));
      onNext({ photoUrls: finalUrls });
    } catch (e: any) {
      setError(e?.response?.data?.error?.message ?? e?.message ?? 'Error al subir fotos');
    } finally {
      setUploading(false);
    }
  };

  const canSkipUpload = data.photoUrls.length >= minPhotos && data.photoUrls.length <= maxPhotos && files.length === 0;

  return (
    <div className="space-y-6">
      <h2 className="text-lg font-semibold text-gray-900 dark:text-white">{title}</h2>
      <p className="text-sm text-gray-500 dark:text-gray-400">{hint}</p>

      {data.photoUrls.length > 0 && (
        <div className="space-y-2">
          <p className="text-xs font-medium text-gray-400 uppercase tracking-wider">Fotos ya subidas ({data.photoUrls.length})</p>
          <div className="flex gap-2 overflow-x-auto pb-2 scrollbar-thin scrollbar-thumb-gray-300">
            {data.photoUrls.map((url, i) => (
              <div key={i} className="relative h-16 w-24 shrink-0 rounded border border-gray-200 dark:border-gray-700 overflow-hidden bg-gray-100">
                <img src={getImageUrl(url)} className="w-full h-full object-cover opacity-60" alt="" />
                <button
                  type="button"
                  onClick={() => setData(prev => ({ ...prev, photoUrls: prev.photoUrls.filter((_, idx) => idx !== i) }))}
                  className="absolute top-0 right-0 bg-red-500 text-white p-0.5 rounded-bl hover:bg-red-600"
                >
                  <span className="text-[8px]">✕</span>
                </button>
              </div>
            ))}
          </div>
          {files.length > 0 && <p className="text-xs text-green-600 font-medium italic">✨ Las nuevas fotos se añadirán a las existentes.</p>}
        </div>
      )}

      <div className="space-y-4">
        <label className="block w-full cursor-pointer rounded-xl border-2 border-dashed border-gray-300 dark:border-gray-600 p-6 text-center hover:border-green-500 transition-colors">
          <input type="file" accept="image/jpeg,image/png" multiple onChange={handleFileChange} className="hidden" />
          <div className="space-y-1">
            <span className="text-2xl">📸</span>
            <p className="text-sm font-medium text-gray-700 dark:text-gray-300">
              {data.photoUrls.length > 0 ? 'Subir nuevas fotos' : 'Haz clic para subir fotos'}
            </p>
            <p className="text-xs text-gray-500">O arrastra y suelta aquí</p>
          </div>
        </label>

        {previews.length > 0 && (
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
            {previews.map((src, i) => (
              <div key={i} className="relative aspect-square rounded-lg overflow-hidden border border-gray-200 dark:border-gray-700 group">
                <img src={src} className="w-full h-full object-cover" alt={`Preview ${i + 1}`} />
                <button
                  type="button"
                  onClick={() => removeFile(i)}
                  className="absolute top-1 right-1 bg-red-600 text-white rounded-full p-1 opacity-0 group-hover:opacity-100 transition-opacity"
                  title="Quitar foto"
                >
                  <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
            ))}
          </div>
        )}

        <p className="text-sm text-gray-500">{files.length}/{maxPhotos} fotos seleccionadas</p>
      </div>
      {error && <p className="text-sm text-red-600 dark:text-red-400" role="alert">{error}</p>}
      <div className="flex justify-between">
        <button type="button" onClick={onPrev} className="rounded-xl border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 px-5 py-2.5">← Atrás</button>
        <button
          type="button"
          onClick={() => canSkipUpload ? onNext() : uploadAndNext()}
          disabled={uploading || (!canSkipUpload && files.length < minPhotos)}
          className="rounded-xl bg-green-600 hover:bg-green-700 disabled:opacity-50 text-white font-semibold px-5 py-2.5"
        >
          {uploading ? 'Subiendo…' : (canSkipUpload ? 'Siguiente →' : 'Subir y seguir →')}
        </button>
      </div>
    </div>
  );
}

function Step9({ data, setData, onNext, onPrev }: { data: WizardData; setData: (d: React.SetStateAction<WizardData>) => void; onNext: () => void; onPrev: () => void }) {
  return (
    <div className="space-y-6">
      <h2 className="text-lg font-semibold text-gray-900 dark:text-white">Términos y condiciones</h2>
      <p className="text-sm text-gray-500 dark:text-gray-400">Lee y acepta para continuar.</p>
      <div className="space-y-3">
        <label className="flex items-start gap-3 cursor-pointer">
          <input type="checkbox" checked={data.termsAccepted} onChange={(e) => setData((d) => ({ ...d, termsAccepted: e.target.checked }))} className="mt-1 rounded border-gray-300 text-green-600 focus:ring-green-500" />
          <span className="text-sm text-gray-700 dark:text-gray-300">Acepto los Términos de servicio *</span>
        </label>
        <label className="flex items-start gap-3 cursor-pointer">
          <input type="checkbox" checked={data.privacyAccepted} onChange={(e) => setData((d) => ({ ...d, privacyAccepted: e.target.checked }))} className="mt-1 rounded border-gray-300 text-green-600 focus:ring-green-500" />
          <span className="text-sm text-gray-700 dark:text-gray-300">Acepto la Política de privacidad *</span>
        </label>
        <label className="flex items-start gap-3 cursor-pointer">
          <input type="checkbox" checked={data.verificationAccepted} onChange={(e) => setData((d) => ({ ...d, verificationAccepted: e.target.checked }))} className="mt-1 rounded border-gray-300 text-green-600 focus:ring-green-500" />
          <span className="text-sm text-gray-700 dark:text-gray-300">Acepto que GARDEN verifique mi identidad *</span>
        </label>
      </div>
      <div className="flex justify-between">
        <button type="button" onClick={onPrev} className="rounded-xl border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 px-5 py-2.5">← Atrás</button>
        <button type="button" onClick={onNext} className="rounded-xl bg-green-600 hover:bg-green-700 text-white font-semibold px-5 py-2.5">Siguiente →</button>
      </div>
    </div>
  );
}

function Step10Review({ data, onSubmit, onPrev, isSubmitting }: { data: WizardData; setData: (d: React.SetStateAction<WizardData>) => void; onSubmit: () => void; onPrev: () => void; isSubmitting: boolean }) {
  return (
    <div className="space-y-6">
      <h2 className="text-lg font-semibold text-gray-900 dark:text-white">Revisa tu información</h2>
      <p className="text-sm text-gray-500 dark:text-gray-400">Verifica que todo esté correcto antes de enviar.</p>
      <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-4 space-y-3 text-sm">
        <p><span className="text-gray-500 dark:text-gray-400">Nombre:</span> {data.firstName} {data.lastName}</p>
        <p><span className="text-gray-500 dark:text-gray-400">Teléfono:</span> {data.phone}</p>
        <p><span className="text-gray-500 dark:text-gray-400">Fecha nacimiento:</span> {data.dateOfBirth || '-'}</p>
        <p><span className="text-gray-500 dark:text-gray-400">Email:</span> {data.email}</p>
        <p><span className="text-gray-500 dark:text-gray-400">Zona:</span> {data.zone ? ZONE_LABELS[data.zone as Zone] : '-'}</p>
        <p><span className="text-gray-500 dark:text-gray-400">Servicios:</span> {data.servicesOffered.join(', ') || '-'}</p>
        <p><span className="text-gray-500 dark:text-gray-400">Descripción:</span> {data.bioSummary.slice(0, 80)}…</p>
        <p><span className="text-gray-500 dark:text-gray-400">Fotos:</span> {data.photoUrls.length} subidas</p>
        <div className="grid grid-cols-4 sm:grid-cols-6 gap-2 mt-2">
          {data.photoUrls.map((url, i) => (
            <div key={i} className="aspect-square rounded border border-gray-200 dark:border-gray-700 overflow-hidden bg-gray-100">
              <img src={getImageUrl(url)} className="w-full h-full object-cover" alt={`Espacio ${i + 1}`} onError={(e) => { (e.target as HTMLImageElement).src = 'https://placehold.co/400x300/EEEEEE/999999/png?text=Sin+foto'; }} />
            </div>
          ))}
        </div>
      </div>
      <p className="text-xs text-gray-500 dark:text-gray-400">Tu perfil será revisado por el equipo GARDEN en 24-48 horas.</p>
      <div className="flex justify-between">
        <button type="button" onClick={onPrev} className="rounded-xl border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 px-5 py-2.5">← Atrás</button>
        <button type="button" onClick={onSubmit} disabled={isSubmitting} className="rounded-xl bg-green-600 hover:bg-green-700 disabled:opacity-50 text-white font-semibold px-5 py-2.5">{isSubmitting ? 'Enviando…' : 'Enviar solicitud →'}</button>
      </div>
    </div>
  );
}
