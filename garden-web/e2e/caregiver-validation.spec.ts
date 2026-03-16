import { test, expect } from '@playwright/test';

test.describe('Caregiver Validation - Detailed Logic', () => {

    test('Hospedaje vs Paseo photo requirements', async ({ page }) => {
        // Case 1: Paseo Only
        await page.goto('/caregiver/register');
        await page.getByPlaceholder('Tu nombre').fill('Paseo');
        await page.getByPlaceholder('Tu apellido').fill('User');
        await page.locator('input[type="tel"]').fill('62233445');
        await page.locator('input[type="date"]').fill('1990-01-01');
        await page.getByRole('button', { name: /Siguiente/ }).click();

        await page.locator('input[type="email"]').fill(`paseo.${Date.now()}@test.com`);
        await page.getByPlaceholder('Mínimo 8 caracteres').fill('Password123!');
        await page.getByPlaceholder('Repite tu contraseña').fill('Password123!');
        await page.getByRole('button', { name: /Siguiente/ }).click();

        await page.getByRole('button', { name: 'Norte' }).click();
        await page.getByRole('button', { name: /Siguiente/ }).click();

        await page.getByRole('button', { name: /Paseos/ }).click();
        await page.getByRole('button', { name: /Siguiente/ }).click();

        await page.locator('textarea').first().fill('Hola soy paseador de perros profesional con 5 años de experiencia. Adoro a los animales.');
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 6 (Home) should be skipped for Paseo Only
        await expect(page.locator('h2')).toContainText('Define tus tarifas');

        await page.getByPlaceholder('30').fill('40');
        await page.getByPlaceholder('50').fill('70');
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 8: Photos - Should say "personales" and min 2
        await expect(page.locator('h2')).toContainText('Fotos personales');

        await page.route('**/api/upload/registration-photos', async route => {
            await route.fulfill({ status: 200, json: { success: true, data: { urls: ['u1', 'u2'] } } });
        });

        const [fileChooser] = await Promise.all([
            page.waitForEvent('filechooser'),
            page.getByText('Haz clic para subir fotos').click(),
        ]);
        await fileChooser.setFiles([
            { name: '1.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('1') },
            { name: '2.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('2') },
        ]);

        await page.getByRole('button', { name: /Subir y seguir/ }).click();

        // Step 9: Terms - Use getByText with exact false and click since labels might be tricky
        await page.getByText('Acepto los Términos de servicio', { exact: false }).click();
        await page.getByText('Acepto la Política de privacidad', { exact: false }).click();
        await page.getByText('Acepto que GARDEN verifique mi identidad', { exact: false }).click();
        await page.getByRole('button', { name: /Siguiente/ }).click();

        // Step 10: Review
        await expect(page.locator('h2')).toContainText('Revisa tu información');
        await expect(page.locator('text=PASEO')).toBeVisible();
    });
});
