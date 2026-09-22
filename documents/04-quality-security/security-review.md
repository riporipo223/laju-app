# Laju App — Security Review

Created 2026-09-17. Scope: a systematic security audit of the areas that are legally and ethically sensitive for a location-based app, conducted against the specification set as it stands after Round 7 of the pre-execution audit, plus the Fase 1 code actually on disk.

Depends on: [tech-spec.md](../02-architecture/tech-spec.md), [database-api-spec.md](../02-architecture/database-api-spec.md), [product-spec.md](../01-product/product-spec.md), [pre-launch-checklist.md](./pre-launch-checklist.md), [lean-canvas.md](../01-product/lean-canvas.md), [adr/README.md](../02-architecture/adr/README.md)

This document is a **findings register**, not a task backlog. Findings that need engineering work are cross-referenced to the task file that should own them; assigning task IDs is a separate step and is not done here.

---

## 0. Severity convention

`audit-report.md`'s established convention is two-tier — **Blocker** (`B7-n`) and **Note** (`N7-n`). This review uses a three-tier scale, adding **Warning** between them, because a pure Blocker/Note split collapses two genuinely different things in a security context: "this will get the app rejected or breaks a guarantee we have already made to users" versus "this is a real exposure with no current exploit path but should not ship unaddressed." The added tier is a deliberate extension of the existing convention, not a replacement of it.

| Tier | Meaning |
|---|---|
| **Blocker** | Must be resolved before the affected phase ships. Either breaks a guarantee already stated to users or to Apple, or blocks a pre-launch checklist item that itself blocks submission. |
| **Warning** | A real exposure or a real gap in the spec. No current exploit path in the shipped surface, but it should be closed deliberately, not by accident. |
| **Note** | Documented for completeness. Either an accepted risk being re-confirmed, or a verification that an area is genuinely sound and should not be re-raised. |

Findings are numbered `SEC-n`. Items marked **VERIFIED COVERED** are not findings — they are explicit confirmations that an area previously flagged elsewhere is genuinely closed, recorded so that a future round does not re-open settled ground.

---

## 1. Location data (GPS)

The most sensitive data this app handles. A `gps_route` is a precise, timestamped trace of where a real person physically was — its first and last points are, for most users, their home address.

### SEC-1 — No retention policy exists for GPS route data, anywhere — **Blocker**

A grep across the entire document set for retention language (`retention`, `berapa lama`, `disimpan selama`, automatic deletion) returns **zero** matches relating to run or location data. The only deletion path specified for `gps_route` is user-initiated account deletion (`database-api-spec.md` §2.1b point 5, which nulls `RUN.gps_route` server-side).

Consequences of the gap, concretely:

- **Server-side**: `RUN.gps_route` is retained indefinitely by default, for every run, for every user, forever. Nobody decided this — it is the default that results from never having made a decision.
- **Local**: `Run.gpsRoute` in Core Data is likewise retained for the life of the install. The history screen implies indefinite local retention as a *product* feature, which is legitimate, but it has never been examined as a *data* decision.
- **Blocks a submission-blocking checklist item**: `pre-launch-checklist.md` §1 requires a published Privacy Policy covering "every data category actually collected." A Privacy Policy cannot be truthfully written without stating how long precise location data is kept. That checklist item cannot be honestly completed until this decision is made, and §1 is a Guideline 5.1.1 requirement — so this transitively blocks App Store submission.

This is a decision, not a bug: the resolution can legitimately be "retained indefinitely, because run history is the product." But that must be a stated, deliberate position that the Privacy Policy reflects, not an unexamined default.

**Should be owned by**: a new item in `pre-launch-checklist.md` §1, plus a retention statement in `tech-spec.md` alongside the existing data model.

### SEC-2 — Core Data store has no specified file-protection class — **Warning**

`ADR-0002` locks Core Data as the local persistence layer, and `database-api-spec.md` §2.1b point 4 correctly identifies local `gpsRoute` as "the most sensitive personal data on the device." But no document specifies an `NSFileProtection` class for the persistent store.

Without an explicit setting, an iOS SQLite store inherits the platform default (`NSFileProtectionCompleteUntilFirstUserAuthentication`), which leaves the file readable by any process with filesystem access once the device has been unlocked a single time after boot — including while the device is subsequently locked. `NSFileProtectionComplete` would restrict access to while-unlocked only.

