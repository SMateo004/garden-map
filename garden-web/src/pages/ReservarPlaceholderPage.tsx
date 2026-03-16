import { useParams, Link } from 'react-router-dom';

/** Placeholder para fase 2.2: flujo de reserva */
export function ReservarPlaceholderPage() {
  const { id } = useParams<{ id: string }>();

  return (
    <div className="rounded-xl border border-gray-200 bg-white p-6 text-center">
      <h1 className="text-xl font-bold text-gray-900">Reserva</h1>
      <p className="mt-2 text-gray-600">
        Flujo de reserva próximamente. Cuidador: <code className="text-sm">{id}</code>
      </p>
      <Link to={id ? `/caregivers/${id}` : '/'} className="mt-4 inline-block text-green-600 hover:underline">
        Volver al perfil
      </Link>
    </div>
  );
}
