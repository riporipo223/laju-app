# Laju App — Tech Spec (v1)

Depends on: [product-spec.md](./product-spec.md)

## 1. Stack Decision Table

| Layer | Choice | Alasan |
|---|---|---|
| Mobile client | Swift + SwiftUI, native (min. iOS 16) | **Keputusan pivot (locked)** — Laju launch iOS-exclusive. Native menghindari overhead bridge/JS thread untuk background GPS yang sensitif battery & reliability, dan iOS 16 cukup luas jangkauannya sekaligus mendukung background location capability yang dibutuhkan. Android ditunda tanpa timeline — lihat Future Development di lean-canvas.md/mvp-report.md. |
| Architecture pattern (mobile) | MVVM (SwiftUI Views → ViewModels → Model/services) | Idiomatik untuk SwiftUI, dan secara konsep dekat dengan pembagian Presentation/State/Data-Sync layer yang sudah didesain di architecture.md §3 — memudahkan porting logic yang sudah dirancang, bukan desain ulang dari nol. |
| GPS tracking | `CLLocationManager` (native, langsung — bukan library pihak ketiga) | Keputusan pivot (locked) — menghapus dependency ke `react-native-background-geolocation` sekaligus menghapus lapisan risiko third-party yang sebelumnya jadi alasan T0.9 sebagai gate. `allowsBackgroundLocationUpdates` + `Info.plist` background modes (`location`) dipakai untuk background tracking; `desiredAccuracy`/`distanceFilter` diatur manual untuk battery (lihat §4). |
| Local/offline storage (mobile) | Core Data | Keputusan pivot (locked) — dipilih dibanding SwiftData karena SwiftData masih relatif baru untuk kompleksitas sync/reconciliation yang sudah didesain (§2.4.1, §3): banyak field mirror server (`server_run_id`, `server_status`, `flag_confidence`, dst) + `sync_meta` terpisah. Core Data lebih matang untuk pola ini. Representasi: Entity (bukan tabel SQL) — lihat §3. |
| Client state management | SwiftUI native state (`@State`/`@Published`/`ObservableObject`) di layer ViewModel | Idiomatik MVVM SwiftUI — ViewModel meng-observe Core Data (via `NSFetchedResultsController`/`@FetchRequest`) untuk data lokal, dan meng-expose state hasil `URLSession` call untuk data dari server. Tidak butuh library pihak ketiga (Zustand/TanStack Query) untuk MVP. |
| Networking (mobile) | `URLSession` + `Codable` | Native, cukup untuk kebutuhan MVP (`POST`/`GET` JSON ke Next.js API routes) — tidak ada kebutuhan fitur lanjutan (interceptor kompleks, GraphQL, dsb) yang butuh library pihak ketiga. |
| Backend framework | Next.js (App Router, API routes) + TypeScript | **Rekomendasi**, bukan keputusan final — lihat catatan trade-off di bawah. Memanfaatkan familiarity existing (Next.js/TS) dan bisa dipakai juga untuk admin/B2B dashboard di masa depan. |
| Database | PostgreSQL (via Supabase) | **Rekomendasi**, bukan keputusan final — lihat catatan trade-off. Leaderboard butuh ranking query & aggregation per region (kecamatan/kabupaten-kota/provinsi) yang jauh lebih natural & efisien di relational DB dengan `GROUP BY`/window function dibanding NoSQL document store. |
| Auth | Supabase Auth (JWT) | Terintegrasi langsung dengan Postgres (Row Level Security opsional), menghindari sinkronisasi identitas dua sistem (Firebase Auth + Postgres user table terpisah). |
| Maps SDK (jika/ketika dipakai) | Mapbox | Free tier lebih generous dari Google Maps untuk volume request rendah-menengah; tidak dipakai di v1 core (lihat product-spec §5 Non-goals), disiapkan sebagai Open Question untuk Could-have "route map visualization". |
| Backend hosting | Vercel | Native untuk Next.js, familiar dari stack existing. |
| DB/Auth hosting | Supabase Cloud | Managed Postgres, mengurangi ops overhead dibanding self-host. |
| Background jobs (leaderboard precompute) | Vercel Cron (v1) → dedicated worker jika volume naik | Cukup untuk interval precompute 15 menit di skala awal; lihat architecture.md §4 untuk migration path. |
| Repo tooling | Xcode project (`.xcodeproj`/SPM) untuk `ios/`, npm/pnpm untuk `backend/`, dalam satu monorepo Git — lihat repo-coding-rules.md §1 untuk struktur & alasan | Client (Swift) dan server (TypeScript) sudah beda bahasa sepenuhnya — tidak ada shared-types package yang bisa dipakai literal di kedua sisi lagi (lihat §2.2b untuk strategi parity poin), jadi tidak butuh build orchestration lintas-bahasa (Turborepo/pnpm workspaces tidak relevan lagi untuk sisi mobile). |

