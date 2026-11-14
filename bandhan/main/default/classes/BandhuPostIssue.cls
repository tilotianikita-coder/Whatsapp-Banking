/**
 * After the decision: the system keeps learning and re-engaging.
 *   reassess()      declined / not-eligible journeys are re-checked when due (6 months after, then every 3 months):
 *                   a fresh soft pull (mock: each clean month since the last pull adds 6 points, up to 60) and the same
 *                   eligibility; if an unsecured card is now possible, the RM gets a task and the customer a WhatsApp.
 *   limitOffers()   cardholders 6+ months on book, activated, no missed payments and 40%+ utilisation are offered a
 *                   higher limit (x1.25, x1.5 at 70%+ use, within the card's maximum) or, at the maximum, the next card.
 *                   Nothing changes without the customer's explicit consent (RBI MD 2022): accept() records it.
 *   monitoring()    the scorecard's outcomes by band (activation, use, missed payments): the quarterly extract for
 *                   recalibrating the Bandhan Score (saved as a file once a quarter).
 * Behaviour data (utilisation, payments, spend) comes from the card management system; here it is mock fields.
 */
public inherited sharing class BandhuPostIssue {
    public static final Integer REASSESS_AFTER_DAYS = 180;
    public static final Integer REASSESS_AGAIN_DAYS = 90;

    public static void runDaily() {
        reassess();
        limitOffers();
        saveQuarterlyMonitoring();
    }

    public static void scheduleReassess(Card_Journey__c j) {
        j.Reassess_On__c = BandhuI18n.today().addDays(REASSESS_AFTER_DAYS);
        j.Reassess_Status__c = 'Pending';
    }

    // ------------------------------------------------------------------ re-approach
    public static Integer reassess() {
        Date today = BandhuI18n.today();
        List<Card_Journey__c> due = new List<Card_Journey__c>();
        for (Card_Journey__c d : [SELECT Id FROM Card_Journey__c WHERE Reassess_Status__c = 'Pending' AND Reassess_On__c <= :today LIMIT 20]) {
            due.add(BandhuJourneyService.byId(d.Id));
        }
        List<BandhuWhatsAppSender.Outbound> out = new List<BandhuWhatsAppSender.Outbound>();
        Integer eligible = 0;
        for (Card_Journey__c j : due) {
            if (String.isBlank(j.PAN__c)) {
                j.Reassess_Status__c = 'Still not eligible';
                continue;
            }
            Integer months = j.Bureau_At__c == null ? 6 : Math.max(0, j.Bureau_At__c.date().monthsBetween(today));
            BandhuBureau.Report before = BandhuBureau.fromJourney(j);
            BandhuBureau.Report now = BandhuBureau.pullAfterCleanMonths(j.PAN__c, months);
            BandhuBureau.apply(j, now);
            BandhuEligibility.Outcome o = BandhuEligibility.evaluate(BandhuJourneyService.profile(j));
            if (o.best != null && !o.best.refer) {
                eligible++;
                j.Reassess_Status__c = 'Eligible';
                j.Recommended_Card__c = o.best.card.DeveloperName;
                j.Credit_Limit__c = o.best.creditLimit;
                j.Eligible_Cards__c = String.join(o.eligibleNames(), ';');
                String why = 'CIBIL ' + (before == null || before.score == null ? '-' : String.valueOf(before.score)) + ' → ' + now.score
                    + ' after ' + months + ' months of clean repayment';
                BandhuLeadService.rmTask(j, 'Bandhu: re-approach - now eligible for ' + o.best.card.DeveloperName + ' - ' + j.Customer_Name__c,
                    why + '\nEligible now: ' + String.join(o.eligibleNames(), ', ') + '\nBandhan Score ' + o.score.score + ' (band ' + o.score.band + ')');
                String first = String.isBlank(j.Customer_Name__c) ? '' : ' ' + j.Customer_Name__c.substringBefore(' ');
                out.add(new BandhuWhatsAppSender.Outbound(j.Id, BandhuI18n.msg('Reapproach', j.Language__c, new Map<String, Object>{
                    'name' => first, 'card' => o.best.card.DeveloperName, 'limit' => BandhuI18n.inr(o.best.creditLimit) }), null));
            } else {
                j.Reassess_On__c = today.addDays(REASSESS_AGAIN_DAYS);
            }
        }
        update due;
        if (!out.isEmpty()) {
            BandhuWhatsAppSender.enqueue(out);
        }
        return eligible;
    }

    // ------------------------------------------------------------------ limit enhancement
    public static Integer limitOffers() {
        Datetime sixMonths = Datetime.now().addDays(-180);
        List<Card_Application__c> apps = [
            SELECT Id, Card_Journey__c, Card_Product__c, Credit_Limit__c, Monthly_Income__c, Verified_Income__c, Avg_Utilisation_Pct__c,
                Limit_Offer__c, Upgrade_Offer_Card__c, Limit_Offer_Status__c, Limit_Offer_At__c
            FROM Card_Application__c
            WHERE Status__c = 'Card Issued' AND Activated_At__c != null AND Card_Issued_At__c <= :sixMonths AND Missed_Payments__c = 0
                AND Avg_Utilisation_Pct__c >= 40 AND Limit_Offer_Status__c = null LIMIT 50
        ];
        List<Card_Journey__c> journeys = new List<Card_Journey__c>();
        List<BandhuWhatsAppSender.Outbound> out = new List<BandhuWhatsAppSender.Outbound>();
        for (Card_Application__c a : apps) {
            offer(a);
            if (a.Card_Journey__c != null) {
                Card_Journey__c j = BandhuJourneyService.byId(a.Card_Journey__c);
                j.Status__c = BandhuJourneyService.STATUS_ACTIVE;
                j.Step__c = 'limit_offer';
                journeys.add(j);
                out.add(new BandhuWhatsAppSender.Outbound(j.Id, offerMessage(j, a), null));
            }
        }
        update apps;
        update journeys;
        if (!out.isEmpty()) {
            BandhuWhatsAppSender.enqueue(out);
        }
        return apps.size();
    }

    @TestVisible
    private static void offer(Card_Application__c a) {
        Bandhu_Card__mdt c = BandhuConfig.card(a.Card_Product__c);
        Decimal factor = a.Avg_Utilisation_Pct__c >= 70 ? 1.5 : 1.25;
        Decimal max = c == null || c.Limit_Max__c == null ? a.Credit_Limit__c * factor : c.Limit_Max__c;
        Decimal raised = Math.floor(Math.min(max, a.Credit_Limit__c * factor) / 5000) * 5000;
        a.Limit_Offer_Status__c = 'Offered';
        a.Limit_Offer_At__c = Datetime.now();
        if (raised > a.Credit_Limit__c) {
            a.Limit_Offer__c = raised;
            return;
        }
        // at the card's maximum: the next card up the customer's income supports
        Decimal income = a.Verified_Income__c != null ? a.Verified_Income__c : a.Monthly_Income__c;
        for (Bandhu_Card__mdt next : BandhuConfig.cards()) {
            if (next.Secured__c != true && c != null && next.Tier__c > c.Tier__c && income != null && income >= next.Min_Monthly_Income__c
                    && a.Upgrade_Offer_Card__c == null) {
                a.Upgrade_Offer_Card__c = next.DeveloperName;
                a.Limit_Offer__c = Math.max(a.Credit_Limit__c, BandhuEligibility.limitFor(next, income));
            }
        }
        if (a.Upgrade_Offer_Card__c == null) {
            a.Limit_Offer_Status__c = null;
            a.Limit_Offer_At__c = null;
        }
    }

    public static String offerMessage(Card_Journey__c j, Card_Application__c a) {
        String first = String.isBlank(j.Customer_Name__c) ? '' : ' ' + j.Customer_Name__c.substringBefore(' ');
        return BandhuI18n.msg(a.Upgrade_Offer_Card__c != null ? 'Upgrade_Offer' : 'Limit_Offer', j.Language__c, new Map<String, Object>{
            'name' => first, 'card' => a.Card_Product__c, 'upgrade' => a.Upgrade_Offer_Card__c,
            'old' => BandhuI18n.inr(a.Credit_Limit__c), 'limit' => BandhuI18n.inr(a.Limit_Offer__c) });
    }

    /** The customer's explicit consent to the offer (RBI MD 2022): only then does the limit or card change. */
    public static Card_Application__c respond(Card_Journey__c j, Boolean accepted) {
        Card_Application__c a = [SELECT Id, Card_Product__c, Credit_Limit__c, Limit_Offer__c, Upgrade_Offer_Card__c, Limit_Offer_Status__c
                                 FROM Card_Application__c WHERE Id = :j.Card_Application__c];
        if (a.Limit_Offer_Status__c != 'Offered') {
            return a;
        }
        a.Limit_Offer_Status__c = accepted ? 'Accepted' : 'Declined';
        if (accepted) {
            String change = (a.Upgrade_Offer_Card__c != null ? 'Upgrade ' + a.Card_Product__c + ' → ' + a.Upgrade_Offer_Card__c + ', limit ' : 'Limit ')
                + BandhuI18n.inr(a.Credit_Limit__c) + ' → ' + BandhuI18n.inr(a.Limit_Offer__c);
            if (a.Upgrade_Offer_Card__c != null) {
                a.Card_Product__c = a.Upgrade_Offer_Card__c;
            }
            a.Credit_Limit__c = a.Limit_Offer__c;
            BandhuCompliance.record(j, 'Limit enhancement', change, 'OFFER-' + a.Id, null, offerMessage(j, a));
        }
        update a;
        j.Status__c = BandhuJourneyService.STATUS_COMPLETED;
        j.Step__c = 'done';
        return a;
    }

    // ------------------------------------------------------------------ model monitoring
    public class BandRow {
        public String band;
        public Integer applications = 0;
        public Integer issued = 0;
        public Integer activated = 0;
        public Integer withMissedPayments = 0;
        public Decimal avgUtilisation = 0;
    }

    public static List<BandRow> monitoring() {
        Map<String, BandRow> rows = new Map<String, BandRow>();
        for (String b : new List<String>{ 'A', 'B', 'C', 'D' }) {
            BandRow r = new BandRow();
            r.band = b;
            rows.put(b, r);
        }
        Map<String, Decimal> utilSum = new Map<String, Decimal>();
        Map<String, Integer> utilN = new Map<String, Integer>();
        for (Card_Application__c a : [SELECT Score_Band__c, Status__c, Activated_At__c, Missed_Payments__c, Avg_Utilisation_Pct__c, Card_Issued_At__c
                                      FROM Card_Application__c WHERE Score_Band__c != null LIMIT 50000]) {
            BandRow r = rows.get(a.Score_Band__c);
            if (r == null) {
                continue;
            }
            r.applications++;
            if (a.Card_Issued_At__c != null) {
                r.issued++;
            }
            if (a.Activated_At__c != null) {
                r.activated++;
            }
            if (a.Missed_Payments__c != null && a.Missed_Payments__c > 0) {
                r.withMissedPayments++;
            }
            if (a.Avg_Utilisation_Pct__c != null) {
                utilSum.put(r.band, (utilSum.containsKey(r.band) ? utilSum.get(r.band) : 0) + a.Avg_Utilisation_Pct__c);
                utilN.put(r.band, (utilN.containsKey(r.band) ? utilN.get(r.band) : 0) + 1);
            }
        }
        for (BandRow r : rows.values()) {
            r.avgUtilisation = utilN.containsKey(r.band) ? (utilSum.get(r.band) / utilN.get(r.band)).setScale(1) : 0;
        }
        return rows.values();
    }

    public static String monitoringCsv() {
        List<String> lines = new List<String>{ 'model,band,applications,issued,activated,with_missed_payments,avg_utilisation_pct' };
        for (BandRow r : monitoring()) {
            lines.add(String.join(new List<String>{ BandhuScore.MODEL_VERSION, r.band, String.valueOf(r.applications), String.valueOf(r.issued),
                String.valueOf(r.activated), String.valueOf(r.withMissedPayments), String.valueOf(r.avgUtilisation) }, ','));
        }
        return String.join(lines, '\n');
    }

    /** One monitoring file per quarter (for the quarterly recalibration of the scorecard). */
    public static Id saveQuarterlyMonitoring() {
        Date today = BandhuI18n.today();
        String title = 'Bandhu scorecard monitoring ' + today.year() + '-Q' + ((today.month() - 1) / 3 + 1);
        if (![SELECT Id FROM ContentVersion WHERE Title = :title AND IsLatest = true LIMIT 1].isEmpty()) {
            return null;
        }
        ContentVersion v = new ContentVersion(Title = title, PathOnClient = title + '.csv', VersionData = Blob.valueOf(monitoringCsv()));
        insert v;
        return v.Id;
    }
}
