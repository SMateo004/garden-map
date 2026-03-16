import { test, expect } from '@playwright/test';

test.describe('Caregiver Onboarding Flow & Step Enforcement', () => {

    test('Flow: Auto-start after registration and enforce steps', async ({ page }) => {
        const email = `test.onboarding.${Date.now()}@mail.com`;
        const password = 'Password123!';

        // 1. Register a new user
        await page.goto('/caregiver/register');

        // Step 1: Personal info
        await page.fill('input[placeholder="Tu nombre"]', 'Onboarding');
        await page.fill('input[placeholder="Tu apellido"]', 'Tester');
        await page.fill('input[type="tel"]', '76899346');
        await page.fill('input[type="date"]', '1990-01-01');
        await page.click('button:has-text("Siguiente")');

        // Step 2: Auth
        await page.fill('input[type="email"]', email);
        await page.fill('input[placeholder="Contraseña"]', password);
        await page.fill('input[placeholder="Confirmar contraseña"]', password);
        await page.click('button:has-text("Siguiente")');

        // Step 3: Zone
        await page.click('button:has-text("Urbari")');
        await page.click('button:has-text("Siguiente")');

        // Step 4: Services
        await page.click('label:has-text("Paseo")');
        await page.click('button:has-text("Siguiente")');

        // Step 5: Bio
        await page.fill('textarea', 'Bio minimal description for testing onboarding flow auto-start. Must be at least 50 chars long to complete Step 4 later.');
        await page.click('button:has-text("Siguiente")');

        // Step 6 skipped for Paseo

        // Step 7: Pricing
        await page.fill('input[placeholder="30"]', '25');
        await page.fill('input[placeholder="50"]', '45');
        await page.click('button:has-text("Siguiente")');

        // Step 8: Photos - Mocking
        await page.route('**/api/upload/registration-photos', async route => {
            await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ success: true, data: { urls: ['url1', 'url2'] } }) });
        });
        const fileChooserPromise = page.waitForEvent('filechooser');
        await page.locator('label:has-text("Haz clic para subir fotos")').click();
        const fileChooser = await fileChooserPromise;
        await fileChooser.setFiles([{ name: 'p1.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('t') }, { name: 'p2.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('t') }]);
        await page.click('button:has-text("Siguiente")');

        // Step 9: Terms
        await page.click('label:has-text("Acepto los Términos y Condiciones")');
        await page.click('label:has-text("Acepto la Política de Privacidad")');
        await page.click('label:has-text("Acepto la Verificación de mi identidad")');
        await page.click('button:has-text("Siguiente")');

        // Step 10: Final
        await page.route('**/api/auth/register-caregiver', async route => {
            await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ success: true, data: { user: { id: 'u1', email }, token: 'mock-token' } }) });
        });
        // Also mock getMyProfile
        await page.route('**/api/caregiver/my-profile', async route => {
            await route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({
                    success: true,
                    data: {
                        id: 'p1',
                        status: 'DRAFT',
                        user: { firstName: 'Onboarding', lastName: 'Tester', email },
                        servicesOffered: ['PASEO'],
                        bio: 'Bio minimal description for testing onboarding flow auto-start. Must be at least 50 chars long to complete Step 4 later.',
                        zone: 'URBARI',
                        photos: ['url1', 'url2']
                    }
                })
            });
        });

        await page.click('button:has-text("Finalizar registro")');

        // 2. EXPECT REDIRECT TO DASHBOARD -> ONBOARDING
        // The dashboard has a check: if (needsOnboarding) navigate('/caregiver/onboarding')
        await page.waitForURL('**/caregiver/onboarding');
        await expect(page.locator('h1')).toContainText('Completa tu perfil');
        await expect(page.locator('p')).toContainText('Paso 1 de 5: Foto de perfil');

        // 4. Complete Step 1: Profile Photo
        await page.route('**/api/upload/profile-photo', async route => {
            await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ success: true, data: { profilePhoto: 'new-profile-photo.jpg' } }) });
        });
        // Update profile mock for next getMyProfile call
        await page.route('**/api/caregiver/my-profile', async route => {
            await route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({
                    success: true,
                    data: {
                        id: 'p1',
                        status: 'DRAFT',
                        user: { firstName: 'Onboarding', lastName: 'Tester', email },
                        profilePhoto: 'new-profile-photo.jpg', // NOW COMPLETED
                        servicesOffered: ['PASEO'],
                        bio: 'Bio minimal description for testing onboarding flow auto-start. Must be at least 50 chars long to complete Step 4 later.',
                        zone: 'URBARI',
                        photos: ['url1', 'url2']
                    }
                })
            });
        });

        const photoChooserPromise = page.waitForEvent('filechooser');
        await page.click('button:has-text("Subir foto")');
        const photoChooser = await photoChooserPromise;
        await photoChooser.setFiles([{ name: 'p.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('t') }]);

        await expect(page.locator('p')).toContainText('Paso 2 de 5: Verificación de identidad');

        // 5. Complete Step 2: Identity (CI)
        await page.route('**/api/auth/upload-ci', async route => {
            await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ success: true, data: { ciAnversoUrl: 'anv.jpg', ciReversoUrl: 'rev.jpg' } }) });
        });
        await page.route('**/api/caregiver/profile', async route => {
            await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ success: true, data: { profileId: 'p1' } }) });
        });
        // Update profile mock for next getMyProfile call
        await page.route('**/api/caregiver/my-profile', async route => {
            await route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({
                    success: true,
                    data: {
                        id: 'p1',
                        status: 'DRAFT',
                        user: { firstName: 'Onboarding', lastName: 'Tester', email },
                        profilePhoto: 'new-profile-photo.jpg',
                        ciAnversoUrl: 'anv.jpg', // NOW COMPLETED
                        ciReversoUrl: 'rev.jpg', // NOW COMPLETED
                        servicesOffered: ['PASEO'],
                        bio: 'Bio minimal description for testing onboarding flow auto-start. Must be at least 50 chars long to complete Step 4 later.',
                        zone: 'URBARI',
                        photos: ['url1', 'url2']
                    }
                })
            });
        });

        await page.locator('input[type="file"]').nth(0).setInputFiles([{ name: 'a.jpg', buffer: Buffer.from('t'), mimeType: 'image/jpeg' }]);
        await page.locator('input[type="file"]').nth(1).setInputFiles([{ name: 'r.jpg', buffer: Buffer.from('t'), mimeType: 'image/jpeg' }]);

        await page.click('button:has-text("Enviar documentos")');
        await expect(page.locator('p')).toContainText('Paso 3 de 5: Verificación de correo');

        // 6. Complete Step 3: Email (placeholder)
        await page.click('button:has-text("Omitir por ahora")');
        await expect(page.locator('p')).toContainText('Paso 4 de 5: Perfil del cuidador');

        // 7. Complete Step 4: Questionnaire
        await page.click('button:has-text("Completar cuestionario")');
        await page.waitForURL('**/caregiver/questionnaire');

        // Check sections exist
        await expect(page.locator('section h2:has-text("1. Servicios")')).toBeVisible();
        await expect(page.locator('section h2:has-text("7. Tarifas (Bs)")')).toBeVisible();

        // Fill minimal to complete Step 4 (Bio already > 50 in our mock and data)
        await page.click('button:has-text("Continuar")');

        await page.waitForURL('**/caregiver/onboarding');
        await expect(page.locator('p')).toContainText('Paso 5 de 5: Disponibilidad');
    });
});