### Trade-off note: Firebase vs Postgres/Supabase — untuk PM decide

Firebase (Firestore) familiar buat developer, tapi:
- Leaderboard lokal granular (per kecamatan/kabupaten-kota/provinsi, per
  season) butuh
  query semacam "top N per region, sorted by points, dengan tie-break" —
  ini native di SQL (`ORDER BY`, `PARTITION BY`, materialized view), tapi di
  Firestore butuh precompute manual + denormalisasi berlapis, lebih rawan
  bug & lebih mahal di read quota saat scale.
- Point ledger (immutable transaction log, lihat §2) natural sebagai tabel
  relational dengan foreign key ke User/Run/Season — enforceable di level
  DB. Di Firestore, integritas ini harus dijaga manual di application code.

Firebase tetap opsi valid kalau prioritas PM adalah kecepatan development
awal & familiarity di atas efisiensi query leaderboard jangka panjang.
**Rekomendasi: Postgres (Supabase)**, tapi ini keputusan dengan trade-off
besar — final call ada di PM.

## 2. Point System Algorithm

### 2.1 Variabel
- `distance_km` — jarak run (dari GPS, setelah dibersihkan dari noise)
- `avg_pace_sec_per_km` — rata-rata pace run
- `pace_consistency` — deviasi pace antar segmen run (semakin stabil,
  semakin tinggi skor konsistensi)
- `streak_days` — jumlah hari berturut-turut user run (untuk bonus)
- `season_id` — poin selalu tercatat dalam konteks season aktif

**Capture format (client → server):** `distance_km` dan
`avg_pace_sec_per_km` di atas dihitung dari `distance_meters`/
`duration_seconds` — dua field top-level yang dikirim client, dihitung
sama persis di device (estimasi optimistic) dan disimpan di server (nilai
otoritatif). GPS trail mentah dikirim terpisah sebagai `gps_route`: array
per-titik `{lat, lng, timestamp, elevation}` (bukan cuma `{lat, lng}` —
`timestamp` dan `elevation` wajib per titik, dibutuhkan anti-cheat §2.4
untuk hitung speed instan antar titik dan deteksi anomali elevasi).
`gps_route` **tidak** dipakai untuk kalkulasi poin dasar (§2.2) — itu
murni input untuk anti-cheat checks (§2.4), yang beroperasi per-segmen di
atas titik-titik ini.

### 2.2 Formula (v1, perlu divalidasi dengan data real — lihat lean-canvas)

```
pace_multiplier = f(avg_pace_sec_per_km)   // piecewise, lihat §2.3
base_points     = distance_km * pace_multiplier
streak_bonus    = min(streak_days, 7) * STREAK_BONUS_PER_DAY   // cap 7 hari
raw_points      = base_points + streak_bonus
final_points    = raw_points * trust_multiplier(user)          // lihat §2.4
```

`STREAK_BONUS_PER_DAY` adalah konstanta konfigurasi (bukan hardcode),
supaya bisa di-tuning tanpa deploy ulang app. **Nilai awal v1: 2 poin**
per hari streak (cap 7 hari → maksimum bonus 14 poin/run) — starting
point yang sama statusnya dengan tabel pace multiplier di §2.3: perlu
di-tuning pakai data run real, bukan angka final.

### 2.3 Pace multiplier (piecewise)

Tujuan: reward pace yang sehat & konsisten, tapi **tidak** memberi lebih
banyak poin untuk pace yang secara fisik tidak masuk akal (indikasi cheat,
bukan performa nyata).

Bracket **half-open** (`[batas_bawah, batas_atas)`) supaya tidak ada pace
yang match 2 baris sekaligus — pace tepat di batas atas masuk ke bracket
berikutnya, bukan bracket saat ini.

