# LoanSeva — acceptance checklist

Run on 30 Sep 2026 against org `kotak-demo`.

**Evidence sources:**
- 42 Apex tests: all pass, 96% LoanSeva coverage.
- `scripts/apex/smoke.apex`: full journey in the live org.
- A live drop-off and OTP-lockout run in the org.

**How the checks ran:** everything is driven through the engine and the 12 agent actions. Nothing was run on a physical handset, because of the open items below:
- the public site returns 503 (SETUP_STEPS §2);
- the agent must be published in Builder (§3);
- Omni routing needs a manual step (§4);
- `Send_Mode` is still `LogOnly` (§5).

| # | Check | Result | Evidence / notes |
|---|---|---|---|
| 1 | QR / link shows the Kotak-branded form on mobile | ⚠️ **Blocked (org)** | The page, controller, branding, validation and consent work. They are tested and render at `/apex/LoanSevaRegister` for internal users. The public Sites URL returns 503 for every page, including a controller-less one, so it is a site/domain state rather than code (SETUP_STEPS §2). The QR image is in `docs/`. |
| 2 | Submitting a seeded mobile sends the nudge with **Continue Here!** within seconds | ⚠️ **Pass in LogOnly** | The submission path is Platform Event → trigger → journey → queued sender. It produced the personalised nudge ("…up to *₹5L*… Reply *Continue Here!*") in `Last_Send_Status__c` within the same second (`LoanSevaRegistrationTest`). A real WhatsApp delivery needs `Send_Mode = ConversationMessage`, plus a Meta template or an open 24-hour window (§5). |
| 3 | All four sample FAQ questions get grounded, on-brand answers | ✅ **Pass (engine)** | *Use*, *rate*, *vs new loan* and *disbursal speed* each match their `LoanSeva_FAQ__mdt` entry. Rates are merged from config, and every answer ends with "Reply **Yes** to verify" (`LoanSevaUtilsTest`, `LoanSevaEngineTest`, smoke). Checking through the agent needs publishing (§3). |
| 4 | OTP 123456 passes; wrong OTP ×3 exits gracefully and creates an RM task | ✅ **Pass** | Live: Ananya with 3 wrong codes → status `Exited`, a reassuring exit message, and Task "OTP failed 3x - assist Ananya with verification". The smoke run passed after one wrong code and then 123456. |
| 5 | Loan snapshot matches seed data | ✅ **Pass** | XXXX XXXX 8901, outstanding ₹3,20,000, EMI ₹11,800, 30 months left, "12/12 EMIs on time ✅". The full account number is never shown. |
| 6 | Personalisation via buttons; offer EMI maths correct | ✅ **Pass** | Numbered quick replies (1️⃣ 2️⃣ …) for employment, income, purpose and amount; free text for company. For ₹5,00,000 at 10.99% over 48 months the EMI is ₹12,920, which matches P·r·(1+r)ⁿ/((1+r)ⁿ−1). Amount and tenure can be edited, and FOIR, track and cap rules are tested. |
| 7 | Accept → reference number + RM Task/Event with summary | ✅ **Pass** | Smoke: `KMB-PLTU-260930-0041`. Task and Event "Priya — ₹5L top-up for home renovation, Salaried @ Infosys, income 1L-2L, accepted offer, callback Thu 11:00 AM", with the Event at 1 Oct 11:00 IST. `Loan_Application__c` was created. |
| 8 | Feedback — 3 questions stored | ✅ **Pass** | CSAT 1–5, resolution (Yes, fully / Mostly / Not really) and an optional comment (or *Skip*) are stored in `Journey_Feedback__c`, followed by a warm sign-off with the reference number. |
| 9 | Abandoning at Stage 4 creates an RM task and fires the re-engagement nudge (demo timings) | ✅ **Pass** | Live: Rahul went idle at Personalise and was marked `Dropped` at "Personalise (3/5 fields)". The RM Task carries the intent summary, and nudge 1 went out ("everything you shared is saved… Reply *Continue*"). Nudge 2 follows at +5 min. The job runs every minute (`LoanSevaDropOffJob`). |
| 10 | Language switch to Hindi works mid-conversation | ✅ **Pass (engine)** | Smoke switches to HI during Personalise and back to EN without losing answers. All 44 messages and 8 FAQs are available in EN, HI and MR, and a test asserts that none is blank. |
| 11 | No competitor-brand references remain anywhere | ✅ **Pass** | A case-insensitive grep for both competitor brand names over all source, metadata, docs and scripts returns nothing. The only matches are the original build prompt and the reference deck in `reference/`, a design input that is excluded from git. |

**Summary:**
- 9 of 11 pass at the Salesforce level.
- #1 is blocked by the org's Sites 503.
- #2 passes in LogOnly mode; the live WhatsApp send is pending the channel steps in SETUP_STEPS §§3–5.
