import {
  loginSchema,
  registerCaregiverSchema,
  phoneSchema,
  patchCaregiverProfileSchema,
} from '../../src/modules/auth/auth.validation';

describe('Auth validation (Zod)', () => {
  describe('phoneSchema', () => {
    it('accepts +591 followed by 8-9 digits', () => {
      expect(phoneSchema.parse('+59171234567')).toBe('+59171234567');
      expect(phoneSchema.parse('+591712345678')).toBe('+591712345678');
    });

    it('rejects invalid phone (not +591)', () => {
      expect(() => phoneSchema.parse('+5491112345678')).toThrow();
      expect(() => phoneSchema.parse('71234567')).toThrow();
    });

    it('rejects phone with wrong length', () => {
      expect(() => phoneSchema.parse('+5917123456')).toThrow();   // 7 digits
      expect(() => phoneSchema.parse('+5917123456789')).toThrow(); // 10 digits
    });
  });

  describe('loginSchema', () => {
    it('accepts valid email and password', () => {
      expect(loginSchema.parse({ email: 'a@b.co', password: 'secret' })).toEqual({
        email: 'a@b.co',
        password: 'secret',
      });
    });

    it('rejects invalid email', () => {
      expect(() => loginSchema.parse({ email: 'invalid', password: 'x' })).toThrow();
    });

    it('rejects empty password', () => {
      expect(() => loginSchema.parse({ email: 'a@b.co', password: '' })).toThrow();
    });
  });

  describe('registerCaregiverSchema', () => {
    const validUser = {
      email: 'c@test.com',
      password: 'password123',
      firstName: 'A',
      lastName: 'B',
      phone: '+59171234567',
      country: 'Bolivia',
      city: 'Santa Cruz',
      isOver18: true,
    };
    const validProfile = {
      servicesOffered: ['HOSPEDAJE'],
      photos: ['https://x.co/1.jpg', 'https://x.co/2.jpg', 'https://x.co/3.jpg', 'https://x.co/4.jpg'],
      zone: 'EQUIPETROL',
      bio: 'A'.repeat(50),
      ciAnversoUrl: 'https://x.co/ci-anverso.jpg',
      ciReversoUrl: 'https://x.co/ci-reverso.jpg',
    };

    it('accepts valid full body', () => {
      expect(registerCaregiverSchema.parse({ user: validUser, profile: validProfile })).toBeDefined();
    });

    it('rejects isOver18 false (400 invalid)', () => {
      expect(() =>
        registerCaregiverSchema.parse({
          user: { ...validUser, isOver18: false },
          profile: validProfile,
        })
      ).toThrow();
    });

    it('rejects invalid phone', () => {
      expect(() =>
        registerCaregiverSchema.parse({
          user: { ...validUser, phone: '+5491112345678' },
          profile: validProfile,
        })
      ).toThrow();
    });

    it('rejects short password', () => {
      expect(() =>
        registerCaregiverSchema.parse({
          user: { ...validUser, password: 'short' },
          profile: validProfile,
        })
      ).toThrow();
    });

    it('rejects profile with fewer than 4 photos', () => {
      expect(() =>
        registerCaregiverSchema.parse({
          user: validUser,
          profile: { ...validProfile, photos: ['https://x.co/1.jpg', 'https://x.co/2.jpg'] },
        })
      ).toThrow();
    });

    it('rejects profile without zone', () => {
      expect(() =>
        registerCaregiverSchema.parse({
          user: validUser,
          profile: { ...validProfile, zone: undefined },
        })
      ).toThrow();
    });

    it('rejects profile with bio shorter than 50 chars', () => {
      expect(() =>
        registerCaregiverSchema.parse({
          user: validUser,
          profile: { ...validProfile, bio: 'short' },
        })
      ).toThrow();
    });

    it('accepts profile with spaceType as array (multi-select)', () => {
      expect(
        registerCaregiverSchema.parse({
          user: validUser,
          profile: { ...validProfile, spaceType: ['Casa con patio', 'Departamento amplio'] },
        })
      ).toBeDefined();
    });

    it('rejects profile when spaceType is string (legacy single value)', () => {
      expect(() =>
        registerCaregiverSchema.parse({
          user: validUser,
          profile: { ...validProfile, spaceType: 'Casa con patio' as unknown as string[] },
        })
      ).toThrow();
    });
  });

  describe('patchCaregiverProfileSchema', () => {
    it('accepts empty object (partial update)', () => {
      expect(patchCaregiverProfileSchema.parse({})).toEqual({});
    });

    it('accepts valid partial fields', () => {
      expect(
        patchCaregiverProfileSchema.parse({
          bio: 'New bio',
          maxPets: 2,
        })
      ).toEqual({ bio: 'New bio', maxPets: 2 });
    });

    it('rejects text field shorter than 100 when provided', () => {
      expect(() =>
        patchCaregiverProfileSchema.parse({
          experienceDescription: 'short',
        })
      ).toThrow();
    });
  });
});
