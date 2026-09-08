import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Opt-in test page only. The normal A/B builds do not include this entry.
export default defineConfig({
  plugins: [react()],
  build: {
    modulePreload: { polyfill: false },
    rollupOptions: { input: "web/acceptance/index.html" },
  },
});
