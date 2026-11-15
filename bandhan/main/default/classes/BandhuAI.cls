/**
 * Generative AI in the Bandhu journey: Agentforce Prompt Builder templates (Setup > Prompt Builder: Bandhu Card Answer,
 * Bandhu Personal Note, Bandhu Underwriter Brief), run through the Einstein Trust Layer. Apex assembles the facts;
 * the templates hold the instructions, so they can be tuned in Prompt Builder without code.
 * AI writes; it never decides. Every credit decision stays with the rules (BandhuEligibility, BandhuDecision).
 *
 *   cardAnswer()       free-form questions about the cards, answered only from the card catalogue (web and WhatsApp)
 *   personalNote()     a short note in the customer's language: why the recommended card fits ('why') and how to earn
 *                      more on it ('tip'), from the same facts the rules used; it adds to the fact lines, never replaces them
 *   underwriterBrief() a summary of the application for the underwriter: strengths, concerns, a suggested decision
 *
 * Salesforce allows the LLM call only before any DML in the transaction: answers run at the start of a turn, the notes
 * as a follow-up (BandhuAIFollowUp on WhatsApp, a second call from the web page), the brief from a button.
 * Any failure returns null and the journey carries on with the rule-based text.
 */
public inherited sharing class BandhuAI {
    public static final String TEMPLATE_ANSWER = 'Bandhu_Card_Answer';
    public static final String TEMPLATE_NOTE = 'Bandhu_Personal_Note';
    public static final String TEMPLATE_BRIEF = 'Bandhu_Underwriter_Brief';
    @TestVisible private static String stub;          // tests: the LLM reply (null = the LLM is unavailable)

    /** Run a Prompt Builder template (Agentforce generative AI) with text inputs; null when unavailable. */
    public static String runTemplate(String template, Map<String, String> inputs) {
        if (Test.isRunningTest()) {
            lastTemplate = template;
            lastInputs = inputs;
            return stub;
        }
        try {
            ConnectApi.EinsteinPromptTemplateGenerationsInput inp = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            Map<String, ConnectApi.WrappedValue> params = new Map<String, ConnectApi.WrappedValue>();
            for (String k : inputs.keySet()) {
                ConnectApi.WrappedValue v = new ConnectApi.WrappedValue();
                v.value = inputs.get(k) == null ? '' : inputs.get(k);
                params.put('Input:' + k, v);
            }
            inp.inputParams = params;
            inp.isPreview = false;
            inp.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            inp.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation out = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(template, inp);
            String text = out == null || out.generations == null || out.generations.isEmpty() ? null : out.generations[0].text;
            // WhatsApp bold is *one* asterisk; drop markdown headings the model may add
            return String.isBlank(text) ? null : text.replace('**', '*').replaceAll('(?m)^#+\\s*', '').trim();
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Bandhu AI unavailable (' + template + '): ' + e.getMessage());
            return null;
        }
    }
    @TestVisible private static String lastTemplate;
    @TestVisible private static Map<String, String> lastInputs;

    private static String languageName(String lang) {
        return lang == BandhuI18n.HI ? 'Hindi (Devanagari script, the everyday Hinglish a bank chat uses: English words like card, income, limit are fine)'
            : lang == BandhuI18n.BN ? 'Bengali (Bengali script, everyday words; English words like card, income, limit are fine)' : 'English (Indian English)';
    }

    // ------------------------------------------------------------------ the card catalogue, as facts
    public static String cardFacts() {
        List<String> l = new List<String>();
        for (Bandhu_Card__mdt c : BandhuConfig.cards()) {
            l.add('=== CARD: Bandhan ' + c.DeveloperName + ' (' + c.Tier_Label__c + ') ===');
            l.add(c.DeveloperName + ' | about: ' + c.Tagline__c);
            l.add(c.DeveloperName + ' | fees: joining ₹' + (c.Joining_Fee__c == null ? 0 : c.Joining_Fee__c.intValue()) + ', annual ₹'
                + (c.Annual_Fee__c == null ? 0 : c.Annual_Fee__c.intValue()) + '; ' + c.Fee_Waiver__c);
            l.add(c.DeveloperName + ' | rewards: ' + c.Rewards__c + (String.isBlank(c.Accelerated__c) ? '' : '; ' + c.Accelerated__c));
            l.add(c.DeveloperName + ' | lounges: ' + c.Lounge__c);
            l.add(c.DeveloperName + ' | welcome: ' + c.Welcome__c + (String.isBlank(c.Milestone__c) ? '' : '; milestone: ' + c.Milestone__c));
            l.add(c.DeveloperName + ' | dining and movies: ' + (String.isBlank(c.Dining__c) ? 'none' : c.Dining__c) + '; ' + (String.isBlank(c.Movies__c) ? 'no movie offer' : c.Movies__c));
            l.add(c.DeveloperName + ' | fuel: ' + c.Fuel__c);
            if (String.isNotBlank(c.Extras__c)) {
                l.add(c.DeveloperName + ' | also: ' + c.Extras__c);
            }
            l.add(c.DeveloperName + ' | minimum net monthly income: ₹' + (c.Min_Monthly_Income__c == null ? 0 : c.Min_Monthly_Income__c.intValue()));
        }
        l.add('=== ALL CARDS ===');
        l.add('Cards work in India and abroad wherever the card network is accepted; international spends: see each card\'s rewards line.');
        l.add('Eligibility: age 21-60 salaried, 21-65 self-employed or business. CIBIL 750+ (Excellent) approves every card; 700-749 (Good) '
            + 'approves Sparks, Ignite and Flare, Lumina on review; 650-699 (Fair) every card on review; below 650 no card.');
        l.add('Applying is paperless: PAN, Aadhaar eKYC and a short Video KYC; income can be verified instantly through Account Aggregator. '
            + 'A virtual card is issued on approval; the physical card arrives in 5-7 working days. Reward points do not expire.');
        return String.join(l, '\n');
    }

    // ------------------------------------------------------------------ free-form questions
    public static String cardAnswer(String question, String lang) {
        return runTemplate(TEMPLATE_ANSWER, new Map<String, String>{
            'Question' => question.abbreviate(500), 'Language' => languageName(lang), 'Facts' => cardFacts() });
    }

    // ------------------------------------------------------------------ personal notes (follow-up messages)
    public static String personalNote(Card_Journey__c j, String kind) {
        String card = kind == 'tip' && j.Chosen_Card__c != null ? j.Chosen_Card__c : j.Recommended_Card__c;
        Bandhu_Card__mdt c = BandhuConfig.card(card);
        if (c == null) {
            return null;
        }
        String first = String.isBlank(j.Customer_Name__c) ? '' : j.Customer_Name__c.substringBefore(' ');
        BandhuCashFlow.Analysis cf = BandhuCashFlow.fromJourney(j);
        List<String> facts = new List<String>{
            'Customer first name: ' + first,
            'Card: Bandhan ' + c.DeveloperName + ' (' + c.Tier_Label__c + '): ' + c.Tagline__c,
            'Card benefits: ' + c.Rewards__c + (String.isBlank(c.Accelerated__c) ? '' : '; ' + c.Accelerated__c) + '; lounges: ' + c.Lounge__c
                + (String.isBlank(c.Dining__c) ? '' : '; dining: ' + c.Dining__c) + '; fuel: ' + c.Fuel__c + '; ' + c.Fee_Waiver__c
        };
        if (String.isNotBlank(j.Spend_Focus__c)) {
            facts.add('They said they spend on: ' + j.Spend_Focus__c.replace(';', ', '));
        }
        if (cf != null) {
            facts.add('Their bank statements show, per month: ' + cf.customerSpendText(BandhuI18n.EN)
                + (cf.tripsAbroad > 0 ? '; ' + cf.tripsAbroad + ' trips abroad in ' + cf.months + ' months' : ''));
        }
        String task;
        if (kind == 'tip') {
            BandhuRewards.Tip t = BandhuRewards.compute(cf, c);
            if (t == null) {
                return null;
            }
            List<String> rows = new List<String>();
            for (BandhuRewards.Line l : t.lines) {
                rows.add(l.category + ' ₹' + l.monthly.setScale(0) + ' a month earns ' + l.points + ' points');
            }
            facts.add('Moving these UPI / debit payments to the card: ' + String.join(rows, '; ') + '; about ' + t.points
                + ' points a month in total');
            task = 'Write a short, warm note suggesting the ONE OR TWO everyday payments ' + first + ' should move to the card first '
                + 'and what that earns. Start with "💡".';
        } else {
            task = 'Write a short, warm note telling ' + first + ' in their own terms why the Bandhan ' + c.DeveloperName
                + ' suits how they spend: connect their biggest spends to the card\'s matching benefits. Start with "✨".';
        }
        return runTemplate(TEMPLATE_NOTE, new Map<String, String>{
            'Task' => task, 'Language' => languageName(j.Language__c), 'Facts' => String.join(facts, '\n') });
    }

    // ------------------------------------------------------------------ underwriter brief
    public static String underwriterBrief(Id applicationId) {
        BandhuConsoleController.Review rv = BandhuConsoleController.getReview(applicationId);
        Card_Application__c a = rv.application;
        List<String> facts = new List<String>{
            'Applicant: ' + a.Applicant_Name__c + ', ' + (a.Customer_Type__c == 'Existing' ? 'existing Bandhan customer' : 'new to bank')
                + ', ' + a.Employment_Type__c + (String.isBlank(a.Company_Name__c) ? '' : ' at ' + a.Company_Name__c) + ', applied on ' + a.Channel__c,
            'Card applied for: ' + a.Card_Product__c + ', proposed limit ₹' + (a.Credit_Limit__c == null ? 0 : a.Credit_Limit__c.intValue())
                + ', declared income ₹' + (a.Monthly_Income__c == null ? 0 : a.Monthly_Income__c.intValue()) + '/month'
                + (a.Verified_Income__c == null ? '' : ', verified ₹' + a.Verified_Income__c.intValue() + '/month'),
            'CIBIL: ' + a.CIBIL_Score__c + ' (' + BandhuBureau.band(a.CIBIL_Score__c == null ? null : a.CIBIL_Score__c.intValue()) + ')',
            'Rule-based recommendation: ' + a.Recommendation__c + '. Reasons: ' + (a.Recommendation_Reasons__c == null ? '' : a.Recommendation_Reasons__c.replace('\n', ' | '))
        };
        for (BandhuConsoleController.Check c : rv.checks) {
            facts.add('Check ' + c.name + ': ' + c.result + ' - ' + c.summary);
        }
        if (rv.score != null) {
            List<String> fs = new List<String>();
            for (BandhuConsoleController.FactorRow f : rv.score.factors) {
                fs.add(f.name + ' ' + f.points + '/' + f.maxPoints + ' (' + f.value + ')');
            }
            facts.add('Bandhan Score ' + rv.score.score + '/1000, band ' + rv.score.band + ': ' + String.join(fs, '; '));
        }
        if (rv.cashFlow != null) {
            BandhuConsoleController.CashFlowView v = rv.cashFlow;
            facts.add('Bank statements (' + v.months + ' months, ' + v.banks + ' banks): net income ' + v.netIncome + ' (' + v.incomeSource + '), stability '
                + v.stability + '/100 ' + v.trend + ', EMIs ' + v.emi + ' (FOIR ' + v.foir + '%), surplus ' + v.surplus + ', outflow ' + v.outflow
                + ', card-able spend ' + v.cardSpend + (v.declaredSpend == null ? '' : ', declared card spend ' + v.declaredSpend)
                + '. Lifestyle: ' + String.join(v.lifestyle, '; ') + '. Flags: ' + (v.anomalies.isEmpty() ? 'none' : String.join(v.anomalies, '; '))
                + (v.spendGapFlag == null ? '' : '; ' + v.spendGapFlag));
        }
        return runTemplate(TEMPLATE_BRIEF, new Map<String, String>{ 'Facts' => String.join(facts, '\n') });
    }
}
