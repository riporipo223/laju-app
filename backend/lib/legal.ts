/**
 * The text of Laju's public privacy policy, as data. The page (`app/privacy/page.tsx`) only renders it, so the wording can
 * be tested and kept honest against what the system really does. Every statement below was written from the code and
 * documents, not from a template:
 *  - what is collected: `POST /api/runs`, `POST /api/profile/complete`, the Supabase Auth identity (database-api-spec.md §1);
 *  - what deletion does: `lib/account-deletion.ts` (route erased, personal fields cleared, ledger kept, identity removed);
 *  - where it runs: Supabase project in ap-southeast-1 and Vercel functions pinned to sin1 (Singapore) — i.e. outside Indonesia;
 *  - retention: there is NO time-based deletion today (security-review.md SEC-1 is still an open decision), so the policy
 *    states the real behaviour — kept until the user deletes the account — rather than an invented period.
 *
 * This is the developer's draft, not legal advice: it has to be reviewed by the owner (and, ideally, by someone who knows
 * UU PDP No. 27/2022) before the app ships.
 */

export const CONTACT_EMAIL = "designbyripo@gmail.com";
export const PRIVACY_LAST_UPDATED = "21 September 2026";
export const APP_NAME = "Laju";

export interface PolicySection {
  id: string;
  title: string;
  paragraphs: string[];
  bullets?: string[];
}

