import { useState } from 'react';
import { Link, useParams, useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { useQueryClient } from '@tanstack/react-query';
import {
  verifyCaregiverEmail,
  suspendCaregiver,
  activateCaregiver,
  deleteCaregiver,
} from '@/api/admin';
import { useCaregiverDetail } from '@/hooks/useCaregiverDetail';
import { ADMIN_CAREGIVERS_QUERY_KEY } from '@/hooks/useAdminCaregivers';
import { getImageUrl } from '@/utils/images';

function Section({
  title,
  children,
  className = '',
}: {
  title: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <section className={`rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm overflow-hidden ${className}`}>
      <h2 className="px-4 py-3 text-sm font-semibold text-gray-900 dark:text-white bg-gray-50 dark:bg-gray-700/50 border-b border-gray-200 dark:border-gray-700">
        {title}
      </h2>
      <div className="p-4 text-sm text-gray-700 dark:text-gray-300">{children}</div>
    </section>
  );
}

function Field({ label, value }: { label: string; value: React.ReactNode }) {
  if (value == null || value === '') return null;
  return (
    <div className="mb-3 last:mb-0">
      <span className="font-medium text-gray-500 dark:text-gray-400 block mb-0.5">{label}</span>
      <span className="text-gray-900 dark:text-gray-100">{value}</span>
    </div>
  );
}

function JsonBlock({ data, title }: { data: Record<string, unknown> | null; title?: string }) {
  if (!data || Object.keys(data).length === 0) return null;
  return (
    <div className="mt-2">
      {title && <span className="font-medium text-gray-500 dark:text-gray-400 block mb-1">{title}</span>}
      <pre className="text-xs bg-gray-100 dark:bg-gray-700 p-3 rounded-lg overflow-x-auto max-h-48 overflow-y-auto">
        {JSON.stringify(data, null, 2)}
      </pre>
    </div>
  );
}

function PhotoGrid({ urls, title }: { urls: string[]; title?: string }) {
  if (!urls?.length) return null;
  return (
    <div>
      {title && <p className="font-medium text-gray-500 dark:text-gray-400 mb-2">{title}</p>}
      <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
        {urls.map((url, i) => (
          <a
            key={i}
            href={getImageUrl(url)}
            target="_blank"
            rel="noopener noreferrer"
            className="block aspect-square rounded-lg overflow-hidden border border-gray-200 dark:border-gray-600 bg-gray-100 dark:bg-gray-700 focus:ring-2 focus:ring-green-500"
          >
            <img
              src={getImageUrl(url)}
              alt={`Foto ${i + 1}`}
              loading="lazy"
              className="w-full h-full object-cover"
            />
          </a>
        ))}
      </div>
    </div>
  );
}

function servicesLabel(services: string[]): string {
  if (!services?.length) return '—';
  const map: Record<string, string> = { HOSPEDAJE: 'Hospedaje', PASEO: 'Paseos' };
  const labels = services.map((s) => map[s] ?? s);
  if (labels.length === 2) return 'Hospedaje y Paseos (ambos)';
  return labels.join(', ');
}

function SuspendModal({
  onConfirm,
  onCancel,
  acting,
}: {
  onConfirm: (reason: string) => void;
  onCancel: () => void;
  acting: boolean;
}) {
  const [reason, setReason] = useState('');
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div className="w-full max-w-md rounded-2xl bg-white dark:bg-gray-800 shadow-2xl p-6 border border-gray-200 dark:border-gray-700 animate-in fade-in zoom-in duration-200">
        <h3 className="text-xl font-bold text-gray-900 dark:text-white mb-2">Suspender Cuidador</h3>
        <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">
          Indica el motivo de la suspensión. Este mensaje será enviado al cuidador y su perfil dejará de ser público temporalmente.
        </p>
        <textarea
          autoFocus
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="Ej: Incumplimiento de términos, reporte de mal servicio..."
          rows={4}
          className="w-full rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white px-4 py-3 text-sm focus:ring-2 focus:ring-amber-500 focus:border-transparent outline-none transition-all"
        />
        <div className="mt-6 flex gap-3 justify-end">
          <button
            type="button"
            onClick={onCancel}
            disabled={acting}
            className="px-4 py-2 text-sm font-semibold text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors"
          >
            Cancelar
          </button>
          <button
            type="button"
            onClick={() => onConfirm(reason)}
            disabled={acting || reason.trim().length < 5}
            className="px-6 py-2 text-sm font-bold rounded-lg bg-amber-600 hover:bg-amber-700 text-white disabled:opacity-50 shadow-md transition-all active:scale-95"
          >
            {acting ? 'Suspendiendo...' : 'Confirmar Suspensión'}
          </button>
        </div>
      </div>
    </div>
  );
}

