import { LedgerAccountType } from '@prisma/client';

/** Plan de cuentas — ver comentario en el schema de Prisma (bloque LIBRO
 * CONTABLE) para el diseño completo y por qué quedó así. */
export const CHART_OF_ACCOUNTS: Array<{ code: string; name: string; type: LedgerAccountType }> = [
  { code: '1100', name: 'Banco', type: LedgerAccountType.ACTIVO },

  { code: '2100', name: 'Billeteras de clientes', type: LedgerAccountType.PASIVO },
  { code: '2200', name: 'Billeteras de cuidadores', type: LedgerAccountType.PASIVO },

  { code: '3100', name: 'Capital / aportes de socios', type: LedgerAccountType.PATRIMONIO },
  { code: '3200', name: 'Utilidades retenidas', type: LedgerAccountType.PATRIMONIO },

  { code: '4100', name: 'Ingresos por comisión', type: LedgerAccountType.INGRESO },
  { code: '4900', name: 'Otros ingresos', type: LedgerAccountType.INGRESO },

  { code: '5100', name: 'Marketing — bonos de referidos', type: LedgerAccountType.GASTO },
  { code: '5200', name: 'Marketing — descuentos promocionales', type: LedgerAccountType.GASTO },
  { code: '5300', name: 'Reembolsos otorgados', type: LedgerAccountType.GASTO },
  { code: '5400', name: 'Gastos operativos', type: LedgerAccountType.GASTO },
  { code: '5900', name: 'Otros gastos', type: LedgerAccountType.GASTO },
];

export const ACCOUNT = {
  BANCO: '1100',
  BILLETERA_CLIENTES: '2100',
  BILLETERA_CUIDADORES: '2200',
  CAPITAL: '3100',
  UTILIDADES_RETENIDAS: '3200',
  INGRESO_COMISION: '4100',
  OTROS_INGRESOS: '4900',
  GASTO_MARKETING_REFERIDOS: '5100',
  GASTO_MARKETING_PROMOS: '5200',
  GASTO_REEMBOLSOS: '5300',
  GASTO_OPERATIVO: '5400',
  OTROS_GASTOS: '5900',
} as const;