export const privacySections: PolicySection[] = [
  {
    id: "siapa-kami",
    title: "1. Siapa kami",
    paragraphs: [
      "Laju adalah aplikasi iOS untuk mencatat lari, mengumpulkan poin, naik level, dan bersaing di papan peringkat. Kebijakan ini menjelaskan data apa yang Laju kumpulkan, untuk apa, siapa yang memprosesnya, berapa lama disimpan, dan apa yang bisa kamu lakukan.",
      `Pertanyaan apa pun tentang privasi: ${CONTACT_EMAIL}.`,
    ],
  },
  {
    id: "data-yang-dikumpulkan",
    title: "2. Data yang kami kumpulkan",
    paragraphs: ["Hanya data yang dibutuhkan agar fitur-fitur Laju berjalan:"],
    bullets: [
      "Akun: pengenal akun dari Apple atau Google yang kamu pakai untuk masuk, dan alamat email yang diberikan penyedia login itu (Apple bisa menyamarkannya). Kami tidak menyimpan kata sandi karena Laju tidak memakai email dan kata sandi.",
      "Profil: nama panggilan dan wilayah (kecamatan, kabupaten/kota, provinsi) yang kamu isi saat pertama kali masuk.",
      'Lokasi presisi: dipakai untuk merekam jalur lari. Laju meminta izin lokasi saat app dipakai dan, agar lari tetap tercatat saat layar terkunci, izin "Selalu". Di luar lari, Laju hanya memakai satu pembacaan lokasi untuk memusatkan peta.',
      "Data lari: jalur GPS (titik koordinat, waktu, dan ketinggian), jarak, durasi, pace, poin yang diberikan, level, serta hasil pemeriksaan anti-curang (status lari, tanda anomali, dan skor kepercayaan).",
    ],
  },
  {
    id: "tidak-dikumpulkan",
    title: "3. Yang tidak kami lakukan",
    paragraphs: [
      "Laju tidak menampilkan iklan, tidak memakai SDK analitik atau pelacak pihak ketiga, tidak menjual data pribadimu, dan tidak melacakmu di app atau situs lain.",
    ],
  },
  {
    id: "tujuan",
    title: "4. Untuk apa data dipakai",
    paragraphs: [],
    bullets: [
      "Merekam dan menghitung lari, poin, dan level.",
      "Menampilkan papan peringkat. Nama panggilan dan poinmu terlihat oleh pengguna lain di papan peringkat; jalur GPS dan wilayahmu tidak.",
      "Mencegah kecurangan (misalnya kecepatan yang tidak masuk akal) dengan memeriksa jalur lari yang dikirim.",
      "Menjalankan akunmu: masuk, menyimpan progres, dan menghapus akun.",
    ],
  },
  {
    id: "pihak-pemroses",
    title: "5. Siapa yang memproses data",
    paragraphs: ["Kami memakai penyedia berikut untuk menjalankan Laju. Mereka memproses data atas nama kami:"],
    bullets: [
      "Supabase: basis data dan autentikasi. Server berada di Singapura.",
      "Vercel: hosting API Laju. Fungsi dijalankan di wilayah Singapura.",
      "Apple dan Google: layanan masuk (Sign in with Apple, Sign in with Google) sesuai pilihanmu, tunduk pada kebijakan privasi masing-masing.",
      "Apple Maps (MapKit): menampilkan peta di app, tunduk pada kebijakan privasi Apple.",
    ],
  },
  {
    id: "transfer",
    title: "6. Data di luar Indonesia",
    paragraphs: [
      "Karena server berada di Singapura, datamu diproses di luar Indonesia. Kami hanya memakai penyedia yang melindungi data dengan enkripsi saat transit dan pembatasan akses, dan tidak membuka basis data ke publik.",
    ],
  },
  {
    id: "retensi",
    title: "7. Berapa lama data disimpan",
    paragraphs: [
      "Saat ini kami belum menerapkan penghapusan otomatis berdasarkan waktu. Data lari, termasuk jalur GPS, disimpan di perangkatmu selama app terpasang dan di server kami selama akunmu ada. Semuanya dihapus atau dianonimkan saat kamu menghapus akun (lihat bagian berikut). Jika kebijakan penyimpanan berjangka diterapkan, halaman ini akan diperbarui sebelum berlaku.",
    ],
  },
  {
    id: "hapus-akun",
    title: "8. Menghapus akunmu",
    paragraphs: [
      'Kamu bisa menghapus akun kapan saja dari dalam app: tab Profil, lalu "Hapus akun", dan konfirmasi. Yang terjadi di server:',
    ],
    bullets: [
      "Jalur GPS semua larimu dihapus.",
      "Nama panggilan, nama tampilan, alamat email, foto, dan wilayahmu dihapus atau diganti dengan pengganti anonim.",
      "Identitas login (akun Apple/Google yang tertaut ke Laju) dihapus, sehingga token lama tidak bisa dipakai lagi.",
      "Catatan poin dipertahankan tanpa identitas pribadi. Buku poin bersifat tetap agar papan peringkat dan riwayat poin tetap konsisten; setelah penghapusan ia tidak lagi bisa dikaitkan denganmu. Ringkasan lari (jarak, durasi, poin, status) dan skor turunan dipertahankan dengan cara yang sama.",
      "Data di perangkatmu dihapus oleh app saat proses selesai.",
    ],
  },
  {
    id: "hakmu",
    title: "9. Hakmu",
    paragraphs: [
      `Kamu berhak meminta akses, salinan, perbaikan, atau penghapusan datamu, dan menarik persetujuan. Penghapusan bisa kamu lakukan sendiri di app. Untuk permintaan lain, hubungi ${CONTACT_EMAIL}; kami akan menjawab dalam waktu yang wajar. Izin lokasi bisa kamu cabut kapan saja di Pengaturan iOS (perekaman lari lalu tidak berfungsi).`,
    ],
  },
  {
    id: "keamanan",
    title: "10. Keamanan",
    paragraphs: [
      "Data dikirim lewat koneksi terenkripsi (HTTPS). Basis data tidak dapat diakses langsung oleh publik; semua akses lewat API kami yang memeriksa siapa kamu, dan kami membatasi frekuensi permintaan untuk mencegah penyalahgunaan. Tidak ada sistem yang sepenuhnya kebal; jika terjadi insiden yang memengaruhimu, kami akan memberi tahu sesuai ketentuan yang berlaku.",
    ],
  },
  {
    id: "usia",
    title: "11. Usia",
    paragraphs: ["Laju ditujukan untuk pengguna berusia 13 tahun ke atas."],
  },
  {
    id: "perubahan",
    title: "12. Perubahan kebijakan",
    paragraphs: [
      `Jika kebijakan ini berubah, tanggal "terakhir diperbarui" ikut berubah. Perubahan yang material akan kami umumkan di app. Terakhir diperbarui: ${PRIVACY_LAST_UPDATED}.`,
    ],
  },
];

export const privacyEnglishSummary: string[] = [
  "Laju is an iOS running app. Summary in English — the Indonesian text above is the authoritative version.",
  "We collect: your Apple or Google sign-in identifier and email, a nickname and region you enter, precise location and the GPS route of each run (only to record it), and run statistics with anti-cheat results.",
  "We do not show ads, use third-party analytics or trackers, or sell personal data. Your nickname and points are visible to other users on the leaderboard; your GPS route and region are not.",
  "Processors: Supabase (database and authentication, Singapore), Vercel (API hosting, Singapore), Apple and Google (sign-in), Apple Maps (maps). Data is therefore processed outside Indonesia.",
  "Retention: there is no automatic time-based deletion today. Run data is kept on your device while the app is installed and on our servers while your account exists; deleting your account erases all GPS routes, clears your nickname, display name, email and region, removes your sign-in identity, and keeps only an identity-free points ledger.",
  `You can delete your account inside the app (Profile → Hapus akun). For access, copy, correction or any other request: ${CONTACT_EMAIL}.`,
];
