# Laju App — Database & API Spec (v1)

Depends on: [architecture.md](./architecture.md)

**Client-agnostic by design:** the schema and API contracts below are
entirely unchanged by the iOS/Swift pivot (tech-spec.md §1). Client-side
field names in this document (e.g. `sync_status`) describe *concept*, not a
specific storage technology — on iOS they map to Core Data entity
attributes (camelCase, e.g. `syncStatus` — repo-coding-rules.md §2), but
the server-side schema/endpoints below stay identical regardless of what
the client is built with.

## 1. ERD

```mermaid
erDiagram
    USER ||--o{ RUN : records
    USER ||--o{ POINT_TRANSACTION : earns
    USER ||--o{ LEADERBOARD_ENTRY : appears_in
    RUN ||--o| POINT_TRANSACTION : generates
    SEASON ||--o{ POINT_TRANSACTION : scopes
    SEASON ||--o{ LEADERBOARD_ENTRY : scopes
    SEASON ||--o{ LEADERBOARD_SCOPE : scopes
    CLUB ||--o{ USER : "(future, nullable)"

    USER {
        uuid id PK
        string email
        string username
        string display_name
        string avatar_url
        string region_kecamatan
        string region_kabupaten_kota "merged tier — kabupaten and kota are the same administrative level in Indonesia, never both for one user"
        string region_provinsi
        int total_points
        int current_level
        float trust_score
        uuid club_id FK "nullable, reserved for future Circle/Club feature"
        timestamp created_at
    }

    RUN {
        uuid id PK
        uuid user_id FK
        timestamp started_at
        timestamp ended_at
        float distance_meters
        int duration_seconds
        int avg_pace_sec_per_km
        jsonb gps_route "array of {lat, lng, timestamp, elevation} per-point samples — NOT a 2D GeoJSON LineString; timestamp+elevation required per point for anti-cheat (tech-spec.md §2.4)"
        string status "validated|flagged|approved|rejected — see tech-spec.md §2.4.1"
        string flag_confidence "low|high — set the moment status becomes flagged; RETAINED (not nulled) through approved/rejected-from-flagged as a historical record of why points were held; null only for validated and immediate-rejected (never flagged)"
        json anomaly_flags "list of anti-cheat checks triggered"
        int estimated_points "client-computed, optimistic"
        int final_points_awarded "server-computed, authoritative; 0 for immediate rejected AND for rejected-via-override (net award after the compensating transaction, tech-spec.md §2.4.1)"
        timestamp resolved_at "nullable — set when a run reaches ANY terminal status: validated, immediate-rejected, OR a flagged run's later approved/rejected. Null only while status=flagged"
        timestamp updated_at "NOT NULL DEFAULT now() — set at insert and re-touched by a DB-level trigger (not application code) on any change to status/flag_confidence/final_points_awarded/resolved_at, so no writer can forget it. The filter column for GET /api/runs?since= (§2.2b); indexed (user_id, updated_at)"
        timestamp created_at
    }

    POINT_TRANSACTION {
        uuid id PK
        uuid user_id FK
        uuid run_id FK "nullable — non-run grants (e.g. adjustment)"
        uuid season_id FK
        int amount
        string type "run|streak_bonus|adjustment"
        timestamp created_at
    }

    LEADERBOARD_ENTRY {
        uuid id PK
        uuid season_id FK
        string scope_type "global|kecamatan|kabupaten_kota|provinsi"
        string scope_id "NOT NULL — sentinel 'GLOBAL' for global scope, consistent with LEADERBOARD_SCOPE"
        uuid user_id FK
        int points
        int rank
        timestamp computed_at
    }

    LEADERBOARD_SCOPE {
        uuid season_id FK "composite PK with scope_type, scope_id"
        string scope_type "global|kecamatan|kabupaten_kota|provinsi"
        string scope_id "NOT NULL — sentinel 'GLOBAL' for global scope (composite PK cannot hold NULL in Postgres)"
        int user_count "how many users have entries in this scope this season"
        boolean insufficient_data "true if user_count < configurable threshold N"
        timestamp computed_at
    }

    SEASON {
        uuid id PK
        string name
        timestamp start_at
        timestamp end_at
        string status "upcoming|active|ended"
        timestamp created_at
    }

    CLUB {
        uuid id PK "future entity — NOT built in v1"
        string name
        string region
    }
```

