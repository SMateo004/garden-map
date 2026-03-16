import { useEffect } from 'react';
import { Routes, Route, Navigate, useNavigate, useLocation } from 'react-router-dom';
import { Toaster } from 'react-hot-toast';
import { AuthProvider, useAuth } from '@/contexts/AuthContext';
import { Navbar } from '@/components/Navbar';
import { ListingPage } from '@/pages/ListingPage';
import { CaregiverDetailPage } from '@/pages/CaregiverDetailPage';
import { BookingPage } from '@/pages/BookingPage';
import { BookingSuccessPage } from '@/pages/BookingSuccessPage';
import { BookingDetailPage } from '@/pages/BookingDetailPage';
import { BookingConfirmationPage } from '@/pages/BookingConfirmationPage';
import { PaymentPage } from '@/pages/PaymentPage';
import { MyBookingsPage } from '@/pages/MyBookingsPage';
import { CaregiverRegisterPage } from '@/pages/CaregiverRegisterPage';
import { CaregiverAuthPage } from '@/pages/CaregiverAuthPage';
import { RegisterWizard } from '@/pages/caregiver/RegisterWizard';
import { CaregiverDashboard } from '@/pages/caregiver/CaregiverDashboard';
import { CaregiverBookingDetailPage } from '@/pages/caregiver/CaregiverBookingDetailPage';
import { CaregiverProfilePage } from '@/pages/caregiver/CaregiverProfilePage';
import { CaregiverOnboardingPage } from '@/pages/caregiver/CaregiverOnboardingPage';
import { CaregiverPersonalInfoPage } from '@/pages/caregiver/CaregiverPersonalInfoPage';
import { VerifyIdentityPage } from '@/pages/VerifyIdentityPage';
import { CaregiverQuestionnairePage } from '@/pages/caregiver/CaregiverQuestionnairePage';
import { CaregiverAvailabilityPage } from '@/pages/caregiver/CaregiverAvailabilityPage';
import { ServiceExecutionPage } from '@/pages/caregiver/ServiceExecutionPage';
import { CaregiverPaymentsPage } from '@/pages/caregiver/CaregiverPaymentsPage';
import { CaregiverCalendarPage } from '@/pages/caregiver/CaregiverCalendarPage';
import { InboxPage } from '@/pages/InboxPage';
import { CaregiverReservationsPage } from '@/pages/CaregiverReservationsPage';
import { AdminCaregiversListPage } from '@/pages/admin/AdminCaregiversListPage';
import { AdminPendingPage } from '@/pages/admin/AdminPendingPage';
import { AdminPaymentsPendingPage } from '@/pages/admin/AdminPaymentsPendingPage';
import { AdminReservationsPage } from '@/pages/admin/AdminReservationsPage';
import { AdminCaregiverReviewPage } from '@/pages/admin/AdminCaregiverReviewPage';
import { AdminVerificationPage } from '@/pages/admin/AdminVerificationPage';
import { AdminIdentityReviewsPage } from '@/pages/admin/AdminIdentityReviewsPage';
import { AdminAuthPage } from '@/pages/admin/AdminAuthPage';
import { ClientProfileCompletePage } from '@/pages/ClientProfileCompletePage';
import { ClientProfilePage } from '@/pages/ClientProfilePage';
import { ClientReservationsPage } from '@/pages/ClientReservationsPage';
import { BecomeCaregiverPage } from '@/pages/BecomeCaregiverPage';
import { CompletePetProfilePage } from '@/pages/CompletePetProfilePage';
import { EditPetPage } from '@/pages/EditPetPage';

function CaregiverRoute({ children }: { children: React.ReactNode }) {
  const { token, isCaregiver, isLoading } = useAuth();
  if (!token) return <Navigate to="/caregiver/auth" replace />;
  if (!isLoading && !isCaregiver) return <Navigate to="/" replace />;
  if (isLoading) return <div className="py-12 text-center text-gray-500">Cargando…</div>;
  return <>{children}</>;
}

/** Guard: rutas admin. Solo role === 'ADMIN' con token; si no → /admin/auth o /. */
function AdminRoute({ children }: { children: React.ReactNode }) {
  const { token, isAdmin, isLoading } = useAuth();
  if (!token) return <Navigate to="/admin/auth" replace />;
  if (!isLoading && !isAdmin) return <Navigate to="/" replace />;
  if (isLoading) return <div className="py-12 text-center text-gray-500">Cargando…</div>;
  return <>{children}</>;
}

