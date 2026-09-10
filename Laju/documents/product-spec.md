# Laju App — Product Spec (v1)

Source of truth: [lean-canvas.md](./lean-canvas.md), [mvp-report.md](./mvp-report.md)

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

| Feature | Priority | v1 scope note |
|---|---|---|
| Account / profile (needed to persist points, identity across devices, leaderboard identity) | **Must** | Minimal: email/password or OAuth, username, region |
| GPS run tracking (background) | **Must** | Core action; must survive app backgrounding |
| Point calculation (formula + anti-cheat) | **Must** | Server is source of truth; client shows optimistic estimate |
| Level / Rank progression | **Must** | Derived from cumulative points |
| Leaderboard — Global | **Must** | Precomputed, season-scoped |
| Leaderboard — Local (kecamatan/kabupaten-kota/provinsi) | **Must** | Requires user region on profile |
| Season system (reset cycle) | **Must** | Drives re-engagement; resets rank, not lifetime stats |
| Run history / stats view | Should | List of past runs, distance/pace/points |
| Streak indicator | Should | Visual only in v1; feeds into point bonus already in formula |
| Offline sync status indicator | Should | User-facing trust signal for offline-first behavior |
| Route map visualization | Could | Not required for core loop; adds Maps SDK cost |
| Seasonal pass / Premium stats / Exclusive badge / Premium profile | Could | Monetization, post-core-loop validation |
| B2B dashboard (club, EO) | Could | Depends on club entity, which is Won't for v1 |
| Circle / Clan / Group | **Won't (v1)** | Explicit scope cut, see Non-goals |
| Circle war | **Won't (v1)** | Depends on Circle |
| Matchmaking (circle-to-circle) | **Won't (v1)** | Depends on Circle |
| Government / sports-brand partnership tooling | **Won't (v1)** | No product surface needed until B2B validated |
| Android support | **Won't (v1)** | v1 launches iOS-exclusive; ditunda tanpa timeline pasti — lihat tech-spec.md §1 |

## 4. User Stories & Acceptance Criteria (Must-have v1)

### 4.1 Account & Profile
**Sebagai** calon pengguna, **saya ingin** membuat akun dan mengisi region
saya, **supaya** progres saya tersimpan dan saya muncul di leaderboard lokal
yang benar.

- AC1: User bisa daftar dengan email/password (atau OAuth) dalam ≤3 langkah.
- AC2: User wajib set region (minimal kecamatan + kabupaten/kota) sebelum
  run pertama bisa disubmit ke server.
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
  lihat aturan anti-cheat di [tech-spec.md](./tech-spec.md).

### 4.4 Level Progression
**Sebagai** runner, **saya ingin** melihat level saya naik seiring poin
bertambah, **supaya** saya punya tujuan jangka panjang selain satu run.

> **Catatan istilah:** "Rank" di dokumen ini SELALU berarti posisi user di
> leaderboard (`LEADERBOARD_ENTRY.rank` — lihat database-api-spec.md §1),
> season-scoped dan reset tiap season baru. "Level" adalah entitas
> terpisah: progres lifetime dari total poin kumulatif, tidak pernah
> reset. Tidak ada tier/rank persisten tambahan di v1 — lihat §4.5/§4.6
> untuk acceptance criteria Rank (leaderboard).

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
  lihat [architecture.md](./architecture.md)).
- AC3: Leaderboard di-scope per season aktif.

### 4.6 Leaderboard — Local
**Sebagai** runner, **saya ingin** melihat posisi saya dibanding runner di
daerah saya, **supaya** kompetisinya terasa relevan dan achievable.

- AC1: User bisa filter leaderboard by kecamatan, kabupaten/kota, atau
  provinsi (hierarki administratif: kecamatan ada di dalam satu
  kabupaten/kota, kabupaten/kota ada di dalam satu provinsi).
- AC2: Jika data user di region tersebut terlalu sedikit (< threshold,
  misal 5 user), UI menampilkan pesan "belum cukup data" alih-alih
  leaderboard kosong yang terkesan buggy.
- AC3: Region ditentukan dari profil user, bukan dari GPS run per-run
  (mencegah leaderboard shopping dengan pindah-pindah region tiap run).

### 4.7 Season System
**Sebagai** runner, **saya ingin** kompetisi reset berkala, **supaya** saya
punya kesempatan baru untuk naik peringkat walau baru mulai lari.

- AC1: Rank (= posisi leaderboard) reset di awal season baru; lifetime
  points & level tidak reset.
- AC2: User bisa lihat sisa waktu season aktif.
- AC3: Hasil akhir season (final rank) tersimpan sebagai riwayat, bisa
  dilihat user setelah season berakhir.

## 5. Non-Goals (v1) — dan alasannya

| Non-goal | Alasan |
|---|---|
| Circle / Clan / Club War / Matchmaking | mvp-report eksplisit: loop individual harus tervalidasi dulu sebelum lapisan sosial ditambahkan — supaya tidak menutupi apakah core loop benar-benar rewarding tanpa teman. |
| Monetisasi (Premium, B2B dashboard) | Fokus v1 = retention/validasi core loop, bukan revenue. Monetisasi baru relevan setelah ada basis user aktif. |
| Android support | v1 launches iOS-exclusive, native Swift/SwiftUI — Android ditunda tanpa timeline pasti (keputusan platform, bukan technical debt). Lihat tech-spec.md §1. |
| Route map visualization | Bukan bagian dari core loop (poin/level/leaderboard); menambah biaya Maps API tanpa validasi kebutuhan dulu. |
| Government / sports-brand partnership tooling | Tidak ada demand tervalidasi; secondary user, bukan primary. |
| Real-time push notification infrastruktur kompleks (mis. live leaderboard push) | Precompute interval 15 menit cukup untuk v1; real-time push adalah optimisasi, bukan requirement inti. |
