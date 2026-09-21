import Link from "next/link";
import { APP_NAME, CONTACT_EMAIL } from "@/lib/legal";

/** Public home page — the "application home page" the Google OAuth consent screen and App Store Connect ask for. */
export default function HomePage() {
  return (
    <>
      <h1>
        Lari yang berasa <span className="accent">main game.</span>
      </h1>
      <p className="lead">
        {APP_NAME} mengubah setiap lari jadi progres: tiap kilometer dapat poin, tiap poin membawamu naik level, dan
        papan peringkat menunjukkan posisimu.
      </p>

      <div className="card">
        <strong>Track</strong>
        <p>GPS mencatat jarak, pace, dan rute lari-mu, bahkan saat layar terkunci.</p>
      </div>
      <div className="card">
        <strong>Earn points</strong>
        <p>Makin jauh dan konsisten, makin banyak poin. Poin dihitung dan diperiksa di server supaya adil.</p>
      </div>
      <div className="card">
        <strong>Level up</strong>
        <p>Kumpulkan poin, naik level, dan bersaing di papan peringkat tiap season.</p>
      </div>

      <p className="meta">Laju untuk iPhone. Segera hadir di App Store.</p>

      <footer>
        <Link href="/privacy">Kebijakan privasi</Link> · Kontak: <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>
      </footer>
    </>
  );
}