**Level** is intentionally not a per-user table — it is a static lookup
config (`level_thresholds: [{level, points_required, title}]`) since level
is a pure function of `User.total_points`. Defined independently on each
side — `ios/Laju/PointFormula` (Swift, T1.3) and `backend/lib` (TypeScript,
T2.15) — since client and server can no longer share one literal module
post-pivot. Unlike the point formula (tech-spec.md §2.2b), this table is
small and static enough that a fixture file is unnecessary overhead —
parity is instead enforced by each side having a unit test asserting its
`levelThresholds` values match the table below exactly, row for row (T1.3,
T2.15). No dedicated migration needed — not a DB seed/config table.

**v1 starting values** (starting point, not final — needs tuning with
real data, same status as the pace-multiplier table in tech-spec.md §2.3):

| Level | `points_required` (cumulative) | Title |
|---|---|---|
| 1 | 0 | Pemula |
| 2 | 100 | Rajin |
| 3 | 300 | Konsisten |
| 4 | 700 | Gigih |
| 5 | 1500 | Veteran |
| 6 | 3000 | Elit |
| 7 | 6000 | Master |
| 8 | 12000 | Legenda |

`current_level` = highest level whose `points_required` ≤
`User.total_points`; `points_to_next_level` (§2.3 response) = next
level's `points_required` − `User.total_points` (undefined/0 at the top
level, v1 has no level cap beyond 8 — a run that pushes past level 8
simply stays at level 8 until this table is extended).

**Future extension points already reserved (not built in v1):**
- `USER.club_id` — nullable FK, unused until Circle/Club ships.
- `CLUB` table shape sketched but not migrated in v1 (documented here for
  forward compatibility of the ERD only).

**`LEADERBOARD_SCOPE`** is the persisted home for the `insufficient_data`
flag that `GET /api/leaderboard` (§2.4) returns and that architecture.md
§4 describes computing — one row per `(season_id, scope_type, scope_id)`,
written by the same precompute job that writes `LEADERBOARD_ENTRY` rows.
**`global` is an explicit `scope_type` value in this table** (row with
`scope_type='global'`, `scope_id='GLOBAL'`), not represented by the
absence of a row — the precompute job writes it starting Fase 2
(`insufficient_data` hardcoded `false` for global, since a global user
count has no meaningful density threshold). Migrated in Fase 2 alongside
the other core entities (tasks/phase-2 T2.2), because the global
leaderboard needs this row from the moment it ships — not deferred to
Fase 3. Fase 3 (tasks/phase-3) only adds rows for the local scope types
(`kecamatan`, `kabupaten_kota`, `provinsi`) on top of the table that
already exists.

**Why `scope_id='GLOBAL'` (sentinel), not `NULL`:** `LEADERBOARD_SCOPE`'s
primary key is the composite `(season_id, scope_type, scope_id)` —
PostgreSQL implicitly makes every `PRIMARY KEY` column `NOT NULL`, so
the table literally cannot store a `scope_id=null` row. `'GLOBAL'` is a
reserved literal `scope_id` value, never a real region code (region
codes are lowercase administrative names, never uppercase). Same
sentinel applied to `LEADERBOARD_ENTRY.scope_id` for consistency between
the two tables. This is purely an **internal storage detail** — the
public API (`GET /api/leaderboard` request/response, §2.4) is
unaffected: clients still pass `scope=global` with no `scope_id`, and
the response's `scope_id` field is still `null` for a global request
(the backend translates `'GLOBAL'` ↔ `null` at the query boundary, the
same way T2.18/T2.2 own the internal representation without leaking it
externally).

**Region hierarchy note:** Indonesia's administrative hierarchy is
Provinsi → Kabupaten/Kota → Kecamatan → Kelurahan/Desa. Kabupaten and
Kota are the **same tier** (one region is either a kabupaten or a kota,
never both) — v1 therefore stores a single `region_kabupaten_kota` field
and offers exactly 3 local leaderboard scopes: `kecamatan` (most local),
`kabupaten_kota`, and `provinsi` (broadest). The earlier "daerah" term
and the separate `region_kota` field have been removed as undefined/
redundant.

## 2. API Endpoints (v1)

Auth: all endpoints except `/api/auth/*` require `Authorization: Bearer
<supabase_jwt>`. Backend verifies the JWT against Supabase Auth; it does not
issue its own session tokens.

### 2.1 Auth

Auth itself is handled client-side via the Supabase Auth SDK (sign up,
sign in, session refresh) — the mobile app talks to Supabase directly for
these, not through the Next.js API. The one backend-owned step is
completing the profile (region, username) after first sign-in.