| Pace (min/km) | Multiplier | Catatan |
|---|---|---|
| < 3:00 | 0.5x | Lebih cepat dari elite sprint pace berkelanjutan — kemungkinan besar GPS noise/spoofing, tapi multiplier saja **tidak** memutuskan status run (validated/flagged/rejected) — itu murni fungsi `excluded_pct` di §2.4.1, dipisah sengaja supaya tidak ada 2 mekanisme flagging yang bersaing |
| [3:00, 4:00) | 1.2x | Elite-level, plausible untuk atlet terlatih |
| [4:00, 7:00) | 1.0x | Range normal, multiplier baseline |
| [7:00, 10:00) | 0.9x | Jalan cepat/lari santai |
| ≥ 10:00 | 0.7x | Tetap dapat poin (menghargai usaha), tapi lebih rendah |

**Kenapa `< 3:00` dapat 0.5x (bukan 0, dan bukan otomatis `flagged`):**
sebelumnya baris ini berbunyi "0 (run diflag)" — itu menyiratkan
mekanisme flagging kedua di luar `excluded_pct` (§2.4.1), yang
kontradiksi dengan prinsip "status run ditentukan HANYA oleh
`excluded_pct`, diputuskan HANYA di T2.12a" yang dipegang ketat di
seluruh §2.4. Pace rata-rata run yang sangat cepat biasanya sudah
kena-exclude oleh pace-cap check (§2.4, per-segmen >1km) dan berkontribusi
ke `excluded_pct` lewat jalur itu — multiplier di tabel ini cuma
mempengaruhi *besaran poin dari segmen yang lolos*, bukan status akhir
run. Nilai 0.5x (bukan 0) mencegah kasus run pendek ber-noise GPS yang
rata-ratanya kebetulan jatuh di bawah 3:00 tapi tidak cukup segmen
ke-exclude untuk kena `FLAG_THRESHOLD_PCT` — user tetap dapat sedikit
poin, bukan nol tiba-tiba tanpa penjelasan.

Angka pasti di atas (termasuk `STREAK_BONUS_PER_DAY`) adalah starting
point, bukan final — perlu di-tuning setelah ada data run real (lihat
development-plan.md Fase 4 backlog terkait monetisasi/tuning lanjutan;
tidak ada Open Question section terpisah di development-plan.md saat ini).

### 2.2b Cross-language point-formula parity (Swift client vs TypeScript server)

Sebelum pivot, `packages/shared-types/point-formula.ts` (T1.1) jadi satu
file literal yang dipakai mobile (RN/TS) **dan** backend (Next.js/TS) —
strategi ini menutup risiko divergensi otomatis lewat compiler/import yang
sama. Setelah pivot, client (Swift) dan server (TypeScript) tidak bisa lagi
share satu file source secara literal — strateginya berubah:

1. **Server tetap satu-satunya source of truth** untuk poin final (prinsip
   ini sudah ada sejak awal §2.4, tidak berubah) — estimasi client murni
   optimistic display, dilebur ulang oleh server saat sync (§3 step 4).
   Ini artinya divergensi formula client vs server **tidak pernah jadi bug
   data** (poin yang dibayar selalu dari server), hanya berisiko bikin UX
   estimasi awal terasa "salah tebak" kalau kedua sisi tidak selaras.
2. **Formula didefinisikan sekali secara tekstual** di dokumen ini (§2.2,
   §2.3) sebagai spec — bukan sebagai kode yang di-share.
3. **Parity dijaga lewat fixture file bersama** (bukan shared code):
   `point-formula.fixtures.json` — array test-vector `{input:
   {distance_km, avg_pace_sec_per_km, streak_days}, expected_points}` yang
   di-commit satu kali di repo (mis. `shared/point-formula.fixtures.json`
   di root monorepo — lihat repo-coding-rules.md §1) dan **dibaca oleh
   kedua sisi** saat test: unit test Swift (`XCTest`, T1.1) dan unit test
   TypeScript (`vitest`/`jest`, T2.6) sama-sama load file ini dan assert
   `calculatePoints(input) == expected_points` untuk tiap baris. Kalau
   salah satu sisi mengubah formula tanpa update fixture yang sama, test
   di sisi itu gagal — memberi sinyal cepat tanpa butuh compile-time
   sharing yang sudah tidak mungkin lintas bahasa.
