import { test, expect } from '@playwright/test';

test.describe('Elevator Dashboard Happy Path', () => {
  test('Scenario 1.1: Request from IDLE at F0 to F3', async ({ page }) => {
    // 1. Navigate to the dashboard
    await page.goto('/');

    // 2. Wait for LiveView to connect (Activity Log should show the connection message)
    const log = page.locator('#log');
    await expect(log).toContainText(/LiveView Connected/i, { timeout: 10000 });

    // 3. Wait for rehoming to complete (Core status should become NORMAL)
    const coreStatus = page.locator('.footer-item', { hasText: 'Core' }).locator('.status-value');
    await expect(coreStatus).toHaveText('NORMAL', { timeout: 15000 });

    // 3. Verify initial state (Digital indicator should show current floor)
    const indicator = page.locator('.digital-indicator');
    await expect(indicator).toBeVisible();

    // 4. Request Floor 3
    const label3 = page.locator('#label-3');
    await label3.click();

    // 4. Verify visual feedback: Floor 3 should be 'pending' or 'targeting'
    await expect(label3).toHaveClass(/pending|targeting/);

    // 5. Verify Activity Log entry
    await expect(log).toContainText(/Controller: Floor 3/i);

    // 6. Wait for arrival (Digital indicator should show 3)
    // The simulation takes time (2s per floor), so we increase timeout.
    await expect(indicator).toHaveText('3', { timeout: 20000 });

    // 7. Verify doors are OPEN — check immediately after arrival, before the 5s auto-close fires
    const doorStatus = page.locator('.footer-item', { hasText: 'Doors' }).locator('.status-value');
    await expect(doorStatus).toHaveText('OPEN', { timeout: 3000 });

    // 8. Verify car class shows doors-open
    const car = page.locator('#elevator-car');
    await expect(car).toHaveClass(/doors-open/);

    // 9. Verify car vertical position aligns with Floor 3 label
    const carBox = await car.boundingBox();
    const label3Box = await page.locator('#label-3').boundingBox();
    const carCenterY = carBox!.y + carBox!.height / 2;
    const label3CenterY = label3Box!.y + label3Box!.height / 2;
    expect(Math.abs(carCenterY - label3CenterY)).toBeLessThan(15);
  });
});
