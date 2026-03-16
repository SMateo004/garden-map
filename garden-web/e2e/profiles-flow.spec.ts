/**
 * E2E: Listing → Detail → Register flow (profiles).
 * Backend must be running (or mock) for full flow; listing/detail can run against mock.
 */

import { test, expect } from '@playwright/test';

test.describe('Profiles flow', () => {
  test('listing page loads and shows filters', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('h1')).toContainText(/Cuidadores/i);
    await expect(page.getByRole('combobox', { name: /Servicio/i })).toBeVisible();
    await expect(page.getByRole('combobox', { name: /Zona/i })).toBeVisible();
  });

  test('can open caregiver auth page from Soy cuidador', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('link', { name: /Soy cuidador/i }).first().click();
    await expect(page).toHaveURL(/\/caregiver\/auth/);
    await expect(page.getByRole('button', { name: /Iniciar sesión/i })).toBeVisible({ timeout: 5000 });
  });

  test('register form has required fields', async ({ page }) => {
    await page.goto('/register-caregiver');
    await expect(page.getByLabel(/Descripción \(bio\)/i)).toBeVisible();
    await expect(page.getByLabel(/Zona/i)).toBeVisible();
    await expect(page.getByText(/Servicios que ofreces/i)).toBeVisible();
    await expect(page.getByRole('button', { name: /Enviar perfil/i })).toBeVisible();
  });

  test('navigate to caregiver detail when clicking a card (if API returns data)', async ({ page }) => {
    await page.goto('/');
    // If list is empty we stay on listing; if not we click first card link
    const cardLink = page.getByRole('link', { name: /.*/ }).first();
    const count = await cardLink.count();
    if (count > 0) {
      await cardLink.click();
      await expect(page).toHaveURL(/\/caregivers\/[a-f0-9-]+/);
      await expect(page.getByText(/Volver al listado/)).toBeVisible();
    }
  });
});
