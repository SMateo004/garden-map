import PDFDocument from 'pdfkit';
import type { Response } from 'express';

const MESES = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

type MonthlyLedger = Awaited<ReturnType<typeof import('./ledger.service.js').getMonthlyLedger>>;

const MARGIN = 40;
const PAGE_WIDTH = 612; // Letter
const CONTENT_WIDTH = PAGE_WIDTH - MARGIN * 2;

function money(n: number): string {
  return `Bs ${n.toLocaleString('es-BO', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/** Arma el PDF del libro contable mensual (reporte gerencial interno — no
 * reemplaza el libro oficial que lleva el contador externo, ver comentario
 * en el schema de Prisma) y lo escribe directo al response. */
export function streamMonthlyLedgerPdf(res: Response, ledger: MonthlyLedger): void {
  const doc = new PDFDocument({ size: 'LETTER', margin: MARGIN });
  const fileName = `garden-finanzas-${ledger.year}-${String(ledger.month).padStart(2, '0')}.pdf`;
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${fileName}"`);
  doc.pipe(res);

  // ── Portada / Estado de Resultados ──────────────────────────────────────
  doc.font('Helvetica-Bold').fontSize(20).fillColor('#1E2D0F').text('GARDEN', MARGIN, MARGIN);
  doc.font('Helvetica').fontSize(11).fillColor('#5C7238')
    .text('Reporte financiero mensual — documento interno para socios', MARGIN, doc.y + 2);
  doc.moveDown(0.3);
  doc.font('Helvetica-Bold').fontSize(15).fillColor('#1E2D0F')
    .text(`${capitalize(MESES[ledger.month - 1]!)} ${ledger.year}`, MARGIN, doc.y);
  doc.font('Helvetica').fontSize(9).fillColor('#8A9C6C')
    .text(`Generado el ${new Date().toLocaleDateString('es-BO', { day: '2-digit', month: 'long', year: 'numeric' })}`, MARGIN, doc.y + 2);
  doc.moveDown(1);

  drawDivider(doc);
  doc.moveDown(0.8);

  doc.font('Helvetica-Bold').fontSize(13).fillColor('#1E2D0F').text('Estado de Resultados', MARGIN, doc.y);
  doc.moveDown(0.5);

  doc.font('Helvetica-Bold').fontSize(10).fillColor('#5C7238').text('INGRESOS', MARGIN, doc.y);
  doc.moveDown(0.2);
  for (const ing of ledger.estadoResultados.ingresos) {
    row2(doc, `${ing.code} — ${ing.name}`, money(ing.amount));
  }
  row2(doc, 'Total ingresos', money(ledger.estadoResultados.totalIngresos), true);
  doc.moveDown(0.6);

  doc.font('Helvetica-Bold').fontSize(10).fillColor('#5C7238').text('GASTOS', MARGIN, doc.y);
  doc.moveDown(0.2);
  for (const g of ledger.estadoResultados.gastos) {
    row2(doc, `${g.code} — ${g.name}`, money(g.amount));
  }
  row2(doc, 'Total gastos', money(ledger.estadoResultados.totalGastos), true);
  doc.moveDown(0.6);

  drawDivider(doc);
  doc.moveDown(0.4);
  const utilidad = ledger.estadoResultados.utilidad;
  doc.font('Helvetica-Bold').fontSize(13)
    .fillColor(utilidad >= 0 ? '#1A9954' : '#E74C3C')
    .text('Utilidad neta del mes', MARGIN, doc.y, { continued: true, width: CONTENT_WIDTH - 120 });
  doc.text(money(utilidad), { align: 'right' });
  doc.moveDown(0.3);
  doc.font('Helvetica').fontSize(8).fillColor('#8A9C6C')
    .text('No incluye propinas ni donaciones — esa plata pasa de largo por Garden, no es ingreso ni gasto de la empresa.', MARGIN, doc.y, { width: CONTENT_WIDTH });

  // ── Libro Diario ─────────────────────────────────────────────────────────
  doc.addPage();
  doc.font('Helvetica-Bold').fontSize(14).fillColor('#1E2D0F').text('Libro Diario', MARGIN, MARGIN);
  doc.font('Helvetica').fontSize(9).fillColor('#8A9C6C')
    .text(`Partida doble — cada asiento con Debe = Haber. ${ledger.entries.length} asientos este mes.`, MARGIN, doc.y + 2);
  doc.moveDown(0.8);

  const cols = { fecha: MARGIN, cuenta: MARGIN + 60, debe: MARGIN + 300, haber: MARGIN + 380 };
  tableHeader(doc, cols);

  for (const entry of ledger.entries) {
    ensureSpace(doc, 60);
    const dateStr = new Date(entry.date).toLocaleDateString('es-BO', { day: '2-digit', month: '2-digit', year: 'numeric' });
    doc.font('Helvetica-Bold').fontSize(8).fillColor('#1E2D0F')
      .text(`${dateStr}  —  ${entry.description}`, MARGIN, doc.y, { width: CONTENT_WIDTH });
    doc.moveDown(0.15);
    for (const line of entry.lines) {
      ensureSpace(doc, 14);
      const y = doc.y;
      doc.font('Helvetica').fontSize(8).fillColor('#5C7238');
      doc.text(`${line.account.code} ${line.account.name}`, cols.cuenta, y, { width: 235 });
      doc.text(Number(line.debit) > 0 ? money(Number(line.debit)) : '', cols.debe, y, { width: 75, align: 'right' });
      doc.text(Number(line.credit) > 0 ? money(Number(line.credit)) : '', cols.haber, y, { width: 75, align: 'right' });
      doc.moveDown(0.35);
    }
    doc.moveDown(0.3);
  }

  if (ledger.entries.length === 0) {
    doc.font('Helvetica').fontSize(10).fillColor('#8A9C6C').text('Sin movimientos este mes.', MARGIN, doc.y);
  }

  doc.end();
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function row2(doc: PDFKit.PDFDocument, label: string, value: string, bold = false) {
  doc.font(bold ? 'Helvetica-Bold' : 'Helvetica').fontSize(9.5).fillColor(bold ? '#1E2D0F' : '#333')
    .text(label, MARGIN, doc.y, { continued: true, width: CONTENT_WIDTH - 100 });
  doc.text(value, { align: 'right' });
  doc.moveDown(0.15);
}

function drawDivider(doc: PDFKit.PDFDocument) {
  doc.moveTo(MARGIN, doc.y).lineTo(PAGE_WIDTH - MARGIN, doc.y).strokeColor('#DDD5C8').lineWidth(1).stroke();
}

function tableHeader(doc: PDFKit.PDFDocument, cols: { fecha: number; cuenta: number; debe: number; haber: number }) {
  const y = doc.y;
  doc.font('Helvetica-Bold').fontSize(8).fillColor('#778C43');
  doc.text('FECHA / CONCEPTO', cols.fecha, y, { width: 235 });
  doc.text('DEBE', cols.debe, y, { width: 75, align: 'right' });
  doc.text('HABER', cols.haber, y, { width: 75, align: 'right' });
  doc.moveDown(0.4);
  drawDivider(doc);
  doc.moveDown(0.4);
}

function ensureSpace(doc: PDFKit.PDFDocument, needed: number) {
  const pageBottom = doc.page.height - MARGIN;
  if (doc.y + needed > pageBottom) {
    doc.addPage();
  }
}