`POST /api/profile/complete`

Request:
```json
{
  "username": "budi_run",
  "display_name": "Budi",
  "region_kecamatan": "Cilandak",
  "region_kabupaten_kota": "Jakarta Selatan",
  "region_provinsi": "DKI Jakarta"
}
```

Response `201`:
```json
{
  "id": "usr_123",
  "username": "budi_run",
  "total_points": 0,
  "current_level": 1
}
```

### 2.2 Submit Run

`POST /api/runs`

Request:
```json
{
  "started_at": "2026-09-08T06:00:00Z",
  "ended_at": "2026-09-08T06:32:10Z",
  "distance_meters": 5230,
  "duration_seconds": 1930,
  "gps_route": [
    { "lat": -6.2, "lng": 106.8, "timestamp": "2026-09-08T06:00:01Z", "elevation": 45.2 },
    { "lat": -6.2001, "lng": 106.8001, "timestamp": "2026-09-08T06:00:02Z", "elevation": 45.3 }
  ]
}
```

`gps_route` is an array of per-point samples — `lat`/`lng` (degrees),
`timestamp` (ISO 8601), `elevation` (meters). All four fields are
required on every point; a 2D-only point (no `timestamp`/`elevation`)
is rejected per §3's malformed-route rule, since the anti-cheat checks
in tech-spec.md §2.4 cannot compute instantaneous speed or elevation
change without them.

Validation is synchronous — the response always carries the **initial**
resolution status for this submission (see tech-spec.md §2.4.1 for the
full state machine). No polling is needed for that initial outcome. A
`flagged` run's *later* resolution (LOW auto-approves up to
`REVIEW_WINDOW_LOW` after submission; HIGH resolves at an arbitrary
later time via manual override) is reconciled separately — see §2.2b
`GET /api/runs`.

Response `201` (validated example):
```json
{
  "run_id": "run_456",
  "status": "validated",
  "flag_confidence": null,
  "final_points_awarded": 62,
  "resolved_at": "2026-09-08T06:32:15Z",
  "anomaly_flags": []
}
```

Response `201` (flagged example — partial points recorded, excluded from
leaderboard until resolved; `flag_confidence: "low"` auto-resolves within
`REVIEW_WINDOW_LOW`, default 48h — `"high"` never auto-resolves, see
tech-spec.md §2.4.1):
```json
{
  "run_id": "run_457",
  "status": "flagged",
  "flag_confidence": "low",
  "final_points_awarded": 18,
  "resolved_at": null,
  "anomaly_flags": ["gps_speed_jump_segment_3", "pace_cap_exceeded"]
}
```

Response `201` (rejected example — immediate, no points ever granted):
```json
{
  "run_id": "run_458",
  "status": "rejected",
  "flag_confidence": null,
  "final_points_awarded": 0,
  "resolved_at": "2026-09-08T06:32:15Z",
  "anomaly_flags": ["pace_cap_exceeded_majority_segments"]
}
```

`flag_confidence` is included so the client can differentiate LOW vs HIGH
messaging (T2.14b) without a second request. **In this endpoint's
response specifically**, it is non-null only for `flagged` — because
`POST /api/runs` only ever returns a run's **initial** status, and a run
cannot be `approved` or overridden-`rejected` at submission time. Once a
`flagged` run later resolves, `flag_confidence` is **retained** (not
nulled) — see §1 and §2.2b, whose examples show this.

### 2.2b Get Run Status (reconciliation)

`GET /api/runs[?since=<ISO8601 timestamp>]`

Returns the caller's runs whose `updated_at` is at or after `since` — the
mechanism a client uses to learn about a `flagged` run's later
resolution, since that resolution happens after the run is already
synced (LOW confidence up to `REVIEW_WINDOW_LOW` later, HIGH confidence
at an arbitrary later time via manual override — tech-spec.md §2.4.1).
Filtering on `updated_at` (not `resolved_at`) is deliberate: `resolved_at`
is `null` for any run still `flagged`, so a `resolved_at`-based filter
would never surface those — `updated_at` is touched on every mutation,
including the transition *into* `flagged`, so nothing is missed. Not a
general run-history/pagination endpoint — scoped specifically to status
reconciliation for locally-stored runs the client is still watching
(anything whose local `server_status` column, T0.6, is `flagged`).

Query params:
- `since`: **optional**, ISO 8601 timestamp — see the clock-source note
  below for why it's optional and what happens when it's omitted

