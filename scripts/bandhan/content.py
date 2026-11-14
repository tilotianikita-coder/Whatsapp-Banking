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
    'Send_Mode__c': 'ConversationMessage',  # LogOnly = compose and log only
    'WhatsApp_Channel__c': 'WhatsApp_BYOC',
    'Nudge_Definition__c': 'Bandhu_Text',
    'Country_Code__c': '91',
    'Idle_Minutes__c': 2,                    # production: e.g. 30
    'RM_Username__c': 'trailsignup.fbf7dadaec8000@salesforce.com',
    'Site_Url__c': 'https://trailsignup-fbf7dadaec8000.my.site.com/consumer/BandhuWeb',
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
        'ETB_Tiers__c': 'Microfinance;Deposit;Loan;Wealth',
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
        'ETB_Tiers__c': 'Deposit;Loan;Wealth',
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
        'ETB_Tiers__c': 'Deposit;Loan;Wealth',
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
        'ETB_Tiers__c': 'Deposit;Loan;Wealth',
        'Limit_Multiple__c': 3, 'Limit_Min__c': 300000, 'Limit_Max__c': 1500000,
        'Fit_Travel__c': 5, 'Fit_International__c': 5, 'Fit_Dining__c': 5, 'Fit_Groceries__c': 1, 'Fit_Shopping__c': 3,
        'Fit_Fuel__c': 3, 'Fit_Low_Fee__c': 0, 'Fit_High_Spend__c': 5, 'Color__c': '#B8860B',
    },
}

# Card serviceability by PIN prefix (PLACEHOLDER footprint: Bandhan Bank's eastern and north-eastern heartland plus metros).
# name: (label, prefixes, serviceable)
REGIONS = {
    'Kolkata': ('Kolkata', '700,711,712', True),
    'West_Bengal': ('Rest of West Bengal', '713,721,722,731,732,733,734,735,736,741,742,743', True),
    'North_East': ('Assam & North East', '78,79', True),
    'Bihar_Jharkhand': ('Bihar & Jharkhand', '80,81,82,83,84,85', True),
    'Odisha': ('Odisha', '75,76,77', True),
    'Metros': ('Metros', '11,40,41,56,60,50', True),
    'Rest_Of_India': ('Rest of India', '*', True),
    'Not_Serviceable': ('Not serviceable (Andaman, Ladakh, Lakshadweep)', '744,194,682555', False),
}

LANG_HINT = ('Reply *HI* for हिंदी / *BN* for বাংলা', 'Reply *EN* for English / *BN* for বাংলা', 'Reply *EN* for English / *HI* for हिंदी')

