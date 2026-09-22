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
| Leaderboard — Local (kota)                                                                  | **Won't (v1)** | **Deferred to v1.1 / Fase 4 (decided 2026-09-21), not cancelled** — needs high user density to be useful; see §4.6 and Non-goals. Tasks T3.2–T3.5 preserved in tasks/phase-4-backlog.md                                 |
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
| Circle / Clan / Group                                                                       | **Won't (v1)** | Explicit scope cut, see Non-goals                                                                                                                                                                                        |
| Circle war                                                                                  | **Won't (v1)** | Depends on Circle                                                                                                                                                                                                        |
| Matchmaking (circle-to-circle)                                                              | **Won't (v1)** | Depends on Circle                                                                                                                                                                                                        |
| Social Feed (post run achievements, likes, comments)                                        | **Won't (v1)** | Only existed as an unreconciled draft in user-flow.md — see Non-goals; recommendation: Fase 4 backlog (T4.15), not Fase 3 — same "prove the loop alone first" rationale as Circle                                        |
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

## 5. Non-Goals (v1) — dan alasannya

| Non-goal | Alasan |
|---|---|
| Circle / Clan / Club War / Matchmaking | mvp-report eksplisit: loop individual harus tervalidasi dulu sebelum lapisan sosial ditambahkan — supaya tidak menutupi apakah core loop benar-benar rewarding tanpa teman. |
| Social Feed (post pencapaian, like, comment) | Sama alasannya dengan Circle di atas — draft di user-flow.md (belum direkonsiliasi ke dokumen manapun sampai 2026-09-12) menggabungkan Social Feed dengan Circle-feed; keduanya sama-sama lapisan sosial yang sengaja ditunda sampai core loop individual tervalidasi. Rekomendasi: Fase 4 backlog (T4.15), bukan Fase 3 — lihat tasks/phase-4-backlog.md. |
| Leaderboard Lokal (kecamatan / kabupaten-kota / provinsi) | ~~**Ditunda ke v1.1 / Fase 4 (2026-09-21) — bukan dibatalkan.** Butuh kepadatan user tinggi supaya berguna: dengan user awal sedikit, satu kecamatan hanya berisi beberapa orang dan leaderboard-nya kosong/tidak kompetitif. Global-only untuk MVP terasa "lokal" secara natural saat user masih sedikit. Kerja yang sudah ada (hierarki wilayah, skema `LEADERBOARD_SCOPE`, task T3.2–T3.5) disimpan sebagai referensi, ditandai deferred — lihat §4.6 dan tasks/phase-4-backlog.md.~~ **DIBATALKAN PERMANEN 2026-09-22 (PM sign-off)** — bukan ditunda. Alasan: scope terlalu luas untuk logic leaderboard yang dibutuhkan. Hierarki wilayah di `User` dan nilai `scope_type` regional di `LEADERBOARD_SCOPE` justru **dihapus** dari skema, bukan disimpan sebagai referensi (Task B). Lihat §4.6 dan tasks/phase-4-backlog.md. |
| Monetisasi (Premium, B2B dashboard) | Fokus v1 = retention/validasi core loop, bukan revenue. Monetisasi baru relevan setelah ada basis user aktif. |
| Android support | v1 launches iOS-exclusive, native Swift/SwiftUI — Android ditunda tanpa timeline pasti (keputusan platform, bukan technical debt). Lihat tech-spec.md §1. |
| ~~Route map visualization~~ | **Dicabut sebagai Non-goal (2026-09-12)** — dipecah jadi Live map (§4.8) dan Static map (§4.9), keduanya Must-have Fase 1. Alasan awal (biaya Maps API) sudah tidak berlaku setelah keputusan pakai MapKit native (tech-spec.md §1, lean-canvas.md §7); alasan "bukan bagian dari core loop" tetap benar secara literal, tapi diputuskan tetap masuk sebagai fitur engagement pendukung core loop, bukan lagi dianggap di luar prioritas. |
| Government / sports-brand partnership tooling | Tidak ada demand tervalidasi; secondary user, bukan primary. |
| Real-time push notification infrastruktur kompleks (mis. live leaderboard push) | Precompute interval 15 menit cukup untuk v1; real-time push adalah optimisasi, bukan requirement inti. Catatan: streak reminder (§4.16) TIDAK termasuk di sini — itu local notification on-device, bukan infrastruktur push server. |
