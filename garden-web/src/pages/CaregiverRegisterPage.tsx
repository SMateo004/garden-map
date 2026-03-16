import { CaregiverProfileForm } from '@/components/CaregiverProfileForm';

export function CaregiverRegisterPage() {
  return (
    <div className="mx-auto max-w-2xl px-4 py-8">
      <h1 className="text-2xl font-bold text-gray-900">Registro de cuidador</h1>
      <p className="mt-1 text-gray-600">
        Completa tu perfil para aparecer en el listado. Necesitas entre 2 y 4 fotos (paseadores)
        o entre 4 y 6 fotos (hospedaje) del espacio y perfil, además de una descripción.
      </p>
      <div className="mt-6">
        <CaregiverProfileForm />
      </div>
    </div>
  );
}
