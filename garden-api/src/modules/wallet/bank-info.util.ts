/**
 * bank-info.util.ts — validación y escritura compartida de datos bancarios.
 *
 * Usado por wallet.routes.ts (PUT /api/wallet/bank, todos los roles) y por
 * caregiver-profile.routes.ts (PATCH /caregiver/bank-info) para que ambos
 * endpoints validen el mismo conjunto fijo de opciones de `bankType` y
 * escriban siempre a User (única fuente de verdad para retiros — ver
 * CLAUDE.md) además de sincronizar CaregiverProfile por compatibilidad con
 * queries admin existentes.
 */

import prisma from '../../config/database.js';
import type { BankAccountType } from '@prisma/client';

/** Conjunto fijo y conocido de opciones de bankType. */
export const BANK_ACCOUNT_TYPES: BankAccountType[] = [
  'CUENTA_AHORRO',
  'CUENTA_CORRIENTE',
  'YAPE',
  'ZAS',
  'YOLOPAGO',
  'ALTOKE',
];

/** Billeteras que usan número de teléfono en vez de número de cuenta. */
export const PHONE_BASED_BANK_TYPES: BankAccountType[] = ['YAPE', 'ZAS', 'YOLOPAGO', 'ALTOKE'];

export function isPhoneBasedBankType(bankType: string | null | undefined): boolean {
  return !!bankType && (PHONE_BASED_BANK_TYPES as string[]).includes(bankType);
}

export interface BankInfoInput {
  bankName: string;
  bankAccount: string;
  bankHolder: string;
  bankType?: string;
}

export interface BankInfoValidationError {
  message: string;
}

/**
 * Valida el payload de datos bancarios. Devuelve un error legible si algo no
 * cuadra, o null si es válido. No lanza — el caller decide el código HTTP.
 */
export function validateBankInfo(input: Partial<BankInfoInput>): BankInfoValidationError | null {
  const { bankName, bankAccount, bankHolder, bankType } = input;

  if (!bankName || !bankAccount || !bankHolder) {
    return { message: 'bankName, bankAccount y bankHolder son obligatorios' };
  }

  if (bankType && !(BANK_ACCOUNT_TYPES as string[]).includes(bankType)) {
    return { message: `bankType inválido. Debe ser uno de: ${BANK_ACCOUNT_TYPES.join(', ')}` };
  }

  if (isPhoneBasedBankType(bankType) && !/^\d{6,15}$/.test(bankAccount)) {
    return { message: 'Número de teléfono inválido' };
  }

  return null;
}

/**
 * Escribe los datos bancarios en User (fuente de verdad para retiros) y, si
 * el usuario es CAREGIVER, también en CaregiverProfile (legacy, solo para
 * compatibilidad con vistas de admin existentes — nunca se lee de ahí para
 * procesar un retiro real).
 */
export async function persistBankInfo(
  userId: string,
  role: string | undefined,
  data: BankInfoInput
): Promise<void> {
  const bankType = (data.bankType as BankAccountType | undefined) ?? 'CUENTA_AHORRO';

  await prisma.user.update({
    where: { id: userId },
    data: {
      bankName: data.bankName,
      bankAccount: data.bankAccount,
      bankHolder: data.bankHolder,
      bankType,
    },
  });

  if (role === 'CAREGIVER') {
    await prisma.caregiverProfile.updateMany({
      where: { userId },
      data: {
        bankName: data.bankName,
        bankAccount: data.bankAccount,
        bankHolder: data.bankHolder,
        bankType,
      },
    });
  }
}
