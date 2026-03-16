/**
 * E2E: Flujo de registro de cuidador con API mockeada (Playwright route).
 */
import { test, expect } from '@playwright/test';

test.describe('Register caregiver with mock API', () => {
  test('listing with mock GET /api/caregivers returns empty list', async ({ page }) => {
    await page.route('**/api/caregivers*', (route) => {
      if (route.request().method() === 'GET' && !route.request().url().includes('/api/caregivers/')) {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            success: true,
            data: {
              caregivers: [],
              pagination: { total: 0, page: 1, currentPage: 1, pages: 0, limit: 10 },
            },
          }),
        });
      }
      return route.continue();
    });

    await page.goto('/');
    await expect(page.locator('h1')).toContainText(/Cuidadores/i);
  });

  test('register form submit shows success when POST mock returns 201', async ({ page }) => {
    await page.route('**/api/caregivers', async (route) => {
      const request = route.request();
      if (request.method() === 'POST') {
        return route.fulfill({
          status: 201,
          contentType: 'application/json',
          body: JSON.stringify({
            success: true,
            data: {
              id: 'cp-mock-1',
              firstName: 'Test',
              lastName: 'User',
              zone: 'EQUIPETROL',
              verified: false,
            },
          }),
        });
      }
      return route.continue();
    });

    await page.goto('/register-caregiver');
    await expect(page.getByLabel(/Descripción \(bio\)/i)).toBeVisible();

    await page.getByLabel(/Descripción \(bio\)/i).fill('Casa con patio grande.');
    await page.getByRole('combobox', { name: /zona/i }).selectOption('EQUIPETROL');
    await page.getByRole('checkbox', { name: /Hospedaje/i }).check();

    const fileInput = page.locator('input[type="file"]');
    await fileInput.setInputFiles([
      { name: 'p1.jpg', mimeType: 'image/jpeg', buffer: Buffer.alloc(200) },
      { name: 'p2.jpg', mimeType: 'image/jpeg', buffer: Buffer.alloc(200) },
      { name: 'p3.jpg', mimeType: 'image/jpeg', buffer: Buffer.alloc(200) },
      { name: 'p4.jpg', mimeType: 'image/jpeg', buffer: Buffer.alloc(200) },
      { name: 'p5.jpg', mimeType: 'image/jpeg', buffer: Buffer.alloc(200) },
    ]);

    await page.getByRole('button', { name: /Enviar perfil/i }).click();

    await expect(page.getByText(/Perfil enviado para verificación/i)).toBeVisible({ timeout: 5000 });
  });
});
