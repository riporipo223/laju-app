# Laju App — Lean Canvas

## 1. Problem Statement

Masyarakat mulai menerapkan gaya hidup sehat lewat lari — tapi masalahnya bukan
di niat awal, melainkan di konsistensi. Data pasar mendukung ini: Strava
tumbuh sampai ~50 juta MAU di 2025 (hampir 2x kompetitor terdekat), tapi
engagement-nya digerakkan oleh mekanisme sosial (kudos, sharing, comparison
sesama teman) — bukan sistem progres personal. Runner yang tidak punya
lingkaran sosial aktif di app tersebut cenderung kehilangan motivasi begitu
"rasa baru"-nya habis.

Insight kunci: ketika Strava mewajibkan user set goal eksplisit, tingkat
keberhasilan mencapai goal tersebut mencapai 72% — jauh di atas rata-rata
app wellness lain. Ini membuktikan bahwa struktur (goal, progres yang
terlihat, milestone) bekerja lebih efektif daripada sekadar logging sosial.
Laju mengambil insight ini dan membangunnya sebagai *core mechanic*, bukan
fitur tambahan: gamefikasi lewat Poin, Rank, Level, dan Leaderboard membuat
progres personal terasa nyata setiap sesi lari, terlepas dari ada tidaknya
circle sosial di sekitar user.

**Gap yang dieksploitasi:** Strava & Nike Run Club = social logging tool.
Laju = progression system (mirip RPG/game), dengan lari sebagai aksi utama
untuk "leveling up". Ini kategori berbeda, bukan sekadar Strava-clone.

## 2. Customer Segments

**Primary User**
- **Progress Runner** — termotivasi oleh angka & progres personal (poin,
  rank, level), tipikal orang yang suka checklist/achievement system
- **Aspiring Runner** — niat lari ada, habit belum terbentuk; butuh
  external structure/reward loop supaya lari terasa punya "tujuan" tiap sesi
- **Community Runner** — suka bersosialisasi lewat aktivitas fisik,
  termotivasi oleh validasi sosial & kompetisi ringan antar teman/club

**Secondary User**
- Running club — butuh tools untuk kelola member & kompetisi internal
- ~~Event organizer (EO) — butuh platform partisipasi & leaderboard untuk event~~
  ~~**Direframe 2026-09-23 (ADR-0014):** EO bukan pengguna dashboard aktif — EO adalah **klien yang
  meminta** (requesting client), bukan yang mengoperasikan tool sendiri. Event-scale reach (partisipasi
  & leaderboard yang menjangkau seluruh/sebagian besar user base) bersifat Laju-exclusive di semua
  tier, tidak ada self-serve. Tim Laju sendiri yang membuat dan mengelola event untuk EO (managed
  service), bukan EO login dan mengelola sendiri. Nama "Dashboard untuk EO" kemungkinan sudah tidak
  akurat lagi — open question, belum diputuskan nama penggantinya.~~
  **Konsep diganti total 2026-09-23 — "EO managed service" bukan lagi model yang dipakai.**
  Segmen sekunder yang benar adalah **Brand/Sponsor**, bukan Event Organizer: brand membayar Laju
  untuk exposure lewat **Laju Branded Events** (product-spec.md §4.21) — Laju's own team yang
  membuat Event, brand tidak pernah dapat akses apapun ke sistem Laju (ADR-0014 tetap berlaku: no
  self-serve, whole-user-base reach tetap Laju-exclusive). Brand hanya berperan sebagai sponsor yang
  menyediakan reward dan menangani registrasi/distribusi reward di platform mereka sendiri
  (redirect eksternal) — lihat detail lengkap di §6 dan product-spec.md §4.21. Digabung ke baris
  "Sports brand" di bawah, bukan entitas terpisah.
- Government — potensi partner untuk program kesehatan masyarakat berbasis
  data aktivitas fisik daerah
- **Sports brand / sponsor** — sponsor Laju Branded Events (product-spec.md §4.21) untuk exposure ke
  seluruh user base; juga potensi sponsor season/challenge terpisah, brand placement di reward

## 3. Unique Value Proposition

**"Lari yang berasa seperti main game, bukan sekadar logging."**

Gamefikasi lewat: Point System, Rank, Level, Season, Leaderboard Global
(~~Leaderboard Local ditunda ke v1.1, keputusan 2026-09-21~~ **Leaderboard
Local dibatalkan permanen 2026-09-22** — lihat product-spec.md §4.6). Beda dari kompetitor yang gamefikasinya cuma badge
kosmetik (Nike Run Club) atau sosial-driven (Strava kudos) — Laju punya
sistem progres persisten dengan konsekuensi nyata (naik/turun rank per
season; dengan user awal yang masih sedikit, leaderboard Global sendiri
sudah terasa dekat secara geografis).