function ClientRoute({ children }: { children: React.ReactNode }) {
  const { token, isLoading } = useAuth();
  if (!token) return <Navigate to="/" replace />;
  if (isLoading) return <div className="py-12 text-center text-gray-500">Cargando…</div>;
  return <>{children}</>;
}

/** Solo CLIENT logueado; CAREGIVER/ADMIN o no logueado → redirigir a /. */
function ClientOnlyRoute({ children }: { children: React.ReactNode }) {
  const { user, token, isLoading } = useAuth();
  if (!token) return <Navigate to="/" replace />;
  if (isLoading) return <div className="py-12 text-center text-gray-500">Cargando…</div>;
  if (user?.role !== 'CLIENT') return <Navigate to="/" replace />;
  return <>{children}</>;
}

/** Tras login/carga: si CLIENT y perfil de mascota incompleto → redirigir a /profile. No afecta a CAREGIVER/ADMIN. */
function ClientPetProfileRedirect() {
  const navigate = useNavigate();
  const location = useLocation();
  const { user, isLoading } = useAuth();

  useEffect(() => {
    if (isLoading || !user) return;
    if (user.role !== 'CLIENT') return;
    const isComplete = user.clientProfile?.isComplete === true;
    if (isComplete) return;
    const pathname = location.pathname;
    if (pathname === '/profile' || pathname === '/profile/complete-pet' || pathname === '/profile/complete') return;
    navigate('/profile', {
      replace: true,
      state: { returnTo: location.pathname + location.search },
    });
  }, [user, isLoading, location.pathname, location.search, navigate]);

  return null;
}

