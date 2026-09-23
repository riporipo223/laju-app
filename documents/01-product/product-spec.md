# Laju App — Product Spec (v1)

Source of truth: [lean-canvas.md](./lean-canvas.md), [mvp-report.md](../05-reports/mvp-report.md)

## 1. Problem & Value Proposition (synthesis)

Running apps today (Strava, Nike Run Club) retain users mainly through social
mechanics — kudos, comparison, sharing. Users without an active social circle
in the app lose motivation once the novelty fades. Evidence from the market
(Strava's explicit-goal cohort hitting 72% goal-completion) shows that
**structure** — visible progress, milestones, goals — drives consistency more
reliably than social logging alone.

Laju's bet: treat running as a **progression system** (points → level → rank
→ leaderboard), not a social feed. The core loop must be rewarding for a
single player with zero friends on the app. Social features are a later
layer, not the retention mechanism.

**Value proposition:** "Lari yang berasa seperti main game, bukan sekadar
logging."

## 2. Target Users (v1)

| Segment | Motivation | Product implication |
|---|---|---|
| Progress Runner | Numbers, achievement, checklists | Primary v1 audience — core loop must work standalone for this user |
| Aspiring Runner | Wants to build a habit, needs external structure | Onboarding + first-run reward must create an immediate "hook" |
| Community Runner | Social validation, light competition | Served indirectly in v1 via leaderboard visibility; no dedicated social features yet |

Secondary users (club, EO, government, sports brand) are **not** addressed by
v1 product surface — they are future B2B/monetization targets (see
Non-goals).

## 3. Feature List — MoSCoW

| Feature                                                                                     | Priority       | v1 scope note                                                                                                                                                                                                            |
| ------------------------------------------------------------------------------------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Account / profile (needed to persist points, identity across devices, leaderboard identity) | **Must**       | Minimal: email/password or OAuth, username, region                                                                                                                                                                       |
| GPS run tracking (background)                                                               | **Must**       | Core action; must survive app backgrounding                                                                                                                                                                              |
| Point calculation (formula + anti-cheat)                                                    | **Must**       | Server is source of truth; client shows optimistic estimate                                                                                                                                                              |
| Level / Rank progression                                                                    | **Must**       | Derived from cumulative points                                                                                                                                                                                           |
| Leaderboard — Global                                                                        | **Must**       | Precomputed, season-scoped                                                                                                                                                                                               |
| Leaderboard — Local (kota)                                                                  | **Won't (v1)** | ~~Deferred to v1.1 / Fase 4 (decided 2026-09-21), not cancelled — needs high user density to be useful.~~ **CANCELLED PERMANENTLY 2026-09-22, not deferred** — see §4.6 and Non-goals. Missed by all 4 prior audit sweeps of that reversal (this table is §3, the AC section fixed was §4.6), caught 2026-09-23. Tasks T3.2–T3.5 preserved in tasks/phase-4-backlog.md as historical record only |
| Season system (reset cycle)                                                                 | **Must**       | Drives re-engagement; resets rank, not lifetime stats                                                                                                                                                                    |
| Run history / stats view                                                                    | **Must**       | Promoted from Should 2026-09-13 (Round 7 finding N7-4) — §4.9 AC2 (static map) load-bears on this screen existing; see §4.18                                                                                             |
| Streak indicator                                                                            | Should         | Visual only in v1; feeds into point bonus already in formula                                                                                                                                                             |
| Offline sync status indicator                                                               | Should         | User-facing trust signal for offline-first behavior                                                                                                                                                                      |
| Live map during tracking                                                                    | **Must**       | Added 2026-09-12 — reverses the prior "Route map visualization" Non-goal below (§5); see §4.8. MapKit (native, no per-request cost, tech-spec.md §1) removes the cost objection that originally justified deferring this |
| Static route map (Run Summary & History)                                                    | **Must**       | Added 2026-09-12; see §4.9. Renders already-captured `gps_route`, no new data collection                                                                                                                                 |
| Splits per kilometer                                                                        | **Must**       | Added 2026-09-12; see §4.10                                                                                                                                                                                              |
| Auto-pause                                                                                  | **Must**       | Added 2026-09-12; see §4.11. Reuses the existing `stationaryAnchor` drift guard (T0.9/T1.2b) as an explicit user-facing Pause trigger, not a new detection mechanism                                                     |
| Elevation gain/loss                                                                         | **Must**       | Added 2026-09-12; see §4.12. `elevation` per `gps_route` point already captured since T0.8                                                                                                                               |
| Audio cues (distance/pace announcement)                                                     | **Must**       | Added 2026-09-12; see §4.13                                                                                                                                                                                              |
| Crash/interrupt recovery flow                                                               | **Must**       | Added 2026-09-12; see §4.14                                                                                                                                                                                              |
| Refined location permission flow (While Using vs Always vs Denied)                          | **Must**       | Added 2026-09-12; see §4.15                                                                                                                                                                                              |
| Streak reminder notification                                                                | **Must**       | Added 2026-09-12; see §4.16. Local notification only — streak is already tracked entirely on-device (T1.1/T1.4), no backend needed                                                                                       |
| Account deletion                                                                            | **Must**       | Added 2026-09-12; see §4.17. App Store Guideline 5.1.1(v) — release blocker once Fase 2 auth exists, not optional                                                                                                        |
| Seasonal pass / Premium stats / Exclusive badge / Premium profile                           | Could          | Monetization, post-core-loop validation                                                                                                                                                                                  |
| B2B dashboard (club, EO)                                                                    | Could          | Depends on club entity, which is Won't for v1                                                                                                                                                                            |
| ~~Circle~~ Club / Group                                                                     | **Won't (v1)** | Explicit scope cut, see Non-goals. Renamed "Circle"→"Club" 2026-09-23                                                                                                                                                    |
| Club War                                                                                    | **Won't (v1)** | Depends on Club. **Confirmed to build (Fase 4), 2026-09-23** — see §4.19. Still Won't for v1 itself                                                                                                                     |
| Matchmaking (club-to-club)                                                                  | **Won't (v1)** | Depends on Club                                                                                                                                                                                                          |
| Social Feed (post run achievements, likes, comments)                                        | **Won't (v1)** | Only existed as an unreconciled draft in user-flow.md — see Non-goals; recommendation: Fase 4 backlog (T4.15), not Fase 3 — same "prove the loop alone first" rationale as Club                                          |
| Apple Watch companion app                                                                   | **Won't (v1)** | Low priority, large effort (separate target, WatchConnectivity) — added 2026-09-13, tasks/phase-4-backlog.md T4.14                                                                                                       |
| Government / sports-brand partnership tooling                                               | **Won't (v1)** | No product surface needed until B2B validated                                                                                                                                                                            |
| Android support                                                                             | **Won't (v1)** | v1 launches iOS-exclusive; ditunda tanpa timeline pasti — lihat tech-spec.md §1                                                                                                                                          |

