# -*- coding: utf-8 -*-
"""Bandhu (Bandhan Bank credit card advisor): card catalogue, settings and customer copy.
Generates the custom metadata records under bandhan/main/default/customMetadata.
Run from the project root: python3 scripts/bandhan/content.py

Card benefits are Bandhan Bank's published ones (creditcards.bandhan.bank.in). Fees and eligibility thresholds are
DEMO PLACEHOLDERS: confirm with the bank's schedule of charges and credit policy before any customer-facing use.
Copy: key -> (English, Hindi, Bengali). Tokens in {braces} are merged by Apex. Option lists are separate keys
(Opt_*) with one option per line: WhatsApp shows them numbered, the web journey shows them as buttons.
"""
import os
from xml.sax.saxutils import escape

OUT = 'bandhan/main/default/customMetadata'

CONFIG = {
    'Demo_OTP__c': '123456',
    'Max_OTP_Attempts__c': 3,
    'Min_Age__c': 21,
    'Max_Age_Salaried__c': 60,
    'Max_Age_Self_Employed__c': 65,
    'Decline_Cibil__c': 650,
    'Send_Mode__c': 'LogOnly',              # ConversationMessage once WhatsApp is connected
    'WhatsApp_Channel__c': 'WhatsApp_BYOC',
    'Nudge_Definition__c': 'Bandhu_Text',
    'Country_Code__c': '91',
    'Idle_Minutes__c': 2,                    # production: e.g. 30
    'RM_Username__c': 'trailsignup.fbf7dadaec8000@salesforce.com',
    'Site_Url__c': '',
    'Reference_Prefix__c': 'BBL-CC',
    'Card_Bin__c': '524193',
}

