import { useState, useRef, useEffect } from 'react';
import { uploadProfilePhoto, patchProfile, patchUserInfo, sendVerifyEmail } from '@/api/caregiverProfile';
import { getImageUrl } from '@/utils/images';
import toast from 'react-hot-toast';
import { IdentityVerificationCard } from './IdentityVerificationCard';
import { VerifyEmailModal } from './VerifyEmailModal';

// Only email and phone are editable — name is locked after identity verification
interface LocalUser {
  firstName: string;
  lastName: string;
  email: string;
  phone: string;
}

export function PersonalInfoSection({
  profile,
  user,
  onUpdate,
}: {
  profile: any;
  user: { firstName: string; lastName: string; email: string };
  onUpdate: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [uploadingPhoto, setUploadingPhoto] = useState(false);
  const [saving, setSaving] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const profileStatus = profile?.profileStatus ?? '';
  const isLocked = profileStatus === 'SUBMITTED' || profileStatus === 'UNDER_REVIEW';
  const emailVerified = Boolean(profile?.emailVerified);
  const identityVerified = profile?.identityVerificationStatus === 'VERIFIED';

  const [showVerifyModal, setShowVerifyModal] = useState(false);

  const handleSendVerifyCode = async () => {
    try {
      const res = await sendVerifyEmail();
      if (res.success) {
        setShowVerifyModal(true);
      }
    } catch (err: any) {
      toast.error('Error al enviar el código de verificación');
    }
  };

  const makeLocal = (): LocalUser => ({
    firstName: user.firstName,
    lastName: user.lastName,
    email: user.email,
    phone: profile?.user?.phone ?? '',
  });

  const [local, setLocal] = useState<LocalUser>(makeLocal);

  // Sync when props change and not editing
  useEffect(() => {
    if (!editing) setLocal(makeLocal());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user.email, profile?.user?.phone, editing]);

  const startEditing = () => {
    setLocal(makeLocal());
    setEditing(true);
  };

  /* ── Photo upload ─────────────────────────────────────── */
  const handlePhotoChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file?.type.startsWith('image/')) return;
    if (isLocked) {
      toast.error('No puedes editar mientras el perfil está en revisión');
      return;
    }
    setUploadingPhoto(true);
    try {
      const url = await uploadProfilePhoto(file);
      await patchProfile({ profilePhoto: url });
      toast.success('Foto actualizada');
      onUpdate();
    } catch (err: any) {
      toast.error(err?.response?.data?.error?.message ?? 'Error al subir la foto');
    } finally {
      setUploadingPhoto(false);
    }
  };

  /* ── Save email + phone ───────────────────────────────── */
  const handleSave = async () => {
    if (!local.email.trim() || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(local.email)) {
      toast.error('Ingresa un correo electrónico válido');
      return;
    }
    setSaving(true);
    try {
      const result = await patchUserInfo({
        firstName: !identityVerified ? local.firstName.trim() : undefined,
        lastName: !identityVerified ? local.lastName.trim() : undefined,
        email: local.email.trim().toLowerCase(),
        phone: local.phone.trim() || undefined,
      });
      if (result.emailChanged) {
        toast.success(
          'Datos actualizados. Tu correo cambió — debes verificarlo nuevamente.',
          { duration: 6000 }
        );
      } else {
        toast.success('Datos actualizados correctamente');
      }
      setEditing(false);
      onUpdate();
    } catch (err: any) {
      const d = err?.response?.data;
      const msg = d?.error?.message ?? d?.message ?? err?.message ?? 'Error al guardar';
      toast.error(msg);
    } finally {
      setSaving(false);
    }
  };

  /* ── Render ───────────────────────────────────────────── */
  return (
    <div className="space-y-6">

      {/* Header */}
      <div className="flex items-start justify-between">
        <h2 className="text-lg font-semibold text-gray-900 dark:text-white">Información personal</h2>
        {isLocked || profileStatus === 'APPROVED' ? (
          <span className={`text-xs font-medium px-2.5 py-1 rounded-full ${isLocked ? 'bg-amber-100 text-amber-700' : 'bg-green-100 text-green-700'}`}>
            {isLocked ? 'En revisión' : '✓ Aprobado'}
          </span>
        ) : !editing ? (
          <button
            type="button"
            onClick={startEditing}
            className={
              profile?.personalInfoComplete
                ? "text-sm font-medium text-green-600 dark:text-green-400 hover:underline"
                : "px-4 py-1.5 rounded-lg bg-red-600 text-white text-xs font-black uppercase tracking-tight shadow-md shadow-red-600/20 hover:bg-red-700 active:scale-95 transition-all animate-pulse"
            }
          >
            {profile?.personalInfoComplete ? 'Editar' : 'Completar'}
          </button>
        ) : (
          <div className="flex gap-3">
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

      {isLocked && (
        <p className="text-sm text-amber-700 dark:text-amber-300 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-xl px-4 py-3">
          Tu perfil está en revisión. No puedes editarlo hasta que el equipo GARDEN lo procese.
        </p>
      )}

      {/* Photo + info */}
      <div className="flex items-start gap-6">

        {/* Photo with hover-to-change */}
        <div className="flex-shrink-0">
          <div className="relative group">
            <img
              src={getImageUrl(profile?.profilePhoto ?? null)}
              alt="Foto de perfil"
              className="w-24 h-24 rounded-2xl object-cover border-2 border-gray-200 dark:border-gray-600"
            />
            {!isLocked && (
              <>
                <button
                  type="button"
                  onClick={() => fileInputRef.current?.click()}
                  disabled={uploadingPhoto}
                  className="absolute inset-0 rounded-2xl bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center text-white text-xs font-medium disabled:cursor-wait"
                >
                  {uploadingPhoto ? '…' : 'Cambiar'}
                </button>
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="image/*"
                  className="hidden"
                  onChange={handlePhotoChange}
                />
              </>
            )}
          </div>
        </div>

        {/* Fields */}
        <div className="flex-1 space-y-4">

          {!editing && (
            <div>
              <p className="text-base font-semibold text-gray-900 dark:text-white">
                {user.firstName} {user.lastName}
              </p>
              {identityVerified && (
                <span className="inline-flex items-center gap-1 text-xs text-green-600 dark:text-green-400 mt-0.5">
                  🔒 Nombre verificado por identidad
                </span>
              )}
            </div>
          )}

          {editing ? (
            /* ── Edit mode: name, email + phone ── */
            <>
              {!identityVerified && (
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">Nombre</label>
                    <input
                      type="text"
                      value={local.firstName}
                      onChange={(e) => setLocal((p) => ({ ...p, firstName: e.target.value }))}
                      className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3 py-2 text-sm focus:ring-2 focus:ring-green-500 outline-none"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">Apellido</label>
                    <input
                      type="text"
                      value={local.lastName}
                      onChange={(e) => setLocal((p) => ({ ...p, lastName: e.target.value }))}
                      className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3 py-2 text-sm focus:ring-2 focus:ring-green-500 outline-none"
                    />
                  </div>
                </div>
              )}

              {identityVerified && (
                <div>
                  <p className="text-sm font-semibold text-gray-900 dark:text-white">
                    {user.firstName} {user.lastName}
                  </p>
                  <p className="text-[10px] text-green-600 dark:text-green-400 font-medium">Nombre bloqueado (verificado)</p>
                </div>
              )}

              <div className="pt-2">
                <label className="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">
                  Correo electrónico
                  {!emailVerified && (
                    <span className="ml-1 text-amber-500">· sin verificar</span>
                  )}
                </label>
                <input
                  type="email"
                  value={local.email}
                  onChange={(e) => setLocal((p) => ({ ...p, email: e.target.value }))}
                  className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3 py-2 text-sm focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none"
                />
                {local.email.toLowerCase() !== user.email.toLowerCase() && (
                  <p className="text-xs text-amber-600 dark:text-amber-400 mt-1">
                    ⚠️ Si cambias el correo deberás verificarlo nuevamente antes de que tu perfil pueda enviarse.
                  </p>
                )}
              </div>

              <div>
                <label className="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">Teléfono</label>
                <input
                  type="tel"
                  value={local.phone}
                  onChange={(e) => setLocal((p) => ({ ...p, phone: e.target.value }))}
                  placeholder="+591 7XXXXXXX"
                  className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3 py-2 text-sm focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none"
                />
              </div>
            </>
          ) : (
            /* ── Read mode ── */
            <>
              <div className="flex items-center gap-3">
                <p className="text-sm text-gray-600 dark:text-gray-400 flex items-center gap-1.5 flex-wrap">
                  {user.email}
                  {emailVerified ? (
                    <span className="inline-flex items-center px-2 py-0.5 rounded-full bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400 text-xs font-medium">
                      ✓ verificado
                    </span>
                  ) : (
                    <span className="inline-flex items-center px-2 py-0.5 rounded-full bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400 text-xs font-medium">
                      sin verificar
                    </span>
                  )}
                </p>
                {!emailVerified && !isLocked && (
                  <button
                    type="button"
                    onClick={handleSendVerifyCode}
                    className="text-xs font-bold text-blue-600 dark:text-blue-400 hover:bg-blue-50 dark:hover:bg-blue-900/20 px-2 py-1 rounded-lg border border-blue-200 dark:border-blue-800 transition-colors"
                  >
                    Verificar ahora
                  </button>
                )}
              </div>
              <p className="text-sm text-gray-600 dark:text-gray-400">
                {profile?.user?.phone
                  ? `📞 ${profile.user.phone}`
                  : <span className="text-gray-400 dark:text-gray-500 italic text-sm">Sin teléfono registrado</span>
                }
              </p>
            </>
          )}
        </div>
      </div>

      {showVerifyModal && (
        <VerifyEmailModal
          email={user.email}
          onSuccess={onUpdate}
          onClose={() => setShowVerifyModal(false)}
        />
      )}

      {/* Identity card — only when NOT yet verified */}
      {!identityVerified && (
        <div className="pt-2">
          <IdentityVerificationCard
            status={profile?.identityVerificationStatus ?? 'PENDING'}
            caregiverId={profile?.id ?? ''}
            token={profile?.identityVerificationToken ?? null}
          />
        </div>
      )}
    </div>
  );
}
