import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  server: {
    host: "127.0.0.1",
    port: 1420,
    strictPort: true,
    watch: {
      ignored: [
        "**/vendor/**",
        "**/build/**",
        "**/runtime/**",
        "**/downloads/**",
        "**/docs/**",
        "**/src-tauri/**",
        "**/playwright-report/**",
        "**/test-results/**",
        "**/release/**",
        "**/toolchain/**",
        "**/.venv/**",
      ],
    },
  },
  build: { target: "es2022" },
});