Response `200`:
```json
{
  "server_time": "2026-09-10T06:00:05Z",
  "has_more": false,
  "runs": [
    {
      "run_id": "run_457",
      "status": "approved",
      "flag_confidence": "low",
      "final_points_awarded": 18,
      "resolved_at": "2026-09-10T06:00:00Z",
      "updated_at": "2026-09-10T06:00:00Z",
      "anomaly_flags": ["gps_speed_jump_segment_3", "pace_cap_exceeded"]
    },
    {
      "run_id": "run_501",
      "status": "rejected",
      "flag_confidence": "high",
      "final_points_awarded": 0,
      "resolved_at": "2026-09-10T05:58:00Z",
      "updated_at": "2026-09-10T05:58:00Z",
      "anomaly_flags": ["gps_speed_jump_segment_1", "gps_speed_jump_segment_2"]
    }
  ]
}
```

`status: "approved"` — the resolved-from-flagged terminal state — did not
previously appear in any example in this document before this endpoint
was added. The second entry shows the `flagged → rejected` override
case: `flag_confidence` is **retained** (not nulled) and
`final_points_awarded` is `0` (the net award after the compensating
`PointTransaction`, tech-spec.md §2.4.1) — this is the case a naive
reading of an earlier draft of this field got wrong.

**Clock source (avoids device-clock-skew bugs, and solves the cold-start
problem):** the client must never compute `since` from its own
`Date.now()`. On every call **after** the first, persist the
**`server_time`** value from this response and send it as `since` on the
next call — never a client-generated timestamp. On the **first-ever**
call (no `since` available yet — nothing has been persisted locally),
**omit `since` entirely**: the server defaults to a fixed lookback
(`now() - 90 days`, comfortably longer than `REVIEW_WINDOW_LOW` plus any
realistic HIGH-confidence review delay) and returns `server_time` as
usual, which the client then persists for every subsequent call. This is
the only legal way to obtain a first `since` — no server timestamp is
otherwise available to the client before its first successful call to
this endpoint, and using a device timestamp is explicitly forbidden. A
fast or slow device clock cannot then cause resolutions to be silently
and permanently skipped, on the first call or any later one.

**Result cap and drain order (fixes a data-loss direction bug in an
earlier draft of this endpoint):** response capped at 200 rows, ordered
`updated_at` **ASC** (oldest-changed-first), `has_more: true` when
exactly 200 rows are returned and **newer** unreturned changes beyond
this batch may remain.
- **When `has_more: false`:** persist `server_time` as the next `since`
  — the window is fully drained.
