import { hideCommissionFromClients } from '../../src/middleware/hide-commission.middleware';

function run(user: Record<string, unknown> | undefined, body: unknown) {
  let sent: unknown;
  const res: any = { json: (b: unknown) => { sent = b; return res; } };
  const req: any = {};
  hideCommissionFromClients(req, res, () => {});
  req.user = user; // authMiddleware corre después: el filtro se evalúa al responder
  res.json(body);
  return sent as any;
}

const booking = () => ({ id: 'b1', totalAmount: '116', commissionAmount: '10', taxAmount: '16' });

describe('hideCommissionFromClients', () => {
  it('quita la comisión de las reservas que recibe un CLIENT', () => {
    const out = run({ role: 'CLIENT' }, { success: true, data: [booking(), { nested: booking() }] });
    expect(out.data[0].commissionAmount).toBeUndefined();
    expect(out.data[1].nested.commissionAmount).toBeUndefined();
    expect(out.data[0].totalAmount).toBe('116');
    expect(out.data[0].taxAmount).toBe('16');
  });

  it('respeta el rol efectivo (cuidador usando la app como dueño)', () => {
    const out = run({ role: 'CAREGIVER', activeRole: 'CLIENT' }, { data: booking() });
    expect(out.data.commissionAmount).toBeUndefined();
  });

  it('la deja para el cuidador y el admin, que la necesitan para la ganancia', () => {
    expect(run({ role: 'CAREGIVER' }, { data: booking() }).data.commissionAmount).toBe('10');
    expect(run({ role: 'ADMIN' }, { data: booking() }).data.commissionAmount).toBe('10');
  });
});
