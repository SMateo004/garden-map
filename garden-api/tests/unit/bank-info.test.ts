import { normalizeBankAccount, validateBankInfo } from '../../src/modules/wallet/bank-info.util';

jest.mock('../../src/config/database', () => ({ __esModule: true, default: {} }));

const base = { bankName: 'Banco BNB', bankHolder: 'Ana Pérez', bankType: 'CUENTA_AHORRO' };

describe('datos de cobro', () => {
  it('normaliza espacios, guiones y el +591 de las billeteras', () => {
    expect(normalizeBankAccount('CUENTA_AHORRO', '1000-234 567.8')).toBe('10002345678');
    expect(normalizeBankAccount('YAPE', '+591 700 12345')).toBe('70012345');
    expect(normalizeBankAccount('CUENTA_AHORRO', '591123456')).toBe('591123456');
  });

  it('cuenta bancaria: solo números, de 6 a 20', () => {
    expect(validateBankInfo({ ...base, bankAccount: '1000-2345-678' })).toBeNull();
    expect(validateBankInfo({ ...base, bankAccount: '' })?.message).toMatch(/número de cuenta/);
    expect(validateBankInfo({ ...base, bankAccount: 'ABC12345' })?.message).toMatch(/solo lleva números/);
    expect(validateBankInfo({ ...base, bankAccount: '12345' })?.message).toMatch(/entre 6 y 20/);
  });

  it('billetera: celular boliviano de 8 dígitos', () => {
    const yape = { ...base, bankName: 'Yape', bankType: 'YAPE' };
    expect(validateBankInfo({ ...yape, bankAccount: '+591 70012345' })).toBeNull();
    expect(validateBankInfo({ ...yape, bankAccount: '3341234' })?.message).toMatch(/8 dígitos/);
    expect(validateBankInfo({ ...yape, bankAccount: '50012345' })?.message).toMatch(/6 o 7/);
  });

  it('titular y banco con mensajes en lenguaje simple', () => {
    expect(validateBankInfo({ ...base, bankAccount: '1234567', bankHolder: ' ' })?.message).toMatch(/titular/);
    expect(validateBankInfo({ ...base, bankAccount: '1234567', bankHolder: '12' })?.message).toMatch(/nombre completo/);
    expect(validateBankInfo({ ...base, bankAccount: '1234567', bankName: '' })?.message).toBe('Elige tu banco o billetera');
    expect(validateBankInfo({ ...base, bankAccount: 1234567 as any })?.message).toBe('Datos de cobro inválidos');
  });
});
