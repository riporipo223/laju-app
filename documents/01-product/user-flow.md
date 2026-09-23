# Laju App — User Flow (Final, dengan Freemium/Premium)

**Status: draft standalone, belum diintegrasikan ke product-spec.md /
development-plan.md / tasks.** Dokumen ini berisi eksplorasi
Freemium/Premium + fitur baru (Circle, Social Feed, Cloud Backup, dst) yang
belum direkonsiliasi dengan MVP scope yang sudah settle (lihat
product-spec.md §3/§5 MoSCoW & Non-Goals — beberapa item di sini, misalnya
Circle, sebelumnya ditandai Fase 4 backlog). Simpan di sini dulu sebagai
referensi sampai ada keputusan eksplisit soal integrasi.

**Update 2026-09-12:** Social Feed sekarang punya representasi resmi (tapi
minimal — cuma nama + rekomendasi fase, bukan full breakdown dari draft
ini) di product-spec.md §5 Non-Goals dan tasks/phase-4-backlog.md
T4.15-T4.16. Freemium/Premium tiering, Circle admin tools, Cloud Backup,
dan detail lain di dokumen ini **masih** belum direkonsiliasi — dokumen
ini tetap berstatus draft standalone untuk sisanya.

**Update 2026-09-23:** §2.6 (Circle → Club) sebagian sudah direkonsiliasi ke
product-spec.md §4.24 (siapa boleh membuat club, deskripsi, privasi, cara
join, admin tools & feed ditunda). Kalau berbeda, §4.24 yang berlaku. Sisa
dokumen ini tetap draft.

## 1. Feature Matrix — Final

| Fitur | Freemium | Premium |
|---|---|---|
| Track run (GPS, poin, level, rank naik) | ✅ | ✅ |
| Post pencapaian ke feed | ✅ | ✅ (+ template/badge eksklusif di card) |
| Join circle | ✅ | ✅ |
| Basic run stats (jarak/pace/durasi per-run) | ✅ | ✅ |
| Apple Health sync | ✅ | ✅ |
| Leaderboard — Global, liga sendiri saja ("tier" = Season League, tech-spec.md §2.5) | ✅ | — |
| Leaderboard — Global, semua liga terlihat | ❌ | ✅ |
| Custom profile (foto, bio) | ❌ | ✅ |
| Ganti icon app Laju | ❌ | ✅ |
| ~~Membuat circle~~ | ~~❌~~ | ~~✅~~ — **superseded 2026-09-23**: semua tier boleh membuat club (product-spec.md §4.24) |
| Advanced statistics (tren mingguan/bulanan, personal record history, grafik) | ❌ | ✅ |
| Exclusive badge/cosmetic di profile & post | ❌ | ✅ |
| Seasonal cosmetic reward (bukan bonus poin) | ❌ | ✅ |
| Circle admin tools (analytics circle, buat challenge internal) | ❌ | ✅ (untuk circle yang dia buat) |
| Cloud backup & restore run history | ❌ | ✅ |
| ~~Redemption rate lebih tinggi~~ | — | **Di-skip** — berpotensi kebaca pay-to-win (nyentuh reward tracking), tidak dipakai |

Poin & rank di leaderboard sendiri **sama persis** antara Freemium/Premium — tidak ada fitur yang mengubah kalkulasi/kecepatan naik level. Semua diferensiasi ada di **visibilitas, kustomisasi, dan kenyamanan**, bukan kompetisi.

## 2. User Flow

### 2.1 Onboarding & Signup

```
App dibuka pertama kali
  → Welcome screen (value prop: "Lari yang berasa main game")
  → Penjelasan singkat kenapa butuh izin lokasi
  → System permission prompt: Location "Always"
    ├─ Granted → lanjut Sign Up
    └─ Denied → layar "tracking background tidak optimal" + tombol buka Settings
  → Sign Up: dua tombol — "Sign in with Apple" dan "Sign in with Google" (keputusan 2026-09-21, membalik Apple-only; tanpa email/password)
  → (Opsional) tanya target segment (progress/aspiring/community runner) — untuk personalisasi, tidak wajib
  → Landing di Home
```

### 2.2 Core Loop — Track Run

```
Home (tombol besar "Mulai Lari")
  → Tap Start
  → Run Tracking: live distance/pace/duration
    ├─ Pause → Resume
    └─ Stop → konfirmasi "Selesai lari?"
  → Run Summary: jarak, durasi, pace, poin didapat
    ├─ Level naik? → level-up moment (visual, bukan notif kecil)
    ├─ Flagged (anomali)? → status "sedang diverifikasi" (poin belum final)
    └─ CTA: "Post pencapaian" / "Kembali ke Home"
```

### 2.3 Leaderboard

```
Tab Leaderboard (Global — satu-satunya leaderboard di v1)
  → Freemium: tampil leaderboard Global untuk liga sendiri saja (Season League: Bronze/Silver/Gold/Platinum, dari poin season berjalan, reset tiap season — tech-spec.md §2.5). Toggle "Liga sendiri / Semua liga" → "Semua liga" locked + CTA upgrade
  → Premium: toggle "Liga sendiri / Semua liga", semua liga di Global terlihat
```

