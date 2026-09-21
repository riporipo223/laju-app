import type { Metadata } from "next";
import Link from "next/link";
import { CONTACT_EMAIL, PRIVACY_LAST_UPDATED, privacyEnglishSummary, privacySections } from "@/lib/legal";

export const metadata: Metadata = {
  title: "Kebijakan privasi",
  description: "Data apa yang Laju kumpulkan, untuk apa, berapa lama disimpan, dan bagaimana menghapusnya.",
};

/** Public privacy policy — the URL the Google OAuth consent screen and App Store Connect require. Text lives in `lib/legal.ts`. */
export default function PrivacyPage() {
  return (
    <>
      <p>
        <Link href="/">← Laju</Link>
      </p>
      <h1>Kebijakan privasi</h1>
      <p className="meta">Terakhir diperbarui: {PRIVACY_LAST_UPDATED}</p>

      {privacySections.map((section) => (
        <section key={section.id} id={section.id}>
          <h2>{section.title}</h2>
          {section.paragraphs.map((paragraph) => (
            <p key={paragraph}>{paragraph}</p>
          ))}
          {section.bullets && (
            <ul>
              {section.bullets.map((bullet) => (
                <li key={bullet}>{bullet}</li>
              ))}
            </ul>
          )}
        </section>
      ))}

      <section id="english" lang="en">
        <h2>Summary in English</h2>
        {privacyEnglishSummary.map((line) => (
          <p key={line}>{line}</p>
        ))}
      </section>

      <footer>
        Kontak: <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>
      </footer>
    </>
  );
}
