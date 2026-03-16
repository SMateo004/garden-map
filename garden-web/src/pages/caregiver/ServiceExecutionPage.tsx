import { useEffect, useState, useRef } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { api } from '@/api/client';
import { CaregiverBookingItem } from '@/api/caregiverProfile';
import { PhotoUploader } from '@/components/PhotoUploader';
import toast from 'react-hot-toast';

export function ServiceExecutionPage() {
    const { id } = useParams();
    const navigate = useNavigate();
    const { isCaregiver } = useAuth();
    const [booking, setBooking] = useState<CaregiverBookingItem | null>(null);
    const [loading, setLoading] = useState(true);
    const [startTime, setStartTime] = useState<number | null>(null);
    const [elapsed, setElapsed] = useState(0);
    const [tracking, setTracking] = useState(false);
    const [showReportModal, setShowReportModal] = useState(false);
    const [startPhotoFile, setStartPhotoFile] = useState<File | null>(null);
    const [endPhotoFile, setEndPhotoFile] = useState<File | null>(null);
    const [rating, setRating] = useState(5);
    const watchId = useRef<number | null>(null);

    useEffect(() => {
        if (!isCaregiver) navigate('/caregiver/auth');
        fetchBooking();
    }, [id]);

    const fetchBooking = async () => {
        try {
            const res = await api.get(`/api/bookings/${id}`);
            const data = res.data.data;
            setBooking(data);
            if (data.status === 'IN_PROGRESS' && data.serviceStartedAt) {
                setStartTime(new Date(data.serviceStartedAt).getTime());
                setTracking(true);
            }
        } catch (err) {
            toast.error('Error al cargar la reserva');
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        let interval: any;
        if (startTime) {
            interval = setInterval(() => {
                setElapsed(Math.floor((Date.now() - startTime) / 1000));
            }, 1000);
        }
        return () => clearInterval(interval);
    }, [startTime]);

    useEffect(() => {
        if (tracking && 'geolocation' in navigator) {
            watchId.current = navigator.geolocation.watchPosition(
                (pos) => {
                    const { latitude, longitude } = pos.coords;
                    api.post(`/api/bookings/${id}/track`, { lat: latitude, lng: longitude })
                        .catch(console.error);
                },
                (err) => console.error(err),
                { enableHighAccuracy: true }
            );
        }
        return () => {
            if (watchId.current) navigator.geolocation.clearWatch(watchId.current);
        };
    }, [tracking, id]);

    const uploadFile = async (file: File) => {
        const formData = new FormData();
        formData.append('photo', file);
        // Note: You need a fallback or real endpoint for /api/upload
        const res = await api.post('/api/upload/service-photo', formData);
        return res.data.data.url;
    };

    const handleStart = async () => {
        if (!startPhotoFile) return toast.error('Debes subir una foto de la mascota para iniciar');
        try {
            const photoUrl = await uploadFile(startPhotoFile);
            const res = await api.post(`/api/bookings/${id}/start`, { photo: photoUrl });
            setBooking(res.data.data);
            setStartTime(Date.now());
            setTracking(true);
            toast.success('Servicio iniciado');
        } catch (err) {
            toast.error('Error al iniciar el servicio');
        }
    };

    const handleReport = async (type: string, description: string) => {
        try {
            await api.post(`/api/bookings/${id}/event`, { type, description });
            toast.success('Reporte enviado');
            setShowReportModal(false);
        } catch (err) {
            toast.error('Error al enviar el reporte');
        }
    };

    const handleConclude = async () => {
        if (!endPhotoFile) return toast.error('Debes subir la foto de entrega');
        if (!navigator.geolocation) return toast.error('Se requiere GPS para finalizar');

        navigator.geolocation.getCurrentPosition(async (pos) => {
            try {
                const { latitude, longitude } = pos.coords;
                const photoUrl = await uploadFile(endPhotoFile);
                await api.post(`/api/bookings/${id}/conclude`, {
                    photo: photoUrl,
                    rating,
                    lat: latitude,
                    lng: longitude
                });
                toast.success('Servicio culminado con éxito');
                navigate('/caregiver/dashboard');
            } catch (err) {
                toast.error('Error al finalizar el servicio');
            }
        }, () => toast.error('No se pudo obtener la ubicación final'));
    };

    if (loading) return <div className="p-10 text-center text-gray-500">Cargando ejecución...</div>;
    if (!booking) return <div className="p-10 text-center">Reserva no encontrada</div>;

    const formatTime = (seconds: number) => {
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        const s = seconds % 60;
        return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
    };

    const isCompleted = booking.status === 'COMPLETED';
    const isInProgress = booking.status === 'IN_PROGRESS';
    const isStarted = !!startTime;

    return (
        <div className="min-h-screen bg-white dark:bg-gray-950 flex flex-col">
            <div className="bg-green-600 p-6 text-white text-center rounded-b-[2rem] shadow-lg">
                <h1 className="text-xl font-black uppercase tracking-widest">GARDEN Tracking</h1>
                <p className="text-sm opacity-90">{booking.petName} • {booking.serviceType}</p>
            </div>

            <div className="flex-1 overflow-y-auto p-6 space-y-8 max-w-lg mx-auto w-full">

                {/* Timer Card */}
                <div className="bg-gray-50 dark:bg-gray-900 rounded-3xl p-8 text-center shadow-inner border border-gray-100 dark:border-gray-800">
                    <p className="text-xs font-bold text-gray-400 uppercase tracking-tighter mb-2">Tiempo de Cuidado</p>
                    <div className="text-5xl font-black font-mono text-gray-800 dark:text-gray-100">
                        {formatTime(elapsed)}
                    </div>
                    {tracking && (
                        <div className="mt-4 flex items-center justify-center gap-2 text-green-500 animate-pulse">
                            <span className="w-2 h-2 bg-green-500 rounded-full"></span>
                            <span className="text-[10px] font-bold uppercase tracking-widest">GPS Activo • Siguiendo ubicación</span>
                        </div>
                    )}
                </div>

                {/* Step 1: Start */}
                {!isStarted && !isCompleted && (
                    <div className="space-y-4 bg-white dark:bg-gray-900 p-6 rounded-3xl border border-gray-100 dark:border-gray-800 shadow-sm">
                        <h2 className="text-lg font-bold">1. Iniciar Servicio</h2>
                        <p className="text-sm text-gray-500">Tómale una foto a {booking.petName} al recibirlo para comenzar.</p>
                        <PhotoUploader
                            value={startPhotoFile ? [startPhotoFile] : []}
                            onChange={(files) => setStartPhotoFile(files[0] || null)}
                        />
                        <button
                            onClick={handleStart}
                            className="w-full py-4 bg-green-600 text-white font-black rounded-2xl shadow-xl shadow-green-100 dark:shadow-none active:scale-95 transition-all"
                        >
                            INICIAR AHORA
                        </button>
                    </div>
                )}

                {/* In Progress Actions */}
                {isInProgress && (
                    <div className="space-y-6">
                        <div className="grid grid-cols-3 gap-3">
                            <button
                                onClick={() => setShowReportModal(true)}
                                className="flex flex-col items-center justify-center p-4 bg-amber-50 dark:bg-amber-900/20 text-amber-700 rounded-2xl border border-amber-100"
                            >
                                <span className="text-2xl mb-1">⚠️</span>
                                <span className="text-[10px] font-black uppercase tracking-tighter">Reportar</span>
                                <span className="text-[8px] opacity-70">Incidente</span>
                            </button>
                            <button className="flex flex-col items-center justify-center p-4 bg-blue-50 dark:bg-blue-900/20 text-blue-700 rounded-2xl border border-blue-100">
                                <span className="text-2xl mb-1">💬</span>
                                <span className="text-[10px] font-black uppercase tracking-tighter">Chat</span>
                                <span className="text-[8px] opacity-70">Dueño</span>
                            </button>
                            <button className="flex flex-col items-center justify-center p-4 bg-red-50 dark:bg-red-900/20 text-red-700 rounded-2xl border border-red-100">
                                <span className="text-2xl mb-1">🛑</span>
                                <span className="text-[10px] font-black uppercase tracking-tighter">Forzar</span>
                                <span className="text-[8px] opacity-70">Final</span>
                            </button>
                        </div>

                        <div className="space-y-4 pt-6 border-t bg-white dark:bg-gray-900 p-6 rounded-3xl border border-gray-100 dark:border-gray-800 shadow-sm">
                            <h2 className="text-lg font-bold">2. Concluir Servicio</h2>
                            <p className="text-sm text-gray-500">Sácale una segunda foto a {booking.petName} al momento de la entrega.</p>
                            <PhotoUploader
                                value={endPhotoFile ? [endPhotoFile] : []}
                                onChange={(files) => setEndPhotoFile(files[0] || null)}
                            />
                            <div className="space-y-2">
                                <label className="text-sm font-bold">Califica al Dueño</label>
                                <div className="flex gap-2">
                                    {[1, 2, 3, 4, 5].map(s => (
                                        <button
                                            key={s}
                                            onClick={() => setRating(s)}
                                            className={`flex-1 h-12 rounded-xl font-black transition-all ${rating === s ? 'bg-green-600 text-white scale-110' : 'bg-gray-100 dark:bg-gray-800 text-gray-400'}`}
                                        >
                                            {s}
                                        </button>
                                    ))}
                                </div>
                            </div>
                            <button
                                onClick={handleConclude}
                                className="w-full py-4 bg-black text-white font-black rounded-2xl shadow-xl active:scale-95 transition-all mt-4"
                            >
                                CONCLUIR SERVICIO
                            </button>
                        </div>
                    </div>
                )}

                {isCompleted && (
                    <div className="p-10 text-center space-y-4 animate-in zoom-in duration-500">
                        <span className="text-7xl block">✨</span>
                        <h2 className="text-2xl font-black">¡Gran trabajo!</h2>
                        <p className="text-gray-500">Servicio para {booking.petName} completado satisfactoriamente.</p>
                        <button onClick={() => navigate('/caregiver/dashboard')} className="w-full py-4 bg-green-600 text-white font-bold rounded-2xl shadow-lg ring-4 ring-green-100 dark:ring-0">
                            Volver al Dashboard
                        </button>
                    </div>
                )}
            </div>

            {showReportModal && (
                <div className="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-end sm:items-center justify-center p-4">
                    <div className="bg-white dark:bg-gray-900 w-full max-w-md rounded-t-3xl sm:rounded-3xl p-6 space-y-4 shadow-2xl animate-in slide-in-from-bottom-4 duration-300">
                        <h3 className="text-xl font-black uppercase mb-4">Reportar Incidente</h3>
                        <div className="grid grid-cols-1 gap-2">
                            <button onClick={() => handleReport('ACCIDENT', 'Accidente ocurrido')} className="w-full p-4 bg-red-50 text-red-600 rounded-2xl font-black flex items-center justify-between">
                                ACCIDENTE <span>🚑</span>
                            </button>
                            <button onClick={() => handleReport('ILLNESS', 'Enfermedad detectada')} className="w-full p-4 bg-amber-50 text-amber-600 rounded-2xl font-black flex items-center justify-between">
                                ENFERMEDAD <span>🌡️</span>
                            </button>
                            <button onClick={() => handleReport('COMPLICATION', 'Inconveniente general')} className="w-full p-4 bg-blue-50 text-blue-600 rounded-2xl font-black flex items-center justify-between">
                                INCONVENIENTE <span>❓</span>
                            </button>
                            <button onClick={() => setShowReportModal(false)} className="w-full p-4 bg-gray-100 rounded-2xl font-black text-gray-500 mt-4">
                                CANCELAR
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}