> **Diubah 2026-09-21:** sebelumnya flow ini punya toggle **Global ↔ Local**
> (sub-filter kecamatan/kabupaten-kota/provinsi) sebagai pembeda
> Freemium/Premium. Local Leaderboard **dipotong dari MVP v1** dan ditunda
> ke v1.1 / Fase 4 (butuh kepadatan user tinggi — product-spec.md §4.6), jadi
> toggle itu dihapus dari desain v1; diferensiasi kini murni di dalam Global
> (product-spec.md §4.5 AC4). **Local sebagai state masa depan:** begitu
> dikerjakan, toggle Global ↔ Local kembali di sini — belum perlu didesain
> sekarang. Desain layar Local yang sudah ada (scope filter, state "belum
> cukup data") tetap tersimpan di 06-design/wireframe-spec.md §6, ditandai
> deferred.

### 2.4 Profile & Customization

```
Tab Profile
  → Tampil: level, progress bar, total poin, riwayat run
  → Freemium: foto/bio locked (default avatar) + CTA upgrade. Icon app locked + preview.
  → Premium: edit foto/bio bebas, pilih varian icon app (alternate app icon)
  → Premium only: badge eksklusif ditampilkan di profile (dari achievement/seasonal reward)
```

### 2.5 Advanced Statistics (Premium)

```
Dari Profile → tab "Statistik" (Freemium lihat versi terbatas: cuma total lifetime; Premium lihat penuh)
  → Premium:
      Grafik tren pace mingguan/bulanan
      Personal record history (jarak terjauh, pace tercepat, dst — dengan tanggal & konteks run)
      Perbandingan periode (bulan ini vs bulan lalu)
  → Freemium yang tap area locked → CTA upgrade dengan preview grafik (blur/sample) biar kelihatan value-nya
```

### 2.6 Circle

```
Tab Circle
  → Belum join/buat apapun:
      Freemium: tombol "Cari Circle" saja
      Premium: tombol "Cari Circle" + "Buat Circle Baru"
  → Buat Circle (Premium):
      Nama, deskripsi, privasi (publik/invite-only) → jadi admin otomatis
  → Join Circle (semua tier):
      Browse publik / masukkan kode invite → request join atau langsung masuk
  → Di dalam Circle:
      Member list, leaderboard internal circle, feed circle
  → Circle Admin Tools (Premium, khusus circle yang dia buat sendiri):
      Analytics circle (aktivitas member, total distance circle, dst)
      Buat challenge internal (misal: "500km bareng bulan ini")
```

### 2.7 Social Feed / Posting (semua tier)

```
Dari Run Summary atau tab Feed
  → Tap "Post pencapaian"
  → Card otomatis ter-generate (jarak/pace/poin/badge level-up)
  → Premium: opsi template card lebih variatif, badge eksklusif tampil di card
  → Tambah caption (opsional)
  → Pilih audience: Public / Circle saja / Private (simpan aja)
  → Post tampil di feed sesuai audience
  → User lain: like, lihat profile poster
```

### 2.8 Seasonal Cosmetic Reward (Premium)

```
Season berakhir (trigger otomatis sistem, bukan aksi user)
  → Notifikasi: "Season berakhir — reward kamu siap"
  → Premium user dengan rank tertentu di season itu → dapat cosmetic reward (frame profile khusus, badge season)
  → Freemium: tetap dapat hasil rank season (Fase 3 core feature, gratis), tapi tanpa cosmetic tambahan
  → Reward otomatis ter-apply ke profile, muncul di Profile screen
```

### 2.9 Cloud Backup & Restore (Premium)

```
Settings → Cloud Backup (Premium only, locked untuk Freemium + CTA upgrade)
  → Toggle "Auto backup run history"
  → Kalau ganti device / reinstall app:
      Sign in → deteksi ada backup tersedia → prompt "Restore run history?"
      → Ya → data run lama sinkron kembali
      → Tidak → mulai fresh
```

### 2.10 Apple Health Sync (semua tier)

```
Onboarding (opsional, atau dari Settings kapan saja)
  → Toggle "Sync ke Apple Health"
  → System permission prompt HealthKit
  → Granted → tiap run selesai, otomatis ditulis ke Apple Health (jarak, kalori, durasi)
```

### 2.11 Upgrade Flow (Freemium → Premium)

```
CTA muncul di titik locked feature (leaderboard semua liga, custom profile, buat circle, advanced stats, cloud backup)
  → Tap CTA → Paywall screen: value proposition konkret per fitur locked yang relevan sama konteks user tap dari mana
  → Pilih paket (bulanan/tahunan, diskon tahunan)
  → StoreKit in-app purchase (wajib, Apple mengharuskan untuk digital subscription)
  → Sukses → unlock instant, highlight fitur yang baru kebuka
```

## 3. Belum diputuskan (di luar scope diskusi ini)

- Harga & struktur paket (bulanan/tahunan) — belum dibahas
- Apakah Circle dimajukan ke scope aktif sekarang atau tetap Fase 4 backlog (masih pending dari diskusi sebelumnya)
