"""Single source for LoanSeva copy + demo configuration.
Generates customMetadata records. Run from the project root: python3 scripts/content.py

Rates, fees and timelines are ILLUSTRATIVE DEMO PLACEHOLDERS — align with Kotak's published terms
before any customer-facing use. Tokens in {braces} are merged at runtime by Apex.
"""
import os
from xml.sax.saxutils import escape

OUT = 'force-app/main/default/customMetadata'

CONFIG = {
    'Demo_Mode__c': True,
    'Demo_OTP__c': '123456',
    'Max_OTP_Attempts__c': 3,
    'Base_Rate__c': 10.99,               # DEMO PLACEHOLDER
    'Self_Employed_Premium__c': 0.75,    # DEMO PLACEHOLDER
    'Good_Track_Premium__c': 1.00,       # DEMO PLACEHOLDER
    'Min_On_Time_EMIs__c': 10,
    'Max_FOIR_Pct__c': 55,               # DEMO PLACEHOLDER
    'Income_Bucket_Values__c': 'Below 50K=40000;50K-1L=75000;1L-2L=150000;2L+=250000',
    'Tenure_Options__c': '12,24,36,48,60',
    'Default_Tenure__c': 36,
    'Min_Topup_Amount__c': 50000,
    'Amount_Rounding__c': 25000,
    'Processing_Fee_Pct__c': 1.5,        # DEMO PLACEHOLDER
    'Processing_Fee_Min__c': 2999,       # DEMO PLACEHOLDER
    'Disbursal_Timeline__c': 'in as little as 24 hours',   # DEMO PLACEHOLDER
    'Rate_Display__c': '10.99% p.a.',    # DEMO PLACEHOLDER
    'Idle_Minutes_Before_Drop__c': 2,    # production: e.g. 30
    'Nudge_1_Delay_Minutes__c': 2,       # production: 1440 (T+24h)
    'Nudge_2_Delay_Minutes__c': 5,       # production: 4320 (T+72h)
    'Job_Interval_Minutes__c': 1,        # production: 60
    'Reference_Prefix__c': 'KMB-PLTU',
    'Send_Mode__c': 'ConversationMessage', # LogOnly = compose and log only, no WhatsApp send
    'WhatsApp_Channel__c': 'WhatsApp_BYOC',
    'Nudge_Definition__c': 'LoanSeva_Text',
    'Reengage_Definition__c': 'LoanSeva_Text',
    'Country_Code__c': '91',
    'RM_Owner_Username__c': 'trailsignup.5e5549adddf5d7@salesforce.com',
    'Registration_Url__c': 'https://trailsignup-5e5549adddf5d7.my.salesforce-sites.com/loanseva',
    # New Personal Loan (customers without a pre-approved offer) and mock underwriting — DEMO PLACEHOLDERS
    'Lan_Prefix__c': 'PL',
    'New_Loan_Reference_Prefix__c': 'KMB-PL',
    'New_Loan_Rate_Premium__c': 0.50,
    'New_Loan_Min_Amount__c': 50000,
    'New_Loan_Max_Amount__c': 2500000,
    'New_Loan_Income_Multiple__c': 20,
    'New_Loan_Min_Income__c': 25000,
    'Min_Age__c': 21,
    'Max_Age_At_Maturity__c': 60,
    'Min_Cibil_Score__c': 720,
    'Decline_Cibil_Score__c': 650,
}

LANG_FOOTER = {
    'en': 'Reply *HI* for हिंदी / *MR* for मराठी',
    'hi': 'Reply *EN* for English / *MR* for मराठी',
    'mr': 'Reply *EN* for English / *HI* for हिंदी',
}