4. Fixture di-update manual tiap kali §2.2/§2.3 berubah (mis. tuning
   `STREAK_BONUS_PER_DAY` pakai data real, per catatan di atas) — jadi
   satu PR yang mengubah tabel di dokumen ini idealnya juga menyertakan
   fixture baru, direview bareng.

### 2.4 Anti-cheat / Anomaly Detection

Prinsip: **server adalah source of truth** untuk poin final. Klien hanya
menampilkan estimasi optimistic (lihat §3 Offline-first).

| Check | Trigger | Aksi |
|---|---|---|
| Pace cap | Avg pace < 3:00/km untuk segmen >1km berturut-turut | Segmen tersebut di-exclude dari perhitungan poin |
| GPS speed jump | Kecepatan instan antar 2 titik GPS > 25 km/h sustained (>3 sample berturut) | Segmen di-exclude |
| Distance/duration sanity | Total distance tidak konsisten dengan durasi (mis. GPS loncat lokasi jauh dalam interval pendek — teleport) | Segmen di-exclude |
| Elevation anomaly | Perubahan elevasi tidak wajar dalam waktu singkat | Tambahan sinyal, bukan trigger tunggal — tidak meng-exclude segmen sendirian |
| Trust score | Kumulatif berapa kali user kena flag/reject dalam periode tertentu | Trust score turun → `trust_multiplier` < 1.0 → poin user berikutnya otomatis lebih rendah sampai trust pulih |

**Definisi "segmen":** interval antara 2 titik GPS berurutan (satu
point-pair) di `gps_route`. Setiap check di atas beroperasi per-segmen —
GPS speed jump & distance/duration sanity langsung bekerja di satu
point-pair, elevation anomaly di jendela waktu singkat yang dipetakan ke
point-pair terdekat.

**Metrik status — count-based, BUKAN berbasis jarak:**

```
excluded_pct = (jumlah segmen yang di-exclude oleh minimal satu check)
               / (total segmen dalam run) × 100
```

Bukan `excluded_distance_meters / distance_meters`. Alasan: tiap check
mendeteksi anomali per pasangan titik (point-pair), bukan per meter —
metrik berbasis segmen konsisten langsung dengan unit deteksinya, dan
tidak bias oleh panjang segmen yang bervariasi (adaptive distance filter
bikin sampling rate berubah-ubah, jadi satu segmen panjang secara jarak
tidak berarti lebih "parah" daripada beberapa segmen pendek berurutan).
`excluded_pct` inilah yang menentukan status akhir run — lihat §2.4.1.

#### 2.4.1 Resolution flow (state machine)

`RUN.status` (server, authoritative) punya 4 nilai. Ini menjawab
pertanyaan yang sebelumnya tidak terjawab: siapa/apa yang review run
`flagged`, dan apa efeknya ke poin & leaderboard selama masa review.

| Status | Kapan terjadi | Efek ke poin & leaderboard |
|---|---|---|
| `validated` | Tidak ada check trigger, ATAU total segmen ke-exclude < `FLAG_THRESHOLD_PCT` (default 10%) | Poin penuh (formula §2.2, dikurangi segmen exclude kalau ada) langsung ditulis ke `PointTransaction`, langsung ikut leaderboard precompute berikutnya |
| `flagged` | Total segmen ke-exclude antara `FLAG_THRESHOLD_PCT` (10%) dan `REJECT_THRESHOLD_PCT` (50%). Otomatis diberi `flag_confidence` — **LOW** kalau exclusion 10%–<25%, **HIGH** kalau 25%–<50% (lihat rationale di bawah) | Poin dari segmen valid saja ditulis ke `PointTransaction` (bukan 0, bukan full) — tapi run ini **DIKECUALIKAN dari leaderboard precompute** sampai resolved jadi `approved`. `resolved_at = null` |
| `approved` | **LOW confidence:** auto-resolve otomatis setelah `REVIEW_WINDOW_LOW` (default **48 jam**) tanpa manual override — dijalankan oleh job terjadwal `resolve-flagged-runs` (lihat di bawah). **HIGH confidence:** TIDAK PERNAH auto-resolve — wajib manual override lewat runbook; kalau tidak direview, run tetap `flagged` tanpa batas waktu. Manual override (kedua confidence) bisa menerima lebih awal. | Poin yang sudah tercatat sejak `flagged` mulai ikut leaderboard precompute berikutnya. `resolved_at` diisi |
| `rejected` | Total segmen ke-exclude ≥ `REJECT_THRESHOLD_PCT` (50%) → auto-reject **segera** (synchronous, sebelum `PointTransaction` ditulis sama sekali), ATAU manual override dari `flagged` (LOW atau HIGH) | Kasus immediate: tidak ada `PointTransaction` ditulis, `final_points_awarded = 0`. Kasus override dari `flagged` (sudah ada transaksi partial di ledger): ditulis `PointTransaction` baru type `adjustment` bernilai negatif untuk menetralkan — ledger tetap append-only, transaksi lama tidak dihapus/diubah (lihat §4 NFR). Trust_score user turun di kedua kasus. |

