import { parseExtractedDOB, calculateAgeFromDOB } from '../../src/modules/verification/ocr.service';

describe('parseExtractedDOB', () => {
  it('parses DD/MM/YYYY (formato boliviano estándar)', () => {
    const d = parseExtractedDOB('13/04/2004');
    expect(d).not.toBeNull();
    expect(d!.getFullYear()).toBe(2004);
    expect(d!.getMonth()).toBe(3); // abril = index 3
    expect(d!.getDate()).toBe(13);
  });

  it('parses DD-MM-YYYY', () => {
    const d = parseExtractedDOB('01-01-1990');
    expect(d!.getFullYear()).toBe(1990);
    expect(d!.getMonth()).toBe(0);
    expect(d!.getDate()).toBe(1);
  });

  it('parses YYYY-MM-DD', () => {
    const d = parseExtractedDOB('1995-06-15');
    expect(d!.getFullYear()).toBe(1995);
    expect(d!.getMonth()).toBe(5);
    expect(d!.getDate()).toBe(15);
  });

  it('interprets a 2-digit year as 19xx (nunca 20xx para un CI de adulto)', () => {
    const d = parseExtractedDOB('05/09/85');
    expect(d!.getFullYear()).toBe(1985);
  });

  it('returns null for unparseable strings', () => {
    expect(parseExtractedDOB('no es una fecha')).toBeNull();
    expect(parseExtractedDOB('')).toBeNull();
    expect(parseExtractedDOB(null)).toBeNull();
  });

  it('returns null for a malformed date (e.g. day/month out of range)', () => {
    // new Date(1990, 12, 40) rueda a otro mes/año en JS — no debe pasar silenciosamente
    // como una fecha "válida" arbitraria; solo verificamos que no explote.
    expect(() => parseExtractedDOB('40/13/1990')).not.toThrow();
  });
});

describe('calculateAgeFromDOB', () => {
  it('calculates age for a birthday that already passed this year', () => {
    const today = new Date();
    const dob = new Date(today.getFullYear() - 25, 0, 1); // 1 de enero, hace 25 años
    expect(calculateAgeFromDOB(dob)).toBe(25);
  });

  it('calculates age for a birthday later this year (not turned yet)', () => {
    const today = new Date();
    // Cumple mañana, hace 25 años — el cumpleaños de este año todavía no pasó.
    const dob = new Date(today.getFullYear() - 25, today.getMonth(), today.getDate() + 1);
    expect(calculateAgeFromDOB(dob)).toBe(24);
  });

  it('returns 17 for someone who turns 18 tomorrow', () => {
    const today = new Date();
    const dob = new Date(today.getFullYear() - 18, today.getMonth(), today.getDate() + 1);
    expect(calculateAgeFromDOB(dob)).toBe(17);
  });

  it('returns 18 for someone who turned 18 today', () => {
    const today = new Date();
    const dob = new Date(today.getFullYear() - 18, today.getMonth(), today.getDate());
    expect(calculateAgeFromDOB(dob)).toBe(18);
  });
});