# key: (English, Hindi, Marathi)
MESSAGES = {
    'Nudge': (
        "Hi {name}, great news from Kotak! 🎉 You're pre-qualified for a Personal Loan Top-Up of up to *{limit}* on your existing loan. Get a personalised offer in about 90 seconds — right here on WhatsApp.\n\n👉 Reply *Continue Here!* to begin.",
        "नमस्ते {name}, Kotak की ओर से खुशखबरी! 🎉 आपके मौजूदा लोन पर आप *{limit}* तक के पर्सनल लोन टॉप-अप के लिए प्री-क्वालिफाइड हैं। लगभग 90 सेकंड में अपना पर्सनलाइज़्ड ऑफ़र पाएँ — यहीं WhatsApp पर।\n\n👉 शुरू करने के लिए *Continue Here!* लिखें।",
        "नमस्कार {name}, Kotak कडून आनंदाची बातमी! 🎉 तुमच्या सध्याच्या कर्जावर तुम्ही *{limit}* पर्यंतच्या पर्सनल लोन टॉप-अपसाठी प्री-क्वालिफाइड आहात. सुमारे 90 सेकंदात तुमची वैयक्तिक ऑफर मिळवा — इथेच WhatsApp वर.\n\n👉 सुरू करण्यासाठी *Continue Here!* लिहा.",
    ),
    'Nudge_Generic': (
        "Hi there! 👋 Thanks for your interest in the Kotak Personal Loan Top-Up. Unlock more for your plans with a personalised offer in about 90 seconds — right here on WhatsApp.\n\n👉 Reply *Continue Here!* to begin.",
        "नमस्ते! 👋 Kotak पर्सनल लोन टॉप-अप में रुचि के लिए धन्यवाद। लगभग 90 सेकंड में पर्सनलाइज़्ड ऑफ़र के साथ अपने प्लान्स के लिए और पाएँ — यहीं WhatsApp पर।\n\n👉 शुरू करने के लिए *Continue Here!* लिखें।",
        "नमस्कार! 👋 Kotak पर्सनल लोन टॉप-अपमध्ये रस दाखवल्याबद्दल धन्यवाद. सुमारे 90 सेकंदात वैयक्तिक ऑफरसह तुमच्या योजनांसाठी अधिक मिळवा — इथेच WhatsApp वर.\n\n👉 सुरू करण्यासाठी *Continue Here!* लिहा.",
    ),
    'Reengage_1': (
        "Hi {name} 👋 Your Kotak Top-Up{purpose} is just a few taps away — everything you shared is saved, so you can pick up right where you left off.\n\n👉 Reply *Continue* to see your personalised offer.",
        "नमस्ते {name} 👋 आपका Kotak टॉप-अप{purpose} बस कुछ ही कदम दूर है — आपकी दी गई सारी जानकारी सेव है, जहाँ छोड़ा था वहीं से शुरू करें।\n\n👉 अपना पर्सनलाइज़्ड ऑफ़र देखने के लिए *Continue* लिखें।",
        "नमस्कार {name} 👋 तुमचा Kotak टॉप-अप{purpose} फक्त काही पावलांवर आहे — तुम्ही दिलेली सर्व माहिती सेव्ह आहे, जिथे थांबलात तिथून पुढे सुरू करा.\n\n👉 तुमची वैयक्तिक ऑफर पाहण्यासाठी *Continue* लिहा.",
    ),
    'Reengage_2': (
        "{name}, your pre-qualified Kotak Top-Up is still reserved for you ✨ It takes about a minute to finish.\n\n👉 Reply *Continue* to pick up, or *Agent* and a specialist will call you.",
        "{name}, आपका प्री-क्वालिफाइड Kotak टॉप-अप अभी भी आपके लिए रिज़र्व है ✨ पूरा करने में लगभग एक मिनट लगता है।\n\n👉 आगे बढ़ने के लिए *Continue* लिखें, या *Agent* लिखें और हमारे विशेषज्ञ आपको कॉल करेंगे।",
        "{name}, तुमचा प्री-क्वालिफाइड Kotak टॉप-अप अजूनही तुमच्यासाठी राखीव आहे ✨ पूर्ण करायला सुमारे एक मिनिट लागतो.\n\n👉 पुढे जाण्यासाठी *Continue* लिहा, किंवा *Agent* लिहा आणि आमचे तज्ज्ञ तुम्हाला कॉल करतील.",
    ),
    'Welcome': (
        "Hi {name}! 👋 I'm *LoanSeva by Kotak*, your personal loan assistant.\n\nYou're pre-qualified for a Top-Up of up to *{limit}*. How can I help?\n\n1️⃣ See my personalised offer\n2️⃣ Ask a question about Top-Up\n3️⃣ Talk to a specialist\n\n" + LANG_FOOTER['en'],
        "नमस्ते {name}! 👋 मैं हूँ *LoanSeva by Kotak*, आपका पर्सनल लोन असिस्टेंट।\n\nआप *{limit}* तक के टॉप-अप के लिए प्री-क्वालिफाइड हैं। मैं आपकी कैसे मदद करूँ?\n\n1️⃣ मेरा पर्सनलाइज़्ड ऑफ़र देखें\n2️⃣ टॉप-अप के बारे में सवाल पूछें\n3️⃣ विशेषज्ञ से बात करें\n\n" + LANG_FOOTER['hi'],
        "नमस्कार {name}! 👋 मी *LoanSeva by Kotak*, तुमचा पर्सनल लोन सहाय्यक.\n\nतुम्ही *{limit}* पर्यंतच्या टॉप-अपसाठी प्री-क्वालिफाइड आहात. मी कशी मदत करू?\n\n1️⃣ माझी वैयक्तिक ऑफर पहा\n2️⃣ टॉप-अपबद्दल प्रश्न विचारा\n3️⃣ तज्ज्ञांशी बोला\n\n" + LANG_FOOTER['mr'],
    ),
    'Welcome_Generic': (
        "Hi! 👋 I'm *LoanSeva by Kotak*, your personal loan assistant. I can help you unlock a Personal Loan Top-Up on your existing Kotak loan.\n\n1️⃣ See my personalised offer\n2️⃣ Ask a question about Top-Up\n3️⃣ Talk to a specialist\n\n" + LANG_FOOTER['en'],
        "नमस्ते! 👋 मैं हूँ *LoanSeva by Kotak*, आपका पर्सनल लोन असिस्टेंट। मैं आपके मौजूदा Kotak लोन पर पर्सनल लोन टॉप-अप पाने में मदद कर सकता हूँ।\n\n1️⃣ मेरा पर्सनलाइज़्ड ऑफ़र देखें\n2️⃣ टॉप-अप के बारे में सवाल पूछें\n3️⃣ विशेषज्ञ से बात करें\n\n" + LANG_FOOTER['hi'],
        "नमस्कार! 👋 मी *LoanSeva by Kotak*, तुमचा पर्सनल लोन सहाय्यक. तुमच्या सध्याच्या Kotak कर्जावर पर्सनल लोन टॉप-अप मिळवण्यासाठी मी मदत करू शकतो.\n\n1️⃣ माझी वैयक्तिक ऑफर पहा\n2️⃣ टॉप-अपबद्दल प्रश्न विचारा\n3️⃣ तज्ज्ञांशी बोला\n\n" + LANG_FOOTER['mr'],
    ),
    'FAQ_Nudge': (
        "Want to see your personalised offer? Reply *Yes* to verify in 30 seconds.",
        "क्या आप अपना पर्सनलाइज़्ड ऑफ़र देखना चाहेंगे? 30 सेकंड में वेरिफ़ाई करने के लिए *Yes* लिखें।",
        "तुमची वैयक्तिक ऑफर पाहायची आहे का? 30 सेकंदात व्हेरिफाय करण्यासाठी *Yes* लिहा.",
    ),
    # No "reply Yes" here: the engine appends the step-aware follow-up (at the offer, Yes would accept it).
    'FAQ_Not_Found': (
        "That's a great question — I want to make sure you get the exact answer, so I'll have a Kotak specialist confirm it on your callback. 🙏\n\nMeanwhile, I can help with rates, uses, timelines and how Top-Up differs from a new loan.",
        "बहुत अच्छा सवाल — आपको सटीक जवाब मिले, इसलिए कॉलबैक पर Kotak विशेषज्ञ इसकी पुष्टि करेंगे। 🙏\n\nतब तक मैं ब्याज दर, उपयोग, समय-सीमा और टॉप-अप व नए लोन के अंतर के बारे में बता सकता हूँ।",
        "छान प्रश्न — तुम्हाला अचूक उत्तर मिळावे म्हणून कॉलबॅकवर Kotak तज्ज्ञ याची खात्री करतील. 🙏\n\nतोपर्यंत मी व्याजदर, वापर, कालावधी आणि टॉप-अप व नवीन कर्जातील फरक याबद्दल सांगू शकतो.",
    ),
    'Resume_Prompt': (
        "Shall we continue where we left off? 👇",
        "क्या हम वहीं से आगे बढ़ें जहाँ रुके थे? 👇",
        "आपण जिथे थांबलो होतो तिथून पुढे जाऊया? 👇",
    ),
    'Language_Options': (
        "I can chat in English, हिंदी or मराठी. Reply *EN*, *HI* or *MR*.",
        "मैं English, हिंदी या मराठी में बात कर सकता हूँ। *EN*, *HI* या *MR* लिखें।",
        "मी English, हिंदी किंवा मराठीत बोलू शकतो. *EN*, *HI* किंवा *MR* लिहा.",
    ),
    'Language_Set': (
        "Sure — let's continue in English. 👍",
        "ज़रूर — अब हम हिंदी में बात करेंगे। 👍",
        "नक्की — आता आपण मराठीत बोलूया. 👍",
    ),
    'Verify_Prompt': (
        "Let's quickly verify you 🔐 Please share your *full name* and your *registered mobile number* (10 digits).",
        "चलिए जल्दी से आपको वेरिफ़ाई करते हैं 🔐 कृपया अपना *पूरा नाम* और *रजिस्टर्ड मोबाइल नंबर* (10 अंक) बताएँ।",
        "चला, पटकन तुमची पडताळणी करूया 🔐 कृपया तुमचे *पूर्ण नाव* आणि *नोंदणीकृत मोबाइल नंबर* (10 अंकी) सांगा.",
    ),
    'Verify_Not_Found': (
        "I couldn't find a Kotak personal loan linked to {mobile}. Please double-check the number, or reply *Agent* and a specialist will help you.",
        "{mobile} से जुड़ा कोई Kotak पर्सनल लोन नहीं मिला। कृपया नंबर दोबारा जाँचें, या *Agent* लिखें और विशेषज्ञ आपकी मदद करेंगे।",
        "{mobile} शी जोडलेले Kotak पर्सनल लोन सापडले नाही. कृपया नंबर पुन्हा तपासा, किंवा *Agent* लिहा आणि तज्ज्ञ तुम्हाला मदत करतील.",
    ),
    'Verify_Name_Mismatch': (
        "Hmm, that name doesn't match our records for this number. Please share your name exactly as on your loan account.",
        "यह नाम इस नंबर के रिकॉर्ड से मेल नहीं खाता। कृपया अपना नाम वैसे ही लिखें जैसा लोन अकाउंट में है।",
        "हे नाव या नंबरच्या नोंदीशी जुळत नाही. कृपया कर्ज खात्यावर आहे तसेच तुमचे नाव लिहा.",
    ),
    'OTP_Sent': (
        "Thanks {name}! I've sent a 6-digit OTP to {mobile}. Please type it here. 🔐",
        "धन्यवाद {name}! मैंने {mobile} पर 6 अंकों का OTP भेजा है। कृपया उसे यहाँ लिखें। 🔐",
        "धन्यवाद {name}! मी {mobile} वर 6 अंकी OTP पाठवला आहे. कृपया तो इथे लिहा. 🔐",
    ),
    'OTP_Sent_Demo': (
        "Thanks {name}! I've sent a 6-digit OTP to {mobile}. Please type it here. 🔐\n\n_(Demo OTP: {otp})_",
        "धन्यवाद {name}! मैंने {mobile} पर 6 अंकों का OTP भेजा है। कृपया उसे यहाँ लिखें। 🔐\n\n_(डेमो OTP: {otp})_",
        "धन्यवाद {name}! मी {mobile} वर 6 अंकी OTP पाठवला आहे. कृपया तो इथे लिहा. 🔐\n\n_(डेमो OTP: {otp})_",
    ),
    'OTP_Reprompt': (
        "Please enter the 6-digit OTP sent to your registered mobile. 🔐",
        "कृपया अपने रजिस्टर्ड मोबाइल पर भेजा गया 6 अंकों का OTP लिखें। 🔐",
        "कृपया तुमच्या नोंदणीकृत मोबाइलवर पाठवलेला 6 अंकी OTP लिहा. 🔐",
    ),
    'OTP_Wrong': (
        "That OTP didn't match. You have {left} attempt(s) left — please try again.",
        "यह OTP मेल नहीं खाया। आपके पास {left} प्रयास बाकी हैं — कृपया फिर से कोशिश करें।",
        "हा OTP जुळला नाही. तुमच्याकडे {left} प्रयत्न शिल्लक आहेत — कृपया पुन्हा प्रयत्न करा.",
    ),
    'OTP_Locked': (
        "For your security, I've paused verification after too many attempts. 🔒 No worries — a Kotak specialist will call you shortly on your registered number to help you finish.",
        "आपकी सुरक्षा के लिए, कई प्रयासों के बाद वेरिफ़िकेशन रोक दिया गया है। 🔒 चिंता न करें — Kotak विशेषज्ञ जल्द ही आपके रजिस्टर्ड नंबर पर कॉल करके मदद करेंगे।",
        "तुमच्या सुरक्षेसाठी, अनेक प्रयत्नांनंतर पडताळणी थांबवली आहे. 🔒 काळजी करू नका — Kotak तज्ज्ञ लवकरच तुमच्या नोंदणीकृत नंबरवर कॉल करून मदत करतील.",
    ),
    'Loan_Snapshot': (
        "✅ Verified! Here's your existing loan, {name}:\n\n> 🏦 Loan account: {account}\n> 💰 Outstanding principal: {outstanding}\n> 📅 EMI: {emi}/month\n> ⏳ Tenure remaining: {tenure} months\n> 📈 Repayment track: {ontime}/{due} EMIs on time {trackIcon}\n\nIs this correct? Reply *Yes* to continue or *No* if something looks off.",
        "✅ वेरिफ़ाई हो गया! {name}, यह रहा आपका मौजूदा लोन:\n\n> 🏦 लोन अकाउंट: {account}\n> 💰 बकाया मूलधन: {outstanding}\n> 📅 EMI: {emi}/माह\n> ⏳ बची अवधि: {tenure} महीने\n> 📈 भुगतान रिकॉर्ड: {ontime}/{due} EMI समय पर {trackIcon}\n\nक्या यह सही है? आगे बढ़ने के लिए *Yes* या कुछ गलत हो तो *No* लिखें।",
        "✅ पडताळणी पूर्ण! {name}, हे तुमचे सध्याचे कर्ज:\n\n> 🏦 कर्ज खाते: {account}\n> 💰 थकीत मुद्दल: {outstanding}\n> 📅 EMI: {emi}/महिना\n> ⏳ उर्वरित कालावधी: {tenure} महिने\n> 📈 परतफेड रेकॉर्ड: {ontime}/{due} EMI वेळेवर {trackIcon}\n\nहे बरोबर आहे का? पुढे जाण्यासाठी *Yes* किंवा काही चुकीचे असल्यास *No* लिहा.",
    ),
    'Loan_Confirm_Reprompt': (
        "Do the loan details above look correct? Reply *Yes* or *No*.",
        "क्या ऊपर दिए लोन विवरण सही हैं? *Yes* या *No* लिखें।",
        "वरील कर्जाचे तपशील बरोबर आहेत का? *Yes* किंवा *No* लिहा.",
    ),
    'Loan_Disputed': (
        "Thanks for flagging that. 🙏 I've asked a Kotak specialist to review your loan details — they'll call you shortly.",
        "बताने के लिए धन्यवाद। 🙏 मैंने Kotak विशेषज्ञ से आपके लोन विवरण की समीक्षा करने को कहा है — वे जल्द ही कॉल करेंगे।",
        "कळवल्याबद्दल धन्यवाद. 🙏 मी Kotak तज्ज्ञांना तुमच्या कर्जाचे तपशील तपासायला सांगितले आहे — ते लवकरच कॉल करतील.",
    ),
    'Personalise_Intro': (
        "Great! Let's personalise your offer — 5 quick questions, about 60 seconds. ⏱️",
        "बढ़िया! चलिए आपका ऑफ़र पर्सनलाइज़ करते हैं — 5 छोटे सवाल, लगभग 60 सेकंड। ⏱️",
        "छान! चला, तुमची ऑफर वैयक्तिक करूया — 5 छोटे प्रश्न, सुमारे 60 सेकंद. ⏱️",
    ),
    'Personalise_Invalid': (
        "Sorry, I didn't catch that. 🙂 Please reply with one of the options below.",
        "माफ़ कीजिए, मैं समझ नहीं पाया। 🙂 कृपया नीचे दिए विकल्पों में से एक चुनें।",
        "माफ करा, मला समजले नाही. 🙂 कृपया खालील पर्यायांपैकी एक निवडा.",
    ),
    'Q_Employment': (
        "*1/5* — What's your employment type?\n\n1️⃣ Salaried\n2️⃣ Self-employed",
        "*1/5* — आपका रोज़गार प्रकार क्या है?\n\n1️⃣ वेतनभोगी (Salaried)\n2️⃣ स्व-रोज़गार (Self-employed)",
        "*1/5* — तुमचा रोजगार प्रकार कोणता?\n\n1️⃣ पगारदार (Salaried)\n2️⃣ स्वयंरोजगार (Self-employed)",
    ),
    'Q_Company': (
        "*2/5* — Which company do you work with?",
        "*2/5* — आप किस कंपनी में काम करते हैं?",
        "*2/5* — तुम्ही कोणत्या कंपनीत काम करता?",
    ),
    'Q_Business': (
        "*2/5* — What's the name of your business?",
        "*2/5* — आपके व्यवसाय का नाम क्या है?",
        "*2/5* — तुमच्या व्यवसायाचे नाव काय आहे?",
    ),
    'Q_Income': (
        "*3/5* — What's your monthly income?\n\n1️⃣ Below ₹50K\n2️⃣ ₹50K – 1L\n3️⃣ ₹1L – 2L\n4️⃣ ₹2L+",
        "*3/5* — आपकी मासिक आय कितनी है?\n\n1️⃣ ₹50K से कम\n2️⃣ ₹50K – 1L\n3️⃣ ₹1L – 2L\n4️⃣ ₹2L+",
        "*3/5* — तुमचे मासिक उत्पन्न किती आहे?\n\n1️⃣ ₹50K पेक्षा कमी\n2️⃣ ₹50K – 1L\n3️⃣ ₹1L – 2L\n4️⃣ ₹2L+",
    ),
    'Q_Purpose': (
        "*4/5* — What are you planning? ✨\n\n1️⃣ Home renovation\n2️⃣ Education\n3️⃣ Medical\n4️⃣ Travel\n5️⃣ Wedding\n6️⃣ Other",
        "*4/5* — आप क्या प्लान कर रहे हैं? ✨\n\n1️⃣ घर का नवीनीकरण\n2️⃣ शिक्षा\n3️⃣ चिकित्सा\n4️⃣ यात्रा\n5️⃣ शादी\n6️⃣ अन्य",
        "*4/5* — तुम्ही काय योजना करत आहात? ✨\n\n1️⃣ घराचे नूतनीकरण\n2️⃣ शिक्षण\n3️⃣ वैद्यकीय\n4️⃣ प्रवास\n5️⃣ लग्न\n6️⃣ इतर",
    ),
    'Q_Amount': (
        "*5/5* — How much would you like to unlock? (pre-approved up to {limit})\n\n{options}\n\nOr type an amount, e.g. *3 lakh*.",
        "*5/5* — आप कितनी राशि चाहेंगे? ({limit} तक प्री-अप्रूव्ड)\n\n{options}\n\nया राशि लिखें, जैसे *3 lakh*।",
        "*5/5* — तुम्हाला किती रक्कम हवी आहे? ({limit} पर्यंत प्री-अप्रूव्ड)\n\n{options}\n\nकिंवा रक्कम लिहा, उदा. *3 lakh*.",
    ),
    'Offer_Card': (
        "🎉 Great news, {name}! Here's your personalised Top-Up offer:\n\n> 💰 Amount: *{amount}*\n> 📈 Rate: *{rate}% p.a.*\n> 📅 Tenure: *{tenure} months*\n> 💳 EMI: *{emi}/month*\n> 🧾 Processing fee: {fee} + GST\n\nOther tenures: {otherTenures}\n\n_This is a preliminary offer, subject to final verification._\n\n1️⃣ Accept offer\n2️⃣ Change amount or tenure\n3️⃣ Ask a question",
        "🎉 बधाई हो, {name}! यह रहा आपका पर्सनलाइज़्ड टॉप-अप ऑफ़र:\n\n> 💰 राशि: *{amount}*\n> 📈 ब्याज दर: *{rate}% प्रति वर्ष*\n> 📅 अवधि: *{tenure} महीने*\n> 💳 EMI: *{emi}/माह*\n> 🧾 प्रोसेसिंग शुल्क: {fee} + GST\n\nअन्य अवधि: {otherTenures}\n\n_यह एक प्रारंभिक ऑफ़र है, अंतिम सत्यापन के अधीन।_\n\n1️⃣ ऑफ़र स्वीकार करें\n2️⃣ राशि या अवधि बदलें\n3️⃣ सवाल पूछें",
        "🎉 अभिनंदन, {name}! ही तुमची वैयक्तिक टॉप-अप ऑफर:\n\n> 💰 रक्कम: *{amount}*\n> 📈 व्याजदर: *{rate}% प्रतिवर्ष*\n> 📅 कालावधी: *{tenure} महिने*\n> 💳 EMI: *{emi}/महिना*\n> 🧾 प्रोसेसिंग शुल्क: {fee} + GST\n\nइतर कालावधी: {otherTenures}\n\n_ही प्राथमिक ऑफर आहे, अंतिम पडताळणीच्या अधीन._\n\n1️⃣ ऑफर स्वीकारा\n2️⃣ रक्कम किंवा कालावधी बदला\n3️⃣ प्रश्न विचारा",
    ),
    'Offer_Capped': (
        "ℹ️ Based on your income and current EMI, the best amount I can offer right now is {max}.",
        "ℹ️ आपकी आय और मौजूदा EMI के आधार पर, अभी मैं अधिकतम {max} का ऑफ़र दे सकता हूँ।",
        "ℹ️ तुमचे उत्पन्न आणि सध्याच्या EMI नुसार, सध्या मी जास्तीत जास्त {max} ची ऑफर देऊ शकतो.",
    ),
    'Offer_Refer': (
        "Thanks {name}! 🙏 Based on your details, I'd like a Kotak loan specialist to design the best option for you personally. They'll call you within 24 hours.",
        "धन्यवाद {name}! 🙏 आपके विवरण के आधार पर, Kotak लोन विशेषज्ञ आपके लिए सबसे अच्छा विकल्प तैयार करेंगे। वे 24 घंटों में आपको कॉल करेंगे।",
        "धन्यवाद {name}! 🙏 तुमच्या तपशिलांनुसार, Kotak कर्ज तज्ज्ञ तुमच्यासाठी सर्वोत्तम पर्याय तयार करतील. ते 24 तासांत तुम्हाला कॉल करतील.",
    ),
    'Refer_Reprompt': (
        "A Kotak loan specialist will call you within 24 hours to design your option. 🙏\n\nMeanwhile, you can try a different amount or tenure (e.g. *2 lakh for 48 months*), or ask me any question about Top-Up.",
        "Kotak लोन विशेषज्ञ 24 घंटों में आपको कॉल करके आपका विकल्प तैयार करेंगे। 🙏\n\nतब तक आप कोई दूसरी राशि या अवधि आज़मा सकते हैं (जैसे *2 लाख 48 महीने*), या टॉप-अप के बारे में कोई भी सवाल पूछें।",
        "Kotak कर्ज तज्ज्ञ 24 तासांत तुम्हाला कॉल करून तुमचा पर्याय तयार करतील. 🙏\n\nतोपर्यंत तुम्ही वेगळी रक्कम किंवा कालावधी वापरून पाहू शकता (उदा. *2 लाख 48 महिने*), किंवा टॉप-अपबद्दल कोणताही प्रश्न विचारा.",
    ),
    'Offer_Reprompt': (
        "Would you like to go ahead with this offer?\n\n1️⃣ Accept offer\n2️⃣ Change amount or tenure\n3️⃣ Ask a question",
        "क्या आप इस ऑफ़र के साथ आगे बढ़ना चाहेंगे?\n\n1️⃣ ऑफ़र स्वीकार करें\n2️⃣ राशि या अवधि बदलें\n3️⃣ सवाल पूछें",
        "तुम्हाला या ऑफरसह पुढे जायचे आहे का?\n\n1️⃣ ऑफर स्वीकारा\n2️⃣ रक्कम किंवा कालावधी बदला\n3️⃣ प्रश्न विचारा",
    ),
    'Offer_Change_Prompt': (
        "Sure! Tell me the new amount (e.g. *3 lakh*) and/or tenure (e.g. *48 months*) you'd like to explore.",
        "ज़रूर! नई राशि (जैसे *3 लाख*) और/या अवधि (जैसे *48 महीने*) बताइए जो आप देखना चाहेंगे।",
        "नक्कीच! नवीन रक्कम (उदा. *3 लाख*) आणि/किंवा कालावधी (उदा. *48 महिने*) सांगा.",
    ),
    'Ask_Question_Prompt': (
        "Of course! What would you like to know about Personal Loan Top-Up? 🙂",
        "ज़रूर! पर्सनल लोन टॉप-अप के बारे में आप क्या जानना चाहेंगे? 🙂",
        "नक्कीच! पर्सनल लोन टॉप-अपबद्दल तुम्हाला काय जाणून घ्यायचे आहे? 🙂",
    ),
    'Offer_Accepted': (
        "✅ Offer accepted! Your reference number is ```{ref}```.\n\nWhen should our loan specialist call you?\n\n1️⃣ Within 24 hrs (as soon as possible)\n{slots}\n\nOr type a day & time, e.g. *Thu 11am*.",
        "✅ ऑफ़र स्वीकार हुआ! आपका रेफ़रेंस नंबर है ```{ref}```।\n\nहमारे लोन विशेषज्ञ आपको कब कॉल करें?\n\n1️⃣ 24 घंटों के भीतर (जल्द से जल्द)\n{slots}\n\nया दिन और समय लिखें, जैसे *Thu 11am*।",
        "✅ ऑफर स्वीकारली! तुमचा संदर्भ क्रमांक आहे ```{ref}```.\n\nआमच्या कर्ज तज्ज्ञांनी तुम्हाला कधी कॉल करावा?\n\n1️⃣ 24 तासांच्या आत (लवकरात लवकर)\n{slots}\n\nकिंवा दिवस व वेळ लिहा, उदा. *Thu 11am*.",
    ),
    'Callback_Options': (
        "When should our loan specialist call you?\n\n1️⃣ Within 24 hrs (as soon as possible)\n{slots}\n\nOr type a day & time, e.g. *Thu 11am*.",
        "हमारे लोन विशेषज्ञ आपको कब कॉल करें?\n\n1️⃣ 24 घंटों के भीतर (जल्द से जल्द)\n{slots}\n\nया दिन और समय लिखें, जैसे *Thu 11am*।",
        "आमच्या कर्ज तज्ज्ञांनी तुम्हाला कधी कॉल करावा?\n\n1️⃣ 24 तासांच्या आत (लवकरात लवकर)\n{slots}\n\nकिंवा दिवस व वेळ लिहा, उदा. *Thu 11am*.",
    ),
    'Callback_Invalid': (
        "I couldn't work out that time. 🙂 Please pick an option or type something like *tomorrow 4pm*.",
        "मैं वह समय समझ नहीं पाया। 🙂 कृपया कोई विकल्प चुनें या *tomorrow 4pm* जैसा लिखें।",
        "मला ती वेळ समजली नाही. 🙂 कृपया पर्याय निवडा किंवा *tomorrow 4pm* असे लिहा.",
    ),
    'Callback_Confirmed': (
        "📞 All set! A Kotak loan specialist will call you on *{when}*.\n\n🔖 Reference: ```{ref}```",
        "📞 सब तय! Kotak लोन विशेषज्ञ आपको *{when}* पर कॉल करेंगे।\n\n🔖 रेफ़रेंस: ```{ref}```",
        "📞 सर्व ठरले! Kotak कर्ज तज्ज्ञ तुम्हाला *{when}* ला कॉल करतील.\n\n🔖 संदर्भ: ```{ref}```",
    ),
    'FB_Q1_Intro': (
        "Before you go — 3 quick questions (10 seconds) 🙏",
        "जाने से पहले — 3 छोटे सवाल (10 सेकंड) 🙏",
        "जाण्यापूर्वी — 3 छोटे प्रश्न (10 सेकंद) 🙏",
    ),
    'FB_Q1': (
        "*1/3* How satisfied were you with today's experience?\n\n1 😞   2 😐   3 🙂   4 😊   5 🤩",
        "*1/3* आज के अनुभव से आप कितने संतुष्ट हैं?\n\n1 😞   2 😐   3 🙂   4 😊   5 🤩",
        "*1/3* आजच्या अनुभवाने तुम्ही किती समाधानी आहात?\n\n1 😞   2 😐   3 🙂   4 😊   5 🤩",
    ),
    'FB_Q2': (
        "*2/3* Did LoanSeva answer all your Top-Up questions?\n\n1️⃣ Yes, fully\n2️⃣ Mostly\n3️⃣ Not really",
        "*2/3* क्या LoanSeva ने टॉप-अप से जुड़े आपके सभी सवालों के जवाब दिए?\n\n1️⃣ हाँ, पूरी तरह\n2️⃣ ज़्यादातर\n3️⃣ ज़्यादा नहीं",
        "*2/3* LoanSeva ने तुमच्या सर्व टॉप-अप प्रश्नांची उत्तरे दिली का?\n\n1️⃣ हो, पूर्णपणे\n2️⃣ बहुतेक\n3️⃣ फारसे नाही",
    ),
    'FB_Q3': (
        "*3/3* Any additional feedback? Type freely, or reply *Skip*.",
        "*3/3* कोई और सुझाव? खुलकर लिखें, या *Skip* लिखें।",
        "*3/3* आणखी काही अभिप्राय? मोकळेपणाने लिहा, किंवा *Skip* लिहा.",
    ),
    'FB_Thanks': (
        "Thank you, {name}! 💙 Your plans just got a step closer. Our specialist will be in touch soon.\n\n🔖 Reference: ```{ref}```\n\n— Team Kotak Mahindra Bank",
        "धन्यवाद, {name}! 💙 आपके प्लान्स अब एक कदम और करीब हैं। हमारे विशेषज्ञ जल्द ही संपर्क करेंगे।\n\n🔖 रेफ़रेंस: ```{ref}```\n\n— टीम Kotak Mahindra Bank",
        "धन्यवाद, {name}! 💙 तुमच्या योजना आता एक पाऊल जवळ आल्या आहेत. आमचे तज्ज्ञ लवकरच संपर्क साधतील.\n\n🔖 संदर्भ: ```{ref}```\n\n— टीम Kotak Mahindra Bank",
    ),
    'Escalate': (
        "Of course! 🙋 I'm connecting you with a Kotak loan specialist. Everything you've shared is saved, so you won't need to repeat yourself. If no one is free right now, they'll call you back within 24 hours.",
        "ज़रूर! 🙋 मैं आपको Kotak लोन विशेषज्ञ से जोड़ रहा हूँ। आपकी दी गई सारी जानकारी सेव है, दोबारा बताने की ज़रूरत नहीं। अगर अभी कोई उपलब्ध नहीं है, तो वे 24 घंटों में कॉल करेंगे।",
        "नक्कीच! 🙋 मी तुम्हाला Kotak कर्ज तज्ज्ञांशी जोडत आहे. तुम्ही दिलेली सर्व माहिती सेव्ह आहे, पुन्हा सांगायची गरज नाही. आत्ता कोणी उपलब्ध नसल्यास, ते 24 तासांत कॉल करतील.",
    ),
}

