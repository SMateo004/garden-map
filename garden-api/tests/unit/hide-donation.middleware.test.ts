/**
 * El cuidador no ve la donación del dueño (hide-commission.middleware.ts).
 * El campo queda en 0 —no se elimina— para no romper apps viejas que lo leen como número.
 */
import {
  hideDonationFromCaregivers,
  hideCommissionFromClients,
} from '../../src/middleware/hide-commission.middleware';

function run(mw: (req: any, res: any, next: () => void) => void, role: string | undefined, body: unknown) {
  let sent: unknown;
  const res: any = { json: (b: unknown) => { sent = b; return res; } };
  const req: any = { user: role ? { role, activeRole: null } : undefined };
  mw(req, res, () => {});
  res.json(body);
  return sent as any;
}

const booking = () => ({
  id: 'b1',
  totalAmount: '128',
  donationAmount: 20,
  commissionAmount: '10',
  nested: { payment: { donationAmount: 5 } },
  list: [{ donationAmount: 7 }],
});

describe('hideDonationFromCaregivers', () => {
  it('el cuidador ve la donación en 0, en cualquier nivel de la respuesta', () => {
    const out = run(hideDonationFromCaregivers, 'CAREGIVER', booking());
    expect(out.donationAmount).toBe(0);
    expect(out.nested.payment.donationAmount).toBe(0);
    expect(out.list[0].donationAmount).toBe(0);
    expect(out.totalAmount).toBe('128'); // el resto no se toca
  });

  it('el dueño sigue viendo su donación', () => {
    expect(run(hideDonationFromCaregivers, 'CLIENT', booking()).donationAmount).toBe(20);
  });

  it('el admin la sigue viendo (soporte)', () => {
    expect(run(hideDonationFromCaregivers, 'ADMIN', booking()).donationAmount).toBe(20);
  });

  it('respeta el rol activo: un usuario que es cuidador pero navega como dueño la ve', () => {
    let sent: any;
    const res: any = { json: (b: unknown) => { sent = b; return res; } };
    const req: any = { user: { role: 'CAREGIVER', activeRole: 'CLIENT' } };
    hideDonationFromCaregivers(req, res, () => {});
    res.json(booking());
    expect(sent.donationAmount).toBe(20);
  });
});

describe('hideCommissionFromClients (sin regresión)', () => {
  it('al dueño le quita la comisión pero no la donación', () => {
    const out = run(hideCommissionFromClients, 'CLIENT', booking());
    expect('commissionAmount' in out).toBe(false);
    expect(out.donationAmount).toBe(20);
  });
});
