/**
 * Custom errors for GARDEN API.
 * Modular: extend for new domains without changing handlers.
 */

export class AppError extends Error {
  public readonly field?: string;

  constructor(
    message: string,
    public readonly statusCode: number,
    public readonly code: string,
    public readonly isOperational = true,
    field?: string
  ) {
    super(message);
    this.name = this.constructor.name;
    this.field = field;
    Error.captureStackTrace(this, this.constructor);
  }
}

export class BadRequestError extends AppError {
  constructor(message: string, code = 'BAD_REQUEST', field?: string) {
    super(message, 400, code, true, field);
  }
}

export class UnauthorizedError extends AppError {
  constructor(message = 'No autorizado', code = 'UNAUTHORIZED') {
    super(message, 401, code);
  }
}

export class ForbiddenError extends AppError {
  constructor(message = 'Acceso denegado', code = 'FORBIDDEN') {
    super(message, 403, code);
  }
}

export class NotFoundError extends AppError {
  constructor(message: string, code = 'NOT_FOUND') {
    super(message, 404, code);
  }
}

export class ConflictError extends AppError {
  constructor(message: string, code = 'CONFLICT', field?: string) {
    super(message, 409, code, true, field);
  }
}

// Caregiver-profile specific
export class CaregiverProfileValidationError extends BadRequestError {
  constructor(message: string, code = 'CAREGIVER_VALIDATION') {
    super(message, code);
  }
}

export class CaregiverNotFoundError extends NotFoundError {
  constructor(id: string) {
    super(`Cuidador no encontrado: ${id}`, 'CAREGIVER_NOT_FOUND');
  }
}

export class PhotoUploadError extends BadRequestError {
  constructor(message: string) {
    super(message, 'PHOTO_UPLOAD_ERROR');
  }
}

/** Reserva no puede crearse: fecha/slot ya no disponible u otra regla de negocio. */
export class AvailabilityConflictError extends ConflictError {
  constructor(message: string, field?: string) {
    super(message, 'AVAILABILITY_CONFLICT', field);
    this.name = 'AvailabilityConflictError';
  }
}

/** Datos de reserva inválidos (fechas, servicio, mascota, etc.). */
export class BookingValidationError extends BadRequestError {
  constructor(message: string, code = 'BOOKING_VALIDATION', field?: string) {
    super(message, code, field);
  }
}

export class BookingNotFoundError extends NotFoundError {
  constructor(id: string) {
    super(`Reserva no encontrada: ${id}`, 'BOOKING_NOT_FOUND');
  }
}