The trade-off is real and is the reason this is a Warning rather than a Blocker: this app writes location data from a **background** location callback, and `NSFileProtectionComplete` would make those writes fail while the device is locked — which is precisely the primary tracking scenario. The correct resolution is most likely `NSFileProtectionCompleteUnlessOpen` on the store, which allows an already-open handle to keep writing while locked. That nuance is exactly why this needs to be decided explicitly rather than inherited.

**This is a consequence of ADR-0002 that ADR-0002 does not currently record.** A cross-reference has been added to that ADR's Risks section.

### SEC-3 — The "Unfair Advantage" aggregate-data strategy is an idea, not a design — **Warning**

`lean-canvas.md` §9 states the strategic position directly: "Banyak user = banyak data," supporting more accurate leaderboards, more relevant local competition, fairer season tier placement, and performance-based matchmaking.

Checked against the technical specs: there is **no** anonymization design, no aggregation pipeline spec, no k-anonymity or minimum-cohort threshold, and no separation between identified operational data and de-identified analytical data anywhere in `tech-spec.md`, `database-api-spec.md`, or `architecture.md`. The nearest thing that exists is `LEADERBOARD_SCOPE.insufficient_data` — a minimum-user-count threshold below which a scope is not shown. That is a *product* guard (a leaderboard of two people is not interesting), but it incidentally functions as a small-cohort privacy guard, and it is the only mechanism in the entire system that does.

So, to answer the question as posed: **the security of the aggregate-insight strategy is not designed. It is currently only an idea.**

Why this is a Warning and not a Blocker: aggregate insights are not in the MVP scope (`lean-canvas.md` §4 lists them nowhere; the "Government partner" use in §2 is a Secondary User, explicitly future). Nothing ships on this today. It is a Warning because the moment an aggregate-analytics or government-partnership feature is scoped, the privacy architecture must precede it, not be retrofitted — retrofitting de-identification onto a corpus of precise GPS traces already collected under a Privacy Policy that did not mention analytical use is the specific failure mode that produces regulatory and reputational incidents.