function DeleteModal({
  onConfirm,
  onCancel,
  acting,
}: {
  onConfirm: (reason: string, pass: string) => void;
  onCancel: () => void;
  acting: boolean;
}) {
  const [reason, setReason] = useState('');
  const [pass, setPass] = useState('');
  const canDelete = reason.trim().length >= 5 && pass.length > 0;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm">
      <div className="w-full max-w-md rounded-2xl bg-white dark:bg-gray-800 shadow-2xl p-6 border border-red-500/20 animate-in fade-in zoom-in duration-200">
        <div className="w-12 h-12 rounded-full bg-red-100 dark:bg-red-900/30 flex items-center justify-center mb-4 mx-auto text-red-600">
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
          </svg>
        </div>
        <h3 className="text-xl font-bold text-gray-900 dark:text-white mb-2 text-center">¡Atención! Eliminar Cuidador</h3>
        <p className="text-sm text-gray-500 dark:text-gray-400 mb-4 text-center">
          Esta acción es <strong>permanente</strong> e irreversible. Se eliminará toda la información del usuario y su perfil.
        </p>

        <div className="space-y-4">
          <div>
            <label className="block text-xs font-bold text-gray-400 uppercase mb-1 ml-1">Motivo de eliminación</label>
            <textarea
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Explica por qué se elimina esta cuenta..."
              rows={3}
              className="w-full rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white px-4 py-2 text-sm focus:ring-2 focus:ring-red-500 outline-none transition-all"
            />
          </div>

          <div>
            <label className="block text-xs font-bold text-gray-400 uppercase mb-1 ml-1">Tu contraseña de Admin</label>
            <input
              type="password"
              value={pass}
              onChange={(e) => setPass(e.target.value)}
              placeholder="Confirma con tu contraseña"
              className="w-full rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white px-4 py-3 text-sm focus:ring-2 focus:ring-red-500 outline-none transition-all"
            />
          </div>
        </div>

        <div className="mt-6 flex gap-3 justify-center">
          <button
            type="button"
            onClick={onCancel}
            disabled={acting}
            className="flex-1 px-4 py-3 text-sm font-semibold text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-xl transition-colors"
          >
            Cancelar
          </button>
          <button
            type="button"
            onClick={() => onConfirm(reason, pass)}
            disabled={acting || !canDelete}
            className="flex-1 px-4 py-3 text-sm font-bold rounded-xl bg-red-600 hover:bg-red-700 text-white disabled:opacity-50 shadow-lg shadow-red-600/20 transition-all active:scale-95"
          >
            {acting ? 'Eliminando...' : 'Eliminar Permanentemente'}
          </button>
        </div>
      </div>
    </div>
  );
}

