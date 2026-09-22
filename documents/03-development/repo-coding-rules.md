# Laju App — Repo & Coding Rules

Depends on: [tech-spec.md](../02-architecture/tech-spec.md), [development-plan.md](./development-plan.md)

## 1. Repo Structure — monorepo (`ios/` + `backend/`)

**Keputusan: tetap satu Git repo (monorepo), bukan repo terpisah.** Alasan
singkat: `ios/` (Swift) dan `backend/` (TypeScript) sudah beda bahasa
sepenuhnya sejak pivot ini — tidak ada lagi `packages/shared-types` yang
butuh build tool lintas-bahasa (Turborepo/pnpm workspaces tidak relevan
lagi, lihat tech-spec.md §1). Tapi API contract antara keduanya
(database-api-spec.md §2) tetap satu sumber kebenaran yang harus berubah
bareng — satu PR yang mengubah endpoint request/response shape idealnya
menyentuh `ios/` dan `backend/` sekaligus supaya reviewer melihat kontrak
berubah secara atomik, bukan tersebar di dua repo dengan risiko salah satu
sisi telat update. Untuk tim kecil/solo saat ini, satu repo juga berarti
satu tempat untuk issue tracker, satu `Laju/documents/` yang dirujuk kedua
sisi, dan satu CI config — overhead sinkronisasi dua repo tidak sepadan
manfaatnya di tahap ini.

```
laju/
├── ios/                          # Swift + SwiftUI native app (min. iOS 16)
│   ├── Laju.xcodeproj            # atau Package.swift kalau full-SPM app
│   ├── Laju/
│   │   ├── Views/                # SwiftUI Views (Presentation layer)
│   │   ├── ViewModels/           # ObservableObject ViewModels (MVVM)
│   │   ├── Models/                # Core Data entities + Codable DTOs
│   │   ├── Services/
│   │   │   ├── Location/         # CLLocationManager wrapper
│   │   │   ├── Networking/       # URLSession + Codable API client
│   │   │   └── Persistence/      # Core Data stack (NSPersistentContainer)
│   │   └── PointFormula/         # calculatePoints (Swift) — see tech-spec §2.2b
│   └── LajuTests/                # XCTest — includes point-formula.fixtures.json parity test
├── backend/                       # Next.js API (Vercel)
│   ├── app/api/                   # route handlers: runs, leaderboard, seasons, profile
│   ├── lib/                       # point calculation, anti-cheat, db client
│   └── jobs/                      # leaderboard precompute + resolve-flagged-runs (Vercel Cron entry points)
├── shared/
│   └── point-formula.fixtures.json  # test-vector parity file, read by BOTH ios/ and backend/ tests (tech-spec §2.2b)
└── Laju/documents/                # product & architecture docs (this folder)
```

No root-level JS package manager/build-tool config (`turbo.json`,
`pnpm-workspace.yaml`) — `ios/` builds via Xcode/SPM, `backend/` builds via
its own `package.json`/npm scripts, independently. CI runs two separate
jobs gated by path filters (`ios/**` triggers the Xcode job, `backend/**`
triggers the Next.js job) rather than one shared pipeline.

## 2. Naming Conventions

### Swift (`ios/`) — Swift API Design Guidelines

- **Types** (struct/class/enum/protocol): `PascalCase` — e.g. `RunViewModel`,
  `LocationTrackingService`, `RunStatus`.
- **Properties, functions, enum cases**: `camelCase` — e.g.
  `calculatePoints(distanceKm:avgPaceSecPerKm:streakDays:)`,
  `syncStatus`, case `.pendingSync`.
- **Files**: match the primary type name — `RunViewModel.swift`,
  `LocationTrackingService.swift`. One primary type per file as a default;
  small tightly-coupled helper types may share a file with their owner.
- **Protocols**: describe capability, often `-able`/`-ing`/noun —
  e.g. `LocationTracking`, `RunSyncing` — avoid an `I`-prefix or
  `Protocol`-suffix convention (not idiomatic Swift).
- **Core Data entities**: `PascalCase` singular, matching the domain noun —
  e.g. entity `Run` (not `Runs`, not `run_table`) — attributes `camelCase`
  (e.g. `serverRunId`, `syncStatus`, `flagConfidence`), same field names as
  documented in database-api-spec.md/tech-spec.md, just camelCase instead
  of snake_case to match Swift convention.

### TypeScript (`backend/`) — unchanged from before the pivot

- API route handlers: Next.js App Router convention
  (`app/api/runs/route.ts`).
