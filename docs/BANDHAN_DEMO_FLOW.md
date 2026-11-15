# Bandhu demo flow: every journey (org `bandhan`)

| | |
|---|---|
| Web (public) | **https://trailsignup-fbf7dadaec8000.my.site.com/consumer/BandhuWeb** |
| Lightning | App Launcher → **Bandhu Cards** (Leads, Card Applications, Card Journeys, Contacts). Open records from this app: the Contact 360 page is assigned to it only (the Service Console shows the SDO Contact page) |
| OTPs | mobile, Aadhaar and card activation: **123456** |
| WhatsApp | presenter phone **9063480755** (+91) |

Answer keys
- Spend: 1 Travel · 2 International · 3 Dining · 4 Groceries · 5 Shopping · 6 Fuel (several: `1, 3`; on the web tap the chips, then *Continue*)
- Monthly spend: 1 under ₹15K · 2 ₹15–50K · 3 ₹50K–1L · 4 over ₹1L · Fee: 1 lowest · 2 best benefits
- Income source: 1 Salaried · 2 Self-employed professional · 3 Business owner
- Any mobile that isn't a seeded customer is new to bank. Seeded (existing) customers, typed at the mobile step on the web:
  **Rohan 9000000101 · Sutapa 9000000102 · Rina 9000000103 · Debasish 9000000104**

Running order (about 45 minutes; Acts 3, 4 and 9 can be trimmed)

| Act | Journey | Where | Min |
|---|---|---|---|
| 1 | The page and the brand | Web | 2 |
| 2 | New to bank: the statements pick the card, apply, approve, activate | Web | 7 |
| 3 | New to bank: when it doesn't fit (low score, no history, heavy EMIs) | Web | 4 |
| 4 | Existing customers: pre-approved, wealth, microfinance, dormant | Web | 5 |
| 5 | WhatsApp in Bengali, drop-off, lead management and the RM nudge | Phone + Lightning | 5 |
| 6 | Underwriting: refer, risk flags, income documents | Lightning | 7 |
| 7 | Human handoff | Phone + Service Console | 3 |
| 8 | RM 360 and a branch-assisted application | Lightning + phone | 4 |
| 9 | After the card: limit offer, re-approach, cooling-off, consent | Script + phone | 5 |

## Before the demo (10 min)
0. Clean slate (removes every Bandhu journey, application, lead, task, consent and document from earlier runs):
   `sf apex run -f scripts/bandhan/apex/reset_demo.apex -o bandhan`. Do this before every demo: an old application on a
   demo PAN makes the fraud check refer the new one as a duplicate.
1. `sf apex run -f scripts/bandhan/apex/seed.apex -o bandhan` with `ON_DEMO_PHONE = ''` (the phone is new to bank).
   For Act 8 run it again with `'Rohan'`.
2. Leads and the underwriting queue: run `scripts/bandhan/apex/demo_leads.apex` for WHICH = 0, 1, 2, 3 (loop in its header).
   Expected: Priya (Lumina, dropped at Aadhaar), Arjun (Ignite, at the recommendation), Moumita (not eligible, knocked out
   at the bureau gate), Sourav (Flare, Under Review).
3. Setup → Messaging Components → **Bandhu Text** → Activate.
4. WhatsApp router portal: register **919063480755** against this org (it routes to one org at a time).
5. End any open WhatsApp session for the phone; Omni-Channel Offline until Act 7.
6. Browser: open the web page in a private window (the cookie banner shows once per session) and Lightning in another.

