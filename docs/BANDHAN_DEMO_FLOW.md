# Bandhu demo flow: every journey (org `bandhan`)

Web: **https://trailsignup-fbf7dadaec8000.my.site.com/consumer/BandhuWeb** · OTPs (mobile, Aadhaar, activation): **123456**

Lightning: app **Bandhu Cards** (Leads, Card Applications, Card Journeys, Contacts).

Answer keys used below
- Spend: 1 Travel · 2 International · 3 Dining · 4 Groceries · 5 Shopping · 6 Fuel (several: `1, 3`)
- Monthly spend: 1 under ₹15K · 2 ₹15–50K · 3 ₹50K–1L · 4 over ₹1L · Fee: 1 lowest · 2 best benefits
- Income source: 1 Salaried · 2 Self-employed professional · 3 Business owner
- Any mobile that is not a seeded customer = new to bank. Seeded customers (existing to bank) on the web: type their
  mobile at the mobile step: **Rohan 9000000101 · Sutapa 9000000102 · Rina 9000000103 · Debasish 9000000104**.

## 0. Before the demo (10 min)
1. `sf apex run -f scripts/bandhan/apex/seed.apex -o bandhan` (set `ON_DEMO_PHONE` to `'Rohan'` only for the RM 360
   WhatsApp act; leave `''` otherwise).
2. Lead and underwriting data: run `scripts/bandhan/apex/demo_leads.apex` for WHICH = 0, 1, 2, 3 (see its header).
3. Setup → Messaging Components → **Bandhu Text** → Activate. WhatsApp router: register 919063480755 against this org.
4. End any open WhatsApp session for the phone; Omni-Channel Offline until the handoff act.

## Act 1. New to bank, web: statements pick the card (6 min) — *the AA story*
Web → *Talk to Bandhu* → English → Find my card → consent (note: DPDP, purpose-limited) → name → mobile **9876511001** → OTP.
1. Income source **1**, income **1 lakh**, PAN **ABCPT1234K**.
2. Account Aggregator: *"Connect your accounts for instant approval, no documents needed — 24 months, only for this
   decision, consent valid 30 days"* → **1**. Show: *What your statements show* (24 months, 2 accounts, stability 96/100
   growing, EMIs 12%, top spends Travel / International / Dining, "Frequent traveller") and *you qualify for 4 cards so far*.
3. Spend: say **4** (groceries) — the customer *says* groceries — monthly **2**, fee **2** → company, DOB, PIN, soft check **1**.
4. Recommendation: **Flare (Gold)**, not Ignite: *"Travel: ₹14,284/month in your statements"*, limit **₹2.65–3.35L**.
   (Run it again skipping AA and the pick is Ignite.)
5. Type **I want Lumina** → *"You asked for Lumina (Platinum) — monthly income below ₹2,00,000 — but you qualify for
   Flare (Gold), here's what you get"* → **1** apply.
6. Email, Aadhaar last 4 **1234**, OTP, Video KYC **Done** → review: *hard credit enquiry* notice → **1**.
7. **Approved**, virtual card, MITC link, *Activate within 30 days*, *Cancel card within 7 days*.
8. Type **Activate** → OTP **123456** → *card is active*.
   Lightning: Card Applications → this one → 9 checks all Pass, Bandhan Score ~826 band A with every factor; Related:
   Card Checks, Card Consents (DPDP, soft check, AA with expiry, hard enquiry, MITC, activation).

## Act 2. New to bank, when it doesn't fit (5 min)
| Mobile / PAN / answers | What to show |
|---|---|
| **9876511002**, PAN **ABCPS1234Z**, income 60000, AA 1, spend 4/2/1 | CIBIL 630: no card today → *"a specialist can look at other options, for example a Loan / Overdraft against your Fixed Deposit; I'll check again in 6 months"* → **1** specialist (RM task). The lead is Unqualified at the Credit Bureau gate |
| **9876511003**, PAN **ABCPS1235K**, AA **2** (skip) | No bureau footprint and no statements → not eligible (*no credit history and no bank statements shared*). Redo with AA **1** → a card becomes possible on the statements |
| **9876511004**, PAN **ABCPS1238K**, income 2.5 lakh, AA 1, spend `1, 2`/4/2 | Lumina, *"⚖ Limit set for your existing EMIs (55% of income)"*: limit halved to ₹5.4L |

