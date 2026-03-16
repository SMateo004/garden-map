import { Router } from 'express';
import { asyncHandler } from '../../shared/async-handler.js';
import { sendVerificationEmail } from './email.service.js';
import { BadRequestError } from '../../shared/errors.js';

const router = Router();

/**
 * POST /api/test/send-email
 * Temporary test route to verify Resend integration.
 */
router.post('/send-email', asyncHandler(async (req, res) => {
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