## Act 1. The page and the brand (2 min)
Open the web page (and on a phone, or narrow the window, to show it is mobile-first).
- Header: the **Bandhan Bank logo**, the official palette (Indigo #0A3152, Ocean Red to Lava Red), Poppins.
- Hero: *"The right credit card, picked for how you spend."* and *Find my card*; the facts row (4 cards, 5 min,
  instant virtual card, 24/7 on web and WhatsApp); Bandhu's greeting.
- Trust strip: RBI-regulated Account Aggregator · DPDP Act 2023 consent · no documents, no branch visit · English, Hindi & Bengali.
- *How it works*: tell us how you spend → connect your accounts → get your virtual card.
- *The card range*: Bandhan's four cards with their tiers: Sparks (Classic), Ignite (Silver), Flare (Gold), Lumina (Platinum).
- Accept the cookie banner.

## Act 2. New to bank: the statements pick the card (7 min) — *the Account Aggregator story*
*Find my card* → the chat opens (language buttons English / हिंदी / বাংলা at the top) → **Find my card** → consent
(DPDP, purpose-limited) → name → mobile **9876511001** → OTP.

The order is: your details (email, date of birth, city and PIN, PAN), then your income and bank statements, then the
three needs questions in one run, then the soft check and the recommendation. Nothing interrupts the needs.
1. Details: email **any@example.com**, date of birth **12/04/1990**, **Kolkata 700091**, PAN **ABCPT1234K**.
   Income: source **Salaried**, income **1 lakh**.
2. Account Aggregator: *"connect your accounts for instant approval, no documents needed: 24 months, only for this
   decision, consent valid 30 days"* → **Connect my accounts**. Show *What your statements show* (24 months, 2 accounts,
   income stability 96/100 growing, EMIs 12% of income, *Top spends: Travel ₹22,892 (₹12,000 of it abroad) · Groceries
   ₹5,716 · Dining ₹4,761*) and the live *"you qualify for 3 cards so far"*. (Inside, travel in India and abroad stay separate: Flare
   rewards travel, Lumina international spends.)
3. Needs, in one run: tap **Groceries** only (the customer *says* groceries) → *Continue* → monthly **₹15–50K** → fee
   **best benefits** → soft check **Yes**. (No company question: the employer was read from the salary credits.)
4. Recommendation: **Flare (Gold)**, not Ignite: *"Travel: ₹10,892/month in your statements · 20 points per ₹200 on
   travel"* and *"Travel abroad: 4 trips in 24 months, about ₹72,000 a trip"*, limit **₹2,65,000 – ₹3,35,000**, the card tiles with *Bandhu's pick* first. (Skip AA and the pick is Ignite.)
5. Type **I want Lumina** → *"You asked for Lumina (Platinum): monthly income below ₹2,00,000. But you qualify for
   Flare (Gold). Here's what you get"* → **Apply for Flare**.
6. Aadhaar last 4 **1234** → OTP → Video KYC **Done** → review: point at the *hard credit enquiry* notice → **Confirm**.
7. **Approved**: virtual card, limit, reference, the **MITC** link, *Activate within 30 days*, *Cancel card within 7
   days*, and **"Earn more with your Bandhan Flare"**: from the statements, the ~₹42,100 a month paid today by UPI or
   debit card that could go on the card, by category with the points at Flare's rates (travel ₹10,892 → 1,089 points at
   20 per ₹200, travel abroad, groceries, dining), about **2,551 points a month (≈ ₹638)**, and the fuel surcharge waiver. (Point value ₹0.25 is a
   placeholder.) Underwriter-approved cards get the same tip on WhatsApp.
8. Type **Activate** → OTP **123456** → *your Bandhan Flare is active*, with the tip again as a reminder.
9. Lightning → Card Applications → this application: the Bandhan header, the Flare card face, the CIBIL and **Bandhan
   Score** (~905, band A) tiles, every stage gate green, *why this card* as statement-backed reasons. Related: Card
   Checks (each with detail), **Card Consents** (DPDP, soft check, AA with its expiry, hard enquiry, MITC, activation).

## Act 3. New to bank: when it doesn't fit (4 min) — web, a new mobile each
| Mobile / PAN / answers | What to show |
|---|---|
| **9876511002**, PAN **ABCPS1234Z**, income 60000, AA Connect, spend Groceries / ₹15–50K / lowest | CIBIL 630: no card today → *"a specialist can look at other options, for example a Loan / Overdraft against your Fixed Deposit. I'll check again in 6 months"* → **Talk to a specialist** (RM task). Its lead is Unqualified at the Credit Bureau gate |
| **9876511003**, PAN **ABCPS1235K**, AA **Skip** | No bureau footprint and no statements → *"no credit history and no bank statements shared"*. Redo with AA **Connect** → a card is possible on the statements |
| **9876511004**, PAN **ABCPS1238K**, income 2.5 lakh, AA Connect, spend Travel + International / over ₹1L / best | Lumina with *"⚖ Limit set for your existing EMIs (55% of income)"*: the limit is halved to ₹5.4L |

