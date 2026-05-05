import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
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

// Mock checkEmailExists: returns false by default (new user)
vi.mock('@/api/auth', () => ({
  checkEmailExists: vi.fn().mockResolvedValue(false),
}));

import { CaregiverAuthPage } from './CaregiverAuthPage';
import * as authApi from '@/api/auth';

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
    (authApi.checkEmailExists as ReturnType<typeof vi.fn>).mockResolvedValue(false);
  });

  it('shows email input and Continuar button by default', () => {
    renderAuth();
    expect(screen.getByPlaceholderText(/tucorreo@email\.com/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Continuar/i })).toBeInTheDocument();
  });

  it('navigates to /caregiver/register when email does not exist', async () => {
    (authApi.checkEmailExists as ReturnType<typeof vi.fn>).mockResolvedValue(false);
    renderAuth();
    fireEvent.change(screen.getByPlaceholderText(/tucorreo@email\.com/), {
      target: { value: 'nuevo@test.com' },
    });
    fireEvent.submit(screen.getByRole('button', { name: /Continuar/i }).closest('form')!);
    await waitFor(() => {
      expect(mockNavigate).toHaveBeenCalledWith('/caregiver/register', expect.anything());
    });
  });

  it('shows password field when email exists', async () => {
    (authApi.checkEmailExists as ReturnType<typeof vi.fn>).mockResolvedValue(true);
    renderAuth();
    fireEvent.change(screen.getByPlaceholderText(/tucorreo@email\.com/), {
      target: { value: 'existente@test.com' },
    });
    fireEvent.submit(screen.getByRole('button', { name: /Continuar/i }).closest('form')!);
    await waitFor(() => {
      expect(screen.getByPlaceholderText(/••••••••/)).toBeInTheDocument();
    });
  });

  it('shows GARDEN header', () => {
    renderAuth();
    expect(screen.getByText('GARDEN')).toBeInTheDocument();
  });
});
