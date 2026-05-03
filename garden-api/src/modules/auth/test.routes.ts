import { Router, Request, Response, NextFunction } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import { sendVerificationEmail } from './email.service.js';
import { BadRequestError, UnauthorizedError } from '../../shared/errors.js';

const router = Router();

/**
 * Guard: requires X-Test-Token header matching TEST_SECRET env var.
 * Prevents staging test routes from being invoked without a shared secret.
 * If TEST_SECRET is not configured the route is blocked entirely.
 */
function requireTestSecret(req: Request, _res: Response, next: NextFunction): void {
  const secret = process.env.TEST_SECRET;
  if (!secret) {
    next(new UnauthorizedError('TEST_SECRET is not configured'));
    return;
  }
  const provided = req.headers['x-test-token'];
  if (provided !== secret) {
    next(new UnauthorizedError('Invalid X-Test-Token'));
    return;
  }
  next();
}

/**
 * POST /api/test/send-email
 * Temporary test route to verify Resend integration.
 * Requires X-Test-Token: <TEST_SECRET> header.
 */
router.post('/send-email', requireTestSecret, asyncHandler(async (req, res) => {
    const { email } = req.body;

    if (!email) {
        throw new BadRequestError('Email is required', 'MISSING_EMAIL');
    }

    // Generate a real OTP for the test (just a random 6-digit for the test email)
    const testCode = Math.floor(100000 + Math.random() * 900000).toString();

    await sendVerificationEmail(email, testCode);

    res.json({
        success: true,
        message: `Test email sent successfully to ${email} via Resend`,
        data: {
            sentTo: email,
            provider: 'Resend'
        }
    });
}));

export default router;
