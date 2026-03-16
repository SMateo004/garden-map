import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { UploadForm } from './UploadForm';

describe('UploadForm', () => {
  it('renders label and add button', () => {
    const onChange = vi.fn();
    render(<UploadForm value={[]} onChange={onChange} />);
    expect(screen.getByText(/Fotos \(4–6\)/)).toBeInTheDocument();
    expect(screen.getByText('+ Añadir')).toBeInTheDocument();
  });

  it('shows error when provided', () => {
    render(
      <UploadForm value={[]} onChange={vi.fn()} error="Se requieren entre 4 y 6 fotos" />
    );
    expect(screen.getByText('Se requieren entre 4 y 6 fotos')).toBeInTheDocument();
  });

  it('calls onChange when file is selected', () => {
    const onChange = vi.fn();
    const { container } = render(<UploadForm value={[]} onChange={onChange} />);
    const input = container.querySelector('input[type="file"]');
    expect(input).toBeInTheDocument();
    const file = new File(['x'], 'photo.jpg', { type: 'image/jpeg' });
    fireEvent.change(input!, { target: { files: [file] } });
    expect(onChange).toHaveBeenCalledWith([file]);
  });

  it('removes file when remove button clicked', () => {
    const file = new File(['x'], 'a.jpg', { type: 'image/jpeg' });
    const onChange = vi.fn();
    render(<UploadForm value={[file]} onChange={onChange} />);
    const removeBtn = screen.getByRole('button', { name: '×' });
    fireEvent.click(removeBtn);
    expect(onChange).toHaveBeenCalledWith([]);
  });
});