# key: (English, Hindi, Bengali). Hindi/Bengali are filled in by the translation pass; empty falls back to English.
MESSAGES = {
    # ---------------------------------------------------------------- welcome and consent
    'Welcome': (
        "Hi{name}! 👋 I'm *Bandhu*, your Bandhan Bank credit card advisor.\n\nTell me a little about how you spend and I'll match you with the right card — and you can apply right here in about 5 minutes. Paperless, with a virtual card on approval.",
        'नमस्ते{name}! 👋 मैं *Bandhu* हूँ, आपका Bandhan Bank credit card सलाहकार।\n\nमुझे थोड़ा बताइए कि आप कैसे खर्च करते हैं, और मैं आपके लिए सही card चुन दूँगा — और आप यहीं लगभग 5 मिनट में apply कर सकते हैं। पूरी तरह paperless, और approval मिलते ही virtual card।', 'নমস্কার{name}! 👋 আমি *Bandhu*, আপনার Bandhan Bank credit card উপদেষ্টা।\n\nআপনি কীভাবে খরচ করেন একটু বলুন, আমি আপনার জন্য সঠিক card খুঁজে দেব — আর এখানেই প্রায় 5 মিনিটে apply করতে পারবেন। সম্পূর্ণ paperless, approval হলেই virtual card।'),
    'Welcome_Existing': (
        "Welcome back{name}! 👋 I'm *Bandhu*, your Bandhan Bank card advisor.\n\nAs a Bandhan Bank customer you get a faster journey — I already have most of your details, so it's just a few questions.",
        'फिर से स्वागत है{name}! 👋 मैं *Bandhu* हूँ, आपका Bandhan Bank card सलाहकार।\n\nBandhan Bank ग्राहक होने के नाते आपकी journey और भी तेज़ है — आपकी ज़्यादातर जानकारी मेरे पास पहले से है, बस कुछ ही सवाल पूछने हैं।', 'আবার স্বাগতম{name}! 👋 আমি *Bandhu*, আপনার Bandhan Bank card উপদেষ্টা।\n\nBandhan Bank-এর গ্রাহক হিসেবে আপনার journey আরও দ্রুত — আপনার বেশিরভাগ তথ্য আমার কাছে আগে থেকেই আছে, তাই শুধু কয়েকটা প্রশ্ন।'),
    'Opt_Menu': ("Find my card\nCompare all cards\nAsk a question\nTalk to a specialist", 'मेरा card ढूँढें\nसभी cards की तुलना करें\nकोई सवाल पूछें\nकिसी specialist से बात करें', 'আমার card খুঁজুন\nসব card তুলনা করুন\nএকটি প্রশ্ন করুন\nএকজন specialist-এর সঙ্গে কথা বলুন'),
    'Consent': (
        "🔒 Before we begin: Bandhan Bank will use the details you share only to recommend a card and process your application, as per RBI guidelines and the Digital Personal Data Protection Act, 2023. If you already bank with us, this includes a soft credit check, which does not affect your credit score. You can withdraw consent anytime.",
        '🔒 शुरू करने से पहले: आप जो जानकारी देंगे, Bandhan Bank उसका इस्तेमाल सिर्फ़ आपको card सुझाने और आपकी application process करने के लिए करेगा, RBI दिशानिर्देशों और Digital Personal Data Protection Act, 2023 के अनुसार। अगर आप पहले से हमारे ग्राहक हैं, तो इसमें एक soft credit check भी शामिल है, जिससे आपके credit score पर कोई असर नहीं पड़ता। आप कभी भी अपनी सहमति वापस ले सकते हैं।', '🔒 শুরু করার আগে: আপনি যে তথ্য দেবেন, Bandhan Bank তা শুধু আপনাকে card সুপারিশ করতে ও আপনার application process করতে ব্যবহার করবে, RBI নির্দেশিকা এবং Digital Personal Data Protection Act, 2023 অনুযায়ী। আপনি যদি আগে থেকেই আমাদের গ্রাহক হন, তাহলে এর মধ্যে একটি soft credit check-ও আছে, যা আপনার credit score-এ কোনো প্রভাব ফেলে না। আপনি যেকোনো সময় সম্মতি প্রত্যাহার করতে পারেন।'),
    'Opt_Consent': ("I agree, let's start\nNot now", 'मैं सहमत हूँ, शुरू करें\nअभी नहीं', 'আমি সম্মত, শুরু করুন\nএখন নয়'),
    'Consent_Declined': ("No problem 🙂 Nothing has been saved. Say *Hi* whenever you'd like to find your card.", 'कोई बात नहीं 🙂 कुछ भी save नहीं किया गया है। जब भी अपना card ढूँढना हो, बस *Hi* लिखें।', 'কোনো সমস্যা নেই 🙂 কিছুই save করা হয়নি। যখনই আপনার card খুঁজতে চান, শুধু *Hi* লিখুন।'),
    # ---------------------------------------------------------------- identity
    'Q_Name': ("What's your full name, as on your PAN?", 'आपका पूरा नाम क्या है, जैसा आपके PAN पर लिखा है?', 'আপনার পুরো নাম কী, যেমন PAN-এ লেখা আছে?'),
    'Q_Mobile': ("Your 10-digit mobile number? I'll send a one-time password to verify it.", 'आपका 10 अंकों का mobile number? Verify करने के लिए मैं एक OTP भेजूँगा।', 'আপনার 10 সংখ্যার mobile number? যাচাই করার জন্য আমি একটি OTP পাঠাব।'),
    'OTP_Sent': ("Thanks{name}! I've sent a 6-digit OTP to {mobile}. Please enter it here. 🔐\n\n_(Demo OTP: {otp})_", 'धन्यवाद{name}! मैंने {mobile} पर 6 अंकों का OTP भेजा है। कृपया उसे यहाँ डालें। 🔐\n\n_(Demo OTP: {otp})_', 'ধন্যবাদ{name}! আমি {mobile}-এ একটি 6 সংখ্যার OTP পাঠিয়েছি। অনুগ্রহ করে এখানে লিখুন। 🔐\n\n_(Demo OTP: {otp})_'),
    'OTP_Wrong': ("That OTP didn't match — {left} attempt(s) left. Please try again.", 'यह OTP मेल नहीं खाया — {left} प्रयास बाकी हैं। कृपया फिर से कोशिश करें।', 'এই OTP মেলেনি — আর {left} বার চেষ্টা করতে পারবেন। অনুগ্রহ করে আবার চেষ্টা করুন।'),
    'OTP_Locked': ("For your security I've paused this application after too many wrong OTPs. A specialist will call you back.", 'आपकी सुरक्षा के लिए, कई बार गलत OTP डालने के कारण मैंने यह application रोक दी है। एक specialist आपको call करेंगे।', 'আপনার নিরাপত্তার জন্য, বারবার ভুল OTP দেওয়ায় আমি এই application আপাতত থামিয়ে রেখেছি। একজন specialist আপনাকে call করবেন।'),
    'Verified_New': ("✅ Verified! Now a few quick questions about how you spend, so I can find your best card.", '✅ Verify हो गया! अब आपके खर्च के बारे में कुछ छोटे सवाल, ताकि मैं आपके लिए सबसे अच्छा card ढूँढ सकूँ।', '✅ যাচাই হয়ে গেছে! এবার আপনার খরচ নিয়ে কয়েকটা ছোট প্রশ্ন, যাতে আমি আপনার জন্য সেরা card খুঁজে দিতে পারি।'),
    'Hold_Dormant': (
        "Thanks{name}. Your Bandhan Bank account has been inactive for a while, so it needs a quick reactivation before we can go ahead with a card. 🙏 Your relationship manager will call you to help — or visit any Bandhan Bank branch with your PAN and Aadhaar.",
        'धन्यवाद{name}। आपका Bandhan Bank account कुछ समय से inactive है, इसलिए card से पहले इसे एक बार reactivate करना होगा। 🙏 आपके relationship manager आपको call करके मदद करेंगे — या PAN और Aadhaar के साथ किसी भी Bandhan Bank branch पर जाएँ।',
        'ধন্যবাদ{name}। আপনার Bandhan Bank account কিছুদিন ধরে inactive, তাই card-এর আগে একবার reactivate করতে হবে। 🙏 আপনার relationship manager আপনাকে call করে সাহায্য করবেন — অথবা PAN ও Aadhaar নিয়ে যেকোনো Bandhan Bank branch-এ যান।'),
    'Hold_KYC': (
        "Thanks{name}. Your KYC with Bandhan Bank is due for a periodic update (Re-KYC), as RBI requires — once that's done we can go ahead with your card. 🙏 Your relationship manager will call you, or you can update it at any branch.",
        'धन्यवाद{name}। RBI के नियमों के अनुसार Bandhan Bank में आपका KYC update (Re-KYC) होना बाकी है — यह होते ही हम आपके card के साथ आगे बढ़ सकते हैं। 🙏 आपके relationship manager आपको call करेंगे, या आप किसी भी branch पर इसे update कर सकते हैं।',
        'ধন্যবাদ{name}। RBI-র নিয়ম অনুযায়ী Bandhan Bank-এ আপনার KYC update (Re-KYC) বাকি আছে — এটা হয়ে গেলেই আমরা আপনার card নিয়ে এগোতে পারব। 🙏 আপনার relationship manager আপনাকে call করবেন, অথবা যেকোনো branch-এ update করতে পারেন।'),
    'Hold_Review': (
        "Thanks{name}. We need to complete a routine review of your account before we can take a card application forward. 🙏 Your relationship manager will be in touch shortly.",
        'धन्यवाद{name}। card application आगे बढ़ाने से पहले हमें आपके account का एक routine review पूरा करना है। 🙏 आपके relationship manager जल्द ही आपसे संपर्क करेंगे।',
        'ধন্যবাদ{name}। card application এগোনোর আগে আপনার account-এর একটি routine review শেষ করতে হবে। 🙏 আপনার relationship manager শিগগিরই যোগাযোগ করবেন।'),
    'Verified_Existing': (
        "✅ Verified! Good to see you again{name}. I can see your Bandhan Bank {relationship} — so no income proof or extra KYC needed. Just a few questions about how you spend.",
        '✅ Verify हो गया! आपसे फिर मिलकर अच्छा लगा{name}। मुझे आपका Bandhan Bank {relationship} दिख रहा है — इसलिए income proof या अलग से KYC की ज़रूरत नहीं। बस आपके खर्च के बारे में कुछ सवाल।', '✅ যাচাই হয়ে গেছে! আপনাকে আবার দেখে ভালো লাগল{name}। আমি আপনার Bandhan Bank {relationship} দেখতে পাচ্ছি — তাই income proof বা আলাদা KYC লাগবে না। শুধু আপনার খরচ নিয়ে কয়েকটা প্রশ্ন।'),
    'Invalid_Mobile': ("Please enter a valid 10-digit mobile number, e.g. 98765 43210.", 'कृपया सही 10 अंकों का mobile number डालें, जैसे 98765 43210।', 'অনুগ্রহ করে সঠিক 10 সংখ্যার mobile number দিন, যেমন 98765 43210।'),
    'Invalid_Name': ("Please type your full name as on your PAN.", 'कृपया अपना पूरा नाम लिखें, जैसा आपके PAN पर है।', 'অনুগ্রহ করে PAN-এ যেমন আছে, সেভাবে আপনার পুরো নাম লিখুন।'),
    # ---------------------------------------------------------------- needs
    'Q_Spend': ("*1/3* — What do you spend most on? Pick all that apply, e.g. *1, 3*", '*1/3* — आप सबसे ज़्यादा किस पर खर्च करते हैं? जितने लागू हों सब चुनें, जैसे *1, 3*', '*1/3* — আপনি সবচেয়ে বেশি কীসে খরচ করেন? যতগুলো প্রযোজ্য সব বেছে নিন, যেমন *1, 3*'),
    'Opt_Spend': ("Travel & flights\nInternational trips\nDining & movies\nGroceries & everyday\nOnline shopping\nFuel", 'Travel और flights\nविदेश यात्राएँ\nDining और movies\nGroceries और रोज़ का खर्च\nOnline shopping\nFuel (पेट्रोल/डीज़ल)', 'Travel ও flights\nবিদেশ ভ্রমণ\nDining ও movies\nGroceries ও রোজকার খরচ\nOnline shopping\nFuel (পেট্রোল/ডিজেল)'),
    'Q_Monthly_Spend': ("*2/3* — Roughly how much would you spend on the card each month?", '*2/3* — आप हर महीने card पर लगभग कितना खर्च करेंगे?', '*2/3* — প্রতি মাসে card-এ মোটামুটি কত খরচ করবেন?'),
    'Opt_Monthly_Spend': ("Under ₹15,000\n₹15,000 – ₹50,000\n₹50,000 – ₹1 lakh\nMore than ₹1 lakh", '₹15,000 से कम\n₹15,000 – ₹50,000\n₹50,000 – ₹1 लाख\n₹1 लाख से ज़्यादा', '₹15,000-এর কম\n₹15,000 – ₹50,000\n₹50,000 – ₹1 লাখ\n₹1 লাখের বেশি'),
    'Q_Fee': ("*3/3* — Which matters more to you?", '*3/3* — आपके लिए क्या ज़्यादा ज़रूरी है?', '*3/3* — আপনার কাছে কোনটা বেশি গুরুত্বপূর্ণ?'),
    'Opt_Fee': ("The lowest fee\nThe best benefits, even with a fee", 'सबसे कम fee\nसबसे अच्छे benefits, भले ही fee लगे', 'সবচেয়ে কম fee\nসেরা benefits, fee লাগলেও'),
    # ---------------------------------------------------------------- profile
    'Q_Employment': ("Great, now your details for eligibility. Are you…", 'बढ़िया, अब eligibility के लिए आपकी जानकारी। आप…', 'দারুণ, এবার eligibility-র জন্য আপনার তথ্য। আপনি…'),
    'Opt_Employment': ("Salaried\nSelf-employed", 'नौकरीपेशा (Salaried)\nस्व-रोज़गार (Self-employed)', 'চাকরিজীবী (Salaried)\nস্বনিযুক্ত (Self-employed)'),
    'Q_Income': ("Your net monthly income? e.g. *85,000* or *1.2 lakh*", 'आपकी हर महीने की net income कितनी है? जैसे *85,000* या *1.2 lakh* (1.2 लाख)', 'আপনার মাসিক net income কত? যেমন *85,000* বা *1.2 lakh* (1.2 লাখ)'),
    'Q_Company': ("Which company do you work for (or your business name)?", 'आप किस company में काम करते हैं (या आपके business का नाम)?', 'আপনি কোন company-তে কাজ করেন (বা আপনার business-এর নাম)?'),
    'Q_PAN': ("Your PAN? e.g. *ABCPS1234K* — shown back to you only masked. 🔒", 'आपका PAN? जैसे *ABCPS1234K* — आपको यह सिर्फ़ masked रूप में ही दिखाया जाएगा। 🔒', 'আপনার PAN? যেমন *ABCPS1234K* — এটি আপনাকে শুধু masked অবস্থায় দেখানো হবে। 🔒'),
    'Q_DOB': ("Your date of birth? e.g. *15/08/1990*", 'आपकी जन्मतिथि? जैसे *15/08/1990*', 'আপনার জন্মতারিখ? যেমন *15/08/1990*'),
    'Q_Pincode': ("Your city and 6-digit PIN code? e.g. *Kolkata 700091*", 'आपका शहर और 6 अंकों का PIN code? जैसे *Kolkata 700091*', 'আপনার শহর ও 6 সংখ্যার PIN code? যেমন *Kolkata 700091*'),
    'Q_Bureau': ("🔍 May I run a *soft credit check* with CIBIL? It does *not* affect your credit score and helps me confirm which cards you qualify for.", '🔍 क्या मैं CIBIL से एक *soft credit check* कर सकता हूँ? इससे आपके credit score पर *कोई असर नहीं* पड़ता, और इससे पक्का हो जाता है कि आप किन cards के लिए eligible हैं।', '🔍 আমি কি CIBIL-এ একটি *soft credit check* করতে পারি? এতে আপনার credit score-এ *কোনো প্রভাব পড়ে না*, আর আপনি কোন card-গুলোর জন্য যোগ্য তা নিশ্চিত করতে সাহায্য হয়।'),
    'Opt_Bureau': ("Yes, go ahead\nNo, skip", 'हाँ, कर लीजिए\nनहीं, छोड़ दें', 'হ্যাঁ, করুন\nনা, বাদ দিন'),
    'Bureau_Skipped': ("No problem — I'll recommend on your income for now; the credit check happens when you apply.", 'कोई बात नहीं — अभी मैं आपकी income के आधार पर सुझाव दूँगा; credit check apply करते समय होगा।', 'কোনো সমস্যা নেই — আপাতত আমি আপনার income দেখে সুপারিশ করব; credit check হবে apply করার সময়।'),
    'Q_AA': (
        "📊 One more thing: link your bank accounts through *Account Aggregator* for instant approval — no documents needed. You share 24 months of statements, only for this card decision (consent valid 30 days). It's RBI-regulated and takes a minute.",
        '📊 एक और बात: तुरंत approval के लिए अपने bank accounts *Account Aggregator* से link करें — कोई document नहीं चाहिए। आप 24 महीने के statements सिर्फ़ इस card के फ़ैसले के लिए share करते हैं (consent 30 दिन के लिए)। यह RBI-regulated है और बस एक मिनट लगता है।',
        '📊 আর একটা কথা: সঙ্গে সঙ্গে approval-এর জন্য আপনার bank account-গুলো *Account Aggregator*-এর মাধ্যমে link করুন — কোনো document লাগবে না। আপনি 24 মাসের statements শুধু এই card-এর সিদ্ধান্তের জন্য share করবেন (consent 30 দিনের জন্য)। এটি RBI-regulated, আর মাত্র এক মিনিট লাগে।'),
    'Opt_AA': ("Connect my accounts\nSkip for now", 'मेरे accounts connect करें\nअभी के लिए छोड़ दें', 'আমার account connect করুন\nআপাতত বাদ দিন'),
    'AA_Insights': (
        "📊 *What your statements show* ({months} months, {banks} accounts):\n• Income stability: *{stability}/100* ({trend})\n• EMIs: {emi}/month ({foir}% of income)\n• Top spends: {top}{lifestyle}",
        '📊 *आपके statements से* ({months} महीने, {banks} accounts):\n• Income stability: *{stability}/100* ({trend})\n• EMIs: {emi}/महीना (income का {foir}%)\n• सबसे ज़्यादा खर्च: {top}{lifestyle}',
        '📊 *আপনার statements থেকে* ({months} মাস, {banks}টি account):\n• Income stability: *{stability}/100* ({trend})\n• EMI: {emi}/মাস (income-এর {foir}%)\n• সবচেয়ে বেশি খরচ: {top}{lifestyle}'),
    'AA_Done': ("✅ Income verified through Account Aggregator: *{income}/month*.", '✅ Account Aggregator से income verify हो गई: *{income}/महीना*।', '✅ Account Aggregator-এর মাধ্যমে income যাচাই হয়েছে: *{income}/মাস*।'),
    'Invalid_Answer': ("Hmm, that doesn't look quite right. 🙂 Please try again.", 'हम्म, यह कुछ ठीक नहीं लग रहा। 🙂 कृपया फिर से कोशिश करें।', 'হুম, এটা ঠিক মনে হচ্ছে না। 🙂 অনুগ্রহ করে আবার চেষ্টা করুন।'),
    'Invalid_PAN': ("That doesn't look like a PAN — it's 10 characters like *ABCPS1234K*.", 'यह PAN जैसा नहीं लग रहा — PAN में 10 characters होते हैं, जैसे *ABCPS1234K*।', 'এটা PAN বলে মনে হচ্ছে না — PAN-এ 10টি character থাকে, যেমন *ABCPS1234K*।'),
    'Invalid_DOB': ("Please share your date of birth as *DD/MM/YYYY*, e.g. *15/08/1990*.", 'कृपया अपनी जन्मतिथि *DD/MM/YYYY* के रूप में लिखें, जैसे *15/08/1990*।', 'অনুগ্রহ করে আপনার জন্মতারিখ *DD/MM/YYYY* আকারে লিখুন, যেমন *15/08/1990*।'),
    'Invalid_Pincode': ("Please share a 6-digit PIN code, e.g. *Kolkata 700091*.", 'कृपया 6 अंकों का PIN code लिखें, जैसे *Kolkata 700091*।', 'অনুগ্রহ করে 6 সংখ্যার PIN code লিখুন, যেমন *Kolkata 700091*।'),
    'Invalid_Income': ("Please type your monthly income as a number, e.g. *85,000* or *1.2 lakh*.", 'कृपया अपनी monthly income अंकों में लिखें, जैसे *85,000* या *1.2 lakh* (1.2 लाख)।', 'অনুগ্রহ করে আপনার মাসিক income সংখ্যায় লিখুন, যেমন *85,000* বা *1.2 lakh* (1.2 লাখ)।'),
    # ---------------------------------------------------------------- recommendation
    'Recommend': (
        "✨ *Your best match: Bandhan {card}*\n_{tagline}_\n\nWhy it fits you:\n{why}\n\n> 🎁 {welcome}\n> 💳 {rewards}\n> ✈️ {lounge}\n> 🧾 Joining fee ₹{fee} · {waiver}\n> 💰 Indicative credit limit: *{limit}*{alt}{upgrade}",
        '✨ *आपके लिए सबसे सही: Bandhan {card}*\n_{tagline}_\n\nयह आपके लिए क्यों सही है:\n{why}\n\n> 🎁 {welcome}\n> 💳 {rewards}\n> ✈️ {lounge}\n> 🧾 Joining fee ₹{fee} · {waiver}\n> 💰 अनुमानित credit limit: *{limit}*{alt}{upgrade}', '✨ *আপনার জন্য সেরা: Bandhan {card}*\n_{tagline}_\n\nকেন এটি আপনার জন্য উপযুক্ত:\n{why}\n\n> 🎁 {welcome}\n> 💳 {rewards}\n> ✈️ {lounge}\n> 🧾 Joining fee ₹{fee} · {waiver}\n> 💰 আনুমানিক credit limit: *{limit}*{alt}{upgrade}'),
    'Recommend_Alt': ("\n\nAlso a good fit: *{card}* — {tagline}.", '\n\nयह भी आपके लिए अच्छा रहेगा: *{card}* — {tagline}।', '\n\nএটিও আপনার জন্য ভালো হবে: *{card}* — {tagline}।'),
    'Recommend_Upgrade': ("\n\n💡 With a monthly income of {income} or more, you'd also qualify for *{card}*.", '\n\n💡 अगर आपकी monthly income {income} या उससे ज़्यादा है, तो आप *{card}* के लिए भी eligible होंगे।', '\n\n💡 আপনার মাসিক income {income} বা তার বেশি হলে, আপনি *{card}*-এর জন্যও যোগ্য হবেন।'),
    'Opt_Recommend': ("Apply for {card}\nApply for {alt}\nCompare all cards\nTalk to a specialist", '{card} के लिए apply करें\n{alt} के लिए apply करें\nसभी cards की तुलना करें\nकिसी specialist से बात करें', '{card}-এর জন্য apply করুন\n{alt}-এর জন্য apply করুন\nসব card তুলনা করুন\nএকজন specialist-এর সঙ্গে কথা বলুন'),
    'Opt_Recommend_Single': ("Apply for {card}\nCompare all cards\nTalk to a specialist", '{card} के लिए apply करें\nसभी cards की तुलना करें\nकिसी specialist से बात करें', '{card}-এর জন্য apply করুন\nসব card তুলনা করুন\nএকজন specialist-এর সঙ্গে কথা বলুন'),
    'Not_Eligible': (
        "Thank you for sharing all that{name}. 🙏 Based on what you've told me, I can't offer a Bandhan credit card right now ({reason}).\n\nA specialist can look at other options with you — for example a card against a fixed deposit.",
        'यह सब बताने के लिए धन्यवाद{name}। 🙏 आपने जो बताया उसके आधार पर, मैं अभी आपको Bandhan credit card नहीं दे पा रहा हूँ ({reason})।\n\nएक specialist आपके साथ दूसरे विकल्प देख सकते हैं — जैसे fixed deposit के बदले card।', 'এত কিছু জানানোর জন্য ধন্যবাদ{name}। 🙏 আপনি যা বলেছেন তার ভিত্তিতে, এই মুহূর্তে আমি আপনাকে Bandhan credit card দিতে পারছি না ({reason})।\n\nএকজন specialist আপনার সঙ্গে অন্য বিকল্পগুলো দেখতে পারেন — যেমন fixed deposit-এর বিপরীতে card।'),
    'Opt_Not_Eligible': ("Talk to a specialist\nBack to the menu", 'किसी specialist से बात करें\nवापस menu पर जाएँ', 'একজন specialist-এর সঙ্গে কথা বলুন\nmenu-তে ফিরে যান'),
    'Compare': (
        "📋 *Bandhan Bank credit cards*\n\n{lines}\n\n_Fees are indicative for this demo._",
        '📋 *Bandhan Bank credit cards*\n\n{lines}\n\n_इस demo में fees अनुमानित हैं।_', '📋 *Bandhan Bank credit cards*\n\n{lines}\n\n_এই demo-তে fees আনুমানিক।_'),
    'Compare_Line': ("*{card}* — {tagline}\n  {rewards} · {lounge} · Joining ₹{fee}", '*{card}* — {tagline}\n  {rewards} · {lounge} · Joining fee ₹{fee}', '*{card}* — {tagline}\n  {rewards} · {lounge} · Joining fee ₹{fee}'),
    'Opt_After_Compare': ("Find my card\nTalk to a specialist", 'मेरा card ढूँढें\nकिसी specialist से बात करें', 'আমার card খুঁজুন\nএকজন specialist-এর সঙ্গে কথা বলুন'),
    # ---------------------------------------------------------------- KYC and submit
    'Chosen': ("Great choice! 🎉 Let's get your *Bandhan {card}* — just KYC and you're done.", 'बढ़िया चुनाव! 🎉 चलिए आपका *Bandhan {card}* बनवाते हैं — बस KYC और काम पूरा।', 'দারুণ পছন্দ! 🎉 চলুন আপনার *Bandhan {card}* নিয়ে নিই — শুধু KYC, তারপরই কাজ শেষ।'),
    'Q_Email': ("Your email for card statements?", 'Card statements के लिए आपका email?', 'Card statement-এর জন্য আপনার email?'),
    'Invalid_Email': ("Please share a valid email, e.g. *name@example.com*.", 'कृपया सही email लिखें, जैसे *name@example.com*।', 'অনুগ্রহ করে সঠিক email দিন, যেমন *name@example.com*।'),
    'Q_Aadhaar': ("🪪 *Aadhaar eKYC* — enter the *last 4 digits* of your Aadhaar. I'll send an OTP to your Aadhaar-linked mobile.", '\U0001faaa *Aadhaar eKYC* — अपने Aadhaar के *आख़िरी 4 अंक* डालें। मैं आपके Aadhaar से जुड़े mobile पर OTP भेजूँगा।', '\U0001faaa *Aadhaar eKYC* — আপনার Aadhaar-এর *শেষ 4টি সংখ্যা* লিখুন। আমি আপনার Aadhaar-লিঙ্ক করা mobile-এ একটি OTP পাঠাব।'),
    'Invalid_Aadhaar': ("Please enter just the last 4 digits of your Aadhaar.", 'कृपया अपने Aadhaar के सिर्फ़ आख़िरी 4 अंक डालें।', 'অনুগ্রহ করে শুধু আপনার Aadhaar-এর শেষ 4টি সংখ্যা লিখুন।'),
    'Q_Aadhaar_OTP': ("Enter the 6-digit OTP sent to your Aadhaar-linked mobile. _(Demo OTP: {otp})_", 'आपके Aadhaar से जुड़े mobile पर भेजा गया 6 अंकों का OTP डालें। _(Demo OTP: {otp})_', 'আপনার Aadhaar-লিঙ্ক করা mobile-এ পাঠানো 6 সংখ্যার OTP লিখুন। _(Demo OTP: {otp})_'),
    'Aadhaar_Done': ("✅ Aadhaar eKYC done — name and address matched.", '✅ Aadhaar eKYC पूरा — नाम और पता मेल खा गए।', '✅ Aadhaar eKYC সম্পন্ন — নাম ও ঠিকানা মিলে গেছে।'),
    'Q_VKYC': (
        "🎥 Last step: a quick *Video KYC* (about 2 minutes) with our officer.\n👉 {link}\n\nReply *Done* once you've finished.",
        '🎥 आख़िरी कदम: हमारे officer के साथ एक छोटा-सा *Video KYC* (लगभग 2 मिनट)।\n👉 {link}\n\nपूरा होने के बाद *Done* लिखें।', '🎥 শেষ ধাপ: আমাদের officer-এর সঙ্গে একটি ছোট *Video KYC* (প্রায় 2 মিনিট)।\n👉 {link}\n\nশেষ হলে *Done* লিখুন।'),
    'Opt_VKYC': ("Done\nDo it later", 'Done — हो गया\nबाद में करें', 'Done — হয়ে গেছে\nপরে করব'),
    'VKYC_Later': ("No problem — your application is saved. Use the same link anytime, then reply *Done*.", 'कोई बात नहीं — आपकी application save हो गई है। कभी भी यही link इस्तेमाल करें, फिर *Done* लिखें।', 'কোনো সমস্যা নেই — আপনার application save করা আছে। যেকোনো সময় একই link ব্যবহার করুন, তারপর *Done* লিখুন।'),
    'Review': (
        "📝 *Please confirm your application*\n\n> 💳 Bandhan *{card}* · limit *{limit}*\n> 👤 {fullname} · PAN {pan}\n> 🎂 {dob} · 📍 {city}\n> 💼 {employment} · {income}/month\n> 🪪 KYC: {kyc}\n\nBy confirming, you agree to the card's terms (MITC) and to Bandhan Bank verifying your details for this application.",
        '📝 *कृपया अपनी application confirm करें*\n\n> 💳 Bandhan *{card}* · limit *{limit}*\n> 👤 {fullname} · PAN {pan}\n> 🎂 {dob} · 📍 {city}\n> 💼 {employment} · {income}/महीना\n> \U0001faaa KYC: {kyc}\n\nConfirm करके, आप card की शर्तों (MITC) से और इस application के लिए Bandhan Bank द्वारा आपकी जानकारी verify किए जाने से सहमत होते हैं।', '📝 *অনুগ্রহ করে আপনার application confirm করুন*\n\n> 💳 Bandhan *{card}* · limit *{limit}*\n> 👤 {fullname} · PAN {pan}\n> 🎂 {dob} · 📍 {city}\n> 💼 {employment} · {income}/মাস\n> \U0001faaa KYC: {kyc}\n\nConfirm করার মাধ্যমে, আপনি card-এর শর্তাবলি (MITC) এবং এই application-এর জন্য Bandhan Bank-কে আপনার তথ্য যাচাই করার সম্মতি দিচ্ছেন।'),
    'Opt_Review': ("Confirm and submit\nTalk to a specialist", 'Confirm करें और submit करें\nकिसी specialist से बात करें', 'Confirm করে submit করুন\nএকজন specialist-এর সঙ্গে কথা বলুন'),
    # ---------------------------------------------------------------- decision
    'Approved': (
        "🎉 *Congratulations{name}! Your Bandhan {card} is approved.*\n\n> 💳 Virtual card: *{masked}*\n> 💰 Credit limit: *{limit}*\n> 🔖 Reference: ```{ref}```\n\nYour virtual card is ready to use online now 👉 {link} (set your PIN in the Bandhan mBanking app). Your physical card arrives in 5–7 working days.",
        '🎉 *बधाई हो{name}! आपका Bandhan {card} approve हो गया है।*\n\n> 💳 Virtual card: *{masked}*\n> 💰 Credit limit: *{limit}*\n> 🔖 Reference: ```{ref}```\n\nआपका virtual card अभी online इस्तेमाल के लिए तैयार है 👉 {link} (Bandhan mBanking app में अपना PIN set करें)। आपका physical card 5–7 कामकाजी दिनों में पहुँच जाएगा।', '🎉 *অভিনন্দন{name}! আপনার Bandhan {card} approve হয়েছে।*\n\n> 💳 Virtual card: *{masked}*\n> 💰 Credit limit: *{limit}*\n> 🔖 Reference: ```{ref}```\n\nআপনার virtual card এখনই online ব্যবহারের জন্য তৈরি 👉 {link} (Bandhan mBanking app-এ আপনার PIN set করুন)। আপনার physical card 5–7 কার্যদিবসের মধ্যে পৌঁছে যাবে।'),
    'Referred': (
        "Thank you{name}! 🙏 Your *Bandhan {card}* application ```{ref}``` is with our card team for a quick review. You'll hear from us within 24 hours — no need to resubmit anything.",
        'धन्यवाद{name}! 🙏 आपकी *Bandhan {card}* application ```{ref}``` एक छोटे-से review के लिए हमारी card team के पास है। 24 घंटे के अंदर हम आपसे संपर्क करेंगे — कुछ भी दोबारा submit करने की ज़रूरत नहीं।', 'ধন্যবাদ{name}! 🙏 আপনার *Bandhan {card}* application ```{ref}``` একটি দ্রুত review-এর জন্য আমাদের card team-এর কাছে আছে। 24 ঘণ্টার মধ্যে আমরা আপনার সঙ্গে যোগাযোগ করব — কিছুই আবার submit করতে হবে না।'),
    'Declined': (
        "Thank you for applying{name}. We're unable to approve the *{card}* right now.{alt}\n\nYou can also talk to a specialist about other options.",
        'Apply करने के लिए धन्यवाद{name}। हम अभी *{card}* approve नहीं कर पा रहे हैं।{alt}\n\nदूसरे विकल्पों के बारे में आप किसी specialist से भी बात कर सकते हैं।', 'Apply করার জন্য ধন্যবাদ{name}। এই মুহূর্তে আমরা *{card}* approve করতে পারছি না।{alt}\n\nঅন্য বিকল্প নিয়ে আপনি একজন specialist-এর সঙ্গেও কথা বলতে পারেন।'),
    'Declined_Alt': ("\n\nGood news — you're eligible for the *Bandhan {alt}* instead. Shall I apply for it?", '\n\nअच्छी ख़बर — इसके बजाय आप *Bandhan {alt}* के लिए eligible हैं। क्या मैं इसके लिए apply कर दूँ?', '\n\nসুখবর — তার বদলে আপনি *Bandhan {alt}*-এর জন্য যোগ্য। আমি কি এটির জন্য apply করে দেব?'),
    'Opt_Declined_Alt': ("Apply for {alt}\nTalk to a specialist", '{alt} के लिए apply करें\nकिसी specialist से बात करें', '{alt}-এর জন্য apply করুন\nএকজন specialist-এর সঙ্গে কথা বলুন'),
    'Done': ("Anything else I can help with? Reply *Menu* anytime. 😊", 'क्या मैं किसी और चीज़ में मदद कर सकता हूँ? कभी भी *Menu* लिखें। 😊', 'আর কিছুতে সাহায্য করতে পারি? যেকোনো সময় *Menu* লিখুন। 😊'),
    'Decision_Approved_RM': (
        "🎉 Good news{name}! Our card team has *approved* your *Bandhan {card}*.\n\n> 💳 Virtual card: *{masked}*\n> 💰 Credit limit: *{limit}*\n> 🔖 Reference: ```{ref}```\n\nActivate it here 👉 {link}",
        '🎉 अच्छी ख़बर{name}! हमारी card team ने आपका *Bandhan {card}* *approve* कर दिया है।\n\n> 💳 Virtual card: *{masked}*\n> 💰 Credit limit: *{limit}*\n> 🔖 Reference: ```{ref}```\n\nइसे यहाँ activate करें 👉 {link}', '🎉 সুখবর{name}! আমাদের card team আপনার *Bandhan {card}* *approve* করেছে।\n\n> 💳 Virtual card: *{masked}*\n> 💰 Credit limit: *{limit}*\n> 🔖 Reference: ```{ref}```\n\nএখানে activate করুন 👉 {link}'),
    'Decision_Declined_RM': (
        "Hi{name}, our card team has reviewed your *Bandhan {card}* application ```{ref}```. We're unable to approve it right now. A specialist will call you to discuss other options.",
        'नमस्ते{name}, हमारी card team ने आपकी *Bandhan {card}* application ```{ref}``` का review किया है। हम अभी इसे approve नहीं कर पा रहे हैं। दूसरे विकल्पों पर बात करने के लिए एक specialist आपको call करेंगे।', 'নমস্কার{name}, আমাদের card team আপনার *Bandhan {card}* application ```{ref}``` review করেছে। এই মুহূর্তে আমরা এটি approve করতে পারছি না। অন্য বিকল্প নিয়ে কথা বলতে একজন specialist আপনাকে call করবেন।'),
    # ---------------------------------------------------------------- anytime
    'Handoff': ("Of course! 🙋 Connecting you with a Bandhan Bank card specialist. Everything you've shared is saved, so you won't need to repeat yourself.", 'ज़रूर! 🙋 आपको Bandhan Bank के card specialist से जोड़ रहा हूँ। आपकी दी हुई सारी जानकारी save है, इसलिए आपको कुछ भी दोहराना नहीं पड़ेगा।', 'অবশ্যই! 🙋 আপনাকে Bandhan Bank-এর একজন card specialist-এর সঙ্গে যুক্ত করছি। আপনার দেওয়া সব তথ্য save করা আছে, তাই আবার কিছু বলতে হবে না।'),
    'Menu_Back': ("Back to the menu — your answers are saved. 👇", 'वापस menu पर — आपके जवाब save हैं। 👇', 'menu-তে ফিরে এলাম — আপনার উত্তরগুলো save করা আছে। 👇'),
    'Language_Set': ("Sure — let's continue in English. 👍", 'ज़रूर — अब हम हिंदी में बात करेंगे। 👍', 'অবশ্যই — এখন আমরা বাংলায় কথা বলব। 👍'),
    'Resume': ("Welcome back{name}! 👋 Your card application is saved — let's pick up where you left off. 👇", 'फिर से स्वागत है{name}! 👋 आपकी card application save है — चलिए वहीं से आगे बढ़ते हैं जहाँ आपने छोड़ा था। 👇', 'আবার স্বাগতম{name}! 👋 আপনার card application save করা আছে — চলুন যেখানে থেমেছিলেন সেখান থেকেই শুরু করি। 👇'),
    'Nudge_RM': (
        "Hi{name} 👋 This is {rm} from Bandhan Bank. You were finding your credit card with Bandhu — you'd already shared {done} details, so it takes just a minute to finish.\n\n👉 Reply *Continue* to pick up where you left off.",
        'नमस्ते{name} 👋 Bandhan Bank से {rm} यहाँ। आप Bandhu के साथ अपना credit card ढूँढ रहे थे — आप पहले ही {done} details दे चुके हैं, इसलिए पूरा करने में बस एक मिनट लगेगा।\n\n👉 जहाँ छोड़ा था वहीं से आगे बढ़ने के लिए *Continue* लिखें।', 'নমস্কার{name} 👋 আমি Bandhan Bank থেকে {rm}। আপনি Bandhu-র সঙ্গে আপনার credit card খুঁজছিলেন — আপনি ইতিমধ্যেই {done} details দিয়েছেন, তাই শেষ করতে মাত্র এক মিনিট লাগবে।\n\n👉 যেখানে থেমেছিলেন সেখান থেকে শুরু করতে *Continue* লিখুন।'),
    'Status': ("📋 Your application ```{ref}``` for the Bandhan *{card}* is *{status}*.", '📋 Bandhan *{card}* के लिए आपकी application ```{ref}``` का status: *{status}*।', '📋 Bandhan *{card}*-এর জন্য আপনার application ```{ref}```-এর status: *{status}*।'),
    'Status_None': ("I couldn't find an application on this number yet. Reply *Menu* to find your card. 🙂", 'इस number पर मुझे अभी तक कोई application नहीं मिली। अपना card ढूँढने के लिए *Menu* लिखें। 🙂', 'এই number-এ এখনও কোনো application খুঁজে পাইনি। আপনার card খুঁজতে *Menu* লিখুন। 🙂'),
    'FAQ_Fallback': (
        "Good question! I can help with which card suits you, fees, rewards, lounges, eligibility and how to apply. For anything else, reply *Agent* to talk to a specialist.",
        'अच्छा सवाल! मैं इनमें मदद कर सकता हूँ: कौन-सा card आपके लिए सही है, fees, rewards, lounges, eligibility और apply कैसे करें। किसी और चीज़ के लिए, specialist से बात करने हेतु *Agent* लिखें।', 'ভালো প্রশ্ন! আমি এগুলোতে সাহায্য করতে পারি: কোন card আপনার জন্য উপযুক্ত, fees, rewards, lounge, eligibility আর কীভাবে apply করবেন। অন্য কিছুর জন্য, specialist-এর সঙ্গে কথা বলতে *Agent* লিখুন।'),
    'FAQ_Fees': ("Joining fees range from ₹499 (Sparks) to ₹9,999 (Lumina), and each card's annual fee is waived when you spend enough in a year. I'll show the exact fee with your recommendation. _(Indicative for this demo.)_", 'Joining fee ₹499 (Sparks) से ₹9,999 (Lumina) तक है, और साल भर में पर्याप्त खर्च करने पर हर card की annual fee माफ़ हो जाती है। आपके recommendation के साथ मैं सही fee दिखाऊँगा। _(इस demo के लिए अनुमानित।)_', 'Joining fee ₹499 (Sparks) থেকে ₹9,999 (Lumina) পর্যন্ত, আর বছরে যথেষ্ট খরচ করলে প্রতিটি card-এর annual fee মকুব হয়ে যায়। আপনার recommendation-এর সঙ্গে আমি সঠিক fee দেখাব। _(এই demo-র জন্য আনুমানিক।)_'),
    'FAQ_Eligibility': ("You need to be 21–60 (salaried) or 21–65 (self-employed) with a steady income — from ₹25,000 a month for Sparks up to ₹2 lakh for Lumina — and a healthy credit history. Existing Bandhan Bank customers often qualify faster. _(Indicative for this demo.)_", 'आपकी उम्र 21–60 (salaried) या 21–65 (self-employed) होनी चाहिए, नियमित income के साथ — Sparks के लिए ₹25,000 महीना से लेकर Lumina के लिए ₹2 लाख तक — और अच्छी credit history। मौजूदा Bandhan Bank ग्राहक अक्सर जल्दी qualify करते हैं। _(इस demo के लिए अनुमानित।)_', 'আপনার বয়স 21–60 (salaried) বা 21–65 (self-employed) হতে হবে, নিয়মিত income সহ — Sparks-এর জন্য মাসে ₹25,000 থেকে Lumina-র জন্য ₹2 লাখ পর্যন্ত — আর ভালো credit history। Bandhan Bank-এর বর্তমান গ্রাহকরা প্রায়ই দ্রুত qualify করেন। _(এই demo-র জন্য আনুমানিক।)_'),
    'FAQ_Documents': ("Usually none! PAN, Aadhaar eKYC and a quick Video KYC — and income can be verified instantly through Account Aggregator. Existing Bandhan customers skip most of this.", 'आमतौर पर कोई नहीं! PAN, Aadhaar eKYC और एक छोटा-सा Video KYC — और income तुरंत Account Aggregator से verify हो सकती है। मौजूदा Bandhan ग्राहकों को इनमें से ज़्यादातर की ज़रूरत ही नहीं पड़ती।', 'সাধারণত কিছুই লাগে না! PAN, Aadhaar eKYC আর একটি ছোট Video KYC — আর income সঙ্গে সঙ্গে Account Aggregator-এর মাধ্যমে যাচাই করা যায়। Bandhan-এর বর্তমান গ্রাহকদের এর বেশিরভাগই লাগে না।'),
    'FAQ_Lounge': ("Lounge access by card: Sparks 1 domestic a quarter · Ignite 1 domestic + 1 international · Flare 4 domestic + 1 international · Lumina 8 domestic + unlimited international.", 'हर card पर lounge access: Sparks — हर तिमाही 1 domestic · Ignite — 1 domestic + 1 international · Flare — 4 domestic + 1 international · Lumina — 8 domestic + unlimited international।', 'card অনুযায়ী lounge access: Sparks — প্রতি ত্রৈমাসিকে 1 domestic · Ignite — 1 domestic + 1 international · Flare — 4 domestic + 1 international · Lumina — 8 domestic + unlimited international।'),
    'FAQ_Rewards': ("Rewards per ₹200: Sparks 2 · Ignite 4 · Flare 10 · Lumina 16 points — with accelerated points on groceries, travel or international spends. Bandhan reward points never expire.", 'हर ₹200 पर reward points: Sparks 2 · Ignite 4 · Flare 10 · Lumina 16 — groceries, travel या international खर्च पर accelerated points के साथ। Bandhan reward points कभी expire नहीं होते।', 'প্রতি ₹200-এ reward points: Sparks 2 · Ignite 4 · Flare 10 · Lumina 16 — groceries, travel বা international খরচে accelerated points সহ। Bandhan reward points কখনো expire হয় না।'),
}
MESSAGES['Lang_Hint'] = LANG_HINT
# Salesforce trims leading line breaks from metadata text: these snippets are spaced by Apex instead
for _key in ('Recommend_Alt', 'Recommend_Upgrade', 'Declined_Alt'):
    MESSAGES[_key] = tuple(t.lstrip('\n') for t in MESSAGES[_key])


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
    for name, (label, prefixes, serviceable) in REGIONS.items():
        record('Bandhu_Region', name, label, {'PIN_Prefixes__c': prefixes, 'Serviceable__c': serviceable, 'RM_Username__c': ''})
    for name, values in CARDS.items():
        record('Bandhu_Card', name, name, values)
    for key, (en, hi, bn) in MESSAGES.items():
        record('Bandhu_Message', key, key.replace('_', ' '), {'English__c': en, 'Hindi__c': hi, 'Bengali__c': bn})
    print('config 1, cards', len(CARDS), 'messages', len(MESSAGES))