## 4. Solution

**MVP (Core)**
- GPS run tracking system (native `CLLocationManager`, iOS-exclusive v1 —
  lihat tech-spec.md §1, product-spec.md §5 Non-goals)
- Point system dengan formula transparan (lihat catatan formula di bawah)
- Rank & Level (progression permanen + reset per season untuk kompetisi adil)
- Global leaderboard
- ~~Local leaderboard~~ — **dibatalkan permanen 2026-09-22 (PM sign-off),
  bukan bagian MVP, tidak akan pernah dikerjakan.** ~~(Sebelumnya: ditunda
  ke v1.1 / Fase 4, keputusan 2026-09-21, butuh kepadatan user tinggi
  supaya berguna.)~~ Alasan pembatalan: scope terlalu luas untuk logic
  leaderboard yang dibutuhkan. Spesifikasi lama disimpan sebagai catatan
  sejarah saja: granularity kecamatan → kabupaten/kota →
  provinsi, mengikuti hierarki administratif Indonesia ("daerah" dan
  campuran kabupaten/kota sebagai tier terpisah dihapus, lihat
  database-api-spec.md)
- Season competition (siklus reset berkala, mendorong re-engagement)

**Nice to have (v2+)**
- ~~Circle / Clan / Group~~ **Renamed "Club" 2026-09-23** — sudah selaras dengan `club_id` di skema
  DB (database-api-spec.md §1). Lihat product-spec.md §4.19.
- ~~Circle war~~ **Club War — CONFIRMED TO BUILD 2026-09-23** (bukan lagi "nice to have", lihat
  product-spec.md §4.19: max 3 club per Club War, self-serve oleh owner/admin Club Premium).
  ~~Mekanik/win-condition/durasi masih open question.~~ **Mekanisme finalized 2026-09-23**: basis
  menang Participation Rate (sama seperti §4.20 Club Aktif), durasi 48 jam, mulai lewat tantangan
  tertarget (bukan matchmaking) — lihat product-spec.md §4.19 untuk detail lengkap AC1-AC12.
  **AC7 resolved 2026-09-23**: tantangan yang ditolak/timeout 24 jam dianggap tidak pernah terjadi,
  nol entri di Club War Record untuk siapapun — bukan forfeit.
- Matchmaking antar club berbasis performa — masih Non-goal, belum ada keputusan bentuknya.

**Catatan formula poin (perlu divalidasi, bukan final):**
Poin dasar = fungsi dari jarak (km) × konsistensi pace, dengan bonus untuk
konsistensi mingguan (streak). Perlu ada pace cap/anomaly detection sejak
awal untuk mencegah exploit (GPS spoofing, treadmill-simulasi-lari-cepat) —
ini risiko yang tidak muncul di notes awal tapi krusial untuk sistem
berbasis poin/leaderboard kompetitif.

## 5. Channels
- Instagram, TikTok (konten progres/achievement — natural fit untuk
  gamified content, screenshot rank-up sangat shareable)
- Campus community (early adopter pool: mahasiswa, target awal yang murah
  diakuisisi lewat komunitas lari kampus)
- Kolaborasi dengan running club lokal existing sebagai secondary channel
  sekaligus validasi B2B

## 6. Revenue Streams
- **Freemium** — semua fitur dasar gratis (tracking, poin, rank, leaderboard)
- **Premium** — Seasonal pass, Advanced statistics, Exclusive badge, Premium
  profile (referensi: Discord Nitro model — kosmetik/status, bukan pay-to-win).
  **Harga DECIDED 2026-09-23**: $7.99/bulan (harga referensi USD), harga
  regional lewat App Store Connect's price-tier localization sendiri —
  bukan sistem konversi kurs custom, ini tugas konfigurasi store, bukan
  engineering. Lihat product-spec.md §5 (baris Monetisasi). **Paket v1
  (2026-09-23): bulanan saja — tanpa paket tahunan, tanpa free trial**,
  keputusan sadar membatasi scope. Infrastruktur langganannya (StoreKit +
  verifikasi server) belum ada sama sekali — product-spec.md §4.23 / T4.20.
- **B2B — running club**: Dashboard untuk running club (kelola member,
  leaderboard privat) — model tetap tool self-serve, tidak berubah.
