# Laju App — Tech Spec (v1)

Depends on: [product-spec.md](../01-product/product-spec.md)

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
| Database | PostgreSQL (via Supabase) | **Rekomendasi**, bukan keputusan final — lihat catatan trade-off. Leaderboard butuh ranking query & aggregation (v1: Global; per region kecamatan/kabupaten-kota/provinsi ditunda ke v1.1, 2026-09-21, tapi tetap alasan pilih relational DB) yang jauh lebih natural & efisien di relational DB dengan `GROUP BY`/window function dibanding NoSQL document store. |
| Auth | Supabase Auth (JWT) | Terintegrasi langsung dengan Postgres (Row Level Security opsional), menghindari sinkronisasi identitas dua sistem (Firebase Auth + Postgres user table terpisah). |
| Maps SDK | **MapKit** (native Apple, keputusan locked 2026-09-12 — sebelumnya Mapbox/Open Question, lihat riwayat di bawah) | Dipakai di v1 core mulai Fase 1 (product-spec.md §4.8-4.9 — reverses the prior Non-goal) untuk live map saat tracking + static route map di Summary/History. Tidak ada biaya per-request (native framework, termasuk dalam Apple Developer Program fee) — lihat §5.1 untuk pendekatan integrasi, lean-canvas.md §7 untuk koreksi cost structure. Mapbox tidak jadi dipakai — MapKit cukup untuk kebutuhan v1 (tampilkan posisi + polyline dari data lokal, bukan routing/geocoding kompleks) dan menghapus dependency pihak ketiga sekaligus biaya. |
| Backend hosting | Vercel | Native untuk Next.js, familiar dari stack existing. |
| DB/Auth hosting | Supabase Cloud | Managed Postgres, mengurangi ops overhead dibanding self-host. |
| Background jobs (leaderboard precompute) | Vercel Cron (v1) → dedicated worker jika volume naik | Cukup untuk interval precompute 15 menit di skala awal; lihat architecture.md §4 untuk migration path. |
| Repo tooling | Xcode project (`.xcodeproj`/SPM) untuk `ios/`, npm/pnpm untuk `backend/`, dalam satu monorepo Git — lihat repo-coding-rules.md §1 untuk struktur & alasan | Client (Swift) dan server (TypeScript) sudah beda bahasa sepenuhnya — tidak ada shared-types package yang bisa dipakai literal di kedua sisi lagi (lihat §2.2b untuk strategi parity poin), jadi tidak butuh build orchestration lintas-bahasa (Turborepo/pnpm workspaces tidak relevan lagi untuk sisi mobile). |

### Trade-off note: Firebase vs Postgres/Supabase — untuk PM decide

Firebase (Firestore) familiar buat developer, tapi:
- Leaderboard lokal granular (per kecamatan/kabupaten-kota/provinsi, per
  season — *ditunda ke v1.1 / Fase 4, keputusan 2026-09-21; v1 hanya Global,
  alasan ini dipertahankan sebagai dasar pemilihan Postgres untuk saat itu*) butuh
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

### 2.1b Client-side GPS noise filtering (distinct from §2.4 anti-cheat)

Ditemukan lewat testing fisik di T0.9/T0.8 (`tasks/phase-0-setup.md`), bukan
didesain di muka — dicatat di sini supaya jejaknya gak hilang. Ini murni
soal **kualitas display/distance lokal di client** (biar angka yang
ditampilkan ke user masuk akal), **bukan** anti-cheat (§2.4, server-side,
tetap satu-satunya penentu status run) — dua mekanisme ini sengaja gak
digabung, threshold-nya beda tujuan.

Setiap `CLLocation` yang masuk (`LocationTrackingService.swift`) disaring
lewat 4 lapis sebelum ikut ke `distanceMeters`:

1. **Accuracy filter** — tolak kalau `horizontalAccuracy < 0` atau `> 20m`.
   Ditemukan: cold-fix GPS awal tracking bisa punya accuracy jelek (puluhan
   meter), dan sebelum filter ini ada, satu titik seperti itu pernah
   menghasilkan implied speed **6459 km/h** (run pk=34, 2026-09-10).
2. **Staleness filter** — tolak kalau `|timestamp - now| > 5 detik` (fix
   cache lama yang dianggap seolah live).
3. **Speed sanity filter** — tolak kalau implied speed dari titik
   sebelumnya (accepted) `> 12 m/s` (~43 km/h, generous ceiling buat
   manusia lari, threshold longgar disengaja — ini bukan pengganti §2.4).
