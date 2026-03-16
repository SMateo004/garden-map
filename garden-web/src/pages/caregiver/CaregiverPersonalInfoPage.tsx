import { useState, useRef, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { getMyProfile, uploadProfilePhoto } from '@/api/caregiverProfile';
import type { MyProfileResponse } from '@/api/caregiverProfile';
import { getImageUrl } from '@/utils/images';
import { IdentityVerificationCard } from '@/components/caregiver/IdentityVerificationCard';

export function CaregiverPersonalInfoPage() {
  const navigate = useNavigate();
  const { user, isCaregiver } = useAuth();
  const [profile, setProfile] = useState<MyProfileResponse | null | undefined>(undefined);
  const [uploadingPhoto, setUploadingPhoto] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const refetchProfile = () => {
    if (!isCaregiver) return;
    getMyProfile()
      .then(setProfile)
      .catch(() => setProfile(null));
  };

  useEffect(() => {
    refetchProfile();
  }, [isCaregiver]);

  // Polling for identity verification status
  useEffect(() => {
    if (!isCaregiver || profile?.identityVerificationStatus === 'VERIFIED') return;

    const interval = setInterval(() => {
      getMyProfile().then((newProfile) => {
        if (newProfile?.identityVerificationStatus === 'VERIFIED') {
          setProfile(newProfile);
          clearInterval(interval);
        }
      });
    }, 3000);

    return () => clearInterval(interval);
  }, [isCaregiver, profile?.identityVerificationStatus]);

  const handleProfilePhotoChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file || !file.type.startsWith('image/')) return;
    setUploadingPhoto(true);
    try {
      await uploadProfilePhoto(file);
      refetchProfile();
    } finally {
      setUploadingPhoto(false);
    }
  };

  if (!isCaregiver || !user) {
    navigate('/caregiver/auth');
    return null;
  }

  if (profile === undefined) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gray-50 dark:bg-gray-900">
        <p className="text-gray-500">Cargando…</p>
      </div>
    );
  }

  const hasPhoto = Boolean(profile?.profilePhoto);

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900">
      <header className="sticky top-0 z-10 border-b border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3">
        <div className="mx-auto max-w-2xl flex items-center gap-3">
          <button
            type="button"
            onClick={() => navigate('/caregiver/dashboard')}
            className="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
          >
            <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
            </svg>
          </button>
          <h1 className="text-lg font-semibold text-gray-900 dark:text-white">Información personal</h1>
        </div>
      </header>

      <main className="mx-auto max-w-2xl px-4 py-6 space-y-6">
        <section className="space-y-4">
          <h2 className="text-base font-semibold text-gray-900 dark:text-white">Foto de perfil</h2>
          <div className="flex items-center gap-4">
            <img
              src={getImageUrl(profile?.profilePhoto ?? null)}
              alt="Foto de perfil"
              className="h-24 w-24 rounded-full object-cover border-2 border-gray-200 dark:border-gray-600"
            />
            <div>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={handleProfilePhotoChange}
                disabled={uploadingPhoto}
              />
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                disabled={uploadingPhoto}
                className={`rounded-xl bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50 ${!hasPhoto ? 'animate-bounce' : ''}`}
              >
                {uploadingPhoto ? 'Subiendo…' : 'Subir foto'}
              </button>
            </div>
          </div>
        </section>

        <section>
          <IdentityVerificationCard
            caregiverId={profile?.id ?? ''}
            token={profile?.identityVerificationToken ?? null}
            status={(profile?.identityVerificationStatus as 'PENDING' | 'IN_PROGRESS' | 'VERIFIED') ?? 'PENDING'}
          />
        </section>
      </main>
    </div>
  );
}
