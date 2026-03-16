import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { getIdentityReviewsList, type IdentityReviewItem } from '@/api/admin';
import toast from 'react-hot-toast';

export function AdminIdentityReviewsPage() {
  const navigate = useNavigate();
  const [items, setItems] = useState<IdentityReviewItem[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    load();
  }, []);

  const load = async () => {
    setLoading(true);
    try {
      const data = await getIdentityReviewsList();
      setItems(data ?? []);
    } catch (err: any) {
      toast.error(err?.message ?? 'Error al cargar');
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return <div className="p-10 text-center text-gray-500">Cargando revisiones...</div>;
  }

  return (
    <div className="py-6 px-4 max-w-4xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-black text-gray-900 dark:text-white">Revisiones de Identidad</h1>
        <button
          onClick={() => navigate('/admin')}
          className="text-sm text-green-600 dark:text-green-400 hover:underline"
        >
          ← Panel Admin
        </button>
      </div>

      {items.length === 0 ? (
        <div className="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-12 text-center">
          <p className="text-gray-500 dark:text-gray-400">No hay verificaciones pendientes de revisión manual.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {items.map((item) => (
            <div
              key={item.id}
              className="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-4 flex items-center justify-between shadow-sm"
            >
              <div>
                <p className="font-bold text-gray-900 dark:text-white">
                  {item.user?.firstName} {item.user?.lastName}
                </p>
                <p className="text-sm text-gray-500 dark:text-gray-400">{item.user?.email}</p>
                <p className="text-xs text-gray-400 mt-1">
                  Similitud: {item.similarity != null ? `${Math.round(item.similarity)}%` : '—'} •{' '}
                  {item.completedAt ? new Date(item.completedAt).toLocaleString() : '—'}
                </p>
              </div>
              <button
                onClick={() => navigate(`/admin/identity-reviews/${item.id}`)}
                className="px-4 py-2 rounded-xl bg-green-600 hover:bg-green-700 text-white text-sm font-semibold"
              >
                Ver fotos
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
