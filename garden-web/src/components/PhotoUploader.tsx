import { useCallback, useState } from 'react';
import { useDropzone } from 'react-dropzone';
import { getImageUrl } from '@/utils/images';

const MIN_FILES = 4;
const MAX_FILES = 6;
const MAX_SIZE_BYTES = 5 * 1024 * 1024;
const ACCEPT = { 'image/jpeg': ['.jpg', '.jpeg'], 'image/png': ['.png'] };

export interface PhotoUploaderProps {
  value: File[];
  onChange: (files: File[]) => void;
  disabled?: boolean;
  error?: string;
}

export function PhotoUploader({ value, onChange, disabled, error }: PhotoUploaderProps) {
  const [previews, setPreviews] = useState<Map<number, string>>(new Map());

  const revoke = useCallback((url: string) => {
    URL.revokeObjectURL(url);
  }, []);

  const addPreviews = useCallback((files: File[]) => {
    const next = new Map<number, string>();
    files.forEach((file, i) => {
      next.set(i, URL.createObjectURL(file));
    });
    setPreviews((prev) => {
      prev.forEach((url) => revoke(url));
      return next;
    });
  }, [revoke]);

  const onDrop = useCallback(
    (accepted: File[]) => {
      const total = [...value, ...accepted].slice(0, MAX_FILES);
      onChange(total);
      addPreviews(total);
    },
    [value, onChange, addPreviews]
  );

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: ACCEPT,
    maxSize: MAX_SIZE_BYTES,
    maxFiles: MAX_FILES - value.length,
    disabled,
    multiple: true,
  });

  const remove = useCallback(
    (index: number) => {
      const next = value.filter((_, i) => i !== index);
      const url = previews.get(index);
      if (url) {
        revoke(url);
        setPreviews((p) => {
          const m = new Map(p);
          m.delete(index);
          return m;
        });
      }
      onChange(next);
      addPreviews(next);
    },
    [value, onChange, previews, revoke, addPreviews]
  );

  const move = useCallback(
    (from: number, delta: number) => {
      const to = from + delta;
      if (to < 0 || to >= value.length) return;
      const next = [...value];
      const [f] = next.splice(from, 1);
      next.splice(to, 0, f);
      onChange(next);
      addPreviews(next);
    },
    [value, onChange, addPreviews]
  );

  return (
    <div className="space-y-2">
      <label className="block text-sm font-medium text-gray-700">
        Fotos reales (casa/patio + cuidador con mascota si tienes)
      </label>
      <p className="text-xs text-gray-500">
        Entre {MIN_FILES} y {MAX_FILES} fotos. JPG o PNG, máx. 5 MB cada una.
      </p>

      <div
        {...getRootProps()}
        className={`rounded-xl border-2 border-dashed p-4 text-center transition-colors ${
          isDragActive ? 'border-green-500 bg-green-50' : 'border-gray-300 bg-gray-50 hover:border-green-400 hover:bg-green-50/50'
        } ${disabled ? 'pointer-events-none opacity-60' : 'cursor-pointer'}`}
      >
        <input {...getInputProps()} />
        <span className="text-sm text-gray-600">
          {isDragActive ? 'Suelta aquí' : 'Arrastra fotos o haz clic para seleccionar'}
        </span>
      </div>

      {value.length > 0 && (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
          {value.map((file, i) => (
            <div
              key={`${file.name}-${i}`}
              className="group relative aspect-square overflow-hidden rounded-lg border border-gray-200 bg-gray-100"
            >
              <img
                src={getImageUrl(previews.get(i))}
                alt={`Preview ${i + 1}`}
                loading="lazy"
                className="h-full w-full object-cover"
              />
              <div className="absolute inset-0 flex items-center justify-center gap-1 bg-black/40 opacity-0 transition-opacity group-hover:opacity-100">
                <button
                  type="button"
                  onClick={() => move(i, -1)}
                  disabled={i === 0 || disabled}
                  className="rounded bg-white/90 px-2 py-1 text-xs font-medium text-gray-800 disabled:opacity-50"
                >
                  ←
                </button>
                <button
                  type="button"
                  onClick={() => remove(i)}
                  disabled={disabled}
                  className="rounded bg-red-500 px-2 py-1 text-xs font-medium text-white hover:bg-red-600"
                >
                  Eliminar
                </button>
                <button
                  type="button"
                  onClick={() => move(i, 1)}
                  disabled={i === value.length - 1 || disabled}
                  className="rounded bg-white/90 px-2 py-1 text-xs font-medium text-gray-800 disabled:opacity-50"
                >
                  →
                </button>
              </div>
              <span className="absolute bottom-0 left-0 right-0 bg-black/60 py-0.5 text-center text-xs text-white">
                {i + 1} / {value.length}
              </span>
            </div>
          ))}
        </div>
      )}

      {error && <p className="text-sm text-red-600">{error}</p>}
    </div>
  );
}
