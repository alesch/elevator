import { test, expect } from '@playwright/test';

test.describe('Elevator Dashboard Happy Path', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');

    // Wait for LiveView to connect
    await expect(page.locator('#log')).toContainText(/LiveView Connected/i, { timeout: 10000 });

    // Wait for boot sequence to complete — elevator idles at F0
    const coreStatus = page.locator('.footer-item', { hasText: 'Core' }).locator('.status-value');
    await expect(coreStatus).toHaveText('IDLE', { timeout: 15000 });

    const indicator = page.locator('.digital-indicator');
    await expect(indicator).toHaveText('0', { timeout: 10000 });
  });

  // [S-UI-JOURNEY]: Full journey from F0 to F3
  test('[S-UI-JOURNEY]: Full journey from F0 to F3', async ({ page }) => {
    const indicator = page.locator('.digital-indicator');
    const doorStatus = page.locator('.footer-item', { hasText: 'Doors' }).locator('.status-value');

    // Request Floor 3
    const label3 = page.locator('#label-3');
    await label3.click();

    // Floor 3 button shows pending or targeting
    await expect(label3).toHaveClass(/pending|targeting/);

    // Elevator arrives at F3 (3 floors × ~2s + buffer)
    await expect(indicator).toHaveText('3', { timeout: 20000 });

    // Doors open on arrival (before 5s auto-close fires)
    await expect(doorStatus).toHaveText('OPEN', { timeout: 3000 });

    // Car visual shows doors-open class
    const car = page.locator('#elevator-car');
    await expect(car).toHaveClass(/doors-open/);

    // Car vertical position aligns with Floor 3 label within 15px
    const carBox = await car.boundingBox();
    const label3Box = await label3.boundingBox();
    const carCenterY = carBox!.y + carBox!.height / 2;
    const label3CenterY = label3Box!.y + label3Box!.height / 2;
    expect(Math.abs(carCenterY - label3CenterY)).toBeLessThan(15);
  });
});
