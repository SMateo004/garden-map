import winston from 'winston';

const level = process.env.LOG_LEVEL ?? 'info';

const logger = winston.createLogger({
  level,
  format: winston.format.combine(
    winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  defaultMeta: { service: 'garden-api' },
  transports: [
    // Disable file logging in dev because OneDrive makes it very slow
    /*
    new winston.transports.File({ filename: 'logs/error.log', level: 'error' }),
    new winston.transports.File({ filename: 'logs/combined.log' }),
    */
  ],
});

// Always log to console — in production Render captures stdout
logger.add(
  new winston.transports.Console({
    format:
      process.env.NODE_ENV === 'production'
        ? winston.format.json()
        : winston.format.combine(
            winston.format.colorize(),
            winston.format.simple()
          ),
  })
);

export default logger;