export function AdminCaregiverReviewPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { data: detail, isLoading, isError, error } = useCaregiverDetail(id);

  const [acting, setActing] = useState(false);
  const [showSuspend, setShowSuspend] = useState(false);
  const [showDelete, setShowDelete] = useState(false);

  const handleSuspend = async (reason: string) => {
    if (!id) return;
    setActing(true);
    try {
      await suspendCaregiver(id, reason);
      toast.success('Cuidador suspendido correctamente');
      queryClient.invalidateQueries({ queryKey: ['caregiver-detail', id] });
      queryClient.invalidateQueries({ queryKey: [ADMIN_CAREGIVERS_QUERY_KEY] });
      setShowSuspend(false);
    } catch (err: any) {
      toast.error(err.message || 'Error al suspender');
    } finally {
      setActing(false);
    }
  };

  const handleActivate = async () => {
    if (!id) return;
    if (!confirm('¿Deseas activar nuevamente este perfil?')) return;
    setActing(true);
    try {
      await activateCaregiver(id);
      toast.success('Perfil activado correctamente');
      queryClient.invalidateQueries({ queryKey: ['caregiver-detail', id] });
      queryClient.invalidateQueries({ queryKey: [ADMIN_CAREGIVERS_QUERY_KEY] });
    } catch (err: any) {
      toast.error(err.message || 'Error al activar');
    } finally {
      setActing(false);
    }
  };

  const handleDelete = async (reason: string, adminPassword: string) => {
    if (!id) return;
    setActing(true);
    try {
      await deleteCaregiver(id, { reason, adminPassword });
      toast.success('Cuidador eliminado permanentemente');
      queryClient.invalidateQueries({ queryKey: [ADMIN_CAREGIVERS_QUERY_KEY] });
      navigate('/admin/caregivers');
    } catch (err: any) {
      toast.error(err.response?.data?.error?.message || err.message || 'Error al eliminar');
    } finally {
      setActing(false);
      setShowDelete(false);
    }
  };

  if (isLoading) {
    return (
      <div className="py-12 text-center text-gray-500 dark:text-gray-400">
        Cargando solicitud…
      </div>
    );
  }
  if (isError || !detail) {
    const is401 = error && typeof error === 'object' && 'response' in error && (error as { response?: { status?: number } }).response?.status === 401;
    const message = is401
      ? 'Sesión expirada. Inicia sesión de nuevo.'
      : error instanceof Error
        ? error.message
        : 'No se encontró el perfil.';
    return (
      <div className="py-12 px-4 text-center">
        <p className="text-red-600 dark:text-red-400 mb-4">{message}</p>
        <div className="flex flex-col sm:flex-row gap-2 justify-center items-center">
          {is401 ? (
            <Link
              to="/admin/auth"
              className="text-green-600 dark:text-green-400 hover:underline font-medium"
            >
              Ir a inicio de sesión admin
            </Link>
          ) : (
            <Link to="/admin/caregivers" className="text-green-600 dark:text-green-400 hover:underline">
              ← Volver al listado
            </Link>
          )}
        </div>
      </div>
    );
  }

  const u = detail.user;

  return (
    <div className="py-6 px-4 max-w-4xl mx-auto space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <Link
            to="/admin/caregivers"
            className="text-sm text-green-600 dark:text-green-400 hover:underline mb-1 inline-block"
          >
            ← Volver al listado
          </Link>
          <h1 className="text-2xl font-semibold text-gray-900 dark:text-white">
            Revisar solicitud: {u.firstName} {u.lastName}
          </h1>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
            Estado: <span className="font-medium text-gray-700 dark:text-gray-300">{detail.status}</span>
            {detail.verificationStatus && detail.verificationStatus !== detail.status && (
              <span className="ml-2">| Verificación: {detail.verificationStatus}</span>
            )}
            {detail.rejectionReason && (
              <span className="block mt-1 text-amber-700 dark:text-amber-400">
                Motivo de rechazo/revisión: {detail.rejectionReason}
              </span>
            )}
            {detail.reviewChecklist && detail.reviewChecklist.length > 0 && (
              <div className="block mt-2 p-2 bg-amber-50 dark:bg-amber-900/20 rounded-lg border border-amber-200 dark:border-amber-800">
                <span className="font-medium text-amber-800 dark:text-amber-200">Checklist de revisión:</span>
                <ul className="list-disc list-inside mt-1 text-amber-700 dark:text-amber-300 text-sm">
                  {detail.reviewChecklist.map((item, i) => (
                    <li key={i}>{item}</li>
                  ))}
                </ul>
              </div>
            )}
          </p>
        </div>
        <div className="text-xs text-gray-400 font-mono bg-gray-50 dark:bg-gray-900/50 p-2 rounded border border-gray-200 dark:border-gray-700">
          ID: {id} | {detail.photos?.length || 0} fotos | Identidad IA: {detail.identityVerificationStatus === 'VERIFIED' ? 'VERIFICADO' : detail.identityVerificationStatus === 'REVIEW' ? 'PENDIENTE REVISIÓN' : detail.identityVerificationStatus || 'PENDIENTE'} {detail.identityVerificationScore != null && `(${Math.round(detail.identityVerificationScore)}%)`} | Email: {detail.emailVerified ? 'VERIFICADO' : 'PENDIENTE'}
          {!detail.emailVerified && (
            <button
              onClick={async () => {
                try {
                  await verifyCaregiverEmail(id!);
                  toast.success('Email verificado manualmente');
                  queryClient.invalidateQueries({ queryKey: [ADMIN_CAREGIVERS_QUERY_KEY] });
                  queryClient.invalidateQueries({ queryKey: ['caregiver-detail', id] });
                } catch (e) {
                  toast.error('Error al verificar email');
                }
              }}
              className="ml-2 text-green-600 hover:text-green-700 underline font-bold"
            >
              (Verificar Manualmente)
            </button>
          )}
        </div>
      </div>

      <div className="grid gap-6 md:grid-cols-1">
        {/* 1. Datos personales */}
        <Section title="Datos personales">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Nombre completo" value={`${u.firstName} ${u.lastName}`} />
            <Field label="Email" value={u.email} />
            <Field label="Teléfono" value={u.phone} />
            <Field label="Dirección" value={detail.address ?? undefined} />
            <Field label="Número de CI" value={detail.ciNumber ?? undefined} />
            <Field label="Ciudad" value={u.city ?? undefined} />
            <Field label="País" value={u.country ?? undefined} />
            <Field label="Mayor de 18" value={u.isOver18 ? 'Sí' : 'No'} />
            <Field label="Fecha de registro" value={new Date(detail.createdAt).toLocaleString()} />
          </div>
        </Section>

        {/* 2. Estado actual */}
        <Section title="Estado actual y revisión">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Estado" value={detail.status} />
            <Field label="Verificado" value={detail.verified ? 'Sí' : 'No'} />
            <Field label="Motivo de rechazo o revisión" value={detail.rejectionReason ?? undefined} />
            <Field label="Notas admin" value={detail.adminNotes ?? undefined} />
            <Field label="Aprobado en" value={detail.approvedAt ? new Date(detail.approvedAt).toLocaleString() : undefined} />
            <Field label="Revisado en" value={detail.reviewedAt ? new Date(detail.reviewedAt).toLocaleString() : undefined} />
          </div>
        </Section>

        {/* 3. Fotos del espacio */}
        <Section title="Fotos del espacio">
          <PhotoGrid urls={detail.photos ?? []} title="Fotos del espacio (4-6)" />
          {(!detail.photos || detail.photos.length === 0) && (
            <p className="text-gray-500">Sin fotos del espacio</p>
          )}
        </Section>

        {/* 4. Foto personal y selfie */}
        <Section title="Foto de perfil y selfie">
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <p className="font-medium text-gray-500 dark:text-gray-400 mb-2">Foto de perfil</p>
              <a
                href={getImageUrl(detail.profilePhoto)}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-block rounded-lg overflow-hidden border border-gray-200 dark:border-gray-600 max-w-[200px]"
              >
                <img
                  src={getImageUrl(detail.profilePhoto)}
                  alt="Foto de perfil del cuidador"
                  loading="lazy"
                  className="w-full h-auto object-cover"
                />
              </a>
              <a href={getImageUrl(detail.profilePhoto)} target="_blank" rel="noopener noreferrer" className="text-green-600 dark:text-green-400 hover:underline text-xs block mt-1">Abrir</a>
            </div>
            <div>
              <p className="font-medium text-gray-500 dark:text-gray-400 mb-2">Selfie / foto con mascota</p>
              <a
                href={getImageUrl(detail.selfieUrl)}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-block rounded-lg overflow-hidden border border-gray-200 dark:border-gray-600 max-w-[200px]"
              >
                <img
                  src={getImageUrl(detail.selfieUrl)}
                  alt="Selfie del cuidador"
                  loading="lazy"
                  className="w-full h-auto object-cover"
                />
              </a>
              <a href={getImageUrl(detail.selfieUrl)} target="_blank" rel="noopener noreferrer" className="text-green-600 dark:text-green-400 hover:underline text-xs block mt-1">Abrir</a>
            </div>
          </div>
        </Section>

        {/* 5. Verificación de identidad (IA) */}
        <Section title="Verificación de identidad (IA)">
          <div className="space-y-4">
            <div className="flex items-center gap-3">
              <span className="font-medium text-gray-500 dark:text-gray-400">Estado:</span>
              <span className={`px-2.5 py-1 rounded-full text-xs font-bold ${detail.identityVerificationStatus === 'VERIFIED' ? 'bg-green-100 text-green-800' :
                detail.identityVerificationStatus === 'REVIEW' ? 'bg-amber-100 text-amber-800' :
                  detail.identityVerificationStatus === 'REJECTED' ? 'bg-red-100 text-red-800' :
                    'bg-gray-100 text-gray-800'
                }`}>
                {detail.identityVerificationStatus === 'VERIFIED' ? 'VERIFICADO (IA)' :
                  detail.identityVerificationStatus === 'REVIEW' ? 'PEDIR REVISIÓN' :
                    detail.identityVerificationStatus === 'REJECTED' ? 'RECHAZADO' :
                      detail.identityVerificationStatus || 'PENDIENTE'}
              </span>
            </div>
            {detail.identityVerificationScore != null && (
              <Field label="Puntaje de similitud" value={`${Math.round(detail.identityVerificationScore)}%`} />
            )}

            {(detail.identityVerificationStatus === 'REVIEW' || detail.identityVerificationStatus === 'VERIFIED' || detail.identityVerificationStatus === 'REJECTED') && detail.lastIdentityVerificationSessionId && (
              <div className={`mt-4 p-4 border rounded-xl shadow-sm ${detail.identityVerificationStatus === 'REVIEW'
                ? 'bg-amber-50 border-amber-200 dark:bg-amber-900/10 dark:border-amber-900/30'
                : 'bg-gray-50 border-gray-200 dark:bg-gray-900/40 dark:border-gray-700'
                }`}>
                <p className="text-gray-700 dark:text-gray-300 text-sm mb-4 font-medium">
                  {detail.identityVerificationStatus === 'REVIEW'
                    ? '⚠️ Esta identidad requiere revisión manual obligatoria debido al puntaje de similitud.'
                    : detail.identityVerificationStatus === 'REJECTED'
                      ? '❌ Esta verificación fue rechazada.'
                      : '✅ Verificación completada por IA automáticamente.'}
                </p>
                <Link
                  to={`/admin/verification/${detail.lastIdentityVerificationSessionId}`}
                  className={`inline-flex items-center justify-center gap-2 px-6 py-4 rounded-xl text-sm font-black transition-all transform hover:scale-[1.02] shadow-lg ${detail.identityVerificationStatus === 'REVIEW'
                    ? 'bg-amber-500 hover:bg-amber-600 text-white ring-4 ring-amber-500/20'
                    : 'bg-gray-900 dark:bg-white text-white dark:text-gray-900'
                    }`}
                >
                  {detail.identityVerificationStatus === 'REVIEW' ? '🔍 VERIFICAR IDENTIDAD MANUALMENTE AHORA' : '🔍 VER DETALLES DE VERIFICACIÓN'}
                </Link>
              </div>
            )}

            {detail.ciNumber && <Field label="Número de CI" value={detail.ciNumber} />}
          </div>
        </Section>

        {/* 6. Servicios ofrecidos */}
        <Section title="Servicios ofrecidos">
          <Field label="Servicios" value={servicesLabel(detail.servicesOffered ?? [])} />
        </Section>

        {/* 7. Zona y descripción */}
        <Section title="Zona y descripción">
          <Field label="Zona" value={detail.zone ?? undefined} />
          <Field label="Tipo de espacio" value={detail.spaceType?.length ? detail.spaceType.join(', ') : undefined} />
          <Field label="Descripción del espacio" value={detail.spaceDescription ?? undefined} />
          <Field label="Bio / descripción" value={detail.bio ?? undefined} />
          <Field label="Bio detalle" value={detail.bioDetail ?? undefined} />
        </Section>

        {/* 8. Tarifas */}
        <Section title="Tarifas">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Precio por día (Bs)" value={detail.pricePerDay != null ? String(detail.pricePerDay) : undefined} />
            <Field label="Paseo 30 min (Bs)" value={detail.pricePerWalk30 != null ? String(detail.pricePerWalk30) : undefined} />
            <Field label="Paseo 60 min (Bs)" value={detail.pricePerWalk60 != null ? String(detail.pricePerWalk60) : undefined} />
          </div>
          <JsonBlock data={detail.rates ?? null} title="Tarifas adicionales (noche, paseo, adicional, festivos)" />
        </Section>

        {/* 9. Disponibilidad */}
        <Section title="Disponibilidad">
          {(detail.availability && detail.availability.length > 0) && (
            <div className="mb-3">
              <p className="font-medium text-gray-500 dark:text-gray-400 mb-2">Calendario ({detail.availability.length} días)</p>
              <div className="flex flex-wrap gap-2">
                {detail.availability.slice(0, 30).map((a, i) => (
                  <span
                    key={i}
                    className={`inline-flex rounded-lg px-2 py-1 text-xs ${a.isAvailable ? 'bg-green-100 dark:bg-green-900/40 text-green-800 dark:text-green-200' : 'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400'}`}
                    title={typeof a.timeBlocks === 'object' ? JSON.stringify(a.timeBlocks) : ''}
                  >
                    {a.date}
                  </span>
                ))}
                {detail.availability.length > 30 && (
                  <span className="text-xs text-gray-500">+{detail.availability.length - 30} más</span>
                )}
              </div>
            </div>
          )}
          {detail.defaultAvailabilitySchedule && Object.keys(detail.defaultAvailabilitySchedule).length > 0 && (
            <JsonBlock data={detail.defaultAvailabilitySchedule} title="Horario predeterminado" />
          )}
          <JsonBlock data={detail.serviceAvailability ?? null} title="Disponibilidad por servicio (JSON)" />
          {(!detail.serviceAvailability || Object.keys(detail.serviceAvailability).length === 0) &&
            (!detail.availability || detail.availability.length === 0) &&
            !detail.defaultAvailabilitySchedule && (
              <p className="text-gray-500">Sin disponibilidad definida</p>
            )}
        </Section>

        {/* 10. Experiencia */}
        <Section title="Experiencia">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Años de experiencia" value={detail.experienceYears ?? undefined} />
            <Field label="Tiene mascotas propias" value={detail.ownPets != null ? (detail.ownPets ? 'Sí' : 'No') : undefined} />
            <Field label="Ha cuidado otras mascotas" value={detail.caredOthers != null ? (detail.caredOthers ? 'Sí' : 'No') : undefined} />
            <Field label="Tipos de animal" value={detail.animalTypes?.length ? detail.animalTypes.join(', ') : undefined} />
            <Field label="Acepta cachorros" value={detail.acceptPuppies != null ? (detail.acceptPuppies ? 'Sí' : 'No') : undefined} />
            <Field label="Acepta seniors" value={detail.acceptSeniors != null ? (detail.acceptSeniors ? 'Sí' : 'No') : undefined} />
            <Field label="Acepta agresivos" value={detail.acceptAggressive != null ? (detail.acceptAggressive ? 'Sí' : 'No') : undefined} />
            <Field label="Medicación" value={detail.acceptMedication?.length ? detail.acceptMedication.join(', ') : undefined} />
            <Field label="Tamaños aceptados" value={detail.sizesAccepted?.length ? detail.sizesAccepted.join(', ') : undefined} />
          </div>
          <Field label="Descripción de experiencia" value={detail.experienceDescription ?? undefined} />
          <Field label="Por qué es cuidador" value={detail.whyCaregiver ?? undefined} />
          <Field label="Qué le diferencia" value={detail.whatDiffers ?? undefined} />
          <Field label="Manejo de ansiedad" value={detail.handleAnxious ?? undefined} />
          <Field label="Respuesta ante emergencias" value={detail.emergencyResponse ?? undefined} />
          <Field label="Razón no acepta razas" value={detail.breedsWhy ?? undefined} />
          <JsonBlock data={detail.currentPetsDetails as Record<string, unknown> | null} title="Mascotas actuales" />
        </Section>

        {/* 11. Hogar */}
        <Section title="Hogar">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Tipo de hogar" value={detail.homeType ?? undefined} />
            <Field label="Casa propia" value={detail.ownHome != null ? (detail.ownHome ? 'Sí' : 'No') : undefined} />
            <Field label="Tiene patio" value={detail.hasYard != null ? (detail.hasYard ? 'Sí' : 'No') : undefined} />
            <Field label="Patio cerrado" value={detail.yardFenced != null ? (detail.yardFenced ? 'Sí' : 'No') : undefined} />
            <Field label="Niños en casa" value={detail.hasChildren != null ? (detail.hasChildren ? 'Sí' : 'No') : undefined} />
            <Field label="Otras mascotas" value={detail.hasOtherPets != null ? (detail.hasOtherPets ? 'Sí' : 'No') : undefined} />
            <Field label="Dónde duermen sus mascotas" value={detail.petsSleep ?? undefined} />
            <Field label="Dónde duermen mascotas del cliente" value={detail.clientPetsSleep ?? undefined} />
            <Field label="Horas solas (máx)" value={detail.hoursAlone != null ? String(detail.hoursAlone) : undefined} />
            <Field label="Trabaja desde casa" value={detail.workFromHome != null ? (detail.workFromHome ? 'Sí' : 'No') : undefined} />
            <Field label="Máx. mascotas" value={detail.maxPets != null ? String(detail.maxPets) : undefined} />
            <Field label="Suele salir" value={detail.oftenOut != null ? (detail.oftenOut ? 'Sí' : 'No') : undefined} />
          </div>
          <Field label="Día típico" value={detail.typicalDay ?? undefined} />
        </Section>

        {/* Documento de identidad (si existe aparte de CI) */}
        {(detail.idDocumentUrl) && (
          <Section title="Documento de identidad">
            <a
              href={detail.idDocumentUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="text-green-600 dark:text-green-400 hover:underline break-all"
            >
              {detail.idDocumentUrl}
            </a>
          </Section>
        )}

        {/* Términos */}
        <Section title="Términos aceptados">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Términos" value={detail.termsAccepted != null ? (detail.termsAccepted ? 'Sí' : 'No') : undefined} />
            <Field label="Privacidad" value={detail.privacyAccepted != null ? (detail.privacyAccepted ? 'Sí' : 'No') : undefined} />
            <Field label="Verificación" value={detail.verificationAccepted != null ? (detail.verificationAccepted ? 'Sí' : 'No') : undefined} />
            <Field label="Fecha aceptación" value={detail.termsAcceptedAt ? new Date(detail.termsAcceptedAt).toLocaleString() : undefined} />
          </div>
        </Section>
      </div>

      {/* Acciones: Panel de control post-aprobación automática */}
      <div className="sticky bottom-4 rounded-2xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-lg p-6 flex flex-col sm:flex-row flex-wrap gap-4 justify-center">
        {detail.suspended ? (
          <button
            type="button"
            onClick={handleActivate}
            disabled={acting}
            className="px-6 py-3 rounded-xl bg-green-600 hover:bg-green-700 text-white font-semibold text-sm shadow-sm transition-all active:scale-95"
          >
            ✅ Activar Perfil
          </button>
        ) : (
          <button
            type="button"
            onClick={() => setShowSuspend(true)}
            disabled={acting}
            className="px-6 py-3 rounded-xl bg-amber-600 hover:bg-amber-700 text-white font-semibold text-sm shadow-sm transition-all active:scale-95"
          >
            🚫 Suspender
          </button>
        )}

        <button
          type="button"
          onClick={() => setShowDelete(true)}
          disabled={acting}
          className="px-6 py-3 rounded-xl bg-red-600 hover:bg-red-700 text-white font-semibold text-sm shadow-sm transition-all active:scale-95"
        >
          🗑️ Eliminar
        </button>

        <a
          href={`https://wa.me/591${u.phone.replace(/\D/g, '')}`}
          target="_blank"
          rel="noopener noreferrer"
          className="px-6 py-3 rounded-xl bg-[#25D366] hover:bg-[#128C7E] text-white font-semibold text-sm inline-flex items-center justify-center shadow-sm transition-all active:scale-95"
        >
          <svg className="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 24 24">
            <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413Z" />
          </svg>
          WhatsApp
        </a>

        <button
          type="button"
          onClick={() => toast('Funcionalidad de premiación en desarrollo')}
          className="px-6 py-3 rounded-xl bg-gray-100 dark:bg-gray-700 text-gray-400 font-semibold text-sm shadow-sm transition-all"
        >
          ⭐ Premiar
        </button>
      </div>

      {showSuspend && (
        <SuspendModal
          acting={acting}
          onConfirm={handleSuspend}
          onCancel={() => setShowSuspend(false)}
        />
      )}

      {showDelete && (
        <DeleteModal
          acting={acting}
          onConfirm={handleDelete}
          onCancel={() => setShowDelete(false)}
        />
      )}
    </div>
  );
}