# New Personal Loan journey (no pre-approved offer) — key: (English, Hindi, Marathi)
APPLY_MENU = (
    "\n\n1️⃣ Apply for a new Personal Loan\n2️⃣ Re-enter my details\n3️⃣ Talk to a specialist",
    "\n\n1️⃣ नए पर्सनल लोन के लिए आवेदन करें\n2️⃣ अपनी जानकारी दोबारा दर्ज करें\n3️⃣ विशेषज्ञ से बात करें",
    "\n\n1️⃣ नवीन पर्सनल लोनसाठी अर्ज करा\n2️⃣ माझी माहिती पुन्हा भरा\n3️⃣ तज्ज्ञांशी बोला",
)
DOC_FOOTER = (
    "\n\nSend it here as a *photo* or *PDF*, then reply *Done*. Or reply *Skip* to send it later.",
    "\n\nइसे यहीं *फ़ोटो* या *PDF* के रूप में भेजें, फिर *Done* लिखें। या बाद में भेजने के लिए *Skip* लिखें।",
    "\n\nते इथेच *फोटो* किंवा *PDF* म्हणून पाठवा, मग *Done* लिहा. किंवा नंतर पाठवण्यासाठी *Skip* लिहा.",
)
NEW_LOAN = {
    'Verify_Not_Found': tuple(t + m for t, m in zip((
        "I couldn't find a pre-approved Kotak offer linked to {mobile}. No problem — you can still apply for a new *Kotak Personal Loan* right here, in about 3 minutes. 👇",
        "{mobile} से जुड़ा कोई प्री-अप्रूव्ड Kotak ऑफ़र नहीं मिला। कोई बात नहीं — आप यहीं लगभग 3 मिनट में नए *Kotak पर्सनल लोन* के लिए आवेदन कर सकते हैं। 👇",
        "{mobile} शी जोडलेली कोणतीही प्री-अप्रूव्ड Kotak ऑफर सापडली नाही. काही हरकत नाही — तुम्ही इथेच सुमारे 3 मिनिटांत नवीन *Kotak पर्सनल लोन*साठी अर्ज करू शकता. 👇",
    ), APPLY_MENU)),
    'NL_No_Offer': tuple(t + m for t, m in zip((
        "Thanks {name}! There's no pre-approved Top-Up on your account right now, but you can apply for a new *Kotak Personal Loan* right here, in about 3 minutes. 👇",
        "धन्यवाद {name}! अभी आपके खाते पर कोई प्री-अप्रूव्ड टॉप-अप नहीं है, लेकिन आप यहीं लगभग 3 मिनट में नए *Kotak पर्सनल लोन* के लिए आवेदन कर सकते हैं। 👇",
        "धन्यवाद {name}! सध्या तुमच्या खात्यावर कोणताही प्री-अप्रूव्ड टॉप-अप नाही, पण तुम्ही इथेच सुमारे 3 मिनिटांत नवीन *Kotak पर्सनल लोन*साठी अर्ज करू शकता. 👇",
    ), APPLY_MENU)),
    'NL_Apply_Reprompt': tuple(t + m for t, m in zip((
        "Would you like to apply for a new Kotak Personal Loan?",
        "क्या आप नए Kotak पर्सनल लोन के लिए आवेदन करना चाहेंगे?",
        "तुम्हाला नवीन Kotak पर्सनल लोनसाठी अर्ज करायचा आहे का?",
    ), APPLY_MENU)),
    'NL_Intro': (
        "Let's start your *Kotak Personal Loan* application 📝 It takes about 3 minutes — keep your *PAN card* handy.",
        "चलिए आपका *Kotak पर्सनल लोन* आवेदन शुरू करते हैं 📝 इसमें लगभग 3 मिनट लगते हैं — अपना *PAN कार्ड* पास रखें।",
        "चला, तुमचा *Kotak पर्सनल लोन* अर्ज सुरू करूया 📝 यासाठी सुमारे 3 मिनिटे लागतात — तुमचे *PAN कार्ड* जवळ ठेवा.",
    ),
    'NL_Verify_Prompt': (
        "First, let's verify you 🔐 Please share your *full name (as on PAN)* and your *mobile number* (10 digits).",
        "पहले आपकी पुष्टि कर लेते हैं 🔐 कृपया अपना *पूरा नाम (PAN के अनुसार)* और *मोबाइल नंबर* (10 अंक) बताएँ।",
        "आधी तुमची पडताळणी करूया 🔐 कृपया तुमचे *पूर्ण नाव (PAN प्रमाणे)* आणि *मोबाइल नंबर* (10 अंकी) सांगा.",
    ),
    'NL_Verified': (
        "✅ Mobile verified, {name}! A few quick questions about you — about 2 minutes. ⏱️",
        "✅ मोबाइल वेरिफ़ाई हो गया, {name}! आपके बारे में कुछ छोटे सवाल — लगभग 2 मिनट। ⏱️",
        "✅ मोबाइल पडताळला, {name}! तुमच्याबद्दल काही छोटे प्रश्न — सुमारे 2 मिनिटे. ⏱️",
    ),
    'NL_Invalid': (
        "Hmm, that doesn't look quite right. 🙂 Please try again.",
        "हम्म, यह सही नहीं लग रहा। 🙂 कृपया फिर से कोशिश करें।",
        "हम्म, हे बरोबर वाटत नाही. 🙂 कृपया पुन्हा प्रयत्न करा.",
    ),
    'NL_Q_Dob': (
        "What's your *date of birth*? e.g. *15/08/1990*",
        "आपकी *जन्म तिथि* क्या है? जैसे *15/08/1990*",
        "तुमची *जन्मतारीख* काय आहे? उदा. *15/08/1990*",
    ),
    'NL_Q_Pan': (
        "Please type your *PAN* (10 characters, e.g. *ABCPE1234F*). 🔒 It's used only for this application and your credit check.",
        "कृपया अपना *PAN* लिखें (10 अक्षर, जैसे *ABCPE1234F*)। 🔒 इसका उपयोग केवल इस आवेदन और क्रेडिट जाँच के लिए होगा।",
        "कृपया तुमचा *PAN* लिहा (10 अक्षरे, उदा. *ABCPE1234F*). 🔒 याचा वापर फक्त या अर्जासाठी आणि क्रेडिट तपासणीसाठी होईल.",
    ),
    'NL_Q_Email': (
        "What's your *email address*? 📧 Your sanction letter will be sent here.",
        "आपका *ईमेल पता* क्या है? 📧 आपका सैंक्शन लेटर यहीं भेजा जाएगा।",
        "तुमचा *ईमेल पत्ता* काय आहे? 📧 तुमचे सँक्शन लेटर इथेच पाठवले जाईल.",
    ),
    'NL_Q_Pincode': (
        "Which *city* do you live in, and what's your *PIN code*? e.g. *Pune 411001*",
        "आप किस *शहर* में रहते हैं, और आपका *PIN कोड* क्या है? जैसे *Pune 411001*",
        "तुम्ही कोणत्या *शहरात* राहता, आणि तुमचा *PIN कोड* काय आहे? उदा. *Pune 411001*",
    ),
    'NL_Q_Income': (
        "What's your *monthly take-home income*? e.g. *85,000* or *85k*",
        "आपकी *मासिक इन-हैंड आय* कितनी है? जैसे *85,000* या *85k*",
        "तुमचे *मासिक हातात येणारे उत्पन्न* किती आहे? उदा. *85,000* किंवा *85k*",
    ),
    'NL_Q_Obligations': (
        "How much do you pay in *EMIs per month* on other loans or credit cards? Reply *0* if none.",
        "दूसरे लोन या क्रेडिट कार्ड पर आप *हर महीने कितनी EMI* भरते हैं? कोई नहीं तो *0* लिखें।",
        "इतर कर्जे किंवा क्रेडिट कार्डवर तुम्ही *दरमहा किती EMI* भरता? काहीही नसल्यास *0* लिहा.",
    ),
    'NL_Q_Amount': (
        "How much would you like to borrow? 💰 ({min} – {max})\n\nType an amount, e.g. *3 lakh*.",
        "आप कितना लोन लेना चाहेंगे? 💰 ({min} – {max})\n\nराशि लिखें, जैसे *3 lakh*।",
        "तुम्हाला किती कर्ज हवे आहे? 💰 ({min} – {max})\n\nरक्कम लिहा, उदा. *3 lakh*.",
    ),
    'NL_Offer_Card': (
        "🎉 Good news, {name}! Here's your *indicative* Personal Loan offer:\n\n> 💰 Amount: *{amount}*\n> 📈 Rate: *{rate}% p.a.*\n> 📅 Tenure: *{tenure} months*\n> 💳 EMI: *{emi}/month*\n> 🧾 Processing fee: {fee} + GST\n\nOther tenures: {otherTenures}\n\n_Indicative only — final terms after credit checks and document verification._\n\n1️⃣ Accept and continue\n2️⃣ Change amount or tenure\n3️⃣ Ask a question",
        "🎉 अच्छी खबर, {name}! यह रहा आपका *अनुमानित* पर्सनल लोन ऑफ़र:\n\n> 💰 राशि: *{amount}*\n> 📈 ब्याज दर: *{rate}% प्रति वर्ष*\n> 📅 अवधि: *{tenure} महीने*\n> 💳 EMI: *{emi}/माह*\n> 🧾 प्रोसेसिंग शुल्क: {fee} + GST\n\nअन्य अवधि: {otherTenures}\n\n_यह केवल अनुमान है — अंतिम शर्तें क्रेडिट जाँच और दस्तावेज़ सत्यापन के बाद।_\n\n1️⃣ स्वीकार करें और आगे बढ़ें\n2️⃣ राशि या अवधि बदलें\n3️⃣ सवाल पूछें",
        "🎉 आनंदाची बातमी, {name}! ही तुमची *अंदाजित* पर्सनल लोन ऑफर:\n\n> 💰 रक्कम: *{amount}*\n> 📈 व्याजदर: *{rate}% प्रतिवर्ष*\n> 📅 कालावधी: *{tenure} महिने*\n> 💳 EMI: *{emi}/महिना*\n> 🧾 प्रोसेसिंग शुल्क: {fee} + GST\n\nइतर कालावधी: {otherTenures}\n\n_ही फक्त अंदाजित ऑफर आहे — अंतिम अटी क्रेडिट तपासणी आणि कागदपत्र पडताळणीनंतर._\n\n1️⃣ स्वीकारा आणि पुढे जा\n2️⃣ रक्कम किंवा कालावधी बदला\n3️⃣ प्रश्न विचारा",
    ),
    'NL_Refer': (
        "Thanks {name}! 🙏 Based on your details, a Kotak loan specialist will work out the best option for you personally. They'll call you within 24 hours.",
        "धन्यवाद {name}! 🙏 आपकी जानकारी के आधार पर, Kotak लोन विशेषज्ञ आपके लिए सबसे अच्छा विकल्प तैयार करेंगे। वे 24 घंटों में कॉल करेंगे।",
        "धन्यवाद {name}! 🙏 तुमच्या माहितीनुसार, Kotak कर्ज तज्ज्ञ तुमच्यासाठी सर्वोत्तम पर्याय तयार करतील. ते 24 तासांत कॉल करतील.",
    ),
    'NL_Offer_Accepted': (
        "✅ Great choice! Now a few documents 📎 — up to 3, one at a time.",
        "✅ बढ़िया! अब कुछ दस्तावेज़ 📎 — अधिकतम 3, एक-एक करके।",
        "✅ छान! आता काही कागदपत्रे 📎 — जास्तीत जास्त 3, एकेक करून.",
    ),
    'NL_Doc_Pan': tuple(t + f for t, f in zip((
        "📄 *Document 1/3* — your *PAN card* (front side).",
        "📄 *दस्तावेज़ 1/3* — आपका *PAN कार्ड* (सामने की तरफ़)।",
        "📄 *कागदपत्र 1/3* — तुमचे *PAN कार्ड* (पुढची बाजू).",
    ), DOC_FOOTER)),
    'NL_Doc_Bank': tuple(t + f for t, f in zip((
        "🏦 *Document 2/3* — your *bank statement* for the last 6 months (PDF works best). We use it to verify your income.",
        "🏦 *दस्तावेज़ 2/3* — पिछले 6 महीनों का *बैंक स्टेटमेंट* (PDF सबसे अच्छा)। इससे आपकी आय की पुष्टि होती है।",
        "🏦 *कागदपत्र 2/3* — मागील 6 महिन्यांचे *बँक स्टेटमेंट* (PDF सर्वोत्तम). याने तुमच्या उत्पन्नाची पडताळणी होते.",
    ), DOC_FOOTER)),
    'NL_Doc_Salary': tuple(t + f for t, f in zip((
        "💼 *Document 3/3* — your last *3 salary slips*.",
        "💼 *दस्तावेज़ 3/3* — आपकी पिछली *3 सैलरी स्लिप*।",
        "💼 *कागदपत्र 3/3* — तुमच्या मागील *3 पगार स्लिप*.",
    ), DOC_FOOTER)),
    'NL_Doc_Received': (
        "✅ Received {count} file(s) — thank you!",
        "✅ {count} फ़ाइल मिल गई — धन्यवाद!",
        "✅ {count} फाइल मिळाली — धन्यवाद!",
    ),
    'NL_Doc_Skipped': (
        "👍 No problem — you can share it later.",
        "👍 कोई बात नहीं — आप इसे बाद में भेज सकते हैं।",
        "👍 काही हरकत नाही — तुम्ही ते नंतर पाठवू शकता.",
    ),
    'NL_Doc_Not_Received': (
        "I haven't received a file yet. 📎 Tap the attachment icon to send a photo or PDF, then reply *Done* — or reply *Skip* to send it later.",
        "मुझे अभी तक कोई फ़ाइल नहीं मिली। 📎 अटैचमेंट आइकन से फ़ोटो या PDF भेजें, फिर *Done* लिखें — या बाद में भेजने के लिए *Skip* लिखें।",
        "मला अजून कोणतीही फाइल मिळाली नाही. 📎 अटॅचमेंट आयकॉनवरून फोटो किंवा PDF पाठवा, मग *Done* लिहा — किंवा नंतर पाठवण्यासाठी *Skip* लिहा.",
    ),
    'NL_Review': (
        "📋 *Please review your application*\n\n> 👤 {name}\n> 🎂 {dob}\n> 🪪 PAN {pan}\n> 📧 {email}\n> 📍 {city}\n> 💼 {employment}\n> 💵 Income {income}/month · EMIs {emis}/month\n> 💰 *{amount}* for *{tenure} months* · EMI *{emi}*\n> 📎 {docs}\n\nBy replying *1* you confirm these details are correct, and consent to Kotak fetching your credit report (CIBIL) and verifying your PAN, bank statement and employment for this application.\n\n1️⃣ Confirm and submit\n2️⃣ Something's wrong — talk to a specialist",
        "📋 *कृपया अपना आवेदन जाँच लें*\n\n> 👤 {name}\n> 🎂 {dob}\n> 🪪 PAN {pan}\n> 📧 {email}\n> 📍 {city}\n> 💼 {employment}\n> 💵 आय {income}/माह · EMI {emis}/माह\n> 💰 *{amount}*, *{tenure} महीने* · EMI *{emi}*\n> 📎 {docs}\n\n*1* लिखकर आप पुष्टि करते हैं कि यह जानकारी सही है, और इस आवेदन के लिए Kotak को आपकी क्रेडिट रिपोर्ट (CIBIL) लेने तथा PAN, बैंक स्टेटमेंट और रोज़गार सत्यापित करने की सहमति देते हैं।\n\n1️⃣ पुष्टि करें और सबमिट करें\n2️⃣ कुछ गलत है — विशेषज्ञ से बात करें",
        "📋 *कृपया तुमचा अर्ज तपासा*\n\n> 👤 {name}\n> 🎂 {dob}\n> 🪪 PAN {pan}\n> 📧 {email}\n> 📍 {city}\n> 💼 {employment}\n> 💵 उत्पन्न {income}/महिना · EMI {emis}/महिना\n> 💰 *{amount}*, *{tenure} महिने* · EMI *{emi}*\n> 📎 {docs}\n\n*1* लिहून तुम्ही ही माहिती बरोबर असल्याची पुष्टी करता, आणि या अर्जासाठी Kotak ला तुमचा क्रेडिट रिपोर्ट (CIBIL) घेण्याची तसेच PAN, बँक स्टेटमेंट आणि रोजगाराची पडताळणी करण्याची संमती देता.\n\n1️⃣ पुष्टी करा आणि सबमिट करा\n2️⃣ काहीतरी चुकले आहे — तज्ज्ञांशी बोला",
    ),
    'NL_Submitted': (
        "🎉 Application submitted! Your reference number is ```{ref}```.\n\nWe're running your credit and document checks now. A Kotak credit officer will review your application and you'll hear from us right here — usually within 24 hours.",
        "🎉 आवेदन सबमिट हो गया! आपका रेफ़रेंस नंबर ```{ref}``` है।\n\nहम अभी आपकी क्रेडिट और दस्तावेज़ जाँच कर रहे हैं। Kotak क्रेडिट अधिकारी आपके आवेदन की समीक्षा करेंगे और आपको यहीं जानकारी मिलेगी — आमतौर पर 24 घंटों में।",
        "🎉 अर्ज सबमिट झाला! तुमचा संदर्भ क्रमांक ```{ref}``` आहे.\n\nआम्ही आत्ता तुमची क्रेडिट आणि कागदपत्र तपासणी करत आहोत. Kotak क्रेडिट अधिकारी तुमच्या अर्जाचे पुनरावलोकन करतील आणि तुम्हाला इथेच कळवले जाईल — साधारणपणे 24 तासांत.",
    ),
    'NL_Approved': (
        "🎉 Congratulations {name}! Your *Kotak Personal Loan* is approved.\n\n> 💰 Sanctioned: *{amount}*\n> 📈 Rate: *{rate}% p.a.*\n> 📅 Tenure: *{tenure} months*\n> 💳 EMI: *{emi}/month*\n> 🏦 Loan account: ```{lan}```\n\nYour sanction letter is on its way to your email. 🔖 Ref: ```{ref}```",
        "🎉 बधाई हो {name}! आपका *Kotak पर्सनल लोन* स्वीकृत हो गया है।\n\n> 💰 स्वीकृत राशि: *{amount}*\n> 📈 ब्याज दर: *{rate}% प्रति वर्ष*\n> 📅 अवधि: *{tenure} महीने*\n> 💳 EMI: *{emi}/माह*\n> 🏦 लोन खाता: ```{lan}```\n\nआपका सैंक्शन लेटर आपके ईमेल पर भेजा जा रहा है। 🔖 रेफ़रेंस: ```{ref}```",
        "🎉 अभिनंदन {name}! तुमचे *Kotak पर्सनल लोन* मंजूर झाले आहे.\n\n> 💰 मंजूर रक्कम: *{amount}*\n> 📈 व्याजदर: *{rate}% प्रतिवर्ष*\n> 📅 कालावधी: *{tenure} महिने*\n> 💳 EMI: *{emi}/महिना*\n> 🏦 कर्ज खाते: ```{lan}```\n\nतुमचे सँक्शन लेटर तुमच्या ईमेलवर पाठवले जात आहे. 🔖 संदर्भ: ```{ref}```",
    ),
    'NL_Rejected': (
        "Hi {name}, thank you for applying for a Kotak Personal Loan. 🙏 After careful review, we're unable to approve your application right now. This doesn't affect your relationship with Kotak, and you're welcome to apply again after 3 months.\n\nReply *Agent* to talk to a specialist. 🔖 Ref: ```{ref}```",
        "नमस्ते {name}, Kotak पर्सनल लोन के लिए आवेदन करने का धन्यवाद। 🙏 सावधानीपूर्वक समीक्षा के बाद, हम अभी आपका आवेदन स्वीकृत नहीं कर पा रहे हैं। इससे Kotak के साथ आपके संबंध पर कोई असर नहीं पड़ता, और आप 3 महीने बाद फिर से आवेदन कर सकते हैं।\n\nविशेषज्ञ से बात करने के लिए *Agent* लिखें। 🔖 रेफ़रेंस: ```{ref}```",
        "नमस्कार {name}, Kotak पर्सनल लोनसाठी अर्ज केल्याबद्दल धन्यवाद. 🙏 काळजीपूर्वक पुनरावलोकनानंतर, आम्ही सध्या तुमचा अर्ज मंजूर करू शकत नाही. याचा Kotak सोबतच्या तुमच्या संबंधावर परिणाम होत नाही, आणि तुम्ही 3 महिन्यांनंतर पुन्हा अर्ज करू शकता.\n\nतज्ज्ञांशी बोलण्यासाठी *Agent* लिहा. 🔖 संदर्भ: ```{ref}```",
    ),
    'NL_Reengage_1': (
        "Hi {name} 👋 Your Kotak Personal Loan application is saved — pick up right where you left off.\n\n👉 Reply *Continue* to carry on.",
        "नमस्ते {name} 👋 आपका Kotak पर्सनल लोन आवेदन सेव है — जहाँ छोड़ा था वहीं से आगे बढ़ें।\n\n👉 जारी रखने के लिए *Continue* लिखें।",
        "नमस्कार {name} 👋 तुमचा Kotak पर्सनल लोन अर्ज सेव्ह आहे — जिथे थांबलात तिथून पुढे सुरू करा.\n\n👉 पुढे जाण्यासाठी *Continue* लिहा.",
    ),
    'NL_Reengage_2': (
        "{name}, your Kotak Personal Loan application is still waiting for you ✨ It takes just a couple of minutes to finish.\n\n👉 Reply *Continue* to pick up, or *Agent* and a specialist will call you.",
        "{name}, आपका Kotak पर्सनल लोन आवेदन अभी भी आपका इंतज़ार कर रहा है ✨ पूरा करने में बस कुछ मिनट लगते हैं।\n\n👉 आगे बढ़ने के लिए *Continue* लिखें, या *Agent* लिखें और विशेषज्ञ आपको कॉल करेंगे।",
        "{name}, तुमचा Kotak पर्सनल लोन अर्ज अजूनही तुमची वाट पाहत आहे ✨ पूर्ण करायला फक्त काही मिनिटे लागतात.\n\n👉 पुढे जाण्यासाठी *Continue* लिहा, किंवा *Agent* लिहा आणि तज्ज्ञ तुम्हाला कॉल करतील.",
    ),
}
MESSAGES.update(NEW_LOAN)