export default function App() {
  return (
    <AuthProvider>
      <ClientPetProfileRedirect />
      <div className="min-h-screen bg-white dark:bg-gray-900">
        <Navbar />
        <main className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <Routes>
            {/* Listado público: accesible con o sin login (CLIENT, CAREGIVER o anónimo) */}
            <Route path="/" element={<ListingPage />} />
            <Route path="/caregivers/:id" element={<CaregiverDetailPage />} />
            <Route path="/reservar/:id" element={<BookingPage />} />
            <Route
              path="/booking/:id/confirm"
              element={
                <ClientOnlyRoute>
                  <BookingConfirmationPage />
                </ClientOnlyRoute>
              }
            />
            <Route
              path="/booking/:id/payment"
              element={
                <ClientOnlyRoute>
                  <PaymentPage />
                </ClientOnlyRoute>
              }
            />
            <Route path="/bookings/:id/success" element={<BookingSuccessPage />} />
            <Route
              path="/bookings"
              element={
                <ClientRoute>
                  <MyBookingsPage />
                </ClientRoute>
              }
            />
            <Route
              path="/bookings/:id"
              element={
                <ClientRoute>
                  <BookingDetailPage />
                </ClientRoute>
              }
            />
            <Route path="/caregiver/:id/verify" element={<VerifyIdentityPage />} />
            <Route path="/verify-identity" element={<VerifyIdentityPage />} />
            <Route path="/register-caregiver" element={<CaregiverRegisterPage />} />
            <Route path="/caregiver/auth" element={<CaregiverAuthPage />} />
            <Route path="/become-caregiver" element={<BecomeCaregiverPage />} />
            <Route path="/admin/auth" element={<AdminAuthPage />} />
            <Route
              path="/profile/edit-pet/:petId"
              element={
                <ClientOnlyRoute>
                  <EditPetPage />
                </ClientOnlyRoute>
              }
            />
            <Route
              path="/profile/complete-pet"
              element={
                <ClientOnlyRoute>
                  <CompletePetProfilePage />
                </ClientOnlyRoute>
              }
            />
            <Route
              path="/profile/complete"
              element={
                <ClientOnlyRoute>
                  <CompletePetProfilePage />
                </ClientOnlyRoute>
              }
            />
            <Route
              path="/profile"
              element={
                <ClientRoute>
                  <ClientProfilePage />
                </ClientRoute>
              }
            />
            <Route
              path="/profile/reservations"
              element={
                <ClientOnlyRoute>
                  <ClientReservationsPage />
                </ClientOnlyRoute>
              }
            />
            <Route
              path="/inbox"
              element={
                <ClientRoute>
                  <InboxPage />
                </ClientRoute>
              }
            />
            <Route
              path="/profile/notifications"
              element={
                <ClientRoute>
                  <InboxPage />
                </ClientRoute>
              }
            />
            <Route
              path="/profile/welcome"
              element={
                <ClientRoute>
                  <ClientProfileCompletePage />
                </ClientRoute>
              }
            />
            <Route path="/caregiver/register" element={<RegisterWizard />} />
            <Route
              path="/caregiver/questionnaire"
              element={
                <CaregiverRoute>
                  <CaregiverQuestionnairePage />
                </CaregiverRoute>
              }
            />
            <Route
              path="/caregiver/onboarding"
              element={
                <CaregiverRoute>
                  <CaregiverOnboardingPage />
                </CaregiverRoute>
              }
            />
            <Route
              path="/caregiver/onboarding/personal"
              element={
                <CaregiverRoute>
                  <CaregiverPersonalInfoPage />
                </CaregiverRoute>
              }
            />
            <Route
              path="/caregiver/dashboard"
              element={
                <CaregiverRoute>
                  <CaregiverDashboard />
                </CaregiverRoute>
              }
            />
            <Route
              path="/caregiver/profile"
              element={
                <CaregiverRoute>
                  <CaregiverProfilePage />
                </CaregiverRoute>
              }
            />
            <Route
              path="/caregiver/edit"
              element={<Navigate to="/caregiver/profile" replace />}
            />
            <Route
              path="/caregiver/calendar"
              element={
                <CaregiverRoute>
                  <CaregiverCalendarPage />
                </CaregiverRoute>
              }
            />
            <Route
              path="/caregiver/availability"
              element={
                <CaregiverRoute>
                  <CaregiverAvailabilityPage />
                </CaregiverRoute>
              }
            />
            <Route
              path="/caregiver/inbox"
              element={
                <CaregiverRoute>
                  <InboxPage />
                </CaregiverRoute>
              }
            />
            <Route
              path="/caregiver/reservations"
              element={
                <CaregiverRoute>
                  <CaregiverReservationsPage />
                </CaregiverRoute>
              }
            />
            <Route
              path="/caregiver/reservations/:id"
              element={
                <CaregiverRoute>
                  <CaregiverBookingDetailPage />
                </CaregiverRoute>
              }
            />
            <Route
              path="/caregiver/service/:id"
              element={
                <CaregiverRoute>
                  <ServiceExecutionPage />
                </CaregiverRoute>
              }
            />
            <Route
              path="/caregiver/payments"
              element={
                <CaregiverRoute>
                  <CaregiverPaymentsPage />
                </CaregiverRoute>
              }
            />
            <Route
              path="/admin/caregivers/pending"
              element={
                <AdminRoute>
                  <AdminPendingPage />
                </AdminRoute>
              }
            />
            <Route
              path="/admin/payments-pending"
              element={
                <AdminRoute>
                  <AdminPaymentsPendingPage />
                </AdminRoute>
              }
            />
            <Route
              path="/admin/reservations"
              element={
                <AdminRoute>
                  <AdminReservationsPage />
                </AdminRoute>
              }
            />
            <Route
              path="/admin/caregivers/:id/review"
              element={
                <AdminRoute>
                  <AdminCaregiverReviewPage />
                </AdminRoute>
              }
            />
            <Route
              path="/admin/verification/:id"
              element={
                <AdminRoute>
                  <AdminVerificationPage />
                </AdminRoute>
              }
            />
            <Route
              path="/admin/identity-reviews"
              element={
                <AdminRoute>
                  <AdminIdentityReviewsPage />
                </AdminRoute>
              }
            />
            <Route
              path="/admin/identity-reviews/:id"
              element={
                <AdminRoute>
                  <AdminVerificationPage />
                </AdminRoute>
              }
            />
            <Route
              path="/admin/caregivers"
              element={
                <AdminRoute>
                  <AdminCaregiversListPage />
                </AdminRoute>
              }
            />
          </Routes>
        </main>
      </div>
      <Toaster position="top-center" toastOptions={{ duration: 4000 }} />
    </AuthProvider>
  );
}
