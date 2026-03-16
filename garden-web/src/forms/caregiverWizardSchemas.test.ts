import { describe, it, expect } from 'vitest';
import {
  step1Schema,
  step2Schema,
  step3Schema,
  step4Schema,
  step5Schema,
  step6Schema,
  step7Schema,
  step9Schema,
} from './caregiverWizardSchemas';

describe('caregiverWizardSchemas', () => {
  describe('step1Schema', () => {
    it('accepts valid name and phone', () => {
      expect(step1Schema.parse({ firstName: 'Juan', lastName: 'Pérez', phone: '+59171234567' })).toBeDefined();
    });
    it('rejects invalid phone', () => {
      expect(() => step1Schema.parse({ firstName: 'J', lastName: 'P', phone: '+5491112345678' })).toThrow();
    });
    it('rejects empty firstName', () => {
      expect(() => step1Schema.parse({ firstName: '', lastName: 'P', phone: '+59171234567' })).toThrow();
    });
  });

  describe('step2Schema', () => {
    it('accepts matching passwords', () => {
      expect(step2Schema.parse({ email: 'a@b.co', password: 'password123', confirmPassword: 'password123' })).toBeDefined();
    });
    it('rejects password mismatch', () => {
      expect(() => step2Schema.parse({ email: 'a@b.co', password: 'password123', confirmPassword: 'other' })).toThrow();
    });
    it('rejects short password', () => {
      expect(() => step2Schema.parse({ email: 'a@b.co', password: 'short', confirmPassword: 'short' })).toThrow();
    });
  });

  describe('step3Schema', () => {
    it('accepts valid zone', () => {
      expect(step3Schema.parse({ zone: 'EQUIPETROL' })).toEqual({ zone: 'EQUIPETROL' });
    });
    it('rejects invalid zone', () => {
      expect(() => step3Schema.parse({ zone: 'INVALID' })).toThrow();
    });
  });

  describe('step4Schema', () => {
    it('accepts at least one service', () => {
      expect(step4Schema.parse({ servicesOffered: ['HOSPEDAJE'] })).toBeDefined();
      expect(step4Schema.parse({ servicesOffered: ['PASEO', 'HOSPEDAJE'] })).toBeDefined();
    });
    it('rejects empty services', () => {
      expect(() => step4Schema.parse({ servicesOffered: [] })).toThrow();
    });
  });

  describe('step5Schema', () => {
    it('accepts bio 50-500 chars', () => {
      const bio = 'a'.repeat(50);
      expect(step5Schema.parse({ bioSummary: bio, bioDetail: undefined })).toBeDefined();
    });
    it('rejects bio under 50 chars', () => {
      expect(() => step5Schema.parse({ bioSummary: 'short', bioDetail: undefined })).toThrow();
    });
  });

  describe('step6Schema', () => {
    it('accepts spaceType array and spaceDescription', () => {
      expect(step6Schema.parse({ spaceType: ['Casa con patio'], spaceDescription: 'Amplio' })).toBeDefined();
    });
  });

  describe('step7Schema', () => {
    it('accepts optional prices', () => {
      expect(step7Schema.parse({ pricePerDay: 120, pricePerWalk30: 30, pricePerWalk60: 50 })).toBeDefined();
    });
  });

  describe('step9Schema', () => {
    it('accepts all three checkboxes true', () => {
      expect(step9Schema.parse({ termsAccepted: true, privacyAccepted: true, verificationAccepted: true })).toBeDefined();
    });
    it('rejects termsAccepted false', () => {
      expect(() => step9Schema.parse({ termsAccepted: false, privacyAccepted: true, verificationAccepted: true })).toThrow();
    });
  });
});
