# Laju App — Pre-Launch Checklist (App Store Submission)

Depends on: [product-spec.md](../01-product/product-spec.md), [tech-spec.md](../02-architecture/tech-spec.md)

Created 2026-09-12 alongside product-spec.md §4.8-4.17 — this is
non-engineering compliance/legal work (writing documents, filling forms
in App Store Connect), tracked separately from `tasks/*.md` since it
isn't a code deliverable. Items here block App Store submission; some
also require an engineering task to exist first (cross-referenced below).

## 1. Privacy Policy

- [x] Privacy Policy **drafted and published 2026-09-21** at
      `https://backend-eight-gules-56.vercel.app/privacy` (home page at `/`), served by the
      backend's Next.js app; text in `backend/lib/legal.ts`. Written from the code and
      documents, not a template, and guarded by `lib/legal.test.ts` (every field
      `lib/account-deletion.ts` clears must be described as cleared; no invented
      retention period). **It is a developer draft, not legal advice: it still needs the
      owner's review (ideally by someone who knows UU PDP No. 27/2022) before submission**,
      and the URL should move to a domain the project owns (a `vercel.app` address is fine
      for Google's consent screen but is a poor long-term App Store URL). One statement still
      depends on a decision left open: "13+" as the age line. **Retention (SEC-1) is now
      decided, 2026-09-22: indefinite, until account deletion — a deliberate product choice
      (full route history is a core feature), not an unexamined default.** The policy's
      retention section (`backend/lib/legal.ts`) was reworded from "we haven't implemented
      automatic deletion yet" to state that choice affirmatively; see
      `database-api-spec.md` §1 ERD (`gps_route`) and §2.1b point 5, and
      `security-review.md` SEC-1 for the full rationale and options considered.
- [ ] Covers every data category actually collected: precise location
      ("Always" usage, tech-spec.md §1), and any HealthKit data if/when
      that integration ships (development-plan.md Fase 4, T4.13 — not v1,
      but the policy should be structured to extend cleanly when it does).
- [ ] Explicitly states what happens to user data on account deletion
      (product-spec.md §4.17, tasks/phase-2-backend-sync-global-leaderboard.md
      T2.22) — this document and that feature must agree with each other,
      not be written independently.
- [ ] Reviewed against Apple's current Privacy Policy requirements (App
      Store Review Guidelines §5.1) before submission — guidelines change
      over time, re-check at submission time, not just at the time this
      checklist was written.

## 2. App Privacy "Nutrition Label" (App Store Connect)

- [ ] Data types declared in App Store Connect's App Privacy questionnaire
      match what the app actually collects — at minimum: Location (Precise
      Location, since background tracking needs "Always"), and User
      Content/Identifiers once auth (Fase 2) ships.
- [ ] Declared purpose for each data type is accurate (e.g. Location →
      "App Functionality", not "Analytics" or "Third-Party Advertising"
      unless that's genuinely also true).
- [ ] Re-verified after every feature that changes what data is collected
      (e.g. HealthKit, if/when T4.13 ships) — this is not a one-time
      checklist item, it must be revisited per release if data collection
      changes.

## 3. Location Permission Compliance

- [ ] `NSLocationAlwaysAndWhenInUseUsageDescription` /
      `NSLocationWhenInUseUsageDescription` strings in `Info.plist` clearly
      explain *why* (background run tracking), not generic boilerplate —
      Apple rejects vague usage strings.
- [ ] The three-state permission flow (product-spec.md §4.15,
      tasks/phase-1-core-loop-offline.md T1.15) is implemented and tested
      before submission — Apple reviewers specifically test the
      While-Using-only path for apps requesting Always.

## 4. Account Deletion (Guideline 5.1.1(v))

- [ ] product-spec.md §4.17 / tasks/phase-2-backend-sync-global-leaderboard.md
      T2.22 verified end-to-end — **this blocks submission entirely** once
      the app has account creation (Fase 2). Apple rejects apps with
      account creation but no in-app deletion path.
      *Status 2026-09-19: built and verified server-side against real
      Supabase (T2.22); the end-to-end run on a real signed-in device is the
      part still open.*
- [ ] **Revoke the Sign in with Apple token on deletion.** Apple requires
      apps that offer Sign in with Apple to revoke the user's token (Apple's
      `/auth/revoke` REST endpoint, authenticated with a client secret signed
      by a `.p8` key from the developer account) when the account is
      deleted, not just delete the app's own record. **Not implemented**:
      it needs the Apple Developer Program key, and T2.22's spec did not
      list it. Add it to `deleteAccount` (backend) before submission —
      without it App Review can reject the deletion flow as incomplete.