- ~~**B2B — event organizer**: Dashboard untuk event organizer (partisipasi,
  hasil real-time)~~ ~~**Direframe 2026-09-23 (ADR-0014), lihat §2**: bukan lagi
  tool-subscription. EO tidak dapat akses dashboard sendiri — model jadi
  **per-event service fee**: tim Laju yang membuat dan mengelola event untuk
  klien EO. Harga pastinya belum diputuskan — open question, ini baru
  perubahan model (managed service vs self-serve tool), bukan angka harga.~~
  **Konsep diganti total 2026-09-23 — bukan lagi "EO service fee".** Model revenue yang benar:
  **sponsorship fee** — brand/sponsor membayar Laju untuk exposure ke seluruh user base lewat
  sebuah **Laju Branded Event** (product-spec.md §4.21), bukan membayar Laju untuk *mengelola event
  bagi klien EO*. Ini integrated sponsored advertising (brand membeli visibilitas di card feed
  Events, ditandai "Sponsored"), bukan B2B managed-service. Laju tidak menangani registrasi maupun
  distribusi reward untuk Event sponsored — itu tanggung jawab sponsor sepenuhnya di platform
  eksternal mereka; yang dijual ke sponsor murni exposure/reach, bukan operasional event.
  **Harga sponsorship fee belum diputuskan — open question**, sama seperti sebelumnya ini baru
  perubahan model, bukan angka harga.

**Catatan strategis:** hindari monetisasi yang merusak fairness leaderboard
(pay-to-win) — ini akan merusak kredibilitas kompetisi yang jadi core value
proposition.

## 7. Cost Structure
- Cloud infrastructure (scaling seiring jumlah user & aktivitas GPS)
- Big data / analytics pipeline (leaderboard real-time butuh query cepat
  atas volume data run yang terus tumbuh)
- ~~Maps API (biaya per-request...)~~ — **koreksi (2026-09-12):** asumsi
  awal ini mengira app akan pakai Google Maps Platform/Mapbox berbayar.
  Setelah live map + static route map masuk scope Fase 1 (product-spec.md
  §3/§4.8-4.9), keputusan teknisnya adalah **MapKit** (native Apple,
  tech-spec.md §1) — tidak ada biaya per-request sama sekali, sudah
  termasuk dalam Apple Developer Program fee yang sudah ada di daftar ini.
  Item cost ini dihapus dari daftar, bukan diganti nilainya — net
  pengurangan cost structure, bukan penambahan.
- Backend
- Mobile development (native Swift/SwiftUI, iOS-exclusive v1 — tech-spec.md
  §1; tidak ada cross-platform savings karena Android ditunda tanpa
  timeline, lihat §8 Future Development di mvp-report.md)
- Apple Developer Program fee (tahunan, wajib untuk App Store distribution
  & TestFlight)
- Data storage
- Anti-cheat/anomaly detection (item baru — dibutuhkan begitu leaderboard
  jadi kompetitif, bukan opsional)
- **Redis hosting (item baru, 2026-09-23)** — Redis-backed leaderboard
  **CONFIRMED TO BUILD** (product decision, resolves architecture.md §4's
  Open Question; sebelumnya kondisional "hanya jika precompute 15-menit
  terbukti tidak cukup di scale", sekarang dianggap terpenuhi/moot oleh
  keputusan produk, bukan oleh data pengukuran nyata). Contoh provider:
  Upstash, dipilih karena kompatibel dengan Vercel serverless. Harga/tier
  belum diputuskan.

## 8. Key Metrics / Success Metrics
- DAU/WAU dan rasio DAU/MAU (indikator stickiness, bukan cuma jumlah user)
- Total distance per user
- Average run per user
- User consistency (streak retention — proxy langsung untuk validasi core
  value proposition: apakah gamefikasi benar-benar bikin orang lari lagi?)
- D7/D30 retention (metrik paling penting untuk MVP — validasi core loop
  sebelum invest ke fitur sosial/B2B)
- Total club
- Premium conversion rate

## 9. Unfair Advantage
Banyak user = banyak data. Data ini membuat:
- Leaderboard lebih akurat (distribusi tier yang representatif)
- ~~Kompetisi lokal lebih relevan (cukup data untuk leaderboard granular per
  kecamatan/kabupaten-kota, bukan cuma nasional yang terasa jauh dari user
  biasa) — inilah yang membuat Local Leaderboard layak dikerjakan
  *setelah* basis user besar (ditunda ke v1.1, 2026-09-21)~~ **Tidak lagi
  berlaku (Local Leaderboard dibatalkan permanen 2026-09-22, lihat
  product-spec.md §4.6) — poin ini dihapus dari strategi Unfair Advantage,
  bukan sekadar ditunda menunggu basis user besar.**
- Sistem season lebih adil (matchmaking/tier placement berbasis histori
  performa aktual, bukan asumsi)
- Matchmaking berdasarkan performa nyata

Selain data, mover-advantage di kategori "gamified running" (bukan sekadar
"running app") relatif kosong di pasar Indonesia — kompetitor besar (Strava,
NRC) tidak memposisikan diri sebagai game-first product.

## Sumber data
Business of Apps — Strava Revenue and Usage Statistics 2026; TechCrunch,
"Strava eyes IPO as Gen Z trades dating apps for running clubs" (Okt 2025)