**Recommendation**: before any aggregate-data feature is scoped, the Privacy Policy (SEC-1's item) must already state whether collected location data may be used in de-identified aggregate form. Adding that sentence now costs nothing; adding it later requires re-consent.

### SEC-4 — Full-fidelity route upload is un-minimized — **Note**

`POST /api/runs` uploads the complete per-point `gps_route` (lat/lng/timestamp/elevation per sample). This is necessary and justified: `tech-spec.md` §2.4's anti-cheat checks compute instantaneous speed and elevation deltas, which are not derivable from a summary.

Recorded as a Note rather than a finding because the collection is genuinely purpose-bound and minimal *relative to its stated purpose*. But it is the input to SEC-1: the server holds a full-fidelity location corpus, so the retention decision there is the one that governs this exposure. No separate action.

---

## 2. Auth and account deletion

### VERIFIED COVERED — the two historical account-deletion findings are genuinely closed in spec

This was the headline question for this review: were the old findings actually turned into locked requirements, or merely recorded as findings? **They are locked requirements.** Both, verified against the current text, not against the audit history:

**(a) "JWT remains valid after account deletion"** — closed in two independent places, which is what distinguishes a requirement from a note:

1. `database-api-spec.md` §2.1b point 3 states the behavior as a numbered element of the endpoint's contract: "Every subsequent authenticated request from this identity is rejected, `401`/`403` (§3) — the JWT itself stays cryptographically valid until it expires, so this is checked by looking up `User.deleted_at` on every request, not by relying on the token alone."
2. `database-api-spec.md` §3's Validation & Error Handling table carries it as its own enforceable rule row: "**Any authenticated request where the caller's own `User.deleted_at` is non-null**… `401`/`403`."

The spec also records the *specific attack it closes* — a still-valid token calling `POST /api/profile/complete` to re-populate the just-cleared `username`/`region_*`, silently undoing the deletion (Round 7 finding B7-10). A finding that has been converted into both an endpoint contract clause and a global validation rule, with its threat model stated, is closed.

**(b) "Local device data is not wiped on deletion"** — closed, with ownership explicitly assigned:

`database-api-spec.md` §2.1b point 4 requires local Core Data `Run` rows (including `gpsRoute`), `SyncMeta`, the Keychain session, and local `UserDefaults` to be cleared on a successful response — and explicitly assigns ownership to **T2.22** rather than to the endpoint, so the requirement cannot fall between the client and the server. Per `audit-report.md` B7-11, T2.22's Scope and DoD were amended to carry it, including a DoD item confirming that a fresh sign-up on the same device sees zero pre-existing runs. The spec states both failure modes it closes: residual cleartext location history on-device, and the deleted user's runs being re-uploaded under a new account.

**Conclusion: no open Blocker remains on account-deletion security.** Both findings are final requirements with named owners and verifiable DoD items, not historical notes. The residual items below are new observations *around* that flow, not re-openings of it.

### SEC-5 — No JWT lifetime or refresh policy is stated anywhere — **Warning**

*Corrected during this review's own verification pass. An earlier draft of this finding claimed that Keychain storage was never specified as a positive requirement, and that claim was wrong: `tasks/phase-2-backend-sync-global-leaderboard.md` T2.3's Scope (line 83) already requires "session persistence via Keychain" as part of the auth implementation. That half of the finding is withdrawn — token storage is correctly specified, in the task that owns it. The remainder stands.*

**No JWT lifetime or refresh policy is stated in any document.** This matters more than it would in a typical app, because this system has a rule that depends on the token's lifetime being bounded: `database-api-spec.md` §2.1b point 3 and §3's validation table require a `User.deleted_at` lookup on *every* authenticated request, precisely because "the JWT itself stays cryptographically valid until it expires" after account deletion.

That design is correct, and the `deleted_at` check makes the system safe regardless of TTL. But the TTL is still the window in which a leaked or exfiltrated token is usable, and it is currently whatever Supabase's default happens to be — applied by omission rather than chosen. A reader of the spec cannot answer "how long is a stolen token good for?", which is a question that will be asked during any security review or legal assessment (SEC-12).

**Should be owned by**: `tech-spec.md`, stating the access-token TTL and refresh-token policy alongside the existing auth row, so T2.3 implements a stated number rather than inheriting one.

### SEC-6 — `trust_score` evasion via delete-then-re-register carries a privacy/security tension not yet recorded — **Note**

`database-api-spec.md` §2.1b point 7 already documents this as a knowingly accepted v1 risk: `trust_score` lives on the retained-but-orphaned `User` row, so re-registration yields a fresh row with default trust and no mechanism carries the penalty forward. The spec even sketches a future fix: "a future round may hash the deleted email to re-apply trust on matching re-registration if abuse is observed."

Re-confirmed as accepted; not re-opened. But one consequence of that proposed fix is not recorded anywhere, and should be before someone implements it:

**Hashing the deleted user's email to recognize them on re-registration means retaining a derived identifier of a user who exercised their right to deletion.** That directly contradicts the deletion guarantee §2.1b otherwise takes care to make complete (every personal field enumerated, email replaced with a `@laju.invalid` placeholder specifically so the real address is not retained). A future round implementing the anti-evasion fix would be quietly re-introducing the exact identifier the deletion flow was designed to destroy.

This is recorded as a Note, not a Warning, because nothing is currently wrong — it is a trap laid for a future implementer by an otherwise reasonable suggestion in the spec. If that fix is ever built, it needs an explicit Privacy Policy disclosure and a retention period of its own, and the trade-off should get its own ADR rather than being treated as a small anti-cheat patch.

---

## 3. Anti-cheat data and privacy

### SEC-7 — `RUN.anomaly_flags` survives account deletion un-anonymized — **Warning**

`database-api-spec.md` §2.1b is unusually rigorous about field-level completeness on the `User` row — it enumerates every personal field and states explicitly that "no field is left untouched by default." Point 5 extends the same care to `RUN`, nulling `gps_route` while keeping the row so `PointTransaction.run_id` stays valid.

But `RUN.anomaly_flags` (ERD §1: "list of anti-cheat checks triggered") is **not** in that list, and is therefore retained. After a deletion, the surviving `RUN` rows still carry per-run behavioral labels — `pace_cap_exceeded`, `gps_speed_jump_segment_3` — attached to a `user_id` that, while anonymized at the `User` row, is still the join key for that user's entire run history.

Sensitivity is genuinely low in isolation: these are check-name strings, not location data, and the deletion flow's headline risk (the route itself) is correctly handled. It is a Warning rather than a Note because of what it is: a **field-completeness miss in exactly the document section whose stated design principle is field completeness**. The Round 7 rewrite enumerated every `User` field precisely so nothing would be retained by oversight; `RUN`'s fields did not get the same enumeration, and `anomaly_flags` is what fell through.

Adjacent, same root cause: `RUN`'s other columns (`distance_meters`, `duration_seconds`, `started_at`) are also retained. That is defensible and probably correct — they feed the immutable `PointTransaction` ledger (`ADR-0013`) and aggregate history. The problem is not that they are retained; it is that §2.1b never states which `RUN` fields are retained and why, the way it does for `User`.

**Recommendation**: extend §2.1b point 5 from "`gps_route` is nulled" to a complete field-by-field disposition of `RUN`, matching the rigor already applied to `User`. Decide `anomaly_flags` explicitly — nulling it is the low-cost default, since after deletion there is no longer a user whose trust could be adjudicated.

### SEC-8 — No detailed per-user pace/speed history store exists; the feared surface is not there — **Note**

Checked directly, because the concern was specifically raised: does `trust_score`/flagging retain a detailed per-user pace or speed history as a separate store?

**It does not.** `tech-spec.md` §2.4 defines trust score as "kumulatif berapa kali user kena flag/reject dalam periode tertentu" — a cumulative counter over flag/reject events, not a time series. `excluded_pct` is likewise count-based (excluded segments ÷ total segments), explicitly chosen as count-based rather than distance-based (`ADR-0008`). The per-run output that persists is `anomaly_flags`, an array of check names (SEC-7).

So the anti-cheat subsystem introduces **no new personal-data surface of its own**. All of its raw input is `gps_route`, which is already governed by §1's findings. This is recorded as a Note specifically so the concern is settled and does not get re-raised in a later round: the privacy question for anti-cheat is entirely subsumed by the GPS retention question (SEC-1).

One observation that follows from this and is worth stating: SEC-1's resolution therefore **constrains** anti-cheat. If retention is ever capped (say, routes older than N months are purged), the anti-cheat system's ability to re-adjudicate historical runs is capped with it. `trust_score` itself survives, being an aggregate — but a manual HIGH-confidence review of an old flagged run would no longer have a route to review. The two decisions are coupled and should be made together.

---

## 4. API security

### SEC-9 — No rate limiting is specified on any endpoint — **Blocker** (for Fase 2 launch) — **RESOLVED 2026-09-21 (T2.20a)**

> **Resolution.** Built and verified live as T2.20a (commit `6bea1a8`): a Postgres-backed limiter (`rate_limit_bucket` + atomic `rate_limit_hit`), a per-IP layer that runs *before* the Auth call and a per-user layer per route (`POST /api/runs` 30/min and 300/h, other routes 60/min, `profile/complete` 10/h, `DELETE /api/account` 3/h), `429` + `Retry-After`, fail-open with a log, and the client stops its sync batch on a 429. Live evidence: exactly 120 of 130 requests per IP accepted, 30 of 35 per user, a second user on the same IP unaffected; concurrent atomicity proven (exactly 10 of 40 against a limit of 10). Exposure 3 (client-only reconciliation throttle) is now also enforced server-side (`GET /api/runs` 30/h).
>
> **Exposure 2 — Supabase Auth's own limits, now recorded (inferred, not read directly):** `supabase config diff` reports no difference in `auth.rate_limit`, so the live project equals the CLI defaults — sign-in/sign-up 30 and OTP/magic-link verification 30 per 5 min per IP, token refresh 150 per 5 min per IP; the email, SMS and anonymous limits are moot now the email provider is off (SEC-15). These are inherited defaults, not tuned decisions; they were reviewed and are acceptable for an Apple-only sign-in.
>
> **Accepted limits:** fixed windows (a burst can straddle a boundary, up to 2× the limit for an instant); a request without a client address skips the per-IP layer; Vercel's WAF rule not used (Hobby plan).

No endpoint in `database-api-spec.md` has a specified request ceiling, per-user or per-IP. A grep for `rate limit` / `rate-limit` / `throttl` across both specs returns exactly one match, `tech-spec.md`'s "redundant-update throttling" — which refers to `CLLocationManager`'s `distanceFilter` for battery efficiency and has nothing to do with API request rates. There is no API rate limiting anywhere.

The spec does not merely omit this — it **documents its own absence**. `database-api-spec.md` §2.2b, on reconciliation call frequency: "**Call frequency (client-side rule, not enforced server-side in v1)**… at least 15 minutes must have elapsed since the last reconciliation attempt." The only throttle in the system is implemented in the client, by the client, and is therefore trivially bypassable by anyone who does not use the client. A modified client, or plain `curl` with a valid token, is subject to no limit at all.

Concrete exposures, in order of severity:

1. **`POST /api/runs` is the most expensive endpoint in the system and is unbounded.** It runs synchronous anti-cheat over an entire route within a p95 < 1.5s budget (`tech-spec.md` §4 NFR). Unbounded submission is simultaneously a denial-of-service surface and a direct compute-cost surface on a serverless platform, where cost scales with invocation.
2. **Auth endpoints have no stated brute-force protection.** Supabase Auth applies its own platform defaults, but nothing in the spec states what they are or that they were considered — the protection is inherited, not decided, which is the same anti-pattern as SEC-2.
3. **`GET /api/runs` reconciliation is explicitly client-throttled only**, per the quote above.

Rated **Blocker for Fase 2** specifically. Nothing is exposed today — there is no deployed backend, and Fase 1 is entirely offline/local. But this must not reach a publicly reachable backend unresolved, and `development-plan.md` already gates the public leaderboard on server-side anti-cheat being verified working — rate limiting belongs in that same gate, since an unlimited submission rate undermines the leaderboard-fairness guarantee that gate exists to protect.

**Note on the platform**: `ADR-0005`'s stack gives some of this for free — Vercel provides platform-level DDoS mitigation, and Supabase applies its own auth rate limits. Neither provides *application-level, per-user* limits on `POST /api/runs`, which is the one that actually matters here. The platform choice reduces the work; it does not remove the requirement.

### SEC-10 — No size cap on the `gps_route` array — **Warning** — **RESOLVED 2026-09-21 (T2.20a)**: `gps_route` capped at 20,000 points and the request body at 4,000,000 bytes, both refused with `413` before any anti-cheat work; no run is written (`payload-cap.integration.test.ts`).

`POST /api/runs` accepts `gps_route` as an unbounded array. `database-api-spec.md` §3 rejects a *malformed* or *missing* route (`422`) and a zero/negative duration (`400`), but nothing bounds the number of points.

For calibration: the real 24km calibration run recorded in the project's own test history (pk=81) is on the order of several thousand points. Nothing prevents a submission of several million. Because anti-cheat validation is synchronous and per-segment, request cost scales linearly with array length — so absent a cap, **a single request can be made arbitrarily expensive**, which is the amplification factor that makes SEC-9 materially worse. The two compound: a rate limit bounds request count, a size cap bounds per-request cost, and neither alone is sufficient.

A cap is also straightforward to derive rather than guess: a plausible maximum run duration at a plausible maximum sample rate gives a defensible ceiling, with a `413`/`422` beyond it.

### SEC-11 — Supabase Row Level Security is never mentioned — **Note**

The architecture routes all client access through the Next.js backend, and `database-api-spec.md` §2.1b correctly reserves the service-role key to the backend ("which the mobile client must never hold"). Given that, RLS is defence-in-depth rather than the primary control, which is why this is a Note.

It is worth recording because the safety of the current design rests entirely on one assumption: **no client ever talks to Supabase directly.** That assumption holds today by architecture, not by enforcement. If any future surface uses the anon key directly — a common and entirely reasonable shortcut for, say, a web leaderboard view — tables without RLS are world-readable to anyone holding a key that is, by design, public. Enabling RLS now, while the schema is small, is cheap; enabling it after a second client exists is a migration.

### VERIFIED COVERED — input validation and authorization are genuinely well-specified

Recorded so these are not re-audited without cause:

- **Input validation**: `database-api-spec.md` §3's table covers malformed/missing route (`422`), route points missing `timestamp`/`elevation` (`422`), zero or negative duration/distance (`400`), an unparseable ISO 8601 `since` (`400`), submission without a completed profile (`409`), and duplicate submission (idempotent). Each rule states its rationale. This is above the standard typically found at this stage.
- **Authorization / IDOR**: §3 states — "Any authenticated request for another user's data (incl. `GET /api/runs`): Not possible by construction — every query is scoped to the caller's `user_id` from the verified JWT, never a client-supplied id." Scoping to the token subject rather than validating a client-supplied id eliminates the entire IDOR class structurally rather than per-endpoint. This is the strongest security line in the API spec and should survive any future refactor unchanged.
- **Secrets handling**: the service-role key is explicitly backend-only (§2.1b), with the reason stated. No hardcoded credentials appear in any spec or in the scaffolded backend.

---

## 5. App Store and legal compliance cross-check

Cross-checked against `pre-launch-checklist.md` as it stands. That checklist is solid on Apple-facing requirements — Privacy Policy, App Privacy label, location permission strings, the three-state permission flow, Guideline 5.1.1(v) account deletion, Guideline 4.8 Sign in with Apple, background modes. The gaps below are ones it does not currently cover.


**UPDATE 2026-09-19 (Fase 2 audit) — this "Note" was in fact a live Critical hole, now fixed.** The
review asked whether RLS was ever considered; the answer turned out to matter. Checked against the real
project: **row level security was OFF on all six `public` tables and `anon`/`authenticated` held full
SELECT/INSERT/UPDATE/DELETE** (Supabase's default grants). The `anon` key is embedded in the iOS app and
committed to this repository, which is **public** — so anyone on the internet could read (probe returned
HTTP 200 on every table) or rewrite/delete the whole database over PostgREST with one `curl`: emails, GPS
routes, points, trust scores, the ledger. No real user data was exposed (the database only ever held test
data and there were no users), which is the only reason this was not an incident. The architecture never
needed that access — the app talks to Supabase for Auth only; all data goes through the Vercel API on the
`service_role` key. **Fix:** migration `20260919150457_enable_rls_deny_anon.sql` enables RLS with no policies
(deny-all), revokes all grants from `anon`/`authenticated`, and changes default privileges so future tables
do not reopen it; regression test `backend/lib/rls.integration.test.ts` (12 checks) attacks PostgREST with the
public anon key and requires every table to refuse read and write. Verified after the fix: probe now `401 /
42501` on every table; backend suite 182/182, live release check 7/7, `pg_cron` job still succeeds.
Lesson recorded: "Supabase provides auth" is not "Supabase is secured" — deny-by-default must be explicit.
### SEC-12 — Indonesian data-protection law (UU PDP No. 27/2022) is not referenced in any document — **Warning**

The entire product is geographically Indonesian: leaderboard scopes follow the Indonesian administrative hierarchy (kecamatan / kabupaten-kota / provinsi), the target early-adopter channel is Indonesian campus running communities, and Government is named as a Secondary User. Every user in v1 is therefore an Indonesian data subject.

`pre-launch-checklist.md` covers Apple's requirements thoroughly and **contains no reference to any legal regime at all** — not UU PDP No. 27/2022, not PP 71/2019. Compliance is currently treated as synonymous with App Store review, and those are different things with different enforcement bodies: passing App Review is not a legal safe harbour.

At minimum, and as a non-lawyer flagging areas rather than giving legal advice, the following are the obvious touchpoints, each of which intersects a finding already in this document:

- **Lawful basis and explicit consent** for processing precise location — currently obtained as an iOS system permission prompt, which is an OS-level authorization, not necessarily a documented lawful basis.
- **Retention limits** — directly SEC-1, which currently has no answer.
- **Data subject rights** (access, correction, erasure) — erasure is well covered by §2.1b; **access/portability is not specified anywhere**, i.e. there is no way for a user to export their own data.
- **Breach notification obligations**, which run on a defined timeline and require an incident process to exist *before* an incident.
- **Cross-border transfer**, which is directly relevant here: Supabase and Vercel host outside Indonesia by default, so Indonesian users' precise location data leaves the country. This follows from `ADR-0005` and is not currently noted as a consequence there. If a region choice is available at provisioning time, it is much cheaper to make deliberately now than to migrate later.

Rated **Warning**, not Blocker, deliberately: it does not gate App Store submission, and the correct next step is a qualified legal review rather than an engineering task. But it is the single largest *category* of compliance risk that the existing checklist does not model at all, and the cross-border point in particular has an architectural consequence with a narrow, cheap window (before provisioning) and an expensive one (after data exists).

**Recommendation**: add a legal-compliance section to `pre-launch-checklist.md` distinct from the App Store section, with a single first item — "obtain qualified legal review of UU PDP obligations" — rather than attempting to self-assess the details.

### SEC-13 — No user-facing data export path exists — **Warning**

Following from the above, and independently worth noting: `product-spec.md` §4.17 specifies account **deletion**, and it is well specified. There is no corresponding **export**. A user can destroy their data but cannot obtain a copy of it.

Apple does not require export for App Store approval (only deletion, Guideline 5.1.1(v)), which is why this was never caught by the existing checklist — the checklist is derived from Apple's requirements. Most data-protection regimes, including UU PDP, treat access/portability as a right parallel to erasure.

Practically cheap to satisfy relative to its risk: all the data already exists locally on-device in Core Data, and a "export my runs" action producing GPX or JSON is a small, self-contained feature. Worth scoping into Fase 2 alongside T2.22, where the deletion flow already touches the same data.

### SEC-14 — App Privacy label needs the "Linked to You" determination stated — **Note**

`pre-launch-checklist.md` §2 requires declared data types and purposes to match reality, which is correct. It does not mention Apple's **linkage** and **tracking** dimensions, which are separate questionnaire axes from the data type itself.

For this app the determination is unambiguous and should simply be recorded so it is not mis-answered under submission pressure: location is **Linked to You** (it is tied to a user account, a username, and a public leaderboard identity), and the app does **not** Track (no third-party advertising or data broker sharing, per `lean-canvas.md` §6's freemium/B2B model). Mis-declaring linkage is a common rejection cause and is trivially avoidable by writing the answer down now.

### VERIFIED COVERED — Guideline 5.1.1(v) account deletion

`pre-launch-checklist.md` §4 correctly identifies account deletion as blocking submission entirely once account creation ships, and correctly ties it to `product-spec.md` §4.17 and T2.22. Combined with the §2 verification above, the deletion requirement is covered end-to-end: Apple requirement → product spec → API contract → task DoD. No gap.


### SEC-15 — Supabase email/password provider was left enabled, contradicting the Apple-only decision — **Warning** — **CLOSED 2026-09-19** *(the "Apple-only" premise was reversed 2026-09-21 — Google added; the finding itself stands: email/password stays off)*

Found in the Fase 2 audit. `product-spec.md` §4.1 AC1 and `pre-launch-checklist.md` §5 record a final decision:
**Sign in with Apple only, zero email/password**. The hosted Supabase project never matched it: the public
auth settings showed `external: {apple: true, email: true}` with signup open, so anyone holding the (public)
anon key could `POST /auth/v1/signup` an email account, obtain a JWT, and call the API — outside the intended
sign-in path, with no Apple identity behind it. Beyond the policy mismatch it is a cheap way to mint unlimited
throwaway identities, which matters because `trust_score` is per-`User` row (the same evasion class
`database-api-spec.md` §2.1b point 7 already accepts for delete-then-re-register, but without needing to delete
anything first).

**Fix:** email provider switched off on the project (`auth.email.enable_signup = false`, applied with a
minimal config file so the other 15 remote settings were left untouched — a full `config.toml` push would have
changed 11 unrelated settings, `supabase config diff` showed). Verified against the live project with the public
key: `POST /auth/v1/signup` → `400 email_provider_disabled`; `signInWithPassword` → `Email logins are disabled`;
`POST /auth/v1/otp` → `422 email_provider_disabled`; anonymous sign-in → `422 anonymous_provider_disabled`;
public settings now `external: {apple: true}`. The Apple provider is configured for native token exchange with
`client_id = com.designbyripo.laju`. **Test impact:** every integration test previously used
`signInWithPassword`; they now obtain real JWTs through `backend/test-support/auth.ts` (users created with the
`service_role` Admin API, session issued from a server-generated magic-link token hash) — 194/194 pass with the
provider off.

**Correction to an earlier audit note:** the audit summary cited SEC-6 for this. SEC-6 is a different item —
the privacy trap in the spec's proposed "hash the deleted email" fix — and is **unchanged and still an accepted
Note**. It was not closed by this work.

**Residual, accepted (unchanged):** delete-then-re-register *with the same Apple ID* still yields a fresh `User`
row with default trust (§2.1b point 7).
---

### SEC-16 — Two identity providers, no account linking — **Note** — added 2026-09-21

With Google added beside Apple (product-spec.md §4.1 AC1), one person can hold two Supabase identities: Supabase only merges identities that share an email, and Apple often issues a private-relay address. Consequences, all accepted for v1: a user who signs in with the other provider starts from zero (points, level and history are per identity); and creating a second account is one more way to reset `trust_score`, which SEC-6 already accepts as a risk — a second provider widens that path slightly but does not create it. Email/password stays off (SEC-15 unchanged). Revisit with account linking if real users hit it.

## 6. Findings summary

| ID | Area | Finding | Severity | Status |
|---|---|---|---|---|
| SEC-1 | Location | No retention policy for GPS route data anywhere; blocks Privacy Policy, which blocks submission | **Blocker** | New |
| SEC-9 | API | No rate limiting specified on any endpoint; spec explicitly notes the only throttle is client-side | ~~Blocker~~ **RESOLVED 2026-09-21** (T2.20a) | Closed |
| SEC-2 | Location | Core Data store has no specified `NSFileProtection` class | **Warning** | New |
| SEC-3 | Location | "Unfair Advantage" aggregate-data strategy has no anonymization design — idea only | **Warning** | New |
| SEC-5 | Auth | No JWT lifetime or refresh policy stated anywhere (Keychain-storage half of this finding withdrawn — T2.3 already requires it) | **Warning** | New |
| SEC-7 | Anti-cheat | `RUN.anomaly_flags` survives deletion un-anonymized; `RUN` lacks the field-by-field disposition `User` has | **Warning** | New |
| SEC-10 | API | No size cap on `gps_route` array; amplifies SEC-9 | ~~Warning~~ **RESOLVED 2026-09-21** (T2.20a) | Closed |
| SEC-12 | Compliance | UU PDP No. 27/2022 unreferenced; includes cross-border transfer consequence of ADR-0005 | **Warning** | New |
| SEC-13 | Compliance | No data export path (deletion exists, access does not) | **Warning** | New |
| SEC-4 | Location | Full-fidelity route upload is purpose-bound and justified; governed by SEC-1 | **Note** | New |
| SEC-6 | Auth | `trust_score` evasion accepted risk re-confirmed; proposed future fix has an unrecorded privacy contradiction | **Note** | Re-confirmed |
| SEC-8 | Anti-cheat | No separate pace/speed history store exists; surface is subsumed by SEC-1 | **Note** | Verified sound |
| SEC-11 | API | Supabase RLS unmentioned; defence-in-depth only, given backend-only access | **Note** | New |
| SEC-14 | Compliance | App Privacy "Linked to You" determination should be written down | **Note** | New |
| SEC-16 | Auth | Two identity providers (Apple + Google), no account linking; a second account is one more `trust_score` reset path (SEC-6) | **Note** | New 2026-09-21 |
| — | Auth | **Account deletion: JWT-after-delete and local-wipe both genuinely closed as final requirements** | — | **Verified covered** |
| — | API | Input validation, IDOR-by-construction scoping, and service-role key handling all well specified | — | **Verified covered** |
| — | Compliance | Guideline 5.1.1(v) covered end-to-end from Apple requirement to task DoD | — | **Verified covered** |

**Two Blockers, seven Warnings, five Notes, three areas verified covered.**

Both Blockers share a shape worth naming: neither is a mistake in anything that was decided. Both are decisions that were never made, and where **the default that results from not deciding is the unsafe one** — indefinite retention, and unlimited request rate. The specification set is notably strong wherever a decision was actually taken; its gaps are where the question was never posed.

---

## 7. Cross-references created by this review

Findings here changed two documents outside this file:

- **`adr/0002-core-data-over-swiftdata.md`** — SEC-2 identifies an at-rest encryption consequence of the Core Data decision that the ADR did not record. A Risks entry was added pointing here.
- **`adr/0005-nextjs-supabase-vercel-backend-stack.md`** — SEC-12's cross-border data transfer point is a consequence of that stack choice for an Indonesian user base. A Risks entry was added pointing here.

Neither ADR's Decision or Alternatives sections were altered — the decisions stand as taken; only their recorded consequences were completed.

See also [code-quality-audit.md](./code-quality-audit.md) for the Swift concurrency and pattern audit of the Fase 1 code, conducted alongside this review.
