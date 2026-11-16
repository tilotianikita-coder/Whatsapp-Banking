/**
 * The RM's Bandhu leads dashboard (the Leads tab): how many prospects start the card journey, how far they get, where
 * the open leads stopped, why leads were knocked out, and the leads to work, each one a link to its Lead page.
 *
 *   journeys  Card_Journey__c started in the period (new-to-bank and existing customers, every channel): the funnel
 *   leads     Leads with LeadSource 'Bandhu Card Journey' (new to bank) in the period: ratings, drop points, gates
 *   gates     Bandhu_Lead_Check__c knock-outs on those leads: the gate and the reason
 */
public with sharing class BandhuLeadDashboard {
    public static final List<String> FUNNEL = new List<String>{
        'Started', 'Mobile verified', 'Income & statements', 'Needs', 'Credit check', 'Recommendation', 'KYC', 'Submitted', 'Card issued' };
    public static final List<String> CIBIL_BANDS = new List<String>{ 'Excellent (750+)', 'Good (700-749)', 'Fair (650-699)', 'Poor (below 650)', 'No score yet' };

    public class Item {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Integer count = 0;
        @AuraEnabled public String note;
        Item(String key, String label) {
            this.key = key;
            this.label = label;
        }
    }

    public class Kpi {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String sub;
        Kpi(String key, String label, String value, String sub) {
            this.key = key;
            this.label = label;
            this.value = value;
            this.sub = sub;
        }
    }

    public class Row {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String rating;
        @AuraEnabled public String status;
        @AuraEnabled public String stageGate;
        @AuraEnabled public String stoppedAt;     // the step the lead is at / dropped at (no details count)
        @AuraEnabled public String stage;         // the journey stage of that step (the path on the Lead page)
        @AuraEnabled public String knockoutGate;
        @AuraEnabled public String knockoutReason;
        @AuraEnabled public String outcome;       // Open / Knocked out / Card issued
        @AuraEnabled public String card;
        @AuraEnabled public Decimal combined;
        @AuraEnabled public Decimal intent;
        @AuraEnabled public Decimal credit;
        @AuraEnabled public Decimal cibil;
        @AuraEnabled public String cibilBand;
        @AuraEnabled public String region;
        @AuraEnabled public String channel;
        @AuraEnabled public String mobile;
        @AuraEnabled public Datetime lastActivity;
        @AuraEnabled public Datetime lastNudged;
        @AuraEnabled public Datetime created;
    }

    public class Dashboard {
        @AuraEnabled public List<Kpi> kpis = new List<Kpi>();
        @AuraEnabled public List<Item> funnel = new List<Item>();
        @AuraEnabled public List<Item> dropOffs = new List<Item>();
        @AuraEnabled public List<Item> knockouts = new List<Item>();
        @AuraEnabled public List<Item> ratings = new List<Item>();
        @AuraEnabled public List<Item> channels = new List<Item>();
        @AuraEnabled public List<Item> regions = new List<Item>();
        @AuraEnabled public List<Item> cards = new List<Item>();
        @AuraEnabled public List<Item> cibil = new List<Item>();
        @AuraEnabled public List<Item> trend = new List<Item>();   // journeys started a day (key yyyy-MM-dd), last 14 or 30 days
        @AuraEnabled public List<Row> leads = new List<Row>();
        @AuraEnabled public Integer journeys = 0;
        @AuraEnabled public Datetime asOf;
    }

    /** days: 7 / 30 / 90, or 0 for all time. channel: WhatsApp / Web / Branch, or blank for all. */
    @AuraEnabled
    public static Dashboard getDashboard(Integer days, String channel) {
        Dashboard d = new Dashboard();
        d.asOf = Datetime.now();
        Datetime since = days == null || days <= 0 ? Datetime.newInstance(2000, 1, 1) : Datetime.now().addDays(-days);
        Boolean anyChannel = String.isBlank(channel);

        // ---------------------------------------------------------------- the funnel, from every journey
        Map<String, Item> stages = items(FUNNEL);
        Integer submitted = 0;
        Integer issued = 0;
        Integer trendDays = days != null && days > 0 && days <= 14 ? 14 : 30;
        Map<String, Item> trend = new Map<String, Item>();
        Date today = BandhuI18n.today();
        for (Integer k = trendDays - 1; k >= 0; k--) {
            Date dt = today.addDays(-k);
            String key = Datetime.newInstance(dt, Time.newInstance(12, 0, 0, 0)).format('yyyy-MM-dd');
            Item t = new Item(key, Datetime.newInstance(dt, Time.newInstance(12, 0, 0, 0)).format('d MMM'));
            trend.put(key, t);
        }
        for (Card_Journey__c j : [
            SELECT Id, Status__c, Step__c, Stage__c, OTP_Verified__c, Card_Application__c, Card_Application__r.Status__c, Channel__c,
                Consent_At__c, CreatedDate
            FROM Card_Journey__c ORDER BY CreatedDate DESC LIMIT 5000
        ]) {
            if (started(j) < since || (!anyChannel && j.Channel__c != channel)) {
                continue;
            }
            d.journeys++;
            String day = started(j).format('yyyy-MM-dd', BandhuI18n.TIMEZONE);
            if (trend.containsKey(day)) {
                trend.get(day).count++;
            }
            Integer idx = BandhuConsoleController.pathIndex(j);
            Boolean isIssued = j.Stage__c == 'Issued' || (j.Card_Application__r != null && j.Card_Application__r.Status__c == 'Card Issued');
            Boolean verified = j.OTP_Verified__c || idx >= 1 || j.Card_Application__c != null;
            bump(stages, 'Started');
            if (verified) {
                bump(stages, 'Mobile verified');
            }
            for (Integer s = 1; s <= 6; s++) {
                if (idx >= s) {
                    bump(stages, FUNNEL[s + 1]);
                }
            }
            if (idx >= 6) {
                submitted++;
            }
            if (isIssued) {
                bump(stages, 'Card issued');
                issued++;
            }
        }
        d.funnel = stages.values();
        d.trend = trend.values();
        Integer prev = null;
        for (Item i : d.funnel) {
            i.note = prev == null ? null : prev == 0 ? '' : (prev - i.count) + ' lost (' + pct(prev - i.count, prev) + '%)';
            prev = i.count;
        }

        // ---------------------------------------------------------------- the leads (new to bank)
        Map<String, Item> ratings = items(new List<String>{ 'Hot', 'Warm', 'Cold' });
        Map<String, Item> dropOffs = items(BandhuConsoleController.PATH);
        Map<String, Map<String, Integer>> stepsByStage = new Map<String, Map<String, Integer>>();
        Map<String, Item> channels = items(new List<String>{ 'WhatsApp', 'Web', 'Branch' });
        Map<String, Item> regions = new Map<String, Item>();
        Map<String, Item> cards = new Map<String, Item>();
        Map<String, Item> cibil = items(CIBIL_BANDS);
        Integer knockedOut = 0;
        Integer qualified = 0;
        Integer nudged = 0;
        Decimal scoreSum = 0;
        Integer scored = 0;
        List<Lead> leads = [
            SELECT Id, Name, Status, Rating, MobilePhone, CreatedDate, Bandhu_Stage_Gate__c, Bandhu_Drop_Point__c, Bandhu_Recommended_Card__c,
                Bandhu_Combined_Score__c, Bandhu_Intent_Score__c, Bandhu_Credit_Score__c, Bandhu_CIBIL__c, Bandhu_Region__c, Bandhu_Last_Nudged__c,
                Bandhu_Journey__r.Channel__c, Bandhu_Journey__r.Last_Activity__c, Bandhu_Journey__r.Status__c, Bandhu_Journey__r.Step__c,
                Bandhu_Journey__r.Stage__c, Bandhu_Journey__r.Card_Application__r.Status__c, Bandhu_Journey__r.Consent_At__c,
                Bandhu_Journey__r.CreatedDate, Bandhu_Journey__r.Card_Application__c
            FROM Lead WHERE LeadSource = :BandhuLeadService.SOURCE AND IsConverted = false
            ORDER BY Bandhu_Combined_Score__c DESC NULLS LAST, CreatedDate DESC LIMIT 2000
        ];
        Map<Id, Bandhu_Lead_Check__c> knockByLead = new Map<Id, Bandhu_Lead_Check__c>();
        for (Bandhu_Lead_Check__c c : [SELECT Lead__c, Gate__c, Summary__c FROM Bandhu_Lead_Check__c
                                       WHERE Lead__c IN :leads AND Knockout__c = true ORDER BY Sort_Order__c]) {
            if (!knockByLead.containsKey(c.Lead__c)) {
                knockByLead.put(c.Lead__c, c);
            }
        }
        Map<String, Item> knockouts = new Map<String, Item>();
        Map<String, Set<String>> reasons = new Map<String, Set<String>>();
        for (Lead l : leads) {
            String ch = l.Bandhu_Journey__r == null ? null : l.Bandhu_Journey__r.Channel__c;
            Datetime start = l.Bandhu_Journey__r == null ? l.CreatedDate : started(l.Bandhu_Journey__r);
            if (start < since || (!anyChannel && ch != channel)) {
                continue;
            }
            Row r = new Row();
            r.id = l.Id;
            r.name = l.Name;
            r.rating = String.isBlank(l.Rating) ? 'Cold' : l.Rating;
            r.status = l.Status;
            r.stageGate = l.Bandhu_Stage_Gate__c;
            r.card = l.Bandhu_Recommended_Card__c;
            r.combined = l.Bandhu_Combined_Score__c;
            r.intent = l.Bandhu_Intent_Score__c;
            r.credit = l.Bandhu_Credit_Score__c;
            r.cibil = l.Bandhu_CIBIL__c;
            r.cibilBand = cibilBand(l.Bandhu_CIBIL__c);
            r.region = String.isBlank(l.Bandhu_Region__c) ? 'Not shared yet' : l.Bandhu_Region__c;
            r.channel = ch;
            r.mobile = BandhuI18n.maskMobile(l.MobilePhone);
            r.created = start;
            r.lastActivity = l.Bandhu_Journey__r == null ? null : l.Bandhu_Journey__r.Last_Activity__c;
            r.lastNudged = l.Bandhu_Last_Nudged__c;
            r.stoppedAt = stopLabel(l.Bandhu_Drop_Point__c);
            Bandhu_Lead_Check__c ko = knockByLead.get(l.Id);
            Card_Journey__c j = l.Bandhu_Journey__r;
            Boolean isIssued = l.Bandhu_Drop_Point__c == 'Card issued' || (j != null && (j.Stage__c == 'Issued'
                || (j.Card_Application__r != null && j.Card_Application__r.Status__c == 'Card Issued')));
            if (ko != null) {
                r.outcome = 'Knocked out';
                r.knockoutGate = ko.Gate__c;
                r.knockoutReason = ko.Summary__c;
                knockedOut++;
                if (!knockouts.containsKey(ko.Gate__c)) {
                    knockouts.put(ko.Gate__c, new Item(ko.Gate__c, ko.Gate__c));
                    reasons.put(ko.Gate__c, new Set<String>());
                }
                knockouts.get(ko.Gate__c).count++;
                reasons.get(ko.Gate__c).add(reason(ko.Summary__c));
            } else if (isIssued) {
                r.outcome = 'Card issued';
                r.stoppedAt = 'Card issued';
            } else if (j != null && j.Card_Application__r != null) {
                r.outcome = 'With underwriting';
                r.stoppedAt = 'Application ' + j.Card_Application__r.Status__c.toLowerCase();
            } else {
                r.outcome = 'Open';
                r.stage = j == null ? BandhuConsoleController.PATH[0] : BandhuConsoleController.PATH[BandhuConsoleController.pathIndex(j)];
                bump(dropOffs, r.stage);
                String step = r.stoppedAt == null ? 'Not started' : r.stoppedAt;
                if (!stepsByStage.containsKey(r.stage)) {
                    stepsByStage.put(r.stage, new Map<String, Integer>());
                }
                Map<String, Integer> steps = stepsByStage.get(r.stage);
                steps.put(step, (steps.containsKey(step) ? steps.get(step) : 0) + 1);
            }
            if (l.Bandhu_Stage_Gate__c == 'Qualified') {
                qualified++;
            }
            if (l.Bandhu_Last_Nudged__c != null) {
                nudged++;
            }
            if (l.Bandhu_Combined_Score__c != null) {
                scoreSum += l.Bandhu_Combined_Score__c;
                scored++;
            }
            bump(ratings, r.rating);
            if (ch != null) {
                bump(channels, ch);
            }
            bumpNew(regions, r.region);
            if (String.isNotBlank(r.card)) {
                bumpNew(cards, r.card);
            }
            bump(cibil, r.cibilBand);
            d.leads.add(r);
        }
        for (Item i : knockouts.values()) {
            i.note = String.join(new List<String>(reasons.get(i.key)), ' · ');
        }
        d.ratings = ratings.values();
        d.channels = channels.values();
        d.cibil = cibil.values();
        // the stages in journey order (where the leak is), the steps inside each stage in the tooltip
        for (Item i : dropOffs.values()) {
            Map<String, Integer> steps = stepsByStage.get(i.key);
            if (steps != null) {
                List<String> parts = new List<String>();
                for (String st : steps.keySet()) {
                    parts.add(st + ' ' + steps.get(st));
                }
                i.note = String.join(parts, ' · ');
            }
            if (i.count > 0) {
                d.dropOffs.add(i);
            }
        }
        d.knockouts = ranked(knockouts.values());
        d.regions = ranked(regions.values());
        d.cards = ranked(cards.values());

        // ---------------------------------------------------------------- headline numbers
        Integer n = d.leads.size();
        Integer hot = ratings.get('Hot').count;
        Integer open = 0;
        Integer openNotNudged = 0;
        for (Row r : d.leads) {
            if (r.outcome == 'Open') {
                open++;
                if (r.lastNudged == null && r.rating != 'Cold') {
                    openNotNudged++;
                }
            }
        }
        d.kpis.add(new Kpi('journeys', 'Journeys started', String.valueOf(d.journeys), 'web, WhatsApp and branch'));
        d.kpis.add(new Kpi('leads', 'Card leads', String.valueOf(n), 'new to bank · ' + qualified + ' qualified'));
        d.kpis.add(new Kpi('hot', 'Hot leads', String.valueOf(hot), pct(hot, n) + '% of leads'));
        d.kpis.add(new Kpi('open', 'Open, to work', String.valueOf(open), openNotNudged + ' hot or warm not nudged yet'));
        d.kpis.add(new Kpi('knocked', 'Knocked out', String.valueOf(knockedOut), pct(knockedOut, n) + '% of leads · no RM task'));
        d.kpis.add(new Kpi('submitted', 'Applications', String.valueOf(submitted), pct(submitted, d.journeys) + '% of journeys'));
        d.kpis.add(new Kpi('issued', 'Cards issued', String.valueOf(issued), pct(issued, d.journeys) + '% start-to-card'));
        d.kpis.add(new Kpi('score', 'Avg lead score', scored == 0 ? '—' : String.valueOf((scoreSum / scored).setScale(0)), 'combined, out of 100 · ' + nudged + ' nudged'));
        return d;
    }

    // ------------------------------------------------------------------ helpers
    /** When the journey started: the DPDP consent (the first answer), else when the record was created. */
    private static Datetime started(Card_Journey__c j) {
        return j.Consent_At__c != null ? j.Consent_At__c : j.CreatedDate;
    }

    /** 'Aadhaar eKYC (7/10 details)' -> 'Aadhaar eKYC'. */
    @TestVisible
    private static String stopLabel(String dropPoint) {
        if (String.isBlank(dropPoint)) {
            return null;
        }
        String s = dropPoint.contains(' (') ? dropPoint.substringBefore(' (') : dropPoint;
        return s == 'Done' ? 'Card issued' : s;
    }

    /** A knock-out summary without the applicant's numbers, so the same reason groups: 'CIBIL 630 (Poor) - below 650' -> 'CIBIL below 650'. */
    @TestVisible
    private static String reason(String summary) {
        if (String.isBlank(summary)) {
            return 'No reason recorded';
        }
        String s = summary.toLowerCase();
        if (s.contains('cibil') && s.contains('below')) {
            return 'CIBIL below the cut-off';
        }
        if (s.contains('overdue') || s.contains('dpd')) {
            return 'Over 90 days overdue';
        }
        if (s.contains('minimum for any card') || s.contains('below the')) {
            return 'Income below the minimum';
        }
        if (s.contains('outside the card footprint')) {
            return 'PIN outside the card footprint';
        }
        if (s.contains('negative list')) {
            return 'PAN on the negative list';
        }
        if (s.contains('not eligible')) {
            return summary.substringAfter(': ').abbreviate(60);
        }
        return summary.abbreviate(60);
    }

    private static String cibilBand(Decimal score) {
        String b = BandhuBureau.band(score == null ? null : score.intValue());
        return b == null ? 'No score yet' : b == 'Excellent' ? CIBIL_BANDS[0] : b == 'Good' ? CIBIL_BANDS[1] : b == 'Fair' ? CIBIL_BANDS[2] : CIBIL_BANDS[3];
    }

    private static Map<String, Item> items(List<String> keys) {
        Map<String, Item> m = new Map<String, Item>();
        for (String k : keys) {
            m.put(k, new Item(k, k));
        }
        return m;
    }

    private static void bump(Map<String, Item> m, String key) {
        if (m.containsKey(key)) {
            m.get(key).count++;
        }
    }

    private static void bumpNew(Map<String, Item> m, String key) {
        if (!m.containsKey(key)) {
            m.put(key, new Item(key, key));
        }
        m.get(key).count++;
    }

    private static List<Item> ranked(List<Item> l) {
        List<Item> out = new List<Item>();
        while (!l.isEmpty()) {
            Integer best = 0;
            for (Integer i = 1; i < l.size(); i++) {
                if (l[i].count > l[best].count) {
                    best = i;
                }
            }
            out.add(l.remove(best));
        }
        return out;
    }

    private static Integer pct(Integer part, Integer whole) {
        return whole == null || whole == 0 ? 0 : Math.round(part * 100.0 / whole);
    }
}
