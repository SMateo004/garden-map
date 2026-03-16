/**
 * Runs before any test file. Sets minimal env so config/env.ts does not exit(1) in tests.
 */
process.env.NODE_ENV = 'test';
if (!process.env.DATABASE_URL) process.env.DATABASE_URL = 'file:./test.db';
if (!process.env.JWT_SECRET) process.env.JWT_SECRET = 'x'.repeat(32);
