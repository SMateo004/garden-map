import { test, expect } from '@playwright/test';

test.describe('Caregiver Full Validation Flow', () => {
    const email = `val.${Date.now()}@test.com`;
    const password = 'Password123!';

    test('Should complete full onboarding and validate logic', async ({ page }) => {
        // --- 1. REGISTER WIZARD (HOSPEDAJE) ---
        await page.goto('/caregiver/register');

        // Step 1: Personal
        await page.getByPlaceholder('Tu nombre').fill('Mateo');
        await page.getByPlaceholder('Tu apellido').fill('Vargas');
        await page.locator('input[type="tel"]').fill('76812345');
        await page.locator('input[type="date"]').fill('1990-05-15');
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 2: Auth
        await page.locator('input[type="email"]').fill(email);
        await page.getByPlaceholder('Mínimo 8 caracteres').fill(password);
        await page.getByPlaceholder('Repite tu contraseña').fill(password);
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 3: Zone
        await page.getByRole('button', { name: 'Equipetrol' }).click();
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 4: Services
        await page.getByRole('button', { name: /Hospedaje/ }).click();
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 5: Bio
        await page.locator('textarea').first().fill('Hola, soy Mateo y tengo mucha experiencia cuidando perros de todos los tamaños. Mi espacio es seguro y divertido.');
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 6: Home
        await page.getByText('Casa con patio').click();
        await page.locator('textarea').fill('Es una casa de dos pisos con un patio trasero de 50 metros cuadrados totalmente bardeado.');
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 7: Pricing
        await page.getByPlaceholder('120').fill('150');
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 8: Photos (Logic Validation)
        await expect(page.locator('h2')).toContainText('Fotos de tu espacio');
        await expect(page.locator('text=Mínimo 4, máximo 6')).toBeVisible();

        await page.route('**/api/upload/registration-photos', async route => {
            await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ success: true, data: ['url1', 'url2', 'url3', 'url4'] }) });
        });

        const [fileChooser] = await Promise.all([
            page.waitForEvent('filechooser'),
            page.getByText('Haz clic para subir fotos').click(),
        ]);
        await fileChooser.setFiles([
            { name: '1.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('1') },
            { name: '2.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('2') },
            { name: '3.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('3') },
            { name: '4.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('4') },
        ]);

        await page.getByRole('button', { name: /Subir y seguir/ }).click();

        // Step 9: Terms
        await page.getByText('Acepto los Términos de servicio').click();
        await page.getByText('Acepto la Política de privacidad').click();
        await page.getByText('Acepto que GARDEN verifique mi identidad').click();
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 10: Final
        await page.getByRole('button', { name: /Enviar solicitud/ }).click();

        // --- 2. ONBOARDING FLOW ---
        await page.waitForURL('**/caregiver/onboarding');
        await page.waitForSelector('text=Paso 1 de 5');

        // Step 1: Profile Photo
        await page.route('**/api/upload/profile-photo', async route => {
            await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ success: true, data: { profilePhoto: 'p-photo.jpg' } }) });
        });

        const [photoChooser] = await Promise.all([
            page.waitForEvent('filechooser'),
            page.getByRole('button', { name: 'Subir foto' }).click(),
        ]);
        await photoChooser.setFiles([{ name: 'me.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('me') }]);

        await expect(page.locator('text=Paso 2 de 5')).toBeVisible();

        // Step 2: CI
        await page.route('**/api/auth/upload-ci', async route => {
            await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ success: true, data: { ciAnversoUrl: 'anv.jpg', ciReversoUrl: 'rev.jpg' } }) });
        });

        const ciInputs = page.locator('input[type="file"]');
        await ciInputs.nth(0).setInputFiles([{ name: 'a.jpg', buffer: Buffer.from('a'), mimeType: 'image/jpeg' }]);
        await ciInputs.nth(1).setInputFiles([{ name: 'r.jpg', buffer: Buffer.from('r'), mimeType: 'image/jpeg' }]);
        await page.getByRole('button', { name: 'Enviar documentos' }).click();

        await expect(page.locator('text=Paso 3 de 5')).toBeVisible();

        // Step 3: Email Stub
        await page.getByRole('button', { name: /Omitir por ahora/ }).click();
        await expect(page.locator('text=Paso 4 de 5')).toBeVisible();

        // --- 3. QUESTIONNAIRE ---
        await page.getByRole('button', { name: /Completar cuestionario/ }).click();
        await page.waitForURL('**/caregiver/questionnaire');

        // Partially fill and check persistence
        await page.getByText('Pequeño (0-7kg)').click();
        await page.getByText('Grande (15-40kg)').click();

        // Bio should be filled from Register
        const bioTextarea = page.locator('textarea[placeholder*="Ej: Tengo 2 labradores"]').first();
        await expect(bioTextarea).not.toBeEmpty();

        await page.getByRole('button', { name: 'Continuar' }).click();
        await page.waitForURL('**/caregiver/onboarding');
        await expect(page.locator('text=Paso 5 de 5')).toBeVisible();

        // --- 4. AVAILABILITY ---
        await page.getByRole('button', { name: /Configurar disponibilidad/ }).click();
        await page.waitForURL('**/caregiver/availability');

        // Click a day (today or tomorrow to be safe)
        const today = new Date().getDate();
        // In react-calendar, the day button usually has the text or an aria-label
        await page.locator(`.react-calendar__month-view__days__day:has-text("${today}")`).first().click();

        await page.getByText('Disponible este día').check();
        await page.getByText('Mañana (6am–11am)').check();

        await page.getByRole('button', { name: 'Guardar disponibilidad' }).click();
        await expect(page.locator('text=Guardado')).toBeVisible();

        // Final Check: Everything done
        await page.goto('/caregiver/onboarding');
        // If all complete, it might redirect to Profile or Dashboard
        // But since we have the "Email Stub" and "isStep3Complete" fix, let's see.
    });
});
