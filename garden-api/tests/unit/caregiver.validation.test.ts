/**
 * Unit: Validación Zod para POST y query GET /api/caregivers
 */
import {
  createCaregiverProfileSchema,
  listCaregiversQuerySchema,
  caregiverPhotosFilesSchema,
  PHOTO_COUNT,
} from '../../src/modules/caregiver-service/caregiver.validation';

describe('Caregiver validation (Zod)', () => {
  describe('createCaregiverProfileSchema', () => {
    const validBody = {
      bio: 'Casa con patio, experiencia con perros.',
      zone: 'EQUIPETROL',
      servicesOffered: ['HOSPEDAJE', 'PASEO'],
    };

    it('accepts valid body', () => {
      expect(createCaregiverProfileSchema.parse(validBody)).toEqual(validBody);
    });

    it('accepts with optional spaceType and prices', () => {
      const withOptionals = {
        ...validBody,
        spaceType: 'Casa con patio',
        pricePerDay: 100,
        pricePerWalk30: 30,
      };
      expect(createCaregiverProfileSchema.parse(withOptionals)).toMatchObject(withOptionals);
    });

    it('rejects empty bio', () => {
      expect(() =>
        createCaregiverProfileSchema.parse({ ...validBody, bio: '' })
      ).toThrow();
    });

    it('rejects bio over 500 chars', () => {
      expect(() =>
        createCaregiverProfileSchema.parse({
          ...validBody,
          bio: 'a'.repeat(501),
        })
      ).toThrow();
    });

    it('rejects invalid zone', () => {
      expect(() =>
        createCaregiverProfileSchema.parse({ ...validBody, zone: 'INVALID' })
      ).toThrow();
    });

    it('rejects empty servicesOffered', () => {
      expect(() =>
        createCaregiverProfileSchema.parse({ ...validBody, servicesOffered: [] })
      ).toThrow();
    });

    it('rejects duplicate services', () => {
      expect(() =>
        createCaregiverProfileSchema.parse({
          ...validBody,
          servicesOffered: ['HOSPEDAJE', 'HOSPEDAJE'],
        })
      ).toThrow();
    });

    it('coerces price strings to number', () => {
      const parsed = createCaregiverProfileSchema.parse({
        ...validBody,
        pricePerDay: '120',
      });
      expect(parsed.pricePerDay).toBe(120);
    });
  });

  describe('listCaregiversQuerySchema', () => {
    it('defaults page 1 and limit 10', () => {
      const parsed = listCaregiversQuerySchema.parse({});
      expect(parsed.page).toBe(1);
      expect(parsed.limit).toBe(10);
    });

    it('accepts valid service', () => {
      expect(listCaregiversQuerySchema.parse({ service: 'hospedaje' }).service).toBe('hospedaje');
      expect(listCaregiversQuerySchema.parse({ service: 'paseo' }).service).toBe('paseo');
      expect(listCaregiversQuerySchema.parse({ service: 'ambos' }).service).toBe('ambos');
    });

    it('accepts valid zone', () => {
      expect(listCaregiversQuerySchema.parse({ zone: 'equipetrol' }).zone).toBe('equipetrol');
      expect(listCaregiversQuerySchema.parse({ zone: 'centro_san_martin' }).zone).toBe('centro_san_martin');
    });

    it('accepts priceRange', () => {
      expect(listCaregiversQuerySchema.parse({ priceRange: 'economico' }).priceRange).toBe('economico');
    });

    it('rejects invalid zone', () => {
      expect(() => listCaregiversQuerySchema.parse({ zone: 'invalid_zone' })).toThrow();
    });

    it('coerces page and limit from string', () => {
      const parsed = listCaregiversQuerySchema.parse({ page: '2', limit: '20' });
      expect(parsed.page).toBe(2);
      expect(parsed.limit).toBe(20);
    });
  });

  describe('caregiverPhotosFilesSchema', () => {
    it('rejects fewer than 4 files', () => {
      expect(() => caregiverPhotosFilesSchema.parse([])).toThrow(/Mínimo 4/);
      expect(() => caregiverPhotosFilesSchema.parse([1, 2, 3])).toThrow(/Mínimo 4/);
    });

    it('accepts 4 to 6 files', () => {
      const four = [1, 2, 3, 4];
      expect(caregiverPhotosFilesSchema.parse(four)).toEqual(four);
      expect(caregiverPhotosFilesSchema.parse([...four, 5, 6])).toHaveLength(6);
    });

    it('rejects more than 6 files', () => {
      expect(() =>
        caregiverPhotosFilesSchema.parse([1, 2, 3, 4, 5, 6, 7])
      ).toThrow(/Máximo 6/);
    });
  });
});