4. **Stationary-anchor drift filter** (`RunViewModel.swift`) — lapisan
   yang paling belakangan ditemukan perlu. Filter #1-3 di atas cuma
   membandingkan SATU titik ke titik SEBELUMNYA — itu mencegah satu
   lompatan besar, tapi gak mencegah titik referensinya sendiri "jalan
   sendiri" pelan-pelan kalau tiap drift kecil individual masih "masuk
   akal" dibanding titik tepat sebelumnya. Kebukti nyata: HP diam total
   indoor 60 menit tetap mencatat 34.9m (3 segmen: 14.32m, 14.32m, 6.25m —
   masing-masing lolos filter #1-3, run pk=41, 2026-09-11). Fix: simpan
   `stationaryAnchor` — titik TERAKHIR yang terkonfirmasi gerakan nyata
   (bukan sekadar titik terakhir yang accepted). Titik baru dalam radius
   20m dari anchor dianggap noise/drift — direkam tetap ke `gps_route`
   mentah (data gak dibuang, cuma gak ikut `distanceMeters`), dan anchor
   TIDAK digeser sampai ada titik yang beneran keluar radius 20m.

Radius 20m (stationary-anchor) sengaja lebih besar dari floor per-titik
(yang terikat ke `horizontalAccuracy` masing-masing fix, biasanya
single-digit sampai ~10m outdoor) — karena tujuannya beda: floor per-titik
menilai SATU fix, radius stationary-anchor menilai AKUMULASI drift
sepanjang periode diam.

**Status retest (2026-09-12): RESOLVED, dengan keterbatasan terdokumentasi.**
Percobaan pertama (~6.3 menit, 1 titik) gak cukup, diulang dengan target
waktu eksplisit (jam pasti, konfirmasi per-fase). Retest final: run
kontinu **61.8 menit** (jauh di atas syarat ≥35 menit), device diam total
indoor, `distanceMeters` tetap **0m** sepanjang durasi itu. Fase outdoor
yang direncanakan gak sempat menghasilkan titik GPS tambahan sebelum Stop
(cuma 1 titik GPS total sepanjang seluruh 61.8 menit) — jadi hasil ini
kuat secara PRAKTIS (0m stabil >1 jam diam, kondisi nyata) tapi **logic
`stationaryAnchor` (radius 20m) sendiri belum pernah benar-benar dieksekusi
dalam retest ini** — gak ada titik kedua yang masuk radius anchor untuk
dievaluasi/ditolak. Ini konsisten dengan desain filter-filter sebelumnya
(accuracy/stale/speed + `distanceFilter=10m`) yang sudah cukup ketat
sehingga GPS nyaris tidak pernah fire ulang saat device benar-benar diam
— anchor jadi backstop yang jarang ter-trigger dalam kondisi normal,
bukan berarti tidak berguna (bug awal, run pk=41, membuktikan situasi itu
BISA terjadi kalau GPS kebetulan noise beberapa kali berturut-turut).
Kalau mau menguji mekanisme anchor secara langsung di masa depan, skenario
yang lebih tepat: device dipegang tangan dengan sedikit gerakan alami
(bukan ditaruh diam total di meja), supaya drift-dalam-radius benar-benar
terpicu berkali-kali.

**Konsumen kedua `gps_route`: splits/elevation/map (2026-09-13, Round 7
audit finding B7-1).** `gps_route` yang tersimpan berisi SEMUA titik yang
lolos filter #1-3 (accuracy/stale/speed) — ini superset dari titik yang
ikut `distanceMeters`, karena titik dalam radius anchor tetap direkam
mentah tapi TIDAK ikut `distanceMeters` (lihat poin 4 di atas). Splits
per-km (§4.10), elevation gain/loss (§4.12), dan live/static polyline
(§5.1) semuanya menampilkan/menghitung dari `gps_route` — kalau fungsi
turunan ini menjumlahkan jarak titik-ke-titik MENTAH tanpa mereplikasi
logic anchor, hasilnya **tidak akan** sama dengan `distanceMeters` (bisa
lebih besar, karena drift yang di-suppress dari `distanceMeters` tetap
ikut terhitung). **Aturan wajib:** setiap fungsi yang menurunkan jarak
dari `gps_route` (T1.10 splits, T1.12 elevation-noise-context) harus
mereplikasi logic acceptance `stationaryAnchor` yang sama persis
(`RunViewModel.handle(_:)`), bukan menjumlahkan delta titik-ke-titik
mentah — ini deterministik untuk direplikasi karena hanya butuh
`gps_route` + 2 konstanta yang sudah ada (`stationaryRadiusMeters=20`,
`anchorAccuracyThresholdMeters=10`), tidak butuh field baru di skema.
Dengan aturan ini, total split per-km dijamin sama dengan
`distanceMeters` by construction (product-spec §4.10 AC3 tetap
achievable tanpa migrasi skema).

**Konsumen kedua `stationaryAnchor`: auto-pause (2026-09-13, Round 7
audit finding B7-3).** Logic anchor di atas murni REAKTIF — hanya
dievaluasi saat sebuah fix GPS datang. Retest T0.9 di atas sendiri
membuktikan saat device benar-benar diam, GPS nyaris tidak fire ulang
(1 titik dalam 61.8 menit) — artinya kalau auto-pause (product-spec
§4.11) didesain "trigger saat anchor mendeteksi diam", trigger itu
**tidak akan pernah menyala** justru pada kondisi diam total yang paling
jelas. Auto-pause **harus** jadi mekanisme time-based terpisah: timer
periodik yang mengecek "berapa lama sejak `stationaryAnchor` terakhir
kali berpindah (bukti gerakan nyata terakhir)", independen dari kapan
fix GPS berikutnya datang — bukan callback yang cuma jalan saat
`handle(_:)` dipanggil. Anchor tetap satu-satunya sumber "kapan
terakhir kali gerakan nyata dikonfirmasi"; yang berubah cuma cara
auto-pause MENGEVALUASI-nya (polling berkala, bukan reaktif-per-fix).

**Bug kedua ditemukan & di-fix (2026-09-12, T1.2b re-verify di device
fisik):** skenario Start→Pause(10s)→Resume(5s)→Stop menghasilkan 35m
tercatat padahal device diam total — device log konkret: fix pertama run
`accuracy=15.11m` (lolos filter #1 tapi masih fix cold-start yang belum
"settle"), 12 detik kemudian fix kedua jauh lebih akurat
`accuracy=3.20m` — jarak asli antar keduanya ~35.0m, di atas radius
anchor 20m DAN di atas jitter-floor per-titik (15.11m), jadi lolos semua
filter #1-4 yang ada. Root cause: `stationaryAnchor` di-set TANPA SYARAT
dari fix pertama sebuah run, tanpa peduli kualitas fix itu sendiri — kalau
fix pertama itu kebetulan cold-start yang buruk, dia jadi referensi yang
salah, dan fix BERIKUTNYA yang justru lebih akurat malah kebaca sebagai
"gerakan". **Fix:** anchor cuma boleh dibentuk/dipindah dari fix dengan
`horizontalAccuracy ≤ 10m` (`anchorAccuracyThresholdMeters`,
`RunViewModel.swift`) — fix yang lebih buruk dari itu tetap direkam ke
`gps_route` mentah, tapi tidak dipercaya jadi anchor. Ambang 10m dipilih
persis dari data insiden ini (tolak 15.11m, terima 3.20m), konsisten
dengan catatan "biasanya single-digit sampai ~10m outdoor" di atas.
Diverifikasi ulang di device fisik yang sama persis: `distanceMeters`
tetap 0m sepanjang siklus Start→Pause→Resume→Stop, dikonfirmasi lewat
`devicectl device copy from` (SQLite store `Laju.sqlite`, bukan cuma UI).

**Validasi akurasi jarak jauh & durasi lama (2026-09-13, run pk=81,
~24km/~1 jam, kendaraan bermotor).** Testing sebelumnya (T1.8/T1.9 device
verification) cuma pakai pergerakan skala pendek di tempat. Run ini data
pertama untuk jarak jauh dan durasi berkelanjutan panjang:

- `distanceMeters` tersimpan: **24287.75m**, cocok dengan UI (24.3km).
  Strava paralel: 24.57km. Deviasi **1.16%** (0.28km) — konsisten dengan
  estimasi user dari layar (~1.1%).
- 1402 titik GPS diperiksa (sampling window: awal/tengah/akhir + tiap gap
  waktu >10 detik). Implied speed titik-ke-titik tertinggi **12.03 m/s**
  (~43.3 km/h) — pas di bawah `maxPlausibleSpeedMetersPerSecond=12`
  (§2.1b poin 3), 5 titik mendarat di 12.00-12.03 m/s. Tidak ada titik
  yang lolos filter padahal melebihi 12 m/s — speed sanity filter bekerja
  sesuai desain di kondisi kecepatan tinggi sustained, bukan cuma di
  kecepatan lari manusia.
- **25 gap waktu >10 detik** ditemukan antar titik berurutan (total 972s,
  ~27% dari 3589s rentang GPS pertama-terakhir) — kemungkinan besar sinyal
  hilang sesaat (jalan raya, app-switch ke Strava seperti diakui user).
  Titik-titik ini menyumbang **5284.6m (21.8%)** dari total distance,
  dihitung sebagai garis lurus antar 2 titik yang berjauhan waktu. Dua gap
  terbesar: 190 detik/2273m (implied speed 11.96 m/s, pas di bawah
  threshold) dan 89 detik/1053.8m (11.84 m/s). Garis lurus lintas gap
  besar begini kemungkinan **underestimate** jarak jalan sebenarnya
  (jalan gak lurus) — kontribusi masuk akal ke arah deviasi vs Strava di
  atas (Laju < Strava).
- Gap akhir run: fix GPS terakhir 138.5 detik SEBELUM `endedAt` (user
  tap Stop) — device diam/app di-background sesaat sebelum Stop (bukan
  bug: `distanceMeters` gak ikut nambah karena gak ada fix baru yang
  masuk, tapi `durationSeconds` tetap jalan sebagai active time sampai
  Stop ditekan — lihat §2.4 catatan `duration_seconds` client-asserted).
  Delay start (Start tap → fix pertama): 2.26 detik, wajar (GPS
  acquisition).
- Kesimpulan: tidak ada anomali teknis (bug) ditemukan — filter #1-3
  bekerja sesuai desain bahkan di kecepatan tinggi sustained lama. Dua
  temuan di atas (gap-jump straight-line & trailing-duration-after-last-
  fix) murni karakteristik desain yang sudah ada, dicatat di sini sebagai
  data kalibrasi, bukan bug baru — lihat §2.4 untuk implikasi anti-cheat.

### 2.1c Unit display: kilometer, bukan meter (keputusan)

Data internal — storage (`Run.distanceMeters` di Core Data,
`distance_meters` di API/server), kalkulasi, dan semua threshold di §2.1b
di atas — **tetap dalam meter, tidak berubah**. Yang berubah cuma layer
presentasi ke user:

- **< 10 km:** 2 desimal, mis. `0.66 km`
- **≥ 10 km:** 1 desimal, mis. `12.3 km`

Konversi meter→km ini murni terjadi di layer UI (formatting saat display),
bukan di layer data/kalkulasi.

**Belum diterapkan ke `RunTrackingView` (skeleton/debug screen saat ini,
masih nampilin "Distance: 661 m").** Sengaja dibiarkan meter untuk
sekarang — screen itu bukan UI final, cuma alat verifikasi/debug (presisi
meter lebih berguna buat kasus kayak drift test kemarin). Konversi ke km
jadi requirement eksplisit untuk **Run Tracking Screen** yang sesungguhnya
(Fase 1 UI work, belum dikerjakan) — jangan sampai kelewatan pas screen
itu dibangun. Belum ada UI lain (Run Summary, notifikasi, dst.) yang
sudah menampilkan distance ke user dalam meter mentah — semuanya masih
belum diimplementasikan (Fase 1), jadi tidak ada tempat lain yang perlu
diupdate sekarang.

### 2.2 Formula (v1, perlu divalidasi dengan data real — lihat lean-canvas)

```
pace_multiplier = f(avg_pace_sec_per_km)   // piecewise, lihat §2.3
base_points     = distance_km * pace_multiplier
streak_bonus    = min(streak_days, 7) * STREAK_BONUS_PER_DAY   // cap 7 hari
raw_points      = 0                                    if distance_km < MIN_DISTANCE_KM_FOR_POINTS
raw_points      = base_points + streak_bonus           otherwise
final_points    = raw_points * trust_multiplier(user)          // lihat §2.4
```

`STREAK_BONUS_PER_DAY` adalah konstanta konfigurasi (bukan hardcode),
supaya bisa di-tuning tanpa deploy ulang app. **Nilai awal v1: 2 poin**
per hari streak (cap 7 hari → maksimum bonus 14 poin/run) — starting
point yang sama statusnya dengan tabel pace multiplier di §2.3: perlu
di-tuning pakai data run real, bukan angka final.

**`MIN_DISTANCE_KM_FOR_POINTS` — bug ditemukan & fix (2026-09-13):**
`streak_bonus` bersifat **additive**, bukan multiplicative terhadap
`distance_km` — sebelum fix ini, `raw_points = base_points + streak_bonus`
tanpa syarat, artinya `distance_km = 0` (base_points = 0) tetap
menghasilkan poin penuh dari `streak_bonus` saja. Terbukti nyata di
device: dua run dengan `distanceMeters = 0.0` (tap Start lalu Stop
langsung, tanpa gerak) menghasilkan **6.0** dan **8.0** poin — masing-
masing PERSIS `min(streak_days,7) * STREAK_BONUS_PER_DAY` untuk
`streak_days = 3` dan `streak_days = 4` (dikonfirmasi dari histori run
riil di device: 3 dan 4 hari berturut-turut punya run sebelum tanggal
run tersebut). Ini celah grinding — user bisa spam Start/Stop tanpa lari
sama sekali dan tetap dapat poin selama sudah punya streak berjalan,
bertentangan dengan prinsip inti "poin mencerminkan usaha lari nyata".

**Fix:** `raw_points = 0` kalau `distance_km < MIN_DISTANCE_KM_FOR_POINTS`
— gate ini berlaku untuk TOTAL poin (base **dan** streak bonus sekaligus),
bukan cuma base_points, karena celahnya justru ada di streak_bonus yang
additive. **Nilai v1: 0.1 km (100m)** — dipilih sengaja jauh di atas
radius `stationaryAnchor` (20m, §2.1b): threshold harus lebih besar dari
noise floor GPS yang sudah terbukti, supaya tidak ada cara "curang"
dengan gerakan kecil yang kebetulan lolos filter GPS tapi di bawah radius
anchor. 100m = 5x radius anchor, margin lebar tapi tetap trivial buat
gerakan nyata sekecil apapun (bukan bar "olahraga", cuma bar
anti-grinding). Sama status dengan `STREAK_BONUS_PER_DAY`/tabel pace
multiplier — starting point, perlu tuning data real, bukan final.

**Konsekuensi ke `streak_days` sendiri (mencegah "checklist kosong"):**
hari yang cuma py run di bawah `MIN_DISTANCE_KM_FOR_POINTS` **tidak**
dihitung sebagai "hari lari" untuk keperluan hitung `streak_days` hari-hari
BERIKUTNYA — kalau tidak, seseorang bisa jaga streak-nya tetap hidup
selamanya dengan tap Start/Stop kosong tiap hari (dapat 0 poin hari itu,
tapi tetap "menyelamatkan" streak untuk suatu hari nanti ditukar poin
lewat 1 run beneran). `streak_days` yang dipakai untuk bonus run hari ini
dihitung sebagai: (jumlah hari berturut-turut ber-run qualifying, berakhir
KEMARIN) + 1 KALAU run hari ini sendiri qualifying (`distance_km >=
MIN_DISTANCE_KM_FOR_POINTS`), + 0 kalau tidak (dan poin tetap 0 lewat gate
di atas, jadi nilai `streak_days` di kasus itu tidak mempengaruhi poin
apapun, cuma dipakai buat tampilan status streak).

**Streak di server (2026-09-21).** Sebelumnya server memakai `streakDays = 0`, jadi bonus streak di estimasi klien
tidak pernah ikut poin final (estimasi +2.7, final 1 — terlihat pada run nyata pertama dari app). Sekarang server
menurunkan `streak_days` dari riwayat run milik user itu sendiri, **bukan** dari klien (bonusnya hingga 14 poin/run,
jadi tidak boleh di-assert klien; field `streak_days` di request diabaikan). Semantik sama dengan `StreakTracker` klien:
jumlah hari kalender berturut-turut yang berakhir **kemarin** dengan minimal satu run, ditambah 1 bila run yang sedang
dikirim memenuhi syarat sendiri. Syarat: jarak ≥ `MIN_DISTANCE_KM_FOR_POINTS` (100 m) dan status `validated`/
`approved`/`flagged` — run `rejected` tidak menyambung streak (anti-farming). Satu hari dihitung sekali berapa pun
jumlah run; satu hari bolong mereset; dihitung mundur maksimal 7 hari (cap bonus). **Asumsi zona waktu:** server tidak
tahu zona waktu perangkat, jadi batas hari memakai **Asia/Jakarta (UTC+7)**, asumsi v1 untuk pasar Indonesia; user
WITA/WIT bisa selisih di sekitar tengah malam, yang muncul sebagai selisih kecil estimasi-vs-final, bukan poin
berlebih. Implementasi: `backend/lib/streak.ts`; dipanggil dari `POST /api/runs`.

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
| Trust score | Kumulatif berapa kali user kena flag/reject dalam rolling 30 hari terakhir | Trust turun → `trust_multiplier` < 1.0 → poin user berikutnya otomatis lebih rendah sampai trust pulih. **Formula lengkap (decay/floor/recovery) ada di bawah tabel ini** — bukan lagi "turun" tanpa angka |

**Definisi "segmen":** interval antara 2 titik GPS berurutan (satu
point-pair) di `gps_route`. Setiap check di atas beroperasi per-segmen —
GPS speed jump & distance/duration sanity langsung bekerja di satu
point-pair, elevation anomaly di jendela waktu singkat yang dipetakan ke
point-pair terdekat.

**`duration_seconds` sengaja tidak di-cross-check terhadap rentang
waktu `gps_route` (2026-09-13, Round 7 finding B7-4):** sejak auto-pause
(product-spec §4.11, T1.11) ada, waktu diam otomatis dikecualikan dari
`duration_seconds` — sama seperti pause manual (T1.2b) — sehingga
`duration_seconds` yang dikirim client SECARA RUTIN lebih pendek dari
selisih timestamp titik pertama-terakhir di `gps_route`. Ini BUKAN
sinyal cheat: `duration_seconds` tetap `client-asserted`, tidak
divalidasi ulang dari `gps_route` di sisi manapun — desain ini sudah
disengaja sejak T1.2b/T2.9 untuk pause manual, sekarang juga berlaku
untuk auto-pause karena keduanya menghasilkan gap waktu nyata tanpa
titik GPS di antaranya (bukan artifact yang perlu dicurigai).

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

**Formula `trust_multiplier` (didefinisikan 2026-09-17).** Sebelum ini
baris "Trust score" di tabel checks cuma bilang trust turun → multiplier
< 1.0, tanpa angka — jadi T2.11 tidak bisa dikerjakan sama sekali (tidak
ada formula, decay rate, floor, maupun jalur pemulihan). Definisi final:

```
trust_multiplier(user) = clamp(
    1.0
      - 0.10 × (jumlah flag HIGH confidence dalam 30 hari terakhir)
      - 0.05 × (jumlah flag LOW confidence dalam 30 hari terakhir
                yang TIDAK berakhir auto-approve)
      + 0.02 × (jumlah run bersih dalam 30 hari terakhir),
    min: 0.3,
    max: 1.0
)
```

Aturan tiap komponen:

| Komponen | Nilai | Catatan |
|---|---|---|
| **Base** | `1.0` | Full trust. User baru mulai di sini |
| **Decay — HIGH** | `-0.10` per flag | HIGH confidence (`excluded_pct` 25%–<50%, §2.4.1) tidak pernah auto-resolve, jadi setiap flag HIGH selalu dihitung |
| **Decay — LOW** | `-0.05` per flag | HANYA untuk flag LOW yang **tidak** berakhir `approved` lewat auto-resolve. Flag LOW yang auto-approve setelah `REVIEW_WINDOW_LOW` (default 48 jam) **tidak** kena decay sama sekali — sistem sudah memutuskan run itu wajar, menghukumnya lagi berarti menghukum user dua kali untuk kejadian yang dinyatakan bersih |
| **Floor** | `0.3` | Tidak boleh turun ke 0. Curang berat itu domain manual ban/review, bukan `trust_multiplier` — multiplier ini alat graduated consequence, bukan alat penghapus akun. `0` juga bikin user tidak punya jalan pulang, yang menghapus insentif berhenti curang |
| **Recovery** | `+0.02` per run bersih | "Bersih" = run selesai dengan `status = validated` dan `anomaly_flags` kosong. Run `approved` (pernah flagged lalu lolos) **tidak** dihitung bersih — cukup untuk tidak kena decay, tidak cukup untuk memulihkan trust |
| **Ceiling** | `1.0` | Recovery berhenti di full trust, tidak pernah jadi bonus di atas 1.0 |

**Window: rolling 30 hari terakhir**, dihitung ulang tiap kali run baru
divalidasi — bukan counter permanen. Konsekuensinya disengaja: flag yang
umurnya lewat 30 hari otomatis berhenti menekan multiplier tanpa perlu
job pembersih terpisah, dan user yang berhenti curang pulih lewat dua
jalur sekaligus (flag lama keluar dari window + run bersih menambah
recovery).

Contoh: user kena 1 flag HIGH lalu menyelesaikan 3 run bersih dalam
window yang sama → `1.0 - 0.10 + 0.06 = 0.96`. User kena 8 flag HIGH
tanpa run bersih → `1.0 - 0.80 = 0.20` → di-clamp ke floor `0.3`.

**Status angka-angka ini: starting point yang defensible, BUKAN final.**
Sama persis statusnya dengan pace-bracket multiplier di §2.3,
`MIN_DISTANCE_KM_FOR_POINTS` di §2.2, dan threshold pace cap / GPS speed
jump di tabel §2.4 ini sendiri — yang terakhir itu baru dikalibrasi ulang
setelah ada data real (run pk=81, lihat blok kalibrasi di bawah). Rasio
decay-vs-recovery di sini (butuh 5 run bersih untuk menghapus 1 flag
HIGH) dipilih supaya pemulihan terasa nyata tapi tidak instan; apakah itu
terlalu keras atau terlalu longgar **tidak bisa dijawab tanpa data user
asli** — berapa sering user jujur kena false-positive flag, dan berapa
cepat pelanggar berulang benar-benar mentok di floor. Kalibrasi ulang
angka-angka ini begitu Fase 2 jalan dan ada trafik nyata, dengan pola
yang sama: kumpulkan data dulu, baru ubah threshold, jangan tebak di
awal.

**Data kalibrasi real — pace cap & GPS speed jump (2026-09-13, run pk=81,
lihat §2.1b untuk detail penuh).** Test ~24km/~1 jam pakai kendaraan
bermotor (bukan lari sungguhan, diakui user) menghasilkan data real buat
kalibrasi threshold di atas, BUKAN implementasi baru — Fase 1 sengaja
belum punya anti-cheat aktif (server-side, Fase 2):

- Avg pace sustained **2:34/km (~23.9 km/h)** selama >1 jam, jauh di
  bawah `pace_cap` threshold yang sudah ada (**3:00/km untuk segmen
  >1km berturut-turut**) — data ini MENGKONFIRMASI threshold 3:00/km
  sudah cukup ketat untuk menangkap pola non-lari seperti ini (run
  pk=81 akan ter-exclude penuh kalau anti-cheat ini aktif).
  Pace per-km dari layar (Laju/Strava) bervariasi **1:28/km sampai
  4:27/km** tergantung kondisi jalan (lampu merah, kepadatan) — range
  ini referensi kalau `pace_consistency` (§2.1) perlu tuning lebih
  halus dari sekadar avg pace tunggal.
- Kecepatan mayoritas titik (median 8.31 m/s / ~29.9 km/h, banyak window
  30-43 km/h berturut-turut) jauh di atas `GPS speed jump` threshold
  yang sudah ada (**25 km/h sustained >3 sample**) — juga terkonfirmasi
  akan ter-exclude oleh rule yang sudah ada.
- **Blind spot ditemukan dari data ini, dicatat untuk desain Fase 2
  (BUKAN untuk di-fix sekarang):** `GPS speed jump` didefinisikan
  "sustained >3 sample berturut-turut" — run ini punya 25 gap waktu >10
  detik (2 di antaranya 190s/2273m dan 89s/1053.8m) yang masing-masing
  **1 segmen (1 point-pair) saja**, implied speed pas di bawah 12 m/s
  client-side ceiling. Segmen SATUAN seperti ini tidak akan pernah
  memicu rule ">3 sample berturut" walau jaraknya jauh lebih besar
  dibanding 3 sample normal berurutan — kalau di masa depan seseorang
  coba cheat pakai mock-location yang "teleport" pas di bawah speed
  ceiling dalam 1 lompatan besar (bukan beberapa sample kecil), rule
  count-based saat ini bisa kebobolan. Rekomendasi buat Fase 2: tambah
  check yang sadar **durasi gap** (jarak/waktu sejak titik sebelumnya),
  bukan cuma jumlah sample berturut — jadi 1 segmen dengan gap besar +
  jarak besar tetap ke-flag meski cuma "1 sample".

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

### 2.5 Season League (division) — arti resmi "tier" (keputusan 2026-09-21)

Sebelumnya AC Premium leaderboard (product-spec.md §4.5 AC4) memakai kata
"tier" tanpa definisi. **"Tier" = Season League**: divisi kompetitif yang
dihitung dari **poin yang didapat selama season yang sedang berjalan**.
Bukan Level (lifetime kumulatif, tidak pernah reset — database-api-spec.md
§1) dan bukan Rank (posisi real-time di leaderboard — product-spec.md §4.4
catatan istilah). Reset tiap season baru, konsisten dengan sistem Season.

```
season_points(user, season) = jumlah `PointTransaction.amount` milik user untuk `season_id` itu,
                              hanya dari run berstatus validated/approved
league(season_points)       = band pertama dari LEAGUE_BANDS yang memuat season_points
```

`season_points` sengaja **kuantitas yang sama** dengan kolom `points` di
`LEADERBOARD_ENTRY` scope global (T2.18: hanya `validated`/`approved`,
`deleted_at IS NULL`) — supaya liga dan papan peringkat tidak pernah
berselisih soal berapa poin seseorang. Kompensasi ledger (mis. run
`flagged` yang akhirnya `rejected`, tech-spec §2.4.1) ikut terhitung, jadi
liga bisa **turun** dalam satu season bila poin dicabut; ini benar, bukan bug.

**Band v1 (half-open `[min, max)`, sama gaya dengan tabel pace §2.3):**

| Liga | `season_points` | Perkiraan profil (≈13 minggu, run 5-10 km pace normal + bonus streak rata-rata) |
|---|---|---|
| Bronze | 0 – <80 | Kasual: ≈1 run/minggu |
| Silver | 80 – <250 | Rutin ringan: ≈2 run/minggu |
| Gold | 250 – <600 | Reguler: ≈3-4 run/minggu |
| Platinum | ≥ 600 | Serius: ≈5+ run/minggu dan/atau jarak jauh |

Semua user selalu punya liga (0 poin = Bronze) — tidak ada state "tanpa
liga". Nama liga sengaja berbeda dari title Level (Pemula … Legenda,
database-api-spec.md §1) supaya dua sistem itu tidak tertukar di UI.

