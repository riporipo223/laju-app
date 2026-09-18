import path from "node:path";
import { defineConfig } from "vitest/config";

// Mirrors tsconfig.json's "@/*" path — Vite/Vitest doesn't read tsconfig paths automatically. Needed by
// T2.11's route.ts importing "@/lib/point-calculation" without a corresponding vi.mock (unlike "@/lib/auth"
// and "@/lib/supabase", which route.test.ts mocks before import, so resolution never happens for real).
export default defineConfig({
  resolve: {
    alias: { "@": path.resolve(__dirname, ".") },
  },
  test: {
    environment: "node",
    include: ["**/*.test.ts"],
  },
});
