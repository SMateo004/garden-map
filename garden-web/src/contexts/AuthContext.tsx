import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { api, getStoredToken, clearStoredToken, AUTH_UNAUTHORIZED_EVENT } from '@/api/client';
import * as authApi from '@/api/auth';
import type { AuthUser } from '@/api/auth';

interface AuthState {
  user: AuthUser | null;
  token: string | null;
  isLoading: boolean;
}

interface AuthContextValue extends AuthState {
  login: (email: string, password: string, roleCaregiverOnly?: boolean) => Promise<AuthUser | undefined>;
  logout: () => void;
  refreshUser: () => Promise<void>;
  isCaregiver: boolean;
  isAdmin: boolean;
  isAuthenticated: boolean;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthState>({
    user: null,
    token: getStoredToken(),
    isLoading: true,
  });

  const loadUser = useCallback(async (): Promise<AuthUser | null> => {
    const token = getStoredToken();
    if (!token) {
      setState((s) => ({ ...s, user: null, token: null, isLoading: false }));
      return null;
    }
    try {
      const res = await api.get<{ success: boolean; data?: AuthUser }>('/api/auth/me', {
        validateStatus: (status) => status === 200 || status === 401,
      });
      if (res.status === 401) {
        clearStoredToken();
        setState((s) => ({ ...s, user: null, token: null, isLoading: false }));
        return null;
      }
      if (res.data?.success && res.data?.data) {
        const user = res.data.data;
        setState((s) => ({ ...s, user, token, isLoading: false }));
        return user;
      }
      setState((s) => ({ ...s, user: null, token: null, isLoading: false }));
      return null;
    } catch (error) {
      setState((s) => ({ ...s, user: null, token: null, isLoading: false }));
      console.error('Error al cargar usuario:', error);
      return null;
    }
  }, []);

  useEffect(() => {
    if (!state.token) {
      setState((s) => ({ ...s, isLoading: false }));
      return;
    }
    loadUser();
  }, [state.token, loadUser]);

  const login = useCallback(
    async (email: string, password: string, roleCaregiverOnly = false) => {
      await authApi.login(email, password, roleCaregiverOnly);
      const user = await loadUser();
      return user ?? undefined;
    },
    [loadUser]
  );

  const logout = useCallback(() => {
    authApi.logout();
    setState({ user: null, token: null, isLoading: false });
  }, []);

  useEffect(() => {
    const onUnauthorized = () => {
      setState((s) => (s.token ? { ...s, user: null, token: null, isLoading: false } : s));
    };
    window.addEventListener(AUTH_UNAUTHORIZED_EVENT, onUnauthorized);
    return () => window.removeEventListener(AUTH_UNAUTHORIZED_EVENT, onUnauthorized);
  }, []);

  const refreshUser = useCallback(async () => {
    await loadUser();
  }, [loadUser]);

  const value = useMemo<AuthContextValue>(
    () => ({
      ...state,
      login,
      logout,
      refreshUser,
      isCaregiver: state.user?.role === 'CAREGIVER',
      isAdmin: state.user?.role === 'ADMIN',
      isAuthenticated: Boolean(state.user && state.token),
    }),
    [state, login, logout, refreshUser]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
