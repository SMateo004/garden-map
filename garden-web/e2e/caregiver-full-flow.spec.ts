/**
 * E2E: Full caregiver flow with mocked API.
 * - Register: wizard steps 1–10, mock upload + register → redirect dashboard.
 * - Login: email/password, mock login + me → dashboard.
 */

import { test, expect } from '@playwright/test';

test.describe('Caregiver full flow (mocked API)', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.evaluate(() => {
      localStorage.removeItem('garden_access_token');
      localStorage.removeItem('garden_wizard_draft');
    });
  });

  test('login with valid credentials shows dashboard', async ({ page }) => {
    await page.route('**/api/auth/login', async (route) => {
      if (route.request().method() !== 'POST') return route.fallback();
      const body = route.request().postDataJSON();
      if (body?.email && body?.password) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            success: true,
            data: {
              accessToken: 'mock-jwt-token',
              expiresIn: '7d',
              user: { id: 'u1', email: body.email, role: 'CAREGIVER', firstName: 'Juan', lastName: 'Pérez' },
            },
          }),
        });
        return;
      }
      await route.fallback();
    });
    await page.route('**/api/auth/me', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          data: { id: 'u1', email: 'cuidador@test.com', role: 'CAREGIVER', firstName: 'Juan', lastName: 'Pérez' },
        }),
      });
    });

    await page.goto('/caregiver/auth');
    await page.getByPlaceholderText(/tucorreo@email\.com/).fill('cuidador@test.com');
    await page.locator('input[type="password"]').first().fill('password123');
    await page.getByRole('button', { name: /Iniciar sesión/i }).click();

    await expect(page).toHaveURL(/\/caregiver\/dashboard/, { timeout: 8000 });
    await expect(page.getByText(/Tu perfil/)).toBeVisible({ timeout: 5000 });
    await expect(page.getByText(/Juan/)).toBeVisible();
  });

  test('register full wizard then submit (mocked upload + register) lands on dashboard', async ({ page }) => {
    await page.route('**/api/upload/registration-photos', async (route) => {
      if (route.request().method() !== 'POST') return route.fallback();
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          data: {
            urls: [
              'https://res.cloudinary.com/1.jpg',
              'https://res.cloudinary.com/2.jpg',
              'https://res.cloudinary.com/3.jpg',
              'https://res.cloudinary.com/4.jpg',
            ],
          },
        }),
      });
    });
    await page.route('**/api/auth/caregiver/register', async (route) => {
      if (route.request().method() !== 'POST') return route.fallback();
      await route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          data: {
            user: { id: 'u1', email: 'new@test.com', role: 'CAREGIVER', firstName: 'New', lastName: 'User' },
            profileId: 'p1',
            verificationStatus: 'PENDING_REVIEW',
            accessToken: 'mock-jwt',
            expiresIn: '7d',
          },
        }),
      });
    });
    await page.route('**/api/auth/me', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          data: { id: 'u1', email: 'new@test.com', role: 'CAREGIVER', firstName: 'New', lastName: 'User' },
        }),
      });
    });

    await page.goto('/caregiver/register');
    await expect(page.getByText(/Paso 1 de 10/)).toBeVisible({ timeout: 5000 });

    await page.getByPlaceholderText(/Tu nombre/).fill('New');
    await page.getByPlaceholderText(/Tu apellido/).fill('User');
    await page.getByPlaceholderText(/\+591/).fill('+59171234567');
    await page.getByRole('button', { name: /Siguiente/ }).click();

    await page.getByPlaceholderText(/tucorreo@email\.com/).fill('new@test.com');
    await page.getByPlaceholderText(/Mínimo 8 caracteres/).fill('password123');
    await page.getByPlaceholderText(/Repite tu contraseña/).fill('password123');
    await page.getByRole('button', { name: /Siguiente/ }).click();

    await page.getByText(/Equipetrol/).click();
    await page.getByRole('button', { name: /Siguiente/ }).click();

    await page.getByText(/Hospedaje/).click();
    await page.getByRole('button', { name: /Siguiente/ }).click();

    const bio = 'Tengo experiencia con mascotas desde hace años. Casa con patio y trabajo desde casa.';
    await page.getByPlaceholderText(/Tengo 2 labradores/).fill(bio);
    await page.getByRole('button', { name: /Siguiente/ }).click();

    await page.getByPlaceholderText(/Casa con patio/).fill('Casa con patio cercado');
    await page.getByRole('button', { name: /Siguiente/ }).click();

    await page.locator('input[type="number"]').first().fill('120');
    await page.getByRole('button', { name: /Siguiente/ }).click();

    const photoInput = page.locator('input[type="file"]');
    await photoInput.setInputFiles([
      { name: '1.jpg', mimeType: 'image/jpeg', buffer: Buffer.alloc(200) },
      { name: '2.jpg', mimeType: 'image/jpeg', buffer: Buffer.alloc(200) },
      { name: '3.jpg', mimeType: 'image/jpeg', buffer: Buffer.alloc(200) },
      { name: '4.jpg', mimeType: 'image/jpeg', buffer: Buffer.alloc(200) },
    ]);
    await page.getByRole('button', { name: /Subir y seguir/ }).click();

    await expect(page.getByText(/Términos y condiciones/)).toBeVisible({ timeout: 5000 });
    await page.getByRole('checkbox', { name: /Términos de servicio/ }).click();
    await page.getByRole('checkbox', { name: /Política de privacidad/ }).click();
    await page.getByRole('checkbox', { name: /verifique mi identidad/ }).click();
    await page.getByRole('button', { name: /Siguiente/ }).click();

    await expect(page.getByText(/Revisa tu información/)).toBeVisible({ timeout: 3000 });
    await page.getByRole('button', { name: /Enviar solicitud/ }).click();

    await expect(page).toHaveURL(/\/caregiver\/dashboard/, { timeout: 10000 });
    await expect(page.getByText(/Tu perfil/)).toBeVisible({ timeout: 5000 });
  });
});