# Generic welcome (no pre-approved offer found for this number): also offer the new-loan application
_APPLY_OPTION = ("4️⃣ Apply for a new Personal Loan", "4️⃣ नए पर्सनल लोन के लिए आवेदन करें", "4️⃣ नवीन पर्सनल लोनसाठी अर्ज करा")
MESSAGES['Welcome_Generic'] = tuple(
    t.replace('\n\n' + footer, '\n' + opt + '\n\n' + footer) for t, opt, footer in zip(MESSAGES['Welcome_Generic'], _APPLY_OPTION, LANG_FOOTER.values()))

# FAQ: key -> (sort, question, keywords, en, hi, mr). Tokens come from LoanSeva_Config__mdt.
FAQS = {
    'Uses': (10, 'What can I use the loan for?',
        'use,using,used for,what can,spend,purpose,end use,किस लिए,किसके लिए,उपयोग,इस्तेमाल,वापर,कशासाठी,कशाकरिता',
        "You can use your Kotak Personal Loan Top-Up for almost any personal goal 🌟 — home renovation, higher education, medical needs, travel, a family wedding, or bringing other expenses together into one EMI.",
        "आप अपने Kotak पर्सनल लोन टॉप-अप का उपयोग लगभग हर निजी ज़रूरत के लिए कर सकते हैं 🌟 — घर का नवीनीकरण, उच्च शिक्षा, इलाज, यात्रा, परिवार में शादी, या दूसरे खर्चों को एक EMI में लाने के लिए।",
        "तुम्ही तुमचा Kotak पर्सनल लोन टॉप-अप जवळजवळ कोणत्याही वैयक्तिक गरजेसाठी वापरू शकता 🌟 — घराचे नूतनीकरण, उच्च शिक्षण, वैद्यकीय गरजा, प्रवास, कुटुंबातील लग्न, किंवा इतर खर्च एका EMI मध्ये आणण्यासाठी."),
    'Interest_Rate': (20, "What's the interest rate?",
        'interest,rate,roi,apr,ब्याज,दर,व्याज,व्याजदर',
        "Top-Up rates start from *{rate}* 📈 Your exact rate depends on your repayment track and profile — customers with a great track record get our best pricing. I'll show your personalised rate, EMI and fees upfront before you decide anything.",
        "टॉप-अप की ब्याज दरें *{rate}* से शुरू होती हैं 📈 आपकी सटीक दर आपके भुगतान रिकॉर्ड और प्रोफ़ाइल पर निर्भर करती है — अच्छे रिकॉर्ड वाले ग्राहकों को हमारी सबसे अच्छी दर मिलती है। कोई भी फ़ैसला लेने से पहले मैं आपकी पर्सनलाइज़्ड दर, EMI और शुल्क दिखाऊँगा।",
        "टॉप-अपचे व्याजदर *{rate}* पासून सुरू होतात 📈 तुमचा नेमका दर तुमच्या परतफेड रेकॉर्ड आणि प्रोफाइलवर अवलंबून असतो — उत्तम रेकॉर्ड असलेल्या ग्राहकांना आमचा सर्वोत्तम दर मिळतो. कोणताही निर्णय घेण्यापूर्वी मी तुमचा वैयक्तिक दर, EMI आणि शुल्क दाखवेन."),
    'Vs_New_Loan': (30, 'How is this different from a new loan?',
        'different,difference,differ,new loan,fresh loan,compare,versus, vs,better than,अलग,फर्क,अंतर,नया लोन,नए लोन,वेगळे,फरक,नवीन कर्ज',
        "A Top-Up builds on your existing Kotak loan, so it's quicker and simpler than a new loan:\n\n✅ Pre-qualified amount based on your repayment track\n✅ Minimal paperwork — no repeat KYC\n✅ Preliminary offer in about 90 seconds, right here on WhatsApp\n✅ Flexible tenure from {minTenure} to {maxTenure} months",
        "टॉप-अप आपके मौजूदा Kotak लोन पर आधारित है, इसलिए यह नए लोन से तेज़ और आसान है:\n\n✅ आपके भुगतान रिकॉर्ड के आधार पर प्री-क्वालिफाइड राशि\n✅ न्यूनतम कागज़ी कार्रवाई — दोबारा KYC नहीं\n✅ लगभग 90 सेकंड में प्रारंभिक ऑफ़र, यहीं WhatsApp पर\n✅ {minTenure} से {maxTenure} महीने तक की लचीली अवधि",
        "टॉप-अप तुमच्या सध्याच्या Kotak कर्जावर आधारित आहे, त्यामुळे तो नवीन कर्जापेक्षा जलद आणि सोपा आहे:\n\n✅ तुमच्या परतफेड रेकॉर्डवर आधारित प्री-क्वालिफाइड रक्कम\n✅ किमान कागदपत्रे — पुन्हा KYC नाही\n✅ सुमारे 90 सेकंदात प्राथमिक ऑफर, इथेच WhatsApp वर\n✅ {minTenure} ते {maxTenure} महिन्यांचा लवचिक कालावधी"),
    'Disbursal_Speed': (40, 'How quickly will I get the money?',
        'quick,fast,how soon,how long,disburs,get the money,receive,credited,turnaround,कितनी जल्दी,कब तक,कब मिलेगा,पैसे कब,किती लवकर,केव्हा,कधी मिळ',
        "Fast! 🚀 You'll see a preliminary offer here in about 90 seconds. Once you accept and our specialist completes final verification, funds can be credited to your bank account {disbursal}.",
        "बहुत जल्दी! 🚀 लगभग 90 सेकंड में आपको यहीं प्रारंभिक ऑफ़र दिखेगा। ऑफ़र स्वीकार करने और हमारे विशेषज्ञ द्वारा अंतिम सत्यापन के बाद, राशि आपके बैंक खाते में {disbursal} में जमा हो सकती है।",
        "अगदी लवकर! 🚀 सुमारे 90 सेकंदात तुम्हाला इथेच प्राथमिक ऑफर दिसेल. ऑफर स्वीकारल्यानंतर आणि आमच्या तज्ज्ञांनी अंतिम पडताळणी केल्यानंतर, रक्कम तुमच्या बँक खात्यात {disbursal} मध्ये जमा होऊ शकते."),
    'Fees': (50, 'What are the charges?',
        'fee,fees,charge,charges,processing,hidden,cost,शुल्क,चार्ज,खर्च',
        "Processing fee is {feePct}% of the Top-Up amount (plus GST) 🧾 — shown clearly on your offer before you accept. No surprises.",
        "प्रोसेसिंग शुल्क टॉप-अप राशि का {feePct}% (साथ में GST) है 🧾 — स्वीकार करने से पहले आपके ऑफ़र पर साफ़ दिखाया जाता है।",
        "प्रोसेसिंग शुल्क टॉप-अप रकमेच्या {feePct}% (अधिक GST) आहे 🧾 — स्वीकारण्यापूर्वी तुमच्या ऑफरवर स्पष्ट दाखवले जाते."),
    'Documents': (60, 'What documents do I need?',
        'document,documents,papers,paperwork,kyc,proof,दस्तावेज़,दस्तावेज,कागज,कागदपत्र',
        "Very little 📄 As an existing Kotak customer your KYC is already on file. Our specialist may ask for your latest salary slips or bank statement during final verification.",
        "बहुत कम 📄 मौजूदा Kotak ग्राहक होने के नाते आपका KYC पहले से हमारे पास है। अंतिम सत्यापन के दौरान विशेषज्ञ हाल की सैलरी स्लिप या बैंक स्टेटमेंट माँग सकते हैं।",
        "अगदी कमी 📄 सध्याचे Kotak ग्राहक असल्याने तुमचा KYC आधीच आमच्याकडे आहे. अंतिम पडताळणीदरम्यान तज्ज्ञ अलीकडील पगार स्लिप किंवा बँक स्टेटमेंट मागू शकतात."),
    'Tenure': (70, 'What tenure can I choose?',
        'tenure,duration,years,months,repay,prepay,foreclos,अवधि,कितने साल,कालावधी,किती वर्ष',
        "You can choose a tenure from {minTenure} to {maxTenure} months 📅 I'll show EMIs for each option on your offer so you can pick what's comfortable.",
        "आप {minTenure} से {maxTenure} महीने तक की अवधि चुन सकते हैं 📅 मैं आपके ऑफ़र पर हर विकल्प की EMI दिखाऊँगा ताकि आप अपनी सुविधा से चुन सकें।",
        "तुम्ही {minTenure} ते {maxTenure} महिन्यांचा कालावधी निवडू शकता 📅 मी तुमच्या ऑफरवर प्रत्येक पर्यायाचा EMI दाखवेन, जेणेकरून तुम्ही सोयीचा पर्याय निवडू शकाल."),
    'Eligibility': (80, 'Am I eligible?',
        'eligible,eligibility,qualify,criteria,पात्र,पात्रता,योग्य',
        "Great news — as an existing Kotak loan customer you're pre-qualified 🎯 Your final amount depends on your repayment track, monthly income and existing EMIs. It takes about a minute to check.",
        "खुशखबरी — मौजूदा Kotak लोन ग्राहक होने के नाते आप प्री-क्वालिफाइड हैं 🎯 अंतिम राशि आपके भुगतान रिकॉर्ड, मासिक आय और मौजूदा EMI पर निर्भर करती है। जाँचने में लगभग एक मिनट लगता है।",
        "आनंदाची बातमी — सध्याचे Kotak कर्ज ग्राहक म्हणून तुम्ही प्री-क्वालिफाइड आहात 🎯 अंतिम रक्कम तुमचा परतफेड रेकॉर्ड, मासिक उत्पन्न आणि सध्याच्या EMI वर अवलंबून असते. तपासायला सुमारे एक मिनिट लागतो."),    # Sort order 900+ = fallback: used only when no specific FAQ matches (LoanSevaFaqMatcher.FALLBACK_ORDER).
    'About_Top_Up': (900, 'Tell me more about the Personal Loan Top-Up',
        'more,about,know,tell,details,detail,explain,information,info,overview,top up,top-up,topup,personal loan,loan,जानकारी,बारे,बताइए,बताओ,टॉप,माहिती,बद्दल,सांगा',
        "A *Kotak Personal Loan Top-Up* 💡 gives you extra funds on top of your existing Kotak Personal Loan, without a fresh application:\n\n✅ Pre-qualified amount based on your repayment track\n✅ Rates from *{rate}*, with EMI and fees shown upfront\n✅ Tenure from {minTenure} to {maxTenure} months\n✅ Minimal paperwork, no repeat KYC\n\nAsk me about rates, fees, documents or eligibility anytime.",
        "*Kotak पर्सनल लोन टॉप-अप* 💡 आपके मौजूदा Kotak पर्सनल लोन पर अतिरिक्त राशि देता है, बिना नए आवेदन के:\n\n✅ आपके भुगतान रिकॉर्ड के आधार पर प्री-क्वालिफाइड राशि\n✅ ब्याज दर *{rate}* से, EMI और शुल्क पहले ही दिखाए जाते हैं\n✅ {minTenure} से {maxTenure} महीने तक की अवधि\n✅ न्यूनतम कागज़ी कार्रवाई, दोबारा KYC नहीं\n\nब्याज दर, शुल्क, दस्तावेज़ या पात्रता के बारे में कभी भी पूछें।",
        "*Kotak पर्सनल लोन टॉप-अप* 💡 तुमच्या सध्याच्या Kotak पर्सनल लोनवर अतिरिक्त रक्कम देतो, नवीन अर्जाशिवाय:\n\n✅ तुमच्या परतफेड रेकॉर्डवर आधारित प्री-क्वालिफाइड रक्कम\n✅ व्याजदर *{rate}* पासून, EMI आणि शुल्क आधीच दाखवले जातात\n✅ {minTenure} ते {maxTenure} महिन्यांचा कालावधी\n✅ किमान कागदपत्रे, पुन्हा KYC नाही\n\nव्याजदर, शुल्क, कागदपत्रे किंवा पात्रतेबद्दल कधीही विचारा."),
}


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
    with open(os.path.join(OUT, f'{type_name}.{dev_name}.md-meta.xml'), 'w') as fh:
        fh.write(xml)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    record('LoanSeva_Config', 'Default', 'Default', CONFIG)
    for key, (en, hi, mr) in MESSAGES.items():
        record('LoanSeva_Message', key, key.replace('_', ' '), {'English__c': en, 'Hindi__c': hi, 'Marathi__c': mr})
    for key, (order, question, keywords, en, hi, mr) in FAQS.items():
        record('LoanSeva_FAQ', key, question, {
            'Sort_Order__c': order, 'Question__c': question, 'Keywords__c': keywords,
            'English__c': en, 'Hindi__c': hi, 'Marathi__c': mr})
    print('config 1, messages', len(MESSAGES), 'faqs', len(FAQS))