- **When `has_more: true`:** persist the **last row's `updated_at`** (the
  newest timestamp in *this* batch, still older than what's undrained)
  as the next `since`, and re-call immediately rather than waiting for
  the next scheduled cycle, repeating until `has_more: false`. A follow-up
  call is expected to re-return that same boundary row (the filter is
  inclusive, `>= since`) — this is harmless since updates are idempotent
  overwrites, but if a batch of ≥200 runs shares an identical `updated_at`
  (e.g. many resolved in one `resolve-flagged-runs` invocation), the
  client must break the drain loop once a follow-up call returns no row
  newer than the current cursor, rather than looping forever.
  (Ordering **DESC** with `server_time` as the next cursor — an earlier
  draft's approach — is wrong: it advances the window forward past the
  undrained older rows, permanently skipping them. ASC + last-row-cursor
  is the only direction that can't lose data.)

**Call frequency (client-side rule, not enforced server-side in v1):**
the client calls this endpoint only when it holds at least one
locally-stored run whose local `server_status` (T0.6) is `flagged` — if
there are none, the call is skipped entirely, on both app-open and each
sync cycle. When there is at least one watched run: call on app open
**subject to** the same cadence floor below (app-open does not bypass
it), and on a sync cycle only if **at least 15 minutes have elapsed
since the last reconciliation attempt** — the attempt timestamp is
persisted in `sync_meta.last_reconcile_attempt_at` (T0.6) so the cadence
survives app restarts, not just held in memory. A failed call still
updates `last_reconcile_attempt_at` (so it counts toward the 15-minute
floor and can't be retried in a tight loop) but does **not** advance
`last_reconciled_at` (so the next attempt re-covers the same window) and
does **not** enter the run-upload retry queue — it is independent of,
and never blocks, T2.14's push/retry flow.

### 2.3 Get Point/Level for Current User

`GET /api/users/me/progress`

Response `200`:
```json
{
  "total_points": 1240,
  "current_level": 6,
  "points_to_next_level": 260,
  "trust_score": 0.98
}
```

### 2.4 Get Leaderboard

`GET /api/leaderboard?scope=kabupaten_kota&scope_id=Jakarta+Selatan&season_id=season_2026_q3`

Query params:
- `scope`: `global | kecamatan | kabupaten_kota | provinsi` (required)
- `scope_id`: required unless `scope=global`
- `season_id`: optional, defaults to active season
- `limit`: optional, default 50

`insufficient_data` is read from the `LEADERBOARD_SCOPE` table (§1) — it
is `true` when the scope's `user_count` is below the configurable
threshold N, not inferred from an empty `entries` array.

Response `200`:
```json
{
  "season_id": "season_2026_q3",
  "scope": "kabupaten_kota",
  "scope_id": "Jakarta Selatan",
  "computed_at": "2026-09-08T07:00:00Z",
  "insufficient_data": false,
  "entries": [
    { "rank": 1, "user_id": "usr_88", "username": "andi_r", "points": 4200 },
    { "rank": 2, "user_id": "usr_123", "username": "budi_run", "points": 3980 }
  ],
  "me": { "rank": 47, "points": 1240 }
}
```

### 2.5 Get Season Info

`GET /api/seasons/active`

Response `200`:
```json
{
  "id": "season_2026_q3",
  "name": "Season 3 — 2026",
  "start_at": "2026-07-01T00:00:00Z",
  "end_at": "2026-09-30T23:59:59Z",
  "status": "active",
  "days_remaining": 22
}
```

## 3. Validation & Error Handling Rules

| Rule | Behavior |
|---|---|
| Run pace faster than 3:00/km sustained over >1km | Segment excluded from point calc; contributes to the exclusion-percentage that decides `flagged` vs `rejected` (tech-spec §2.4.1) — never auto-rejected from a single check alone |
| Total excluded segments ≥ `REJECT_THRESHOLD_PCT` (default 50%) | Run status → `rejected` immediately (synchronous); no `PointTransaction` ever written, `final_points_awarded: 0` (tech-spec §2.4.1) |
| Total excluded segments between `FLAG_THRESHOLD_PCT` (10%) and `REJECT_THRESHOLD_PCT` (50%) | Run status → `flagged`, `flag_confidence` set to `low` (10%–<25%) or `high` (25%–<50%); partial `PointTransaction` written but excluded from leaderboard precompute until resolved. `low` auto-resolves to `approved` after `REVIEW_WINDOW_LOW` (default 48h); `high` never auto-resolves — requires manual override (tech-spec §2.4.1) |
| Run with zero/negative duration or distance | `400 Bad Request`, rejected outright — not a plausible anomaly, a malformed request |
| Run submitted for a user without completed profile (no region set) | `409 Conflict` — run accepted into a holding state is out of scope for v1; client is expected to block submission until profile is complete (product-spec AC 4.1.2) |
| Duplicate run submission (same `started_at`+`user_id` retried by sync queue) | Idempotent — server returns the existing run's result instead of creating a duplicate `PointTransaction` |
| Leaderboard request for a LOCAL scope (`kecamatan`/`kabupaten_kota`/`provinsi`) with no `LEADERBOARD_SCOPE` row yet | `200` with `entries: []` and `insufficient_data: true` — never `404`, this is an expected state right after season start |
| Leaderboard request for `scope=global` | `LEADERBOARD_SCOPE` row always exists from Fase 2 onward (`scope_type='global'`); `insufficient_data` is always `false` |
| GPS route point missing `timestamp` or `elevation` | `422 Unprocessable Entity` — same rule as a missing/malformed route (tech-spec.md §2.4 checks cannot run without them) |
| GPS route missing or malformed JSON | `422 Unprocessable Entity` — cannot validate anti-cheat without a route, run is not accepted |
| `GET /api/runs` with no `since` (first-ever call) | `200`, server defaults to a `now() - 90 days` lookback — not an error (§2.2b) |
| `GET /api/runs` with a `since` present but not a parseable ISO 8601 timestamp | `400 Bad Request` |
| `GET /api/runs` result would exceed 200 rows | `200` with exactly 200 rows (oldest-changed-first) and `has_more: true` — never truncated silently without the client being able to detect it and drain the rest (§2.2b) |
| Requests without a valid Supabase JWT | `401 Unauthorized` |
| Any authenticated request for another user's data (incl. `GET /api/runs`) | Not possible by construction — every query is scoped to the caller's `user_id` from the verified JWT, never a client-supplied id |
