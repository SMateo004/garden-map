import { useParams, Link } from 'react-router-dom';
import { usePublicCaregiverDetail } from '@/hooks/usePublicCaregiverDetail';
import { ProfileDetail } from '@/components/ProfileDetail';

export function ProfileDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { data: caregiver, isLoading, isError } = usePublicCaregiverDetail(id);

  if (isLoading) {
    return <div className="py-12 text-center text-gray-500">Cargando perfil...</div>;
  }
  if (isError || !caregiver) {
    return (
      <div className="rounded-lg bg-red-50 p-4 text-red-700">
        No se encontró el perfil. <Link to="/" className="underline">Volver al listado</Link>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <Link to="/" className="text-sm text-green-600 hover:underline">← Volver al listado</Link>
      <ProfileDetail caregiver={caregiver} />
    </div>
  );
}
