/**
 * Tests para el error handler global.
 * Verifica que AppError, ZodError y errores genéricos devuelven
 * el formato y status code correcto.
 */

import { Request, Response, NextFunction } from 'express';
import { ZodError, ZodIssue } from 'zod';
import { errorHandler } from '../../src/shared/error-handler';
import { AppError, BadRequestError, UnauthorizedError, NotFoundError } from '../../src/shared/errors';

// ── Mocks ─────────────────────────────────────────────────────────────────────

jest.mock('@sentry/node', () => ({
  withScope: jest.fn(),
  captureException: jest.fn(),
}));

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeMocks() {
  const req = {
    path: '/test',
    method: 'POST',
    url: '/test',
    query: {},
    params: {},
    body: {},
    headers: {},
    user: undefined,
  } as unknown as Request;

  const json = jest.fn();
  const status = jest.fn().mockReturnValue({ json });
  const res = { status, json } as unknown as Response;

  const next = jest.fn() as NextFunction;

  return { req, res, status, json, next };
}

// ── AppError ──────────────────────────────────────────────────────────────────

describe('errorHandler — AppError', () => {
  it('devuelve statusCode y code del AppError', () => {
    const { req, res, status, json, next } = makeMocks();
    const err = new BadRequestError('Campo inválido', 'INVALID_FIELD', 'email');

    errorHandler(err, req, res, next);

    expect(status).toHaveBeenCalledWith(400);
    expect(json).toHaveBeenCalledWith(
      expect.objectContaining({
        success: false,
        error: expect.objectContaining({
          code: 'INVALID_FIELD',
          message: 'Campo inválido',
        }),
      })
    );
  });

  it('devuelve 401 para UnauthorizedError', () => {
    const { req, res, status, next } = makeMocks();
    errorHandler(new UnauthorizedError('No autorizado'), req, res, next);
    expect(status).toHaveBeenCalledWith(401);
  });

  it('devuelve 404 para NotFoundError', () => {
    const { req, res, status, next } = makeMocks();
    errorHandler(new NotFoundError('No encontrado'), req, res, next);
    expect(status).toHaveBeenCalledWith(404);
  });

  it('incluye array errors en 400', () => {
    const { req, res, json, next } = makeMocks();
    errorHandler(new BadRequestError('Error', 'ERR', 'field'), req, res, next);
    const payload = json.mock.calls[0][0];
    expect(Array.isArray(payload.errors)).toBe(true);
    expect(payload.errors[0].field).toBe('field');
  });

  it('no incluye field en errorResponse si AppError no tiene field', () => {
    const { req, res, json, next } = makeMocks();
    errorHandler(new UnauthorizedError('Sin acceso'), req, res, next);
    const payload = json.mock.calls[0][0];
    expect(payload.error.field).toBeUndefined();
  });
});

// ── ZodError ──────────────────────────────────────────────────────────────────

describe('errorHandler — ZodError', () => {
  it('devuelve 400 con array de errores de validación', () => {
    const { req, res, status, json, next } = makeMocks();

    const issues: ZodIssue[] = [
      {
        code: 'too_small',
        minimum: 1,
        type: 'string',
        inclusive: true,
        exact: false,
        message: 'String must contain at least 1 character(s)',
        path: ['email'],
      },
    ];
    const zodErr = new ZodError(issues);

    errorHandler(zodErr, req, res, next);

    expect(status).toHaveBeenCalledWith(400);
    const payload = json.mock.calls[0][0];
    expect(Array.isArray(payload.errors)).toBe(true);
    expect(payload.errors[0].field).toBe('email');
  });

  it('normaliza el campo a serviceType si el path está vacío', () => {
    const { req, res, json, next } = makeMocks();

    const issues: ZodIssue[] = [
      {
        code: 'invalid_union',
        unionErrors: [],
        message: 'Invalid input',
        path: [],
      },
    ];
    const zodErr = new ZodError(issues);

    errorHandler(zodErr, req, res, next);

    const payload = json.mock.calls[0][0];
    expect(payload.errors[0].field).toBe('serviceType');
  });
});

// ── Error genérico ────────────────────────────────────────────────────────────

describe('errorHandler — Error genérico', () => {
  const originalNodeEnv = process.env.NODE_ENV;

  afterEach(() => {
    process.env.NODE_ENV = originalNodeEnv;
  });

  it('devuelve 500 con mensaje genérico en producción', () => {
    process.env.NODE_ENV = 'production';
    const { req, res, status, json, next } = makeMocks();

    errorHandler(new Error('Error interno inesperado'), req, res, next);

    expect(status).toHaveBeenCalledWith(500);
    const payload = json.mock.calls[0][0];
    expect(payload.error.code).toBe('INTERNAL_ERROR');
    expect(payload.error.message).toBe('Error interno del servidor');
    expect(payload.error.details).toBeUndefined(); // sin stack en prod
  });

  it('incluye detalles del error en desarrollo', () => {
    process.env.NODE_ENV = 'development';
    const { req, res, json, next } = makeMocks();

    errorHandler(new Error('Crash de prueba'), req, res, next);

    const payload = json.mock.calls[0][0];
    expect(payload.error.message).toContain('Crash de prueba');
  });
});
