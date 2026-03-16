import { useState, useEffect, useCallback } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { getMyProfile } from '@/api/caregiverProfile';
import toast from 'react-hot-toast';
import { PersonalInfoSection } from '@/components/caregiver/PersonalInfoSection';
import { CaregiverProfileSection } from '@/components/caregiver/CaregiverProfileSection';
import { AvailabilitySection } from '@/components/caregiver/AvailabilitySection';

const TABS = [
  { id: 'personal', label: 'Información personal' },
  { id: 'caregiver', label: 'Perfil del cuidador' },
  { id: 'availability', label: 'Disponibilidad' },
] as const;

export function CaregiverProfilePage() {
  const navigate = useNavigate();
  const { user, isCaregiver } = useAuth();
  const [profile, setProfile] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<(typeof TABS)[number]['id']>('personal');

  const refetchProfile = useCallback(async () => {
    try {
      const p = await getMyProfile();
      setProfile(p);
    } catch {
      toast.error('Error al cargar perfil');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!isCaregiver) return;
    refetchProfile();
  }, [isCaregiver, refetchProfile]);

  if (!isCaregiver || !user) {
    navigate('/caregiver/auth');
    return null;
  }

  if (loading) {
    return <div className="py-12 text-center text-gray-500">Cargando perfil…</div>;
  }

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900 pb-20">
      <div className="mx-auto max-w-4xl px-4 py-8">
        <Link
          to="/caregiver/dashboard"
          className="inline-flex items-center gap-2 text-sm font-medium text-green-600 dark:text-green-400 hover:underline mb-6"
        >
          ← Volver al panel
        </Link>

        {/* Tab navigation */}
        <nav className="flex gap-1 p-1 rounded-xl bg-gray-100 dark:bg-gray-800 mb-6 overflow-hidden">
          {TABS.map((tab) => {
            // Logic for indicators in tabs
            let statusBadge = null;
            if (profile) {
              const isApproved = profile.profileStatus === 'APPROVED' || profile.status === 'APPROVED';
              if (tab.id === 'personal') {
                const isComplete = profile.personalInfoComplete || isApproved;
                if (isComplete) {
                  statusBadge = <span className="w-5 h-5 flex items-center justify-center rounded-full ml-2 bg-green-100 text-green-600 text-[10px] font-bold" title="Completado">✓</span>;
                } else {
                  statusBadge = <span className={`w-3 h-3 rounded-full ml-2 border-2 border-white dark:border-gray-900 bg-red-600 animate-pulse`} />;
                }
              } else if (tab.id === 'caregiver') {
                const isComplete = profile.caregiverProfileComplete || isApproved || profile.profileStatus === 'SUBMITTED' || profile.profileStatus === 'UNDER_REVIEW';
                if (isComplete) {
                  statusBadge = <span className="w-5 h-5 flex items-center justify-center rounded-full ml-2 bg-green-100 text-green-600 text-[10px] font-bold" title="Completado">✓</span>;
                } else {
                  statusBadge = <span className={`w-3 h-3 rounded-full ml-2 border-2 border-white dark:border-gray-900 bg-red-600 animate-pulse`} />;
                }
              } else if (tab.id === 'availability') {
                const isComplete = profile.availabilityComplete || isApproved || profile.profileStatus === 'SUBMITTED' || profile.profileStatus === 'UNDER_REVIEW';
                if (isComplete) {
                  statusBadge = <span className="w-5 h-5 flex items-center justify-center rounded-full ml-2 bg-green-100 text-green-600 text-[10px] font-bold" title="Completado">✓</span>;
                } else {
                  statusBadge = <span className="w-3 h-3 rounded-full ml-2 border-2 border-white dark:border-gray-900 bg-red-600 animate-pulse" title="Pendiente de configurar" />;
                }
              }
            }

            return (
              <button
                key={tab.id}
                type="button"
                onClick={() => setActiveTab(tab.id)}
                className={`flex-1 flex items-center justify-center py-2.5 px-4 rounded-lg text-sm font-medium transition-colors ${activeTab === tab.id
                  ? 'bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm'
                  : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200'
                  }`}
              >
                {tab.label}
                {statusBadge}
              </button>
            );
          })}
        </nav>

        {/* Section content - only one visible */}
        <div className="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-6 sm:p-8 shadow-sm">
          {activeTab === 'personal' && (
            <PersonalInfoSection
              profile={profile}
              user={profile?.user ?? user}
              onUpdate={refetchProfile}
            />
          )}
          {activeTab === 'caregiver' && (
            <CaregiverProfileSection profile={profile} onUpdate={refetchProfile} />
          )}
          {activeTab === 'availability' && (
            <AvailabilitySection profile={profile} />
          )}
        </div>
      </div>
    </div>
  );
}
