import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ErrorBoundary } from './ErrorBoundary';

const Throw = () => {
  throw new Error('Test error');
};

describe('ErrorBoundary', () => {
  it('renders children when no error', () => {
    render(
      <ErrorBoundary>
        <span>Child</span>
      </ErrorBoundary>
    );
    expect(screen.getByText('Child')).toBeInTheDocument();
  });

  it('renders fallback when child throws', () => {
    const onError = vi.fn();
    render(
      <ErrorBoundary onError={onError} fallback={<div>Custom fallback</div>}>
        <Throw />
      </ErrorBoundary>
    );
    expect(screen.getByText('Custom fallback')).toBeInTheDocument();
    expect(onError).toHaveBeenCalledWith(expect.any(Error), expect.any(Object));
  });

  it('renders default error UI with message and Reintentar button', () => {
    render(
      <ErrorBoundary>
        <Throw />
      </ErrorBoundary>
    );
    expect(screen.getByText('Algo salió mal')).toBeInTheDocument();
    expect(screen.getByText('Test error')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Reintentar' })).toBeInTheDocument();
  });
});
