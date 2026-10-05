/**
 * LoanSeva conversation engine. Each public method backs one Agentforce action.
 * Apex owns the state machine (which question is pending, how to parse the reply) so the
 * live demo is deterministic; the agent relays the returned, already-localised message.
 */
public with sharing class LoanSevaEngine {
    public class Result {
        public String message;
        public Loan_Journey__c journey;
        public Boolean success = true;
        public Boolean handoff = false;
    }

    public static final List<String> INCOME_BUCKETS = new List<String>{ 'Below 50K', '50K-1L', '1L-2L', '2L+' };
    public static final List<String> PURPOSES = new List<String>{
        'Home renovation', 'Education', 'Medical', 'Travel', 'Wedding', 'Other'
    };

    // ------------------------------------------------------------------ Start / menu
    public static Result start(Loan_Journey__c j) {
        LoanSevaJourneyService.advance(j, 'Start');
        // A resumed journey is mid-step, so the next 1/2/3 must mean the menu shown here, not a slot or answer
        j.Menu_Pending__c = awaiting(j) != 'menu';
        update j;
        return result(j, welcome(j));
    }

    /** Menu option 1 on a resumed journey: pick up where the customer left off. */
    private static Result resume(Loan_Journey__c j) {
        String state = awaiting(j);
        if (state == 'offer_decision' && j.Offer_Amount__c != null) {
            return offer(j, null, j.Offer_Tenure_Months__c == null ? null : j.Offer_Tenure_Months__c.intValue() + ' months');
        }
        if (state == 'identity' || state == 'otp' || state == 'apply_offer' || state == 'done' || state == 'handoff') {
            return promptAndSave(j);
        }
        LoanSevaJourneyService.touch(j);
        update j;
        return result(j, LoanSevaI18n.msg('Resume_Prompt', j.Language__c) + '\n' + pendingPrompt(j, false));
    }

    private static String welcome(Loan_Journey__c j) {
        Existing_Loan__c loan = LoanSevaJourneyService.activeLoan(j.Contact__c);
        String name = LoanSevaJourneyService.firstName(j);
        String key = (loan != null && String.isNotBlank(name)) ? 'Welcome' : 'Welcome_Generic';
        return LoanSevaI18n.msg(key, j.Language__c, new Map<String, Object>{
            'name' => name,
            'limit' => loan == null ? '' : LoanSevaI18n.inrShort(loan.Pre_Approved_Limit__c)
        });
    }

    // ------------------------------------------------------------------ FAQ
    public static Result answerFaq(Loan_Journey__c j, String question) {
        String q = String.isBlank(question) ? '' : question.trim();
        // "What's the EMI for 3 lakh?" and "status?" reach here when the agent reads them as questions
        Result shortcut = LoanSevaShortcuts.handle(j, q);
        if (shortcut != null) {
            return shortcut;
        }
        if (String.isNotBlank(q)) {
            String log = (String.isBlank(j.Questions_Asked__c) ? '' : j.Questions_Asked__c + '\n') +
                '- ' + q.abbreviate(250);
            j.Questions_Asked__c = log.right(32000);
        }
        LoanSevaJourneyService.advance(j, 'Start');
        j.Question_Pending__c = false;
        LoanSeva_FAQ__mdt faq = LoanSevaFaqMatcher.bestMatch(q, true);
        String message = faq == null
            ? LoanSevaI18n.msg('FAQ_Not_Found', j.Language__c)
            : LoanSevaFaqMatcher.render(faq, j.Language__c);
        String followUp = pendingPrompt(j, true);
        message += '\n\n' + (j.OTP_Verified__c && String.isNotBlank(followUp)
            ? LoanSevaI18n.msg('Resume_Prompt', j.Language__c) + '\n' + followUp
            : LoanSevaI18n.msg('FAQ_Nudge', j.Language__c));
        update j;
        Result r = result(j, message);
        r.success = faq != null;
        return r;
    }

    // ------------------------------------------------------------------ Language
    public static Result setLanguage(Loan_Journey__c j, String language) {
        String lang = LoanSevaI18n.parseLanguage(language);
        if (lang == null) {
            return result(j, LoanSevaI18n.msg('Language_Options', j.Language__c));
        }
        j.Language__c = lang;
        LoanSevaJourneyService.touch(j);
        String message = LoanSevaI18n.msg('Language_Set', lang);
        // At the menu the customer hasn't asked to verify yet, so repeat the menu, not the name/mobile ask
        String pending = awaiting(j) == 'menu' ? welcome(j) : pendingPrompt(j, false);
        update j;
        if (String.isNotBlank(pending)) {
            message += '\n\n' + pending;
        }
        return result(j, message);
    }

    // ------------------------------------------------------------------ Verify
    public static Result verifyCustomer(Loan_Journey__c j, String customerName, String mobile) {
        if (LoanSevaJourneyService.isNewLoan(j)) {
            return LoanSevaNewLoan.verify(j, customerName, mobile);
        }
        String lang = j.Language__c;
        if (j.Status__c == LoanSevaJourneyService.STATUS_EXITED && !j.OTP_Verified__c) {
            return result(j, LoanSevaI18n.msg('OTP_Locked', lang));
        }
        String mobile10 = LoanSevaJourneyService.normalizeMobile(mobile);
        if (String.isBlank(customerName) || mobile10 == null) {
            LoanSevaJourneyService.advance(j, 'Verify');
            update j;
            return result(j, LoanSevaI18n.msg('Verify_Prompt', lang));
        }
        j.Customer_Name__c = customerName.trim().abbreviate(120);
        LoanSevaJourneyService.advance(j, 'Verify');

        Contact c = LoanSevaJourneyService.findContact(mobile10);
        Existing_Loan__c loan = c == null ? null : LoanSevaJourneyService.activeLoan(c.Id);
        if (c == null || loan == null) {
            // No pre-approved offer: offer a new Personal Loan application instead (state apply_offer)
            if (j.Mobile__c == null) {
                j.Mobile__c = mobile10;
            }
            if (c != null && j.Contact__c == null) {
                j.Contact__c = c.Id;
            }
            j.Apply_Offered__c = true;
            update j;
            Result r = result(j, LoanSevaI18n.msg(c == null ? 'Verify_Not_Found' : 'NL_No_Offer', lang, new Map<String, Object>{
                'mobile' => maskMobile(mobile10),
                'name' => c == null ? '' : c.FirstName
            }));
            r.success = false;
            return r;
        }
        if (!namesMatch(customerName, c)) {
            update j;
            Result r = result(j, LoanSevaI18n.msg('Verify_Name_Mismatch', lang));
            r.success = false;
            return r;
        }
        if (j.Mobile__c == null) {
            j.Mobile__c = mobile10;
        }
        j.Contact__c = c.Id;
        j.Existing_Loan__c = loan.Id;
        j.OTP_Attempts__c = 0;
        update j;
        Loan_Journey__c fresh = LoanSevaJourneyService.byId(j.Id);
        String key = LoanSevaConfig.get().Demo_Mode__c ? 'OTP_Sent_Demo' : 'OTP_Sent';
        return result(fresh, LoanSevaI18n.msg(key, lang, new Map<String, Object>{
            'name' => LoanSevaJourneyService.firstName(fresh),
            'mobile' => maskMobile(mobile10),
            'otp' => LoanSevaConfig.get().Demo_OTP__c
        }));
    }

    public static Result verifyOtp(Loan_Journey__c j, String otp) {
        String lang = j.Language__c;
        Boolean newLoan = LoanSevaJourneyService.isNewLoan(j);
        if (j.OTP_Verified__c) {
            return newLoan ? promptAndSave(j) : loanSnapshot(j, LoanSevaJourneyService.activeLoan(j.Contact__c));
        }
        if (j.Status__c == LoanSevaJourneyService.STATUS_EXITED) {
            return result(j, LoanSevaI18n.msg('OTP_Locked', lang));
        }
        if (newLoan ? String.isBlank(j.Customer_Name__c) : j.Existing_Loan__c == null) {
            return result(j, LoanSevaI18n.msg(newLoan ? 'NL_Verify_Prompt' : 'Verify_Prompt', lang));
        }
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        String entered = otp == null ? '' : otp.replaceAll('[^0-9]', '');
        LoanSevaJourneyService.touch(j);
        if (cfg.Demo_Mode__c && entered == cfg.Demo_OTP__c) {
            j.OTP_Verified__c = true;
            j.Verified_At__c = Datetime.now();
            if (newLoan) {
                return LoanSevaNewLoan.verified(j);
            }
            update j;
            return loanSnapshot(j, LoanSevaJourneyService.activeLoan(j.Contact__c));
        }

        j.OTP_Attempts__c = (j.OTP_Attempts__c == null ? 0 : j.OTP_Attempts__c) + 1;
        Integer left = LoanSevaConfig.maxOtpAttempts() - Integer.valueOf(j.OTP_Attempts__c);
        if (left > 0) {
            update j;
            Result r = result(j, LoanSevaI18n.msg('OTP_Wrong', lang, new Map<String, Object>{ 'left' => left }));
            r.success = false;
            return r;
        }
        // Graceful exit + RM task after max attempts
        j.Status__c = LoanSevaJourneyService.STATUS_EXITED;
        j.Drop_Point__c = 'Verify - OTP failed ' + j.OTP_Attempts__c + 'x';
        j.Dropped_At__c = Datetime.now();
        j.Intent_Summary__c = LoanSevaJourneyService.intentSummary(j).abbreviate(255);
        LoanSevaJourneyService.createRmTask(j, 'OTP failed ' + j.OTP_Attempts__c + 'x - assist ' + LoanSevaJourneyService.firstName(j) + ' with verification');
        update j;
        Result r = result(j, LoanSevaI18n.msg('OTP_Locked', lang));
        r.success = false;
        return r;
    }

    private static Result loanSnapshot(Loan_Journey__c j, Existing_Loan__c loan) {
        Decimal onTime = loan.EMIs_Paid_On_Time__c;
        Decimal due = loan.EMIs_Due__c == null ? 12 : loan.EMIs_Due__c;
        return result(j, LoanSevaI18n.msg('Loan_Snapshot', j.Language__c, new Map<String, Object>{
            'name' => LoanSevaJourneyService.firstName(j),
            'account' => loan.Masked_Account__c,
            'product' => loan.Product__c,
            'outstanding' => LoanSevaI18n.inr(loan.Outstanding_Principal__c),
            'emi' => LoanSevaI18n.inr(loan.Current_EMI__c),
            'tenure' => loan.Tenure_Remaining_Months__c,
            'ontime' => onTime,
            'due' => due,
            'trackIcon' => onTime >= due ? '✅' : '👍'
        }));
    }

    public static Result confirmLoan(Loan_Journey__c j, Boolean confirmed) {
        String lang = j.Language__c;
        if (!j.OTP_Verified__c) {
            return promptAndSave(j);
        }
        if (confirmed != true) {
            LoanSevaJourneyService.touch(j);
            j.Drop_Point__c = 'Verify - loan details disputed';
            LoanSevaJourneyService.createRmTask(j, 'Customer disputes loan snapshot - please review ' + LoanSevaJourneyService.firstName(j));
            update j;
            Result r = result(j, LoanSevaI18n.msg('Loan_Disputed', lang));
            r.handoff = true;
            return r;
        }
        j.Loan_Confirmed__c = true;
        LoanSevaJourneyService.advance(j, 'Personalise');
        String message = LoanSevaI18n.msg('Personalise_Intro', lang) + '\n\n' + nextPersonaliseQuestion(j);
        update j;
        return result(j, message);
    }

    // ------------------------------------------------------------------ Personalise
    /** Stores the customer's reply against the next pending field and asks the next question. */
    public static Result personalise(Loan_Journey__c j, String answer) {
        String lang = j.Language__c;
        if (!j.OTP_Verified__c) {
            return promptAndSave(j);
        }
        if (!j.Loan_Confirmed__c) {
            j.Loan_Confirmed__c = true;
        }
        if (LoanSevaJourneyService.isNewLoan(j) && LoanSevaNewLoan.wantsChange(j, answer)) {
            return LoanSevaNewLoan.redoPrefilled(j);
        }
        LoanSevaJourneyService.advance(j, 'Personalise');
        String field = pendingField(j);
        if (field == null) {
            update j;
            return offer(j, null, null);
        }
        Boolean ok = applyAnswer(j, field, answer);
        if (!ok) {
            update j;
            Boolean typed = LoanSevaJourneyService.isNewLoan(j) && LoanSevaNewLoan.FREE_TEXT.contains(field);
            Result r = result(j, LoanSevaI18n.msg(typed ? 'NL_Invalid' : 'Personalise_Invalid', lang) + '\n\n' + question(j, field));
            r.success = false;
            return r;
        }
        LoanSevaJourneyService.touch(j);
        if (pendingField(j) == null) {
            j.Personalised_At__c = Datetime.now();
            update j;
            return offer(j, null, null);
        }
        String next = nextPersonaliseQuestion(j);
        update j;
        return result(j, next);
    }

    private static String pendingField(Loan_Journey__c j) {
        if (LoanSevaJourneyService.isNewLoan(j)) {
            return LoanSevaNewLoan.pendingField(j);
        }
        if (String.isBlank(j.Employment_Type__c)) {
            return 'employment';
        }
        if (String.isBlank(j.Company_Name__c)) {
            return 'company';
        }
        if (String.isBlank(j.Income_Bucket__c)) {
            return 'income';
        }
        if (String.isBlank(j.Purpose__c)) {
            return 'purpose';
        }
        if (j.Desired_Amount__c == null) {
            return 'amount';
        }
        return null;
    }

    private static String nextPersonaliseQuestion(Loan_Journey__c j) {
        String field = pendingField(j);
        return field == null ? '' : question(j, field);
    }

    private static String question(Loan_Journey__c j, String field) {
        if (LoanSevaJourneyService.isNewLoan(j)) {
            return LoanSevaNewLoan.question(j, field);
        }
        return withProgress(topUpQuestion(j, field));
    }

    private static final Pattern COUNTER = Pattern.compile('^\\*([0-9]+)/([0-9]+)\\* — ');

    /** "*2/5* — Which company…" becomes "*2/5* ▰▰▱▱▱ — Which company…". */
    public static String withProgress(String text) {
        Matcher m = text == null ? null : COUNTER.matcher(text);
        if (m == null || !m.find()) {
            return text;
        }
        Integer n = Integer.valueOf(m.group(1));
        Integer total = Integer.valueOf(m.group(2));
        String bar = '▰'.repeat(Math.min(n, total)) + '▱'.repeat(Math.max(total - n, 0));
        return '*' + n + '/' + total + '* ' + bar + ' — ' + text.substring(m.end());
    }

    private static String topUpQuestion(Loan_Journey__c j, String field) {
        String lang = j.Language__c;
        if (field == 'employment') {
            return LoanSevaI18n.msg('Q_Employment', lang);
        }
        if (field == 'company') {
            return LoanSevaI18n.msg(j.Employment_Type__c == 'Self-employed' ? 'Q_Business' : 'Q_Company', lang);
        }
        if (field == 'income') {
            return LoanSevaI18n.msg('Q_Income', lang);
        }
        if (field == 'purpose') {
            return LoanSevaI18n.msg('Q_Purpose', lang);
        }
        Existing_Loan__c loan = LoanSevaJourneyService.activeLoan(j.Contact__c);
        List<Decimal> options = amountOptions(loan.Pre_Approved_Limit__c);
        List<String> labels = new List<String>();
        List<String> raw = new List<String>();
        for (Integer i = 0; i < options.size(); i++) {
            labels.add(numberEmoji(i + 1) + ' ' + LoanSevaI18n.inr(options[i]));
            raw.add(String.valueOf(options[i]));
        }
        j.Amount_Options__c = String.join(raw, ',');
        return LoanSevaI18n.msg('Q_Amount', lang, new Map<String, Object>{
            'limit' => LoanSevaI18n.inr(loan.Pre_Approved_Limit__c),
            'options' => String.join(labels, '\n')
        });
    }

    /** 25% / 50% / 75% / 100% of the pre-approved limit, rounded down, de-duplicated. */
    public static List<Decimal> amountOptions(Decimal preApproved) {
        List<Decimal> options = new List<Decimal>();
        Decimal step = LoanSevaConfig.rounding();
        Decimal minimum = LoanSevaConfig.get().Min_Topup_Amount__c;
        for (Decimal pct : new List<Decimal>{ 0.25, 0.5, 0.75, 1 }) {
            Decimal v = LoanSevaEligibilityEngine.roundDown(preApproved * pct, step);
            if (v >= minimum && !options.contains(v)) {
                options.add(v);
            }
        }
        if (options.isEmpty()) {
            options.add(preApproved);
        }
        return options;
    }

    public static Boolean applyAnswer(Loan_Journey__c j, String field, String answer) {
        if (String.isBlank(answer)) {
            return false;
        }
        if (LoanSevaJourneyService.isNewLoan(j) && LoanSevaNewLoan.FREE_TEXT.contains(field)) {
            return LoanSevaNewLoan.applyAnswer(j, field, answer);
        }
        String a = answer.trim();
        String lower = a.toLowerCase();
        Integer choice = choiceNumber(a);
        if (field == 'employment') {
            if (choice == 1 || lower.contains('salar') || lower.contains('job') || lower.contains('नौकरी') || lower.contains('वेतन') || lower.contains('पगार') || lower.contains('नोकरी')) {
                j.Employment_Type__c = 'Salaried';
            } else if (choice == 2 || lower.contains('self') || lower.contains('business') || lower.contains('व्यवसाय') || lower.contains('स्वयं') || lower.contains('स्व-रोजगार') || lower.contains('धंदा')) {
                j.Employment_Type__c = 'Self-employed';
            } else {
                return false;
            }
            return true;
        }
        if (field == 'company') {
            if (a.length() < 2) {
                return false;
            }
            j.Company_Name__c = a.abbreviate(120);
            return true;
        }
        if (field == 'income') {
            Decimal amount = parseAmount(a);
            if (amount != null) {
                j.Income_Bucket__c = amount < 50000 ? 'Below 50K' : amount < 100000 ? '50K-1L' : amount < 200000 ? '1L-2L' : '2L+';
                return true;
            }
            if (choice != null && choice >= 1 && choice <= INCOME_BUCKETS.size()) {
                j.Income_Bucket__c = INCOME_BUCKETS[choice - 1];
                return true;
            }
            return false;
        }
        if (field == 'purpose') {
            if (choice != null && choice >= 1 && choice <= PURPOSES.size()) {
                j.Purpose__c = PURPOSES[choice - 1];
                return true;
            }
            Map<String, List<String>> keywords = new Map<String, List<String>>{
                'Home renovation' => new List<String>{ 'renov', 'home', 'house', 'घर', 'नवीनीकरण', 'नूतनीकरण' },
                'Education' => new List<String>{ 'educat', 'study', 'college', 'course', 'शिक्षा', 'शिक्षण' },
                'Medical' => new List<String>{ 'medic', 'hospital', 'health', 'surgery', 'चिकित्सा', 'इलाज', 'वैद्यकीय' },
                'Travel' => new List<String>{ 'travel', 'trip', 'holiday', 'vacation', 'यात्रा', 'प्रवास' },
                'Wedding' => new List<String>{ 'wedding', 'marriage', 'shaadi', 'शादी', 'विवाह', 'लग्न' },
                'Other' => new List<String>{ 'other', 'अन्य', 'इतर' }
            };
            for (String p : PURPOSES) {
                for (String k : keywords.get(p)) {
                    if (lower.contains(k)) {
                        j.Purpose__c = p;
                        return true;
                    }
                }
            }
            return false;
        }
        if (field == 'amount') {
            Decimal amount = parseAmount(a);
            if (amount != null && amount >= LoanSevaConfig.get().Min_Topup_Amount__c) {
                j.Desired_Amount__c = amount;
                return true;
            }
            List<String> offered = String.isBlank(j.Amount_Options__c) ? new List<String>() : j.Amount_Options__c.split(',');
            if (amount == null && choice != null && choice >= 1 && choice <= offered.size()) {
                j.Desired_Amount__c = Decimal.valueOf(offered[choice - 1]);
                return true;
            }
            return false;
        }
        return false;
    }

    // ------------------------------------------------------------------ Offer
    public static Result offer(Loan_Journey__c j, String amountText, String tenureText) {
        String lang = j.Language__c;
        if (!j.OTP_Verified__c || pendingField(j) != null) {
            return promptAndSave(j);
        }
        Decimal requestedAmount = parseAmount(amountText);
        if (requestedAmount != null) {
            j.Desired_Amount__c = requestedAmount;
        }
        Integer tenure = parseTenure(tenureText);
        if (tenure == null && j.Offer_Tenure_Months__c != null && String.isNotBlank(amountText)) {
            tenure = Integer.valueOf(j.Offer_Tenure_Months__c);
        }

        Boolean newLoan = LoanSevaJourneyService.isNewLoan(j);
        Existing_Loan__c loan = newLoan ? null : LoanSevaJourneyService.activeLoan(j.Contact__c);
        LoanSevaEligibilityEngine.Result e = newLoan
            ? LoanSevaEligibilityEngine.evaluateNew(j.Monthly_Income__c, j.Existing_EMIs__c, j.Employment_Type__c, j.Desired_Amount__c, tenure)
            : LoanSevaEligibilityEngine.evaluate(loan, j.Income_Bucket__c, j.Employment_Type__c, j.Desired_Amount__c, tenure);
        LoanSevaJourneyService.advance(j, 'Offer');
        j.Offer_Presented_At__c = Datetime.now();
        Loan_Application__c app = upsertApplication(j, loan, e);

        if (!e.eligible) {
            j.Offer_Amount__c = null;
            j.Drop_Point__c = 'Offer - referred to RM';
            LoanSevaJourneyService.createRmTask(j, 'Refer: ' + LoanSevaJourneyService.firstName(j) + ' needs a tailored ' + (newLoan ? 'personal loan' : 'top-up') + ' option');
            update j;
            Result r = result(j, LoanSevaI18n.msg(newLoan ? 'NL_Refer' : 'Offer_Refer', lang, new Map<String, Object>{ 'name' => LoanSevaJourneyService.firstName(j) }));
            r.success = false;
            r.handoff = true;
            return r;
        }

        j.Offer_Amount__c = e.amount;
        j.Offer_Rate__c = e.rate;
        j.Offer_Tenure_Months__c = e.tenure;
        j.Offer_EMI__c = e.emi;
        j.Processing_Fee__c = e.processingFee;
        j.Loan_Application__c = app.Id;
        LoanSevaJourneyService.touch(j);
        update j;

        List<String> others = new List<String>();
        for (Integer t : e.emiByTenure.keySet()) {
            if (t != e.tenure) {
                others.add('▫️ ' + t + 'm · ' + LoanSevaI18n.inr(e.emiByTenure.get(t)));
            }
        }
        String message = LoanSevaI18n.msg(newLoan ? 'NL_Offer_Card' : 'Offer_Card', lang, new Map<String, Object>{
            'name' => LoanSevaJourneyService.firstName(j),
            'amount' => LoanSevaI18n.inr(e.amount),
            'rate' => e.rate.setScale(2).toPlainString(),
            'tenure' => e.tenure,
            'emi' => LoanSevaI18n.inr(e.emi),
            'fee' => LoanSevaI18n.inr(e.processingFee),
            'otherTenures' => String.join(others, '\n')
        });
        if (e.cappedBelowDesired) {
            message = LoanSevaI18n.msg('Offer_Capped', lang, new Map<String, Object>{ 'max' => LoanSevaI18n.inr(e.amount) }) + '\n\n' + message;
        }
        return result(j, message);
    }

    private static Loan_Application__c upsertApplication(Loan_Journey__c j, Existing_Loan__c loan, LoanSevaEligibilityEngine.Result e) {
        Loan_Application__c app = new Loan_Application__c(Id = j.Loan_Application__c);
        if (app.Id == null) {
            app.Loan_Journey__c = j.Id;
            app.Contact__c = j.Contact__c;
            app.Existing_Loan__c = loan == null ? null : loan.Id;
            Boolean newLoan = LoanSevaJourneyService.isNewLoan(j);
            app.Product__c = newLoan ? 'Personal Loan' : 'Personal Loan Top-Up';
            app.Application_Type__c = newLoan ? LoanSevaJourneyService.TYPE_NEW_LOAN : 'Top-Up';
        }
        app.Status__c = e.eligible ? 'Offer Presented' : 'Referred to RM';
        app.Requested_Amount__c = j.Desired_Amount__c;
        app.Eligible_Amount__c = e.maxEligible;
        app.Offer_Amount__c = e.eligible ? e.amount : null;
        app.Rate__c = e.eligible ? e.rate : null;
        app.Tenure_Months__c = e.tenure;
        app.EMI__c = e.eligible ? e.emi : null;
        app.Processing_Fee__c = e.eligible ? e.processingFee : null;
        app.FOIR__c = e.foirPct;
        app.Employment_Type__c = j.Employment_Type__c;
        app.Company_Name__c = j.Company_Name__c;
        app.Income_Bucket__c = j.Income_Bucket__c;
        app.Purpose__c = j.Purpose__c;
        app.Eligibility_Notes__c = String.join(e.notes, '\n').abbreviate(4000);
        upsert app;
        j.Loan_Application__c = app.Id;
        return app;
    }

    public static Result acceptOffer(Loan_Journey__c j) {
        String lang = j.Language__c;
        if (j.Offer_Amount__c == null || j.Loan_Application__c == null) {
            return promptAndSave(j);
        }
        if (LoanSevaJourneyService.isNewLoan(j)) {
            // the reference number is assigned at submit, after documents and consent
            return LoanSevaNewLoan.accepted(j);
        }
        if (String.isBlank(j.Reference_Number__c)) {
            Loan_Application__c app = [SELECT Id, Name FROM Loan_Application__c WHERE Id = :j.Loan_Application__c];
            j.Reference_Number__c = referenceNumber(app.Name);
            app.Reference_Number__c = j.Reference_Number__c;
            app.Status__c = 'Offer Accepted';
            update app;
        }
        j.Offer_Accepted__c = true;
        j.Accepted_At__c = Datetime.now();
        LoanSevaJourneyService.advance(j, 'Callback');
        String slots = callbackSlots(j);
        update j;
        return result(j, LoanSevaI18n.msg('Offer_Accepted', lang, new Map<String, Object>{
            'ref' => j.Reference_Number__c,
            'slots' => slots
        }));
    }

    /** KMB-PLTU-YYMMDD-NNNN (IST date, NNNN from the application auto-number). */
    public static String referenceNumber(String sequence) {
        return referenceNumber(LoanSevaConfig.get().Reference_Prefix__c, sequence);
    }

    public static String referenceNumber(String prefix, String sequence) {
        String seq = sequence == null ? '0000' : sequence.replaceAll('[^0-9]', '').leftPad(4, '0').right(4);
        return prefix + '-' + Datetime.now().format('yyMMdd', LoanSevaI18n.TIMEZONE) + '-' + seq;
    }

    // ------------------------------------------------------------------ Callback
    /** Offers: 1 = within 24 hrs, 2-4 = concrete IST slots. Stores options on the journey. */
    private static String callbackSlots(Loan_Journey__c j) {
        List<Datetime> slots = new List<Datetime>{ asapSlot() };
        Date tomorrow = LoanSevaI18n.todayIst().addDays(1);
        slots.add(LoanSevaI18n.istDateTime(tomorrow, 11, 0));
        slots.add(LoanSevaI18n.istDateTime(tomorrow, 16, 0));
        slots.add(LoanSevaI18n.istDateTime(tomorrow.addDays(1), 11, 0));
        List<String> iso = new List<String>();
        List<String> labels = new List<String>();
        for (Integer i = 0; i < slots.size(); i++) {
            iso.add(slots[i].formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
            if (i > 0) {
                labels.add(numberEmoji(i + 1) + ' ' + LoanSevaI18n.formatDateTime(slots[i]));
            }
        }
        j.Callback_Options__c = String.join(iso, ';');
        return String.join(labels, '\n');
    }

    /** Next business-hours slot at least 1 hour out (09:00–19:00 IST). */
    @TestVisible
    private static Datetime asapSlot() {
        Datetime candidate = Datetime.now().addHours(1);
        Integer hour = LoanSevaI18n.istHour(candidate);
        Date day = Date.valueOf(candidate.format('yyyy-MM-dd', LoanSevaI18n.TIMEZONE));
        if (hour < 9) {
            return LoanSevaI18n.istDateTime(day, 10, 0);
        }
        if (hour >= 19) {
            return LoanSevaI18n.istDateTime(day.addDays(1), 10, 0);
        }
        Integer minute = Integer.valueOf(candidate.format('m', LoanSevaI18n.TIMEZONE));
        return LoanSevaI18n.istDateTime(day, minute > 30 ? hour + 1 : hour, minute > 30 || minute == 0 ? 0 : 30);
    }

    public static Result scheduleCallback(Loan_Journey__c j, String preference, String preferredDateTimeIso) {
        String lang = j.Language__c;
        if (!j.Offer_Accepted__c) {
            return promptAndSave(j);
        }
        Datetime slotTime = null;
        Integer choice = choiceNumber(preference);
        List<String> options = String.isBlank(j.Callback_Options__c) ? new List<String>() : j.Callback_Options__c.split(';');
        if (choice != null && choice >= 1 && choice <= options.size()) {
            slotTime = (Datetime) JSON.deserialize('"' + options[choice - 1] + '"', Datetime.class);
        } else if (String.isNotBlank(preference) && isAsap(preference)) {
            slotTime = asapSlot();
        }
        if (slotTime == null && String.isNotBlank(preferredDateTimeIso)) {
            slotTime = parseIso(preferredDateTimeIso);
        }
        if (slotTime == null) {
            slotTime = LoanSevaDateParser.parse(preference);
        }
        if (slotTime == null || slotTime < Datetime.now()) {
            Result r = result(j, LoanSevaI18n.msg('Callback_Invalid', lang) + '\n\n' + LoanSevaI18n.msg('Callback_Options', lang, new Map<String, Object>{ 'slots' => callbackSlots(j) }));
            update j;
            r.success = false;
            return r;
        }

        j.Callback_DateTime__c = slotTime;
        LoanSevaJourneyService.advance(j, 'Feedback');
        j.Feedback_Step__c = 1;
        j.Intent_Summary__c = LoanSevaJourneyService.intentSummary(j).abbreviate(255);
        update new Loan_Application__c(Id = j.Loan_Application__c, Status__c = 'Callback Scheduled', Callback_DateTime__c = slotTime);

        String summary = j.Intent_Summary__c;
        Id ownerId = LoanSevaJourneyService.rmOwnerId(j);
        Task t = LoanSevaJourneyService.buildRmTask(j, summary, LoanSevaJourneyService.rmDescription(j), Date.valueOf(slotTime.format('yyyy-MM-dd', LoanSevaI18n.TIMEZONE)));
        t.WhatId = j.Loan_Application__c;
        Event ev = new Event(
            OwnerId = ownerId,
            Subject = ('Callback: ' + summary).abbreviate(255),
            Description = LoanSevaJourneyService.rmDescription(j),
            StartDateTime = slotTime,
            EndDateTime = slotTime.addMinutes(30),
            WhoId = j.Contact__c,
            WhatId = j.Loan_Application__c,
            Type = 'Call'
        );
        insert t;
        insert ev;
        j.RM_Followup_Created__c = true;
        update j;
        return result(j, LoanSevaI18n.msg('Callback_Confirmed', lang, new Map<String, Object>{
            'when' => LoanSevaI18n.formatDateTime(slotTime),
            'ref' => j.Reference_Number__c
        }) + '\n\n' + LoanSevaI18n.msg('FB_Q1', lang));
    }

    private static Boolean isAsap(String s) {
        String l = s.toLowerCase();
        return l.contains('24') || l.contains('asap') || l.contains('soon') || l.contains('जल्दी') || l.contains('लवकर');
    }

    private static Datetime parseIso(String s) {
        try {
            String v = s.trim();
            if (!v.endsWith('Z') && !v.contains('+')) {
                // treat naive values as IST wall-clock
                Datetime naive = (Datetime) JSON.deserialize('"' + v + (v.length() == 16 ? ':00' : '') + 'Z"', Datetime.class);
                return naive.addMinutes(-330);
            }
            return (Datetime) JSON.deserialize('"' + v + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }

    // ------------------------------------------------------------------ Feedback
    public static Result feedback(Loan_Journey__c j, String answer) {
        String lang = j.Language__c;
        Integer step = j.Feedback_Step__c == null ? 0 : Integer.valueOf(j.Feedback_Step__c);
        if (step == 0) {
            j.Feedback_Step__c = 1;
            LoanSevaJourneyService.advance(j, 'Feedback');
            update j;
            return result(j, LoanSevaI18n.msg('FB_Q1_Intro', lang) + '\n\n' + LoanSevaI18n.msg('FB_Q1', lang));
        }
        if (step >= 4) {
            return result(j, LoanSevaI18n.msg('FB_Thanks', lang, signOffTokens(j)));
        }
        Journey_Feedback__c fb = currentFeedback(j);
        Integer choice = choiceNumber(answer);
        String a = answer == null ? '' : answer.trim();
        if (step == 1) {
            if (choice == null || choice < 1 || choice > 5) {
                return invalidFeedback(j, 'FB_Q1');
            }
            fb.CSAT__c = choice;
        } else if (step == 2) {
            String resolution = parseResolution(a, choice);
            if (resolution == null) {
                return invalidFeedback(j, 'FB_Q2');
            }
            fb.Resolution__c = resolution;
        } else if (step == 3) {
            String l = a.toLowerCase();
            Boolean skip = l == 'skip' || l == 'no' || l == 'nothing' || l == 'na' || l == 'छोड़ें' || l == 'नहीं' || l == 'वगळा' || l == 'नाही';
            fb.Comment__c = skip ? null : a.abbreviate(4000);
        }
        upsert fb;
        j.Feedback_Step__c = step + 1;
        LoanSevaJourneyService.touch(j);
        if (step == 3) {
            j.Stage__c = 'Completed';
            j.Status__c = LoanSevaJourneyService.STATUS_COMPLETED;
            j.Completed_At__c = Datetime.now();
            update j;
            return result(j, LoanSevaI18n.msg('FB_Thanks', lang, signOffTokens(j)));
        }
        update j;
        return result(j, LoanSevaI18n.msg(step == 1 ? 'FB_Q2' : 'FB_Q3', lang));
    }

    private static Map<String, Object> signOffTokens(Loan_Journey__c j) {
        return new Map<String, Object>{
            'name' => LoanSevaJourneyService.firstName(j),
            'ref' => j.Reference_Number__c == null ? '' : j.Reference_Number__c
        };
    }

    private static Result invalidFeedback(Loan_Journey__c j, String questionKey) {
        Result r = result(j, LoanSevaI18n.msg('Personalise_Invalid', j.Language__c) + '\n\n' + LoanSevaI18n.msg(questionKey, j.Language__c));
        r.success = false;
        return r;
    }

    private static String parseResolution(String a, Integer choice) {
        String l = a.toLowerCase();
        if (choice == 1 || l.contains('fully') || l.contains('yes') || l.contains('हाँ') || l.contains('हो,') || l.contains('पूर्ण')) {
            return 'Yes, fully';
        }
        if (choice == 2 || l.contains('mostly') || l.contains('ज़्यादातर') || l.contains('ज्यादातर') || l.contains('बहुतेक')) {
            return 'Mostly';
        }
        if (choice == 3 || l.contains('not') || l.contains('नहीं') || l.contains('नाही')) {
            return 'Not really';
        }
        return null;
    }

    private static Journey_Feedback__c currentFeedback(Loan_Journey__c j) {
        List<Journey_Feedback__c> rows = [
            SELECT Id, CSAT__c, Resolution__c, Comment__c FROM Journey_Feedback__c
            WHERE Loan_Journey__c = :j.Id ORDER BY CreatedDate DESC LIMIT 1
        ];
        return rows.isEmpty() ? new Journey_Feedback__c(Loan_Journey__c = j.Id, Contact__c = j.Contact__c) : rows[0];
    }

    // ------------------------------------------------------------------ Escalation
    public static Result escalate(Loan_Journey__c j, String reason) {
        LoanSevaJourneyService.touch(j);
        j.Escalated__c = true;
        String r = String.isBlank(reason) ? 'Customer asked for a specialist' : reason.abbreviate(120);
        LoanSevaJourneyService.createRmTask(j, 'Human requested - ' + r + ' (' + LoanSevaJourneyService.intentSummary(j) + ')');
        update j;
        Result res = result(j, LoanSevaI18n.msg('Escalate', j.Language__c));
        res.handoff = true;
        return res;
    }

    // ------------------------------------------------------------------ Free-text reply
    /**
     * Routes a customer reply to whatever the journey is waiting for, so the agent never has to pick
     * the step from the conversation text. A clear Top-Up question is answered first at any step.
     */
    public static Result reply(Loan_Journey__c j, String text) {
        String t = text == null ? '' : text.trim();
        String state = awaiting(j);
        Integer choice = choiceNumber(t);
        if (j.Menu_Pending__c == true) {
            j.Menu_Pending__c = false;
            Boolean option = NO_LETTERS.matcher(t).matches();
            if (option && choice == 1 || isYes(t) || wantsOffer(t)) {
                return resume(j);
            }
            if (option && choice == 2) {
                return askQuestion(j);
            }
            if (option && choice == 3) {
                return escalate(j, 'Chose Talk to a specialist from the menu');
            }
            if (option && choice == 4) {
                return LoanSevaJourneyService.isNewLoan(j) ? resume(j) : LoanSevaNewLoan.start(j);
            }
            update j;
        }
        Result shortcut = LoanSevaShortcuts.handle(j, t);
        if (shortcut != null) {
            return shortcut;
        }
        Boolean raw = RAW_INPUT.contains(state);
        // Said in their own words at any step, even mid-PAN or mid-OTP: a person, or back to the menu
        if (raw && wantsHumanWhileTyping(t, state)) {
            return escalate(j, 'Asked for a specialist while entering ' + state + ': ' + t);
        }
        if (wantsMenu(t, state)) {
            return backToMenu(j);
        }
        if (j.Question_Pending__c == true && !raw) {
            // After "Ask a question" the next message is a question, so "Yes" or "tell me more" can
            // never accept the offer. A bare option number still picks that option.
            j.Question_Pending__c = false;
            if (wantsOffer(t) || isYes(t) && t.split('\\s+').size() <= 2) {
                // "Show my offer" (or the planner's "Yes") is a request to carry on, not a question
                return state == 'menu' ? verifyCustomer(j, null, null) : resume(j);
            }
            if (!NO_LETTERS.matcher(t).matches() && !wantsHuman(t)) {
                return answerFaq(j, t);
            }
            update j;
        }
        if (t.contains('?') && !raw && LoanSevaFaqMatcher.bestMatch(t) != null) {
            return answerFaq(j, t);
        }
        if (!raw && wantsHuman(t)) {
            return escalate(j, 'Asked for a specialist: ' + t);
        }
        if ((state == 'menu' || state == 'identity') && wantsNewLoan(t) && !LoanSevaJourneyService.isNewLoan(j)) {
            return LoanSevaNewLoan.start(j);
        }
        switch on state {
            when 'identity' {
                return verifyCustomer(j, identityName(t), t);
            }
            when 'apply_offer' {
                return applyOfferReply(j, t, choice);
            }
            when 'otp' {
                return verifyOtp(j, t);
            }
            when 'loan_confirm' {
                if (choice == 1 || isYes(t)) {
                    return confirmLoan(j, true);
                }
                if (choice == 2 || isNo(t)) {
                    return confirmLoan(j, false);
                }
                return faqOrPrompt(j, t);
            }
            when 'employment', 'company', 'income', 'purpose', 'amount', 'dob', 'pan', 'email', 'pincode', 'obligations' {
                return personalise(j, t);
            }
            when 'doc_pan', 'doc_bank', 'doc_salary' {
                return LoanSevaNewLoan.document(j, t);
            }
            when 'consent' {
                return LoanSevaNewLoan.consent(j, t, choice);
            }
            when 'offer_decision' {
                return offerDecision(j, t, choice);
            }
            when 'callback' {
                return scheduleCallback(j, t, null);
            }
            when 'feedback_csat', 'feedback_resolution', 'feedback_comment' {
                return feedback(j, t);
            }
            when 'handoff' {
                return verifyCustomer(j, null, null);
            }
            when 'done' {
                return faqOrPrompt(j, t);
            }
            when else {
                if (choice == 1 || isYes(t) || wantsOffer(t)) {
                    return verifyCustomer(j, null, null);
                }
                if (choice == 2) {
                    return askQuestion(j);
                }
                if (choice == 3) {
                    return escalate(j, 'Chose Talk to a specialist from the menu');
                }
                if (choice == 4) {
                    return LoanSevaNewLoan.start(j);
                }
                return LoanSevaFaqMatcher.bestMatch(t, true) != null ? answerFaq(j, t) : start(j);
            }
        }
    }

    /** States whose answer is typed data (OTP, PAN, email...), so it is never read as a question or a request for a person. */
    private static final Set<String> RAW_INPUT = new Set<String>{ 'otp', 'company', 'dob', 'pan', 'email' };

    private static String identityName(String t) {
        return t.replaceAll('[0-9+\\-()]', ' ').replaceAll('[,;:|/.]', ' ')
            .replaceAll('(?i)\\b(my|name|is|i am|this is|mobile|number|no|phone|registered)\\b', ' ').normalizeSpace();
    }

    /** No pre-approved offer was found: 1 apply for a new loan, 2 re-enter details, 3 specialist. */
    private static Result applyOfferReply(Loan_Journey__c j, String t, Integer choice) {
        if (choice == 1 || isYes(t) || wantsNewLoan(t)) {
            return LoanSevaNewLoan.start(j);
        }
        if (choice == 3) {
            return escalate(j, 'No pre-approved offer - chose to talk to a specialist');
        }
        if (choice == 2 || t.replaceAll('[^0-9]', '').length() >= 10) {
            j.Apply_Offered__c = false;
            if (choice == 2) {
                LoanSevaJourneyService.touch(j);
                update j;
                return result(j, LoanSevaI18n.msg('Verify_Prompt', j.Language__c));
            }
            return verifyCustomer(j, identityName(t), t);
        }
        return faqOrPrompt(j, t);
    }

    /** "Apply for a loan", "I want a new personal loan", नया लोन, नवीन कर्ज. */
    private static final Pattern NEW_LOAN = Pattern.compile(
        '(?i).*(\\b(apply|new|fresh)\\b.*\\b(loan|pl)\\b|नया लोन|नए लोन|लोन के लिए आवेदन|नवीन कर्ज|नवीन लोन|कर्जासाठी अर्ज).*');

    /** "How is Top-Up different from a new loan" is an FAQ, not an application. */
    private static final Pattern COMPARES = Pattern.compile(
        '(?i).*(\\b(differ\\w*|difference|vs|versus|compare\\w*|comparison|better|than)\\b|अंतर|फर्क|फ़र्क|फरक|तुलना).*');

    private static Boolean wantsNewLoan(String s) {
        if (String.isBlank(s)) {
            return false;
        }
        String line = s.replace('\n', ' ');
        return NEW_LOAN.matcher(line).matches() && !COMPARES.matcher(line).matches();
    }

    private static Result offerDecision(Loan_Journey__c j, String t, Integer choice) {
        // An amount or tenure comes first, so "3 lakh for 48 months" is a change, not option 3
        String tenureText = tenurePhrase(t);
        String amountText = parseAmount(tenureText == null ? t : t.replace(tenureText, ' ')) != null
            ? (tenureText == null ? t : t.replace(tenureText, ' '))
            : null;
        if (amountText != null || tenureText != null) {
            return offer(j, amountText, tenureText);
        }
        if (choice == 1 || isYes(t) || t.toLowerCase().contains('accept')) {
            return acceptOffer(j);
        }
        if (choice == 3) {
            return askQuestion(j);
        }
        if (choice == 2) {
            return result(j, LoanSevaI18n.msg('Offer_Change_Prompt', j.Language__c));
        }
        return faqOrPrompt(j, t);
    }

    private static final Pattern TENURE_PHRASE = Pattern.compile('(?i)([0-9]+\\s*(?:months?|mo|mths?|years?|yrs?|y|साल|वर्ष|महीने|महिने|वर्षे))(?![a-z])');

    /** The tenure part of a message, e.g. "48 months" in "3 lakh for 48 months", or null. */
    public static String tenurePhrase(String t) {
        if (String.isBlank(t)) {
            return null;
        }
        Matcher m = TENURE_PHRASE.matcher(t);
        return m.find() ? m.group(1) : null;
    }

    /** A bare option such as 1, 2️⃣ or ३: picks that option even while a question is pending. */
    private static final Pattern NO_LETTERS = Pattern.compile('[^\\p{L}]*');

    private static Result askQuestion(Loan_Journey__c j) {
        j.Question_Pending__c = true;
        LoanSevaJourneyService.touch(j);
        update j;
        return result(j, LoanSevaI18n.msg('Ask_Question_Prompt', j.Language__c));
    }

    public static Result faqOrPrompt(Loan_Journey__c j, String t) {
        return String.isNotBlank(t) && LoanSevaFaqMatcher.bestMatch(t) != null ? answerFaq(j, t) : promptAndSave(j);
    }

    private static final Set<String> YES_WORDS = new Set<String>{
        'yes', 'y', 'yeah', 'yep', 'yup', 'ok', 'okay', 'correct', 'right', 'sure', 'confirm', 'confirmed',
        'haan', 'han', 'ha', 'haa', 'ho', 'hoy', 'sahi', 'हाँ', 'हां', 'हा', 'हो', 'होय', 'सही', 'बरोबर', 'ठीक'
    };
    private static final Set<String> NO_WORDS = new Set<String>{
        'no', 'n', 'nope', 'nah', 'wrong', 'incorrect', 'nahi', 'nahin', 'galat', 'नहीं', 'नही', 'नाही', 'गलत', 'चुकीचे'
    };

    public static Boolean isYes(String s) {
        return firstWordIn(s, YES_WORDS) || (s != null && s.toLowerCase().contains('go ahead'));
    }

    /** A request for a person rather than an answer; escalation is handled here so the RM Task is always logged. */
    private static final Pattern HUMAN = Pattern.compile(
        '(?i).*(\\b(human|agent|specialist|executive|rm|relationship manager|real person|someone|call me now)\\b'
        + '|इंसान|एजेंट|विशेषज्ञ|तज्ज्ञ|व्यक्ति|माणूस).*');

    private static Boolean wantsHuman(String s) {
        return String.isNotBlank(s) && HUMAN.matcher(s.replace('\n', ' ')).matches();
    }

    /** A request in words ("can I talk to someone", "connect me to an agent", मुझे किसी से बात करनी है), never a typed answer. */
    private static final Pattern ASK_FOR_PERSON = Pattern.compile(
        '(?i).*(\\b(talk|speak|chat|connect me|transfer me|put me through)\\b.*\\b(to|with)\\b.*\\b(someone|somebody|person|human|agent|specialist|executive|rm|banker|manager|expert)\\b'
        + '|\\b(want|need)\\b.*\\b(human|agent|specialist|real person|executive)\\b'
        + '|बात कर|बात करनी|बात करना|बोलायचे|बोलायचं|बोलू इच्छितो|बोलू इच्छिते|विशेषज्ञ से|तज्ज्ञांशी|एजेंट से).*');

    /**
     * On a typed-data step (OTP, DOB, PAN, email, company) only a clear request counts, so "Agent Corp" stays a
     * company and "rm@kotak.com" an email. A bare "agent" or "RM" can't be an OTP, a date or a PAN.
     */
    private static Boolean wantsHumanWhileTyping(String t, String state) {
        if (String.isBlank(t) || state == 'email' && t.contains('@')) {
            return false;
        }
        String line = t.replace('\n', ' ');
        return ASK_FOR_PERSON.matcher(line).matches() || (new Set<String>{ 'otp', 'dob', 'pan' }.contains(state) && wantsHuman(line));
    }

    /** "Main menu", "go back", "start over", "I don't want to continue", "not now", रहने दो, मागे जा. */
    private static final Pattern MENU = Pattern.compile(
        '(?i)\\s*(menu|main menu|back|go back|cancel|stop|exit|quit|not now|start over|restart)\\s*[.!]*\\s*'
        + '|.*(\\b(go|take me|back) (back )?to (the )?(main )?menu\\b|\\bshow (me )?(the )?(main )?menu\\b'
        + '|\\b(don\'?t|do not|dont) want to (proceed|continue|go ahead|go on|apply)\\b|\\bnot interested\\b'
        + '|\\bstop (this|the application|here)\\b|\\bstart (again|over)\\b'
        + '|मेनू|मेन्यू|वापस जा|वापस मेन|रहने दो|आगे नहीं बढ़ना|नहीं करना|अभी नहीं|मागे जा|मुख्य मेनू|पुढे जायचे नाही|आत्ता नको).*');

    private static Boolean wantsMenu(String t, String state) {
        if (String.isBlank(t) || (state == 'menu' || state == 'feedback_comment') && !t.containsIgnoreCase('menu') || state == 'email' && t.contains('@')) {
            return false;
        }
        return MENU.matcher(t.replace('\n', ' ')).matches();
    }

    /** Pauses where the customer is: everything is kept, and option 1 on the menu picks up the same step. */
    private static Result backToMenu(Loan_Journey__c j) {
        Boolean midJourney = awaiting(j) != 'menu';
        j.Question_Pending__c = false;
        Result r = start(j);
        if (midJourney) {
            r.message = LoanSevaI18n.msg('Menu_Paused', j.Language__c) + '\n\n' + r.message;
        }
        return r;
    }

    /** Asking to see their own offer or limit, e.g. "I want to know my offer", "how much can I get". */
    private static final Pattern OFFER = Pattern.compile(
        '(?i).*(\\b(my|see|show|check|view)\\b.*\\b(offer|limit|eligibility)\\b|how much (can|will) i get'
        + '|मेरा ऑफर|ऑफर दिखा|माझी ऑफर|ऑफर दाखव).*');

    private static Boolean wantsOffer(String s) {
        return String.isNotBlank(s) && OFFER.matcher(s.replace('\n', ' ')).matches();
    }

    public static Boolean isNo(String s) {
        return firstWordIn(s, NO_WORDS);
    }

    private static Boolean firstWordIn(String s, Set<String> words) {
        if (String.isBlank(s)) {
            return false;
        }
        String t = s.toLowerCase().replaceAll('[^\\p{L}\\p{M}\\s]', ' ').normalizeSpace();
        return String.isNotBlank(t) && words.contains(t.split(' ')[0]);
    }

    // ------------------------------------------------------------------ Helpers
    /** The question the customer should answer next, given where the journey is. */
    /**
     * What the journey is waiting for next; the agent routes on this rather than guessing from the text.
     * menu, identity, otp, loan_confirm, employment, company, income, purpose, amount, offer_decision,
     * callback, feedback_csat, feedback_resolution, feedback_comment, done, handoff; apply_offer when no
     * pre-approved offer was found. New-loan journeys: see LoanSevaNewLoan.awaiting.
     */
    public static String awaiting(Loan_Journey__c j) {
        if (j == null) {
            return 'menu';
        }
        if (j.Status__c == LoanSevaJourneyService.STATUS_COMPLETED) {
            return 'done';
        }
        if (j.Status__c == LoanSevaJourneyService.STATUS_EXITED) {
            return 'handoff';
        }
        if (LoanSevaJourneyService.isNewLoan(j)) {
            return LoanSevaNewLoan.awaiting(j);
        }
        if (j.Existing_Loan__c == null) {
            return j.Stage__c != 'Verify' ? 'menu' : j.Apply_Offered__c == true ? 'apply_offer' : 'identity';
        }
        if (!j.OTP_Verified__c) {
            return 'otp';
        }
        if (!j.Loan_Confirmed__c) {
            return 'loan_confirm';
        }
        String field = pendingField(j);
        if (field != null) {
            return field;
        }
        if (!j.Offer_Accepted__c) {
            return 'offer_decision';
        }
        if (j.Callback_DateTime__c == null) {
            return 'callback';
        }
        Integer step = j.Feedback_Step__c == null ? 0 : Integer.valueOf(j.Feedback_Step__c);
        if (step == 1) {
            return 'feedback_csat';
        }
        if (step == 2) {
            return 'feedback_resolution';
        }
        if (step == 3) {
            return 'feedback_comment';
        }
        return 'done';
    }

    public static String pendingPrompt(Loan_Journey__c j, Boolean quiet) {
        String lang = j.Language__c;
        if (j.Status__c == LoanSevaJourneyService.STATUS_COMPLETED) {
            return quiet ? '' : LoanSevaI18n.msg('FB_Thanks', lang, signOffTokens(j));
        }
        if (LoanSevaJourneyService.isNewLoan(j)) {
            return LoanSevaNewLoan.pendingPrompt(j, quiet);
        }
        if (j.Existing_Loan__c == null) {
            Boolean applyOffered = j.Apply_Offered__c == true && j.Stage__c == 'Verify';
            return quiet ? '' : LoanSevaI18n.msg(applyOffered ? 'NL_Apply_Reprompt' : 'Verify_Prompt', lang);
        }
        if (!j.OTP_Verified__c) {
            return LoanSevaI18n.msg('OTP_Reprompt', lang);
        }
        if (!j.Loan_Confirmed__c) {
            return LoanSevaI18n.msg('Loan_Confirm_Reprompt', lang);
        }
        String field = pendingField(j);
        if (field != null) {
            return question(j, field);
        }
        if (!j.Offer_Accepted__c) {
            // Referred to an RM: there is no offer to accept, only a different amount or tenure to try
            return LoanSevaI18n.msg(j.Offer_Amount__c == null && j.Offer_Presented_At__c != null ? 'Refer_Reprompt' : 'Offer_Reprompt', lang);
        }
        if (j.Callback_DateTime__c == null) {
            return LoanSevaI18n.msg('Callback_Options', lang, new Map<String, Object>{ 'slots' => callbackSlots(j) });
        }
        Integer step = j.Feedback_Step__c == null ? 0 : Integer.valueOf(j.Feedback_Step__c);
        if (step >= 1 && step <= 3) {
            return LoanSevaI18n.msg('FB_Q' + step, lang);
        }
        return '';
    }

    public static Integer choiceNumber(String s) {
        if (String.isBlank(s)) {
            return null;
        }
        String t = s.trim()
            .replace('1️⃣', '1').replace('2️⃣', '2').replace('3️⃣', '3').replace('4️⃣', '4').replace('5️⃣', '5').replace('6️⃣', '6')
            .replace('१', '1').replace('२', '2').replace('३', '3').replace('४', '4').replace('५', '5').replace('६', '6');
        // a single digit not immediately followed by another digit or letter: "2", "2.", "2 Mostly", "4 😊"
        Matcher m = Pattern.compile('^\\s*(?:option\\s*)?([1-9])(?![0-9a-z]).*$').matcher(t.toLowerCase());
        return m.matches() ? Integer.valueOf(m.group(1)) : null;
    }

    /** Parses "5L", "5 lakh", "2.5 lakhs", "500000", "₹5,00,000", "80k", "1.2 cr". */
    public static Decimal parseAmount(String s) {
        if (String.isBlank(s)) {
            return null;
        }
        String t = s.toLowerCase().replace(',', '').replace('₹', '').replace('rs.', '').replace('rs', '').replace('inr', '')
            .replace('लाख', 'lakh').replace('हजार', 'k').replace('हज़ार', 'k').replace('करोड़', 'cr');
        Matcher m = Pattern.compile('([0-9]+(?:\\.[0-9]+)?)\\s*(lakhs|lakh|lacs|lac|l|k|thousand|crore|cr)?').matcher(t);
        if (!m.find()) {
            return null;
        }
        Decimal value = Decimal.valueOf(m.group(1));
        String unit = m.group(2);
        if (unit == null) {
            return value >= 1000 ? value : null;
        }
        if (unit.startsWith('l')) {
            return value * 100000;
        }
        if (unit == 'k' || unit == 'thousand') {
            return value * 1000;
        }
        return value * 10000000;
    }

    public static Integer parseTenure(String s) {
        if (String.isBlank(s)) {
            return null;
        }
        Matcher m = Pattern.compile('([0-9]+)\\s*(year|years|yr|yrs|y|साल|वर्ष)?').matcher(s.toLowerCase());
        if (!m.find()) {
            return null;
        }
        Integer n = Integer.valueOf(m.group(1));
        Integer months = m.group(2) != null || n <= 5 ? n * 12 : n;
        return LoanSevaConfig.tenureOptions().contains(months) ? months : null;
    }

    public static Boolean namesMatch(String given, Contact c) {
        String g = given.toLowerCase();
        for (String part : new List<String>{ c.FirstName, c.LastName }) {
            if (String.isNotBlank(part) && part.length() >= 2 && g.contains(part.toLowerCase())) {
                return true;
            }
        }
        return false;
    }

    public static String maskMobile(String mobile10) {
        return mobile10 == null ? '' : '+91 XXXXXX' + mobile10.right(4);
    }

    public static String numberEmoji(Integer n) {
        List<String> e = new List<String>{ '0️⃣', '1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣', '6️⃣', '7️⃣', '8️⃣', '9️⃣' };
        return n >= 0 && n < e.size() ? e[n] : String.valueOf(n);
    }

    /** Re-asks the pending question; persists any options it generated (amounts, callback slots). */
    public static Result promptAndSave(Loan_Journey__c j) {
        String prompt = pendingPrompt(j, false);
        update j;
        return result(j, prompt);
    }

    public static Result result(Loan_Journey__c j, String message) {
        Result r = new Result();
        r.journey = j;
        r.message = message;
        return r;
    }
}
