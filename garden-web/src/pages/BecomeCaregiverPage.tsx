import { useNavigate } from 'react-router-dom';

export function BecomeCaregiverPage() {
    const navigate = useNavigate();

    return (
        <div className="min-h-screen bg-slate-50 dark:bg-gray-900 py-12 px-4">
            <div className="max-w-4xl mx-auto">
                <div className="bg-white dark:bg-gray-800 rounded-3xl shadow-xl overflow-hidden border border-gray-100 dark:border-gray-700">
                    <div className="p-8 sm:p-12">
                        <h1 className="text-4xl font-extrabold text-gray-900 dark:text-white mb-6 text-center">
                            Únete a la comunidad de cuidadores de <span className="text-green-600">GARDEN</span>
                        </h1>
                        <p className="text-xl text-gray-600 dark:text-gray-300 text-center mb-12">
                            Convierte tu amor por las mascotas en una oportunidad única. Tú decides tus horarios, tus servicios y tus tarifas.
                        </p>

                        <div className="grid md:grid-cols-2 gap-8 mb-12">
                            {/* Paseo */}
                            <div className="bg-green-50 dark:bg-green-900/10 p-8 rounded-2xl border border-green-100 dark:border-green-900/20">
                                <div className="w-12 h-12 bg-green-100 dark:bg-green-900/30 rounded-xl flex items-center justify-center mb-4">
                                    <svg className="w-6 h-6 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
                                    </svg>
                                </div>
                                <h3 className="text-2xl font-bold text-gray-900 dark:text-white mb-3">Paseador</h3>
                                <p className="text-gray-600 dark:text-gray-400">
                                    Ideal para quienes disfrutan del aire libre. Realiza paseos de 30 o 60 minutos y mantén a las mascotas activas y felices.
                                </p>
                            </div>

                            {/* Hospedaje */}
                            <div className="bg-blue-50 dark:bg-blue-900/10 p-8 rounded-2xl border border-blue-100 dark:border-blue-900/20">
                                <div className="w-12 h-12 bg-blue-100 dark:bg-blue-900/30 rounded-xl flex items-center justify-center mb-4">
                                    <svg className="w-6 h-6 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" />
                                    </svg>
                                </div>
                                <h3 className="text-2xl font-bold text-gray-900 dark:text-white mb-3">Hospedaje</h3>
                                <p className="text-gray-600 dark:text-gray-400">
                                    Recibe mascotas en tu casa. Brinda un hogar temporal seguro y lleno de cariño mientras sus dueños no están.
                                </p>
                            </div>
                        </div>

                        <div className="flex justify-center items-center">
                            <button
                                onClick={() => navigate('/caregiver/auth')}
                                className="w-full sm:w-auto px-12 py-4 bg-green-600 hover:bg-green-700 text-white font-bold rounded-2xl transition-all shadow-lg hover:shadow-green-200 transform hover:-translate-y-1 active:scale-95"
                            >
                                Únete a nuestro equipo
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
}
