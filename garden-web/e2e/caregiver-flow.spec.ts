/**
 * E2E: Flujo cuidador (auth → wizard → dashboard).
 * Requiere API en marcha para login/register.
 */

import { test, expect } from '@playwright/test';

test.describe('Caregiver flow', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.evaluate(() => localStorage.removeItem('garden_access_token'));
  });

  test('Conviértete en cuidador navigates to auth page', async ({ page }) => {
    await page.goto('/caregiver/auth');
    await expect(page).toHaveURL(/\/caregiver\/auth/);
    await expect(page.getByPlaceholderText(/tucorreo@email\.com/)).toBeVisible({ timeout: 5000 });
    await expect(page.getByRole('button', { name: /Continuar/i })).toBeVisible();
  });

  test('auth page has email-first flow', async ({ page }) => {
    await page.goto('/caregiver/auth');
    await expect(page.getByPlaceholderText(/tucorreo@email\.com/)).toBeVisible({ timeout: 5000 });
    await expect(page.getByRole('button', { name: /Continuar/i })).toBeVisible();
  });

  test('new email navigates to register wizard', async ({ page }) => {
    await page.route('**/api/auth/check-email*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ success: true, data: { exists: false } }),
      });
    });

    await page.goto('/caregiver/auth');
    await page.getByPlaceholderText(/tucorreo@email\.com/).fill('nuevo@test.com');
    await page.getByRole('button', { name: /Continuar/i }).click();
    await expect(page).toHaveURL(/\/caregiver\/register/, { timeout: 5000 });
  });

  test('wizard step 1 has required fields', async ({ page }) => {
    await page.goto('/caregiver/register');
    await expect(page.getByText(/Paso 1 de 10/)).toBeVisible({ timeout: 5000 });
    await expect(page.getByPlaceholderText(/Tu nombre/)).toBeVisible();
    await expect(page.getByPlaceholderText(/Tu apellido/)).toBeVisible();
    await expect(page.getByPlaceholderText(/71234567/)).toBeVisible();
    await expect(page.getByRole('button', { name: /Siguiente/ })).toBeVisible();
  });
});
