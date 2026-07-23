/**
 * Hospedaje y Guardería comparten UN solo cupo simultáneo (no uno cada uno) —
 * si el cuidador ofrece ambos, atenderlos a la vez consume el mismo pool de
 * mascotas. Paseo queda completamente aparte, con su propio cupo.
 *
 * La UI (caregiver_profile_data_screen.dart) ya guarda el mismo número en
 * maxPetsHospedaje y maxPetsGuarderia (un solo stepper "Hospedaje +
 * Guardería"), así que cualquiera de los dos sirve como el cupo combinado —
 * se prioriza maxPetsHospedaje por convención, con fallback al otro y al
 * legado maxPets para perfiles viejos que aún no se resguardaron con el
 * campo nuevo.
 */
export function combinedHospedajeGuarderiaMax(profile: {
  maxPetsHospedaje?: number | null;
  maxPetsGuarderia?: number | null;
  maxPets?: number | null;
}): number {
  return profile.maxPetsHospedaje ?? profile.maxPetsGuarderia ?? profile.maxPets ?? 1;
}
