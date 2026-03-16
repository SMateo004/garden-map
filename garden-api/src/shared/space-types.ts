/**
 * Opciones de tipo de espacio para cuidadores (multi-select).
 * Solo aplica si el cuidador ofrece servicio HOSPEDAJE.
 */
export const SPACE_TYPE_OPTIONS = [
  'Casa con patio',
  'Casa sin patio',
  'Departamento pequeño',
  'Departamento amplio',
] as const;

export type SpaceTypeOption = (typeof SPACE_TYPE_OPTIONS)[number];

/**
 * Valores para query params (lowercase, snake_case).
 * Mapeo: valor display → query param
 */
export const SPACE_TYPE_QUERY_MAP: Record<SpaceTypeOption, string> = {
  'Casa con patio': 'casa_con_patio',
  'Casa sin patio': 'casa_sin_patio',
  'Departamento pequeño': 'departamento_pequeno',
  'Departamento amplio': 'departamento_amplio',
};

/**
 * Mapeo inverso: query param → valor display
 */
export const SPACE_TYPE_QUERY_TO_DISPLAY: Record<string, SpaceTypeOption> = {
  casa_con_patio: 'Casa con patio',
  casa_sin_patio: 'Casa sin patio',
  departamento_pequeno: 'Departamento pequeño',
  departamento_amplio: 'Departamento amplio',
};
