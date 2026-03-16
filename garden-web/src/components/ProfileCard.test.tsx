import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { ProfileCard } from './ProfileCard';
import type { CaregiverListItem } from '@/types/caregiver';

const wrap = (ui: React.ReactElement) => (
  <BrowserRouter>{ui}</BrowserRouter>
);

const baseCaregiver: CaregiverListItem = {
  id: '1',
  firstName: 'María',
  lastName: 'López',
  profilePicture: null,
  zone: 'EQUIPETROL',
  services: ['HOSPEDAJE', 'PASEO'],
  rating: 4.8,
  reviewCount: 12,
  pricePerDay: 120,
  pricePerWalk30: 30,
  pricePerWalk60: 50,
  verified: false,
  spaceType: 'casa_patio',
};

describe('ProfileCard', () => {
  it('renders caregiver name and zone', () => {
    render(wrap(<ProfileCard caregiver={baseCaregiver} />));
    expect(screen.getByText('María López')).toBeInTheDocument();
    expect(screen.getByText(/Equipetrol/)).toBeInTheDocument();
  });

  it('does not render verified badge when verified is false', () => {
    render(wrap(<ProfileCard caregiver={baseCaregiver} />));
    expect(screen.queryByText('Verificado por GARDEN')).not.toBeInTheDocument();
  });

  it('renders verified badge when verified is true', () => {
    const verified = { ...baseCaregiver, verified: true };
    render(wrap(<ProfileCard caregiver={verified} />));
    expect(screen.getByText('Verificado por GARDEN')).toBeInTheDocument();
  });

  it('renders space type badge when spaceType is set', () => {
    render(wrap(<ProfileCard caregiver={baseCaregiver} />));
    expect(screen.getByText('Casa patio')).toBeInTheDocument();
  });

  it('renders rating and review count', () => {
    render(wrap(<ProfileCard caregiver={baseCaregiver} />));
    expect(screen.getByText(/★ 4.8/)).toBeInTheDocument();
    expect(screen.getByText(/12 reseñas/)).toBeInTheDocument();
  });

  it('links to caregiver detail page', () => {
    render(wrap(<ProfileCard caregiver={baseCaregiver} />));
    const link = screen.getByRole('link', { name: /María López/ });
    expect(link).toHaveAttribute('href', '/caregivers/1');
  });
});
