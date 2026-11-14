/**
 * Risk and income cross-checks (mocks; going live: a risk / fraud platform, a map API, the GST (NIC) API and the
 * income-tax AIS / Form 26AS via the customer's consent).
 *
 *   fraud      negative list, open applications on the PAN, application velocity (the same PAN or mobile in many journeys
 *              in 24 hours: a device / session proxy), credit-hungry bureau enquiries across lenders, address vs PIN
 *   address    the declared city against the city the PIN belongs to (mock geocoder by PIN prefix)
 *   gst        self-employed / business: GSTIN from the PAN and state, 12 months of returns, turnover vs declared income
 *   ais        Form 26AS / AIS: income reported to the tax department vs declared income
 * Demo lever: PAN digits ending 2 -> GST returns filed 7 of 12 months, turnover and AIS income far below declared.
 */
public inherited sharing class BandhuRisk {
    public static final Decimal INCOME_TOLERANCE = 0.25;

    private static final Map<String, String> PIN_CITY = new Map<String, String>{
        '700' => 'Kolkata', '711' => 'Howrah', '712' => 'Hooghly', '713' => 'Durgapur', '734' => 'Siliguri', '781' => 'Guwahati',
        '751' => 'Bhubaneswar', '800' => 'Patna', '834' => 'Ranchi', '110' => 'Delhi', '400' => 'Mumbai', '560' => 'Bengaluru',
        '600' => 'Chennai', '500' => 'Hyderabad', '411' => 'Pune', '302' => 'Jaipur'
    };
    private static final Map<String, String> PIN_STATE = new Map<String, String>{
        '70' => '19', '71' => '19', '72' => '19', '73' => '19', '74' => '19', '78' => '18', '75' => '21', '80' => '10', '83' => '20',
        '11' => '07', '40' => '27', '56' => '29', '60' => '33', '50' => '36', '41' => '27', '30' => '08'
    };

    public static String cityForPin(String pin) {
        return String.isBlank(pin) || pin.length() < 3 ? null : PIN_CITY.get(pin.left(3));
    }

    /** Declared city vs the PIN's city; null when it matches or the PIN is not in the mock geocoder. */
    public static String addressMismatch(String city, String pin) {
        String expected = cityForPin(pin);
        if (expected == null || String.isBlank(city)) {
            return null;
        }
        String c = city.toLowerCase();
        String e = expected.toLowerCase();
        return c.contains(e) || e.contains(c) ? null : 'Declared city ' + city + ' but PIN ' + pin + ' is in ' + expected;
    }

    private static Boolean weakIncomeLever(String pan) {
        return pan != null && pan.length() >= 9 && pan.substring(5, 9).endsWith('2');
    }

    // ------------------------------------------------------------------ fraud
    public static BandhuProviders.Report fraud(Card_Journey__c j, Id applicationId) {
        BandhuProviders.Report r = new BandhuProviders.Report();
        r.provider = 'Bandhan risk platform (mock)';
        String p = j.PAN__c == null ? '' : j.PAN__c.toUpperCase();
        Integer others = [
            SELECT COUNT() FROM Card_Application__c
            WHERE PAN__c = :p AND Id != :applicationId AND Status__c IN ('Submitted', 'Under Review', 'Approved', 'Card Issued')
        ];
        Datetime dayAgo = Datetime.now().addHours(-24);
        Integer velocity = String.isBlank(p) && String.isBlank(j.Mobile__c) ? 0 : [
            SELECT COUNT() FROM Card_Journey__c WHERE Id != :j.Id AND CreatedDate >= :dayAgo
            AND ((PAN__c = :p AND PAN__c != null) OR (Mobile__c = :j.Mobile__c AND Mobile__c != null))
        ];
        BandhuBureau.Report b = BandhuBureau.fromJourney(j);
        String address = addressMismatch(j.City__c, j.PIN_Code__c);
        List<String> refer = new List<String>();
        if (others > 0) {
            refer.add('Another open card application on this PAN');
        }
        if (velocity >= 2) {
            refer.add((velocity + 1) + ' applications from this PAN / mobile in 24 hours');
        }
        if (b != null && b.enquiryLenders6m >= 4) {
            refer.add('Applied with ' + b.enquiryLenders6m + ' lenders in 6 months (bureau enquiries)');
        }
        if (address != null) {
            refer.add(address);
        }
        r.details.add('Negative list / watchlist: ' + (p.right(1) == 'X' ? 'MATCH' : 'no match'));
        r.details.add('Open applications on the PAN: ' + others + ' · journeys from this PAN or mobile in 24 hours: ' + (velocity + 1));
        r.details.add('Bureau enquiries: ' + (b == null ? 'not pulled' : b.enquiries6m + ' in 6 months across ' + b.enquiryLenders6m + ' lenders'));
        r.details.add('Address: ' + (address == null ? 'PIN ' + j.PIN_Code__c + ' matches ' + (j.City__c == null ? 'the region' : j.City__c) : address));
        if (p.right(1) == 'X') {
            r.result = 'Fail';
            r.summary = 'PAN on the internal negative list';
        } else if (!refer.isEmpty()) {
            r.result = 'Refer';
            r.summary = String.join(refer, '; ');
        } else {
            r.result = 'Pass';
            r.summary = 'No dedupe, watchlist, velocity or address flags';
        }
        r.score = others;
        return r;
    }

    // ------------------------------------------------------------------ income cross-checks
    public class IncomeCheck {
        public String source;
        public Decimal annualIncome;
        public Decimal variancePct;
        public Boolean flagged = false;
        public List<String> lines = new List<String>();
    }

    /** Form 26AS / AIS (mock): income the tax department has on record, vs 12 x declared monthly income. */
    public static IncomeCheck ais(String pan, Decimal declaredMonthly, String employment) {
        IncomeCheck c = new IncomeCheck();
        c.source = 'Form 26AS / AIS (mock)';
        Decimal declaredAnnual = declaredMonthly == null ? 0 : declaredMonthly * 12;
        c.annualIncome = (declaredAnnual * (weakIncomeLever(pan) ? 0.55 : employment == 'Salaried' ? 0.97 : 0.9) / 1000).setScale(0) * 1000;
        c.variancePct = declaredAnnual == 0 ? 0 : ((declaredAnnual - c.annualIncome) / declaredAnnual * 100).setScale(0);
        c.flagged = c.variancePct > INCOME_TOLERANCE * 100;
        c.lines.add('AIS FY income ' + BandhuI18n.inr(c.annualIncome) + (employment == 'Salaried' ? ' (salary, TDS by employer)' : ' (business / professional receipts)')
            + ' vs declared ' + BandhuI18n.inr(declaredAnnual) + '/year: ' + (c.flagged ? '⚠ ' : '') + c.variancePct + '% lower');
        return c;
    }

    /** GST (mock) for self-employed / business: GSTIN, return filing regularity and turnover. */
    public static IncomeCheck gst(String pan, String pin, Decimal declaredMonthly) {
        IncomeCheck c = new IncomeCheck();
        c.source = 'GST portal (mock)';
        String state = pin == null || pin.length() < 2 || !PIN_STATE.containsKey(pin.left(2)) ? '19' : PIN_STATE.get(pin.left(2));
        String gstin = state + (pan == null ? 'XXXXX0000X' : pan.toUpperCase()) + '1Z' + (pan == null ? '0' : pan.right(1));
        Boolean weak = weakIncomeLever(pan);
        Integer filed = weak ? 7 : 12;
        Decimal declaredAnnual = declaredMonthly == null ? 0 : declaredMonthly * 12;
        // income as a share of turnover (a placeholder 15% margin) implies the turnover the declared income needs
        Decimal turnover = (declaredAnnual / 0.15 * (weak ? 0.45 : 1.1) / 10000).setScale(0) * 10000;
        Decimal implied = turnover * 0.15;
        c.annualIncome = implied;
        c.variancePct = declaredAnnual == 0 ? 0 : ((declaredAnnual - implied) / declaredAnnual * 100).setScale(0);
        c.flagged = filed < 10 || c.variancePct > INCOME_TOLERANCE * 100;
        c.lines.add('GSTIN ' + gstin + ' · active · returns filed ' + filed + ' of 12 months' + (filed < 10 ? ' ⚠' : ''));
        c.lines.add('Turnover (12 months) ' + BandhuI18n.inr(turnover) + ' → implied income ' + BandhuI18n.inr(implied) + '/year at a 15% margin'
            + (c.variancePct > INCOME_TOLERANCE * 100 ? ' ⚠ ' + c.variancePct + '% below declared' : ''));
        return c;
    }

    /** The cross-checks for this applicant: AIS for everyone, GST for the self-employed and business owners. */
    public static List<IncomeCheck> incomeChecks(Card_Journey__c j) {
        List<IncomeCheck> out = new List<IncomeCheck>();
        if (j.Monthly_Income__c == null || String.isBlank(j.PAN__c)) {
            return out;
        }
        out.add(ais(j.PAN__c, j.Monthly_Income__c, j.Employment_Type__c));
        if (j.Employment_Type__c == 'Self-employed' || j.Employment_Type__c == 'Business') {
            out.add(gst(j.PAN__c, j.PIN_Code__c, j.Monthly_Income__c));
        }
        return out;
    }
}
