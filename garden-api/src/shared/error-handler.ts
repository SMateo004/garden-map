import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import multer from 'multer';
import { AppError } from './errors.js';
import logger from './logger.js';

export function errorHandler(
  err: Error,
  req: Request,
  res: Response,
  _next: NextFunction
): Response {
  if (err instanceof AppError) {
    const errorResponse: { code: string; message: string; field?: string } = {
      code: err.code,
      message: err.message,
    };
    if (err.field) {
      errorResponse.field = err.field;
    }
    const payload: { success: false; error: typeof errorResponse; errors?: { field: string; message: string }[] } = {
      success: false,
      error: errorResponse,
    };
    if (err.statusCode === 400 || err.statusCode === 409) {
      payload.errors = [{ field: err.field ?? 'general', message: err.message }];
    }
    return res.status(err.statusCode).json(payload);
  }

  if (err instanceof multer.MulterError) {
    if (err.code === 'LIMIT_FILE_SIZE') {
      return res.status(413).json({
        success: false,
        error: { code: 'FILE_TOO_LARGE', message: 'El archivo supera el tamaño máximo permitido (20MB)' },
      });
    }
    if (err.code === 'LIMIT_UNEXPECTED_FILE') {
      return res.status(400).json({
        success: false,
        error: { code: 'UNEXPECTED_FILE', message: `Campo de archivo inesperado: ${err.field}` },
      });
    }
    return res.status(400).json({
      success: false,
      error: { code: 'UPLOAD_ERROR', message: `Error al subir el archivo: ${err.message}` },
    });
  }

  if (err instanceof ZodError) {
    const issues = err.issues.map((issue) => {
      const rawMessage = issue.message;
      let message = rawMessage;
      if ((issue.code as string) === 'invalid_union_discriminator' || issue.code === 'invalid_union') {
        message =
          (issue.code as string) === 'invalid_union_discriminator'
            ? 'Debes seleccionar HOSPEDAJE o PASEO como tipo de servicio'
            : 'Faltan o son inválidos los campos para el tipo de servicio seleccionado';
      } else if (rawMessage === 'Invalid input' || rawMessage.includes('Invalid input')) {
        message =
          'Selecciona tipo de servicio (HOSPEDAJE o PASEO) y completa todos los campos requeridos';
      } else if (rawMessage.includes('union') || rawMessage.includes('discriminator')) {
        message = 'Debes seleccionar HOSPEDAJE o PASEO como tipo de servicio';
      }
      const field = (issue.path.join('.') || 'serviceType') as string;
      return { field: field === 'body' || field === '' ? 'serviceType' : field, message };
    });
    const errors = issues.length > 0 ? issues : [{ field: 'general', message: 'Datos inválidos' }];
    logger.warn('Zod validation failed', { issues: errors, body: req.body });
    return res.status(400).json({
      message: 'Datos inválidos',
      errors,
    });
  }

  // NOTE: Sentry capture is handled upstream by setupExpressErrorHandler (app.ts)
  // which already has full HTTP context. No manual captureException here to avoid
  // double-reporting with missing context.

  // Logging agresivo para errores no manejados
  logger.error('Unhandled error in errorHandler - RETURNING 500', {
    error: err.message,
    stack: err.stack,
    name: err.name,
    path: req.path,
    method: req.method,
    url: req.url,
    query: req.query,
    params: req.params,
    body: req.body,
    headers: {
      'content-type': req.headers['content-type'],
      'user-agent': req.headers['user-agent'],
    },
  });

  // En desarrollo, incluir más detalles del error
  return res.status(500).json({
    success: false,
    error: {
      code: 'INTERNAL_ERROR',
      message: err.message ?? 'Error interno del servidor',
      details: err.stack?.split('\n').slice(0, 5).join(' | '),
    },
  });
}
