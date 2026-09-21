import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "Laju — lari yang berasa main game", template: "%s · Laju" },
  description: "Laju mengubah lari jadi progres: poin, level, dan papan peringkat.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="id">
      <body>
        <main>{children}</main>
      </body>
    </html>
  );
}