- Non-route modules: `kebab-case.ts` (e.g. `point-formula.ts`,
  `anti-cheat.ts`).

**Branches:** `type/short-description`, type ∈
`feat|fix|chore|refactor|docs|test` — e.g. `feat/local-leaderboard-filter`,
`fix/pace-cap-off-by-one`.

**Commits:** [Conventional Commits](https://www.conventionalcommits.org/) —
`type(scope): message`, e.g. `feat(point-formula): add streak bonus cap`,
`fix(anti-cheat): correct gps speed jump threshold`. Scope should match the
touched area where reasonable (`ios`, `backend`, `point-formula`,
`leaderboard`).

## 3. Lint / Format

**iOS (`ios/`): SwiftLint + SwiftFormat**

`.swiftlint.yml` (repo root of `ios/`):
```yaml
disabled_rules:
  - todo
opt_in_rules:
  - force_unwrapping
  - implicitly_unwrapped_optional
line_length: 120
identifier_name:
  min_length: 2
force_unwrapping: error
```

`force_unwrapping` set to `error` (not left at the default warning) is
deliberate — GPS/sync code paths (location updates, Core Data fetches,
decoded API responses) are exactly where an unexpected `nil` should fail
gracefully (e.g. skip a malformed GPS sample), not crash the app. CI (T0.10)
runs `swiftlint` in strict mode so this severity actually blocks merge, not
just a local warning.

**Swift Strict Concurrency / warnings-as-errors baseline** (Xcode build
setting, not a SwiftLint rule): `SWIFT_STRICT_CONCURRENCY = complete`, and
treat-warnings-as-errors enabled for the `ios/` target. Set once in T0.2,
enforced continuously by T0.10's CI build (a warning-as-error failure
fails the build, same as a lint failure).

`.swiftformat` (repo root of `ios/`):
```
--indent 4
--maxwidth 120
--semicolons never
--self remove
--commas inline
```

`--commas inline` added during T1.3 (2026-09-12): SwiftFormat's default
trailing-comma-on-its-own-line style conflicted with SwiftLint's
`trailing_comma` rule (which rejects trailing commas) — the two tools
disagreed on multi-line array literals until this was set explicitly.

**Backend (`backend/`): ESLint + Prettier** (unchanged from before the
pivot):
```js
module.exports = {
  extends: [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
    "prettier"
  ],
  parser: "@typescript-eslint/parser",
  rules: {
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/no-floating-promises": "error",
    "no-console": ["warn", { allow: ["warn", "error"] }]
  }
};
```

`no-floating-promises` stays an error — sync-handling and anti-cheat code
paths on the backend are async-heavy, and a silently swallowed promise
there means a run silently fails to validate or write.

Both `ios/` and `backend/` run their respective lint/format checks in CI
(as separate, path-filtered jobs — see §1); PRs cannot merge with either
failing.

## 4. PR Review Checklist (minimum)

- [ ] Code follows naming conventions above (files, branch, commit
      messages) for whichever side (`ios/`/`backend/`) is touched
- [ ] Lint + format pass (CI green) for the touched side
- [ ] New/changed logic has at least one test (`XCTest` for Swift pure
      functions/ViewModels; `vitest`/`jest`/integration test for backend
      API routes)
- [ ] No secrets/credentials committed (no API keys, no signing
      certificates/provisioning profiles with private keys)
- [ ] **Does this PR touch the point formula or anti-cheat logic**
      (`ios/Laju/PointFormula/`, or anti-cheat checks in `backend/lib`)?
      If yes:
  - [ ] Requires a second reviewer beyond the usual one (point/anti-cheat
        changes affect fairness across all users — higher bar than
        typical UI change)
  - [ ] PR description includes before/after point calculation examples
        for at least one normal case and one edge case (e.g. a previously
        `flagged` run)
  - [ ] `shared/point-formula.fixtures.json` updated to match, and both
        `ios/` (`XCTest`) and `backend/` (`vitest`/`jest`) parity tests
        pass against the updated fixture (tech-spec.md §2.2b — this
        replaces the old "same shared file" guarantee since Swift and
        TypeScript can no longer literally share one source file)
- [ ] If the change affects leaderboard precompute (architecture.md §4):
      confirms the precompute job still completes within the freshness
      target (tech-spec §4) at expected data volume
- [ ] If the change touches `ios/Laju/Services/Location/`: confirms
      background location behavior manually on a physical device (T0.9
      DoD) — simulator alone does not reliably reproduce background
      suspension/termination behavior
