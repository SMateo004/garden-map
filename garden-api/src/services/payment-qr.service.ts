/**
 * QR de pago provisional por tipo de servicio — mostrado a los clientes
 * mientras SIP_ENABLED=false. Es una imagen real (subida por un admin, ej.
 * el QR de una cuenta bancaria) pero NO conectada al riel bancario SIP; una
 * vez SIP_ENABLED=true, generateQR() en booking.service.ts nunca llega a
 * leer estos valores (esa rama solo corre en el bloque SIP_ENABLED=false).
 */
import { ServiceType } from '@prisma/client';
import prisma from '../config/database.js';
import { getStringSetting, invalidateSetting } from '../utils/settings-cache.js';

function settingKey(serviceType: ServiceType): string {
  return `payment_qr_${serviceType}`;
}

export async function getPaymentQrImageUrl(serviceType: ServiceType): Promise<string | null> {
  const url = await getStringSetting(settingKey(serviceType), '');
  return url.length > 0 ? url : null;
}

export async function getAllPaymentQrImageUrls(): Promise<Record<ServiceType, string | null>> {
  const entries = await Promise.all(
    Object.values(ServiceType).map(async (st) => [st, await getPaymentQrImageUrl(st)] as const)
  );
  return Object.fromEntries(entries) as Record<ServiceType, string | null>;
}

export async function setPaymentQrImageUrl(
  serviceType: ServiceType,
  url: string,
  adminUserId: string
): Promise<void> {
  const key = settingKey(serviceType);
  await prisma.appSettings.upsert({
    where: { key },
    update: { value: JSON.stringify(url), updatedBy: adminUserId },
    create: { key, value: JSON.stringify(url), updatedBy: adminUserId },
  });
  invalidateSetting(key);
}
