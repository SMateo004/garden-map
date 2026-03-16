import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { Badge } from './Badge';

describe('Badge', () => {
  it('renders children', () => {
    render(<Badge>Verificado</Badge>);
    expect(screen.getByText('Verificado')).toBeInTheDocument();
  });

  it('applies verified variant class', () => {
    render(<Badge variant="verified">Verificado por GARDEN</Badge>);
    const el = screen.getByText('Verificado por GARDEN');
    expect(el).toHaveClass('bg-green-100', 'text-green-800');
  });

  it('applies muted variant class', () => {
    render(<Badge variant="muted">Zona</Badge>);
    const el = screen.getByText('Zona');
    expect(el).toHaveClass('bg-gray-50', 'text-gray-500');
  });

  it('applies default variant when not specified', () => {
    render(<Badge>Default</Badge>);
    const el = screen.getByText('Default');
    expect(el).toHaveClass('bg-gray-100', 'text-gray-800');
  });
});
