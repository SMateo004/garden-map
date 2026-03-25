import { NavLink, Outlet } from 'react-router-dom';

const navItems = [
  { to: '/admin/caregivers', label: 'Cuidadores', icon: '🐾' },
  { to: '/admin/caregivers/pending', label: 'Solicitudes', icon: '📝' },
  { to: '/admin/reservations', label: 'Reservas', icon: '📅' },
  { to: '/admin/payments-pending', label: 'Pagos Manuales', icon: '💰' },
  { to: '/admin/identity-reviews', label: 'Identidades (IA)', icon: '🆔' },
  { to: '/admin/disputes', label: 'Disputas', icon: '⚖️' },
  { to: '/admin/withdrawals', label: 'Retiros', icon: '🏦' },
  { to: '/admin/gift-codes', label: 'Gifts', icon: '🎁' },
];

export function AdminLayout() {
  return (
    <div className="flex min-h-[calc(100vh-64px)] bg-gray-50 dark:bg-gray-900 -mx-4 -my-6 sm:-mx-6 lg:-mx-8">
      {/* Sidebar */}
      <aside className="w-64 flex-shrink-0 bg-white dark:bg-gray-800 border-r border-gray-200 dark:border-gray-700 hidden md:block">
        <nav className="p-4 space-y-1">
          <div className="px-3 py-2 mb-2 text-xs font-bold text-gray-400 uppercase tracking-widest">
            Navegación Admin
          </div>
          {navItems.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              className={({ isActive }) =>
                `flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-semibold transition-all ${
                  isActive
                    ? 'bg-green-50 text-green-700 dark:bg-green-900/20 dark:text-green-400 ring-1 ring-green-100 dark:ring-green-900/30'
                    : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700'
                }`
              }
              end={item.to === '/admin/caregivers'}
            >
              <span className="text-lg">{item.icon}</span>
              {item.label}
            </NavLink>
          ))}
        </nav>
      </aside>

      {/* Main Content */}
      <main className="flex-1 min-w-0">
        <div className="h-full overflow-y-auto">
          {/* Mobile sub-nav (only visible on mobile) */}
          <div className="md:hidden flex overflow-x-auto p-2 gap-2 bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 scrollbar-hide">
             {navItems.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                className={({ isActive }) =>
                  `flex-shrink-0 px-3 py-1.5 rounded-full text-xs font-bold whitespace-nowrap transition-all ${
                    isActive
                      ? 'bg-green-600 text-white'
                      : 'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400'
                  }`
                }
                end={item.to === '/admin/caregivers'}
              >
                {item.label}
              </NavLink>
            ))}
          </div>
          
          <div className="p-4 md:p-8">
            <Outlet />
          </div>
        </div>
      </main>
    </div>
  );
}
