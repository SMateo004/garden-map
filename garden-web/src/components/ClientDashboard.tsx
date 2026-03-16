import { useEffect, useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { getMyBookings, type BookingResult } from '@/api/bookings';
import { useClientMyProfile } from '@/hooks/useClientMyProfile';
import { getImageUrl } from '@/utils/images';
import { ProfileCard } from '@/components/ProfileCard';
import type { PaginatedCaregivers } from '@/types/caregiver';

interface ClientDashboardProps {
    featuredCaregivers: PaginatedCaregivers | undefined;
    isLoadingCaregivers: boolean;
}

export function ClientDashboard({ featuredCaregivers, isLoadingCaregivers }: ClientDashboardProps) {
    const navigate = useNavigate();
    const { data: profile } = useClientMyProfile();
    const [bookings, setBookings] = useState<BookingResult[]>([]);
    const [loadingBookings, setLoadingBookings] = useState(true);

    useEffect(() => {
        getMyBookings()
            .then((res) => {
                if (res.success && res.data) {
                    setBookings(res.data);
                }
            })
            .finally(() => setLoadingBookings(false));
    }, []);

    const upcomingBookings = bookings.filter(b =>
        b.status === 'CONFIRMED' || b.status === 'IN_PROGRESS' || b.status === 'WAITING_CAREGIVER_APPROVAL'
    );

    // Derive recent caregivers from completed bookings
    const recentCaregivers = bookings
        .filter(b => b.status === 'COMPLETED')
        .reduce((acc, b) => {
            if (!acc.find(item => item.caregiverId === b.caregiverId)) {
                acc.push({
                    caregiverId: b.caregiverId,
                    name: b.caregiverName,
                    photo: b.caregiverPhoto
                });
            }
            return acc;
        }, [] as { caregiverId: string, name?: string, photo?: string | null }[])
        .slice(0, 4);

    return (
        <div className="space-y-12 pb-20">

            {/* 1. Próximas Reservas */}
            <section>
                <div className="flex items-center justify-between mb-6">
                    <h2 className="text-xl font-black text-gray-900 dark:text-white flex items-center gap-2">
                        📅 Próximas Reservas
                        <span className="bg-green-100 text-green-700 text-xs px-2 py-0.5 rounded-full">{upcomingBookings.length}</span>
                    </h2>
                    <Link to="/profile/reservations" className="text-sm font-bold text-green-600 hover:underline">Ver todas</Link>
                </div>

                {loadingBookings ? (
                    <div className="h-32 bg-gray-100 dark:bg-gray-800 animate-pulse rounded-3xl" />
                ) : upcomingBookings.length === 0 ? (
                    <div className="bg-white dark:bg-gray-800 rounded-3xl p-10 text-center border border-dashed border-gray-300 dark:border-gray-700">
                        <p className="text-gray-500 font-medium font-bold">No tienes reservas programadas.</p>
                        <Link to="/" className="text-green-600 font-bold mt-2 inline-block">Busca un cuidador ahora</Link>
                    </div>
                ) : (
                    <div className="grid gap-4 sm:grid-cols-2">
                        {upcomingBookings.map(b => (
                            <div key={b.id} className="bg-white dark:bg-gray-800 p-5 rounded-3xl shadow-sm border border-gray-100 dark:border-gray-700 flex items-center gap-4 hover:shadow-md transition-all">
                                <div className="w-12 h-12 bg-green-50 dark:bg-green-900/20 rounded-2xl flex items-center justify-center text-2xl">
                                    {b.serviceType === 'HOSPEDAJE' ? '🏠' : '🦮'}
                                </div>
                                <div className="flex-1">
                                    <h3 className="font-black text-gray-900 dark:text-white uppercase tracking-tighter">{b.petName}</h3>
                                    <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">
                                        {b.serviceType === 'HOSPEDAJE' ? `${b.startDate} al ${b.endDate}` : `${b.walkDate} • ${b.timeSlot}`}
                                    </p>
                                    <p className="text-[10px] font-black text-green-600 mt-1 uppercase">Cuidador: {b.caregiverName}</p>
                                    <div className="mt-2 flex gap-2">
                                        {b.status === 'WAITING_CAREGIVER_APPROVAL' && (
                                            <span className="text-[8px] font-black bg-amber-100 text-amber-700 px-2 py-0.5 rounded-full uppercase tracking-widest">Esperando Aceptación</span>
                                        )}
                                        {b.status === 'PAYMENT_PENDING_APPROVAL' && (
                                            <span className="text-[8px] font-black bg-blue-100 text-blue-700 px-2 py-0.5 rounded-full uppercase tracking-widest">Pago por Verificar</span>
                                        )}
                                        {b.status === 'CONFIRMED' && (
                                            <span className="text-[8px] font-black bg-green-100 text-green-700 px-2 py-0.5 rounded-full uppercase tracking-widest">Confirmada</span>
                                        )}
                                    </div>
                                </div>
                                <button
                                    onClick={() => navigate(`/bookings/${b.id}`)}
                                    className="px-4 py-2 bg-gray-50 dark:bg-gray-700 text-[10px] font-black rounded-xl uppercase hover:bg-gray-100 transition-colors border border-gray-100 dark:border-gray-600"
                                >
                                    Detalles
                                </button>
                            </div>
                        ))}
                    </div>
                )}
            </section>

            {/* 2. Mis Mascotas */}
            <section>
                <div className="flex items-center justify-between mb-6">
                    <h2 className="text-xl font-black text-gray-900 dark:text-white italic">🐾 Mis Consentidos</h2>
                    <Link to="/profile/complete-pet" className="text-sm font-bold text-green-600 hover:underline">+ Agregar</Link>
                </div>
                <div className="flex gap-4 overflow-x-auto pb-4 no-scrollbar">
                    {profile?.pets.map(pet => (
                        <div key={pet.id} className="shrink-0 w-48 bg-white dark:bg-gray-800 rounded-3xl p-4 shadow-sm border border-gray-100 dark:border-gray-700 text-center hover:scale-105 transition-transform cursor-pointer group" onClick={() => navigate(`/profile/edit-pet/${pet.id}`)}>
                            <div className="relative mb-3">
                                <img
                                    src={getImageUrl(pet.photoUrl)}
                                    alt={pet.name}
                                    className="w-24 h-24 rounded-2xl mx-auto object-cover border-2 border-green-100 group-hover:border-green-400 transition-colors"
                                />
                            </div>
                            <h3 className="font-black text-gray-900 dark:text-white uppercase tracking-tighter">{pet.name}</h3>
                            <p className="text-[10px] font-bold text-gray-500 uppercase">{pet.breed || 'Raza no especificada'}</p>
                            <div className="flex items-center justify-center gap-2 mt-2">
                                <span className="text-[8px] font-black bg-gray-50 dark:bg-gray-700 px-2 py-0.5 rounded-full text-gray-400 uppercase tracking-widest">{pet.age} años</span>
                                <span className="text-[8px] font-black bg-gray-50 dark:bg-gray-700 px-2 py-0.5 rounded-full text-gray-400 uppercase tracking-widest">{pet.size}</span>
                            </div>
                        </div>
                    ))}
                    {(!profile?.pets || profile.pets.length === 0) && (
                        <div className="flex-1 bg-gray-50 dark:bg-gray-800/50 rounded-3xl p-8 text-center text-gray-400 font-bold border-2 border-dashed border-gray-200">
                            Registra a tu mascota para empezar
                        </div>
                    )}
                </div>
            </section>

            {/* 3. Cuidadores Recientes */}
            {recentCaregivers.length > 0 && (
                <section>
                    <h2 className="text-xl font-black text-gray-900 dark:text-white mb-6">🔄 Cuidadores Recientes</h2>
                    <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
                        {recentCaregivers.map(c => (
                            <div key={c.caregiverId} className="bg-white dark:bg-gray-800 p-4 rounded-3xl shadow-sm border border-gray-100 dark:border-gray-700 text-center hover:shadow-md transition-all cursor-pointer" onClick={() => navigate(`/caregivers/${c.caregiverId}`)}>
                                <img
                                    src={getImageUrl(c.photo)}
                                    className="w-16 h-16 rounded-2xl mx-auto object-cover mb-2"
                                    alt={c.name}
                                />
                                <p className="text-[10px] font-black text-gray-900 dark:text-white uppercase tracking-tighter">{c.name}</p>
                                <button className="mt-2 text-[8px] font-bold text-green-600 uppercase tracking-widest">Ver Perfil</button>
                            </div>
                        ))}
                    </div>
                </section>
            )}

            {/* 4. Cuidadores Destacados (Original Listing) */}
            <section className="pt-8 border-t border-gray-100 dark:border-gray-800">
                <h2 className="text-xl font-black text-gray-900 dark:text-white mb-6">⭐ Cuidadores Destacados</h2>
                {isLoadingCaregivers ? (
                    <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                        {[1, 2, 3, 4].map(i => <div key={i} className="h-64 bg-gray-100 dark:bg-gray-800 animate-pulse rounded-3xl" />)}
                    </div>
                ) : (
                    <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                        {featuredCaregivers?.caregivers.map((c) => (
                            <ProfileCard key={c.id} caregiver={c} />
                        ))}
                    </div>
                )}
            </section>

        </div>
    );
}
