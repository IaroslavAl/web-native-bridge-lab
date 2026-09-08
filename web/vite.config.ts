import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig(({ mode }) => ({
  plugins: [react()],
  define: {
    __LAB_VARIANT__: JSON.stringify(mode === "variant-b" ? "B" : "A"),
  },
  build: {
    emptyOutDir: true,
    modulePreload: { polyfill: false },
  },
  test: {
    environment: "jsdom",
    setupFiles: "./src/test/setup.ts",
    restoreMocks: true,
  },
}));