`FLAG_THRESHOLD_PCT`, `REJECT_THRESHOLD_PCT`, `FLAG_LOW_MAX_PCT` (default
25% — batas LOW/HIGH confidence di dalam band flagged), `REVIEW_WINDOW_LOW`
(default 48 jam) adalah konstanta konfigurasi, bukan hardcode — semuanya
dihitung terhadap `excluded_pct` count-based di atas (§2.4), bukan
berbasis jarak.

**Kenapa dipisah LOW/HIGH confidence, bukan satu window untuk semua:**
Exclusion 10-25% biasanya GPS noise biasa (sinyal lemah di urban canyon,
drift stasioner) — bukti cheat lemah, risiko false-positive tinggi kalau
ditahan lama. Exclusion 25-50% adalah bukti jauh lebih kuat (pola
eksklusi besar & konsisten) — lebih mungkin cheat sungguhan, jadi tidak
boleh auto-lolos tanpa mata manusia, berapapun lama menunggu.

**Kenapa 48 jam (bukan 24 atau 72) untuk `REVIEW_WINDOW_LOW`:** 48 jam
memberi operator siklus kerja penuh (termasuk akhir pekan pendek) untuk
spot-check via runbook, sambil tidak menahan poin user yang kemungkinan
besar jujur (LOW confidence) terlalu lama — menahan lebih dari 2 hari
langsung merusak "instant reward" yang jadi inti hipotesis produk
(product-spec.md §1, mvp-report.md §3). 24 jam terlalu ketat untuk
operator manual tanpa admin UI (risiko banyak run keburu expire di luar
jam kerja); 72 jam menahan user jujur lebih lama dari perlu tanpa manfaat
tambahan yang jelas.

**Job yang menjalankan auto-resolve:** `resolve-flagged-runs` (Vercel
Cron, lihat architecture.md §1) query `status = 'flagged' AND
flag_confidence = 'low' AND created_at < now() - REVIEW_WINDOW_LOW`,
transisi tiap baris ke `approved`. Job ini **tidak pernah** menyentuh run
`flag_confidence = 'high'` — itu murni menunggu manual override.

**Kenapa auto-threshold untuk LOW, bukan wajib manual review untuk
semuanya:** v1 sengaja tidak punya admin app/UI review (di luar scope MVP
— lihat product-spec.md §5 Non-goals). Auto-resolve LOW-confidence
memastikan mayoritas kasus (GPS noise biasa) selalu punya jalan keluar
tanpa butuh manusia, sementara HIGH-confidence tetap dijaga manusia.
Manual override tetap tersedia sebagai runbook (query langsung ke DB,
atau script terverifikasi — lihat repo-coding-rules.md) untuk kedua
confidence level, kapan saja.

**Kenapa `flagged` dikecualikan dari leaderboard (bukan tetap tampil
dengan poin penuh):** ini yang melindungi fairness leaderboard — publik
tidak pernah melihat poin dari run yang masih dipertanyakan keabsahannya.
User yang di-flag tetap melihat poin sementaranya di riwayat run pribadi
(product-spec AC 4.3.2), tapi tidak muncul di leaderboard sampai
`approved`.

**`flag_confidence` lifecycle:** diisi (`low`/`high`) tepat saat status
jadi `flagged`, dan **tetap ada** (tidak di-null-kan) setelah resolved ke
`approved` maupun `rejected`-via-override — ini catatan historis kenapa
run itu sempat ditahan, dipakai client untuk copy yang tepat (T2.14b).
Hanya `null` untuk `validated` dan `rejected` immediate (run yang memang
tidak pernah melewati status `flagged`).

