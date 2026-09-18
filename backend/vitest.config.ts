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
    // The integration files share one real Supabase project — and one global leaderboard, which any of
    // them can rebuild. Running files in parallel let one file's test users appear inside another file's
    // rankings (found in T2.19). Serial files remove that whole class of cross-file flake; the unit files
    // are milliseconds each, so the cost is negligible.
    fileParallelism: false,
    // Integration tests are network-bound: CI runners are in the US, Supabase in Singapore (~230 ms per
    // round-trip), and `POST /api/runs` alone makes ~9 sequential calls — it sat right at the 5 s default
    // (measured 4.7 s in CI) and finally tipped over. Unit tests stay milliseconds; this only stops the
    // network-bound ones failing on a budget that was never theirs.
    testTimeout: 30000,
    hookTimeout: 30000,
  },
});