## 5. Sign in with Apple (Guideline 4.8)

- [x] **Re-opened and re-verified 2026-09-21.** The 2026-09-17 closure ("Sign in with Apple only") was explicitly
      conditional on the auth method set staying as-is; on 2026-09-21 a **second provider, Google, was added**
      (product-spec.md §4.1 AC1, tech-spec.md §6). Guideline 4.8's requirement is that when a third-party login is
      offered, an equivalent privacy-preserving option (Sign in with Apple) is offered too — **Apple was not removed**,
      and its button ships alongside Google's on the same screen (`OnboardingSignInStep`). Still compliant.
- [x] **No email/password**, enforced in configuration (2026-09-19, SEC-15): the hosted Supabase project has the email
      provider off; enabled external providers are Apple and Google only (`supabase config diff`, 2026-09-21).
- [ ] **Google OAuth consent screen is in Testing — the publish button needs a homepage and
      a privacy-policy URL on a domain Google has verified as yours.** The two pages now exist
      (§1); what is left is on the owner's Google Cloud / Search Console side: fill Branding
      (home page `…vercel.app/`, privacy `…vercel.app/privacy`), add the domain under
      Authorized domains, verify it in Search Console, then **Publish app**.
- [ ] (original wording) **Google OAuth consent screen is in Testing** — only listed test users can sign in. Publish it ("In production")
      before public release; basic scopes need no Google review, but the consent screen needs the privacy policy URL
      (§3) and app name/support email. **Open.**
- [ ] If a **third** method (email/password, another OAuth provider) is ever added, re-open this item again.

## 6. App Store Assets

- [ ] Screenshots for all required device sizes (per current App Store
      Connect requirements at submission time — sizes change with new
      device form factors).
- [ ] App icon in all required sizes (already generated, see `Icon.jpg` /
      `ios/Laju/Assets.xcassets` — verify completeness against Apple's
      current icon size matrix before submission).
- [ ] App preview video (optional, not required — consider once core loop
      + new Fase 1 features, especially live map, are visually polished
      enough to showcase).
- [ ] App Store description, keywords, promotional text drafted.
- [ ] Support URL and (optional) marketing URL set in App Store Connect.

## 7. Age Rating & Content

- [ ] Age rating questionnaire completed in App Store Connect (Laju has
      no obviously mature content, but Location + user-generated content
      once Social Feed exists — T4.15, Fase 4, not v1 — affects the
      questionnaire; re-verify if/when that ships).

## 8. Export Compliance

- [ ] Export compliance question answered in App Store Connect (standard
      HTTPS/TLS usage typically qualifies for the standard exemption — set
      `ITSAppUsesNonExemptEncryption` in `Info.plist` accordingly once
      Fase 2's networking layer exists).

## 9. TestFlight / Review Notes

- [ ] Demo account credentials provided to reviewers if account creation
      is required to test the core loop (Fase 2) — reviewers must be able
      to reach the point/level/leaderboard experience without friction.
- [ ] Review notes explain any non-obvious permission flow (Always
      location specifically) so reviewers don't reject for unclear usage.

## 10. Background Modes & Entitlements

- [ ] `location` background mode declared in `Info.plist`
      (tech-spec.md §1, already required for T0.7/T0.9's background
      tracking) — confirm it's still present and matches actual usage at
      submission time.
- [ ] `audio` background mode declared in `Info.plist` once T1.13 (audio
      cues) ships (tech-spec.md §5.3, added 2026-09-13 Round 7 finding
      B7-5/N7-10) — without it, announcements silently stop the moment
      the screen locks. Review notes (§9) should explain both background
      modes so reviewers don't flag the app for having two.
- [ ] No unused entitlements/background modes left declared (Apple flags
      declared-but-unused capabilities during review).

---

**This file is a checklist, not a task backlog** — items here don't get a
task ID or a Definition of Done in the `tasks/*.md` sense; they get
checked off directly, with a date and who verified them, before
submission. Add new items as they're discovered — this list is not
guaranteed exhaustive against Apple's current guidelines, which change
over time.
