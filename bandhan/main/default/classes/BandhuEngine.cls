/**
 * Bandhu: the credit card advisor and application journey, one deterministic state machine for WhatsApp and web.
 * Card_Journey__c.Step__c is what the journey waits for; reply() routes every customer message on it, and returns the
 * copy (Bandhu_Message__mdt) plus the options, which WhatsApp shows numbered and the web shows as buttons.
 *
 *   menu -> consent -> name -> [mobile] -> otp -> spend -> monthly_spend -> fee
 *        -> employment -> income -> company -> pan -> dob -> pincode -> bureau -> aa      (existing customers skip what is on file)
 *        -> choose (recommendation) -> email -> aadhaar -> aadhaar_otp -> vkyc -> review  (KYC: new-to-bank only)
 *        -> done | declined_alt
 * Anytime: a language (EN / HI / BN), Agent / specialist, Menu, Compare, Status, and FAQ questions.
 */
public inherited sharing class BandhuEngine {
    public class CardView {
        @AuraEnabled public String name;
        @AuraEnabled public String tagline;
        @AuraEnabled public String color;
        @AuraEnabled public Integer joiningFee;
        @AuraEnabled public String rewards;
        @AuraEnabled public String lounge;
        @AuraEnabled public String welcome;
        @AuraEnabled public String creditLimit;
        @AuraEnabled public Boolean recommended = false;
        @AuraEnabled public Boolean eligible = false;
        @AuraEnabled public String tierLabel;
        @AuraEnabled public Integer tier;
        @AuraEnabled public Boolean secured = false;
    }

    public class Result {
        @AuraEnabled public Card_Journey__c journey;
        @AuraEnabled public String message;
        @AuraEnabled public List<String> options = new List<String>();
        @AuraEnabled public String step;
        @AuraEnabled public Boolean handoff = false;
        @AuraEnabled public Boolean success = true;
        @AuraEnabled public List<CardView> cards = new List<CardView>();

        /** WhatsApp text: the message, then the options numbered. */
        public String whatsapp() {
            String s = message == null ? '' : message;
            if (!options.isEmpty()) {
                List<String> lines = new List<String>();
                for (Integer i = 0; i < options.size(); i++) {
                    lines.add(emoji(i + 1) + ' ' + options[i]);
                }
                s += '\n\n' + String.join(lines, '\n');
            }
            return s;
        }
    }

    private static final List<String> FOCUS_KEYWORDS = new List<String>{ 'travel|flight', 'international|abroad|foreign', 'dining|food|movie|restaurant',
        'grocer|everyday|daily', 'shopping|online|amazon|flipkart', 'fuel|petrol|diesel' };
    private static final Pattern HUMAN = Pattern.compile('(?i).*\\b(agent|human|specialist|executive|relationship manager|rm|call me|talk to (a |some)?(person|someone|human))\\b.*');
    private static final Pattern MENU = Pattern.compile('(?i)^\\W*(menu|main menu|back|start over|restart)\\W*$');
    private static final Pattern COMPARE = Pattern.compile('(?i).*\\b(compare|all cards|card range|show (me )?(the )?cards)\\b.*');
    private static final Pattern ACTIVATE_CMD = Pattern.compile('(?i)^\\W*(activate( my)?( card)?|card activate)\\W*$');
    private static final Pattern CANCEL_CARD = Pattern.compile('(?i)^\\W*(cancel( my)? card|close( my)? card)\\W*$');
    private static final Pattern WITHDRAW = Pattern.compile('(?i).*\\b(withdraw (my )?consent|delete my data|erase my data)\\b.*');
    private static final Pattern STATUS = Pattern.compile('(?i)^\\W*(status|track|application status)\\W*$');
    private static final Pattern GREETING = Pattern.compile('(?i)^\\W*(hi|hello|hey|hii|namaste|namaskar|start|begin)\\W*$');
    private static final Pattern PAN = Pattern.compile('[A-Z]{5}[0-9]{4}[A-Z]');
    private static final Pattern EMAIL = Pattern.compile('[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}');
    private static final Map<String, String> PIN_CITY = new Map<String, String>{ '700' => 'Kolkata', '110' => 'Delhi', '400' => 'Mumbai',
        '560' => 'Bengaluru', '600' => 'Chennai', '500' => 'Hyderabad', '411' => 'Pune', '781' => 'Guwahati', '751' => 'Bhubaneswar', '800' => 'Patna' };
    private static final Map<String, Decimal> SPEND_BANDS = new Map<String, Decimal>{ '1' => 10000, '2' => 30000, '3' => 75000, '4' => 150000 };
    // personal details first, then income and the Account Aggregator, then the needs in one run, then the soft check:
    // nothing interrupts the needs questions (the company comes from the salary credits, or is asked with the income)
    private static final List<String> PROFILE_STEPS = new List<String>{ 'email', 'dob', 'pincode', 'pan', 'employment', 'income', 'aa', 'company',
        'spend', 'monthly_spend', 'fee', 'bureau' };
    private static final List<String> KYC_STEPS = new List<String>{ 'email', 'aadhaar', 'aadhaar_otp', 'vkyc', 'review' };

    // ------------------------------------------------------------------ entry points
    /**
     * Branch-assisted: the RM starts the journey for an existing customer from the 360 view; the customer gets the pitch
     * on WhatsApp and continues there (consent and OTP are still theirs to give). Branch channel scores higher.
     */
    public static Result startBranch(Contact c, String rmName) {
        Card_Journey__c j = new Card_Journey__c(Contact__c = c.Id, Customer_Type__c = BandhuJourneyService.EXISTING, Channel__c = 'Branch',
            Mobile__c = BandhuI18n.normalizeMobile(c.MobilePhone), Customer_Name__c = c.Name, Language__c = BandhuI18n.EN,
            Status__c = BandhuJourneyService.STATUS_ACTIVE, Step__c = 'consent', Stage__c = 'Start', Last_Activity__c = Datetime.now());
        insert j;
        j = BandhuJourneyService.byId(j.Id);
        Result r = ask(j, 'consent');
        r.message = BandhuI18n.msg('Branch_Pitch', j.Language__c, new Map<String, Object>{
            'name' => ' ' + c.FirstName, 'rm' => rmName }) + '\n\n' + r.message;
        update j;
        r.journey = j;
        return r;
    }

    public static Result start(Card_Journey__c j) {
        String lang = j.Language__c;
        if (j.Contact__c == null && j.Mobile__c != null) {
            Contact c = BandhuJourneyService.findContact(j.Mobile__c);
            if (c != null) {
                j.Contact__c = c.Id;
                j.Customer_Type__c = BandhuJourneyService.EXISTING;
                if (String.isBlank(j.Customer_Name__c)) {
                    j.Customer_Name__c = c.Name;
                }
            }
        }
        if (String.isNotBlank(j.Step__c) && j.Step__c != 'menu' && j.Step__c != 'done' && j.Status__c != BandhuJourneyService.STATUS_EXITED) {
            // a resumed journey picks up where it left off
            BandhuJourneyService.touch(j);
            Result r = prompt(j, j.Step__c);
            r.message = BandhuI18n.msg('Resume', lang, tokens(j)) + '\n\n' + r.message;
            return save(j, r);
        }
        j.Step__c = 'menu';
        j.Status__c = BandhuJourneyService.STATUS_ACTIVE;
        return save(j, welcome(j));
    }

    public static Result reply(Card_Journey__c j, String text) {
        String t = text == null ? '' : text.trim();
        BandhuJourneyService.touch(j);
        if (String.isBlank(j.Step__c)) {
            return start(j);
        }
        // "Hi" is a greeting: the short codes count only in capitals (HI / BN / EN), names in any case
        String lang = t.equals('HI') || t.equals('BN') || t.equals('EN') || (t.length() > 2 && t.length() <= 12) ? BandhuI18n.parseLanguage(t) : null;
        if (lang != null) {
            return setLanguage(j, lang);
        }
        if (HUMAN.matcher(t).matches() && j.Step__c != 'otp' && j.Step__c != 'aadhaar_otp') {
            return handoff(j, 'Asked for a specialist: "' + t.abbreviate(80) + '"');
        }
        if (MENU.matcher(t).matches() || (GREETING.matcher(t).matches() && (j.Step__c == 'done' || j.Step__c == 'menu'))) {
            j.Step__c = 'menu';
            Result r = welcome(j);
            if (MENU.matcher(t).matches()) {
                r.message = BandhuI18n.msg('Menu_Back', j.Language__c) + '\n\n' + r.message;
            }
            return save(j, r);
        }
        if (WITHDRAW.matcher(t).matches()) {
            BandhuCompliance.withdraw(j);
            BandhuLeadService.rmTask(j, 'Bandhu: consent withdrawn - ' + label(j), 'The customer withdrew consent (DPDP). Stop processing and erase per the retention policy.');
            Result r = new Result();
            r.message = BandhuI18n.msg('Consent_Withdrawn', j.Language__c);
            return save(j, r);
        }
        if (ACTIVATE_CMD.matcher(t).matches() || CANCEL_CARD.matcher(t).matches()) {
            Card_Application__c issued = BandhuCompliance.issuedApplication(j);
            Result r = new Result();
            if (issued == null) {
                r.message = BandhuI18n.msg('No_Card_Yet', j.Language__c);
                return save(j, appendPrompt(j, r));
            }
            if (ACTIVATE_CMD.matcher(t).matches()) {
                if (issued.Activated_At__c != null) {
                    r.message = BandhuI18n.msg('Activated', j.Language__c, tokens(j));
                    return save(j, r);
                }
                j.Step__c = 'activate_otp';
                r.step = j.Step__c;
                r.message = BandhuI18n.msg('Q_Activate_OTP', j.Language__c, tokens(j));
                return save(j, r);
            }
            if (!BandhuCompliance.inCoolingOff(issued)) {
                r.message = BandhuI18n.msg('Cancel_Too_Late', j.Language__c, new Map<String, Object>{ 'days' => BandhuCompliance.COOLING_OFF_DAYS });
                return save(j, r);
            }
            j.Step__c = 'cancel_confirm';
            r.step = j.Step__c;
            r.message = BandhuI18n.msg('Q_Cancel', j.Language__c, tokens(j));
            r.options = BandhuI18n.options('Opt_Cancel', j.Language__c, null);
            return save(j, r);
        }
        if (STATUS.matcher(t).matches()) {
            return save(j, appendPrompt(j, status(j)));
        }
        if (COMPARE.matcher(t).matches() && j.Step__c != 'name' && j.Step__c != 'company') {
            return save(j, appendPrompt(j, compare(j)));
        }
        String faq = faqKey(t);
        if (faq != null && j.Step__c != 'name' && j.Step__c != 'company' && j.Step__c != 'question') {
            Result r = new Result();
            r.message = BandhuI18n.msg(faq, j.Language__c);
            return save(j, appendPrompt(j, r));
        }
        return save(j, route(j, t));
    }

    public static Result setLanguage(Card_Journey__c j, String lang) {
        j.Language__c = lang;
        Result r = String.isBlank(j.Step__c) || j.Step__c == 'menu' ? welcome(j) : prompt(j, j.Step__c);
        r.message = BandhuI18n.msg('Language_Set', lang) + '\n\n' + r.message;
        return save(j, r);
    }

    public static Result handoff(Card_Journey__c j, String reason) {
        j.Escalated__c = true;
        Result r = new Result();
        r.message = BandhuI18n.msg('Handoff', j.Language__c);
        r.handoff = true;
        r.step = j.Step__c;
        BandhuLeadService.rmTask(j, 'Bandhu: specialist requested - ' + label(j), reason);
        return save(j, r);
    }

    // ------------------------------------------------------------------ routing
    private static Result route(Card_Journey__c j, String t) {
        String step = j.Step__c;
        Integer choice = choiceNumber(t);
        String lang = j.Language__c;
        if (step == 'menu') {
            if (choice == 1 || t.containsIgnoreCase('find') || t.containsIgnoreCase('apply')) {
                if (j.Consent__c) {
                    return next(j, 'consent');
                }
                return ask(j, 'consent');
            }
            if (choice == 2) {
                Result r = compare(j);
                r.options = BandhuI18n.options('Opt_After_Compare', lang, null);
                j.Step__c = 'after_compare';
                return r;
            }
            if (choice == 3) {
                j.Step__c = 'question';
                Result r = new Result();
                r.message = BandhuI18n.msg('FAQ_Fallback', lang);
                return r;
            }
            if (choice == 4) {
                return handoff(j, 'Menu option: talk to a specialist');
            }
            return invalid(j);
        }
        if (step == 'after_compare' || step == 'not_eligible') {
            if (choice == 1 && step == 'after_compare') {
                return j.Consent__c ? next(j, 'consent') : ask(j, 'consent');
            }
            if (choice == 1 && step == 'not_eligible') {
                return handoff(j, 'Not eligible for a card: wants to talk to a specialist');
            }
            if (choice == 2 && step == 'after_compare') {
                return handoff(j, 'After comparing cards: talk to a specialist');
            }
            j.Step__c = 'menu';
            return welcome(j);
        }
        if (step == 'limit_offer') {
            Boolean yes = choice == 1 || Pattern.matches('(?i).*\\b(yes|accept|ok|haan)\\b.*', t);
            Boolean no = choice == 2 || Pattern.matches('(?i).*\\b(no|not now|nahi)\\b.*', t);
            if (!yes && !no) {
                return invalid(j);
            }
            Card_Application__c a = BandhuPostIssue.respond(j, yes);
            Result r = new Result();
            r.step = j.Step__c;
            r.message = BandhuI18n.msg(yes ? 'Limit_Accepted' : 'Limit_Declined', lang, new Map<String, Object>{
                'card' => a.Card_Product__c, 'limit' => BandhuI18n.inr(a.Credit_Limit__c) });
            return r;
        }
        if (step == 'activate_otp' || step == 'cancel_confirm') {
            Card_Application__c issued = BandhuCompliance.issuedApplication(j);
            Result r = new Result();
            j.Step__c = 'done';
            if (issued == null) {
                r.message = BandhuI18n.msg('No_Card_Yet', lang);
            } else if (step == 'activate_otp') {
                if (t.replaceAll('[^0-9]', '') != BandhuConfig.get().Demo_OTP__c) {
                    j.Step__c = 'activate_otp';
                    r.message = BandhuI18n.msg('OTP_Wrong', lang, new Map<String, Object>{ 'left' => '2' });
                } else {
                    BandhuCompliance.activate(j, issued);
                    r.message = BandhuI18n.msg('Activated', lang, tokens(j));
                    String tip = BandhuRewards.message(j, issued.Card_Product__c);
                    if (tip != null) {
                        r.message += '\n\n' + tip;   // the reminder, now that the card can be used
                    }
                }
            } else if (choice == 1 || Pattern.matches('(?i).*\\b(yes|confirm)\\b.*', t)) {
                BandhuCompliance.cancel(j, issued);
                r.message = BandhuI18n.msg('Cancelled', lang, tokens(j));
            } else {
                r.message = BandhuI18n.msg('Done', lang);
            }
            r.step = j.Step__c;
            return r;
        }
        if (step == 'secured_offer') {
            if (choice == 1 || t.containsIgnoreCase('shield') || t.containsIgnoreCase('fd')) {
                choose(j, securedCardName());
                return prefix(BandhuI18n.msg('Chosen', lang, new Map<String, Object>{ 'card' => j.Chosen_Card__c }), next(j, 'choose'));
            }
            if (choice == 2) {
                return handoff(j, 'Offered the secured card: wants to talk to a specialist');
            }
            j.Step__c = 'menu';
            return welcome(j);
        }
        if (step == 'applied_alt') {
            if (choice == 1 && j.Alternative_Card__c != null) {
                choose(j, j.Alternative_Card__c);
                return prefix(BandhuI18n.msg('Chosen', lang, new Map<String, Object>{ 'card' => j.Chosen_Card__c }), next(j, 'choose'));
            }
            if (choice == 2) {
                j.Step__c = 'choose';
                return appendPrompt(j, compare(j));
            }
            return handoff(j, 'Applied for ' + j.Applied_Card__c + ': wants to talk to a specialist');
        }
        if (step == 'hold') {
            return hold(j, BandhuCustomer.forContact(j.Contact__c));
        }
        if (step == 'question') {
            String key = faqKey(t + '?');
            Result r = new Result();
            r.message = BandhuI18n.msg(key == null ? 'FAQ_Fallback' : key, lang);
            j.Step__c = 'menu';
            r.options = BandhuI18n.options('Opt_Menu', lang, null);
            return r;
        }
        if (step == 'consent') {
            if (choice == 1 || Pattern.matches('(?i).*\\b(yes|agree|ok|okay|sure|haan|ha|hya|ji)\\b.*', t)) {
                j.Consent__c = true;
                j.Consent_At__c = Datetime.now();
                BandhuCompliance.record(j, 'DPDP data processing', 'Recommend a card and process the application'
                    + ' (incl. a soft credit check for existing customers)', null, null, BandhuI18n.msg('Consent', lang));
                BandhuJourneyService.advance(j, 'Verify');
                return next(j, 'consent');
            }
            if (choice == 2 || Pattern.matches('(?i).*\\b(no|not now|nahi|na)\\b.*', t)) {
                j.Status__c = BandhuJourneyService.STATUS_EXITED;
                j.Step__c = 'done';
                Result r = new Result();
                r.message = BandhuI18n.msg('Consent_Declined', lang);
                return r;
            }
            return invalid(j);
        }
        if (step == 'name') {
            String name = t.replaceAll('[^\\p{L}\\p{M} .\']', ' ').normalizeSpace();
            if (name.length() < 2 || name.split(' ').size() > 6) {
                return reask(j, 'Invalid_Name');
            }
            j.Customer_Name__c = titleCase(name).abbreviate(120);
            return next(j, 'name');
        }
        if (step == 'mobile') {
            String m = BandhuI18n.normalizeMobile(t);
            if (m == null) {
                return reask(j, 'Invalid_Mobile');
            }
            j.Mobile__c = m;
            return next(j, 'mobile');
        }
        if (step == 'otp') {
            return verifyOtp(j, t);
        }
        if (step == 'spend') {
            Set<String> focus = parseFocus(t);
            if (focus.isEmpty()) {
                return invalid(j);
            }
            j.Spend_Focus__c = String.join(new List<String>(focus), ';');
            j.Travel_Frequency__c = focus.contains('International') ? 'International' : focus.contains('Travel') ? 'Domestic' : 'Rarely';
            BandhuJourneyService.advance(j, 'Needs');
            return next(j, 'spend');
        }
        if (step == 'monthly_spend') {
            Decimal spend = choice != null && SPEND_BANDS.containsKey(String.valueOf(choice)) ? SPEND_BANDS.get(String.valueOf(choice)) : BandhuI18n.parseAmount(t);
            if (spend == null) {
                return invalid(j);
            }
            j.Monthly_Spend__c = spend;
            return next(j, 'monthly_spend');
        }
        if (step == 'fee') {
            if (choice == 1 || t.containsIgnoreCase('low')) {
                j.Fee_Preference__c = BandhuEligibility.LOWEST_FEE;
            } else if (choice == 2 || t.containsIgnoreCase('benefit')) {
                j.Fee_Preference__c = BandhuEligibility.BEST_BENEFITS;
            } else {
                return invalid(j);
            }
            BandhuJourneyService.advance(j, 'Profile');
            return next(j, 'fee');
        }
        if (step == 'employment') {
            if (choice == 1 || t.containsIgnoreCase('salar') || t.containsIgnoreCase('job')) {
                j.Employment_Type__c = 'Salaried';
            } else if (choice == 3 || t.containsIgnoreCase('business') || t.containsIgnoreCase('shop') || t.containsIgnoreCase('dukan')) {
                j.Employment_Type__c = 'Business';
            } else if (choice == 2 || t.containsIgnoreCase('self') || t.containsIgnoreCase('freelanc') || t.containsIgnoreCase('professional')) {
                j.Employment_Type__c = 'Self-employed';
            } else {
                return invalid(j);
            }
            return next(j, 'employment');
        }
        if (step == 'income') {
            Decimal income = BandhuI18n.parseAmount(t);
            if (income == null || income < 1000) {
                return reask(j, 'Invalid_Income');
            }
            j.Monthly_Income__c = income;
            return next(j, 'income');
        }
        if (step == 'company') {
            String c = t.normalizeSpace();
            if (c.length() < 2) {
                return invalid(j);
            }
            j.Company_Name__c = c.abbreviate(120);
            return next(j, 'company');
        }
        if (step == 'pan') {
            Matcher m = PAN.matcher(t.toUpperCase().replaceAll('\\s', ''));
            if (!m.find()) {
                return reask(j, 'Invalid_PAN');
            }
            j.PAN__c = m.group();
            return next(j, 'pan');
        }
        if (step == 'dob') {
            Date dob = parseDob(t);
            if (dob == null) {
                return reask(j, 'Invalid_DOB');
            }
            j.Date_Of_Birth__c = dob;
            return next(j, 'dob');
        }
        if (step == 'pincode') {
            Matcher m = Pattern.compile('(?<![0-9])[1-9][0-9]{5}(?![0-9])').matcher(t.replaceAll('(?<=[0-9])\\s(?=[0-9])', ''));
            if (!m.find()) {
                return reask(j, 'Invalid_Pincode');
            }
            j.PIN_Code__c = m.group();
            String city = t.replaceAll('[0-9]', ' ').replaceAll('(?i)\\b(pin|code|pincode|city|is|my)\\b', ' ').replaceAll('[^\\p{L}\\p{M} ]', ' ').normalizeSpace();
            j.City__c = String.isNotBlank(city) ? titleCase(city).abbreviate(60) : PIN_CITY.get(j.PIN_Code__c.left(3));
            return next(j, 'pincode');
        }
        if (step == 'bureau') {
            Result pre = new Result();
            if (choice == 1 || Pattern.matches('(?i).*\\b(yes|ok|okay|sure|go ahead|haan)\\b.*', t)) {
                j.Bureau_Consent__c = true;
                BandhuBureau.softPull(j);
                BandhuCompliance.record(j, 'Soft credit check', 'Soft credit check for card eligibility (no score impact)', j.PAN__c == null ? null : BandhuI18n.maskPan(j.PAN__c),
                    null, BandhuI18n.msg('Q_Bureau', lang));
            } else if (choice == 2 || Pattern.matches('(?i).*\\b(no|skip|later)\\b.*', t)) {
                pre.message = BandhuI18n.msg('Bureau_Skipped', lang);
            } else {
                return invalid(j);
            }
            return prefix(pre.message, next(j, 'bureau'));
        }
        if (step == 'aa') {
            String pre;
            if (choice == 1 || t.containsIgnoreCase('verify') || t.containsIgnoreCase('connect') || t.containsIgnoreCase('yes')) {
                BandhuCashFlow.Analysis a = BandhuAccountAggregator.run(j);
                if (String.isBlank(j.Company_Name__c) && String.isNotBlank(a.employer) && j.Employment_Type__c == 'Salaried') {
                    j.Company_Name__c = titleCase(a.employer.toLowerCase()).abbreviate(120);   // seen on the salary credits: not asked again
                }
                BandhuCompliance.record(j, 'Account Aggregator', BandhuAccountAggregator.PURPOSE_CREDIT + ': ' + BandhuAccountAggregator.LOOKBACK_MONTHS
                    + ' months of deposit statements, one fetch', j.AA_Consent_Id__c, BandhuI18n.today().addDays(30), BandhuI18n.msg('Q_AA', lang));
                j.Verified_Income__c = a.netMonthlyIncome > 0 ? a.netMonthlyIncome : null;
                pre = BandhuI18n.msg('AA_Done', lang, new Map<String, Object>{ 'income' => BandhuI18n.inr(a.netMonthlyIncome) })
                    + '\n\n' + BandhuI18n.msg('AA_Insights', lang, new Map<String, Object>{
                        'months' => a.months, 'banks' => a.accounts, 'stability' => a.incomeStability, 'trend' => a.incomeTrend,
                        'emi' => BandhuI18n.inr(a.monthlyObligations), 'foir' => a.foirPct.intValue(), 'top' => a.customerSpendText(lang),
                        'lifestyle' => a.extraLifestyle() == null ? '' : '\n• ' + a.extraLifestyle() });
            } else if (choice != 2 && !t.containsIgnoreCase('skip') && !t.containsIgnoreCase('later')) {
                return invalid(j);
            }
            String soFar = soFar(j);
            if (soFar != null) {
                pre = pre == null ? soFar : pre + '\n\n' + soFar;
            }
            return prefix(pre, next(j, 'aa'));
        }
        if (step == 'choose') {
            String picked;
            for (Bandhu_Card__mdt c : BandhuConfig.cards()) {
                if (t.containsIgnoreCase(c.DeveloperName) && !eligibleFor(j, c.DeveloperName) && c.Secured__c != true) {
                    return applied(j, c.DeveloperName);
                }
                if (t.containsIgnoreCase(c.DeveloperName) && (eligibleFor(j, c.DeveloperName) || c.Secured__c == true)) {
                    picked = c.DeveloperName;
                }
            }
            Boolean hasAlt = j.Alternative_Card__c != null;
            if (picked == null && choice == 1) {
                picked = j.Recommended_Card__c;
            } else if (picked == null && choice == 2 && hasAlt) {
                picked = j.Alternative_Card__c;
            } else if (picked == null && (choice == (hasAlt ? 3 : 2))) {
                return appendPrompt(j, compare(j));
            } else if (picked == null && (choice == (hasAlt ? 4 : 3))) {
                return handoff(j, 'At the recommendation: talk to a specialist');
            }
            if (picked == null) {
                return invalid(j);
            }
            choose(j, picked);
            return prefix(BandhuI18n.msg('Chosen', lang, new Map<String, Object>{ 'card' => picked }), next(j, 'choose'));
        }
        if (step == 'email') {
            Matcher m = EMAIL.matcher(t);
            if (!m.find()) {
                return reask(j, 'Invalid_Email');
            }
            j.Email__c = m.group().toLowerCase();
            return next(j, 'email');
        }
        if (step == 'aadhaar') {
            if (!Pattern.matches('[0-9]{4}', t.replaceAll('\\s', ''))) {
                return reask(j, 'Invalid_Aadhaar');
            }
            return ask(j, 'aadhaar_otp');
        }
        if (step == 'aadhaar_otp') {
            if (t.replaceAll('[^0-9]', '') != BandhuConfig.get().Demo_OTP__c) {
                Result r = new Result();
                r.message = BandhuI18n.msg('OTP_Wrong', lang, new Map<String, Object>{ 'left' => '2' });
                r.step = step;
                return r;
            }
            j.KYC_Status__c = 'Aadhaar verified';
            return prefix(BandhuI18n.msg('Aadhaar_Done', lang), next(j, 'aadhaar_otp'));
        }
        if (step == 'vkyc') {
            if (choice == 1 || t.containsIgnoreCase('done') || t.containsIgnoreCase('finished') || t.containsIgnoreCase('complete')) {
                j.KYC_Status__c = 'Complete';
                return next(j, 'vkyc');
            }
            if (choice == 2 || t.containsIgnoreCase('later')) {
                Result r = new Result();
                r.message = BandhuI18n.msg('VKYC_Later', lang);
                r.options = BandhuI18n.options('Opt_VKYC', lang, null);
                r.step = step;
                return r;
            }
            return invalid(j);
        }
        if (step == 'review') {
            if (choice == 1 || Pattern.matches('(?i).*\\b(confirm|submit|yes)\\b.*', t)) {
                BandhuCompliance.record(j, 'Hard credit enquiry', 'Declared before submission: a hard enquiry with CIBIL, recorded on the credit report',
                    j.PAN__c == null ? null : BandhuI18n.maskPan(j.PAN__c), null, BandhuI18n.msg('Hard_Enquiry_Notice', lang));
                return submit(j);
            }
            if (choice == 2) {
                return handoff(j, 'At the review: talk to a specialist');
            }
            return invalid(j);
        }
        if (step == 'declined_alt') {
            if (choice == 1 && j.Alternative_Card__c != null) {
                choose(j, j.Alternative_Card__c);
                j.Status__c = BandhuJourneyService.STATUS_ACTIVE;
                return prefix(BandhuI18n.msg('Chosen', lang, new Map<String, Object>{ 'card' => j.Chosen_Card__c }), ask(j, 'review'));
            }
            return handoff(j, 'Declined: wants to talk to a specialist');
        }
        Result r = new Result();
        r.message = BandhuI18n.msg('Done', lang);
        return r;
    }

    // ------------------------------------------------------------------ steps
    /** The next unanswered step after this one (existing customers skip what is already on file). */
    private static Result next(Card_Journey__c j, String after) {
        j.Fields_Done__c = BandhuJourneyService.fieldsDone(j);
        if (after == 'consent') {
            if (String.isBlank(j.Customer_Name__c)) {
                return ask(j, 'name');
            }
            after = 'name';
        }
        if (after == 'name') {
            if (j.OTP_Verified__c) {
                return next(j, 'otp');
            }
            return j.Mobile__c == null ? ask(j, 'mobile') : sendOtp(j);
        }
        if (after == 'mobile') {
            return sendOtp(j);
        }
        if (after == 'otp' || PROFILE_STEPS.contains(after)) {
            Integer i = after == 'otp' ? -1 : PROFILE_STEPS.indexOf(after);
            for (Integer k = i + 1; k < PROFILE_STEPS.size(); k++) {
                String s = PROFILE_STEPS[k];
                if (needs(j, s)) {
                    return ask(j, s);
                }
            }
            return recommend(j);
        }
        Integer kyc = KYC_STEPS.indexOf(after == 'choose' ? 'start' : after);
        for (Integer k = kyc + 1; k < KYC_STEPS.size(); k++) {
            String s = KYC_STEPS[k];
            if (needs(j, s)) {
                return ask(j, s);
            }
        }
        return ask(j, 'review');
    }

    private static Boolean needs(Card_Journey__c j, String step) {
        Boolean existing = j.Customer_Type__c == BandhuJourneyService.EXISTING;
        switch on step {
            when 'employment' { return String.isBlank(j.Employment_Type__c); }
            when 'spend' { return String.isBlank(j.Spend_Focus__c); }
            when 'monthly_spend' { return j.Monthly_Spend__c == null; }
            when 'fee' { return String.isBlank(j.Fee_Preference__c); }
            when 'income' { return j.Monthly_Income__c == null; }
            when 'company' { return String.isBlank(j.Company_Name__c); }
            when 'pan' { return String.isBlank(j.PAN__c); }
            when 'dob' { return j.Date_Of_Birth__c == null; }
            when 'pincode' { return String.isBlank(j.PIN_Code__c); }
            when 'bureau' { return j.CIBIL_Score__c == null && !j.Bureau_Consent__c && j.Step__c != 'bureau'; }
            when 'aa' { return !existing && j.Verified_Income__c == null && j.Step__c != 'aa'; }
            when 'email' { return String.isBlank(j.Email__c); }
            when 'aadhaar' { return !existing && j.KYC_Status__c != 'Aadhaar verified' && j.KYC_Status__c != 'Complete'; }
            when 'aadhaar_otp' { return false; }
            when 'vkyc' { return !existing && j.KYC_Status__c != 'Complete'; }
            when 'review' { return true; }
        }
        return false;
    }

    private static Result ask(Card_Journey__c j, String step) {
        j.Step__c = step;
        return prompt(j, step);
    }

    /** The question for a step, with its options. */
    public static Result prompt(Card_Journey__c j, String step) {
        String lang = j.Language__c;
        Result r = new Result();
        r.step = step;
        Map<String, Object> tk = tokens(j);
        switch on step {
            when 'menu' { return welcome(j); }
            when 'consent' { r.message = BandhuI18n.msg('Consent', lang); r.options = BandhuI18n.options('Opt_Consent', lang, null); }
            when 'name' { r.message = BandhuI18n.msg('Q_Name', lang); }
            when 'mobile' { r.message = BandhuI18n.msg('Q_Mobile', lang); }
            when 'otp' { r.message = BandhuI18n.msg('OTP_Sent', lang, tk); }
            when 'spend' { r.message = BandhuI18n.msg('Q_Spend', lang); r.options = BandhuI18n.options('Opt_Spend', lang, null); }
            when 'monthly_spend' { r.message = BandhuI18n.msg('Q_Monthly_Spend', lang); r.options = BandhuI18n.options('Opt_Monthly_Spend', lang, null); }
            when 'fee' { r.message = BandhuI18n.msg('Q_Fee', lang); r.options = BandhuI18n.options('Opt_Fee', lang, null); }
            when 'employment' { r.message = BandhuI18n.msg('Q_Employment', lang); r.options = BandhuI18n.options('Opt_Employment', lang, null); }
            when 'income' { r.message = BandhuI18n.msg('Q_Income', lang); }
            when 'company' { r.message = BandhuI18n.msg('Q_Company', lang); }
            when 'pan' { r.message = BandhuI18n.msg('Q_PAN', lang); }
            when 'dob' { r.message = BandhuI18n.msg('Q_DOB', lang); }
            when 'pincode' { r.message = BandhuI18n.msg('Q_Pincode', lang); }
            when 'bureau' { r.message = BandhuI18n.msg('Q_Bureau', lang); r.options = BandhuI18n.options('Opt_Bureau', lang, null); }
            when 'aa' { r.message = BandhuI18n.msg('Q_AA', lang); r.options = BandhuI18n.options('Opt_AA', lang, null); }
            when 'choose' { return recommendation(j, null); }
            when 'email' { r.message = BandhuI18n.msg('Q_Email', lang); }
            when 'aadhaar' { r.message = BandhuI18n.msg('Q_Aadhaar', lang); }
            when 'aadhaar_otp' { r.message = BandhuI18n.msg('Q_Aadhaar_OTP', lang, tk); }
            when 'vkyc' { r.message = BandhuI18n.msg('Q_VKYC', lang, tk); r.options = BandhuI18n.options('Opt_VKYC', lang, null); }
            when 'review' { r.message = BandhuI18n.msg('Review', lang, tk) + '\n\n' + BandhuI18n.msg('Hard_Enquiry_Notice', lang); r.options = BandhuI18n.options('Opt_Review', lang, null); }
            when 'limit_offer' {
                Card_Application__c la = [SELECT Id, Card_Product__c, Credit_Limit__c, Limit_Offer__c, Upgrade_Offer_Card__c FROM Card_Application__c
                                          WHERE Id = :j.Card_Application__c];
                r.message = BandhuPostIssue.offerMessage(j, la);
                r.options = BandhuI18n.options('Opt_Limit_Offer', lang, null);
            }
            when 'secured_offer' {
                BandhuEligibility.Outcome so = BandhuEligibility.evaluate(BandhuJourneyService.profile(j));
                if (so.secured != null) {
                    return securedOffer(j, so);
                }
            }
            when 'applied_alt' { return applied(j, j.Applied_Card__c); }
            when 'not_eligible' { r.message = BandhuI18n.msg('Not_Eligible', lang, tk); r.options = BandhuI18n.options('Opt_Not_Eligible', lang, null); }
            when 'declined_alt' { r.message = BandhuI18n.msg('Done', lang); r.options = BandhuI18n.options('Opt_Declined_Alt', lang, tk); }
            when 'after_compare' { r = compare(j); r.options = BandhuI18n.options('Opt_After_Compare', lang, null); }
            when 'question' { r.message = BandhuI18n.msg('FAQ_Fallback', lang); }
            when else { r.message = BandhuI18n.msg('Done', lang); }
        }
        return r;
    }

    private static Result welcome(Card_Journey__c j) {
        String lang = j.Language__c;
        Boolean existing = j.Customer_Type__c == BandhuJourneyService.EXISTING;
        Result r = new Result();
        r.message = BandhuI18n.msg(existing ? 'Welcome_Existing' : 'Welcome', lang, tokens(j));
        String langHint = BandhuI18n.msg('Lang_Hint', lang);
        if (String.isNotBlank(langHint) && j.Channel__c != 'Web') {
            r.message += '\n\n' + langHint;
        }
        r.options = BandhuI18n.options('Opt_Menu', lang, null);
        r.step = 'menu';
        r.cards = cardViews(null, j);
        return r;
    }

    private static Result sendOtp(Card_Journey__c j) {
        j.Step__c = 'otp';
        BandhuJourneyService.advance(j, 'Verify');
        return prompt(j, 'otp');
    }

    private static Result verifyOtp(Card_Journey__c j, String t) {
        Bandhu_Config__mdt cfg = BandhuConfig.get();
        String lang = j.Language__c;
        if (t.replaceAll('[^0-9]', '') != cfg.Demo_OTP__c) {
            j.OTP_Attempts__c = (j.OTP_Attempts__c == null ? 0 : j.OTP_Attempts__c) + 1;
            Integer left = (cfg.Max_OTP_Attempts__c == null ? 3 : cfg.Max_OTP_Attempts__c.intValue()) - j.OTP_Attempts__c.intValue();
            Result r = new Result();
            r.step = 'otp';
            if (left <= 0) {
                j.Status__c = BandhuJourneyService.STATUS_EXITED;
                r.message = BandhuI18n.msg('OTP_Locked', lang);
                r.handoff = true;
                BandhuLeadService.rmTask(j, 'Bandhu: OTP locked - ' + label(j), 'Too many wrong OTPs; call the customer back.');
                return r;
            }
            r.message = BandhuI18n.msg('OTP_Wrong', lang, new Map<String, Object>{ 'left' => left });
            return r;
        }
        j.OTP_Verified__c = true;
        Contact c = BandhuJourneyService.findContact(j.Mobile__c);
        String pre;
        if (c != null) {
            BandhuCustomer.Insight etb = prefillExisting(j, c);
            if (etb != null && etb.blocker != null) {
                return hold(j, etb);
            }
            if (String.isNotBlank(j.PAN__c) && j.CIBIL_Score__c == null) {
                // existing customer: silent soft pull on the PAN on file (consented at the start), or the cached report
                j.Bureau_Consent__c = true;
                BandhuBureau.softPull(j);
                BandhuCompliance.record(j, 'Soft credit check', 'Existing customer: silent soft check under the consent at the start', BandhuI18n.maskPan(j.PAN__c), null, null);
            }
            pre = BandhuI18n.msg('Verified_Existing', lang, tokens(j));
        } else {
            j.Customer_Type__c = BandhuJourneyService.NEW_TO_BANK;
            pre = BandhuI18n.msg('Verified_New', lang);
        }
        Result r = next(j, 'otp');
        if (j.Customer_Type__c == BandhuJourneyService.NEW_TO_BANK) {
            BandhuLeadService.upsertLead(j);
        }
        return prefix(pre, r);
    }

    /** Existing customer: details from the bank's records (mock core banking) so they are not asked again. */
    /** Dormant account, KYC due or an AML review: stop before any data is used; the RM follows up. */
    private static Result hold(Card_Journey__c j, BandhuCustomer.Insight etb) {
        j.Hold_Reason__c = etb.blocker.abbreviate(255);
        j.Step__c = 'hold';
        j.Status__c = BandhuJourneyService.STATUS_EXITED;
        BandhuLeadService.rmTask(j, 'Bandhu: card journey on hold - ' + label(j), 'On hold before the card journey: ' + etb.blocker
            + '\n' + String.join(etb.lines(), '\n'));
        Result r = new Result();
        r.step = 'hold';
        r.message = BandhuI18n.msg(etb.blockerKind == 'Dormant' ? 'Hold_Dormant' : etb.blockerKind == 'KYC' ? 'Hold_KYC' : 'Hold_Review', j.Language__c, tokens(j));
        return r;
    }

    @TestVisible
    private static BandhuCustomer.Insight prefillExisting(Card_Journey__c j, Contact c) {
        j.Contact__c = c.Id;
        j.Customer_Type__c = BandhuJourneyService.EXISTING;
        j.Customer_Name__c = String.isBlank(j.Customer_Name__c) ? c.Name : j.Customer_Name__c;
        j.Date_Of_Birth__c = j.Date_Of_Birth__c == null ? c.Birthdate : j.Date_Of_Birth__c;
        j.Email__c = String.isBlank(j.Email__c) ? c.Email : j.Email__c;
        if (String.isBlank(j.PIN_Code__c) && String.isNotBlank(c.MailingPostalCode)) {
            j.PIN_Code__c = c.MailingPostalCode;
            j.City__c = c.MailingCity;
        }
        for (Bank_Relationship__c r : BandhuJourneyService.relationships(c.Id)) {
            if (r.Relationship_Type__c == 'Salary Account' && r.Monthly_Salary_Credit__c != null) {
                j.Employment_Type__c = 'Salaried';
                j.Monthly_Income__c = r.Monthly_Salary_Credit__c;
                j.Verified_Income__c = r.Monthly_Salary_Credit__c;
            }
            if (String.isNotBlank(r.PAN__c) && String.isBlank(j.PAN__c)) {
                j.PAN__c = r.PAN__c;
            }
        }
        j.KYC_Status__c = 'Complete';
        BandhuCustomer.Insight etb = BandhuCustomer.forContact(c.Id);
        if (etb != null) {
            j.ETB_Tier__c = etb.tier;
            j.Relationship_Score__c = etb.score;
        }
        return etb;
    }

    // ------------------------------------------------------------------ recommendation
    private static Result recommend(Card_Journey__c j) {
        BandhuJourneyService.advance(j, 'Recommend');
        BandhuEligibility.Outcome out = BandhuEligibility.evaluate(BandhuJourneyService.profile(j));
        j.Eligible_Cards__c = String.join(out.eligibleNames(), ';');
        j.Bandhan_Score__c = out.score.score;
        if (out.best == null) {
            BandhuPostIssue.scheduleReassess(j);
        }
        if (out.best == null && out.secured != null) {
            return securedOffer(j, out);
        }
        if (out.best == null) {
            j.Step__c = 'not_eligible';
            j.Recommended_Card__c = null;
            Result r = new Result();
            Map<String, Object> tk = tokens(j);
            tk.put('reason', out.blockedReason);
            r.message = BandhuI18n.msg('Not_Eligible', j.Language__c, tk);
            r.options = BandhuI18n.options('Opt_Not_Eligible', j.Language__c, null);
            r.step = 'not_eligible';
            r.cards = cardViews(out, j);
            BandhuLeadService.upsertLead(j);
            return r;
        }
        j.Recommended_Card__c = out.best.card.DeveloperName;
        j.Alternative_Card__c = out.alternative == null ? null : out.alternative.card.DeveloperName;
        j.Upgrade_Card__c = out.upgrade == null ? null : out.upgrade.card.DeveloperName;
        j.Credit_Limit__c = out.best.creditLimit;
        j.Recommendation_Reason__c = String.join(out.best.why, '\n');
        j.Step__c = 'choose';
        BandhuLeadService.upsertLead(j);
        return recommendation(j, out);
    }

    private static Result recommendation(Card_Journey__c j, BandhuEligibility.Outcome out) {
        if (out == null) {
            out = BandhuEligibility.evaluate(BandhuJourneyService.profile(j));
        }
        String lang = j.Language__c;
        Bandhu_Card__mdt c = BandhuConfig.card(j.Recommended_Card__c);
        Map<String, Object> tk = tokens(j);
        tk.putAll(new Map<String, Object>{
            'card' => c.DeveloperName, 'tagline' => c.Tagline__c, 'why' => j.Recommendation_Reason__c, 'welcome' => c.Welcome__c,
            'rewards' => c.Rewards__c + (String.isNotBlank(c.Accelerated__c) ? ' · ' + c.Accelerated__c : ''), 'lounge' => c.Lounge__c,
            'fee' => c.Joining_Fee__c == null ? '0' : String.valueOf(c.Joining_Fee__c.intValue()), 'waiver' => c.Fee_Waiver__c,
            'limit' => limitText(j, out), 'alt' => '', 'upgrade' => ''
        });
        if (j.Alternative_Card__c != null) {
            Bandhu_Card__mdt a = BandhuConfig.card(j.Alternative_Card__c);
            tk.put('alt', '\n\n' + BandhuI18n.msg('Recommend_Alt', lang, new Map<String, Object>{ 'card' => a.DeveloperName, 'tagline' => a.Tagline__c }));
        }
        if (j.Upgrade_Card__c != null) {
            Bandhu_Card__mdt u = BandhuConfig.card(j.Upgrade_Card__c);
            tk.put('upgrade', '\n\n' + BandhuI18n.msg('Recommend_Upgrade', lang, new Map<String, Object>{
                'card' => u.DeveloperName, 'income' => BandhuI18n.inrShort(u.Min_Monthly_Income__c) }));
        }
        Result r = new Result();
        r.message = BandhuI18n.msg('Recommend', lang, tk);
        r.options = BandhuI18n.options(j.Alternative_Card__c == null ? 'Opt_Recommend_Single' : 'Opt_Recommend', lang,
            new Map<String, Object>{ 'card' => j.Recommended_Card__c, 'alt' => j.Alternative_Card__c });
        r.step = 'choose';
        r.cards = cardViews(out, j);
        return r;
    }

    /** Real-time eligibility feedback while answering: a soft check on what we know so far (no bureau pull). */
    private static String soFar(Card_Journey__c j) {
        BandhuEligibility.Outcome out = BandhuEligibility.evaluate(BandhuJourneyService.profile(j));
        List<String> names = out.eligibleNames();
        if (names.isEmpty()) {
            return null;
        }
        return BandhuI18n.msg('So_Far', j.Language__c, new Map<String, Object>{ 'cards' => String.join(names, ', '), 'count' => names.size() });
    }

    private static String limitText(Card_Journey__c j, BandhuEligibility.Outcome out) {
        for (BandhuEligibility.Option o : out.options) {
            if (o.card.DeveloperName == j.Recommended_Card__c && o.limitLow != null && o.limitLow < o.creditLimit) {
                return BandhuI18n.inr(o.limitLow) + ' - ' + BandhuI18n.inr(o.creditLimit);
            }
        }
        return BandhuI18n.inr(j.Credit_Limit__c);
    }

    private static String securedCardName() {
        for (Bandhu_Card__mdt c : BandhuConfig.cards()) {
            if (c.Secured__c == true) {
                return c.DeveloperName;
            }
        }
        return null;
    }

    /** No unsecured card: a card against an FD, sized from what they need to spend. */
    private static Result securedOffer(Card_Journey__c j, BandhuEligibility.Outcome out) {
        BandhuEligibility.Option s = out.secured;
        j.Step__c = 'secured_offer';
        j.Recommended_Card__c = s.card.DeveloperName;
        j.Alternative_Card__c = null;
        j.Upgrade_Card__c = null;
        j.Credit_Limit__c = s.creditLimit;
        j.FD_Amount__c = s.fdAmount;
        j.Recommendation_Reason__c = String.join(s.why, '\n');
        BandhuLeadService.upsertLead(j);
        Map<String, Object> tk = tokens(j);
        tk.putAll(new Map<String, Object>{ 'reason' => out.blockedReason, 'card' => s.card.DeveloperName, 'fd' => BandhuI18n.inr(s.fdAmount),
            'limit' => BandhuI18n.inr(s.creditLimit), 'why' => j.Recommendation_Reason__c });
        Result r = new Result();
        r.step = 'secured_offer';
        r.message = BandhuI18n.msg('Secured_Offer', j.Language__c, tk);
        r.options = BandhuI18n.options('Opt_Secured', j.Language__c, tk);
        r.cards = cardViews(out, j);
        return r;
    }

    /** They asked for a card they don't qualify for: the closest one they do, why, and what it gives. */
    private static Result applied(Card_Journey__c j, String card) {
        BandhuEligibility.Outcome out = BandhuEligibility.evaluate(BandhuJourneyService.profile(j));
        BandhuEligibility.Explanation e = BandhuEligibility.explain(out, card);
        j.Applied_Card__c = card;
        if (e.alternative == null) {
            return out.secured != null ? securedOffer(j, out) : recommend(j);
        }
        j.Alternative_Card__c = e.alternative.card.DeveloperName;
        j.Step__c = 'applied_alt';
        Map<String, Object> tk = tokens(j);
        tk.putAll(new Map<String, Object>{
            'applied' => card + (String.isBlank(e.applied.Tier_Label__c) ? '' : ' (' + e.applied.Tier_Label__c + ')'),
            'alt' => e.alternative.card.DeveloperName + (String.isBlank(e.alternative.card.Tier_Label__c) ? '' : ' (' + e.alternative.card.Tier_Label__c + ')'),
            'missed' => '• ' + String.join(e.missed, '\n• '), 'gets' => String.join(e.gets, '\n'),
            'card' => e.alternative.card.DeveloperName });
        Result r = new Result();
        r.step = 'applied_alt';
        r.message = BandhuI18n.msg('Applied_Alt', j.Language__c, tk);
        r.options = BandhuI18n.options('Opt_Applied_Alt', j.Language__c, tk);
        r.cards = cardViews(out, j);
        return r;
    }

    private static Boolean eligibleFor(Card_Journey__c j, String card) {
        return String.isNotBlank(j.Eligible_Cards__c) && j.Eligible_Cards__c.split(';').contains(card);
    }

    private static void choose(Card_Journey__c j, String card) {
        j.Chosen_Card__c = card;
        Bandhu_Card__mdt c = BandhuConfig.card(card);
        BandhuEligibility.Outcome out = BandhuEligibility.evaluate(BandhuJourneyService.profile(j));
        if (c != null && c.Secured__c == true) {
            BandhuEligibility.Option s = BandhuEligibility.securedOption(c, BandhuJourneyService.profile(j));
            j.Credit_Limit__c = s.creditLimit;
            j.FD_Amount__c = s.fdAmount;
        }
        for (BandhuEligibility.Option o : out.options) {
            if (o.card.DeveloperName == card && o.creditLimit != null) {
                j.Credit_Limit__c = o.creditLimit;
            }
        }
        BandhuJourneyService.advance(j, 'KYC');
    }

    // ------------------------------------------------------------------ submit
    private static Result submit(Card_Journey__c j) {
        BandhuDecision.Outcome o = BandhuDecision.submit(j);
        String lang = j.Language__c;
        Map<String, Object> tk = tokens(j);
        tk.put('masked', o.application.Card_Number_Masked__c);
        tk.put('limit', BandhuI18n.inr(o.application.Credit_Limit__c));
        tk.put('link', BandhuDecision.activationLink());
        Result r = new Result();
        if (o.recommendation == BandhuDecision.APPROVE) {
            j.Step__c = 'done';
            r.message = BandhuI18n.msg('Approved', lang, tk) + '\n\n' + BandhuCompliance.onIssue(j, o.application);
            String tip = BandhuRewards.message(j, o.application.Card_Product__c);
            if (tip != null) {
                r.message += '\n\n' + tip;   // with the card: what they could move onto it, from their statements
            }
            update o.application;
            BandhuLeadService.convert(j);
        } else if (o.recommendation == BandhuDecision.REFER) {
            j.Step__c = 'done';
            r.message = BandhuI18n.msg('Referred', lang, tk);
            BandhuLeadService.rmTask(j, 'Bandhu: card application to review - ' + label(j), o.application.Recommendation_Reasons__c);
        } else {
            j.Alternative_Card__c = o.alternativeCard;
            BandhuPostIssue.scheduleReassess(j);
            tk.put('alt', o.alternativeCard == null ? '' : '\n\n' + BandhuI18n.msg('Declined_Alt', lang, new Map<String, Object>{ 'alt' => o.alternativeCard }));
            r.message = BandhuI18n.msg('Declined', lang, tk);
            if (o.alternativeCard != null) {
                j.Step__c = 'declined_alt';
                r.options = BandhuI18n.options('Opt_Declined_Alt', lang, new Map<String, Object>{ 'alt' => o.alternativeCard });
            } else {
                j.Step__c = 'done';
            }
        }
        r.step = j.Step__c;
        if (o.recommendation != BandhuDecision.APPROVE) {
            BandhuLeadService.upsertLead(j);
        }
        return r;
    }

    // ------------------------------------------------------------------ anytime helpers
    private static Result compare(Card_Journey__c j) {
        String lang = j.Language__c;
        List<String> lines = new List<String>();
        for (Bandhu_Card__mdt c : BandhuConfig.cards()) {
            lines.add(BandhuI18n.msg('Compare_Line', lang, new Map<String, Object>{
                'card' => c.DeveloperName, 'tagline' => c.Tagline__c, 'rewards' => c.Rewards__c, 'lounge' => c.Lounge__c,
                'fee' => c.Joining_Fee__c == null ? '0' : String.valueOf(c.Joining_Fee__c.intValue()) }));
        }
        Result r = new Result();
        r.message = BandhuI18n.msg('Compare', lang, new Map<String, Object>{ 'lines' => String.join(lines, '\n\n') });
        r.cards = cardViews(null, j);
        r.step = j.Step__c;
        return r;
    }

    private static Result status(Card_Journey__c j) {
        Result r = new Result();
        List<Card_Application__c> apps = j.Card_Application__c == null ? new List<Card_Application__c>()
            : [SELECT Card_Product__c, Status__c, Reference_Number__c FROM Card_Application__c WHERE Id = :j.Card_Application__c];
        if (apps.isEmpty()) {
            r.message = BandhuI18n.msg('Status_None', j.Language__c);
        } else {
            r.message = BandhuI18n.msg('Status', j.Language__c, new Map<String, Object>{
                'ref' => apps[0].Reference_Number__c, 'card' => apps[0].Card_Product__c, 'status' => apps[0].Status__c.toLowerCase() });
        }
        return r;
    }

    /** A side answer (FAQ, comparison, status) followed by the pending question again. */
    private static Result appendPrompt(Card_Journey__c j, Result side) {
        if (j.Step__c == null || j.Step__c == 'done') {
            return side;
        }
        Result p = prompt(j, j.Step__c);
        if (j.Step__c != 'menu' && j.Step__c != 'after_compare') {
            p.message = side.message + '\n\n' + p.message;
        } else {
            p.message = side.message;
        }
        if (!side.cards.isEmpty()) {
            p.cards = side.cards;
        }
        return p;
    }

    private static String faqKey(String t) {
        if (!t.contains('?') && !Pattern.matches('(?i)^\\s*(what|how|which|can|do|does|is|are|kya|kaun|কি|কোন).*', t)) {
            return null;
        }
        String s = t.toLowerCase();
        if (s.contains('fee') || s.contains('charge') || s.contains('cost') || s.contains('शुल्क') || s.contains('ফি')) {
            return 'FAQ_Fees';
        }
        if (s.contains('eligib') || s.contains('qualify') || s.contains('income') || s.contains('पात्र') || s.contains('যোগ্য')) {
            return 'FAQ_Eligibility';
        }
        if (s.contains('document') || s.contains('kyc') || s.contains('paper') || s.contains('दस्तावेज़') || s.contains('নথি')) {
            return 'FAQ_Documents';
        }
        if (s.contains('lounge') || s.contains('airport')) {
            return 'FAQ_Lounge';
        }
        if (s.contains('reward') || s.contains('point') || s.contains('cashback')) {
            return 'FAQ_Rewards';
        }
        return null;
    }

    private static Result invalid(Card_Journey__c j) {
        return reask(j, 'Invalid_Answer');
    }

    private static Result reask(Card_Journey__c j, String key) {
        Result p = prompt(j, j.Step__c);
        p.message = BandhuI18n.msg(key, j.Language__c) + '\n\n' + p.message;
        p.success = false;
        return p;
    }

    private static Result prefix(String pre, Result r) {
        if (String.isNotBlank(pre)) {
            r.message = pre + '\n\n' + r.message;
        }
        return r;
    }

    private static Result save(Card_Journey__c j, Result r) {
        j.Fields_Done__c = BandhuJourneyService.fieldsDone(j);
        upsert j;
        r.journey = j;
        r.step = j.Step__c;
        return r;
    }

    public static Map<String, Object> tokens(Card_Journey__c j) {
        String first = String.isBlank(j.Customer_Name__c) ? '' : ' ' + j.Customer_Name__c.substringBefore(' ');
        String relationship = 'account';
        for (Bank_Relationship__c r : BandhuJourneyService.relationships(j.Contact__c)) {
            relationship = r.Relationship_Type__c.toLowerCase();
            break;
        }
        return new Map<String, Object>{
            'name' => first, 'fullname' => j.Customer_Name__c, 'mobile' => BandhuI18n.maskMobile(j.Mobile__c), 'otp' => BandhuConfig.get().Demo_OTP__c,
            'relationship' => relationship, 'card' => j.Chosen_Card__c, 'limit' => BandhuI18n.inr(j.Credit_Limit__c),
            'pan' => BandhuI18n.maskPan(j.PAN__c), 'dob' => BandhuI18n.formatDate(j.Date_Of_Birth__c),
            'city' => ((j.City__c == null ? '' : j.City__c) + ' ' + (j.PIN_Code__c == null ? '' : j.PIN_Code__c)).trim(),
            'employment' => j.Employment_Type__c + (String.isNotBlank(j.Company_Name__c) ? ' @ ' + j.Company_Name__c : ''),
            'income' => BandhuI18n.inr(j.Verified_Income__c != null ? j.Verified_Income__c : j.Monthly_Income__c),
            'kyc' => j.Customer_Type__c == BandhuJourneyService.EXISTING ? 'on file (existing customer)' : j.KYC_Status__c,
            'ref' => j.Reference_Number__c, 'alt' => j.Alternative_Card__c, 'link' => 'https://vkyc.bandhan.bank.in/demo/' + (j.Id == null ? '' : String.valueOf(j.Id).right(6)),
            'reason' => ''
        };
    }

    /** Card tiles for the web journey: eligibility and the recommended card highlighted. */
    private static List<CardView> cardViews(BandhuEligibility.Outcome out, Card_Journey__c j) {
        Map<String, BandhuEligibility.Option> byName = new Map<String, BandhuEligibility.Option>();
        if (out != null) {
            for (BandhuEligibility.Option o : out.options) {
                byName.put(o.card.DeveloperName, o);
            }
        }
        List<CardView> views = new List<CardView>();
        for (Bandhu_Card__mdt c : BandhuConfig.cards()) {
            CardView v = new CardView();
            v.name = c.DeveloperName;
            v.tagline = c.Tagline__c;
            v.color = c.Color__c;
            v.joiningFee = c.Joining_Fee__c == null ? 0 : c.Joining_Fee__c.intValue();
            v.rewards = c.Rewards__c;
            v.lounge = c.Lounge__c;
            v.welcome = c.Welcome__c;
            v.tierLabel = c.Tier_Label__c;
            v.tier = c.Tier__c == null ? 0 : c.Tier__c.intValue();
            v.secured = c.Secured__c == true;
            BandhuEligibility.Option o = byName.get(c.DeveloperName);
            v.eligible = o == null ? true : o.eligible;
            v.creditLimit = o == null || o.creditLimit == null ? null : BandhuI18n.inr(o.creditLimit);
            v.recommended = j != null && j.Recommended_Card__c == c.DeveloperName && out != null;
            views.add(v);
        }
        return views;
    }

    // ------------------------------------------------------------------ parsing
    public static Integer choiceNumber(String s) {
        if (String.isBlank(s)) {
            return null;
        }
        String t = s.trim().replace('1️⃣', '1').replace('2️⃣', '2').replace('3️⃣', '3').replace('4️⃣', '4').replace('5️⃣', '5').replace('6️⃣', '6')
            .replace('१', '1').replace('२', '2').replace('३', '3').replace('४', '4').replace('৫', '5').replace('১', '1').replace('২', '2')
            .replace('৩', '3').replace('৪', '4');
        Matcher m = Pattern.compile('^\\s*(?:option\\s*)?([1-9])(?![0-9a-z]).*$').matcher(t.toLowerCase());
        return m.matches() ? Integer.valueOf(m.group(1)) : null;
    }

    public static Set<String> parseFocus(String t) {
        Set<String> focus = new Set<String>();
        for (String n : t.replaceAll('[^1-6]', ' ').normalizeSpace().split(' ')) {
            if (String.isNotBlank(n) && n.length() == 1) {
                focus.add(BandhuEligibility.FOCUS[Integer.valueOf(n) - 1]);
            }
        }
        for (Integer i = 0; i < FOCUS_KEYWORDS.size(); i++) {
            if (Pattern.compile('(?i).*(' + FOCUS_KEYWORDS[i] + ').*').matcher(t).matches()) {
                focus.add(BandhuEligibility.FOCUS[i]);
            }
        }
        return focus;
    }

    public static Date parseDob(String s) {
        String t = s.trim();
        Matcher dmy = Pattern.compile('([0-9]{1,2})[\\s/.\\-]+([0-9]{1,2})[\\s/.\\-]+([0-9]{4})').matcher(t);
        Matcher iso = Pattern.compile('([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})').matcher(t);
        Integer d, m, y;
        if (iso.find()) {
            y = Integer.valueOf(iso.group(1));
            m = Integer.valueOf(iso.group(2));
            d = Integer.valueOf(iso.group(3));
        } else if (dmy.find()) {
            d = Integer.valueOf(dmy.group(1));
            m = Integer.valueOf(dmy.group(2));
            y = Integer.valueOf(dmy.group(3));
        } else {
            return null;
        }
        if (m < 1 || m > 12 || d < 1 || d > Date.daysInMonth(y, m) || y < 1920 || y > BandhuI18n.today().year()) {
            return null;
        }
        return Date.newInstance(y, m, d);
    }

    private static String titleCase(String s) {
        List<String> words = new List<String>();
        for (String w : s.toLowerCase().split(' ')) {
            words.add(w.capitalize());
        }
        return String.join(words, ' ');
    }

    public static String label(Card_Journey__c j) {
        return (String.isBlank(j.Customer_Name__c) ? BandhuI18n.maskMobile(j.Mobile__c) : j.Customer_Name__c);
    }

    public static String emoji(Integer n) {
        List<String> e = new List<String>{ '0️⃣', '1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣', '6️⃣', '7️⃣', '8️⃣', '9️⃣' };
        return n >= 0 && n < e.size() ? e[n] : String.valueOf(n);
    }
}
