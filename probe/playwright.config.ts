import { defineConfig, devices } from '@playwright/test';

// Mobile viewport + stock mobile UA: the probe must see what the app sees.
// A desktop UA gets a different Instagram and a different YouTube, and would
// happily pass while the real product was broken.
export default defineConfig({
  testDir: '.',
  timeout: 60_000,
  expect: { timeout: 15_000 },
  retries: 1,
  reporter: [['list'], ['json', { outputFile: 'results.json' }]],
  use: {
    ...devices['iPhone 14'],
    locale: 'en-US',
    screenshot: 'only-on-failure',
  },
});
