/**
 * Requests that work at any step of a journey and don't move it on: the EMI calculator ("EMI 3 lakh 36 months")
 * and application status ("Status", "where is my application"). Each answer ends with the pending question,
 * so the customer carries on where they were. Called from LoanSevaEngine.reply and answerFaq.
 */
public with sharing class LoanSevaShortcuts {
    /** "EMI", "EMIs", "calculate", ईएमआई, किस्त, हप्ता. */
    private static final Pattern EMI = Pattern.compile('(?i).*(\\bemis?\\b|\\bcalculat\\w*|ईएमआई|किस्त|हप्ता|हफ्ता).*');

    /** "Status", "track my loan", "where is my application", आवेदन की स्थिति, अर्जाची स्थिती. */
    private static final Pattern STATUS = Pattern.compile(
        '(?i).*(\\b(status|track|tracking)\\b|where is my (application|loan)|application update'
        + '|स्टेटस|स्थिति|स्थिती|आवेदन कहाँ|अर्ज कुठे).*');

    /**
     * States where the reply is the answer itself: free text that could contain the word ("Status Infotech" as a
     * company), or an amount/EMI the journey asked for ("my EMIs are 5000" at obligations; "3 lakh for 48 months"
     * re-prices the offer at offer_decision). An OTP, date or PAN can never read as "status" or "EMI 3 lakh".
     */
    private static final Set<String> SKIP_EMI = new Set<String>{ 'company', 'income', 'obligations', 'offer_decision', 'feedback_comment' };
    private static final Set<String> SKIP_STATUS = new Set<String>{ 'company', 'feedback_comment' };

    /** Any whole-month tenure a customer might ask the calculator about, not just the offered ones. */
    private static final Integer MIN_CALC_MONTHS = 6;
    private static final Integer MAX_CALC_MONTHS = 84;

    private static final Decimal MIN_EMI_AMOUNT = 10000;

    /** The shortcut's answer, or null if the message isn't one. */
    public static LoanSevaEngine.Result handle(Loan_Journey__c j, String text) {
        if (j == null || String.isBlank(text)) {
            return null;
        }
        String t = text.replace('\n', ' ').trim();
        String state = LoanSevaEngine.awaiting(j);
        if (state == 'email' && t.contains('@')) {
            return null;
        }
        if (!SKIP_EMI.contains(state) && EMI.matcher(t).matches()) {
            LoanSevaEngine.Result r = emi(j, t);
            if (r != null) {
                return r;
            }
        }
        if (!SKIP_STATUS.contains(state) && STATUS.matcher(t).matches()) {
            return status(j);
        }
        return null;
    }

    // ------------------------------------------------------------------ EMI calculator
    private static LoanSevaEngine.Result emi(Loan_Journey__c j, String t) {
        String tenureText = LoanSevaEngine.tenurePhrase(t);
        Decimal amount = LoanSevaEngine.parseAmount(tenureText == null ? t : t.replace(tenureText, ' '));
        if (amount == null || amount < MIN_EMI_AMOUNT) {
            return null;
        }
        String lang = j.Language__c;
        Decimal rate = rate(j);
        List<Integer> tenures = LoanSevaConfig.tenureOptions();
        Integer tenure = anyTenure(tenureText);
        if (tenure != null && !tenures.contains(tenure)) {
            tenures.add(tenure);
            tenures.sort();
        }
        if (tenure == null && j.Offer_Tenure_Months__c != null && tenures.contains(j.Offer_Tenure_Months__c.intValue())) {
            tenure = j.Offer_Tenure_Months__c.intValue();
        }
        if (tenure == null) {
            tenure = Integer.valueOf(LoanSevaConfig.get().Default_Tenure__c);
        }
        List<String> rows = new List<String>();
        for (Integer months : tenures) {
            String row = LoanSevaI18n.msg('Emi_Row', lang, new Map<String, Object>{
                'tenure' => months,
                'emi' => LoanSevaI18n.inr(LoanSevaEligibilityEngine.emi(amount, rate, months))
            });
            rows.add(months == tenure ? '👉 *' + row + '*' : '▫️ ' + row);
        }
        Decimal monthly = LoanSevaEligibilityEngine.emi(amount, rate, tenure);
        String message = LoanSevaI18n.msg('Emi_Calc', lang, new Map<String, Object>{
            'amount' => LoanSevaI18n.inr(amount),
            'rate' => rate.setScale(2).toPlainString(),
            'rows' => String.join(rows, '\n'),
            'tenure' => tenure,
            'emi' => LoanSevaI18n.inr(monthly),
            'interest' => LoanSevaI18n.inr(monthly * tenure - amount),
            'total' => LoanSevaI18n.inr(monthly * tenure)
        });
        return finish(j, message);
    }

    /** "40 months" is 40, "2 yrs" is 24; outside 6–84 months is ignored. */
    private static Integer anyTenure(String tenureText) {
        if (tenureText == null) {
            return null;
        }
        Matcher m = Pattern.compile('(?i)([0-9]+)\\s*(month|months|mo|mth|mths|महीने|महिने)?').matcher(tenureText);
        if (!m.find()) {
            return null;
        }
        Integer n = Integer.valueOf(m.group(1));
        Integer months = m.group(2) != null ? n : n * 12;
        return months >= MIN_CALC_MONTHS && months <= MAX_CALC_MONTHS ? months : null;
    }

    /** The customer's offer rate once priced; before that the starting rate for their product and employment type. */
    private static Decimal rate(Loan_Journey__c j) {
        if (j.Offer_Rate__c != null) {
            return j.Offer_Rate__c;
        }
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        Decimal rate = cfg.Base_Rate__c;
        if (LoanSevaJourneyService.isNewLoan(j)) {
            rate += cfg.New_Loan_Rate_Premium__c;
        }
        if (j.Employment_Type__c == 'Self-employed') {
            rate += cfg.Self_Employed_Premium__c;
        }
        return rate;
    }

    // ------------------------------------------------------------------ Status tracker
    private static LoanSevaEngine.Result status(Loan_Journey__c j) {
        String lang = j.Language__c;
        Loan_Application__c app = latestApplication(j);
        if (app == null) {
            return finish(j, LoanSevaI18n.msg('Status_None', lang));
        }
        Boolean newLoan = app.Application_Type__c == LoanSevaJourneyService.TYPE_NEW_LOAN;
        String steps = newLoan ? newLoanSteps(app, lang) : topUpSteps(app, lang);
        Decimal amount = app.Offer_Amount__c != null ? app.Offer_Amount__c : app.Requested_Amount__c;
        String message = LoanSevaI18n.msg('Status_Card', lang, new Map<String, Object>{
            'ref' => String.isBlank(app.Reference_Number__c) ? '' : ' · ```' + app.Reference_Number__c + '```',
            'product' => app.Product__c,
            'amount' => LoanSevaI18n.inr(amount),
            'steps' => steps
        });
        String note = outcome(app, newLoan, lang);
        if (String.isNotBlank(note)) {
            message += '\n\n' + note;
        }
        return finish(j, message);
    }

    /**
     * The latest application on this journey, this customer or this WhatsApp number; a submitted one first,
     * so a fresh unpriced journey doesn't hide the application the customer is waiting on.
     */
    private static Loan_Application__c latestApplication(Loan_Journey__c j) {
        Set<Id> ids = new Set<Id>();
        Set<Id> contacts = new Set<Id>();
        Set<String> mobiles = new Set<String>();
        if (j.Loan_Application__c != null) {
            ids.add(j.Loan_Application__c);
        }
        if (j.Contact__c != null) {
            contacts.add(j.Contact__c);
        }
        if (String.isNotBlank(j.Mobile__c)) {
            mobiles.add(j.Mobile__c);
        }
        List<Loan_Application__c> apps = [
            SELECT Id, Application_Type__c, Product__c, Status__c, Reference_Number__c, Offer_Amount__c, Requested_Amount__c,
                Submitted_At__c, Underwriting_Status__c, Decision__c, Callback_DateTime__c, Loan_Account__r.Masked_Account__c,
                (SELECT Status__c FROM Loan_Documents__r)
            FROM Loan_Application__c
            WHERE Id IN :ids OR Contact__c IN :contacts OR Loan_Journey__r.Mobile__c IN :mobiles
            ORDER BY Submitted_At__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 1
        ];
        return apps.isEmpty() ? null : apps[0];
    }

    private static final String DONE = '✅';
    private static final String ACTIVE = '🔄';
    private static final String WAITING = '⚪';

    private static String newLoanSteps(Loan_Application__c app, String lang) {
        Boolean submitted = app.Submitted_At__c != null;
        Integer received = app.Loan_Documents__r.size();
        Integer verified = 0;
        Integer rejected = 0;
        for (Loan_Document__c d : app.Loan_Documents__r) {
            verified += d.Status__c == 'Verified' ? 1 : 0;
            rejected += d.Status__c == 'Rejected' ? 1 : 0;
        }
        String decision = app.Decision__c;
        Boolean decided = decision == LoanSevaDecisionService.APPROVED || decision == LoanSevaDecisionService.REJECTED;
        Boolean checked = app.Underwriting_Status__c == 'Completed';
        return LoanSevaI18n.msg('Status_Steps_New', lang, new Map<String, Object>{
            's1' => submitted ? DONE : ACTIVE,
            's2' => rejected > 0 ? '⚠️' : received > 0 && verified == received ? DONE : received > 0 ? ACTIVE : WAITING,
            'docs' => received == 0 ? '' : ' ' + LoanSevaI18n.msg('Status_Docs', lang, new Map<String, Object>{ 'received' => received, 'verified' => verified }),
            's3' => checked ? DONE : submitted ? ACTIVE : WAITING,
            's4' => decided ? DONE : decision == LoanSevaDecisionService.REFERRED ? '📝' : checked ? ACTIVE : WAITING,
            's5' => decision == LoanSevaDecisionService.APPROVED ? DONE : decision == LoanSevaDecisionService.REJECTED ? '❌' : WAITING
        });
    }

    private static String topUpSteps(Loan_Application__c app, String lang) {
        Boolean priced = app.Offer_Amount__c != null;
        Boolean accepted = String.isNotBlank(app.Reference_Number__c);
        Boolean booked = app.Callback_DateTime__c != null;
        return LoanSevaI18n.msg('Status_Steps_TopUp', lang, new Map<String, Object>{
            's1' => priced ? DONE : ACTIVE,
            's2' => accepted ? DONE : priced ? ACTIVE : WAITING,
            's3' => booked ? DONE : accepted ? ACTIVE : WAITING,
            'when' => booked ? ' · ' + LoanSevaI18n.formatDateTime(app.Callback_DateTime__c) : '',
            's4' => booked ? ACTIVE : WAITING
        });
    }

    private static String outcome(Loan_Application__c app, Boolean newLoan, String lang) {
        if (app.Decision__c == LoanSevaDecisionService.APPROVED) {
            return LoanSevaI18n.msg('Status_Approved', lang, new Map<String, Object>{ 'lan' => app.Loan_Account__r?.Masked_Account__c });
        }
        if (app.Decision__c == LoanSevaDecisionService.REJECTED) {
            return LoanSevaI18n.msg('Status_Rejected', lang);
        }
        if (app.Decision__c == LoanSevaDecisionService.REFERRED) {
            return LoanSevaI18n.msg('Status_Referred', lang);
        }
        if (newLoan) {
            return LoanSevaI18n.msg(app.Submitted_At__c == null ? 'Status_Not_Submitted' : 'Status_In_Review', lang);
        }
        return '';
    }

    // ------------------------------------------------------------------ Shared
    /** Appends the pending question (or the menu nudge) so the next reply still answers the step the customer was on. */
    private static LoanSevaEngine.Result finish(Loan_Journey__c j, String message) {
        String state = LoanSevaEngine.awaiting(j);
        if (state == 'menu') {
            message += '\n\n' + LoanSevaI18n.msg('FAQ_Nudge', j.Language__c);
        } else if (state != 'done' && state != 'handoff') {
            String pending = LoanSevaEngine.pendingPrompt(j, false);
            if (String.isNotBlank(pending)) {
                message += '\n\n' + LoanSevaI18n.msg('Resume_Prompt', j.Language__c) + '\n' + pending;
            }
        }
        j.Question_Pending__c = false;
        LoanSevaJourneyService.touch(j);
        update j;
        return LoanSevaEngine.result(j, message);
    }
}
