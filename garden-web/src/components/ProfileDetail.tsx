import { useMemo } from 'react';
import { Badge } from '@/components/ui/Badge';
import { sanitizeBio } from '@/utils/sanitize';
import type { CaregiverDetail, Zone } from '@/types/caregiver';
import { ZONE_LABELS, SPACE_TYPE_QUERY_TO_DISPLAY } from '@/types/caregiver';
import { getImageUrl } from '@/utils/images';

interface ProfileDetailProps {
  caregiver: CaregiverDetail;
}

function formatZone(zone?: string | null): string {
  if (zone == null || typeof zone !== 'string') return 'Zona no especificada';
  const trimmed = zone.trim();
  if (!trimmed) return 'Zona no especificada';
  if (trimmed in ZONE_LABELS) return ZONE_LABELS[trimmed as Zone];
  return trimmed.charAt(0).toUpperCase() + trimmed.slice(1).replace(/_/g, ' ');
}

function formatDate(d: string): string {
  return new Date(d).toLocaleDateString('es-BO', { day: 'numeric', month: 'short', year: 'numeric' });
}

export function ProfileDetail({ caregiver }: ProfileDetailProps) {
  const name = `${caregiver.firstName} ${caregiver.lastName}`;
  const safeBio = useMemo(() => sanitizeBio(caregiver.bio ?? ''), [caregiver.bio]);

  // Galería de fotos del cuidador (sin la de perfil si ya se usa como avatar)
  const galleryPhotos = useMemo(() => {
    return caregiver.photos || [];
  }, [caregiver.photos]);

  return (
    <article className="mx-auto max-w-5xl space-y-12">
      {/* HEADER PREMIUM REFINADO: Foto de perfil, nombre, zona y calificación */}
      <div className="bg-white dark:bg-gray-800 rounded-3xl p-6 shadow-lg border border-gray-100 dark:border-gray-700 flex flex-col md:flex-row items-center gap-6 animate-in fade-in slide-in-from-bottom-4 duration-500">
        <div className="relative group shrink-0">
          <div className="absolute -inset-1 bg-gradient-to-r from-green-400 to-green-600 rounded-full blur opacity-15 group-hover:opacity-30 transition duration-1000"></div>
          <img
            src={getImageUrl(caregiver.profilePicture)}
            alt={name}
            className="relative h-32 w-32 rounded-full object-cover border-4 border-white dark:border-gray-700 shadow-md"
          />
          {caregiver.verified && (
            <div className="absolute bottom-1 right-1 bg-green-500 text-white p-1 rounded-full border-2 border-white dark:border-gray-800 shadow-sm">
              <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" />
              </svg>
            </div>
          )}
        </div>

        <div className="flex-1 text-center md:text-left space-y-3">
          <div className="space-y-0.5">
            <h1 className="text-3xl font-black text-gray-900 dark:text-white tracking-tight leading-none">{name}</h1>
            <div className="flex flex-wrap justify-center md:justify-start items-center gap-2 mt-1">
              <Badge variant="muted" className="bg-slate-50 dark:bg-slate-700 text-slate-500 dark:text-slate-200 font-bold px-2 py-0.5 text-[10px] uppercase tracking-wider border border-slate-100 dark:border-slate-600">
                {formatZone(caregiver.zone)}
              </Badge>
              {caregiver.verified && (
                <Badge variant="verified" className="text-[10px] font-bold uppercase tracking-wider py-0.5">Verificado</Badge>
              )}
            </div>
          </div>

          <div className="flex flex-wrap justify-center md:justify-start items-center gap-5">
            <div className="flex flex-col items-center md:items-start">
              <span className="text-2xl font-black text-amber-500 flex items-center gap-0.5">
                {caregiver.rating > 0 ? caregiver.rating.toFixed(1) : 'Nuevo'}
                <svg className="h-6 w-6" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                </svg>
              </span>
              <span className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{caregiver.reviewCount} Reseñas</span>
            </div>

            <div className="h-8 w-px bg-gray-100 dark:bg-gray-700 hidden sm:block"></div>

            {caregiver.blockchainReputation && (
              <>
                <div className="flex flex-col items-center md:items-start">
                  <span className="text-2xl font-black text-blue-600 flex items-center gap-0.5">
                    {caregiver.blockchainReputation.average.toFixed(1)}
                    <svg className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                      <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                    </svg>
                  </span>
                  <span className="text-[10px] font-bold text-blue-400 uppercase tracking-widest flex items-center gap-1">
                    <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                    </svg>
                    Blockchain Verified
                  </span>
                </div>
                <div className="h-8 w-px bg-gray-100 dark:bg-gray-700 hidden sm:block"></div>
              </>
            )}

            <div className="flex flex-col items-center md:items-start text-gray-400 font-medium">
              <span className="text-xs uppercase font-black tracking-widest">Servicio</span>
              <span className="text-base font-bold text-gray-700 dark:text-gray-200">
                {caregiver.services.length === 2 ? 'Hospedaje y Paseos' : caregiver.services[0] === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseador experto'}
              </span>
            </div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* COLUMNA IZQUIERDA: Bio y Detalles */}
        <div className="lg:col-span-2 space-y-8">
          <section className="bg-white dark:bg-gray-800 rounded-3xl p-8 shadow-sm border border-gray-100 dark:border-gray-700">
            <h2 className="text-2xl font-black text-gray-900 dark:text-white mb-6 flex items-center gap-3">
              <span className="w-2 h-8 bg-green-500 rounded-full"></span>
              Sobre mí
            </h2>
            <div
              className="mt-1 text-gray-600 dark:text-gray-300 whitespace-pre-wrap leading-relaxed text-lg"
              dangerouslySetInnerHTML={{ __html: safeBio }}
            />
            {caregiver.bioDetail && (
              <p className="mt-4 text-gray-500 dark:text-gray-400 leading-relaxed italic border-l-4 border-gray-100 dark:border-gray-700 pl-4 py-1">
                {caregiver.bioDetail}
              </p>
            )}
          </section>

          {/* SECCIÓN EXPERIENCIA */}
          <section className="bg-white dark:bg-gray-800 rounded-3xl p-8 shadow-sm border border-gray-100 dark:border-gray-700">
            <h2 className="text-2xl font-black text-gray-900 dark:text-white mb-6 flex items-center gap-3">
              <span className="w-2 h-8 bg-green-500 rounded-full"></span>
              Mi experiencia
            </h2>
            <div className="space-y-8">
              <div className="flex flex-wrap gap-8">
                <div>
                  <h3 className="text-xs font-black text-gray-400 uppercase tracking-widest mb-2">Años de experiencia</h3>
                  <Badge variant="muted" className="bg-green-50 dark:bg-green-900/20 text-green-600 dark:text-green-400 font-black px-4 py-2 text-sm uppercase rounded-xl border border-green-100 dark:border-green-900/30">
                    {caregiver.experienceYears === 'NEVER' ? 'Empezando en GARDEN' :
                      caregiver.experienceYears === 'LESS1' ? 'Menos de 1 año' :
                        caregiver.experienceYears === 'ONE_TO_FIVE' ? 'De 1 a 5 años' :
                          caregiver.experienceYears === 'MORE5' ? 'Más de 5 años' : 'Experiencia certificada'}
                  </Badge>
                </div>

                {caregiver.animalTypes && caregiver.animalTypes.length > 0 && (
                  <div>
                    <h3 className="text-xs font-black text-gray-400 uppercase tracking-widest mb-2">Tipos de animal</h3>
                    <div className="flex flex-wrap gap-2">
                      {caregiver.animalTypes.map(type => (
                        <Badge key={type} className="bg-slate-100 dark:bg-slate-700 text-slate-700 dark:text-slate-200 border-slate-200 dark:border-slate-600 px-3 py-1 font-bold text-[10px] uppercase">
                          {type === 'DOGS' ? 'Perros' :
                            type === 'CATS' ? 'Gatos' :
                              type === 'PUPPIES' ? 'Cachorros' :
                                type === 'SENIORS' ? 'Seniors' :
                                  type === 'LARGE' ? 'Grandes' :
                                    type === 'SMALL' ? 'Pequeños' : 'Otros'}
                        </Badge>
                      ))}
                    </div>
                  </div>
                )}
              </div>

              {caregiver.experienceDescription && (
                <div>
                  <h3 className="text-xs font-black text-gray-400 uppercase tracking-widest mb-2">Descripción de la experiencia</h3>
                  <p className="text-gray-600 dark:text-gray-300 leading-relaxed text-lg">
                    {caregiver.experienceDescription}
                  </p>
                </div>
              )}

              <div className="grid grid-cols-1 md:grid-cols-2 gap-8 pt-6 border-t border-gray-50 dark:border-gray-700">
                {caregiver.whyCaregiver && (
                  <div>
                    <h3 className="text-xs font-black text-gray-400 uppercase tracking-widest mb-2">¿Por qué es cuidador?</h3>
                    <p className="text-sm text-gray-600 dark:text-gray-400 leading-relaxed italic border-l-4 border-slate-50 pl-4">
                      "{caregiver.whyCaregiver}"
                    </p>
                  </div>
                )}
                {caregiver.whatDiffers && (
                  <div>
                    <h3 className="text-xs font-black text-gray-400 uppercase tracking-widest mb-2">¿Qué le diferencia?</h3>
                    <p className="text-sm text-gray-600 dark:text-gray-400 leading-relaxed italic border-l-4 border-slate-50 pl-4">
                      "{caregiver.whatDiffers}"
                    </p>
                  </div>
                )}
              </div>
            </div>
          </section>

          {/* SECCIÓN PREFERENCIAS Y SALUD */}
          <section className="bg-white dark:bg-gray-800 rounded-3xl p-8 shadow-sm border border-gray-100 dark:border-gray-700">
            <h2 className="text-2xl font-black text-gray-900 dark:text-white mb-6 flex items-center gap-3">
              <span className="w-2 h-8 bg-green-500 rounded-full"></span>
              Preferencias y Salud
            </h2>

            <div className="space-y-8">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
                <div>
                  <h3 className="text-xs font-black text-gray-400 uppercase tracking-widest mb-3">Tamaños aceptados</h3>
                  <div className="flex flex-wrap gap-2">
                    {caregiver.sizesAccepted?.map(size => (
                      <Badge key={size} className="bg-amber-50 text-amber-700 border-amber-100 px-3 py-1 font-bold text-[10px] uppercase">
                        {size === 'SMALL' ? 'Pequeño' : size === 'MEDIUM' ? 'Mediano' : size === 'LARGE' ? 'Grande' : 'Gigante'}
                      </Badge>
                    ))}
                  </div>
                </div>

                {caregiver.acceptMedication && caregiver.acceptMedication.length > 0 && (
                  <div>
                    <h3 className="text-xs font-black text-gray-400 uppercase tracking-widest mb-3">Administración de medicación</h3>
                    <div className="flex flex-wrap gap-2">
                      {caregiver.acceptMedication.map(med => (
                        <Badge key={med} className="bg-blue-50 text-blue-700 border-blue-100 px-3 py-1 font-bold text-[10px] uppercase">
                          {med === 'ORAL' ? 'Oral (Pastillas/Líquido)' : med === 'INJECT' ? 'Inyectable' : 'Tópica (Cremas)'}
                        </Badge>
                      ))}
                    </div>
                  </div>
                )}
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                <div className={`p-4 rounded-2xl border flex flex-col justify-center ${caregiver.acceptPuppies ? 'bg-green-50/50 border-green-100 text-green-800' : 'bg-gray-50/50 border-gray-100 text-gray-400 grayscale font-medium opacity-60'}`}>
                  <span className="block text-[9px] font-black uppercase tracking-widest mb-1">Acepta cachorros</span>
                  <span className="font-bold flex items-center gap-2">
                    {caregiver.acceptPuppies ? (
                      <><span className="w-1.5 h-1.5 bg-green-500 rounded-full"></span> Sí</>
                    ) : 'No'}
                  </span>
                </div>
                <div className={`p-4 rounded-2xl border flex flex-col justify-center ${caregiver.acceptSeniors ? 'bg-green-50/50 border-green-100 text-green-800' : 'bg-gray-50/50 border-gray-100 text-gray-400 grayscale font-medium opacity-60'}`}>
                  <span className="block text-[9px] font-black uppercase tracking-widest mb-1">Acepta seniors</span>
                  <span className="font-bold flex items-center gap-2">
                    {caregiver.acceptSeniors ? (
                      <><span className="w-1.5 h-1.5 bg-green-500 rounded-full"></span> Sí</>
                    ) : 'No'}
                  </span>
                </div>
                <div className={`p-4 rounded-2xl border flex flex-col justify-center ${caregiver.acceptAggressive ? 'bg-red-50/50 border-red-100 text-red-800' : 'bg-gray-50/50 border-gray-100 text-gray-400 grayscale font-medium opacity-60'}`}>
                  <span className="block text-[9px] font-black uppercase tracking-widest mb-1">Acepta agresivos</span>
                  <span className="font-bold flex items-center gap-2">
                    {caregiver.acceptAggressive ? (
                      <><span className="w-1.5 h-1.5 bg-red-500 rounded-full"></span> Sí</>
                    ) : 'No'}
                  </span>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-8 pt-6 border-t border-gray-50 dark:border-gray-700">
                {caregiver.handleAnxious && (
                  <div>
                    <h3 className="text-xs font-black text-gray-400 uppercase tracking-widest mb-2">Manejo de ansiedad</h3>
                    <p className="text-sm text-gray-600 dark:text-gray-400 leading-relaxed font-medium">
                      {caregiver.handleAnxious}
                    </p>
                  </div>
                )}
                {caregiver.emergencyResponse && (
                  <div>
                    <h3 className="text-xs font-black text-gray-400 uppercase tracking-widest mb-2">Respuesta ante emergencias</h3>
                    <p className="text-sm text-gray-600 dark:text-gray-400 leading-relaxed font-medium">
                      {caregiver.emergencyResponse}
                    </p>
                  </div>
                )}
              </div>
            </div>
          </section>

          {/* SECCIÓN HOGAR: Solo si hace HOSPEDAJE */}
          {caregiver.services.includes('HOSPEDAJE') && (
            <section className="bg-white dark:bg-gray-800 rounded-3xl p-8 shadow-sm border border-gray-100 dark:border-gray-700">
              <h2 className="text-2xl font-black text-gray-900 dark:text-white mb-6 flex items-center gap-3">
                <span className="w-2 h-8 bg-green-500 rounded-full"></span>
                Mi hogar y entorno
              </h2>

              <div className="space-y-8">
                <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
                  {/* Detalles de la Casa */}
                  <div className="space-y-4">
                    <h3 className="text-xs font-black text-gray-400 uppercase tracking-widest">Infraestructura</h3>
                    <div className="space-y-3">
                      <div className="flex justify-between items-center text-sm">
                        <span className="text-gray-500 font-medium">Tipo de hogar</span>
                        <span className="font-bold text-gray-800 dark:text-gray-200">{caregiver.homeType === 'HOUSE' ? 'Casa' : 'Departamento'}</span>
                      </div>
                      <div className="flex justify-between items-center text-sm">
                        <span className="text-gray-500 font-medium">Casa propia</span>
                        <span className="font-bold text-gray-800 dark:text-gray-200">{caregiver.ownHome ? 'Sí' : 'No'}</span>
                      </div>
                      <div className="flex justify-between items-center text-sm">
                        <span className="text-gray-500 font-medium">Tiene patio</span>
                        <span className="font-bold text-gray-800 dark:text-gray-200">{caregiver.hasYard ? 'Sí' : 'No'}</span>
                      </div>
                      {caregiver.hasYard && (
                        <div className="flex justify-between items-center text-sm">
                          <span className="text-gray-500 font-medium">Patio cerrado</span>
                          <span className="font-bold text-green-600">{caregiver.yardFenced ? 'Totalmente vallado' : 'Parcialmente'}</span>
                        </div>
                      )}
                    </div>
                  </div>

                  {/* Convivencia y Reglas */}
                  <div className="space-y-4">
                    <h3 className="text-xs font-black text-gray-400 uppercase tracking-widest">Convivencia</h3>
                    <div className="space-y-3">
                      <div className="flex justify-between items-center text-sm">
                        <span className="text-gray-500 font-medium">Niños en casa</span>
                        <span className="font-bold text-gray-800 dark:text-gray-200">{caregiver.hasChildren ? 'Sí' : 'No'}</span>
                      </div>
                      <div className="flex justify-between items-center text-sm">
                        <span className="text-gray-500 font-medium">Otras mascotas</span>
                        <span className="font-bold text-gray-800 dark:text-gray-200">{caregiver.hasOtherPets ? `Sí (Hasta ${caregiver.maxPets ?? 1})` : 'No'}</span>
                      </div>
                      <div className="flex justify-between items-center text-sm">
                        <span className="text-gray-500 font-medium">Sus mascotas duermen</span>
                        <span className="font-bold text-gray-800 dark:text-gray-200">{caregiver.petsSleep === 'INSIDE' ? 'Adentro' : 'Afuera'}</span>
                      </div>
                      <div className="flex justify-between items-center text-sm">
                        <span className="text-gray-500 font-medium">Tu mascota dormirá</span>
                        <span className="font-bold text-gray-800 dark:text-gray-200 text-right">
                          {caregiver.clientPetsSleep === 'BED' ? 'En la cama' :
                            caregiver.clientPetsSleep === 'CRATE' ? 'En transportadora' :
                              caregiver.clientPetsSleep === 'SOFA' ? 'En el sofá' : 'En su propia camita'}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>

                {/* Rutina y Disponibilidad del hogar */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-8 pt-6 border-t border-gray-50 dark:border-gray-700">
                  <div className="space-y-4">
                    <h3 className="text-xs font-black text-gray-400 uppercase tracking-widest">Disponibilidad en casa</h3>
                    <div className="space-y-3">
                      <div className="flex justify-between items-center text-sm">
                        <span className="text-gray-500 font-medium">Trabaja desde casa</span>
                        <span className="font-bold text-gray-800 dark:text-gray-200">{caregiver.workFromHome ? 'Sí' : 'No'}</span>
                      </div>
                      <div className="flex justify-between items-center text-sm">
                        <span className="text-gray-500 font-medium">Horas solas (máx)</span>
                        <span className="font-bold text-gray-800 dark:text-gray-200">{caregiver.hoursAlone ?? 0} horas</span>
                      </div>
                      <div className="flex justify-between items-center text-sm">
                        <span className="text-gray-500 font-medium">Suele salir seguido</span>
                        <span className="font-bold text-gray-800 dark:text-gray-200">{caregiver.oftenOut ? 'Sí' : 'No'}</span>
                      </div>
                    </div>
                  </div>

                  {caregiver.typicalDay && (
                    <div className="space-y-2">
                      <h3 className="text-xs font-black text-gray-400 uppercase tracking-widest">Día típico</h3>
                      <p className="text-sm text-gray-600 dark:text-gray-400 leading-relaxed italic">
                        "{caregiver.typicalDay}"
                      </p>
                    </div>
                  )}
                </div>
              </div>
            </section>
          )}

          {/* SECCIÓN RUTINA (Simple para usuarios que no hacen hospedaje) */}
          {caregiver.typicalDay && !caregiver.services.includes('HOSPEDAJE') && (
            <section className="bg-white dark:bg-gray-800 rounded-3xl p-8 shadow-sm border border-gray-100 dark:border-gray-700">
              <h2 className="text-2xl font-black text-gray-900 dark:text-white mb-6 flex items-center gap-3">
                <span className="w-2 h-8 bg-green-500 rounded-full"></span>
                Mi rutina diaria
              </h2>
              <p className="text-gray-600 dark:text-gray-300 whitespace-pre-wrap leading-relaxed text-lg">
                {caregiver.typicalDay}
              </p>
            </section>
          )}

          {/* GALERÍA DE FOTOS: Seccion intermedia con distribución ajustable */}
          {galleryPhotos.length > 0 && (
            <section className="bg-white dark:bg-gray-800 rounded-3xl p-8 shadow-sm border border-gray-100 dark:border-gray-700">
              <h2 className="text-2xl font-black text-gray-900 dark:text-white mb-6 flex items-center gap-3">
                <span className="w-2 h-8 bg-green-500 rounded-full"></span>
                Mi galería
              </h2>
              <div className={`grid gap-4 ${galleryPhotos.length === 2 ? 'grid-cols-2' :
                galleryPhotos.length === 4 ? 'grid-cols-2 md:grid-cols-2' :
                  'grid-cols-2 md:grid-cols-3'
                }`}>
                {galleryPhotos.map((url, i) => (
                  <div key={i} className="aspect-square rounded-2xl overflow-hidden shadow-sm hover:shadow-md transition-shadow">
                    <img
                      src={getImageUrl(url)}
                      alt={`Foto gallery ${i + 1}`}
                      className="w-full h-full object-cover transition-transform duration-500 hover:scale-110"
                    />
                  </div>
                ))}
              </div>
            </section>
          )}

          {/* Reseñas si existen */}
          {caregiver.reviews && caregiver.reviews.length > 0 && (
            <section className="bg-white dark:bg-gray-800 rounded-3xl p-8 shadow-sm border border-gray-100 dark:border-gray-700">
              <h2 className="text-2xl font-black text-gray-900 dark:text-white mb-6 flex items-center gap-3">
                <span className="w-2 h-8 bg-green-500 rounded-full"></span>
                Reseñas de clientes
              </h2>
              <div className="space-y-6">
                {caregiver.reviews.map((r) => (
                  <div key={r.id} className="p-6 rounded-2xl bg-gray-50 dark:bg-gray-900/50 border border-transparent hover:border-gray-100 transition-colors">
                    <div className="flex items-center justify-between mb-3">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-full bg-slate-200 flex items-center justify-center font-bold text-slate-500">
                          {r.clientName.charAt(0)}
                        </div>
                        <div>
                          <p className="font-bold text-gray-900 dark:text-white">{r.clientName}</p>
                          <p className="text-[10px] text-gray-400 font-bold uppercase tracking-widest">{formatDate(r.createdAt)}</p>
                        </div>
                      </div>
                      <div className="flex items-center gap-1 text-amber-500">
                        <span className="font-bold">{r.rating}</span>
                        <svg className="h-5 w-5" fill="currentColor" viewBox="0 0 20 20"><path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" /></svg>
                      </div>
                    </div>
                    {r.comment && <p className="text-gray-600 dark:text-gray-400 italic font-medium leading-relaxed">"{r.comment}"</p>}
                  </div>
                ))}
              </div>
            </section>
          )}
        </div>

        {/* COLUMNA DERECHA: Servicios, Tarifas y Espacio */}
        <div className="space-y-6">
          <section className="bg-white dark:bg-gray-800 rounded-3xl p-8 shadow-sm border border-gray-100 dark:border-gray-700 sticky top-24">
            <h3 className="text-xl font-black text-gray-900 dark:text-white mb-6 flex items-center gap-2">
              <svg className="h-6 w-6 text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              Servicios y tarifas
            </h3>

            <div className="space-y-4">
              {caregiver.pricePerDay != null && (
                <div className="flex justify-between items-center p-4 rounded-2xl bg-slate-50 dark:bg-gray-900 border border-slate-100 dark:border-gray-800">
                  <span className="font-bold text-gray-700 dark:text-gray-300">Hospedaje</span>
                  <div className="text-right">
                    <span className="text-xl font-black text-green-600">Bs {caregiver.pricePerDay}</span>
                    <span className="block text-[10px] text-gray-400 uppercase font-black">por día</span>
                  </div>
                </div>
              )}
              {caregiver.pricePerWalk30 != null && (
                <div className="flex justify-between items-center p-4 rounded-2xl bg-slate-50 dark:bg-gray-900 border border-slate-100 dark:border-gray-800">
                  <span className="font-bold text-gray-700 dark:text-gray-300">Paseo 30 min</span>
                  <span className="text-xl font-black text-green-600">Bs {caregiver.pricePerWalk30}</span>
                </div>
              )}
              {caregiver.pricePerWalk60 != null && (
                <div className="flex justify-between items-center p-4 rounded-2xl bg-slate-50 dark:bg-gray-900 border border-slate-100 dark:border-gray-800">
                  <span className="font-bold text-gray-700 dark:text-gray-300">Paseo 60 min</span>
                  <span className="text-xl font-black text-green-600">Bs {caregiver.pricePerWalk60}</span>
                </div>
              )}
            </div>

            <div className="mt-8 pt-8 border-t border-gray-100 dark:border-gray-700 space-y-6">
              <div>
                <h4 className="text-xs font-black text-gray-400 uppercase tracking-widest mb-3">Espacio de cuidado</h4>
                <div className="flex flex-wrap gap-2 mb-4">
                  <Badge variant="muted" className="bg-blue-50 text-blue-700 border-blue-100 px-3 py-1 font-bold text-[10px] uppercase">
                    {caregiver.homeType === 'HOUSE' ? 'Casa' : 'Departamento'}
                  </Badge>
                  {caregiver.hasYard && (
                    <Badge variant="muted" className="bg-green-50 text-green-700 border-green-100 px-3 py-1 font-bold text-[10px] uppercase">
                      Con patio {caregiver.yardFenced ? '(Vallado)' : ''}
                    </Badge>
                  )}
                </div>
                <div className="flex flex-wrap gap-2">
                  {caregiver.spaceType?.map((st) => (
                    <Badge key={st} variant="muted" className="bg-slate-50 dark:bg-gray-900 text-slate-400 font-bold px-3 py-1 text-[9px] border border-slate-100 dark:border-gray-800 uppercase">
                      {SPACE_TYPE_QUERY_TO_DISPLAY[st] ?? st}
                    </Badge>
                  ))}
                </div>
                {caregiver.spaceDescription && (
                  <p className="mt-4 text-xs text-gray-500 leading-relaxed bg-gray-50 dark:bg-gray-900/50 p-3 rounded-xl border border-gray-100 dark:border-gray-800 italic">
                    {caregiver.spaceDescription}
                  </p>
                )}
              </div>

              <div>
                <h4 className="text-xs font-black text-gray-400 uppercase tracking-widest mb-3">Convivencia</h4>
                <div className="space-y-2">
                  <div className={`flex items-center gap-2 text-xs font-bold ${caregiver.hasChildren ? 'text-gray-700' : 'text-gray-400 opacity-60'}`}>
                    <div className={`w-2 h-2 rounded-full ${caregiver.hasChildren ? 'bg-green-500' : 'bg-gray-300'}`}></div>
                    Hay niños en casa
                  </div>
                  <div className={`flex items-center gap-2 text-xs font-bold ${caregiver.hasOtherPets ? 'text-gray-700' : 'text-gray-400 opacity-60'}`}>
                    <div className={`w-2 h-2 rounded-full ${caregiver.hasOtherPets ? 'bg-green-500' : 'bg-gray-300'}`}></div>
                    Tiene otras mascotas
                  </div>
                </div>
              </div>

              <div>
                <h4 className="text-xs font-black text-gray-400 uppercase tracking-widest mb-3">Zona principal</h4>
                <div className="flex items-center gap-2 text-gray-700 dark:text-gray-300">
                  <svg className="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" /><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" /></svg>
                  <span className="font-bold">{formatZone(caregiver.zone)}</span>
                </div>
              </div>
            </div>
          </section>
        </div>
      </div>
    </article>
  );
}