# name: values. Fees / income / CIBIL / limits are PLACEHOLDERS.
CARDS = {
    'Sparks': {
        'Tier__c': 1, 'Tagline__c': 'Your first Bandhan card: rewards on everyday spends',
        'Joining_Fee__c': 499, 'Annual_Fee__c': 499, 'Fee_Waiver__c': 'Annual fee waived on ₹1 lakh spend a year',
        'Rewards__c': '2 reward points per ₹200', 'Accelerated__c': '4 points per ₹200 on groceries & apparel',
        'Welcome__c': '500 bonus points on ₹5,000 spend in 30 days', 'Milestone__c': '',
        'Lounge__c': '1 domestic lounge visit a quarter', 'Dining__c': '', 'Movies__c': '20% off BookMyShow, up to ₹100 a month',
        'Fuel__c': '1% fuel surcharge waiver, up to ₹150 a cycle', 'Extras__c': '10% cashback up to ₹500 on your first EMI',
        'Min_Monthly_Income__c': 25000, 'Min_Cibil__c': 700, 'Refer_Cibil__c': 680, 'ETB_Min_Balance__c': 0,
        'Limit_Multiple__c': 1.5, 'Limit_Min__c': 25000, 'Limit_Max__c': 100000,
        'Fit_Travel__c': 0, 'Fit_International__c': 0, 'Fit_Dining__c': 1, 'Fit_Groceries__c': 4, 'Fit_Shopping__c': 4,
        'Fit_Fuel__c': 2, 'Fit_Low_Fee__c': 5, 'Fit_High_Spend__c': 0, 'Color__c': '#5B6B7F',
    },
    'Ignite': {
        'Tier__c': 2, 'Tagline__c': 'More rewards on groceries and travel',
        'Joining_Fee__c': 999, 'Annual_Fee__c': 999, 'Fee_Waiver__c': 'Annual fee waived on ₹2 lakh spend a year',
        'Rewards__c': '4 reward points per ₹200', 'Accelerated__c': '8 points per ₹200 on groceries & travel',
        'Welcome__c': '1,000 bonus points on ₹10,000 spend in 30 days', 'Milestone__c': '1,200 points on ₹30,000 monthly spend',
        'Lounge__c': '1 domestic + 1 international lounge visit a quarter', 'Dining__c': '15% off EazyDiner, up to ₹500 a month',
        'Movies__c': '', 'Fuel__c': '1% fuel surcharge waiver, up to ₹250 a cycle', 'Extras__c': '10% cashback up to ₹500 on your first EMI',
        'Min_Monthly_Income__c': 40000, 'Min_Cibil__c': 720, 'Refer_Cibil__c': 700, 'ETB_Min_Balance__c': 0,
        'Limit_Multiple__c': 2, 'Limit_Min__c': 50000, 'Limit_Max__c': 250000,
        'Fit_Travel__c': 3, 'Fit_International__c': 1, 'Fit_Dining__c': 3, 'Fit_Groceries__c': 5, 'Fit_Shopping__c': 3,
        'Fit_Fuel__c': 3, 'Fit_Low_Fee__c': 3, 'Fit_High_Spend__c': 1, 'Color__c': '#C2410C',
    },
    'Flare': {
        'Tier__c': 3, 'Tagline__c': 'Travel and lifestyle, with lounges and golf',
        'Joining_Fee__c': 2999, 'Annual_Fee__c': 2999, 'Fee_Waiver__c': 'Annual fee waived on ₹4 lakh spend a year',
        'Rewards__c': '10 reward points per ₹200', 'Accelerated__c': '20 points per ₹200 on travel',
        'Welcome__c': '₹2,000 Amazon Pay gift card on ₹10,000 spend in 30 days', 'Milestone__c': '5,000 points on ₹75,000 monthly spend',
        'Lounge__c': '4 domestic + 1 international lounge visits a quarter', 'Dining__c': '15% off EazyDiner, up to ₹750 a month',
        'Movies__c': '25% off BookMyShow, up to ₹500 a month', 'Fuel__c': '1% fuel surcharge waiver, up to ₹500 a cycle',
        'Extras__c': '4 golf lessons a year · 10% cashback up to ₹750 on your first EMI',
        'Min_Monthly_Income__c': 75000, 'Min_Cibil__c': 740, 'Refer_Cibil__c': 720, 'ETB_Min_Balance__c': 0,
        'Limit_Multiple__c': 2.5, 'Limit_Min__c': 100000, 'Limit_Max__c': 500000,
        'Fit_Travel__c': 5, 'Fit_International__c': 3, 'Fit_Dining__c': 4, 'Fit_Groceries__c': 2, 'Fit_Shopping__c': 2,
        'Fit_Fuel__c': 3, 'Fit_Low_Fee__c': 1, 'Fit_High_Spend__c': 3, 'Color__c': '#7C3AED',
    },
    'Lumina': {
        'Tier__c': 4, 'Tagline__c': 'Premium travel: unlimited international lounges, 1% forex',
        'Joining_Fee__c': 9999, 'Annual_Fee__c': 9999, 'Fee_Waiver__c': 'Annual fee waived on ₹10 lakh spend a year',
        'Rewards__c': '16 reward points per ₹200', 'Accelerated__c': '24 points per ₹200 on international spends · 1% forex mark-up',
        'Welcome__c': '₹10,000 Oberoi e-gift voucher on ₹20,000 spend in 30 days', 'Milestone__c': '10,000 points on ₹1 lakh monthly spend',
        'Lounge__c': '8 domestic + unlimited international lounge visits a quarter', 'Dining__c': '25% off EazyDiner, up to ₹1,000 a month',
        'Movies__c': '25% off BookMyShow, up to ₹1,000 a month', 'Fuel__c': '1% fuel surcharge waiver, up to ₹1,000 a cycle',
        'Extras__c': 'Concierge · 4 golf games & 4 lessons · 4 airport meet & greets · ₹1 Cr air accident cover',
        'Min_Monthly_Income__c': 200000, 'Min_Cibil__c': 760, 'Refer_Cibil__c': 740, 'ETB_Min_Balance__c': 1000000,
        'Limit_Multiple__c': 3, 'Limit_Min__c': 300000, 'Limit_Max__c': 1500000,
        'Fit_Travel__c': 5, 'Fit_International__c': 5, 'Fit_Dining__c': 5, 'Fit_Groceries__c': 1, 'Fit_Shopping__c': 3,
        'Fit_Fuel__c': 3, 'Fit_Low_Fee__c': 0, 'Fit_High_Spend__c': 5, 'Color__c': '#B8860B',
    },
}

