import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { PhotoUploader } from './PhotoUploader';

describe('PhotoUploader', () => {
  it('renders label and dropzone hint', () => {
    render(<PhotoUploader value={[]} onChange={vi.fn()} />);
    expect(screen.getByText(/Fotos reales/)).toBeInTheDocument();
    expect(screen.getByText(/Entre 4 y 6 fotos/)).toBeInTheDocument();
    expect(screen.getByText(/Arrastra fotos o haz clic/)).toBeInTheDocument();
  });

  it('shows error when provided', () => {
    render(
      <PhotoUploader value={[]} onChange={vi.fn()} error="Mínimo 4 fotos" />
    );
    expect(screen.getByText('Mínimo 4 fotos')).toBeInTheDocument();
  });

  it('calls onChange when files are removed', () => {
    const files = Array(5).fill(null).map((_, i) => new File(['x'], `p${i}.jpg`, { type: 'image/jpeg' }));
    const onChange = vi.fn();
    render(<PhotoUploader value={files} onChange={onChange} />);
    const removeButtons = screen.getAllByText('Eliminar');
    expect(removeButtons.length).toBeGreaterThanOrEqual(1);
    fireEvent.click(removeButtons[0]);
    expect(onChange).toHaveBeenCalledWith(expect.any(Array));
    expect(onChange.mock.calls[0][0]).toHaveLength(4);
  });

  it('displays preview count for each photo', () => {
    const files = [
      new File(['a'], 'a.jpg', { type: 'image/jpeg' }),
      new File(['b'], 'b.jpg', { type: 'image/jpeg' }),
    ];
    render(<PhotoUploader value={files} onChange={vi.fn()} />);
    expect(screen.getByText('1 / 2')).toBeInTheDocument();
  });
});
