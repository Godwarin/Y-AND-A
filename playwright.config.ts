import { defineConfig } from "@playwright/test";
const testPort = 14721;
const testUrl = `http://127.0.0.1:${testPort}`;
export default defineConfig({
  testDir: "./tests",
  testMatch: "web.spec.ts",
  fullyParallel: false,
  workers: 1,
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    baseURL: testUrl,
    channel: "msedge",
    viewport: { width: 1440, height: 1000 },
  },
  webServer: {
    command: `npm run build && node scripts/run-tool.mjs vite preview --host 127.0.0.1 --port ${testPort} --strictPort`,
    url: testUrl,
    reuseExistingServer: false,
    timeout: 60000,
  },
});