## Act 4. Existing customers (5 min) — web, type the seeded mobile
| Customer | What to show |
|---|---|
| **Rohan 9000000101** | *Welcome back*: no email, DOB, PIN, PAN, income or KYC asked; silent soft pull (cached 30 days); company **Tata Steel**, then spend Travel + Dining / ₹50K–1L / best → **Flare**, pre-approved **₹3.5L** → apply → review → approved (no Aadhaar or Video KYC) |
| **Sutapa 9000000102** | Wealth tier (balances + FDs + demat ₹18.5L): income source Salaried, income 1 lakh, spend Travel + International → **Lumina** through the relationship route, limit ₹5L |
| **Rina 9000000103** | Microfinance-only customer: income source Business owner, income 45000, spend Groceries + Shopping → **Sparks only** (the other cards aren't offered to the microfinance tier) |
| **Debasish 9000000104** | Dormant savings account: right after the OTP the journey is **on hold** (*"needs a quick reactivation… your RM will call"*) and the RM gets a task. (An AML flag would show *"a routine review"*: never disclosed) |

## Act 5. WhatsApp and lead management (5 min)
1. From the demo phone: **Hi** → **BN** for Bengali → answer up to the recommendation and stop (drop-off).
2. Bandhu Cards → Leads: **Priya** (Hot, Lumina, dropped at Aadhaar eKYC), **Arjun** (Hot, Ignite, at the
   recommendation), **Moumita** (Unqualified: knocked out at the Credit Bureau gate) and your own drop-off (after ~2 min).
3. Open Priya: the full-width **Bandhu card lead** view: the recommended card face (Lumina, ₹10.8L), intent, credit and
   combined scores, CIBIL and Bandhan Score; the journey path (Verified → Income & statements → Needs → Credit check →
   Recommendation → **KYC**) with *dropped at Aadhaar eKYC*; the 7 qualification gates with points; *How the scores were
   built*; *The customer* and *Bank statements*. **Next best action** → **Nudge on WhatsApp** → the phone gets the RM
   message → *Continue* resumes where it stopped. Moumita shows *Knocked out at Credit Bureau* and no nudge.

## Act 6. Underwriting (7 min) — Bandhu Cards → Card Applications
1. **Sourav Ghosh**: Flare, **Under Review**: a frequent traveller (4 trips abroad in 24 months) with CIBIL **772
   (Excellent)**, but a **settled credit card** on his bureau report (RBL Bank, once 90 days overdue, closed by
   settlement), which is a manual-review rule: that is why *Credit Bureau* and *Card Policy* are yellow (Refer). Walk, top to bottom:
   - the header, the Flare card face, CIBIL and **Bandhan Score** (855, band A) tiles, the CIBIL tile labelled *Excellent (750-900)*;
   - **Bank statements · Account Aggregator**: the consent (purpose, 24 months, 2 banks, 764 transactions); net monthly
     income ₹91,200 from *salary credits from INFOSYS LTD* vs ₹95,000 declared, stability 96/100 growing, EMIs 12%,
     surplus; **Where the money goes** (card-able spend highlighted, then rent, EMIs, investments, cash, bills); **Said
     ₹75,000 vs the card-able spend in the statements**; lifestyle *Frequent traveller in India* and *Travels abroad: 4 trips,
     about ₹68,400 a trip*; card-able spend by category; lifestyle signals;
   - **Bandhan Score**: **855/1000, band A** on the band meter (D review · C · B · A +0.5x limit); where the points come
     from, in three groups: credit bureau (of 600) · bank statements (of 250) · income, relationship and channel (of 150);
     strengths and **what holds it back** (the settled card: repayment 20/70 *settled account on record*, then the surplus, new to bank and income level); *All 14 factors* opens the audit table. The CIBIL
     factor follows the CIBIL bands: Excellent 750+ = full 280, Good 700-749 = 220-280, Fair 650-699 = 110-220, Poor
     below 650 = under 110;
   - the stage gates, each check's detail, the recommendation and *why this card* → **Approve & issue card** → the phone
     gets the approval with the MITC on WhatsApp.
2. Risk flags (create on the web with any new mobile, income 1 lakh, spend Dining / ₹15–50K / best, apply through KYC):
   | PAN | Refers because |
   |---|---|
   | **ABCPS1239K** (AA Connect) | Income Verification: round-trip transfers with one party, a 4x-income credit, months without salary (stability 70/100) |
   | **ABCPS1237K** | Credit Bureau: a settled account on record → manual review |
   | **ABCPS1236K** | Dedupe & Fraud: applied with 5 lenders in 6 months |
   | **ABCPS1232K**, income source **Business owner**, AA Skip | Income: GST returns 7 of 12 months, turnover and AIS far below declared |
3. On the ABCPS1232K application, **Income documents**: type *Salary slip* → upload any PDF → *Pass*; Income
   Verification turns Pass and sets the verified income. Upload another file named `*mismatch*` as *Form 16* → 30% below
   declared → Refer.

## Act 7. Human handoff (3 min) — Service Console
Omni-Channel *Available* → on WhatsApp type **Agent** → accept the chat: the **Bandhu handoff** panel shows who they are,
new or existing, every answer, CIBIL, cash flow (AA), eligible cards, the recommendation and why they asked → reply.

## Act 8. RM 360 and branch-assisted (4 min)
Seed with `ON_DEMO_PHONE = 'Rohan'`. **Bandhu Cards** → Contacts → **Rohan Mukherjee**: the **Customer 360 · card to
pitch** panel: tier Deposit, relationship score, Bandhan Score (~885) and what drags it, **pitch Flare (Gold)**,
₹2.8–3.5L, why; bureau and relationship detail → **Start branch-assisted application** → the phone gets *"Namaskar
Rohan… as <RM> mentioned…"* with the consent → he continues on WhatsApp.

## Act 9. After the card (5 min) — `scripts/bandhan/apex/demo_after_issue.apex` (set MOBILE and MODE)
| MODE | Before | Show |
|---|---|---|
| `limit` | an issued card on MOBILE: do Act 2 on the demo phone over WhatsApp (PAN ABCPT1234K) | WhatsApp: *"higher credit limit ₹3,35,000 → ₹5,00,000, reply Yes: your limit changes only with your consent"* → **Yes** → limit updated, *Limit enhancement* consent logged |
| `reapproach` | a declined journey: PAN **ABCPS1234Y**, income 30000 → Sparks refers → **Decline** it in Card Applications | 7 months later: CIBIL 690 → 732 → *"Good news, you now qualify for the Bandhan Sparks"* + an RM task |
| `unactivated` | an issued card never activated | closed after 30 days (RBI rule) |

Also: on an issued card type **Cancel card** → **Yes, cancel it** → cancelled with no charges (cooling-off). Anywhere:
**withdraw my consent** → processing stops, consents are withdrawn, the RM gets an erasure task. Files → *Bandhu
scorecard monitoring YYYY-Qn*: outcomes by score band for recalibrating the Bandhan Score.

## Talk track for what is simulated
Account Aggregator (FIU), CIBIL, NSDL, UIDAI, Video KYC, GST, AIS, OCR, the card management system and the core banking
feed are simulated behind one class each, deterministic on the PAN so the demo repeats; going live replaces each with
the real API behind the same method. Card benefits are Bandhan's published ones; fees, eligibility thresholds,
cooling-off and retention days are placeholders for Bandhan to confirm.

## Smoke test without a phone
`sf apex run -f scripts/bandhan/apex/smoke.apex -o bandhan` walks a new-to-bank applicant to an issued Lumina and rolls back.