LANG_HINT = ('Reply *HI* for हिंदी / *BN* for বাংলা', 'Reply *EN* for English / *BN* for বাংলা', 'Reply *EN* for English / *HI* for हिंदी')

# key: (English, Hindi, Bengali). Hindi/Bengali are filled in by the translation pass; empty falls back to English.
MESSAGES = {
    # ---------------------------------------------------------------- welcome and consent
    'Welcome': (
        "Hi{name}! 👋 I'm *Bandhu*, your Bandhan Bank credit card advisor.\n\nTell me a little about how you spend and I'll match you with the right card — and you can apply right here in about 5 minutes. Paperless, with a virtual card on approval.",
        '', ''),
    'Welcome_Existing': (
        "Welcome back{name}! 👋 I'm *Bandhu*, your Bandhan Bank card advisor.\n\nAs a Bandhan Bank customer you get a faster journey — I already have most of your details, so it's just a few questions.",
        '', ''),
    'Opt_Menu': ("Find my card\nCompare all cards\nAsk a question\nTalk to a specialist", '', ''),
    'Consent': (
        "🔒 Before we begin: Bandhan Bank will use the details you share only to recommend a card and process your application, as per RBI guidelines and the Digital Personal Data Protection Act, 2023. You can withdraw consent anytime.",
        '', ''),
    'Opt_Consent': ("I agree, let's start\nNot now", '', ''),
    'Consent_Declined': ("No problem 🙂 Nothing has been saved. Say *Hi* whenever you'd like to find your card.", '', ''),
    # ---------------------------------------------------------------- identity
    'Q_Name': ("What's your full name, as on your PAN?", '', ''),
    'Q_Mobile': ("Your 10-digit mobile number? I'll send a one-time password to verify it.", '', ''),
    'OTP_Sent': ("Thanks{name}! I've sent a 6-digit OTP to {mobile}. Please enter it here. 🔐\n\n_(Demo OTP: {otp})_", '', ''),
    'OTP_Wrong': ("That OTP didn't match — {left} attempt(s) left. Please try again.", '', ''),
    'OTP_Locked': ("For your security I've paused this application after too many wrong OTPs. A specialist will call you back.", '', ''),
    'Verified_New': ("✅ Verified! Now a few quick questions about how you spend, so I can find your best card.", '', ''),
    'Verified_Existing': (
        "✅ Verified! Good to see you again{name}. I can see your Bandhan Bank {relationship} — so no income proof or extra KYC needed. Just a few questions about how you spend.",
        '', ''),
    'Invalid_Mobile': ("Please enter a valid 10-digit mobile number, e.g. 98765 43210.", '', ''),
    'Invalid_Name': ("Please type your full name as on your PAN.", '', ''),
    # ---------------------------------------------------------------- needs
    'Q_Spend': ("*1/3* — What do you spend most on? Pick all that apply, e.g. *1, 3*", '', ''),
    'Opt_Spend': ("Travel & flights\nInternational trips\nDining & movies\nGroceries & everyday\nOnline shopping\nFuel", '', ''),
    'Q_Monthly_Spend': ("*2/3* — Roughly how much would you spend on the card each month?", '', ''),
    'Opt_Monthly_Spend': ("Under ₹15,000\n₹15,000 – ₹50,000\n₹50,000 – ₹1 lakh\nMore than ₹1 lakh", '', ''),
    'Q_Fee': ("*3/3* — Which matters more to you?", '', ''),
    'Opt_Fee': ("The lowest fee\nThe best benefits, even with a fee", '', ''),
    # ---------------------------------------------------------------- profile
    'Q_Employment': ("Great, now your details for eligibility. Are you…", '', ''),
    'Opt_Employment': ("Salaried\nSelf-employed", '', ''),
    'Q_Income': ("Your net monthly income? e.g. *85,000* or *1.2 lakh*", '', ''),
    'Q_Company': ("Which company do you work for (or your business name)?", '', ''),
    'Q_PAN': ("Your PAN? e.g. *ABCPS1234K* — shown back to you only masked. 🔒", '', ''),
    'Q_DOB': ("Your date of birth? e.g. *15/08/1990*", '', ''),
    'Q_Pincode': ("Your city and 6-digit PIN code? e.g. *Kolkata 700091*", '', ''),
    'Q_Bureau': ("🔍 May I run a *soft credit check* with CIBIL? It does *not* affect your credit score and helps me confirm which cards you qualify for.", '', ''),
    'Opt_Bureau': ("Yes, go ahead\nNo, skip", '', ''),
    'Bureau_Skipped': ("No problem — I'll recommend on your income for now; the credit check happens when you apply.", '', ''),
    'Q_AA': (
        "📊 One more thing: link your bank account through *Account Aggregator* to verify your income instantly — no salary slips needed. It's RBI-regulated and takes a minute.",
        '', ''),
    'Opt_AA': ("Verify with Account Aggregator\nSkip for now", '', ''),
    'AA_Done': ("✅ Income verified through Account Aggregator: *{income}/month*.", '', ''),
    'Invalid_Answer': ("Hmm, that doesn't look quite right. 🙂 Please try again.", '', ''),
    'Invalid_PAN': ("That doesn't look like a PAN — it's 10 characters like *ABCPS1234K*.", '', ''),
    'Invalid_DOB': ("Please share your date of birth as *DD/MM/YYYY*, e.g. *15/08/1990*.", '', ''),
    'Invalid_Pincode': ("Please share a 6-digit PIN code, e.g. *Kolkata 700091*.", '', ''),
    'Invalid_Income': ("Please type your monthly income as a number, e.g. *85,000* or *1.2 lakh*.", '', ''),
    # ---------------------------------------------------------------- recommendation
    'Recommend': (
        "✨ *Your best match: Bandhan {card}*\n_{tagline}_\n\nWhy it fits you:\n{why}\n\n> 🎁 {welcome}\n> 💳 {rewards}\n> ✈️ {lounge}\n> 🧾 Joining fee ₹{fee} · {waiver}\n> 💰 Indicative credit limit: *{limit}*{alt}{upgrade}",
        '', ''),
    'Recommend_Alt': ("\n\nAlso a good fit: *{card}* — {tagline}.", '', ''),
    'Recommend_Upgrade': ("\n\n💡 With a monthly income of {income} or more, you'd also qualify for *{card}*.", '', ''),
    'Opt_Recommend': ("Apply for {card}\nApply for {alt}\nCompare all cards\nTalk to a specialist", '', ''),
    'Opt_Recommend_Single': ("Apply for {card}\nCompare all cards\nTalk to a specialist", '', ''),
    'Not_Eligible': (
        "Thank you for sharing all that{name}. 🙏 Based on what you've told me, I can't offer a Bandhan credit card right now ({reason}).\n\nA specialist can look at other options with you — for example a card against a fixed deposit.",
        '', ''),
    'Opt_Not_Eligible': ("Talk to a specialist\nBack to the menu", '', ''),
    'Compare': (
        "📋 *Bandhan Bank credit cards*\n\n{lines}\n\n_Fees are indicative for this demo._",
        '', ''),
    'Compare_Line': ("*{card}* — {tagline}\n  {rewards} · {lounge} · Joining ₹{fee}", '', ''),
    'Opt_After_Compare': ("Find my card\nTalk to a specialist", '', ''),
    # ---------------------------------------------------------------- KYC and submit
    'Chosen': ("Great choice! 🎉 Let's get your *Bandhan {card}* — just KYC and you're done.", '', ''),
    'Q_Email': ("Your email for card statements?", '', ''),
    'Invalid_Email': ("Please share a valid email, e.g. *name@example.com*.", '', ''),
    'Q_Aadhaar': ("🪪 *Aadhaar eKYC* — enter the *last 4 digits* of your Aadhaar. I'll send an OTP to your Aadhaar-linked mobile.", '', ''),
    'Invalid_Aadhaar': ("Please enter just the last 4 digits of your Aadhaar.", '', ''),
    'Q_Aadhaar_OTP': ("Enter the 6-digit OTP sent to your Aadhaar-linked mobile. _(Demo OTP: {otp})_", '', ''),
    'Aadhaar_Done': ("✅ Aadhaar eKYC done — name and address matched.", '', ''),
    'Q_VKYC': (
        "🎥 Last step: a quick *Video KYC* (about 2 minutes) with our officer.\n👉 {link}\n\nReply *Done* once you've finished.",
        '', ''),
    'Opt_VKYC': ("Done\nDo it later", '', ''),
    'VKYC_Later': ("No problem — your application is saved. Use the same link anytime, then reply *Done*.", '', ''),
    'Review': (
        "📝 *Please confirm your application*\n\n> 💳 Bandhan *{card}* · limit *{limit}*\n> 👤 {fullname} · PAN {pan}\n> 🎂 {dob} · 📍 {city}\n> 💼 {employment} · {income}/month\n> 🪪 KYC: {kyc}\n\nBy confirming, you agree to the card's terms (MITC) and to Bandhan Bank verifying your details for this application.",
        '', ''),
    'Opt_Review': ("Confirm and submit\nTalk to a specialist", '', ''),
    # ---------------------------------------------------------------- decision
    'Approved': (
        "🎉 *Congratulations{name}! Your Bandhan {card} is approved.*\n\n> 💳 Virtual card: *{masked}*\n> 💰 Credit limit: *{limit}*\n> 🔖 Reference: ```{ref}```\n\nYour virtual card is ready to use online now 👉 {link} (set your PIN in the Bandhan mBanking app). Your physical card arrives in 5–7 working days.",
        '', ''),
    'Referred': (
        "Thank you{name}! 🙏 Your *Bandhan {card}* application ```{ref}``` is with our card team for a quick review. You'll hear from us within 24 hours — no need to resubmit anything.",
        '', ''),
    'Declined': (
        "Thank you for applying{name}. We're unable to approve the *{card}* right now.{alt}\n\nYou can also talk to a specialist about other options.",
        '', ''),
    'Declined_Alt': ("\n\nGood news — you're eligible for the *Bandhan {alt}* instead. Shall I apply for it?", '', ''),
    'Opt_Declined_Alt': ("Apply for {alt}\nTalk to a specialist", '', ''),
    'Done': ("Anything else I can help with? Reply *Menu* anytime. 😊", '', ''),
    'Decision_Approved_RM': (
        "🎉 Good news{name}! Our card team has *approved* your *Bandhan {card}*.\n\n> 💳 Virtual card: *{masked}*\n> 💰 Credit limit: *{limit}*\n> 🔖 Reference: ```{ref}```\n\nActivate it here 👉 {link}",
        '', ''),
    'Decision_Declined_RM': (
        "Hi{name}, our card team has reviewed your *Bandhan {card}* application ```{ref}```. We're unable to approve it right now. A specialist will call you to discuss other options.",
        '', ''),
    # ---------------------------------------------------------------- anytime
    'Handoff': ("Of course! 🙋 Connecting you with a Bandhan Bank card specialist. Everything you've shared is saved, so you won't need to repeat yourself.", '', ''),
    'Menu_Back': ("Back to the menu — your answers are saved. 👇", '', ''),
    'Language_Set': ("Sure — let's continue in English. 👍", 'ज़रूर — अब हम हिंदी में बात करेंगे। 👍', 'অবশ্যই — এখন আমরা বাংলায় কথা বলব। 👍'),
    'Resume': ("Welcome back{name}! 👋 Your card application is saved — let's pick up where you left off. 👇", '', ''),
    'Nudge_RM': (
        "Hi{name} 👋 This is {rm} from Bandhan Bank. You were finding your credit card with Bandhu — you'd already shared {done} details, so it takes just a minute to finish.\n\n👉 Reply *Continue* to pick up where you left off.",
        '', ''),
    'Status': ("📋 Your application ```{ref}``` for the Bandhan *{card}* is *{status}*.", '', ''),
    'Status_None': ("I couldn't find an application on this number yet. Reply *Menu* to find your card. 🙂", '', ''),
    'FAQ_Fallback': (
        "Good question! I can help with which card suits you, fees, rewards, lounges, eligibility and how to apply. For anything else, reply *Agent* to talk to a specialist.",
        '', ''),
    'FAQ_Fees': ("Joining fees range from ₹499 (Sparks) to ₹9,999 (Lumina), and each card's annual fee is waived when you spend enough in a year. I'll show the exact fee with your recommendation. _(Indicative for this demo.)_", '', ''),
    'FAQ_Eligibility': ("You need to be 21–60 (salaried) or 21–65 (self-employed) with a steady income — from ₹25,000 a month for Sparks up to ₹2 lakh for Lumina — and a healthy credit history. Existing Bandhan Bank customers often qualify faster. _(Indicative for this demo.)_", '', ''),
    'FAQ_Documents': ("Usually none! PAN, Aadhaar eKYC and a quick Video KYC — and income can be verified instantly through Account Aggregator. Existing Bandhan customers skip most of this.", '', ''),
    'FAQ_Lounge': ("Lounge access by card: Sparks 1 domestic a quarter · Ignite 1 domestic + 1 international · Flare 4 domestic + 1 international · Lumina 8 domestic + unlimited international.", '', ''),
    'FAQ_Rewards': ("Rewards per ₹200: Sparks 2 · Ignite 4 · Flare 10 · Lumina 16 points — with accelerated points on groceries, travel or international spends. Bandhan reward points never expire.", '', ''),
}
MESSAGES['Lang_Hint'] = LANG_HINT


