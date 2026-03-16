import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';

vi.mock('react-hot-toast', () => ({ default: { success: vi.fn(), error: vi.fn() } }));
const mockNavigate = vi.fn();
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return { ...actual, useNavigate: () => mockNavigate };
});
vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ login: vi.fn(), isCaregiver: false }),
}));

import { CaregiverAuthPage } from './CaregiverAuthPage';

function renderAuth() {
  return render(
    <MemoryRouter>
      <CaregiverAuthPage />
    </MemoryRouter>
  );
}

describe('CaregiverAuthPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows login and register tabs', () => {
    renderAuth();
    const tabs = screen.getAllByRole('button', { name: /Iniciar sesión|Registrarme/i });
    expect(tabs.some((b) => b.textContent === 'Iniciar sesión')).toBe(true);
    expect(tabs.some((b) => b.textContent === 'Registrarme')).toBe(true);
  });

  it('shows login form by default', () => {
    renderAuth();
    expect(screen.getByPlaceholderText(/tucorreo@email\.com/)).toBeInTheDocument();
    expect(screen.getByLabelText(/Email/)).toBeInTheDocument();
    const loginButtons = screen.getAllByRole('button', { name: /Iniciar sesión/i });
    expect(loginButtons.some((b) => b.getAttribute('type') === 'submit')).toBe(true);
  });

  it('switches to register tab and shows Comenzar registro', () => {
    renderAuth();
    fireEvent.click(screen.getByRole('button', { name: /Registrarme/i }));
    expect(screen.getByRole('button', { name: /Comenzar registro/i })).toBeInTheDocument();
  });

  it('navigates to /caregiver/register when Comenzar registro is clicked', () => {
    renderAuth();
    fireEvent.click(screen.getByRole('button', { name: /Registrarme/i }));
    fireEvent.click(screen.getByRole('button', { name: /Comenzar registro/i }));
    expect(mockNavigate).toHaveBeenCalledWith('/caregiver/register');
  });
});
