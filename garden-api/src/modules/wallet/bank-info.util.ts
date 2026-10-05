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
 * Quita espacios, guiones y puntos; en billeteras también el prefijo +591.
 * Es lo que se guarda, así el admin ve siempre el mismo formato al pagar.
 * Mismas reglas que GardenBanks en la app (garden_banks.dart).
 */
export function normalizeBankAccount(bankType: string | null | undefined, raw: string): string {
  let v = String(raw ?? '').replace(/[\s.\-]/g, '');
  if (isPhoneBasedBankType(bankType)) v = v.replace(/^\+?591/, '');
  return v;
}

/**
 * Valida el payload de datos bancarios. Devuelve un error legible si algo no
 * cuadra, o null si es válido. No lanza — el caller decide el código HTTP.
 */
export function validateBankInfo(input: Partial<BankInfoInput>): BankInfoValidationError | null {
  const { bankName, bankAccount, bankHolder, bankType } = input;
  // /wallet/bank no pasa por Zod: un número u objeto no debe romper con 500.
  if ([bankName, bankAccount, bankHolder].some((v) => v != null && typeof v !== 'string')) {
    return { message: 'Datos de cobro inválidos' };
  }

  if (!bankName?.trim()) return { message: 'Elige tu banco o billetera' };
  if (bankType && !(BANK_ACCOUNT_TYPES as string[]).includes(bankType)) {
    return { message: 'Elige un tipo de cuenta válido' };
  }

  const account = normalizeBankAccount(bankType, bankAccount ?? '');
  if (isPhoneBasedBankType(bankType)) {
    if (!account) return { message: 'Escribe el número de teléfono de tu billetera' };
    if (!/^[67]\d{7}$/.test(account)) {
      return { message: 'Revisa el número: son 8 dígitos y empieza con 6 o 7' };
    }
  } else {
    if (!account) return { message: 'Escribe tu número de cuenta' };
    if (!/^\d+$/.test(account)) return { message: 'El número de cuenta solo lleva números' };
    if (account.length < 6 || account.length > 20) {
      return { message: 'Revisa el número de cuenta: entre 6 y 20 dígitos' };
    }
  }

  const holder = bankHolder?.trim() ?? '';
  if (!holder) return { message: 'Escribe el nombre del titular de la cuenta' };
  if (holder.length < 3 || !/\p{L}/u.test(holder)) {
    return { message: 'Escribe el nombre completo del titular, como figura en el banco' };
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
  const clean = {
    bankName: data.bankName.trim(),
    bankAccount: normalizeBankAccount(bankType, data.bankAccount),
    bankHolder: data.bankHolder.trim(),
    bankType,
  };

  await prisma.user.update({
    where: { id: userId },
    data: clean,
  });

  if (role === 'CAREGIVER') {
    await prisma.caregiverProfile.updateMany({
      where: { userId },
      data: clean,
    });
  }
}
