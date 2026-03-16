import { useNavigate } from 'react-router-dom';

export function CaregiverEditPage() {
  const navigate = useNavigate();
  return (
    <div className="mx-auto max-w-2xl px-4 py-8">
      <h1 className="text-xl font-bold text-gray-900 dark:text-white">Editar perfil</h1>
      <p className="mt-2 text-gray-500 dark:text-gray-400">Podrás editar tu perfil desde aquí en una próxima actualización.</p>
      <button type="button" onClick={() => navigate('/caregiver/dashboard')} className="mt-4 rounded-xl bg-green-600 hover:bg-green-700 text-white font-semibold px-4 py-2">
        Volver al panel
      </button>
    </div>
  );
}
