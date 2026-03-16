import { Link } from 'react-router-dom';
import { Badge } from '@/components/ui/Badge';
import type { CaregiverListItem, Zone } from '@/types/caregiver';
import { ZONE_LABELS } from '@/types/caregiver';
import { getImageUrl } from '@/utils/images';

interface ProfileCardProps {
  caregiver: CaregiverListItem;
}

function formatZone(zone?: string | null): string {
  if (zone == null || typeof zone !== 'string') return 'Zona no especificada';
  const trimmed = zone.trim();
  if (!trimmed) return 'Zona no especificada';
  if (trimmed in ZONE_LABELS) return ZONE_LABELS[trimmed as Zone];
  return trimmed.charAt(0).toUpperCase() + trimmed.slice(1).replace(/_/g, ' ');
}

function formatPrice(value: number | null): string {
  if (value == null) return '—';
  return `Bs ${value}`;
}

export function ProfileCard({ caregiver }: ProfileCardProps) {
  const name = `${caregiver.firstName} ${caregiver.lastName}`;
  const photoUrl = caregiver.profilePicture ?? caregiver.photos?.[0] ?? null;
  const servicesLabel =
    caregiver.services.length === 2 ? 'Hospedaje y paseos' : caregiver.services[0] === 'HOSPEDAJE' ? 'Hospedaje' : 'Paseos';

  return (
    <Link
      to={`/caregivers/${caregiver.id}`}
      className="group block overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm transition hover:shadow-md"
    >
      <div className="relative aspect-[4/3] overflow-hidden bg-gray-100">
        <img
          src={getImageUrl(photoUrl)}
          alt={`Foto de perfil de ${name}`}
          loading="lazy"
          className="h-full w-full object-cover transition group-hover:scale-105"
        />
        <div className="absolute right-2 top-2 flex flex-wrap gap-1">
          {caregiver.verified && (
            <Badge variant="verified">Verificado por GARDEN</Badge>
          )}
          {caregiver.spaceType?.length ? (
            <Badge variant="muted">
              {formatZone(Array.isArray(caregiver.spaceType) ? caregiver.spaceType[0] : caregiver.spaceType)}
            </Badge>
          ) : null}
        </div>
      </div>
      <div className="p-4">
        <h2 className="font-semibold text-gray-900">{name}</h2>
        <p className="mt-0.5 text-sm text-gray-500">{formatZone(caregiver.zone)} · {servicesLabel}</p>
        <div className="mt-2 flex items-center gap-2 text-sm">
          <span className="font-medium text-amber-600">
            ★ {caregiver.rating > 0 ? caregiver.rating.toFixed(1) : '—'}
          </span>
          {caregiver.reviewCount > 0 && (
            <span className="text-gray-500">({caregiver.reviewCount} reseñas)</span>
          )}
        </div>
        <div className="mt-2 flex gap-2 text-sm text-gray-600">
          {caregiver.pricePerDay != null && (
            <span>{formatPrice(caregiver.pricePerDay)}/día</span>
          )}
          {(caregiver.pricePerWalk30 != null || caregiver.pricePerWalk60 != null) && (
            <span>Paseo {formatPrice(caregiver.pricePerWalk30 ?? caregiver.pricePerWalk60)}</span>
          )}
        </div>
      </div>
    </Link>
  );
}
