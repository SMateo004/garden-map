/**
 * Impuestos en pausa en los Términos (sección 6). Mientras GARDEN no cobre impuestos
 * (pricing.service.ts → taxesActive=false) el texto no puede decir que se suman: sería
 * falso y el cliente vería un total distinto del prometido. withoutTaxMentions() deriva la
 * versión sin impuestos reemplazando exactamente las frases que los mencionan; cuando se
 * activen, vuelve a mostrarse el texto original sin tocar nada.
 *
 * Mismo reemplazo en la app: garden-app/lib/screens/legal/legal_screen.dart. Si cambias
 * una de estas frases en los Términos, cámbiala aquí (la prueba tax-clauses.test.ts falla
 * si alguna deja de encontrarse).
 */
export const TAX_CLAUSE_REPLACEMENTS: ReadonlyArray<readonly [string, string]> = [
  [
    ' y al pagar se suman los impuestos de ley (16%: Bs. 18), para un total de Bs. 128.',
    ', que es el total a pagar.',
  ],
  [
    ' y al pagar se suman los impuestos de ley (ej.: Bs. 18), para un total de Bs. 128.',
    ', que es el total que paga.',
  ],
  [
    ' y destina los impuestos cobrados al pago de sus obligaciones tributarias (ej.: Bs. 18).',
    '.',
  ],
  [
    'IVA E IMPUESTOS: Los impuestos de ley (IVA 13% e IT 3%, 16% en total) se muestran por separado en el detalle de pago y se suman al precio del servicio; no se descuentan al Cuidador. Garden emite las facturas electrónicas que correspondan al amparo de la Ley N° 812 (Factura Electrónica) y las disposiciones del Servicio de Impuestos Nacionales (SIN).',
    'PRECIO TOTAL Y FACTURACIÓN: El precio que el Cliente ve antes de pagar es el total final del servicio; no se suman otros cargos al pagar. Garden emite las facturas electrónicas que correspondan conforme a la Ley N° 812 (Factura Electrónica).',
  ],
];

export function withoutTaxMentions(body: string): string {
  let out = body;
  for (const [from, to] of TAX_CLAUSE_REPLACEMENTS) out = out.split(from).join(to);
  return out;
}
