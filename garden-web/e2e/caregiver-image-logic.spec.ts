import { test, expect } from '@playwright/test';

test.describe('Caregiver Onboarding Validation', () => {

    test('Case A: Hospedaje requires 4-6 space photos', async ({ page }) => {
        const email = `test.hospedaje.${Date.now()}@mail.com`;

        await page.goto('/caregiver/register');

        // Step 1: Personal info
        await page.getByPlaceholder('Tu nombre').fill('Hospedaje');
        await page.getByPlaceholder('Tu apellido').fill('Tester');
        await page.locator('input[type="tel"]').fill('76899344');
        await page.locator('input[type="date"]').fill('1990-01-01');
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 2: Auth
        await page.locator('input[type="email"]').fill(email);
        await page.getByPlaceholder('Mínimo 8 caracteres').fill('Password123!');
        await page.getByPlaceholder('Repite tu contraseña').fill('Password123!');
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 3: Zone
        await page.getByRole('button', { name: 'Urbari' }).click();
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 4: Services - Select Hospedaje
        await page.getByRole('button', { name: /Hospedaje/ }).click();
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 5: Bio (min 50 chars)
        await page.locator('textarea').first().fill('Hola, soy un tester con mucha experiencia en hospedaje de mascotas. Tengo un espacio amplio y seguro para recibir a tus perritos.');
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 6: Home (Only for Hospedaje)
        await page.getByText('Casa con patio').click();
        await page.locator('textarea').fill('Patio de 100m2 con sombra y seguridad.');
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 7: Pricing
        await page.getByPlaceholder('120').fill('100');
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 8: Photos - Check title
        await expect(page.locator('h2')).toContainText('Fotos de tu espacio');

        // Mock the upload API
        await page.route('**/api/upload/registration-photos', async route => {
            await route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({ success: true, data: ['url1', 'url2', 'url3', 'url4'] })
            });
        });

        // Upload 4 photos
        const [fileChooser] = await Promise.all([
            page.waitForEvent('filechooser'),
            page.getByText('Haz clic para subir fotos').click(),
        ]);
        await fileChooser.setFiles([
            { name: 'p1.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('t') },
            { name: 'p2.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('t') },
            { name: 'p3.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('t') },
            { name: 'p4.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('t') },
        ]);

        await page.getByRole('button', { name: /Subir y seguir/ }).click();

        // Step 9: Terms
        await page.getByText('Acepto los Términos de servicio').click();
        await page.getByText('Acepto la Política de privacidad').click();
        await page.getByText('Acepto que GARDEN verifique mi identidad').click();
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 10: Review
        await expect(page.locator('h2')).toContainText('Revisa tu información');
        await expect(page.locator('text=HOSPEDAJE')).toBeVisible();
    });
});