**Kalibrasi — starting point, bukan final** (pola yang sama dengan tabel pace
§2.3, `STREAK_BONUS_PER_DAY`, dan `trust_multiplier`). Angka di atas berasal
dari rumus poin (§2.2: ≈`jarak_km × 1.0` untuk pace normal + bonus streak
maks 14) dan panjang season kuartalan (~91 hari, Season entity), BUKAN dari
data user asli — belum ada. **Wajib dikalibrasi ulang** setelah ada satu-dua
season data nyata; target awal distribusi yang layak dijaga: mayoritas user di
Bronze/Silver, Platinum kecil (mis. ±40% / 35% / 20% / 5%), supaya liga terasa
bisa dicapai tapi tetap prestisius. Band adalah konfigurasi
(`LEAGUE_BANDS`), bukan hardcode inline, supaya bisa dituning tanpa mengubah
logika.

**Sifat implementasi:** dihitung di **server saja** (satu-satunya sumber
`season_points`), diturunkan dari ledger — bukan kolom tersimpan, jadi tidak
ada state yang bisa melenceng. Tidak ada duplikasi di klien, jadi tidak perlu
fixture parity (ADR-0007). Liga akhir season disimpan bersama rank akhir untuk
riwayat (T3.8). Task implementasi: **T3.7a** (tasks/phase-3-season.md).