def value_xml(field, value):
    if isinstance(value, bool):
        return f'    <values>\n        <field>{field}</field>\n        <value xsi:type="xsd:boolean">{str(value).lower()}</value>\n    </values>\n'
    if isinstance(value, (int, float)):
        return f'    <values>\n        <field>{field}</field>\n        <value xsi:type="xsd:double">{value}</value>\n    </values>\n'
    if value == '' or value is None:
        return f'    <values>\n        <field>{field}</field>\n        <value xsi:nil="true"/>\n    </values>\n'
    return f'    <values>\n        <field>{field}</field>\n        <value xsi:type="xsd:string">{escape(value)}</value>\n    </values>\n'


def record(type_name, dev_name, label, values):
    body = ''.join(value_xml(k, v) for k, v in values.items())
    xml = ('<?xml version="1.0" encoding="UTF-8"?>\n'
           '<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">\n'
           f'    <label>{escape(label[:40])}</label>\n    <protected>false</protected>\n{body}</CustomMetadata>\n')
    with open(os.path.join(OUT, f'{type_name}.{dev_name}.md-meta.xml'), 'w', encoding='utf-8') as fh:
        fh.write(xml)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    record('Bandhu_Config', 'Default', 'Default', CONFIG)
    for name, values in CARDS.items():
        record('Bandhu_Card', name, name, values)
    for key, (en, hi, bn) in MESSAGES.items():
        record('Bandhu_Message', key, key.replace('_', ' '), {'English__c': en, 'Hindi__c': hi, 'Bengali__c': bn})
    print('config 1, cards', len(CARDS), 'messages', len(MESSAGES))
