import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { CONTACT_EMAIL, PRIVACY_LAST_UPDATED, privacyEnglishSummary, privacySections } from "./legal";

const fullText = [
  ...privacySections.flatMap((section) => [section.title, ...section.paragraphs, ...(section.bullets ?? [])]),
  ...privacyEnglishSummary,
].join("\n");
const section = (id: string) => privacySections.find((entry) => entry.id === id)!;
const sectionText = (id: string) => [...section(id).paragraphs, ...(section(id).bullets ?? [])].join("\n");

describe("privacy policy text", () => {
  it("has a contact, a date, and unique numbered sections", () => {
    expect(fullText).toContain(CONTACT_EMAIL);
    expect(PRIVACY_LAST_UPDATED).toMatch(/2026/);
    const ids = privacySections.map((entry) => entry.id);
    expect(new Set(ids).size).toBe(ids.length);
    privacySections.forEach((entry, index) => expect(entry.title.startsWith(`${index + 1}. `)).toBe(true));
  });

  it("names every category the system actually handles, and every processor and where it runs", () => {
    for (const phrase of ["Lokasi presisi", "jalur GPS", "Nama panggilan", "wilayah", "skor kepercayaan"]) {
      expect(sectionText("data-yang-dikumpulkan") + sectionText("tujuan"), phrase).toContain(phrase);
    }
    for (const processor of ["Supabase", "Vercel", "Apple", "Google", "Apple Maps"]) {
      expect(sectionText("pihak-pemroses"), processor).toContain(processor);
    }
    expect(sectionText("pihak-pemroses")).toContain("Singapura");
    expect(sectionText("transfer")).toContain("di luar Indonesia");
  });

  it("states what it does NOT do (no ads / trackers / sale) — a claim the code must keep true", () => {
    expect(sectionText("tidak-dikumpulkan")).toMatch(/tidak menampilkan iklan/);
    expect(sectionText("tidak-dikumpulkan")).toMatch(/tidak menjual/);
  });

  it("does not invent a retention period — no time-based deletion exists (SEC-1 is still an open decision)", () => {
    expect(sectionText("retensi")).not.toMatch(/\b\d+\s*(hari|bulan|minggu|tahun|days|months|years)\b/i);
    expect(sectionText("retensi")).toMatch(/belum menerapkan penghapusan otomatis/);
  });

  /**
   * The policy and `lib/account-deletion.ts` must agree (pre-launch-checklist.md §1: "this document and that feature must
   * agree with each other, not be written independently"). Every field the code clears has to be described as cleared.
   */
  it("describes exactly the personal data account deletion really clears", () => {
    const code = readFileSync(join(__dirname, "account-deletion.ts"), "utf8");
    const deletion = sectionText("hapus-akun").toLowerCase();
    const cleared: Record<string, string> = {
      username: "nama panggilan",
      display_name: "nama tampilan",
      email: "alamat email",
      avatar_url: "foto",
      region_kecamatan: "wilayah",
      gps_route: "jalur gps",
    };
    for (const [field, wording] of Object.entries(cleared)) {
      expect(code, `account-deletion.ts should clear ${field}`).toMatch(new RegExp(`${field}:\\s*(null|\`deleted)`));
      expect(deletion, `the policy should say ${wording} is removed`).toContain(wording);
    }
    expect(code).toContain("auth.admin.deleteUser"); // the sign-in identity goes
    expect(deletion).toContain("identitas login");
    expect(code).toMatch(/PointTransaction. rows are never touched/); // the ledger stays
    expect(deletion).toContain("catatan poin dipertahankan");
  });

  it("tells the user how to delete the account in the app", () => {
    expect(sectionText("hapus-akun")).toContain("Hapus akun");
  });
});
