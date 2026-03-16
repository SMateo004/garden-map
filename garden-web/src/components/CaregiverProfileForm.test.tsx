import { describe, it, expect } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { CaregiverProfileForm } from './CaregiverProfileForm';

function wrap(ui: React.ReactElement) {
  const client = new QueryClient({ defaultOptions: { mutations: { retry: false } } });
  return (
    <QueryClientProvider client={client}>
      {ui}
    </QueryClientProvider>
  );
}

describe('CaregiverProfileForm', () => {
  it('renders form with bio, zone, spaceType, services and submit button', () => {
    render(wrap(<CaregiverProfileForm />));
    expect(screen.getByText(/Descripción \(bio\)/)).toBeInTheDocument();
    expect(screen.getByText(/Zona \*/)).toBeInTheDocument();
    expect(screen.getByText(/Tipo de espacio/)).toBeInTheDocument();
    expect(screen.getByText(/Servicios que ofreces/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Enviar perfil/i })).toBeInTheDocument();
  });

  it('submit button is present and not disabled initially', () => {
    render(wrap(<CaregiverProfileForm />));
    const btn = screen.getByRole('button', { name: /Enviar perfil/i });
    expect(btn).toBeInTheDocument();
    expect(btn).not.toBeDisabled();
  });

  it('shows validation error for empty bio on submit', async () => {
    const { container } = render(wrap(<CaregiverProfileForm />));
    const submit = screen.getByRole('button', { name: /Enviar perfil/i });
    fireEvent.click(submit);
    await waitFor(() => {
      const errorParagraphs = container.querySelectorAll('p.text-red-600');
      expect(errorParagraphs.length).toBeGreaterThan(0);
      const text = Array.from(errorParagraphs).map((p) => p.textContent).join(' ');
      expect(text).toMatch(/La descripción es obligatoria|Elige una zona|Elige al menos un servicio/i);
    });
  });

  it('renders zone select with options', () => {
    render(wrap(<CaregiverProfileForm />));
    const comboboxes = screen.getAllByRole('combobox');
    expect(comboboxes.length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText(/Equipetrol/)).toBeInTheDocument();
  });
});