**Level & `User.total_points` tidak diproteksi dari regresi:** level
adalah fungsi murni dari `User.total_points` (product-spec §4.4 AC1),
dihitung ulang tiap kali ledger berubah — termasuk saat override
`flagged → rejected` menulis compensating transaction negatif (§2.4.1
tabel `rejected`). Kalau itu membuat total poin turun di bawah threshold
level saat ini, level ikut turun. Tidak ada special-case "level tidak
boleh turun" — konsisten dengan prinsip "server adalah source of truth"
di awal §2.4, dan menghindari state tersembunyi yang harus dijaga
terpisah dari ledger.

## 3. Offline-First Strategy

1. GPS tracking & point calculation berjalan **sepenuhnya lokal** (Core
   Data) selama run — tidak butuh koneksi sama sekali untuk mencatat run
   dan menghitung estimasi poin.
2. Setelah run selesai, hasil disimpan di local `Run` entity (Core Data)
   dengan `sync_status = pending_sync` — field ini **client-only** (mobile
   Core Data), terpisah dari `RUN.status` di server (§2.4.1:
   validated/flagged/approved/rejected). Jangan disamakan keduanya.
3. Sync queue (background task) mencoba push run ke server setiap kali
   koneksi tersedia (foreground reconnect + periodic background sync);
   `sync_status` berubah `syncing` selama request berlangsung.
4. Server menjalankan ulang validasi & perhitungan poin (§2.4) sebagai
   source of truth — bukan sekadar menerima angka dari klien mentah-mentah
   (mencegah client-side tampering). Response bersifat synchronous
   (`201 Created`), langsung berisi `RUN.status` hasil evaluasi awal
   (§2.4.1) — tidak ada polling untuk hasil awal ini. Resolusi
   *belakangan* dari run `flagged` (LOW auto-resolve sampai
   `REVIEW_WINDOW_LOW` setelahnya, HIGH kapan saja lewat manual override)
   direkonsiliasi terpisah lewat `GET /api/runs` — lihat step 7 di bawah.
5. Setelah sync sukses, `sync_status` device berubah `synced`, dan
   `final_points_awarded` dari server menggantikan estimasi lokal di UI.
   Kalau `RUN.status = flagged`, UI menampilkan alasan dari
   `anomaly_flags` (product-spec AC 4.3.2). Kalau request gagal,
   `sync_status` jadi `failed` dan di-retry.
6. Jika sync gagal berkali-kali (mis. run sangat lama offline), run tetap
   tersimpan di device dan di-retry — tidak pernah silently dropped.
