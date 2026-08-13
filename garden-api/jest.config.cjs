/** @type {import('ts-jest').JestConfigWithTsJest} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/tests'],
  testMatch: ['**/*.test.ts'],
  setupFiles: ['<rootDir>/tests/setup.ts'],
  // Default (5000ms) es muy justo para integration tests que levantan app.ts
  // completo: corriendo una sola suite pasan en <100ms, pero con varias
  // suites pesadas compilando/corriendo en paralelo (como en CI) algunas
  // pasan de 5s por contención de CPU, no por lentitud real del código.
  testTimeout: 20000,
  moduleNameMapper: {
    '^(\\.{1,2}/.*)\\.js$': '$1',
    '^@/(.*)$': '<rootDir>/src/$1',
    '^@config/(.*)$': '<rootDir>/src/config/$1',
    '^@shared/(.*)$': '<rootDir>/src/shared/$1',
    '^@modules/(.*)$': '<rootDir>/src/modules/$1',
  },
  transform: {
    '^.+\\.tsx?$': ['ts-jest', {
      diagnostics: { ignoreCodes: [151002] },
    }],
  },
  collectCoverageFrom: [
    'src/**/*.ts',
    '!src/**/*.d.ts',
    '!src/server.ts',
  ],
  coverageDirectory: 'coverage',
  coverageThreshold: {
    global: {
      branches: 12,
      functions: 13,
      lines: 25,
      statements: 25,
    },
  },
  verbose: true,
};
