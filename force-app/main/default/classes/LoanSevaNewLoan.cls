/**
 * New Personal Loan application, for customers without a pre-approved Top-Up offer:
 * verify (name, mobile, OTP) -> 10 questions (KYC, income, loan need) -> indicative offer ->
 * (an existing customer's answers on file are filled in after the OTP, so only the rest are asked) ->
 * documents on WhatsApp (PAN, bank statement, salary slips; each skippable) -> review and consent ->
 * submit (reference number, RM Task, mock underwriting). The RM then approves or rejects, and an
 * approval creates the loan account (LoanSevaDecisionService).
 * LoanSevaEngine routes here whenever Journey_Type__c is New Loan; the shared steps (OTP, offer, feedback) stay there.
 */
public with sharing class LoanSevaNewLoan {
    public static final List<String> FIELDS = new List<String>{
        'dob', 'pan', 'email', 'pincode', 'employment', 'company', 'income', 'obligations', 'purpose', 'amount'
    };
    /** Typed answers (not option lists): validated here, and an invalid one gets NL_Invalid rather than "pick an option". */
    public static final Set<String> FREE_TEXT = new Set<String>{ 'dob', 'pan', 'email', 'pincode', 'income', 'obligations', 'amount' };

    public static final Integer DOC_PAN = 1;
    public static final Integer DOC_BANK = 2;
    public static final Integer DOC_SALARY = 3;
    public static final Integer DOC_REVIEW = 4;
    public static final Map<Integer, String> DOC_TYPES = new Map<Integer, String>{
        DOC_PAN => 'PAN Card', DOC_BANK => 'Bank Statement', DOC_SALARY => 'Salary Slips'
    };
    private static final Map<Integer, String> DOC_PROMPTS = new Map<Integer, String>{
        DOC_PAN => 'NL_Doc_Pan', DOC_BANK => 'NL_Doc_Bank', DOC_SALARY => 'NL_Doc_Salary'
    };

    public static final Pattern PAN_FORMAT = Pattern.compile('[A-Z]{5}[0-9]{4}[A-Z]');
    private static final Pattern EMAIL_FORMAT = Pattern.compile('[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}');
    private static final List<String> MONTHS = new List<String>{ 'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec' };
    private static final Map<String, String> PIN_CITIES = new Map<String, String>{
        '110' => 'Delhi', '400' => 'Mumbai', '411' => 'Pune', '560' => 'Bengaluru', '600' => 'Chennai', '500' => 'Hyderabad',
        '700' => 'Kolkata', '380' => 'Ahmedabad', '302' => 'Jaipur', '226' => 'Lucknow', '440' => 'Nagpur', '122' => 'Gurugram', '201' => 'Noida'
    };
    private static final Set<String> SKIP_WORDS = new Set<String>{
        'skip', 'later', 'baad', 'next', 'no', 'nahi', 'बाद', 'छोड़ें', 'छोड़ो', 'स्किप', 'वगळा', 'नंतर', 'नाही', 'नहीं'
    };
    private static final Set<String> NONE_WORDS = new Set<String>{
        'none', 'nil', 'no', 'nothing', 'na', 'zero', 'nahi', 'कोई', 'नहीं', 'शून्य', 'नाही', 'काही'
    };
    /** Reply to the on-file summary that re-asks the prefilled questions. */
    private static final Set<String> CHANGE_WORDS = new Set<String>{
        'change', 'update', 'edit', 'badlo', 'badalna', 'बदलें', 'बदलना', 'बदला', 'बदल', 'अपडेट'
    };
    /** Questions that can be answered from data on file; purpose and amount are always asked for each application. */
    private static final List<String> ON_FILE = new List<String>{ 'dob', 'pan', 'email', 'pincode', 'employment', 'company', 'income', 'obligations' };

    // ------------------------------------------------------------------ Start and verify
    /** Switches the journey to a new-loan application and asks for (or, if already given, verifies) name and mobile. */
    public static LoanSevaEngine.Result start(Loan_Journey__c j) {
        j.Journey_Type__c = LoanSevaJourneyService.TYPE_NEW_LOAN;
        j.Apply_Offered__c = false;
        j.Menu_Pending__c = false;
        j.Question_Pending__c = false;
        // The loan need is asked afresh: a Top-Up answer (or an earlier application's) doesn't carry over.
        j.Purpose__c = null;
        j.Desired_Amount__c = null;
        LoanSevaJourneyService.advance(j, 'Verify');
        String intro = LoanSevaI18n.msg('NL_Intro', j.Language__c);
        if (j.OTP_Verified__c) {
            // Already verified in this chat (a Top-Up customer choosing a new loan): no second OTP.
            LoanSevaEngine.Result r = verified(j);
            r.message = intro + '\n\n' + r.message;
            return r;
        }
        if (String.isNotBlank(j.Customer_Name__c) && j.Mobile__c != null) {
            return sendOtp(j, intro, j.Mobile__c);
        }
        update j;
        return LoanSevaEngine.result(j, intro + '\n\n' + LoanSevaI18n.msg('NL_Verify_Prompt', j.Language__c));
    }

    /** Name and mobile for a new applicant. There is no record to match the name against, so any real name is accepted. */
    public static LoanSevaEngine.Result verify(Loan_Journey__c j, String customerName, String mobile) {
        if (j.Status__c == LoanSevaJourneyService.STATUS_EXITED && !j.OTP_Verified__c) {
            return LoanSevaEngine.result(j, LoanSevaI18n.msg('OTP_Locked', j.Language__c));
        }
        String mobile10 = LoanSevaJourneyService.normalizeMobile(mobile);
        if (mobile10 == null) {
            mobile10 = j.Mobile__c;
        }
        String name = customerName == null ? '' : customerName.normalizeSpace();
        if (name.replaceAll('[^\\p{L}]', '').length() < 2 || mobile10 == null) {
            LoanSevaJourneyService.advance(j, 'Verify');
            update j;
            LoanSevaEngine.Result r = LoanSevaEngine.result(j, LoanSevaI18n.msg('NL_Verify_Prompt', j.Language__c));
            r.success = false;
            return r;
        }
        j.Customer_Name__c = name.abbreviate(120);
        if (j.Mobile__c == null) {
            j.Mobile__c = mobile10;
        }
        if (j.Contact__c == null) {
            Contact c = LoanSevaJourneyService.findContact(mobile10);
            j.Contact__c = c == null ? null : c.Id;
        }
        return sendOtp(j, null, mobile10);
    }

    private static LoanSevaEngine.Result sendOtp(Loan_Journey__c j, String prefix, String mobile10) {
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        j.OTP_Attempts__c = 0;
        LoanSevaJourneyService.advance(j, 'Verify');
        update j;
        Loan_Journey__c fresh = LoanSevaJourneyService.byId(j.Id);
        String otp = LoanSevaI18n.msg(cfg.Demo_Mode__c ? 'OTP_Sent_Demo' : 'OTP_Sent', j.Language__c, new Map<String, Object>{
            'name' => LoanSevaJourneyService.firstName(fresh),
            'mobile' => LoanSevaEngine.maskMobile(mobile10),
            'otp' => cfg.Demo_OTP__c
        });
        return LoanSevaEngine.result(fresh, String.isBlank(prefix) ? otp : prefix + '\n\n' + otp);
    }

    /**
     * OTP accepted: straight into the questions (there is no existing loan to confirm). An existing customer's
     * details on file are filled in first and shown back once, so only the missing questions are asked.
     */
    public static LoanSevaEngine.Result verified(Loan_Journey__c j) {
        j.Loan_Confirmed__c = true;
        LoanSevaJourneyService.advance(j, 'Personalise');
        prefill(j);
        List<String> onFile = String.isBlank(j.Prefilled_Fields__c) ? new List<String>() : j.Prefilled_Fields__c.split(';');
        Map<String, Object> params = new Map<String, Object>{
            'name' => LoanSevaJourneyService.firstName(j),
            'details' => onFileSummary(j, onFile),
            'count' => FIELDS.size() - onFile.size()
        };
        String message = LoanSevaI18n.msg(onFile.isEmpty() ? 'NL_Verified' : 'NL_Prefilled', j.Language__c, params)
            + '\n\n' + question(j, pendingField(j));
        update j;
        return LoanSevaEngine.result(j, message);
    }

    // ------------------------------------------------------------------ Existing customers: details on file
    /**
     * Fills blank KYC answers from what is already known about this customer, most reliable first: earlier
     * applications (checked, and corrected by the RM if needed), earlier journeys, the Contact, and the EMIs on
     * their active Kotak loans. Every question answered before the first one is asked is recorded in
     * Prefilled_Fields__c, so numbering counts only the questions actually asked.
     */
    @TestVisible
    private static void prefill(Loan_Journey__c j) {
        if (j.Contact__c == null && j.Mobile__c != null) {
            Contact c = LoanSevaJourneyService.findContact(j.Mobile__c);
            j.Contact__c = c == null ? null : c.Id;
        }
        Id contactId = j.Contact__c;
        // Sets without nulls: "Contact__c = null" would match every record with no customer.
        Set<Id> contactIds = new Set<Id>();
        Set<String> mobiles = new Set<String>();
        if (contactId != null) {
            contactIds.add(contactId);
        }
        if (j.Mobile__c != null) {
            mobiles.add(j.Mobile__c);
        }
        if (!contactIds.isEmpty() || !mobiles.isEmpty()) {
            Id appId = j.Loan_Application__c;
            Id journeyId = j.Id;
            for (Loan_Application__c a : [
                SELECT Date_Of_Birth__c, PAN__c, Email__c, City__c, PIN_Code__c, Monthly_Income__c, Existing_EMIs__c
                FROM Loan_Application__c
                WHERE (Contact__c IN :contactIds OR Mobile__c IN :mobiles) AND Id != :appId AND Submitted_At__c != null
                ORDER BY Submitted_At__c DESC LIMIT 5
            ]) {
                fillFrom(j, a.Date_Of_Birth__c, a.PAN__c, a.Email__c, a.City__c, a.PIN_Code__c, a.Monthly_Income__c, a.Existing_EMIs__c);
            }
            for (Loan_Journey__c p : [
                SELECT Date_Of_Birth__c, PAN__c, Email__c, City__c, PIN_Code__c, Monthly_Income__c, Existing_EMIs__c,
                    Employment_Type__c, Company_Name__c
                FROM Loan_Journey__c
                WHERE (Contact__c IN :contactIds OR Mobile__c IN :mobiles) AND Id != :journeyId
                ORDER BY CreatedDate DESC LIMIT 10
            ]) {
                fillFrom(j, p.Date_Of_Birth__c, p.PAN__c, p.Email__c, p.City__c, p.PIN_Code__c, p.Monthly_Income__c, p.Existing_EMIs__c);
                if (String.isBlank(j.Employment_Type__c) && String.isNotBlank(p.Employment_Type__c)) {
                    j.Employment_Type__c = p.Employment_Type__c;
                    j.Company_Name__c = String.isBlank(j.Company_Name__c) ? p.Company_Name__c : j.Company_Name__c;
                }
            }
        }
        if (contactId != null) {
            for (Contact c : [SELECT Email, Birthdate, MailingCity, MailingPostalCode FROM Contact WHERE Id = :contactId]) {
                fillFrom(j, c.Birthdate, null, c.Email, c.MailingCity, c.MailingPostalCode, null, null);
            }
            if (j.Existing_EMIs__c == null) {
                AggregateResult[] emis = [
                    SELECT SUM(Current_EMI__c) total, COUNT(Id) loans FROM Existing_Loan__c
                    WHERE Contact__c = :contactId AND Status__c = 'Active'
                ];
                if ((Integer) emis[0].get('loans') > 0) {
                    Decimal total = (Decimal) emis[0].get('total');
                    j.Existing_EMIs__c = total == null ? 0 : total;
                }
            }
        }
        List<String> onFile = new List<String>();
        for (String field : ON_FILE) {
            if (isAnswered(j, field)) {
                onFile.add(field);
            }
        }
        j.Prefilled_Fields__c = onFile.isEmpty() ? null : String.join(onFile, ';');
    }

    /** Copies each value only where the journey has none yet, and only if it would pass the question's own validation. */
    private static void fillFrom(Loan_Journey__c j, Date dob, String pan, String email, String city, String pin, Decimal income, Decimal emis) {
        if (j.Date_Of_Birth__c == null && dob != null) {
            Integer age = ageOn(dob, LoanSevaI18n.todayIst());
            j.Date_Of_Birth__c = age >= 18 && age <= 80 ? dob : null;
        }
        if (String.isBlank(j.PAN__c) && String.isNotBlank(pan) && PAN_FORMAT.matcher(pan).matches()) {
            j.PAN__c = pan;
        }
        if (String.isBlank(j.Email__c) && String.isNotBlank(email) && EMAIL_FORMAT.matcher(email).matches()) {
            j.Email__c = email.toLowerCase();
        }
        if (String.isBlank(j.PIN_Code__c) && String.isNotBlank(pin) && Pattern.matches('[1-9][0-9]{5}', pin)) {
            j.PIN_Code__c = pin;
            j.City__c = String.isNotBlank(city) ? city : PIN_CITIES.get(pin.left(3));
        }
        if (j.Monthly_Income__c == null && income != null && income >= 1000) {
            setIncome(j, income);
        }
        if (j.Existing_EMIs__c == null && emis != null && emis >= 0) {
            j.Existing_EMIs__c = emis;
        }
    }

    /** One line per answer on file, in the style of the review card. PAN is masked. */
    private static String onFileSummary(Loan_Journey__c j, List<String> onFile) {
        String lang = j.Language__c;
        String perMonth = '/' + LoanSevaI18n.pick('month', 'माह', 'महिना', lang);
        List<String> lines = new List<String>();
        if (onFile.contains('dob')) {
            lines.add('🎂 ' + formatDate(j.Date_Of_Birth__c));
        }
        if (onFile.contains('pan')) {
            lines.add('🪪 PAN ' + maskPan(j.PAN__c));
        }
        if (onFile.contains('email')) {
            lines.add('📧 ' + j.Email__c);
        }
        if (onFile.contains('pincode')) {
            lines.add('📍 ' + ((j.City__c == null ? '' : j.City__c) + ' ' + j.PIN_Code__c).trim());
        }
        if (onFile.contains('employment') || onFile.contains('company')) {
            List<String> work = new List<String>();
            for (String part : new List<String>{ onFile.contains('employment') ? j.Employment_Type__c : null, onFile.contains('company') ? j.Company_Name__c : null }) {
                if (String.isNotBlank(part)) {
                    work.add(part);
                }
            }
            lines.add('💼 ' + String.join(work, ' @ '));
        }
        if (onFile.contains('income')) {
            lines.add('💵 ' + LoanSevaI18n.pick('Income', 'आय', 'उत्पन्न', lang) + ' ' + LoanSevaI18n.inr(j.Monthly_Income__c) + perMonth);
        }
        if (onFile.contains('obligations')) {
            lines.add('🧾 EMI ' + LoanSevaI18n.inr(j.Existing_EMIs__c) + perMonth);
        }
        return '> ' + String.join(lines, '\n> ');
    }

    /** "Change" after the on-file summary: true if there are prefilled answers to re-ask. */
    public static Boolean wantsChange(Loan_Journey__c j, String text) {
        String t = text == null ? '' : text.toLowerCase().replaceAll('[^\\p{L}\\p{M}\\s]', ' ').normalizeSpace();
        return String.isNotBlank(j.Prefilled_Fields__c) && String.isNotBlank(t) && t.split(' ').size() <= 3
            && CHANGE_WORDS.contains(t.split(' ')[0]);
    }

    /** Clears the prefilled answers so each is asked again, starting with the first. */
    public static LoanSevaEngine.Result redoPrefilled(Loan_Journey__c j) {
        for (String field : j.Prefilled_Fields__c.split(';')) {
            clearAnswer(j, field);
        }
        j.Prefilled_Fields__c = null;
        LoanSevaJourneyService.touch(j);
        update j;
        return LoanSevaEngine.result(j, LoanSevaI18n.msg('NL_Change', j.Language__c) + '\n\n' + question(j, pendingField(j)));
    }

    private static void clearAnswer(Loan_Journey__c j, String field) {
        if (field == 'dob') {
            j.Date_Of_Birth__c = null;
        } else if (field == 'pan') {
            j.PAN__c = null;
        } else if (field == 'email') {
            j.Email__c = null;
        } else if (field == 'pincode') {
            j.PIN_Code__c = null;
            j.City__c = null;
        } else if (field == 'employment') {
            j.Employment_Type__c = null;
        } else if (field == 'company') {
            j.Company_Name__c = null;
        } else if (field == 'income') {
            j.Monthly_Income__c = null;
            j.Income_Bucket__c = null;
        } else if (field == 'obligations') {
            j.Existing_EMIs__c = null;
        }
    }

    // ------------------------------------------------------------------ Questions
    public static String pendingField(Loan_Journey__c j) {
        for (String field : FIELDS) {
            if (!isAnswered(j, field)) {
                return field;
            }
        }
        return null;
    }

    private static Boolean isAnswered(Loan_Journey__c j, String field) {
        List<Object> values = new List<Object>{
            j.Date_Of_Birth__c, j.PAN__c, j.Email__c, j.PIN_Code__c, j.Employment_Type__c, j.Company_Name__c,
            j.Monthly_Income__c, j.Existing_EMIs__c, j.Purpose__c, j.Desired_Amount__c
        };
        Object value = values[FIELDS.indexOf(field)];
        return value != null && String.isNotBlank(String.valueOf(value));
    }

    /**
     * The question for a field, numbered n/total over the questions actually asked (10 for a new customer,
     * fewer when answers were on file). The shared Top-Up copy is numbered n/5, so that prefix is replaced.
     */
    public static String question(Loan_Journey__c j, String field) {
        if (field == null) {
            return '';
        }
        String lang = j.Language__c;
        String text;
        if (field == 'employment') {
            text = LoanSevaI18n.msg('Q_Employment', lang);
        } else if (field == 'company') {
            text = LoanSevaI18n.msg(j.Employment_Type__c == 'Self-employed' ? 'Q_Business' : 'Q_Company', lang);
        } else if (field == 'purpose') {
            text = LoanSevaI18n.msg('Q_Purpose', lang);
        } else if (field == 'amount') {
            text = LoanSevaI18n.msg('NL_Q_Amount', lang, new Map<String, Object>{
                'min' => LoanSevaI18n.inr(LoanSevaConfig.get().New_Loan_Min_Amount__c),
                'max' => LoanSevaI18n.inr(maxAmount(j))
            });
        } else {
            Map<String, String> keys = new Map<String, String>{
                'dob' => 'NL_Q_Dob', 'pan' => 'NL_Q_Pan', 'email' => 'NL_Q_Email', 'pincode' => 'NL_Q_Pincode',
                'income' => 'NL_Q_Income', 'obligations' => 'NL_Q_Obligations'
            };
            text = LoanSevaI18n.msg(keys.get(field), lang);
        }
        List<String> asked = new List<String>();
        Set<String> onFile = String.isBlank(j.Prefilled_Fields__c) ? new Set<String>() : new Set<String>(j.Prefilled_Fields__c.split(';'));
        for (String f : FIELDS) {
            if (!onFile.contains(f) || f == field) {
                asked.add(f);
            }
        }
        return '*' + (asked.indexOf(field) + 1) + '/' + asked.size() + '* — ' + text.replaceFirst('^\\*[0-9]+/[0-9]+\\* — ', '');
    }

    /** Upper bound shown with the amount question: the product maximum, or the income multiple if lower. */
    public static Decimal maxAmount(Loan_Journey__c j) {
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        Decimal max = cfg.New_Loan_Max_Amount__c;
        if (j.Monthly_Income__c != null && j.Monthly_Income__c > 0) {
            max = Math.min(max, LoanSevaEligibilityEngine.roundDown(j.Monthly_Income__c * cfg.New_Loan_Income_Multiple__c, LoanSevaConfig.rounding()));
        }
        return Math.max(max, cfg.New_Loan_Min_Amount__c);
    }

    /** Validates and stores a typed answer (see FREE_TEXT); false if it doesn't parse. */
    public static Boolean applyAnswer(Loan_Journey__c j, String field, String answer) {
        String a = answer == null ? '' : answer.trim();
        if (String.isBlank(a)) {
            return false;
        }
        if (field == 'dob') {
            Date dob = parseDob(a);
            Integer age = dob == null ? null : ageOn(dob, LoanSevaI18n.todayIst());
            if (age == null || age < 18 || age > 80) {
                return false;
            }
            j.Date_Of_Birth__c = dob;
            return true;
        }
        if (field == 'pan') {
            String pan = parsePan(a);
            j.PAN__c = pan;
            return pan != null;
        }
        if (field == 'email') {
            Matcher m = EMAIL_FORMAT.matcher(a);
            if (!m.find()) {
                return false;
            }
            j.Email__c = m.group().toLowerCase();
            return true;
        }
        if (field == 'pincode') {
            Matcher m = Pattern.compile('(?<![0-9])[1-9][0-9]{5}(?![0-9])').matcher(a.replaceAll('(?<=[0-9])\\s(?=[0-9])', ''));
            if (!m.find()) {
                return false;
            }
            j.PIN_Code__c = m.group();
            String city = a.replaceAll('[0-9]', ' ').replaceAll('(?i)\\b(pin|code|pincode|city|is|my|and)\\b', ' ')
                .replaceAll('[^\\p{L}\\p{M}\\s]', ' ').normalizeSpace();
            j.City__c = String.isNotBlank(city) ? titleCase(city).abbreviate(60) : PIN_CITIES.get(j.PIN_Code__c.left(3));
            return true;
        }
        if (field == 'income') {
            Decimal income = LoanSevaEngine.parseAmount(a);
            if (income == null || income < 1000) {
                return false;
            }
            setIncome(j, income);
            return true;
        }
        if (field == 'obligations') {
            String l = a.toLowerCase().replaceAll('[^\\p{L}\\p{M}0-9\\s]', ' ').normalizeSpace();
            Decimal emis = LoanSevaEngine.parseAmount(a);
            if (emis == null && Pattern.matches('[0-9]+', l)) {
                emis = Decimal.valueOf(l);
            }
            if (emis == null && String.isNotBlank(l) && NONE_WORDS.contains(l.split(' ')[0])) {
                emis = 0;
            }
            if (emis == null || emis < 0) {
                return false;
            }
            j.Existing_EMIs__c = emis;
            return true;
        }
        if (field == 'amount') {
            Decimal amount = LoanSevaEngine.parseAmount(a);
            if (amount == null || amount < LoanSevaConfig.get().New_Loan_Min_Amount__c) {
                return false;
            }
            j.Desired_Amount__c = amount;
            return true;
        }
        return false;
    }

    private static void setIncome(Loan_Journey__c j, Decimal income) {
        j.Monthly_Income__c = income;
        j.Income_Bucket__c = income < 50000 ? 'Below 50K' : income < 100000 ? '50K-1L' : income < 200000 ? '1L-2L' : '2L+';
    }

    // ------------------------------------------------------------------ State
    /**
     * New-loan steps, in order: identity, otp, dob, pan, email, pincode, employment, company, income, obligations,
     * purpose, amount, offer_decision, doc_pan, doc_bank, doc_salary, consent, feedback_csat, feedback_resolution,
     * feedback_comment, done.
     */
    public static String awaiting(Loan_Journey__c j) {
        if (!j.OTP_Verified__c) {
            return String.isBlank(j.Customer_Name__c) ? 'identity' : 'otp';
        }
        String field = pendingField(j);
        if (field != null) {
            return field;
        }
        if (!j.Offer_Accepted__c) {
            return 'offer_decision';
        }
        if (j.Submitted_At__c == null) {
            Integer step = docStep(j);
            return step == DOC_PAN ? 'doc_pan' : step == DOC_BANK ? 'doc_bank' : step == DOC_SALARY ? 'doc_salary' : 'consent';
        }
        Integer fb = j.Feedback_Step__c == null ? 0 : Integer.valueOf(j.Feedback_Step__c);
        return fb == 1 ? 'feedback_csat' : fb == 2 ? 'feedback_resolution' : fb == 3 ? 'feedback_comment' : 'done';
    }

    public static String pendingPrompt(Loan_Journey__c j, Boolean quiet) {
        String lang = j.Language__c;
        String state = awaiting(j);
        if (state == 'identity') {
            return quiet ? '' : LoanSevaI18n.msg('NL_Verify_Prompt', lang);
        }
        if (state == 'otp') {
            return LoanSevaI18n.msg('OTP_Reprompt', lang);
        }
        if (FIELDS.contains(state)) {
            return question(j, state);
        }
        if (state == 'offer_decision') {
            return LoanSevaI18n.msg(j.Offer_Amount__c == null && j.Offer_Presented_At__c != null ? 'Refer_Reprompt' : 'Offer_Reprompt', lang);
        }
        if (state.startsWith('doc_')) {
            return LoanSevaI18n.msg(DOC_PROMPTS.get(docStep(j)), lang);
        }
        if (state == 'consent') {
            return review(j);
        }
        if (state.startsWith('feedback_')) {
            return LoanSevaI18n.msg('FB_Q' + Integer.valueOf(j.Feedback_Step__c), lang);
        }
        return '';
    }

    // ------------------------------------------------------------------ Offer accepted -> documents
    public static LoanSevaEngine.Result accepted(Loan_Journey__c j) {
        j.Offer_Accepted__c = true;
        j.Accepted_At__c = Datetime.now();
        j.Doc_Step__c = DOC_PAN;
        LoanSevaJourneyService.advance(j, 'Documents');
        update new Loan_Application__c(Id = j.Loan_Application__c, Status__c = 'Offer Accepted');
        update j;
        return LoanSevaEngine.result(j, LoanSevaI18n.msg('NL_Offer_Accepted', j.Language__c) + '\n\n' + LoanSevaI18n.msg('NL_Doc_Pan', j.Language__c));
    }

    public static Integer docStep(Loan_Journey__c j) {
        return j.Doc_Step__c == null ? DOC_PAN : Integer.valueOf(j.Doc_Step__c);
    }

    /**
     * Any reply on a document step: "Skip" defers it; anything else ("Done", or the text sent with a photo)
     * picks up the files shared on WhatsApp since the last step.
     */
    public static LoanSevaEngine.Result document(Loan_Journey__c j, String text) {
        String lang = j.Language__c;
        Integer step = docStep(j);
        String docType = DOC_TYPES.get(step);
        String reply;
        if (isSkip(text)) {
            List<String> skipped = String.isBlank(j.Docs_Skipped__c) ? new List<String>() : j.Docs_Skipped__c.split(';');
            if (!skipped.contains(docType)) {
                skipped.add(docType);
            }
            j.Docs_Skipped__c = String.join(skipped, ';').abbreviate(255);
            reply = LoanSevaI18n.msg('NL_Doc_Skipped', lang);
        } else {
            Integer received = LoanSevaDocumentService.collect(j, docType);
            if (received == 0) {
                LoanSevaJourneyService.touch(j);
                update j;
                LoanSevaEngine.Result r = LoanSevaEngine.result(j, LoanSevaI18n.msg('NL_Doc_Not_Received', lang));
                r.success = false;
                return r;
            }
            reply = LoanSevaI18n.msg('NL_Doc_Received', lang, new Map<String, Object>{ 'count' => received });
        }
        Integer next = step + 1;
        if (next == DOC_SALARY && j.Employment_Type__c != 'Salaried') {
            next = DOC_REVIEW;
        }
        j.Doc_Step__c = next;
        LoanSevaJourneyService.touch(j);
        update j;
        return LoanSevaEngine.result(j, reply + '\n\n' + (next >= DOC_REVIEW ? review(j) : LoanSevaI18n.msg(DOC_PROMPTS.get(next), lang)));
    }

    private static Boolean isSkip(String text) {
        String t = text == null ? '' : text.toLowerCase().replaceAll('[^\\p{L}\\p{M}\\s]', ' ').normalizeSpace();
        return String.isNotBlank(t) && SKIP_WORDS.contains(t.split(' ')[0]);
    }

    // ------------------------------------------------------------------ Review, consent, submit
    /** Summary of everything collected; PAN is masked to the last 5 characters. */
    public static String review(Loan_Journey__c j) {
        return LoanSevaI18n.msg('NL_Review', j.Language__c, new Map<String, Object>{
            'name' => j.Customer_Name__c,
            'dob' => formatDate(j.Date_Of_Birth__c),
            'pan' => maskPan(j.PAN__c),
            'email' => j.Email__c,
            'city' => ((j.City__c == null ? '' : j.City__c) + ' ' + (j.PIN_Code__c == null ? '' : j.PIN_Code__c)).trim(),
            'employment' => j.Employment_Type__c + (String.isNotBlank(j.Company_Name__c) ? ' @ ' + j.Company_Name__c : ''),
            'income' => LoanSevaI18n.inr(j.Monthly_Income__c),
            'emis' => LoanSevaI18n.inr(j.Existing_EMIs__c == null ? 0 : j.Existing_EMIs__c),
            'amount' => LoanSevaI18n.inr(j.Offer_Amount__c),
            'tenure' => j.Offer_Tenure_Months__c == null ? '' : String.valueOf(j.Offer_Tenure_Months__c.intValue()),
            'emi' => LoanSevaI18n.inr(j.Offer_EMI__c),
            'docs' => docsLine(j)
        });
    }

    private static String formatDate(Date d) {
        return d == null ? '' : Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0)).format('dd/MM/yyyy');
    }

    public static String maskPan(String pan) {
        return String.isBlank(pan) ? '' : 'XXXXX' + pan.right(5);
    }

    private static String docsLine(Loan_Journey__c j) {
        String lang = j.Language__c;
        Set<String> received = new Set<String>();
        for (Loan_Document__c d : [SELECT Document_Type__c FROM Loan_Document__c WHERE Loan_Application__c = :j.Loan_Application__c]) {
            received.add(d.Document_Type__c);
        }
        Map<String, String> labels = new Map<String, String>{
            'PAN Card' => LoanSevaI18n.pick('PAN card', 'PAN कार्ड', 'PAN कार्ड', lang),
            'Bank Statement' => LoanSevaI18n.pick('Bank statement', 'बैंक स्टेटमेंट', 'बँक स्टेटमेंट', lang),
            'Salary Slips' => LoanSevaI18n.pick('Salary slips', 'सैलरी स्लिप', 'पगार स्लिप', lang)
        };
        String later = LoanSevaI18n.pick('⏳ later', '⏳ बाद में', '⏳ नंतर', lang);
        List<String> parts = new List<String>();
        for (String docType : labels.keySet()) {
            if (docType == 'Salary Slips' && j.Employment_Type__c != 'Salaried') {
                continue;
            }
            parts.add(labels.get(docType) + ' ' + (received.contains(docType) ? '✅' : later));
        }
        return String.join(parts, ' · ');
    }

    public static LoanSevaEngine.Result consent(Loan_Journey__c j, String text, Integer choice) {
        String l = text == null ? '' : text.toLowerCase();
        if (choice == 1 || LoanSevaEngine.isYes(text) || l.contains('submit') || l.contains('agree')) {
            return submit(j);
        }
        if (choice == 2 || LoanSevaEngine.isNo(text)) {
            return LoanSevaEngine.escalate(j, 'Details wrong at new-loan review');
        }
        return LoanSevaEngine.promptAndSave(j);
    }

    /**
     * Records consent, copies KYC onto the application, assigns the reference number, creates the customer
     * (if new) and the RM Task, and starts the mock underwriting. The loan account is created only on RM approval.
     */
    public static LoanSevaEngine.Result submit(Loan_Journey__c j) {
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        if (j.Contact__c == null) {
            j.Contact__c = createContact(j);
        } else {
            completeContact(j);
        }
        Loan_Application__c app = [SELECT Id, Name FROM Loan_Application__c WHERE Id = :j.Loan_Application__c];
        Datetime now = Datetime.now();
        String ref = LoanSevaEngine.referenceNumber(cfg.New_Loan_Reference_Prefix__c, app.Name);
        app.Contact__c = j.Contact__c;
        app.Application_Type__c = LoanSevaJourneyService.TYPE_NEW_LOAN;
        app.Applicant_Name__c = j.Customer_Name__c;
        app.Mobile__c = j.Mobile__c;
        app.Date_Of_Birth__c = j.Date_Of_Birth__c;
        app.PAN__c = j.PAN__c;
        app.Email__c = j.Email__c;
        app.City__c = j.City__c;
        app.PIN_Code__c = j.PIN_Code__c;
        app.Monthly_Income__c = j.Monthly_Income__c;
        app.Existing_EMIs__c = j.Existing_EMIs__c;
        app.Bureau_Consent__c = true;
        app.Consent_At__c = now;
        app.Submitted_At__c = now;
        app.Reference_Number__c = ref;
        app.Status__c = 'Application Submitted';
        app.Underwriting_Status__c = 'In Progress';
        update app;

        j.Reference_Number__c = ref;
        j.Submitted_At__c = now;
        j.Feedback_Step__c = 1;
        LoanSevaJourneyService.advance(j, 'Feedback');
        Task t = LoanSevaJourneyService.buildRmTask(j, 'New loan application ' + ref + ' - review underwriting and decide',
            LoanSevaJourneyService.rmDescription(j), LoanSevaI18n.todayIst());
        t.WhatId = app.Id;
        insert t;
        j.RM_Followup_Created__c = true;
        update j;
        LoanSevaUnderwriting.start(app.Id);
        return LoanSevaEngine.result(j, LoanSevaI18n.msg('NL_Submitted', j.Language__c, new Map<String, Object>{ 'ref' => ref })
            + '\n\n' + LoanSevaI18n.msg('FB_Q1', j.Language__c));
    }

    private static Id createContact(Loan_Journey__c j) {
        List<String> parts = j.Customer_Name__c.normalizeSpace().split(' ');
        String lastName = parts.remove(parts.size() - 1);
        Contact c = new Contact(
            FirstName = parts.isEmpty() ? null : titleCase(String.join(parts, ' ')),
            LastName = titleCase(lastName),
            MobilePhone = j.Mobile__c,
            Email = j.Email__c,
            Birthdate = j.Date_Of_Birth__c,
            MailingCity = j.City__c,
            MailingPostalCode = j.PIN_Code__c,
            LeadSource = 'LoanSeva WhatsApp'
        );
        for (Account a : [SELECT Id FROM Account WHERE Name = 'LoanSeva Demo Customers' LIMIT 1]) {
            c.AccountId = a.Id;
        }
        insert c;
        return c.Id;
    }

    /** Fills blanks on an existing customer's Contact from the application, so the next one is prefilled. Never overwrites. */
    private static void completeContact(Loan_Journey__c j) {
        Contact c = [SELECT Id, Email, Birthdate, MailingCity, MailingPostalCode FROM Contact WHERE Id = :j.Contact__c];
        Boolean changed = false;
        if (String.isBlank(c.Email) && String.isNotBlank(j.Email__c)) {
            c.Email = j.Email__c;
            changed = true;
        }
        if (c.Birthdate == null && j.Date_Of_Birth__c != null) {
            c.Birthdate = j.Date_Of_Birth__c;
            changed = true;
        }
        if (String.isBlank(c.MailingPostalCode) && String.isNotBlank(j.PIN_Code__c)) {
            c.MailingPostalCode = j.PIN_Code__c;
            c.MailingCity = String.isBlank(c.MailingCity) ? j.City__c : c.MailingCity;
            changed = true;
        }
        if (changed) {
            // Best effort: a validation rule on the customer record must not block the application.
            Database.update(c, false);
        }
    }

    // ------------------------------------------------------------------ Parsers
    /** 15/08/1990, 15-8-1990, 15.08.1990, 15 Aug 1990, 1990-08-15. */
    public static Date parseDob(String s) {
        String t = s == null ? '' : s.toLowerCase().trim();
        Integer d;
        Integer mo;
        Integer y;
        Matcher iso = Pattern.compile('([0-9]{4})[\\-/.]([0-9]{1,2})[\\-/.]([0-9]{1,2})').matcher(t);
        Matcher dmy = Pattern.compile('([0-9]{1,2})(?:st|nd|rd|th)?[\\s/.\\-]+([0-9]{1,2}|[a-z]{3,9})[\\s/.\\-,]+([0-9]{4})').matcher(t);
        if (iso.find()) {
            y = Integer.valueOf(iso.group(1));
            mo = Integer.valueOf(iso.group(2));
            d = Integer.valueOf(iso.group(3));
        } else if (dmy.find()) {
            d = Integer.valueOf(dmy.group(1));
            String m = dmy.group(2);
            mo = m.isNumeric() ? Integer.valueOf(m) : MONTHS.indexOf(m.left(3)) + 1;
            y = Integer.valueOf(dmy.group(3));
        } else {
            return null;
        }
        if (mo < 1 || mo > 12 || y < 1900 || d < 1 || d > Date.daysInMonth(y, mo)) {
            return null;
        }
        return Date.newInstance(y, mo, d);
    }

    public static Integer ageOn(Date dob, Date onDate) {
        Integer years = onDate.year() - dob.year();
        if (onDate.month() < dob.month() || (onDate.month() == dob.month() && onDate.day() < dob.day())) {
            years--;
        }
        return years;
    }

    /** "ABCPE1234F", "my PAN is abcpe1234f", "ABCPE 1234 F". */
    public static String parsePan(String s) {
        String upper = s == null ? '' : s.toUpperCase();
        Matcher m = Pattern.compile('(?<![A-Z0-9])[A-Z]{5}[0-9]{4}[A-Z](?![A-Z0-9])').matcher(upper);
        if (m.find()) {
            return m.group();
        }
        String compact = upper.replaceAll('[^A-Z0-9]', '');
        return PAN_FORMAT.matcher(compact).matches() ? compact : null;
    }

    private static String titleCase(String s) {
        List<String> words = new List<String>();
        for (String w : s.toLowerCase().split(' ')) {
            words.add(w.capitalize());
        }
        return String.join(words, ' ');
    }
}