7. **Rekonsiliasi status belakangan:** menutup celah yang versi tech-spec
   sebelumnya tidak punya jawabannya — resolusi LOW/HIGH terjadi
   *setelah* run sudah `synced`, jadi step 4-6 saja tidak cukup untuk
   menyampaikan hasil itu ke user. Endpoint-nya (T2.14c) dan loop
   client-nya (T2.14d) dipisah — lihat tasks/phase-2 untuk pembagian
   tugasnya; step ini menjelaskan behavior gabungan keduanya.
   - **Kapan dipanggil:** app open, dan tiap siklus sync — **tapi hanya
     kalau client menyimpan minimal 1 run lokal dengan `server_status
     = flagged`** (T0.6). Kalau tidak ada run yang sedang di-watch,
     panggilan di-skip total. Kalau ada, panggilan (termasuk saat app
     open) tunduk pada batas **minimal 15 menit sejak percobaan
     rekonsiliasi terakhir** — waktu percobaan (bukan cuma yang sukses)
     disimpan di `sync_meta.last_reconcile_attempt_at` (T0.6) supaya
     batas ini bertahan lintas restart app, bukan cuma in-memory.
   - **Yang dipanggil:** `GET /api/runs?since=<last_reconciled_at>`
     (database-api-spec.md §2.2b). **Panggilan pertama kali** (belum ada
     `last_reconciled_at` tersimpan): `since` di-omit, server default ke
     lookback 90 hari — bukan device time, bukan error. Panggilan
     berikutnya: `last_reconciled_at` diambil dari field `server_time` di
     response sebelumnya — **kecuali** kalau response itu `has_more:
     true` (>200 baris berubah), yang mana cursor-nya jadi `updated_at`
     baris terakhir di batch itu, bukan `server_time` (`server_time`
     akan melompati baris yang belum ke-drain). Baik `server_time`
     maupun `updated_at` baris terakhir sama-sama nilai server (**bukan**
     jam device — lihat database-api-spec.md §2.2b "Clock source"). Kalau
     `has_more: true`,
     client re-call segera pakai cursor barusan, berulang sampai
     `has_more: false` sebelum
     berhenti — supaya tidak ada resolusi lama yang ke-skip permanen.
   - **Yang di-update:** untuk tiap run di response, dicocokkan ke baris
     lokal lewat `server_run_id` (run_id di response yang tidak match
     baris lokal manapun diabaikan, bukan disisipkan sebagai baris baru
     — endpoint ini bukan general history sync); lalu timpa kolom lokal
     `server_status`, `flag_confidence`, `final_points_awarded`,
     `anomaly_flags`, `resolved_at` (salinan lokal dari field server
     bernama sama, kecuali `server_status` yang menyalin dari field
     response `status` — lihat tasks/phase-0-setup.md T0.6; semuanya
     beda dari `sync_status` yang client-only). Setelah update, save ke
     Core Data context (ini me-render ulang baris run itu sendiri, mis. di
     run history, lewat `@FetchRequest`) **dan** panggil eksplisit
     `ProgressViewModel.refresh()` (T2.16) yang re-fetch
     `GET /api/users/me/progress` — dua mekanisme terpisah, Core Data save
     saja **tidak** memicu re-fetch data profile/progress dari server —
     supaya poin/level yang berubah langsung ter-render — termasuk kalau
     itu berarti level
     **turun** (override ke `rejected` bisa bikin level turun; ini bukan
     error state, tidak ada proteksi "level tidak boleh turun").
   - **Kalau gagal (offline, request error, JWT expired):** attempt
     timestamp tetap di-update (supaya tidak retry rapat-rapat), tapi
     `last_reconciled_at` **tidak** di-advance (retry window berikutnya
     otomatis meng-cover ulang), dan kegagalan ini **tidak** masuk
     antrian retry upload run (T2.14) — dua mekanisme ini independen.
   - **HIGH confidence bisa tidak pernah resolve** (§2.4.1) — client
     akan terus mencoba rekonsiliasi untuk run itu tanpa batas waktu
     (dibatasi cadence 15 menit di atas) selama masih `flagged`; ini
     disengaja, bukan bug, dan T2.14b's copy harus ditulis supaya wajar
     dilihat user dalam kondisi "masih menunggu" berkepanjangan.

## 4. Non-Functional Requirements

| Kategori | Target | Catatan |
|---|---|---|
| Battery efficiency (background tracking) | < 5% battery per jam active tracking | Manfaatkan `CLLocationManager` native: `desiredAccuracy` (`kCLLocationAccuracyBest` saat active run), `distanceFilter` untuk redundant-update throttling, dan `allowsBackgroundLocationUpdates` + `pausesLocationUpdatesAutomatically` untuk stop-detection bawaan iOS — bukan polling GPS interval tetap, dan bukan lagi library pihak ketiga. |
| Leaderboard query response time | p95 < 300ms untuk leaderboard read (dari precomputed table) | Lihat architecture.md §4 — leaderboard **tidak** dihitung live dari raw transaction table saat request masuk. |
| Point submission (run sync) response time | p95 < 1.5s untuk validasi + write PointTransaction | Termasuk anti-cheat check synchronous di request path. |
| Skalabilitas data poin | PointTransaction sebagai append-only ledger, tidak pernah di-update/delete | Memungkinkan audit trail & re-kalkulasi total poin user kapan saja tanpa kehilangan histori. |
| Precompute freshness leaderboard | Interval maksimal 15 menit (selaras dengan AC di product-spec §4.5) | Trade-off sadar antara real-time dan biaya compute; bisa diperketat di v2 kalau perlu. |
| Run status reconciliation read (`GET /api/runs?since=`) | p95 < 300ms; hasil dibatasi 200 baris (ASC + `has_more`); index `(user_id, updated_at)` wajib | Dipanggil hanya saat client punya run `flagged` yang di-watch, dan minimal 15 menit sejak percobaan terakhir (§3 step 7, cadence persisted lintas restart) — bukan tiap app-open/sync-cycle tanpa syarat, supaya tidak jadi endpoint QPS tertinggi tanpa alasan. |
