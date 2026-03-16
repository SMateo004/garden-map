import { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';

/** Redirects to the dashboard; onboarding is now section-based at /caregiver/dashboard */
export function CaregiverOnboardingPage() {
  const navigate = useNavigate();
  useEffect(() => {
    navigate('/caregiver/dashboard', { replace: true });
  }, [navigate]);
  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-50 dark:bg-gray-900">
      <p className="text-gray-500">Redirigiendo…</p>
    </div>
  );
}
