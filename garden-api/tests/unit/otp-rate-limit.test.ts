/**
 * Límites de OTP: se cuentan por usuario, no por IP (CGNAT de las operadoras
 * bolivianas), con un techo por IP más holgado.
 */
import express from 'express';
import request from 'supertest';
import { phoneOtpSendLimiter, phoneOtpSendIpLimiter, otpVerifyLimiter } from '../../src/modules/auth/otp-rate-limit';

/** App mínima: "autentica" con el header x-test-user y responde 200. */
function buildApp(...limiters: express.RequestHandler[]) {
  const app = express();
  app.set('trust proxy', true);
  app.use((req, _res, next) => {
    const id = req.header('x-test-user');
    if (id) (req as unknown as { user: { userId: string } }).user = { userId: id };
    next();
  });
  app.post('/send', ...limiters, (_req, res) => res.json({ success: true }));
  return app;
}

const post = (app: express.Express, user: string, ip: string) =>
  request(app).post('/send').set('x-test-user', user).set('X-Forwarded-For', ip);

describe('phoneOtpSendLimiter (por usuario)', () => {
  it('bloquea al usuario después de 3 envíos', async () => {
    const app = buildApp(phoneOtpSendLimiter);
    for (let i = 0; i < 3; i++) expect((await post(app, 'user-a', '10.0.0.1')).status).toBe(200);
    const blocked = await post(app, 'user-a', '10.0.0.1');
    expect(blocked.status).toBe(429);
    expect(blocked.body.error.code).toBe('TOO_MANY_REQUESTS');
  });

  it('usuarios distintos detrás de la MISMA IP no se bloquean entre sí', async () => {
    const app = buildApp(phoneOtpSendLimiter);
    for (let i = 0; i < 3; i++) await post(app, 'user-b', '10.0.0.2');
    expect((await post(app, 'user-b', '10.0.0.2')).status).toBe(429);
    // user-c comparte IP con user-b y no debe verse afectado
    expect((await post(app, 'user-c', '10.0.0.2')).status).toBe(200);
  });

  it('el mismo usuario cambiando de IP sigue limitado', async () => {
    const app = buildApp(phoneOtpSendLimiter);
    for (let i = 0; i < 3; i++) await post(app, 'user-d', `10.0.1.${i}`);
    expect((await post(app, 'user-d', '10.0.1.99')).status).toBe(429);
  });
});

describe('phoneOtpSendIpLimiter (techo por IP)', () => {
  it('tolera varios usuarios por IP pero corta un abuso masivo', async () => {
    const app = buildApp(phoneOtpSendIpLimiter);
    for (let i = 0; i < 30; i++) {
      expect((await post(app, `user-ip-${i}`, '10.0.2.1')).status).toBe(200);
    }
    expect((await post(app, 'user-ip-extra', '10.0.2.1')).status).toBe(429);
    // otra IP no se ve afectada
    expect((await post(app, 'user-ip-extra', '10.0.2.2')).status).toBe(200);
  });
});

describe('otpVerifyLimiter (por usuario)', () => {
  it('bloquea tras 10 intentos fallidos de un usuario, no de su vecino de IP', async () => {
    const app = express();
    app.set('trust proxy', true);
    app.use((req, _res, next) => {
      (req as unknown as { user: { userId: string } }).user = { userId: req.header('x-test-user') ?? 'anon' };
      next();
    });
    app.post('/verify', otpVerifyLimiter, (_req, res) => res.status(400).json({ success: false }));

    const verify = (user: string) => request(app).post('/verify').set('x-test-user', user).set('X-Forwarded-For', '10.0.3.1');
    for (let i = 0; i < 10; i++) expect((await verify('user-v1')).status).toBe(400);
    expect((await verify('user-v1')).status).toBe(429);
    expect((await verify('user-v2')).status).toBe(400);
  });
});
