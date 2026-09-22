# Laju — Session Handoff

**Read this file first, completely, before touching anything else.** You are a new Claude Code
session — different device, different account, no memory of any prior conversation. This file is
written so you don't need that memory. It is a map, not a full briefing: it tells you what to read
next and in what order, not everything about the project.

If the user's first message is just **"Lanjutkan"** ("continue"), read this whole file, then go to
§3 before doing anything else.

---

## 0. Reading order — don't read everything, read in this order and stop when you know enough

1. **This file** (2 minutes).
2. **[documents/README.md](./README.md)** — §5 "Status at a glance" for phase status, plus the
   banner at the top. Read §1/§2/§3 only if your task touches Fase 1 or Fase 2 (Fase 3 is closed,
   Fase 4 is not scheduled).
3. **[documents/03-development/tasks/README.md](./03-development/tasks/README.md)** — the task
   checklist. Treat it as *probably* correct, not certainly — see §1 below.
4. **Only the one `phase-N-*.md` file** that owns the task you're about to touch. Don't read the
   other phase files unless your task explicitly references them.
5. **Only the specific section** of `product-spec.md` / `tech-spec.md` / `database-api-spec.md` that
   the task's own `Reference:` line points to. Don't read these documents cover to cover.

Do not read all 20+ documents in `documents/` up front. That is slower than reading the four things
above and looking up anything else only when a task actually needs it.

---

## 1. How this project works — the workflow contract

This project has a specific way of working. Follow it exactly; it is not a suggestion.

- **One task at a time.** Implement it, verify it with **real evidence** (an actual test run's
  actual output — `186/186 passing`, an actual `curl`/`psql` result against the real database, a
  real `xcodebuild test` log — never "this should work" or "tests should pass now"), update that
  task's own checklist/DONE block **only after** its Definition of Done items are genuinely true,
  then **stop and wait for the user to type "Lanjutkan"** before starting the next task. Do not
  chain multiple tasks together in one turn without that checkpoint.
