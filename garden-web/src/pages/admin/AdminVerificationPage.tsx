import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import {
    getIdentityVerificationDetail,
    approveIdentityVerification,
    rejectIdentityVerification,
    type IdentityVerificationSession,
} from '@/api/admin';
import { getImageUrl } from '@/utils/images';

function imgUrl(session: IdentityVerificationSession, key: 'selfie' | 'ci' | 'ciBack' | 'croppedSelfie' | 'croppedDoc'): string {
    const u =
        key === 'selfie'
            ? (session.selfieUrlSigned ?? session.selfieUrl)
            : key === 'ci'
                ? (session.ciFrontUrlSigned ?? session.ciFrontUrl)
                : key === 'ciBack'
                    ? (session.ciBackUrlSigned ?? session.ciBackUrl)
                    : key === 'croppedSelfie'
                        ? (session.faceCroppedSelfieUrlSigned ?? session.faceCroppedSelfieUrl)
                        : (session.faceCroppedDocumentUrlSigned ?? session.faceCroppedDocumentUrl);
    return getImageUrl(u);
}

export function AdminVerificationPage() {
    const { id } = useParams<{ id: string }>();
    const navigate = useNavigate();
    const [session, setSession] = useState<IdentityVerificationSession | null>(null);
    const [loading, setLoading] = useState(true);
    const [acting, setActing] = useState(false);

    useEffect(() => {
        if (id) {
            loadData();
        }
    }, [id]);

    const loadData = async () => {
        setLoading(true);
        try {
            const data = await getIdentityVerificationDetail(id!);
            setSession(data);
        } catch (err: any) {
            toast.error(err.message || "Error al cargar datos");
        } finally {
            setLoading(false);
        }
    };

    const handleApprove = async () => {
        if (!id) return;
        setActing(true);
        try {
            await approveIdentityVerification(id);
            toast.success("Identidad aprobada correctamente");
            loadData(); // Reload to show status
        } catch (err: any) {
            toast.error(err.message || "Error al aprobar");
        } finally {
            setActing(false);
        }
    };

    const handleReject = async () => {
        if (!id) return;
        if (!window.confirm("¿Seguro que deseas rechazar esta identidad?")) return;
        setActing(true);
        try {
            await rejectIdentityVerification(id);
            toast.success("Identidad rechazada correctamente");
            loadData(); // Reload to show status
        } catch (err: any) {
            toast.error(err.message || "Error al rechazar");
        } finally {
            setActing(false);
        }
    };

    if (loading) return <div className="p-10 text-center text-gray-500">Cargando verificación...</div>;
    if (!session) return <div className="p-10 text-center text-red-500">No se encontró la sesión</div>;

    return (
        <div className="py-6 px-4 max-w-4xl mx-auto space-y-8">
            <div className="flex items-center justify-between">
                <button onClick={() => navigate(-1)} className="text-sm text-green-600 hover:underline">← Volver</button>
                <h1 className="text-2xl font-black text-gray-900 dark:text-white">Revisión de Identidad</h1>
                <div />
            </div>

            <div className="grid gap-8 md:grid-cols-2">
                {/* Images */}
                <div className="space-y-6">
                    {session.livenessFrameUrlsSigned && session.livenessFrameUrlsSigned.length > 0 && (
                        <div className="rounded-3xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-4 shadow-sm">
                            <p className="text-xs font-black text-gray-400 uppercase tracking-widest mb-3">Frames de Liveness</p>
                            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                                {session.livenessFrameUrlsSigned.filter(Boolean).map((url, i) => (
                                    <img
                                        key={i}
                                        src={getImageUrl(url!)}
                                        alt={`Liveness ${i + 1}`}
                                        className="aspect-square rounded-lg object-cover border border-gray-200 cursor-pointer"
                                        onClick={() => window.open(getImageUrl(url!), '_blank')}
                                    />
                                ))}
                            </div>
                        </div>
                    )}
                    <div className="rounded-3xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-4 shadow-sm">
                        <p className="text-xs font-black text-gray-400 uppercase tracking-widest mb-3">Selfie</p>
                        <div className="aspect-square rounded-2xl overflow-hidden bg-gray-100 dark:bg-gray-700">
                            <img
                                src={imgUrl(session, 'selfie')}
                                alt="Selfie"
                                className="w-full h-full object-cover cursor-pointer"
                                onClick={() => window.open(imgUrl(session, 'selfie'), '_blank')}
                            />
                        </div>
                    </div>
                    <div className="rounded-3xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-4 shadow-sm">
                        <p className="text-xs font-black text-gray-400 uppercase tracking-widest mb-3">Rostro recortado (selfie)</p>
                        <div className="aspect-square rounded-2xl overflow-hidden bg-gray-100 dark:bg-gray-700">
                            <img
                                src={imgUrl(session, 'croppedSelfie')}
                                alt="Rostro selfie"
                                className="w-full h-full object-cover cursor-pointer"
                                onClick={() => window.open(imgUrl(session, 'croppedSelfie'), '_blank')}
                            />
                        </div>
                    </div>
                    <div className="rounded-3xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-4 shadow-sm">
                        <p className="text-xs font-black text-gray-400 uppercase tracking-widest mb-3">Documento (Anverso)</p>
                        <div className="aspect-[4/3] rounded-2xl overflow-hidden bg-gray-100 dark:bg-gray-700">
                            <img
                                src={imgUrl(session, 'ci')}
                                alt="CI Front"
                                className="w-full h-full object-cover cursor-pointer"
                                onClick={() => window.open(imgUrl(session, 'ci'), '_blank')}
                            />
                        </div>
                    </div>
                    <div className="rounded-3xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-4 shadow-sm">
                        <p className="text-xs font-black text-gray-400 uppercase tracking-widest mb-3">Documento (Reverso)</p>
                        <div className="aspect-[4/3] rounded-2xl overflow-hidden bg-gray-100 dark:bg-gray-700">
                            <img
                                src={imgUrl(session, 'ciBack')}
                                alt="CI Back"
                                className="w-full h-full object-cover cursor-pointer"
                                onClick={() => window.open(imgUrl(session, 'ciBack'), '_blank')}
                            />
                        </div>
                    </div>
                    <div className="rounded-3xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-4 shadow-sm">
                        <p className="text-xs font-black text-gray-400 uppercase tracking-widest mb-3">Rostro del documento</p>
                        <div className="aspect-square rounded-2xl overflow-hidden bg-gray-100 dark:bg-gray-700">
                            <img
                                src={imgUrl(session, 'croppedDoc')}
                                alt="Rostro documento"
                                className="w-full h-full object-cover cursor-pointer"
                                onClick={() => window.open(imgUrl(session, 'croppedDoc'), '_blank')}
                            />
                        </div>
                    </div>
                </div>

                {/* Info & Actions */}
                <div className="space-y-6">
                    <div className="rounded-3xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-6 shadow-sm space-y-6">
                        <div>
                            <p className="text-xs font-black text-gray-400 uppercase tracking-widest mb-1">Usuario</p>
                            <p className="text-xl font-bold text-gray-900 dark:text-white">{session.user?.firstName} {session.user?.lastName}</p>
                            <p className="text-sm text-gray-500">{session.user?.email}</p>
                        </div>

                        <div className="pt-4 border-t border-gray-100 dark:border-gray-700 space-y-4">
                            <div className="flex items-center justify-between">
                                <p className="text-xs font-black text-gray-400 uppercase tracking-widest">Global Trust Score</p>
                                <span className={`text-2xl font-black ${(session.trustScore ?? 0) >= 90 ? 'text-green-500' : (session.trustScore ?? 0) >= 70 ? 'text-amber-500' : 'text-red-500'}`}>
                                    {session.trustScore ?? Math.round(session.identityScore ?? 0)}%
                                </span>
                            </div>

                            <div className="space-y-3">
                                {[
                                    { label: 'Rostro (35%)', score: session.faceScore ?? Math.round(session.similarityScore ?? 0) },
                                    { label: 'Liveness (20%)', score: session.livenessScore },
                                    { label: 'OCR Match (15%)', score: session.ocrScore },
                                    { label: 'Autenticidad (10%)', score: session.docScore },
                                    { label: 'Calidad (10%)', score: session.qualityScore },
                                    { label: 'Comportamiento (10%)', score: session.behaviorScore },
                                ].map((item) => (
                                    <div key={item.label} className="space-y-1">
                                        <div className="flex justify-between text-[10px] font-bold uppercase tracking-tight">
                                            <span className="text-gray-500">{item.label}</span>
                                            <span className={item.score && item.score < 70 ? 'text-red-500' : 'text-gray-900 dark:text-gray-100'}>{item.score ?? 0}%</span>
                                        </div>
                                        <div className="h-1.5 w-full bg-gray-100 dark:bg-gray-700 rounded-full overflow-hidden">
                                            <div
                                                className={`h-full transition-all duration-1000 ${(item.score ?? 0) >= 90 ? 'bg-green-500' : (item.score ?? 0) >= 70 ? 'bg-amber-500' : 'bg-red-500'}`}
                                                style={{ width: `${item.score ?? 0}%` }}
                                            />
                                        </div>
                                    </div>
                                ))}
                            </div>
                        </div>
                        {session.ocrData && (session.ocrData.fullName || session.ocrData.documentNumber) && (
                            <div className="pt-4 border-t border-gray-100 dark:border-gray-700">
                                <p className="text-xs font-black text-gray-400 uppercase tracking-widest mb-2">Datos OCR vs Perfil</p>
                                <div className="text-sm space-y-2">
                                    <div className="p-2 rounded bg-gray-50 dark:bg-gray-900/50">
                                        <p className="text-[10px] text-gray-400 font-bold uppercase">Nombre en Perfil</p>
                                        <p className="font-medium">{session.user?.firstName} {session.user?.lastName}</p>
                                    </div>
                                    <div className="p-2 rounded bg-gray-50 dark:bg-gray-900/50">
                                        <p className="text-[10px] text-gray-400 font-bold uppercase">Nombre en Documento</p>
                                        <p className={`font-medium ${session.fraudFlags?.includes('name_mismatch') ? 'text-red-500' : 'text-green-600'}`}>
                                            {session.ocrData.fullName || 'No detectado'}
                                        </p>
                                    </div>
                                    <div className="grid grid-cols-2 gap-2">
                                        <div className="p-2 rounded bg-gray-50 dark:bg-gray-900/50">
                                            <p className="text-[10px] text-gray-400 font-bold uppercase">Documento (CI)</p>
                                            <p className="font-medium">{session.ocrData.documentNumber || '—'}</p>
                                        </div>
                                        <div className="p-2 rounded bg-gray-50 dark:bg-gray-900/50">
                                            <p className="text-[10px] text-gray-400 font-bold uppercase">Fecha Nacimiento</p>
                                            <p className={`font-medium ${session.fraudFlags?.includes('dob_mismatch') ? 'text-amber-500' : ''}`}>
                                                {session.ocrData.dateOfBirth || '—'}
                                            </p>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        )}

                        <div className="pt-4 border-t border-gray-100 dark:border-gray-700">
                            <p className="text-xs font-black text-gray-400 uppercase tracking-widest mb-3">Red & Dispositivo (Risk Layer)</p>
                            <div className="space-y-3">
                                <div className="flex items-center gap-3 p-2 rounded bg-gray-50 dark:bg-gray-900/50 border border-gray-100 dark:border-gray-800">
                                    <div className="w-10 h-10 rounded-full bg-blue-100 dark:bg-blue-900/30 flex items-center justify-center text-blue-600">
                                        🌍
                                    </div>
                                    <div>
                                        <p className="text-[10px] font-bold text-gray-400 uppercase">Ubicación Estimada (IP)</p>
                                        <p className="text-sm font-bold text-gray-800 dark:text-gray-200">
                                            {session.locationData?.city || 'Desconocida'}, {session.locationData?.country || '—'}
                                            <span className="ml-2 text-[10px] text-gray-400">({session.ipAddress})</span>
                                        </p>
                                    </div>
                                </div>

                                <div className="grid grid-cols-2 gap-2 text-[10px]">
                                    <div className="p-2 border border-gray-100 dark:border-gray-700 rounded">
                                        <span className="text-gray-400 uppercase font-black">OS:</span>{' '}
                                        <span className="font-bold">{session.deviceDetails?.os || '—'}</span>
                                    </div>
                                    <div className="p-2 border border-gray-100 dark:border-gray-700 rounded">
                                        <span className="text-gray-400 uppercase font-black">Browser:</span>{' '}
                                        <span className="font-bold">{session.deviceDetails?.browser || '—'}</span>
                                    </div>
                                    <div className="col-span-2 p-2 border border-gray-100 dark:border-gray-700 rounded truncate">
                                        <span className="text-gray-400 uppercase font-black">Fingerprint:</span>{' '}
                                        <span className="font-mono text-[8px]">{session.deviceFingerprint || '—'}</span>
                                    </div>
                                </div>

                                <div className="h-24 w-full bg-gray-200 dark:bg-gray-700 rounded-xl overflow-hidden relative">
                                    {/* Simulated Map */}
                                    <div className="absolute inset-0 opacity-40 grayscale pointer-events-none" style={{ backgroundImage: 'radial-gradient(circle, #000 1px, transparent 1px)', backgroundSize: '10px 10px' }}></div>
                                    <div className="absolute inset-0 flex items-center justify-center">
                                        <div className="w-4 h-4 bg-blue-500 rounded-full animate-ping opacity-75"></div>
                                        <div className="w-3 h-3 bg-blue-600 rounded-full border-2 border-white absolute"></div>
                                    </div>
                                    <p className="absolute bottom-1 right-2 text-[8px] text-gray-500 font-bold uppercase tracking-widest">Geolocation Active</p>
                                </div>
                            </div>
                        </div>

                        {session.fraudFlags && session.fraudFlags.length > 0 && (
                            <div className="pt-4 border-t border-gray-100 dark:border-gray-700">
                                <p className="text-xs font-black text-red-500 uppercase tracking-widest mb-2">🚩 Flags de Fraude / Alerta</p>
                                <div className="flex flex-wrap gap-2">
                                    {session.fraudFlags.map((flag) => (
                                        <span key={flag} className="px-2 py-1 bg-red-100 text-red-700 text-[10px] font-black rounded uppercase">
                                            {flag.replace(/_/g, ' ')}
                                        </span>
                                    ))}
                                </div>
                            </div>
                        )}

                        <div className="pt-4 border-t border-gray-100 dark:border-gray-700">
                            <p className="text-xs font-black text-gray-400 uppercase tracking-widest mb-1">Fecha de Captura</p>
                            <p className="text-gray-700 dark:text-gray-300 font-medium">
                                {new Date(session.createdAt).toLocaleString()}
                            </p>
                        </div>

                        <div className="pt-4 border-t border-gray-100 dark:border-gray-700">
                            <p className="text-xs font-black text-gray-400 uppercase tracking-widest mb-1">Estado Actual</p>
                            <span className={`px-2 py-1 rounded text-xs font-black ${session.status === 'VERIFIED' ? 'bg-green-100 text-green-700' :
                                session.status === 'REVIEW' ? 'bg-amber-100 text-amber-700' :
                                    'bg-red-100 text-red-700'
                                }`}>
                                {session.status}
                            </span>
                        </div>
                    </div>

                    <div className="flex flex-col gap-3">
                        <button
                            onClick={handleApprove}
                            disabled={acting || session.status === 'VERIFIED'}
                            className="w-full py-4 rounded-2xl bg-green-600 hover:bg-green-700 text-white font-black shadow-lg shadow-green-600/20 disabled:opacity-50 transition-all"
                        >
                            {acting ? 'PROCESANDO...' : '✅ APROBAR IDENTIDAD'}
                        </button>
                        <button
                            onClick={handleReject}
                            disabled={acting}
                            className="w-full py-4 rounded-2xl bg-white dark:bg-gray-800 border-2 border-red-500 text-red-500 font-black hover:bg-red-50 dark:hover:bg-red-900/10 disabled:opacity-50 transition-all"
                        >
                            {acting ? 'PROCESANDO...' : '❌ RECHAZAR IDENTIDAD'}
                        </button>
                    </div>
                </div>
            </div>
        </div>
    );
}
