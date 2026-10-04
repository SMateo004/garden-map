/**
 * Dueño de empresa: el User se llama como el negocio, así que el nombre del CI no se compara
 * contra él (si no, siempre se rechazaría). Para cuentas normales la comparación sigue igual.
 */
const mockExtract = jest.fn();
jest.mock('../../src/modules/verification/ocr.service', () => ({
  ...jest.requireActual('../../src/modules/verification/ocr.service'),
  extractCIData: (...a: unknown[]) => mockExtract(...a),
}));
jest.mock('../../src/config/database', () => ({ __esModule: true, default: {} }));

import { crossValidate } from '../../src/modules/verification/identity-validation.service';

const ocr = {
  firstName: 'JUAN', lastName: 'PEREZ ROJAS', fullName: 'JUAN PEREZ ROJAS', documentNumber: '1234567',
  dateOfBirth: '01/01/1990', rawText: 'JUAN PEREZ ROJAS 1234567', confidence: 95, source: 'textract', hasExplicitLabels: true,
};
const img = Buffer.from('x');

describe('crossValidate — nombre del dueño de empresa', () => {
  beforeEach(() => mockExtract.mockReset().mockResolvedValue(ocr));

  it('cuenta normal: un nombre distinto sigue rechazándose', async () => {
    const r = await crossValidate(img, 'Hotel Patitas', '-', null, 'u1', img);
    expect(r.fraudFlags).toContain('name_mismatch');
    expect(r.passed).toBe(false);
  });

  it('empresa: no se marca name_mismatch aunque el CI diga otro nombre', async () => {
    const r = await crossValidate(img, 'Hotel Patitas', '-', null, 'u1', img, { skipNameMatch: true });
    expect(r.fraudFlags).not.toContain('name_mismatch');
    expect(r.nameSimilarity).toBe(100);
  });

  it('empresa: si el OCR no leyó ningún nombre queda neutro (50), no se infla', async () => {
    mockExtract.mockResolvedValue({ ...ocr, fullName: null, firstName: null, lastName: null });
    const r = await crossValidate(img, 'Hotel Patitas', '-', null, 'u1', img, { skipNameMatch: true });
    expect(r.nameSimilarity).toBe(50);
  });

  it('empresa: sigue exigiendo un CI legible', async () => {
    mockExtract.mockResolvedValue({ ...ocr, documentNumber: null });
    const r = await crossValidate(img, 'Hotel Patitas', '-', null, 'u1', img, { skipNameMatch: true });
    expect(r.fraudFlags).toContain('missing_ci');
    expect(r.passed).toBe(false);
  });
});
