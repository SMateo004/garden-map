import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AuthProvider } from '@/contexts/AuthContext';

vi.mock('react-hot-toast', () => ({ default: { success: vi.fn(), error: vi.fn() } }));
vi.mock('@/api/auth', () => ({ registerCaregiver: vi.fn(), uploadRegistrationPhotos: vi.fn() }));

import { RegisterWizard } from './RegisterWizard';

function renderWizard() {
  return render(
    <AuthProvider>
      <MemoryRouter>
        <RegisterWizard />
      </MemoryRouter>
    </AuthProvider>
  );
}

// Step 1 now includes dateOfBirth and uses a different phone placeholder
function fillStep1() {
  fireEvent.change(screen.getByPlaceholderText(/Tu nombre/), { target: { value: 'Juan' } });
  fireEvent.change(screen.getByPlaceholderText(/Tu apellido/), { target: { value: 'Pérez' } });
  // Phone placeholder: "71234567 (8 dígitos, empieza con 6 o 7)"
  fireEvent.change(screen.getByPlaceholderText(/71234567/), { target: { value: '71234567' } });
  // dateOfBirth input is labelled "Fecha de nacimiento *"
  const dobInput = document.querySelector('input[type="date"]') as HTMLInputElement | null;
  if (dobInput) fireEvent.change(dobInput, { target: { value: '1990-05-15' } });
}

function goNext() {
  fireEvent.click(screen.getByRole('button', { name: /Siguiente/ }));
}

const storage: Record<string, string> = {};
const localStorageMock = {
  getItem: (key: string) => storage[key] ?? null,
  setItem: (key: string, value: string) => { storage[key] = value; },
  removeItem: (key: string) => { delete storage[key]; },
  clear: () => { for (const k of Object.keys(storage)) delete storage[k]; },
  get length() { return Object.keys(storage).length; },
  key: () => null,
};

describe('RegisterWizard', () => {
  beforeEach(() => {
    Object.defineProperty(window, 'localStorage', { value: localStorageMock, writable: true });
    localStorage.clear();
    localStorage.removeItem('garden_wizard_draft');
    vi.clearAllMocks();
  });

  it('shows step 1 and progress', () => {
    renderWizard();
    expect(screen.getByText(/Paso 1 de 10/)).toBeInTheDocument();
    expect(screen.getByText(/Tu nombre/)).toBeInTheDocument();
    expect(screen.getByPlaceholderText(/Tu nombre/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Siguiente/ })).toBeInTheDocument();
  });

  it('advances to step 2 when step 1 is valid', () => {
    renderWizard();
    fillStep1();
    goNext();
    expect(screen.getByText(/Paso 2 de 10/)).toBeInTheDocument();
    expect(screen.getByText(/Tu cuenta GARDEN/)).toBeInTheDocument();
  });

  it('does not advance from step 1 when required fields are empty', () => {
    renderWizard();
    goNext();
    expect(screen.getByText(/Paso 1 de 10/)).toBeInTheDocument();
  });

  it('shows Atrás on step 2', () => {
    renderWizard();
    fillStep1();
    goNext();
    expect(screen.getByRole('button', { name: /Atrás/ })).toBeInTheDocument();
  });

  it('does not advance from step 2 when passwords do not match', () => {
    renderWizard();
    fillStep1();
    goNext();
    fireEvent.change(screen.getByPlaceholderText(/tucorreo@email\.com/), { target: { value: 'a@b.co' } });
    fireEvent.change(screen.getByPlaceholderText(/Mínimo 8 caracteres/), { target: { value: 'password123' } });
    fireEvent.change(screen.getByPlaceholderText(/Repite tu contraseña/), { target: { value: 'other456' } });
    goNext();
    expect(screen.getByText(/Paso 2 de 10/)).toBeInTheDocument();
  });

  it('advances to step 3 when step 2 valid', () => {
    renderWizard();
    fillStep1();
    goNext();
    fireEvent.change(screen.getByPlaceholderText(/tucorreo@email\.com/), { target: { value: 'a@b.co' } });
    fireEvent.change(screen.getByPlaceholderText(/Mínimo 8 caracteres/), { target: { value: 'password123' } });
    fireEvent.change(screen.getByPlaceholderText(/Repite tu contraseña/), { target: { value: 'password123' } });
    goNext();
    expect(screen.getByText(/Paso 3 de 10/)).toBeInTheDocument();
  });

  it('step 4 requires at least one service', () => {
    renderWizard();
    fillStep1();
    goNext();
    fireEvent.change(screen.getByPlaceholderText(/tucorreo@email\.com/), { target: { value: 'a@b.co' } });
    fireEvent.change(screen.getByPlaceholderText(/Mínimo 8 caracteres/), { target: { value: 'password123' } });
    fireEvent.change(screen.getByPlaceholderText(/Repite tu contraseña/), { target: { value: 'password123' } });
    goNext();
    fireEvent.click(screen.getByText(/Equipetrol/));
    goNext();
    expect(screen.getByText(/Paso 4 de 10/)).toBeInTheDocument();
    goNext(); // no service selected → should stay on step 4
    expect(screen.getByText(/Paso 4 de 10/)).toBeInTheDocument();
  });

  it('step 5 requires at least 50 chars in bio', () => {
    renderWizard();
    fillStep1();
    goNext();
    fireEvent.change(screen.getByPlaceholderText(/tucorreo@email\.com/), { target: { value: 'a@b.co' } });
    fireEvent.change(screen.getByPlaceholderText(/Mínimo 8 caracteres/), { target: { value: 'password123' } });
    fireEvent.change(screen.getByPlaceholderText(/Repite tu contraseña/), { target: { value: 'password123' } });
    goNext();
    fireEvent.click(screen.getByText(/Equipetrol/));
    goNext();
    fireEvent.click(screen.getByText(/Hospedaje/));
    goNext();
    fireEvent.change(screen.getByPlaceholderText(/Tengo 2 labradores/), { target: { value: 'short' } });
    goNext();
    expect(screen.getByText(/Paso 5 de 10/)).toBeInTheDocument();
  });
});