## 4. User Stories & Acceptance Criteria (Must-have v1)

### 4.1 Account & Profile

> **Update 2026-09-22 (PM sign-off):** Local Leaderboard is now **cancelled permanently** (§4.6),
> not deferred — the region-collection rationale below (AC2/D1) no longer applies and has been
> reversed. Region (kecamatan/kabupaten_kota/provinsi) is being **removed entirely** from
> onboarding and the database, replaced by a location-permission-granted gate on Global leaderboard
> visibility — see the new mechanism note under §4.5 AC5.

**Sebagai** calon pengguna, **saya ingin** membuat akun dan mengisi region
saya, **supaya** progres saya tersimpan dan saya muncul di leaderboard.
(Sampai 2026-09-21 kalimat ini berbunyi "leaderboard lokal yang benar" —
Local Leaderboard di-defer ke v1.1, lihat §4.6; region tetap dikumpulkan
sekarang sebagai data yang disiapkan untuk fitur itu. **Sejak 2026-09-22
kalimat ini sudah tidak berlaku — lihat catatan di atas.**)

- AC1: User bisa daftar dengan **Sign in with Apple** atau **Google** dalam
  ≤3 langkah. Nol email/password (SEC-15), nol provider lain.
  > **Keputusan 2026-09-21 — MEMBALIK keputusan "Apple only" 2026-09-17
  > (T2.3).** Google Sign-In ditambahkan sebagai opsi resmi kedua, berdampingan
  > dengan Apple (Apple TIDAK dihapus). Alasan: (1) Android ada di roadmap
  > (tanpa timeline) dan Google adalah login default di sana — lebih baik
  > disiapkan dari awal; (2) Google lewat Supabase tidak butuh entitlement
  > Apple Developer berbayar, sehingga alur auth nyata bisa diuji tanpa
  > menunggu keputusan upgrade. Keputusan lama (2026-09-17) beralasan: satu
  > tombol SSO sesuai desain onboarding (reference #4/Peloton) dan Guideline
  > 4.8 terpenuhi otomatis karena tak ada provider lain — alasan kedua itu
  > sekarang dipenuhi dengan cara lain, lihat di bawah.
  > **Guideline 4.8 tetap patuh:** aturannya hanya mewajibkan opsi login
  > setara Apple HADIR bila ada login pihak ketiga lain; Apple tetap ada, jadi
  > terpenuhi (pre-launch-checklist.md §5). **Batasan yang diterima:** Apple
  > dan Google adalah dua identitas terpisah; Supabase hanya menggabungkan bila
  > emailnya sama, dan Apple sering memakai email relay — orang yang sama bisa
  > punya dua akun. Tidak ada penggabungan akun di v1 (security-review.md
  > SEC-16). Detail teknis: tech-spec.md §6.
~~- AC2: User wajib set region (minimal kecamatan + kabupaten/kota) sebelum
  run pertama bisa disubmit ke server.~~
  > **Keputusan FINAL D1 (2026-09-21): region tetap wajib di v1.** ~~Setelah
  > Local Leaderboard di-defer (§4.6), memang tidak ada layar v1 yang memakai
  > region. Tetap diwajibkan karena biayanya rendah (satu field di
  > onboarding/profil) dan manfaatnya jelas: data region user sudah lengkap
  > saat Local Leaderboard dikerjakan, sehingga tidak perlu re-onboarding
  > seluruh user lama. Tidak ada perubahan kode maupun AC: backend `409`
  > tanpa region (T2.5) tetap berlaku, AC ini tetap Must-have, T3.1 tetap di
  > v1. Ini bukan lagi pertanyaan terbuka.~~
  >
  > **D1 REVERSED 2026-09-22 (PM sign-off).** Region collection is **removed
  > entirely** from onboarding and the database — not replaced with GPS-based
  > text detection, just removed. Rationale: D1's own justification ("data
  > region user sudah lengkap saat Local Leaderboard dikerjakan") no longer
  > applies now that Local Leaderboard is cancelled permanently (§4.6), not
  > deferred — there is no future feature left to prepare this data for.
  > **Replacement mechanism**: Global leaderboard visibility is now gated on
  > whether the user has **granted location permission** (boolean/status
  > only — no place name, no reverse geocoding, no administrative hierarchy
  > stored anywhere) — see §4.5 AC5. This reuses the location-permission
  > infrastructure that already exists for run tracking (`CLLocationManager`);
  > no second, separate permission flow. AC2 above is struck through; backend
  > `409`-without-region (T2.5) and T3.1's onboarding step are being removed
  > (tasks/phase-3-season.md T3.1, tasks/phase-2-backend-sync-global-leaderboard.md
  > T2.5 — see Task B/C of this reversal for the implementation work).
- AC3: Login persist di device (tidak perlu login ulang tiap buka app).

### 4.2 GPS Run Tracking
**Sebagai** runner, **saya ingin** app tetap melacak lari saya walau layar
mati atau app di-background, **supaya** saya tidak kehilangan data run.

- AC1: Tracking tetap aktif minimal 60 menit dengan layar mati, GPS drift
  tidak menyebabkan jarak melenceng >5% dari jarak aktual (uji manual rute
  dikenal).
- AC2: Jika app di-kill paksa oleh OS, run yang sudah tercatat sampai titik
  terakhir tetap tersimpan lokal (tidak hilang total).
- AC3: User bisa start/pause/stop run dengan jelas dari UI.

### 4.3 Point Calculation
**Sebagai** runner, **saya ingin** mendapat poin segera setelah run selesai,
**supaya** saya merasakan progres instan.

- AC1: Estimasi poin muncul di device dalam <2 detik setelah run disudahi
  (offline, dihitung lokal).
- AC2: Poin final (server-validated) muncul setelah sync berhasil; jika
  berbeda dari estimasi lokal, user diberi tahu alasannya (mis. run
  diflag).
- AC3: Run dengan pace tidak masuk akal tidak otomatis dapat poin penuh —
  lihat aturan anti-cheat di [tech-spec.md](../02-architecture/tech-spec.md).

### 4.4 Level Progression
**Sebagai** runner, **saya ingin** melihat level saya naik seiring poin
bertambah, **supaya** saya punya tujuan jangka panjang selain satu run.

> **Catatan istilah:** "Rank" di dokumen ini SELALU berarti posisi user di
> leaderboard (`LEADERBOARD_ENTRY.rank` — lihat database-api-spec.md §1),
> season-scoped dan reset tiap season baru. "Level" adalah entitas
> terpisah: progres lifetime dari total poin kumulatif, tidak pernah
> reset. Tidak ada tier/rank persisten tambahan di v1 — "liga" (tier) yang
> dipakai AC Premium §4.5 AC4 bukan persisten: ia dihitung dari poin season
> berjalan dan reset tiap season (tech-spec.md §2.5). Lihat §4.5/§4.6
> untuk acceptance criteria Rank (leaderboard; v1 = Global saja, §4.5).

- AC1: Level dihitung dari total poin kumulatif (lifetime, tidak direset
  per season).
- AC2: User mendapat notifikasi/visual saat naik level.
- AC3: Threshold poin per level terlihat di profil (progress bar ke level
  berikutnya).

### 4.5 Leaderboard — Global
**Sebagai** runner, **saya ingin** melihat posisi saya dibanding semua
pengguna, **supaya** saya termotivasi kompetitif.

- AC1: Leaderboard menampilkan top N + posisi user sendiri walau di luar
  top N.
- AC2: Data leaderboard maksimal "basi" 15 menit (precompute interval,
  lihat [architecture.md](../02-architecture/architecture.md)).
- AC3: Leaderboard di-scope per season aktif.
- AC4 (Freemium vs Premium — direvisi 2026-09-21, sebelumnya "Global &
  Local penuh"): **"Tier" = Season League** (Bronze / Silver / Gold /
  Platinum), divisi yang dihitung dari **poin yang didapat selama season
  berjalan**, reset tiap season — BUKAN Level (lifetime) dan BUKAN Rank
  (posisi real-time). Definisi, band poin, dan catatan kalibrasi: tech-spec.md
  §2.5. Freemium melihat leaderboard Global untuk **liga sendiri** saja;
  Premium membuka **semua liga di Global**. Diferensiasi ini murni di dalam
  Global — tidak ada lagi perbandingan Global-vs-Local di v1. Poin dan rank
  sendiri sama persis untuk keduanya (user-flow.md §1). Berlaku bersama tier
  Premium itu sendiri, yang masih Non-goal v1 (§5 Monetisasi) — gating
  filter-per-liga belum dibangun (Fase 4). Yang SUDAH masuk v1 sebagai
  fondasi: penurunan liga dari poin season dan tampilan liga sendiri (task
  T3.7a, Fase 3). AC ini bukan requirement Must-have v1.
- AC5 (added 2026-09-22, replaces region-based access — see §4.1 D1
  reversal): **Leaderboard visibility is gated on whether the user has
  granted location permission**, not on a stored region. `CLLocationManager`
  authorization status only (`authorizedWhenInUse`/`authorizedAlways`) —
  boolean/status, no place name, no reverse geocoding, no admin hierarchy
  stored anywhere. Reuses the location-permission infrastructure already
  built for run tracking; no second, separate permission flow.
  **Fallback if permission is denied/not granted** (flagged explicitly: this
  is the PM's stated assumption as of 2026-09-22, not yet confirmed in
  detail — correct this AC if the actual intent differs): the Leaderboard
  tab shows a locked state with a CTA to enable location in Settings, same
  pattern as the existing "tracking background tidak optimal" +
  Settings-button flow already in onboarding (user-flow.md §2.1). The rest
  of the app stays usable — this gate affects Leaderboard visibility only,
  not run tracking, points, or level.

### 4.6 Leaderboard — Local (~~DEFERRED ke v1.1 / Fase 4~~ **CANCELLED PERMANENTLY, 2026-09-22**)

> **Status (2026-09-21): ditunda, bukan dibatalkan.** ~~Alasan: leaderboard
> per kecamatan/kabupaten baru berguna kalau kepadatan user tinggi — dengan
> user awal yang sedikit, satu kecamatan hanya berisi beberapa orang dan
> leaderboard-nya kosong/tidak kompetitif. Nilainya muncul SETELAH ada
> banyak user, bukan prasyarat awal; Global-only justru terasa "lokal" secara
> natural saat user masih sedikit. Tiga AC di bawah DIPERTAHANKAN utuh
> sebagai spesifikasi untuk saat fitur ini dikerjakan (tasks T3.2–T3.5,
> dipindah ke tasks/phase-4-backlog.md); tidak ada task v1 yang
> memverifikasinya, jadi tidak ada di AC Coverage Matrix sebagai Must-have.~~
>
> **CANCELLED PERMANENTLY, 2026-09-22 (PM sign-off) — reverses the status
> above.** Rationale: scope too broad for the leaderboard logic actually
> needed — not a density/timing problem to revisit later, a scope decision.
> The three AC below are kept, struck through, as a historical record of
> what was specified (same pattern as auto-pause's removal, §4.11) — they
> will **not** be implemented, ever, not even in v1.1/Fase 4. Tasks
> T3.2–T3.5 (tasks/phase-4-backlog.md) are cancelled, not deferred. The
> region data this feature was the reason to collect is itself being
> removed (§4.1 D1 reversal) — replaced by a location-permission gate on
> Global leaderboard visibility (§4.5 AC5).

**Sebagai** runner, **saya ingin** melihat posisi saya dibanding runner di
daerah saya, **supaya** kompetisinya terasa relevan dan achievable.

~~- AC1: User bisa filter leaderboard by kecamatan, kabupaten/kota, atau
  provinsi (hierarki administratif: kecamatan ada di dalam satu
  kabupaten/kota, kabupaten/kota ada di dalam satu provinsi).~~
~~- AC2: Jika data user di region tersebut terlalu sedikit (< threshold,
  misal 5 user), UI menampilkan pesan "belum cukup data" alih-alih
  leaderboard kosong yang terkesan buggy.~~
~~- AC3: Region ditentukan dari profil user, bukan dari GPS run per-run
  (mencegah leaderboard shopping dengan pindah-pindah region tiap run).~~

### 4.7 Season System
**Sebagai** runner, **saya ingin** kompetisi reset berkala, **supaya** saya
punya kesempatan baru untuk naik peringkat walau baru mulai lari.

- AC1: Rank (= posisi leaderboard) reset di awal season baru; lifetime
  points & level tidak reset.
- AC2: User bisa lihat sisa waktu season aktif.
- AC3: Hasil akhir season (final rank) tersimpan sebagai riwayat, bisa
  dilihat user setelah season berakhir.

### 4.8 Live Map During Tracking

**Sebagai** runner, **saya ingin** melihat posisi saya di peta secara
real-time saat lari, **supaya** saya tahu rute yang sudah saya tempuh
tanpa harus menebak dari angka jarak saja.

- AC1: Layar tracking menampilkan peta (MapKit) dengan posisi user saat
  ini, mengikuti update dari `CLLocationManager` yang sudah berjalan
  (tidak ada request lokasi terpisah).
- AC2: Polyline rute yang sedang terbentuk tergambar di peta secara
  real-time dari titik `gps_route` yang sudah di-capture, sesuai urutan
  waktu.
- AC3: Peta tidak menambah GPS request/polling baru — murni visualisasi
  dari data yang sudah dikumpulkan tracking pipeline yang ada (T0.7/T0.8).

### 4.9 Static Route Map (Run Summary & History)

**Sebagai** runner, **saya ingin** melihat peta rute lari saya setelah
selesai (di Run Summary maupun saat melihat riwayat), **supaya** saya
punya konteks visual dari lari saya, bukan cuma angka.

- AC1: Run Summary menampilkan render statis rute (`MKPolyline`) dari
  `gps_route` yang tersimpan di run tersebut.
- AC2: Run History (§4.18, promoted to Must-have 2026-09-13 — Round 7
  finding N7-4) menampilkan peta/thumbnail yang sama untuk tiap run
  lampau, dari data yang sudah tersimpan (tidak butuh GPS baru/re-tracking).
- AC3: Run tanpa titik GPS (jarak 0m) menampilkan state kosong yang jelas
  ("tidak ada rute untuk lari ini"), bukan peta kosong yang terlihat
  seperti bug.

### 4.10 Splits per Kilometer

**Sebagai** runner, **saya ingin** melihat pace saya per kilometer,
**supaya** saya tahu bagian mana dari lari saya yang cepat/lambat.

- AC1: Run Summary menampilkan daftar split per km (jarak genap 1km, 2km,
  dst.) dengan pace masing-masing, dihitung dari `gps_route` yang
  tersimpan run tersebut.
- AC2: Split terakhir yang kurang dari 1km penuh (sisa jarak) tetap
  ditampilkan sebagai split parsial, ditandai jelas — bukan disembunyikan
  atau dibulatkan seolah genap 1km.
- AC3: Total gabungan seluruh split (jarak) sama dengan jarak total run
  tersebut — tidak ada jarak yang hilang/dobel akibat pemotongan split.

### 4.11 Auto-Pause

> **Feature removed, 2026-09-22 (PM sign-off).** Auto-pause — automatically pausing a run after
> ~60s of no confirmed movement — is removed entirely from v1, not disabled. Product decision, no
> stated rationale beyond the sign-off itself. This AC and its task (T1.11,
> tasks/phase-1-core-loop-offline.md) are kept here, struck through, for history rather than
> deleted outright — see `security-review.md`/`code-quality-audit.md`'s convention for reversed
> decisions. **What is NOT removed**: the underlying `stationaryAnchor` drift-guard GPS filtering
> (ADR 0004, tech-spec.md §2.1b) stays — T1.11 only reused it as a user-facing pause trigger; the
> drift guard itself is core GPS noise filtering used elsewhere (distance calculation, CQ-2's fix)
> and was never in scope for removal.

~~**Sebagai** runner, **saya ingin** app otomatis pause kalau saya berhenti
bergerak (mis. nunggu lampu merah), **supaya** waktu/pace saya tidak
tercemar oleh waktu diam yang tidak sengaja.~~

~~- AC1: Kalau user diam melebihi ambang waktu tertentu saat run aktif, app
  otomatis masuk state Pause yang sama seperti Pause manual (§4.2 AC3) —
  bukan sekadar diam-diam menahan distance seperti mekanisme drift-guard
  yang sudah ada sebelumnya (tech-spec.md §2.1b). Deteksi ini adalah
  timer periodik yang mengecek waktu sejak gerakan nyata terakhir
  terkonfirmasi, BUKAN reaktif terhadap fix GPS berikutnya (tech-spec.md
  §2.1b, koreksi 2026-09-13/Round 7 finding B7-3 — device diam total
  nyaris tidak menerima fix GPS baru sama sekali, jadi trigger reaktif
  tidak akan pernah menyala pada kasus yang justru paling jelas).~~
~~- AC2: UI menampilkan indikator jelas bahwa pause ini terjadi otomatis
  (mis. label "Auto-paused"), berbeda dari Pause manual, supaya user
  tidak bingung kenapa run berhenti sendiri.~~
~~- AC3: User bisa Resume manual kapan saja setelah auto-pause, sama
  seperti resume dari pause manual — **auto-resume tidak ada di v1**
  (GPS berhenti sepenuhnya selama pause, sama seperti T1.2b, supaya
  tidak ada titik palsu di antara pause dan resume — lihat T2.9 —
  sehingga app tidak bisa mendeteksi sendiri kapan user mulai bergerak
  lagi tanpa GPS aktif; ini keterbatasan yang disengaja, bukan bug).~~
~~- AC4: Waktu yang dihabiskan dalam auto-pause dikecualikan dari
  `durationSeconds`/pace yang ditampilkan, persis seperti pause manual
  (tech-spec.md §2.4 — `duration_seconds` tetap client-asserted, tidak
  di-cross-check ulang terhadap rentang waktu `gps_route`).~~

### 4.12 Elevation Gain/Loss

**Sebagai** runner, **saya ingin** tahu berapa elevation gain/loss dari
lari saya, **supaya** saya paham kenapa pace saya terasa lebih berat di
rute berbukit.

- AC1: Run Summary menampilkan total elevation gain dan loss (meter),
  dihitung kumulatif dari field `elevation` per titik `gps_route` run
  tersebut.
- AC2: Noise elevasi kecil antar titik berurutan (GPS altitude yang
  notoriously noisy) tidak menghasilkan angka gain/loss yang jauh lebih
  besar dari elevasi rute sebenarnya — perlu smoothing/threshold minimal,
  bukan penjumlahan delta mentah tanpa filter.

### 4.13 Audio Cues

**Sebagai** runner, **saya ingin** dapat pengumuman suara jarak/pace
tanpa harus lihat layar, **supaya** saya tetap bisa fokus lari tanpa cek
HP terus-menerus.

- AC1: App mengumumkan (audio) jarak dan pace tiap kelipatan 1km yang
  tercapai saat run aktif.
- AC2: User bisa menonaktifkan audio cue dari pengaturan (tidak dipaksa
  aktif).
- AC3: Audio cue tidak terpicu dua kali untuk kilometer yang sama (mis.
  akibat GPS jitter di sekitar batas 1km).

### 4.14 Crash/Interrupt Recovery

**Sebagai** runner, **saya ingin** run saya tidak hilang kalau app crash
atau ke-force-quit di tengah lari, **supaya** saya tidak kehilangan
progres tanpa penjelasan.

- AC1: Saat app dibuka kembali dan ditemukan ada run lokal berstatus
  belum di-Stop (tidak ada `ended_at`) dari sesi sebelumnya, app
  menampilkan opsi eksplisit: lanjutkan (resume) run tersebut atau
  discard.
- AC2: Kalau user pilih discard, run tersebut (dan data GPS-nya) dihapus
  bersih dari penyimpanan lokal, tidak meninggalkan data yatim.
- AC3: Kalau user pilih resume, run melanjutkan tracking dari state
  terakhir yang tersimpan (distance/duration/gps_route), bukan mulai dari
  nol.

### 4.15 Refine Location Permission Flow

**Sebagai** runner, **saya ingin** paham konsekuensi kalau saya cuma
kasih izin lokasi "While Using" (bukan "Always"), **supaya** saya tidak
kaget kalau tracking berhenti saat app di-background.

- AC1: App membedakan penanganan untuk 3 state — "Always", "While Using",
  dan "Denied" — bukan cuma 2 (Always vs Denied) seperti sebelumnya.
- AC2: Kalau user memberi "While Using", app menjelaskan eksplisit (copy
  jelas, bukan cuma silent limitation) bahwa background tracking tidak
  akan berjalan kalau app di-background/layar mati, dan run bisa terhenti
  di tengah jalan.
- AC3: User bisa upgrade izin ke "Always" kapan saja dari dalam app (deep
  link ke Settings), tanpa harus uninstall/reinstall.

### 4.16 Streak Reminder Notification

**Sebagai** runner, **saya ingin** diingatkan kalau saya belum lari hari
ini dan streak saya berisiko putus, **supaya** saya terdorong lari
sebelum hari berakhir.

- AC1: App meminta izin notifikasi di titik yang masuk akal dalam
  onboarding/pengalaman app (bukan langsung di app pertama dibuka tanpa
  konteks).
- AC2: Kalau user belum menyelesaikan run hari ini menjelang malam (waktu
  lokal device) dan punya streak aktif (≥1 hari) yang berisiko putus, app
  mengirim local notification (bukan push server) mengingatkan.
- AC3: Notification tidak terkirim kalau user sudah lari hari ini, atau
  kalau user menonaktifkan izin notifikasi.

### 4.17 Account Deletion (Fase 2)

**Sebagai** pengguna, **saya ingin** bisa menghapus akun saya sepenuhnya
dari dalam app, **supaya** saya punya kontrol penuh atas data saya (App
Store Guideline 5.1.1(v)).

- AC1: User bisa memulai proses penghapusan akun dari dalam app (bukan
  cuma lewat email/web form eksternal), tanpa perlu menghubungi support.
- AC2: Konfirmasi eksplisit diminta sebelum penghapusan final dieksekusi
  (mencegah penghapusan tidak sengaja).
- AC3: Penghapusan akun menghapus/anonymize data personal user (identitas,
  profil) sesuai kebijakan privasi; data agregat non-personal (mis.
  kontribusi ke leaderboard historis) boleh tetap ada sesuai batasan
  privasi yang didokumentasikan.
- AC4: Ini adalah blocker rilis App Store (wajib ada sebelum submit,
  bukan opsional) — lihat pre-launch-checklist.md.

### 4.18 Run History

**Promoted from Should to Must-have 2026-09-13 (Round 7 finding N7-4)** —
§4.9 AC2 (static route map) explicitly requires this screen to exist as
the surface it renders on; a Must-have AC cannot correctly depend on a
cuttable Should-have, so this screen is promoted rather than leaving that
dependency silently unresolved.

**Sebagai** runner, **saya ingin** melihat daftar lari saya sebelumnya,
**supaya** saya bisa lihat progres dari waktu ke waktu, bukan cuma run
yang baru selesai.

- AC1: Semua run lokal muncul di daftar, urut dari yang paling baru.
- AC2: Nilai yang ditampilkan (tanggal, jarak, pace, poin) sama persis
  dengan yang tersimpan di Core Data untuk tiap run.

### 4.19 Club War (Fase 4, added 2026-09-23 — NOT v1/Must-have)

**Status: confirmed to build** (PM decision, 2026-09-23) — reversed from "nice to have v2+"/Non-goal
(§5). This section exists so the feature has a real spec instead of only a backlog stub (T4.2), per
this repo's convention that Fase-4 items get full detail once genuinely decided, not before.

**Decided:**
- Max **3 clubs per Club War**.
- **Self-serve**: a Club War is started by a Premium Club's owner/admin, not by Laju's team —
  distinct from the event-scale permission rule (ADR-0014), since a Club War's reach is bounded
  to the clubs actually entered, never the whole user base.

**NOT decided — genuinely open, flagged rather than invented:**
- **Mechanics** — how a match is scored (e.g. aggregate distance/points across members over the war
  period? head-to-head per pair among the ≤3 clubs?).
- **Win condition** — what determines a winner, and what a winner/loser actually gets.
- **Duration** — how long one Club War runs. Note: this is separate from the *reset cadence*
  question resolved in §4.20 below (how often the **Club War Record** — the running win/loss
  history — resets), which is decided: every 60 days, **starting Season 2** (T4.18). An individual
  Club War's own duration is not decided.

A task cannot be scoped precisely from this section alone — see tasks/phase-4-backlog.md's proposed
T4.18+ breakdown for what's blocked on these still-open points.

### 4.20 Club Global Leaderboard (Fase 4, added 2026-09-23 — NOT v1/Must-have)

**Status: confirmed to build** (PM decision, 2026-09-23). Two independent sections, same
"precompute, never derive live on read" pattern as the existing Global leaderboard (ADR-0013) — two
separate precompute jobs, no combined score between them.

- **Section 1 — "Club Aktif"**: ranked by **Participation Rate** (% of a club's members who ran in
  the period). **Reset cadence: every 60 days, starting Season 2** (PM decision, 2026-09-23 —
  reverses an earlier design conversation that specifically chose a *rolling* 30-day window instead
  of a periodic reset, because a hard reset undermines the "is this club alive right now" purpose a
  rolling window gives it; the PM was presented that tradeoff directly and chose the 60-day reset
  anyway, so this is a deliberate override, not an oversight). Follows the User Season boundary
  (below) — during Season 1 there is no 60-day cadence to align to yet, since Season 1 itself is 91
  days; this section's own reset timing during Season 1 is not yet specified and is part of T4.18/
  T4.17's implementation scoping, not decided here. **Minimum 10 members to qualify** — below that,
  a "Belum Cukup Data" state, mirroring the cancelled Local Leaderboard's `insufficient_data` pattern
  (§4.6, historical reference only; the mechanism itself was removed with that cancellation and
  would need to be rebuilt here, not reused directly).
- **Section 2 — "Club War Record"**: ranked by win/loss record from Club War (§4.19) matches only.
  **Reset cadence: every 60 days, starting Season 2** (PM decision, 2026-09-23, no prior conflicting
  design — this one was always meant to align with a periodic reset, matching the Season pattern).
  Same Season-1 caveat as Section 1 above — the 60-day cadence has nothing to align to until Season 2
  begins. A club that has never fought a Club War is **unranked here, not zero** — absent from the
  list entirely.

**User Season reset cadence — T4.18 DECIDED 2026-09-23, NOT YET IMPLEMENTED:**

> **Season 1: 91 days (unchanged). Season 2 and onward: 60 days.**

The PM confirmed changing the User Season length to 60 days, but explicitly **not retroactively**:
the **currently live, currently active** Season row (`Season 1 — 2026`, 2026-09-01 → 2026-11-30, 91
days, seeded by `20260917211241_seed_initial_season.sql`) **finishes on its original schedule,
unmodified** — it is not cut short. The cadence change applies **forward-only**, starting with
Season 2. Reasoning (PM, 2026-09-23): cutting Season 1 short mid-run would damage the trust of users
who already invested effort under a 91-day expectation set at the start; a forward-only change costs
nothing users have already been promised. tech-spec.md §2.5's documented quarterly (~91-day) cadence
is therefore correct **for Season 1 specifically**, not the general rule going forward — see that
section's own T4.18 note for the Season League point-band calibration consequence this has.

**Still not done — implementation, not documentation, is next:** neither the live season row nor any
season-length constant has been touched by this decision. That is deliberately left as a separate,
scoped task (tasks/phase-4-backlog.md T4.18) — this docs pass only records *what* was decided, not
*how* it gets built (e.g. how `advance_seasons`/`transition_season` should know Season 1 is 91 days
but every season after it is 60).

### 4.21 Laju Branded Events (Fase 4, added 2026-09-23, **concept replaced 2026-09-23** — NOT v1/Must-have)

> **Concept replaced 2026-09-23 (PM decision) — not a refinement of the section below, a different
> concept entirely.** The "EO Managed Event" scoping (same-day real-scoping pass, struck through
> below) got the ownership model right (Laju-exclusive, no dashboard — ADR-0014 still applies) but
> never answered what an "event" technically *is*, which blocked real scoping. That question is
> answered now. Everything struck through below is kept as a historical record of the prior pass,
> per this repo's convention for reversed/replaced decisions — it is not the current spec.

**Decided (final, from product explanation — Senior Tech Lead framing, 2026-09-23):**
- **Only Laju's own team can create an Event.** No self-serve, ever, at any tier — an EO/brand never
  holds any dashboard access, never authenticates into Laju's system. This is ADR-0014's general
  "whole-user-base reach is Laju-exclusive" rule, applied concretely here, not an exception to it.
- **Two Event types:**
  1. **Sponsored** — a brand partners on the Event (e.g. *"Run with Nike, dapatkan sepatu Nike"* —
     sponsored by Nike).
  2. **Announcement-only** — no reward attached (e.g. *"Run With Laju at Yogyakarta"*).
- **Sponsored registration happens entirely off-platform.** Tapping a sponsored Event redirects to
  the sponsor's own external website. Laju does **not** run registration or handle reward
  distribution for sponsored Events — that is the sponsor's own responsibility, on their own
  platform, outside Laju's system.
- **Winner determination is manual, not automated.** Laju staff cross-check participants' run data
  already present in Laju's system (distance, pace, route, etc. for the relevant window) and tell
  the sponsor who won. **No automated payout or reward-distribution mechanism exists or is planned**
  — this is a human process end to end, not a feature to build.
- **Events are available to every user, unfiltered by region.** Region was removed from the system
  entirely in Task B (§4.1 D1 reversal; database-api-spec.md). Events must not reintroduce any
  region requirement, collection, or filter — not even implicitly (e.g. no "only show Events near
  the user" logic that would need a location/region signal).
- **UI**: a card feed in the **Social tab → Events sub-tab**. Large full-width image card, text
  overlay showing participant count (*"Join X Runners"*), tap opens a detail view that redirects
  externally for sponsored Events. Reference: a confirmed mockup/screenshot exists for this pattern
  (not attached to this document — described here from that reference, not re-derived). See
  screen-inventory.md §4 for why this isn't wireframed yet (Fase 4, explicitly out of scope for now,
  per that document's own stated boundary).

**Rough data model** (for the eventual Task B/C scoping pass — not built, no migration exists yet):

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `title` | text | e.g. "Run with Nike" |
| `image_url` | text | full-width card image |
| `description` | text | |
| `type` | `sponsored` \| `announcement` | determines whether the sponsor/redirect fields apply |
| `external_url` | text, nullable | required for `sponsored` (registration + reward, sponsor-owned); `null` for `announcement` |
| `sponsor_name` | text, nullable | `sponsored` only, e.g. "Nike" |
| `starts_at` / `ends_at` | timestamptz | |
| `is_active` | boolean | Laju staff toggles; inactive Events don't appear in the feed |

No region field anywhere in this model — deliberate, per the "available to every user" decision above.

**Acceptance criteria:**
- AC1: An Event is exactly one of two types — `sponsored` or `announcement` — and the type
  determines whether a sponsor name and external redirect are shown.
- AC2: Tapping a `sponsored` Event opens `external_url` externally (browser/webview). Laju performs
  no registration or reward logic of its own for it.
- AC3: No automated reward distribution exists anywhere in the system for Events — winner
  determination and notifying the sponsor is a manual, off-app Laju-staff process.
- AC4: Every user sees every active Event in the feed. No region filter, and no other eligibility
  gate of any kind.
- AC5: Only Laju staff can create/edit/activate/deactivate an Event, through an internal-only
  mechanism (recommended: an admin CLI script, same family as `backend/scripts/season.ts` — no
  dashboard UI, ever, per ADR-0014).

**MoSCoW**: Fase 4. **Must**: internal-only creation, no self-serve dashboard ever — this is locked,
not left open to task-scoping. **Should**: the exact creation mechanism (CLI script is recommended,
not yet the final word on implementation).

---

~~**Status: reframed, real scoping done 2026-09-23** (real scoping, per this session's own work — still
Fase 4, not scheduled, not built). Was "B2B dashboard for event organizer" (T4.9); reframed to a
managed service by ADR-0014 (event-scale reach is Laju-exclusive, no self-serve at any tier) — see
lean-canvas.md §2/§6 for the business-model side of this. This section is the product/technical side:
what "Laju's team creates and manages events on an EO client's behalf" concretely means.

**Decided:**
- No dashboard, no EO-facing UI of any kind. An EO client never authenticates into Laju's system.
- Laju's own team is the operator — every action for an EO's event is performed by Laju staff.
- Revenue: per-event service fee (lean-canvas.md §6). Exact price not decided.

**Recommended minimal technical shape — a proposal for PM confirmation, not yet decided:**
Given there is no self-serve surface at all, the lowest-risk starting shape is an **admin CLI script**
in the same family as the existing `backend/scripts/season.ts` (T3.6's admin-triggered path) —
Laju staff run a script against the real backend to set up and tear down whatever an "event" turns
out to be, rather than building any dashboard UI for a feature nobody outside Laju ever sees. This
mirrors an established pattern already in this codebase (`backend/scripts/resolve-flagged-run.ts` is
the other example) rather than inventing a new one. **This avoids building UI work for a feature with
zero self-serve surface**, which would be spending Fase-4 effort on exactly the kind of speculative
work `tasks/phase-4-backlog.md`'s own top-of-file rule warns against.

**NOT decided — genuinely open, needs the PM before this can be scoped precisely:**
- **What is an "event," technically?** Candidates, none chosen: (a) a time-boxed leaderboard scope
  layered on top of the existing Global leaderboard/precompute pattern (ADR-0013) — participants
  see a separate, bounded-duration ranking; (b) something entirely outside the point/leaderboard
  system, e.g. a one-off data export of run data Laju already has for participants who opted in;
  (c) something else not yet named. The shape of the actual implementation work depends entirely on
  this answer — it is not a detail to fill in later, it is the scoping question.
- **Who counts as a "participant"?** Does an EO's event need its own signup/registration flow inside
  the app, or does it reuse the existing user base filtered by some criterion (region — removed
  entirely per §4.1's D1 reversal, so not that; club membership; a manual list Laju staff maintain)?
- **Does this need real-time-ish data during the event**, or is a manual precompute run (Laju staff
  triggers it, same pattern as `rebuild_global_leaderboard`) sufficient for an event's timescale
  (hours to a few days, presumably — not confirmed)?

Not scoped into a real task (no T4.x DoD written) because the "what is an event" question is not a
detail — until it's answered, any task breakdown here would be guessing at the actual work.~~

### 4.22 Apple Watch Companion (Fase 4, added 2026-09-23 — NOT v1/Must-have)

**Status: real scoping done 2026-09-23** (still Fase 4, not scheduled, not built). T4.14 in
tasks/phase-4-backlog.md, Apple Watch phase specifically — Garmin/Huawei are separate future scoping
passes per that task's own note, not covered here.

**Decided:**
- Apple Watch first, before Garmin/Huawei (2026-09-23, PM decision) — fits the existing native stack
  directly (ADR-0001: Swift/SwiftUI; WatchOS apps are Swift too), no new language/toolchain.
- Separate target + WatchConnectivity, per the original 2026-09-12 scope note.

**Recommended minimal shape — a proposal for PM confirmation, not yet decided:** the Watch app
**mirrors an in-progress run already being tracked by the phone**, it does **not** track GPS
independently on the watch. Concretely: phone remains the single source of truth for the run (start/
stop, GPS ingestion, the anti-drift/anti-cheat pipeline — ADR-0003's direct-`CLLocationManager`
choice and ADR-0004's stationary-anchor filter, §4.2's AC1-3), and `WatchConnectivity` relays
already-computed stats (distance, pace, elapsed time) to the watch face for glanceable display,
plus relays a pause/stop tap back to the phone. **Reasoning:** standalone GPS tracking on the watch
would mean building and maintaining a *second* implementation of the entire anti-drift/anti-cheat
pipeline (ADR-0004, ADR-0008) on a platform this codebase has never targeted — a large, currently
unjustified scope increase for a "companion" feature. Mirroring is the shape every major running app
ships first (Watch as a remote display/control, not a second tracker) before ever adding phone-free
tracking as a later, explicitly separate feature.

**NOT decided — genuinely open, needs the PM before this can be scoped precisely:**
- **Phone-free tracking** (run with just the watch, no phone nearby) — explicitly out of the
  recommended minimal shape above, but is it wanted at all, even as a later phase? If yes, that is a
  substantially larger, separate task (the anti-drift pipeline reimplementation this section
  recommends avoiding for v1 of the companion) — flagged so it isn't silently assumed either way.
- **What exactly shows on the watch face**: live stats only (distance/pace/time), or also start/
  pause/stop controls, or a full Watch-native complication/Live-Activity-style always-visible view
  (this would also depend on T4.13's Live Activities work, priority-ordered but not yet built)?
- **Does the watch need its own location permission prompt**, or does it purely ride on the phone's
  already-granted permission via the paired-device relationship? Not researched — genuinely unknown
  without checking Apple's current WatchConnectivity/location-sharing documentation.

Not scoped into a real task (no T4.x DoD written) because "does the watch ever track independently"
is a scope-defining fork, same category as T4.21's "what is an event" — answering it changes the
size of the work by an order of magnitude, so it is not a detail to fill in during implementation.

## 5. Non-Goals (v1) — dan alasannya

| Non-goal | Alasan |
|---|---|
| ~~Circle~~ **Club** / Matchmaking | mvp-report eksplisit: loop individual harus tervalidasi dulu sebelum lapisan sosial ditambahkan — supaya tidak menutupi apakah core loop benar-benar rewarding tanpa teman. **Renamed "Circle" → "Club" 2026-09-23** (PM decision) — the DB schema already used `club_id` (database-api-spec.md §1), so this brings docs into alignment with existing code, not the reverse. **Club War specifically is now CONFIRMED TO BUILD** (2026-09-23, reversed from "nice to have v2+"/Non-goal) — see the new §4.19 below. Still not v1/Fase 4-scheduled; only the eventual shape is now decided, not the timing. Matchmaking (circle-to-circle) stays a Non-goal, undecided shape. |
| Social Feed (post pencapaian, like, comment) | Sama alasannya dengan Club di atas — draft di user-flow.md (belum direkonsiliasi ke dokumen manapun sampai 2026-09-12) menggabungkan Social Feed dengan Circle/Club-feed; keduanya sama-sama lapisan sosial yang sengaja ditunda sampai core loop individual tervalidasi. Rekomendasi: Fase 4 backlog (T4.15), bukan Fase 3 — lihat tasks/phase-4-backlog.md. |
| Leaderboard Lokal (kecamatan / kabupaten-kota / provinsi) | ~~**Ditunda ke v1.1 / Fase 4 (2026-09-21) — bukan dibatalkan.** Butuh kepadatan user tinggi supaya berguna: dengan user awal sedikit, satu kecamatan hanya berisi beberapa orang dan leaderboard-nya kosong/tidak kompetitif. Global-only untuk MVP terasa "lokal" secara natural saat user masih sedikit. Kerja yang sudah ada (hierarki wilayah, skema `LEADERBOARD_SCOPE`, task T3.2–T3.5) disimpan sebagai referensi, ditandai deferred — lihat §4.6 dan tasks/phase-4-backlog.md.~~ **DIBATALKAN PERMANEN 2026-09-22 (PM sign-off)** — bukan ditunda. Alasan: scope terlalu luas untuk logic leaderboard yang dibutuhkan. Hierarki wilayah di `User` dan nilai `scope_type` regional di `LEADERBOARD_SCOPE` justru **dihapus** dari skema, bukan disimpan sebagai referensi (Task B). Lihat §4.6 dan tasks/phase-4-backlog.md. |
| ~~Monetisasi (Premium, B2B dashboard)~~ | ~~Fokus v1 = retention/validasi core loop, bukan revenue. Monetisasi baru relevan setelah ada basis user aktif.~~ **Premium pricing DECIDED 2026-09-23** (PM decision): $7.99/bulan (harga referensi USD), harga regional lewat App Store Connect's price-tier localization sendiri — bukan sistem konversi kurs custom, ini sebagian besar tugas konfigurasi store, bukan engineering. Ini bukan berarti Premium sudah dijadwalkan untuk dibangun v1/Fase 4 — cuma bentuk harganya yang sudah tidak terbuka lagi. B2B dashboard (EO) tetap Non-goal v1; modelnya sendiri direframe 2026-09-23, lihat lean-canvas.md §2/§6. |
| Android support | v1 launches iOS-exclusive, native Swift/SwiftUI — Android ditunda tanpa timeline pasti (keputusan platform, bukan technical debt). Lihat tech-spec.md §1. |
| ~~Route map visualization~~ | **Dicabut sebagai Non-goal (2026-09-12)** — dipecah jadi Live map (§4.8) dan Static map (§4.9), keduanya Must-have Fase 1. Alasan awal (biaya Maps API) sudah tidak berlaku setelah keputusan pakai MapKit native (tech-spec.md §1, lean-canvas.md §7); alasan "bukan bagian dari core loop" tetap benar secara literal, tapi diputuskan tetap masuk sebagai fitur engagement pendukung core loop, bukan lagi dianggap di luar prioritas. |
| Government / sports-brand partnership tooling | Tidak ada demand tervalidasi; secondary user, bukan primary. |
| Real-time push notification infrastruktur kompleks (mis. live leaderboard push) | Precompute interval 15 menit cukup untuk v1; real-time push adalah optimisasi, bukan requirement inti. Catatan: streak reminder (§4.16) TIDAK termasuk di sini — itu local notification on-device, bukan infrastruktur push server. |
