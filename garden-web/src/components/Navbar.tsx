import { useState, useRef, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { LoginRequiredModal } from './LoginRequiredModal';
import { NotificationBell } from './NotificationBell';

function getProfilePath(role: string | undefined): string {
  if (role === 'ADMIN') return '/admin/caregivers';
  if (role === 'CAREGIVER') return '/caregiver/profile';
  if (role === 'CLIENT') return '/profile';
  return '/';
}

export function Navbar() {
  const navigate = useNavigate();
  const { user, isCaregiver, isAdmin, isAuthenticated, logout } = useAuth();
  const [menuOpen, setMenuOpen] = useState(false);
  const [showOwnerLogin, setShowOwnerLogin] = useState(false);
  const [servicesSubmenuOpen, setServicesSubmenuOpen] = useState(false);
  const [profileSubmenuOpen, setProfileSubmenuOpen] = useState(false);
  const sideMenuRef = useRef<HTMLDivElement>(null);

  const profilePath = getProfilePath(user?.role);

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (sideMenuRef.current && !sideMenuRef.current.contains(e.target as Node)) {
        setMenuOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const closeMenus = () => {
    setMenuOpen(false);
  };

  return (
    <header className="sticky top-0 z-[40] border-b border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800">
      <div className="mx-auto max-w-7xl px-4 py-3 sm:px-6 lg:px-8">
        <div className="relative flex items-center h-10">
          {/* Lado Izquierdo: Menú Hamburguesa */}
          <div className="flex-1 flex items-center">
            <button
              type="button"
              onClick={() => setMenuOpen(true)}
              className="p-2 rounded-lg text-gray-600 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
              aria-label="Menú principal"
            >
              <svg className="h-7 w-7" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
              </svg>
            </button>
          </div>

          {/* Centro: LOGO */}
          <div className="absolute left-1/2 -translate-x-1/2">
            <Link
              to={isCaregiver ? "/caregiver/dashboard" : "/"}
              className="text-2xl font-black tracking-tighter text-green-700 dark:text-green-400 hover:opacity-80 transition-opacity"
            >
              GARDEN
            </Link>
          </div>

          {/* Lado Derecho: Solo Notificaciones si está autenticado */}
          <div className="flex-1 flex justify-end items-center gap-4">
            {isAuthenticated && (
              <NotificationBell />
            )}
          </div>
        </div>
      </div>

      {/* Menú Lateral (Overlay + Panel) */}
      {menuOpen && (
        <div className="fixed inset-0 z-[60] flex">
          <div className="fixed inset-0 bg-black/40 backdrop-blur-sm transition-opacity" onClick={() => setMenuOpen(false)}></div>

          <div ref={sideMenuRef} className="relative w-80 max-w-[90%] bg-white dark:bg-gray-900 h-full shadow-2xl flex flex-col animate-in slide-in-from-left duration-300">
            <div className="p-6 flex items-center justify-between border-b border-gray-100 dark:border-gray-800">
              <span className="text-xl font-black text-green-700 dark:text-green-400">GARDEN</span>
              <button onClick={() => setMenuOpen(false)} className="p-2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-200">
                <svg className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" /></svg>
              </button>
            </div>

            <nav className="flex-1 overflow-y-auto p-4 space-y-2">
              {!isAuthenticated && (
                <>
                  <div>
                    <button
                      onClick={() => setServicesSubmenuOpen(!servicesSubmenuOpen)}
                      className="w-full flex items-center justify-between p-3 text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-xl transition-colors font-semibold text-lg"
                    >
                      <span className="flex items-center gap-3">
                        <svg className="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" /></svg>
                        Servicios
                      </span>
                      <svg className={`h-5 w-5 transition-transform ${servicesSubmenuOpen ? 'rotate-180' : ''}`} fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                      </svg>
                    </button>
                    {servicesSubmenuOpen && (
                      <div className="mt-1 ml-11 space-y-1 border-l border-gray-100 dark:border-gray-800">
                        <button className="w-full text-left p-2.5 pl-4 text-gray-600 dark:text-gray-400 hover:text-green-600 dark:hover:text-green-400 text-base font-medium">Paseadores</button>
                        <button className="w-full text-left p-2.5 pl-4 text-gray-600 dark:text-gray-400 hover:text-green-600 dark:hover:text-green-400 text-base font-medium">Hospedaje</button>
                      </div>
                    )}
                  </div>
                  <button className="w-full text-left p-3 text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-xl transition-colors font-semibold text-lg flex items-center gap-3">
                    <svg className="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" /></svg>
                    Salud y bienestar
                  </button>
                  <Link
                    to="/become-caregiver"
                    onClick={closeMenus}
                    className="flex items-center gap-3 p-3 text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-xl transition-colors font-semibold text-lg"
                  >
                    <svg className="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" /></svg>
                    Conviértete en cuidador
                  </Link>
                  <div className="pt-4 mt-4 border-t border-gray-100 dark:border-gray-800">
                    <button
                      onClick={() => { setMenuOpen(false); setShowOwnerLogin(true); }}
                      className="w-full p-4 bg-green-600 text-white rounded-2xl font-bold shadow-lg shadow-green-200 dark:shadow-none hover:bg-green-700 transition-all text-center flex items-center justify-center gap-2"
                    >
                      <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 16l-4-4m0 0l4-4m-4 4h14m-5 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h7a3 3 0 013 3v1" /></svg>
                      Login / Sign In (Dueños)
                    </button>
                  </div>
                </>
              )}

              {isAuthenticated && (
                <>
                  <div>
                    <button
                      onClick={() => setProfileSubmenuOpen(!profileSubmenuOpen)}
                      className="w-full flex items-center justify-between p-3 text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-xl transition-colors font-semibold text-lg"
                    >
                      <span className="flex items-center gap-3">
                        <svg className="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" /></svg>
                        Mi Perfil
                      </span>
                      <svg className={`h-5 w-5 transition-transform ${profileSubmenuOpen ? 'rotate-180' : ''}`} fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                      </svg>
                    </button>
                    {profileSubmenuOpen && (
                      <div className="mt-1 ml-11 space-y-1 border-l border-gray-100 dark:border-gray-800">
                        <Link to={profilePath} onClick={closeMenus} className="block w-full text-left p-2.5 pl-4 text-gray-600 dark:text-gray-400 hover:text-green-600 dark:hover:text-green-400 text-base font-medium">Perfil</Link>
                        {isCaregiver && (
                          <>
                            <Link to="/caregiver/profile" onClick={closeMenus} className="block w-full text-left p-2.5 pl-4 text-gray-600 dark:text-gray-400 hover:text-green-600 dark:hover:text-green-400 text-base font-medium">Perfil cuidador</Link>
                            <Link to="/caregiver/calendar" onClick={closeMenus} className="block w-full text-left p-2.5 pl-4 text-gray-600 dark:text-gray-400 hover:text-green-600 dark:hover:text-green-400 text-base font-medium">Mi calendario</Link>
                            <Link to="/caregiver/availability" onClick={closeMenus} className="block w-full text-left p-2.5 pl-4 text-gray-600 dark:text-gray-400 hover:text-green-600 dark:hover:text-green-400 text-base font-medium">Mi disponibilidad</Link>
                          </>
                        )}
                      </div>
                    )}
                  </div>

                  {!isCaregiver && !isAdmin && (
                    <>
                      <Link to="/profile/reservations" onClick={closeMenus} className="flex items-center gap-3 p-3 text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-xl transition-colors font-semibold text-lg">
                        <svg className="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" /></svg>
                        Reservas
                      </Link>
                      <Link to="/bookings" onClick={closeMenus} className="flex items-center gap-3 p-3 text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-xl transition-colors font-semibold text-lg">
                        <svg className="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 2" /></svg>
                        Historial de Reservas
                      </Link>
                    </>
                  )}

                  <Link
                    to={isCaregiver ? "/caregiver/inbox" : "/inbox"}
                    onClick={closeMenus}
                    className="flex items-center gap-3 p-3 text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-xl transition-colors font-semibold text-lg"
                  >
                    <svg className="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 8h10M7 12h4m1 8l-4-4H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-3l-4 4z" /></svg>
                    Mensajes
                  </Link>

                  <Link
                    to={isCaregiver ? "/caregiver/payments" : "#"}
                    onClick={closeMenus}
                    className="flex items-center gap-3 p-3 text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-xl transition-colors font-semibold text-lg"
                  >
                    <svg className="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
                    {isCaregiver ? "Mis Ganancias" : "Pagos"}
                  </Link>

                  <button className="w-full text-left p-3 text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-xl transition-colors font-semibold text-lg flex items-center gap-3">
                    <svg className="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" /></svg>
                    Términos y condiciones
                  </button>

                  <button className="w-full text-left p-3 text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-xl transition-colors font-semibold text-lg flex items-center gap-3">
                    <svg className="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" /></svg>
                    Soporte Garden
                  </button>

                  {isAdmin && (
                    <Link to="/admin/caregivers" onClick={closeMenus} className="block p-3 text-blue-600 font-bold hover:bg-blue-50 dark:hover:bg-blue-900/10 rounded-xl transition-colors text-lg">
                      Panel Admin
                    </Link>
                  )}

                  <div className="pt-4 mt-auto border-t border-gray-100 dark:border-gray-800">
                    <button
                      onClick={() => { logout(); closeMenus(); navigate('/'); }}
                      className="w-full p-4 text-red-600 font-bold hover:bg-red-50 dark:hover:bg-red-900/10 rounded-2xl transition-all text-center flex items-center justify-center gap-2"
                    >
                      <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" /></svg>
                      Cerrar sesión
                    </button>
                  </div>
                </>
              )}
            </nav>

            <div className="p-4 border-t border-gray-100 dark:border-gray-800">
              <p className="text-[10px] text-center text-gray-400 uppercase tracking-widest font-black">© 2026 GARDEN Pet Services</p>
            </div>
          </div>
        </div>
      )}

      <LoginRequiredModal
        isOpen={showOwnerLogin}
        onClose={() => setShowOwnerLogin(false)}
        onSuccess={() => setShowOwnerLogin(false)}
      />
    </header>
  );
}
