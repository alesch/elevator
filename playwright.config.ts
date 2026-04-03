import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/ui',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:4000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  // We'll assume the user starts the Phoenix server manually for now, 
  // or we can add a webServer config if needed.
  /*
  webServer: {
    command: 'mix phx.server',
    url: 'http://localhost:4000',
    reuseExistingServer: !process.env.CI,
  },
  */
});
