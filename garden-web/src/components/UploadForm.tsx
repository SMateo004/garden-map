import { useCallback, type ChangeEvent } from 'react';

const MAX_FILES = 6;
const MIN_FILES = 4;
const MAX_SIZE_MB = 5;
const ACCEPT = 'image/jpeg,image/png,image/webp';

export interface UploadFormProps {
  value: File[];
  onChange: (files: File[]) => void;
  maxFiles?: number;
  minFiles?: number;
  accept?: string;
  disabled?: boolean;
  error?: string;
}

export function UploadForm({
  value,
  onChange,
  maxFiles = MAX_FILES,
  minFiles = MIN_FILES,
  accept = ACCEPT,
  disabled,
  error,
}: UploadFormProps) {
  const handleChange = useCallback(
    (e: ChangeEvent<HTMLInputElement>) => {
      const files = Array.from(e.target.files ?? []);
      const valid: File[] = [];
      for (const f of files.slice(0, maxFiles)) {
        if (f.size <= MAX_SIZE_MB * 1024 * 1024) valid.push(f);
      }
      onChange(valid);
      e.target.value = '';
    },
    [onChange, maxFiles]
  );

  const remove = useCallback(
    (index: number) => {
      const next = value.filter((_, i) => i !== index);
      onChange(next);
    },
    [value, onChange]
  );

  return (
    <div className="space-y-2">
      <label className="block text-sm font-medium text-gray-700">
        Fotos ({minFiles}–{maxFiles})
      </label>
      <div className="flex flex-wrap gap-2">
        {value.map((file, i) => (
          <div
            key={`${file.name}-${i}`}
            className="relative flex h-20 w-20 items-center justify-center rounded-lg border border-gray-200 bg-gray-50 text-xs text-gray-600"
          >
            {file.name}
            <button
              type="button"
              onClick={() => remove(i)}
              disabled={disabled}
              className="absolute -right-1 -top-1 rounded-full bg-red-500 px-1.5 py-0.5 text-white hover:bg-red-600 disabled:opacity-50"
            >
              ×
            </button>
          </div>
        ))}
        {value.length < maxFiles && (
          <label className="flex h-20 w-20 cursor-pointer items-center justify-center rounded-lg border-2 border-dashed border-gray-300 bg-gray-50 text-sm text-gray-500 hover:border-green-400 hover:bg-green-50">
            <input
              type="file"
              accept={accept}
              multiple
              onChange={handleChange}
              disabled={disabled}
              className="hidden"
            />
            + Añadir
          </label>
        )}
      </div>
      {error && <p className="text-sm text-red-600">{error}</p>}
      <p className="text-xs text-gray-500">JPEG, PNG o WebP. Máx. {MAX_SIZE_MB} MB por imagen.</p>
    </div>
  );
}
