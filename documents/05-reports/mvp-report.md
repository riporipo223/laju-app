# Laju App — MVP Report

## 1. Vision
Membangun running app dengan gamefikasi yang membuat pelari termotivasi
untuk konsisten lewat progres personal, kompetisi, dan komunitas — mengisi
gap antara "social logging tool" (Strava) dan "game-first fitness
experience" yang belum ada pemain kuat di pasar Indonesia.

## 2. Target User
- **Progress runner** — termotivasi oleh progres pribadi (poin, level);
  cocok jadi first adopter karena tidak butuh social graph untuk merasakan
  value inti
- **Community runner** — suka bersosialisasi, entertain lifestyle
- **Aspiring runner** — mau lari tapi belum punya habit/motivasi; segmen
  paling besar potensinya tapi paling sulit di-retain tanpa struktur reward
  yang jelas sejak sesi pertama

## 3. Value Proposition (Core Loop)
Track Run → Earn Point → Level Up → Leaderboard Placement → Feel Progress →
Run Again

Loop ini harus tervalidasi *single-player* dulu (tanpa fitur sosial) sebelum
invest ke leaderboard/circle — kalau "dapat poin & naik level" saja belum
terasa rewarding secara individual, menambah lapisan sosial di atasnya
justru menutupi masalah inti alih-alih menyelesaikannya.

## 4. Core Features

**Core / Foundation**
1. Track run (GPS system) — reliability jadi prioritas nomor satu, karena
   satu run yang gagal ke-track = kepercayaan user langsung turun
2. Point system — formula transparan + anti-cheat dari awal
3. Rank & Leaderboard

Formula: Lari → dapat Poin → Placing → Level/Rank → Leaderboard

**Nice to have (bukan untuk v1)**
1. Circle / Clan / Club
2. Club war
3. System matchmaking antar club

## 5. Core Product Loop
Track Run → Poin bertambah → Naik level → Positioning di Leaderboard
(Global; Local — Kecamatan → Kabupaten/Kota → Provinsi — ditunda ke v1.1, keputusan 2026-09-21) → Progress terbentuk →
Run again

## 6. Assumptions to Validate (v1)
- Progress runner mau lari lagi hanya karena naik poin/level, tanpa elemen
  sosial — ini asumsi paling kritikal, jadi fokus utama testing MVP
- ~~Leaderboard lokal (granular sampai kecamatan) punya cukup kepadatan user
  di fase awal untuk terasa relevan, bukan kosong~~ — **tidak lagi diuji di
  v1 (2026-09-21):** asumsi ini dijawab dengan keputusan produk, bukan dengan
  eksperimen — Local Leaderboard ditunda ke v1.1 justru karena kepadatan awal
  hampir pasti terlalu rendah. Leaderboard Global tetap diuji.
- Background GPS tracking native (`CLLocationManager`, iOS) cukup reliable
  & battery-efficient untuk use case run 30-60 menit tanpa user komplain
  drain baterai — divalidasi lewat T0.9 (physical device test)

## 7. Out of Scope untuk v1
- Circle/Clan, Club War, Matchmaking — semua fitur sosial ditunda sampai
  core loop individual tervalidasi
- Monetisasi (Freemium/Premium/B2B) — fokus dulu ke retention, monetisasi
  baru relevan setelah ada basis user aktif
- Android — ditunda tanpa timeline pasti; v1 launch iOS-exclusive
  (tech-spec.md §1)

## 8. Future Development
- Circle/Clan system dan Club War
- Matchmaking antar club berdasarkan performa
- Local leaderboard 3-tier (kecamatan/kabupaten-kota/provinsi) — **v1.1 /
  Fase 4**, dipindah dari Fase 3 pada 2026-09-21 (butuh kepadatan user
  tinggi; task T3.2–T3.5 disimpan di tasks/phase-4-backlog.md). Setelah itu:
  ekspansi hyperlocal di luar kecamatan/kabupaten-kota/provinsi (mis.
  kelurahan/desa) begitu density user cukup.
- Monetisasi Premium & B2B (dashboard club/EO)
- Android support — ditunda tanpa timeline (bukan technical debt; keputusan
  platform, lihat tech-spec.md §1)
- Live Activities, Dynamic Island, HealthKit, WidgetKit — kapabilitas native
  yang baru relevan sekarang app sudah Swift-native, eksplisit bukan v1
  scope (tech-spec.md §1)

## Sumber data
Business of Apps — Strava Revenue and Usage Statistics 2026; TechCrunch,
"Strava eyes IPO as Gen Z trades dating apps for running clubs" (Okt 2025)