## Act 3. Existing customers (5 min) — web, type the seeded mobile
| Customer | What to show |
|---|---|
| **Rohan 9000000101** | *Welcome back*: no income, PAN, DOB, PIN or KYC asked; silent soft pull (cached 30 days on the Contact); only spend questions + company → **Flare** pre-approved **₹3.5L** → apply → review → approved (no Aadhaar / Video KYC) |
| **Sutapa 9000000102** | Wealth tier (balances + FDs + demat ₹18.5L): **Lumina** through the relationship route even at ₹1 lakh income (say income source 1, income 1 lakh, spend `1, 2`) |
| **Rina 9000000103** | Microfinance-only customer: income source **3**, income 45000, spend `4, 5` → **Sparks only** (other cards not offered to the microfinance tier) |
| **Debasish 9000000104** | Dormant savings account: right after the OTP the journey is **on hold** (*"needs a quick reactivation… your RM will call"*) and the RM gets a task. (An AML flag shows *"a routine review"*: never disclosed) |

## Act 4. WhatsApp + lead management (5 min)
1. From the demo phone: **Hi** → **BN** for Bengali → go up to the recommendation and stop (drop-off).
2. Bandhu Cards → Leads: Priya (Hot, Lumina, dropped at Aadhaar), Arjun (Hot, at the recommendation), Moumita
   (Unqualified: knocked out at the Credit Bureau gate), your own drop-off (after ~2 min). Open one:
   the 7 qualification gates, intent and credit scores, drop point → **Nudge on WhatsApp** → the phone gets the RM
   message → *Continue* resumes where it stopped.

## Act 5. Underwriting (6 min) — Card Applications
1. **Sourav Ghosh** (demo_leads): Flare, Refer (CIBIL 730 refer band): gates incl. Due Diligence and Bandhan Score,
   each check's detail → **Approve & issue card** → the customer gets the approval with MITC on WhatsApp.
2. Show the underwriting flags (create on the web, mobile any new number, income 1 lakh, spend 3/2/2):
   | PAN | Refer because |
   |---|---|
   | **ABCPS1239K** (AA 1) | Income Verification: statements show round-trip transfers with one party, a 4x-income credit, months without salary (stability 70/100) |
   | **ABCPS1237K** | Credit Bureau: settled account on record → manual review |
   | **ABCPS1236K** | Dedupe & Fraud: applied with 5 lenders in 6 months |
   | **ABCPS1232K**, income source **3**, AA 2 | Income: GST returns 7 of 12 months, turnover and AIS far below declared |
3. On the ABCPS1232K application: **Income documents** → type *Salary slip* → upload any PDF → *Pass*, Income
   Verification turns Pass and sets the verified income. Upload another named `*mismatch*` as Form 16 → 30% below
   declared → Refer.

## Act 6. Human handoff (3 min)
Omni-Channel *Available* → on WhatsApp type **Agent** → accept: the Bandhu panel shows who they are, new or existing,
every answer, CIBIL, cash flow (AA), eligible cards, the recommendation and why they asked.

## Act 7. RM 360 and branch-assisted (4 min)
Seed with `ON_DEMO_PHONE = 'Rohan'`. Bandhu Cards → Contacts → **Rohan Mukherjee**: tier Deposit, relationship score,
products, bureau, Bandhan Score and weakest factors, **the card to pitch** (Flare, ₹2.8–3.5L, why) → **Start
branch-assisted application** → the phone gets *"Namaskar Rohan… as <RM> mentioned…"* + consent → continue on WhatsApp.

## Act 8. After the card (4 min) — `scripts/bandhan/apex/demo_after_issue.apex` (set MOBILE and MODE)
| MODE | Before | Show |
|---|---|---|
| `limit` | an issued card on MOBILE (do Act 1 on the demo phone over WhatsApp, PAN ABCPT1234K) | WhatsApp: *"higher limit ₹3.35L → ₹5L, reply Yes — changes only with your consent"* → **Yes** → limit updated, *Limit enhancement* consent logged |
| `reapproach` | a declined or not-eligible journey, e.g. PAN **ABCPS1234Y**, income 30000 → Sparks refers → decline it in Card Applications | 7 months later: CIBIL 690 → 732 → *"Good news — you now qualify for Sparks"* + RM task |
| `unactivated` | an issued card never activated | closed after 30 days (RBI rule) |
Also: on an issued card type **Cancel card** → **1** → cancelled with no charges (cooling-off). Anywhere: **withdraw my
consent** → processing stops, consents withdrawn, RM gets an erasure task. Files → *Bandhu scorecard monitoring
YYYY-Qn*: outcomes by score band for recalibration.

## Talk track for what is mocked
AA (FIU), CIBIL, NSDL, UIDAI, Video KYC, GST, AIS, OCR, card management and the core banking feed are simulated behind
one class each, deterministic on the PAN so the demo repeats; going live replaces each with the real API behind the
same method. Fees, thresholds, cooling-off and retention days are placeholders.