**Pemakaian (ditunda):** filter leaderboard per liga dan gating Freemium vs
Premium (Freemium = liga sendiri, Premium = semua liga — product-spec.md §4.5
AC4) ikut fitur Premium (Fase 4). v1 hanya menghitung dan menampilkan liga
sendiri; leaderboard Global v1 tetap satu papan untuk semua orang.

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
| Battery efficiency (background tracking) | < 5% battery per jam active tracking | Manfaatkan `CLLocationManager` native: `desiredAccuracy` (`kCLLocationAccuracyBest` saat active run), `distanceFilter` untuk redundant-update throttling, dan `allowsBackgroundLocationUpdates` — bukan polling GPS interval tetap, dan bukan lagi library pihak ketiga. **Koreksi 2026-09-13 (Round 7 finding N7-6):** `pausesLocationUpdatesAutomatically` di-set `false` di kode aktual (`LocationTrackingService.swift`) — stop-detection ditangani eksplisit lewat pause/resume manual (T1.2b) dan sekarang juga auto-pause (T1.11), bukan mekanisme bawaan iOS ini. T0.9's 3%/hour measurement sudah diambil dengan flag `false`, jadi target tetap valid — baris ini sebelumnya salah mengklaim flag itu aktif dipakai. |
| Leaderboard query response time | p95 < 300ms untuk leaderboard read (dari precomputed table) | Lihat architecture.md §4 — leaderboard **tidak** dihitung live dari raw transaction table saat request masuk. |
| Point submission (run sync) response time | p95 < 1.5s untuk validasi + write PointTransaction | Termasuk anti-cheat check synchronous di request path. |
| Skalabilitas data poin | PointTransaction sebagai append-only ledger, tidak pernah di-update/delete | Memungkinkan audit trail & re-kalkulasi total poin user kapan saja tanpa kehilangan histori. |
| Precompute freshness leaderboard | Interval maksimal 15 menit (selaras dengan AC di product-spec §4.5) | Trade-off sadar antara real-time dan biaya compute; bisa diperketat di v2 kalau perlu. |
| Run status reconciliation read (`GET /api/runs?since=`) | p95 < 300ms; hasil dibatasi 200 baris (ASC + `has_more`); index `(user_id, updated_at)` wajib | Dipanggil hanya saat client punya run `flagged` yang di-watch, dan minimal 15 menit sejak percobaan terakhir (§3 step 7, cadence persisted lintas restart) — bukan tiap app-open/sync-cycle tanpa syarat, supaya tidak jadi endpoint QPS tertinggi tanpa alasan. |

