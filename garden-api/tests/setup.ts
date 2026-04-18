/**
 * Runs before any test file. Sets minimal env so config/env.ts does not exit(1) in tests.
 */
process.env.NODE_ENV        = 'test';
process.env.DATABASE_URL    ??= 'postgresql://test:test@localhost:5432/test';
process.env.JWT_SECRET      ??= 'x'.repeat(32);
process.env.RESEND_API_KEY  ??= 're_test_key';
process.env.EMAIL_FROM      ??= 'test@garden.bo';
