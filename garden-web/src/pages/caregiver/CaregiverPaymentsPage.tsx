import { useEffect, useState } from 'react';
import { getMyProfile, type MyProfileResponse, getCaregiverBookings, type CaregiverBookingItem } from '@/api/caregiverProfile';
import { useNavigate } from 'react-router-dom';

export function CaregiverPaymentsPage() {
    const navigate = useNavigate();
    const [profile, setProfile] = useState<MyProfileResponse | null>(null);
    const [bookings, setBookings] = useState<CaregiverBookingItem[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        Promise.all([
            getMyProfile().then(setProfile),
            getCaregiverBookings().then(setBookings)
        ]).finally(() => setLoading(false));
    }, []);

    if (loading) return <div className="p-10 text-center text-gray-500">Cargando tus finanzas...</div>;

    const paidBookings = bookings.filter(b => (b as any).payoutStatus === 'PAID');
    const pendingBookings = bookings.filter(b => b.status === 'COMPLETED' && (b as any).payoutStatus !== 'PAID');

    return (
        <div className="min-h-screen bg-gray-50 dark:bg-gray-950 pb-20">
            <div className="bg-green-600 px-6 py-12 rounded-b-[3rem] shadow-xl text-white">
                <div className="max-w-4xl mx-auto flex items-center justify-between">
                    <div>
                        <p className="text-sm font-bold uppercase tracking-widest opacity-80 mb-1">Balance Actual</p>
                        <h1 className="text-5xl font-black">Bs {profile?.balance || '0.00'}</h1>
                    </div>
                    <div className="w-16 h-16 bg-white/20 rounded-2xl flex items-center justify-center text-3xl">
                        💰
                    </div>
                </div>
            </div>

            <div className="max-w-4xl mx-auto px-6 -mt-8 space-y-8">

                {/* Statistics Cards */}
                <div className="grid grid-cols-2 gap-4">
                    <div className="bg-white dark:bg-gray-900 p-6 rounded-3xl shadow-lg border border-gray-100 dark:border-gray-800">
                        <p className="text-[10px] font-black uppercase text-gray-400 mb-1">Pagos recibidos</p>
                        <p className="text-2xl font-black text-gray-900 dark:text-white">{paidBookings.length}</p>
                    </div>
                    <div className="bg-white dark:bg-gray-900 p-6 rounded-3xl shadow-lg border border-gray-100 dark:border-gray-800">
                        <p className="text-[10px] font-black uppercase text-gray-400 mb-1">Esperando recibo</p>
                        <p className="text-2xl font-black text-amber-500">{pendingBookings.length}</p>
                    </div>
                </div>

                {/* Pending Payouts Section */}
                {pendingBookings.length > 0 && (
                    <section>
                        <h2 className="text-lg font-bold mb-4 flex items-center gap-2">
                            ⏳ Pendientes por Liberar
                            <span className="text-[10px] bg-amber-100 text-amber-700 px-2 py-0.5 rounded-full uppercase">Acción requerida por dueño</span>
                        </h2>
                        <div className="space-y-3">
                            {pendingBookings.map(b => (
                                <div key={b.id} className="bg-amber-50 dark:bg-amber-900/10 border border-amber-100 dark:border-amber-900/30 rounded-2xl p-4 flex items-center justify-between">
                                    <div>
                                        <p className="font-bold text-sm text-gray-900 dark:text-white">{b.petName}</p>
                                        <p className="text-[10px] text-gray-500 uppercase">{b.serviceType} • Finalizado el {new Date(b.createdAt).toLocaleDateString()}</p>
                                    </div>
                                    <p className="font-black text-amber-600">Bs {b.totalAmount}</p>
                                </div>
                            ))}
                        </div>
                        <p className="text-xs text-gray-400 mt-2 italic">* Los fondos se acreditan cuando el dueño confirma que recibió a su mascota en buen estado.</p>
                    </section>
                )}

                {/* History Section */}
                <section>
                    <h2 className="text-lg font-bold mb-4">Historial de Pagos Recibidos</h2>
                    {paidBookings.length === 0 ? (
                        <div className="bg-white dark:bg-gray-900 rounded-3xl p-10 text-center border border-dashed border-gray-300 dark:border-gray-800">
                            <p className="text-gray-400 text-sm">Aún no tienes pagos registrados.</p>
                        </div>
                    ) : (
                        <div className="bg-white dark:bg-gray-900 rounded-3xl shadow-xl overflow-hidden border border-gray-100 dark:border-gray-800">
                            {paidBookings.map((b, i) => (
                                <div key={b.id} className={`p-5 flex items-center justify-between ${i !== paidBookings.length - 1 ? 'border-b border-gray-50 dark:border-gray-800' : ''}`}>
                                    <div className="flex gap-4 items-center">
                                        <div className="w-10 h-10 bg-green-50 dark:bg-green-900/20 rounded-xl flex items-center justify-center text-xl">
                                            ✅
                                        </div>
                                        <div>
                                            <p className="font-bold text-gray-900 dark:text-white">{b.petName}</p>
                                            <p className="text-[10px] text-gray-400 uppercase tracking-tighter">{b.serviceType} • {new Date(b.createdAt).toLocaleDateString()}</p>
                                        </div>
                                    </div>
                                    <div className="text-right">
                                        <p className="font-black text-green-600">+ Bs {(Number(b.totalAmount) - Number(b.commissionAmount)).toFixed(2)}</p>
                                        <p className="text-[8px] text-gray-400">Neto tras comisión</p>
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}
                </section>

            </div>

            {/* Floating Header Back Button */}
            <button
                onClick={() => navigate('/caregiver/dashboard')}
                className="fixed top-6 left-6 w-10 h-10 bg-white/20 backdrop-blur-md rounded-xl flex items-center justify-center text-white border border-white/20 hover:bg-white/30 transition-all"
            >
                ←
            </button>
        </div>
    );
}
