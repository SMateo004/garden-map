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

  test('Soy cuidador navigates to auth page', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('link', { name: /Soy cuidador/i }).first().click();
    await expect(page).toHaveURL(/\/caregiver\/auth/);
    await expect(page.getByRole('button', { name: /Iniciar sesión/i })).toBeVisible({ timeout: 5000 });
    await expect(page.getByRole('button', { name: /Registrarme/i })).toBeVisible();
  });

  test('auth page has login and register tabs', async ({ page }) => {
    await page.goto('/caregiver/auth');
    await expect(page.getByRole('button', { name: /Iniciar sesión/i })).toBeVisible({ timeout: 5000 });
    await expect(page.getByRole('button', { name: /Registrarme/i })).toBeVisible();
  });

  test('Comenzar registro navigates to wizard', async ({ page }) => {
    await page.goto('/caregiver/auth');
    await page.getByRole('button', { name: /Registrarme/i }).click();
    await expect(page.getByRole('button', { name: /Comenzar registro/i })).toBeVisible({ timeout: 3000 });
    await page.getByRole('button', { name: /Comenzar registro/i }).click();
    await expect(page).toHaveURL(/\/caregiver\/register/, { timeout: 5000 });
    await expect(page.getByText(/Paso 1 de 10/)).toBeVisible({ timeout: 5000 });
    await expect(page.getByText(/Tu nombre y teléfono/)).toBeVisible();
  });

  test('wizard step 1 has required fields', async ({ page }) => {
    await page.goto('/caregiver/register');
    await expect(page.getByText(/Paso 1 de 10/)).toBeVisible({ timeout: 5000 });
    await expect(page.getByPlaceholderText(/Tu nombre/)).toBeVisible();
    await expect(page.getByPlaceholderText(/Tu apellido/)).toBeVisible();
    await expect(page.getByPlaceholderText(/\+591/)).toBeVisible();
    await expect(page.getByRole('button', { name: /Siguiente/ })).toBeVisible();
  });
});