## 5. Fase 1 Feature Additions — Technical Approach (2026-09-12)

Ditambahkan bareng dengan product-spec.md §4.8-4.17 — 9 gap fitur/compliance
yang ditemukan lewat penyisiran kebutuhan implisit (standar App Store,
standar kompetitor, konsistensi persona), bukan scope creep baru. Bagian
ini fokus ke 3 area yang butuh pendekatan teknis eksplisit; item lain
(splits, elevation, auto-pause, crash recovery, refined permission flow)
cukup dijelaskan di scope task masing-masing
(tasks/phase-1-core-loop-offline.md) karena murni reuse data/logic yang
sudah ada (`gps_route`, `stationaryAnchor`, Core Data `Run` entity) tanpa
pendekatan arsitektural baru.

### 5.1 MapKit Integration

**Live map (tracking, product-spec §4.8):** `MKMapView` wrapped via
`UIViewRepresentable` — **locked choice, not SwiftUI `Map`** (2026-09-13,
Round 7 finding B7-7): SwiftUI `Map`'s polyline overlay support
(`MapPolyline`) is iOS 17+, but tech-spec §1 locks the deployment target
at iOS 16.0 (T0.2 DoD) — `MKMapView` is the only option that renders a
polyline without an availability fork. Posisi user & polyline rute
**tidak** meminta lokasi sendiri — keduanya murni membaca state yang
sudah ada, dengan satu perubahan konkret: `RunViewModel` butuh dua
`@Published` properti BARU (current position, live route array) yang
tidak ada hari ini — `lastLocation`/`pendingPoints` saat ini `private`
(2026-09-13, Round 7 finding N7-5, koreksi dari draft sebelumnya yang
salah bilang "tidak butuh perubahan apapun"). Kedua properti baru ini
diisi dari path yang sudah ada (`handle(_:)`'s point-append, T1.2b), jadi
tetap **tidak** ada `CLLocationManager` instance baru dan **tidak** ada
Core Data field baru — hanya state yang di-expose ke View layer yang
sebelumnya tersembunyi.
- Posisi user: **wajib** custom annotation yang di-drive dari
  `RunViewModel`'s properti baru di atas — `MKMapView.showsUserLocation`/
  SwiftUI `UserAnnotation`/`MapUserLocationButton` **dilarang** (2026-09-13,
  Round 7 finding B7-8): API itu memulai subscription lokasi INTERNAL
  MapKit sendiri, tidak muncul di call-site `CLLocationManager` manapun
  di kode app, sehingga melanggar product-spec §4.8 AC3 ("tidak menambah
  GPS request baru") dan architecture.md §3's aturan lapisan (hanya
  Data/Sync layer boleh bicara ke `CLLocationManager`) tanpa terlihat di
  code review.
- Polyline: `MKPolyline` di-render dari titik `gpsRoute` yang sudah
  di-capture, di-update setiap titik baru diterima (sama trigger dengan
  `handle(_:)`'s existing point-append path, T1.2b) — bukan re-fetch atau
  re-compute dari nol tiap frame.

**Static map (Summary/History, product-spec §4.9):** `MKPolyline` dibuat
sekali dari `gpsRoute` yang sudah tersimpan (decode dari `Run.gpsRoute`
Core Data attribute, format sama seperti yang dipakai flush/decode di
`RunViewModel`), di-render read-only (tanpa live location, tanpa update).
Tidak butuh koneksi network atau API key MapKit khusus untuk kasus ini
(pure on-device rendering dari data lokal).

**Kenapa tidak butuh perubahan skema data:** `gps_route`/`Run.gpsRoute`
sudah menyimpan `{lat, lng, timestamp, elevation}` per titik sejak T0.8 —
baik live map maupun static map murni konsumen baru dari data yang sudah
ada, bukan sumber data baru. Tidak ada field baru di `database-api-spec.md`
yang dibutuhkan untuk kedua fitur ini.

**Privacy:** MapKit di iOS tidak butuh App Store Connect API key terpisah
untuk basic map display (beda dari Google Maps Platform) — cukup
`NSLocationWhenInUseUsageDescription`/`NSLocationAlwaysAndWhenInUseUsageDescription`
yang sudah ada di `Info.plist` sejak T0.7.

### 5.2 Notification Scheduling Approach (Streak Reminder)

Product-spec.md §4.16. Pakai `UNUserNotificationCenter` lokal
(`UNCalendarNotificationTrigger` atau `UNTimeIntervalNotificationTrigger`),
**bukan** push notification server-side — tidak butuh backend sama sekali,
konsisten dengan Fase 1 tetap client-only.

**Kenapa bukan reschedule-on-open-saja (2026-09-13, Round 7 finding
B7-6):** draft sebelumnya CUMA menjadwalkan 1 notification, di-cancel
dan di-reschedule "setiap run selesai DAN setiap app dibuka" — cacat
logika: user yang jadi target notification ini (belum lari hari ini,
streak berisiko putus) justru user yang PALING KECIL kemungkinan buka
app hari itu, jadi "reschedule saat app dibuka" tidak pernah sempat
terjadi di hari yang butuh reminder. Fix: jadwalkan **N hari ke depan
sekaligus** (`UNCalendarNotificationTrigger` per tanggal, mis. 7 hari ke
depan), bukan 1 notification yang bergantung pada app dibuka duluan.

**Kapan dijadwalkan ulang:**
1. Setiap kali sebuah run selesai (`stop()`, `RunViewModel.swift`) DAN
   setiap app dibuka (app foreground): cancel SEMUA notification
   streak-reminder yang sudah terjadwal untuk N hari ke depan
   (`removePendingNotificationRequests(withIdentifiers:)`, identifier
   per-tanggal mis. `"streak-reminder-2026-09-14"` — bukan satu
   identifier statis, supaya beberapa hari ke depan bisa terjadwal
   sekaligus tanpa saling menimpa).
2. Untuk tiap hari `d` dari besok sampai N hari ke depan: hitung, KALAU
   user tidak lari di hari `d` (belum terjadi, jadi ini asumsi
   proyeksi — streak diasumsikan berlanjut sampai hari `d`), apakah
   streak akan berisiko putus di hari `d`. Jadwalkan satu
   `UNCalendarNotificationTrigger` untuk hari `d` jam tertentu menjelang
   malam waktu lokal device (mis. 20:00 — angka pasti perlu tuning, sama
   status dengan `STREAK_BONUS_PER_DAY` §2.2, bukan final).
3. Reschedule di langkah 1 memastikan proyeksi selalu direvisi begitu
   ada run baru (yang membatalkan risiko putus untuk hari itu) — tapi
   notification untuk hari-hari MENDATANG tetap terjadwal SEBELUMNYA,
   tidak menunggu app dibuka lagi di hari itu.
4. Kalau device melewati jam terjadwal tanpa app dibuka (notification
   terlanjur terkirim) dan user KEMUDIAN lari sebelum tengah malam,
   tidak ada mekanisme "cancel notification yang sudah terkirim" (iOS
   tidak mengizinkan ini) — ini expected, bukan bug: notification yang
   sudah muncul di Notification Center tetap ada, tapi tidak mengganggu
   apapun secara fungsional.
5. **Keputusan v1 (2026-09-13, Round 7 finding N7-12):** user yang belum
   pernah punya streak sama sekali (`currentStreakDays = 0`, belum
   pernah lari) TIDAK dapat reminder — fitur ini secara eksplisit hanya
   melindungi streak yang SUDAH ada dari putus, bukan mendorong lari
   pertama kali. Mendorong first-run adalah scope onboarding, bukan
   fitur ini.

**Permission:** diminta via `UNUserNotificationCenter.requestAuthorization`
di titik yang kontekstual (bukan langsung app-launch pertama tanpa
alasan) — pattern yang sama dengan location permission (product-spec.md
§4.15, tasks/phase-1-core-loop-offline.md T1.15): jelaskan dulu alasan
sebelum system prompt, bukan sekadar prompt polos. Kalau ditolak, app
tidak retry paksa — cukup skip scheduling langkah 1-2 di atas selamanya
sampai user mengaktifkan manual dari Settings.

### 5.3 Audio Cue Implementation Approach

Product-spec.md §4.13. Pakai `AVSpeechSynthesizer` (Text-to-Speech, bukan
file audio pre-rekam) — alasan: jarak/pace adalah angka yang berubah-ubah
tiap run (mis. "3 kilometer, pace 5 menit 30 detik"), TTS menghindari
kebutuhan merekam/meng-generate ratusan kombinasi file audio statis untuk
tiap kemungkinan angka.

**Trigger point:** dari `RunViewModel`'s existing distance-accumulation
path (`handle(_:)`, tempat `distanceMeters` bertambah) — setiap kali
`distanceMeters` melewati kelipatan 1000m yang belum diumumkan, trigger
satu utterance. Butuh state baru `lastAnnouncedKm: Int` (mirip pola
`lastLocation`/`stationaryAnchor` yang sudah ada) supaya tidak
double-announce kalau GPS update datang lebih dari sekali dalam rentang
km yang sama — dibandingkan `Int(distanceMeters / 1000)` terhadap
`lastAnnouncedKm`, hanya announce kalau nilainya baru & lebih besar.

**Isi pengumuman:** jarak (km bulat yang baru tercapai) + pace saat ini
(dari `avgPaceSecPerKm` yang sudah dihitung live, T1.2b's
`updateCurrentEstimatedPoints` path) — format teks sederhana, tidak perlu
localization kompleks untuk v1 (Bahasa Indonesia saja, sesuai locale app
saat ini).

**Toggle on/off:** disimpan sebagai user preference lokal (`UserDefaults`
cukup untuk single boolean flag ini — tidak butuh Core Data), dicek
sebelum trigger utterance apapun.

**Interaksi dengan audio session lain:** `AVAudioSession` category
**`.playback`** (bukan `.ambient` — koreksi 2026-09-13, Round 7 finding
B7-5: `.ambient` mati total saat app di-background dan disenyapkan oleh
ring/silent switch, padahal §4.13's use case eksplisit adalah "tanpa
harus lihat layar", termasuk layar mati/di-background) dengan opsi
`.duckOthers` — meredupkan musik/podcast sementara saat announce, bukan
mematikannya, karena banyak runner dengar musik sambil lari.

**Background mode wajib (2026-09-13, Round 7 finding B7-5):**
`UIBackgroundModes` di `Info.plist` butuh **`audio`** ditambahkan di
samping `location` yang sudah ada sejak T0.7 — tanpa ini, `AVSpeechSynthesizer`
berhenti berbunyi begitu layar mati/app di-background, yaitu persis
kondisi paling umum saat lari. Lihat pre-launch-checklist.md §10 (App
Store scrutinizes background mode declarations — review notes, §9,
sebaiknya jelaskan kenapa app punya 2 background mode).

## 6. Authentication — Apple + Google (T2.3; Google added 2026-09-21)

Dua provider, satu jalur sesi. **Sign in with Apple** (native, `ASAuthorizationController` → identity token →
`signInWithIdToken`, T2.3) dan **Google** (OAuth generik Supabase). Nol email/password (SEC-15: provider email
dimatikan di project Supabase). Keputusan Apple-only 2026-09-17 dibalik 2026-09-21 — alasan dan batasan di
product-spec.md §4.1 AC1.

**Alur Google (iOS).** `AuthService.signInWithGoogle()` memanggil `client.auth.signInWithOAuth(provider: .google,
redirectTo:)` dari supabase-swift: PKCE, dibuka lewat `ASWebAuthenticationSession`, Google → Supabase
(`/auth/v1/callback`) → redirect ke app. **Bukan** Google Sign-In SDK native: satu jalur kode di `client.auth` yang
sama dengan Apple, jadi sesi mendarat di tempat yang sama (`authStateChanges` → `AuthService.session`) dan tidak ada
kode hilir yang bisa membedakan provider. Konsekuensinya hanya butuh OAuth client tipe **Web** di Google Cloud —
client tipe iOS tidak diperlukan.

**Konfigurasi (bukan kode):**
- Google Cloud project `Laju`: OAuth consent screen (scope non-sensitif `openid`, `userinfo.email`,
  `userinfo.profile`), OAuth client tipe Web dengan redirect URI
  `https://qfjavbrwhfjkjremtvol.supabase.co/auth/v1/callback`. Client Secret hanya ada di Supabase, tidak pernah di
  repo atau di app. Client ID bersifat publik.
- Supabase Auth: provider Google aktif (Client ID terpasang); Redirect URLs allow-list memuat
  `com.designbyripo.laju://auth-callback` (`AuthService.oauthRedirectURL`). Kedua nilai diverifikasi lewat
  `supabase config diff`.
- **Halaman untuk consent screen (2026-09-21):** beranda `/` dan kebijakan privasi `/privacy` disajikan oleh backend Next.js (`app/page.tsx`, `app/privacy/page.tsx`, teks di `lib/legal.ts`) di `https://backend-eight-gules-56.vercel.app`. URL itulah yang diisi di Branding consent screen. Domain `vercel.app` cukup untuk Google, tetapi sebaiknya diganti domain milik sendiri sebelum rilis.
- **Consent screen berstatus Testing** — hanya test user yang bisa login. Harus dipublikasikan ("In production")
  sebelum rilis publik (scope dasar tidak butuh review Google); butuh URL kebijakan privasi (pre-launch-checklist.md §3).

**Backend tidak berubah.** `requireAuthenticatedIdentity` memverifikasi tiap bearer token lewat `auth.getUser` dan
tidak memuat logika per-provider (grep `apple`/`google` di `backend/lib` dan `backend/app` kosong). Hal ini
dibuktikan dengan login Google sungguhan, bukan dengan identitas tiruan: Admin API Supabase menimpa
`app_metadata.provider` menjadi `email`, jadi identitas Google tidak bisa dipalsukan lewat test.

**Batasan yang diterima.** Tidak ada penggabungan akun lintas provider (dua identitas untuk satu orang bila emailnya
berbeda) — SEC-16. Penghapusan akun (T2.22) menghapus identitas Auth apa pun providernya; revokasi token khusus
Apple (pre-launch-checklist.md §4) tidak berlaku untuk Google, yang tidak disimpan Supabase untuk kita.
