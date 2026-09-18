# GPS Route Fixture Corpus (T2.6b)

Shared, versioned dataset for the anti-cheat checks (T2.7–T2.10) and their verification (T2.13). Built
up front, before either needs it, so no check gets tested only against data its own implementer wrote —
the gap an earlier audit round found (`audit-report.md`).

**This task produces the data only.** Running the anti-cheat checks against these fixtures is T2.7–T2.10's
and T2.13's job, not this one's (T2.6b's own Scope excludes it explicitly).

## Format

Each fixture is one JSON file:

```json
{
  "name": "pace-cap-breach",
  "category": "pace_cap",
  "source": "synthetic",
  "description": "Human-readable explanation of what this fixture tests and why.",
  "distance_meters": 1498.3,
  "duration_seconds": 225,
  "gps_route": [
    { "lat": -6.2, "lng": 106.8, "timestamp": "2026-09-08T06:00:00Z", "elevation": 40.0 }
  ]
}
```

`gps_route` uses the current point format exactly — `{lat, lng, timestamp, elevation}` per point
(database-api-spec.md §1/§2.2), not the old 2D-only shape. `category` matches one of the five
tech-spec.md §2.4 check rows (`pace_cap`, `gps_speed_jump`, `distance_duration_sanity`,
`elevation_anomaly`) or `clean`/`combined` for negative controls and multi-trigger cases.

This document does **not** prescribe an "expected findings" field — what each check's output shape looks
like is T2.7–T2.10's decision to make, not this task's to anticipate.

## Corpus

| File | Category | Source | What it tests |
|---|---|---|---|
| `clean-negative-control-easy-jog.json` | clean | synthetic | 5km @ 6:00/km (360 s/km) — must trigger zero checks |
| `clean-negative-control-fast-run.json` | clean | synthetic | 5km @ 4:30/km (270 s/km) — deliberately close to, but clear of, the 3:00/km pace cap; catches an over-aggressive check |
| `pace-cap-breach.json` | pace_cap | synthetic | 1.5km sustained @ 2:30/km (150 s/km), under the 3:00/km (180 s/km) cap for >1km |
| `gps-speed-jump.json` | gps_speed_jump | synthetic | 5 consecutive 1s samples @ ~40 km/h, over the 25 km/h cap, sustained past the required >3 samples |
| `teleport.json` | distance_duration_sanity | synthetic | 2km position jump within 2 seconds — a physically impossible instantaneous speed |
| `elevation-anomaly.json` | elevation_anomaly | synthetic | 100m elevation gain within one 2-second point-pair, normal horizontal movement |
| `combined-anomalies.json` | combined | synthetic | One run containing both a pace-cap-breach segment and a GPS-speed-jump segment — tests `excluded_pct`'s aggregation across multiple check types, not single-check isolation |
| `genuine/` | — | **pending** | See below |

Every synthetic fixture was independently verified against its claimed metric using Haversine distance
(not the generator's own flat-earth meters-per-degree approximation, to catch any systematic error) before
being committed — confirmed 2026-09-17: each fixture crosses its intended threshold and, where relevant,
does *not* also cross an unrelated one (e.g. `pace-cap-breach` peaks at 24.0 km/h, under the 25 km/h
speed-jump cap, so it isolates the pace-cap case cleanly; `teleport` sustains only 1 sample over 25 km/h,
not the >3 the speed-jump check requires, so it isolates the distance/duration-sanity case).

## Genuine routes — pending, not fabricated

**DoD requires ≥3 genuine recorded routes, and this corpus currently has zero.** This is reported
honestly rather than worked around: a "genuine" fixture's entire purpose is carrying real-world GPS noise
characteristics that no amount of careful synthetic construction can substitute for — fabricating one and
labeling it genuine would defeat the reason this requirement exists.

What was checked before concluding this needs to stay open:

- No prior on-device run data (T0.8, T0.9, the 24km calibration run pk=81, or any other field test
  referenced throughout `tech-spec.md`/`adr/`) was ever exported to a file in this repo — only ever pulled
  ad-hoc from a device's local Core Data store during the session that needed it, never committed.
- The connected physical device (`Ripo Gagah`, iPhone 13) was reachable earlier in this session but is
  **unavailable** as of this task (`xcrun devicectl list devices` reports `unavailable` — disconnected).
  Its local store cannot be pulled right now regardless of whether old `Run` rows with real `gpsRoute`
  data survive on it.

**To close this**: either (a) reconnect the device and pull any surviving historical `Run` rows via
`devicectl`/on-device SQLite extraction, if T0.8/T0.9-era data is still present, or (b) record ≥3 fresh
real routes with the app (a walk, a run, anything genuinely GPS-captured) and export them in this file's
format. Tracked as an open item — see `documents/README.md` §3.