- **`tasks/README.md` is the intended source of truth, but it drifts stale.** This has happened
  more than once in this project (most recently: T3.1 shipped in code on 2026-09-21 but its
  checklist was never marked done — caught and fixed 2026-09-22, days later, only because a later
  gate task's dependency list forced a re-check). **Always cross-check the checkbox in
  `tasks/README.md` against the actual `DONE`/status block inside the relevant `phase-N-*.md`
  file** before trusting either one in isolation. If they disagree, the `phase-N-*.md` file's own
  DONE block (with its evidence) is more likely correct — but say so and fix the checklist rather
  than silently picking one.
- **An ambiguous product or technical decision with no answer in any document → stop and ask the
  user.** Do not decide it yourself and keep going. The one exception: small mechanical fixes —
  a broken link, a typo, an obviously stale cross-reference — just fix those inline as you notice
  them, no need to ask or make a fuss about it.
- **Reuse existing, already-tested logic. Do not reimplement it from scratch.** In particular:
  - GPS filtering / stationary-anchor drift logic — `ios/Laju/ViewModels/RoutePointBuffer.swift`
    and `ios/Laju/Services/Location/LocationTrackingService.swift` (see ADR 0004).
  - The point formula — `ios/Laju/PointFormula/PointFormula.swift` (client) and
    `backend/lib/point-calculation.ts` (server) — these two must stay in parity (ADR 0007) via a
    shared fixture file; don't hand-edit one without the other.
  - Auth — `ios/Laju/Services/Auth/AuthService.swift` / `SupabaseConfig.swift` (client),
    `backend/lib/auth.ts` (server, `requireUser`/`requireAuthenticatedIdentity`).
  
  Grep for existing logic before writing new logic that looks similar.

---

## 2. Current status (snapshot — `tasks/README.md` has the real detail, this is just orientation)

| Phase | State |
|---|---|
| Fase 0 — Setup | Closed. |
| Fase 1 — Core Loop Offline | Code complete. Gate (T1.17) open — needs physical-device dogfood runs only the user can do. |
| Fase 2 — Backend + Sync + Global Leaderboard | 26/33 closed, 4 PARTIAL. All 4 PARTIAL items blocked on the Apple Developer Program (see §4) or a real device. |
| **Fase 3 — Season** | **DONE, 2026-09-22.** All 7 tasks (T3.1, T3.6, T3.7, T3.7a, T3.8, T3.9, T3.10) complete and signed off — see [phase-3-season.md](./03-development/tasks/phase-3-season.md)'s T3.10 sign-off block. |
| Fase 4 — Backlog (Local Leaderboard, etc.) | **Not scheduled. Do not build without explicit user go-ahead.** |

---

## 3. If the user types "Lanjutkan" right now

**There is no task auto-queued.** Fase 3 just closed; Fase 4 is explicitly "do not build." Do not
guess and start building something from Fase 4. Instead, tell the user where things stand and ask
which of the following they want tackled — all of these are genuinely open and each needs either a
user decision or something only the user can physically do:

- **CQ-2 (Blocker)** — `RoutePointBuffer.flush` can silently destroy a recorded route. Fix is
  understood; needs the user's go-ahead to touch it. See `documents/04-quality-security/code-quality-audit.md`.
- **T1.17 gate** — needs physical-device dogfood sessions (battery-with-map-on-screen, audio cue
  with screen locked, ≥5 runs across ≥3 days). User-only; you cannot do this.
- **SEC-1 (Blocker)** — no GPS retention policy defined yet. Blocks writing the Privacy Policy,
  which blocks App Store submission. Needs a product decision from the user.
- **T2.3/T2.4/T2.22/T2.21 remaining items** — all blocked on the Apple Developer Program, see §4.
- **Fase 4 backlog** (Local Leaderboard: T3.2–T3.5) — only if the user explicitly asks to start it.

Full detail on all of these: `documents/README.md` §1 and §3.

---

## 4. The recurring blocker: Apple Developer Program

You will hit this repeatedly across open Fase 1/2 items. Write it down once here so you don't
re-derive it every time: the Apple ID currently signed into this machine's Xcode is a **free
Personal Team**, and Apple does not allow a Personal Team to carry the **Sign in with Apple**
capability — confirmed live via `xcodebuild`: *"Personal development teams... do not support the
Sign In with Apple capability."* This blocks Sign in with Apple's end-to-end verification, some
T2.21 gate items, and T2.22's real-device half. The user is enrolling in the paid Apple Developer
Program separately; until that lands, treat these as **accepted PARTIAL/open items**, not bugs to
work around. A `DEBUG`-only escape hatch already exists for automated E2E testing without a real
Apple sign-in — see `AuthService.swift`'s `LAJU_DEBUG_ACCESS_TOKEN`/`LAJU_DEBUG_REFRESH_TOKEN`
env-injected session (real Supabase tokens for a throwaway test user, not a bypass of server auth).
Don't build a different workaround; use that one if you need to exercise a post-sign-in flow on a
Personal Team build.

---

## 5. Decisions that are FINAL — do not relitigate without explicit user approval

One-liners only. Full rationale: `documents/02-architecture/adr/README.md` (13 ADRs) and
`documents/README.md` §3's "Closed" tables.

- Native Swift + SwiftUI, not React Native (ADR 0001).
- Core Data, not SwiftData (ADR 0002).
- `CLLocationManager` directly, no third-party GPS library (ADR 0003).
- Stationary-anchor drift filter for GPS, not a simple distance threshold (ADR 0004).
- Next.js + Supabase + Vercel backend stack (ADR 0005), Postgres not Firestore (ADR 0006).
- Shared fixture file keeps client/server point-formula in parity — never let them drift (ADR 0007).
- Server-side anti-cheat is architecturally separate from client-side sanity filtering (ADR 0008).
- Minimum-distance gate on the point formula, anti-farming (ADR 0009) — do not weaken it.
- MapKit, not Mapbox (ADR 0011).
- Append-only `point_transaction` ledger + a separately precomputed leaderboard table — never
  derive the leaderboard live from the ledger on read (ADR 0013).
- **Apple AND Google Sign-In**, not Apple-only — Google added 2026-09-21 as a second provider.
- **Leaderboard is Global-only in v1.** Local/regional scopes (T3.2–T3.5) are deferred to Fase 4 —
  moved intact, not cancelled, waiting on user density.
- **"Tier" = Season League** — a division computed from points earned *in the current season
  only*, resets every season. It is not Level (lifetime) and not Rank. `tech-spec.md` §2.5.
- **Region (kecamatan/kabupaten/provinsi) is mandatory in v1 onboarding**, free text for now — no
  catalog/cascading picker exists yet (that's T3.1's deferred picker work, not built).
- `resolve-flagged-runs` cron runs **daily**, not ≤12h — Vercel Hobby plan limitation, accepted
  (OPS-1). Revisit only if/when the project upgrades to Vercel Pro.
- `POST /api/runs` p95 latency currently **does not** meet the 1.5s budget (PERF-1) — accepted
  limitation pending a possible Supabase Pro upgrade, not being actively optimized right now.

---

## 6. Security — read before your first commit, every session

This repo (`riporipo223/laju-app`) is **public**. There has already been one real incident (a key
exposed in this repo) — do not repeat it. Before any `git add`/`git commit`:

- **Supabase `service_role` key: NEVER a literal value in any tracked file, ever.** Only as an
  env var reference (`process.env.SUPABASE_SERVICE_ROLE_KEY`), sourced from `.env.local` (backend,
  gitignored) or CI/Vercel secrets. If you ever see a literal JWT next to the word "service_role" in
  a diff, stop and do not commit.
- **The Supabase *anon* key is meant to be public.** `ios/Laju/Services/Auth/SupabaseConfig.swift`
  embeds it in the client binary on purpose — Supabase's security model is Row Level Security, not
  key secrecy. Seeing it there is correct, not a leak. Don't "fix" it.
- **Google OAuth**: only a Client *ID* may appear anywhere (public by design). A Client *Secret*
  (`GOCSPX-...`) must never appear in any tracked file.
- **Apple**: no `.p8`/`.p12`/`.mobileprovision` file should ever be added to git.
- Read every file in `git diff --cached` yourself before committing — don't assume `.gitignore`
  alone catches everything, and don't assume a file removed later is scrubbed from git *history*
  (`git log --all --full-history -- <path>` checks that; `.gitignore` only stops *future* commits).
- `documents/` is gitignored almost entirely on purpose (business docs — lean canvas, MVP report,
  full tech spec — stay private, not published on the public repo). **This file and
  `documents/README.md` are a deliberate, narrow, explicit exception** (added 2026-09-22, user
  decision) — see the `!documents/HANDOFF.md` / `!documents/README.md` lines in the root
  `.gitignore`. Do not widen that exception to other files in `documents/` without asking the user
  first — that would newly-publish 20+ documents that were kept private on purpose.

---

## 7. Where things live

- **iOS app**: `ios/Laju` (SwiftUI, Core Data). `ios/project.yml` is the real source — it's fed to
  XcodeGen to generate `ios/Laju.xcodeproj` (gitignored, regenerated, don't hand-edit it if you can
  help it; if you must add a file to a target without XcodeGen installed, edit
  `project.pbxproj`'s `PBXBuildFile`/`PBXFileReference`/group/`Sources` phase sections directly —
  see any recent commit that added a new Swift file for the pattern).
- **Backend**: `backend/` — Next.js API routes + Supabase Postgres, deployed on Vercel at
  `https://backend-eight-gules-56.vercel.app`. Pushing to `main` auto-deploys.
- **Task tracking**: `documents/03-development/tasks/README.md` (index) +
  `documents/03-development/tasks/phase-N-*.md` (one file per phase, DoD blocks with evidence).
- **This file**: `documents/HANDOFF.md` — keep it updated when a phase closes or a major decision
  is made; it's the first thing the next session reads.
