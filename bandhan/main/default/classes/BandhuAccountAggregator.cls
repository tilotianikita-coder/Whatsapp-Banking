/**
 * Account Aggregator, mock FIU (Sahamati ecosystem). Going live replaces consent() and fetch() with calls to a licensed FIU
 * / AA gateway; BandhuCashFlow parses whatever they return.
 *
 * consent(): a consent artefact scoped to credit underwriting, 24 months of deposit-account statements, valid 30 days, one fetch.
 * fetch():   24 months of statements from two FIPs in two slightly different JSON layouts (ReBIT-style lowercase keys with
 *            string amounts vs capitalised keys, DR/CR flags and dd-MM-yyyy dates), the way formats vary across FIPs.
 *
 * Demo levers (deterministic on the PAN, so a demo repeats):
 *   5th PAN letter T -> frequent traveller (domestic + international), D -> dines out, G -> family groceries & fuel,
 *                  F -> long commute (fuel); any other letter -> spends mirror what the customer said they spend on.
 *   PAN digits ending 8 -> heavy EMIs (about 55% of income); ending 9 -> anomalies: an unexplained large credit,
 *                  round-trip transfers with one party and two months without salary.
 *   Self-employed -> business inflows with a festive-season peak (Durga Puja, Sep - Nov).
 * The latest monthly income is BandhuProviders.verifiedIncome(declared); salaries rose about 8% a year ago.
 */
public inherited sharing class BandhuAccountAggregator {
    public static final Integer LOOKBACK_MONTHS = 24;
    public static final String PURPOSE_CREDIT = 'Credit underwriting';
    public static final String PROVIDER = 'Account Aggregator (mock FIU)';

    public class Consent {
        public String consentId;
        public String purpose = PURPOSE_CREDIT;
        public String fiTypes = 'DEPOSIT';
        public Date dataFrom;
        public Date dataTo;
        public Date expiresOn;
        public String fetchType = 'ONETIME';
    }

    /** Consent request + approval (the customer approves in the AA app; the mock approves at once). */
    public static Consent consent(Card_Journey__c j) {
        Consent c = new Consent();
        Date today = BandhuI18n.today();
        c.dataTo = today.toStartOfMonth().addDays(-1);
        c.dataFrom = today.toStartOfMonth().addMonths(-LOOKBACK_MONTHS);
        c.expiresOn = today.addDays(30);
        c.consentId = 'AA-' + Math.abs((String.valueOf(j.PAN__c) + j.Mobile__c + Datetime.now().getTime()).hashCode());
        return c;
    }

    /** Consent, fetch and analysis in one step; stores the analysis and consent on the journey (not saved here). */
    public static BandhuCashFlow.Analysis run(Card_Journey__c j) {
        Consent c = consent(j);
        String fiData = fetch(j, c);
        BandhuCashFlow.Analysis a = BandhuCashFlow.analyse(fiData, j.Monthly_Income__c, j.Employment_Type__c);
        a.consentId = c.consentId;
        a.purpose = c.purpose;
        j.AA_Consent_Id__c = c.consentId;
        j.AA_Consent_At__c = Datetime.now();
        j.AA_Insights__c = JSON.serialize(a, true);
        return a;
    }

    // ------------------------------------------------------------------ mock FI data
    private static final Map<String, List<String>> MERCHANTS = new Map<String, List<String>>{
        'Travel' => new List<String>{ 'UPI/MAKEMYTRIP/FLIGHT', 'POS/INDIGO AIRLINES', 'UPI/IRCTC/TICKET', 'POS/TAJ HOTELS', 'UPI/UBER INDIA', 'UPI/GOIBIBO/HOTEL' },
        'International' => new List<String>{ 'POS/INTL/DUBAI DUTY FREE', 'FOREX CARD LOAD/THOMAS COOK', 'POS/INTL/SINGAPORE AIRLINES', 'POS/INTL/MARINA BAY SANDS' },
        'Dining' => new List<String>{ 'UPI/SWIGGY', 'UPI/ZOMATO', 'POS/MAINLAND CHINA', 'POS/BARBEQUE NATION', 'POS/6 BALLYGUNGE PLACE' },
        'Groceries' => new List<String>{ 'UPI/BIGBASKET', 'UPI/BLINKIT', 'POS/SPENCERS RETAIL', 'POS/MORE SUPERMARKET', 'UPI/ZEPTO' },
        'Shopping' => new List<String>{ 'UPI/AMAZON', 'UPI/FLIPKART', 'UPI/MYNTRA', 'POS/PANTALOONS', 'POS/TANISHQ JEWELLERS' },
        'Fuel' => new List<String>{ 'POS/INDIAN OIL', 'POS/HPCL', 'POS/BHARAT PETROLEUM' }
    };
    private static final Map<String, Integer> TXNS_PER_MONTH = new Map<String, Integer>{
        'Travel' => 2, 'International' => 1, 'Dining' => 7, 'Groceries' => 5, 'Shopping' => 3, 'Fuel' => 4
    };
    // festive peak for business inflows, by calendar month (Jan .. Dec)
    private static final List<Decimal> SEASON = new List<Decimal>{ 0.9, 0.9, 0.95, 1, 1, 1, 1, 1.05, 1.4, 1.6, 1.3, 1 };

    private static Long seed;

    private static Integer rnd(Integer bound) {
        seed = Math.mod(seed * 1103515245L + 12345L, 2147483648L);
        return (Integer) Math.mod(seed / 65536, (Long) bound);
    }

    /** Monthly spend per category as a share of income, by persona. */
    @TestVisible
    private static Map<String, Decimal> spendMix(String pan, String declaredFocus) {
        String persona = pan != null && pan.length() >= 5 ? pan.substring(4, 5).toUpperCase() : '';
        if (persona == 'T') {
            return new Map<String, Decimal>{ 'Travel' => 0.13, 'International' => 0.07, 'Dining' => 0.05, 'Groceries' => 0.04, 'Shopping' => 0.04, 'Fuel' => 0.015 };
        }
        if (persona == 'D') {
            return new Map<String, Decimal>{ 'Travel' => 0.02, 'International' => 0, 'Dining' => 0.12, 'Groceries' => 0.04, 'Shopping' => 0.05, 'Fuel' => 0.015 };
        }
        if (persona == 'G') {
            return new Map<String, Decimal>{ 'Travel' => 0.01, 'International' => 0, 'Dining' => 0.02, 'Groceries' => 0.13, 'Shopping' => 0.05, 'Fuel' => 0.05 };
        }
        if (persona == 'F') {
            return new Map<String, Decimal>{ 'Travel' => 0.02, 'International' => 0, 'Dining' => 0.02, 'Groceries' => 0.05, 'Shopping' => 0.03, 'Fuel' => 0.09 };
        }
        Set<String> focus = new Set<String>(String.isBlank(declaredFocus) ? new List<String>() : declaredFocus.split(';'));
        Map<String, Decimal> mix = new Map<String, Decimal>();
        for (String f : BandhuEligibility.FOCUS) {
            mix.put(f, focus.contains(f) ? 0.09 : focus.isEmpty() ? 0.03 : f == 'International' ? 0 : 0.012);
        }
        return mix;
    }

    public static String fetch(Card_Journey__c j, Consent c) {
        String pan = j.PAN__c == null ? 'ABCPS1234K' : j.PAN__c.toUpperCase();
        seed = Math.abs(pan.hashCode());
        String digits = pan.length() >= 9 ? pan.substring(5, 9) : '0000';
        Boolean heavyEmi = digits.endsWith('8');
        Boolean anomalies = digits.endsWith('9');
        Boolean business = j.Employment_Type__c == 'Self-employed' || j.Employment_Type__c == 'Business';
        Decimal income = BandhuProviders.verifiedIncome(j.Monthly_Income__c == null ? 50000 : j.Monthly_Income__c);
        String holder = String.isBlank(j.Customer_Name__c) ? 'APPLICANT' : j.Customer_Name__c.toUpperCase();
        // the payer on the salary credits: the company if already given, else a plausible employer (the AA comes before that question)
        List<String> employers = new List<String>{ 'TATA CONSULTANCY SERVICES', 'INFOSYS LTD', 'WIPRO LTD', 'COGNIZANT TECHNOLOGY SOLUTIONS',
            'ITC LTD', 'TATA STEEL LTD', 'CESC LTD', 'COAL INDIA LTD' };
        String employer = String.isNotBlank(j.Company_Name__c) ? j.Company_Name__c.toUpperCase()
            : employers[Math.mod(Math.abs(pan.hashCode()), employers.size())];
        Map<String, Decimal> mix = spendMix(pan, j.Spend_Focus__c);

        List<Map<String, Object>> primary = new List<Map<String, Object>>();
        List<Map<String, Object>> secondary = new List<Map<String, Object>>();
        Decimal balA = (income * 1.5).setScale(2);
        Decimal balB = (income * 0.4).setScale(2);
        Integer n = 0;
        for (Integer m = LOOKBACK_MONTHS; m >= 1; m--) {
            Date first = c.dataTo.toStartOfMonth().addMonths(1 - m);
            Integer days = Date.daysInMonth(first.year(), first.month());
            List<Object[]> a = new List<Object[]>();   // day, credit?, amount, mode, narration
            List<Object[]> b = new List<Object[]>();
            Decimal monthIncome = m > 12 ? (income / 1.08 / 100).round(System.RoundingMode.DOWN) * 100 : income;
            String mon = Datetime.newInstance(first, Time.newInstance(0, 0, 0, 0)).format('MMMyy').toUpperCase();
            if (business) {
                Decimal total = monthIncome * SEASON[first.month() - 1];
                Integer k = 8 + rnd(6);
                for (Integer i = 0; i < k; i++) {
                    String party = new List<String>{ 'GHOSH TEXTILES', 'SAHA & SONS', 'NEW MARKET STORES', 'DAS ENTERPRISES', 'KOLEY TRADERS', 'BASAK HOSIERY' }[rnd(6)];
                    a.add(new Object[]{ 1 + rnd(days), true, (total / k).setScale(0), i < k / 2 ? 'UPI' : 'FT',
                        (i < k / 2 ? 'UPI/CR/' + party + '/SALES' : 'NEFT/CR/' + party + '/INV-' + (1000 + rnd(9000))) });
                }
            } else if (!(anomalies && (m == 8 || m == 15))) {
                a.add(new Object[]{ Math.min(days, 28 + rnd(2)), true, monthIncome, 'FT', 'NEFT/SALARY/' + employer + '/' + mon });
            }
            // obligations and fixed outflows
            Decimal emi = heavyEmi ? income * 0.55 : income >= 50000 ? income * 0.12 : 0;
            if (emi > 0) {
                if (heavyEmi) {
                    a.add(new Object[]{ 5, false, (emi * 0.6).setScale(0), 'ACH', 'ACH/NACH/HDFC BANK HOME LOAN EMI' });
                    a.add(new Object[]{ 7, false, (emi * 0.4).setScale(0), 'ACH', 'ACH/NACH/BAJAJ FINANCE PERSONAL LOAN EMI' });
                } else {
                    a.add(new Object[]{ 5, false, emi.setScale(0), 'ACH', 'ACH/NACH/TATA CAPITAL CAR LOAN EMI' });
                }
            }
            if (income < 150000) {
                a.add(new Object[]{ 3, false, (income * 0.14 / 100).setScale(0) * 100, 'FT', 'IMPS/RENT/S K BANERJEE' });
            }
            a.add(new Object[]{ 10, false, (income * 0.012).setScale(0), 'OTHERS', 'BILLPAY/CESC ELECTRICITY' });
            a.add(new Object[]{ 12, false, Decimal.valueOf(799 + rnd(3) * 100), 'OTHERS', 'BILLPAY/JIO POSTPAID' });
            a.add(new Object[]{ 8, false, (income * 0.05 / 500).setScale(0) * 500, 'ACH', 'ACH/SIP/ICICI PRU MF' });
            a.add(new Object[]{ 2 + rnd(10), false, (income * 0.015 / 500).setScale(0) * 500 + 500, 'ATM', 'ATM WDL/PARK STREET' });
            a.add(new Object[]{ 1 + rnd(days), false, (income * 0.015 / 500).setScale(0) * 500 + 500, 'ATM', 'ATM WDL/SALT LAKE' });
            Decimal toSecondary = (income * 0.1 / 1000).setScale(0) * 1000;
            a.add(new Object[]{ 2, false, toSecondary, 'FT', 'IMPS/SELF/' + holder });
            b.add(new Object[]{ 2, true, toSecondary, 'FT', 'IMPS/SELF/' + holder });
            // discretionary spends; travel peaks in May and December
            for (String cat : BandhuEligibility.FOCUS) {
                Decimal share = mix.get(cat);
                if (share == null || share == 0) {
                    continue;
                }
                Decimal amount = income * share * (cat == 'Travel' && (first.month() == 5 || first.month() == 12) ? 1.8 : 1);
                Integer k = TXNS_PER_MONTH.get(cat);
                if (cat == 'International') {
                    if (Math.mod(m, 2) == 1) {
                        continue;
                    }
                    amount *= 2;
                }
                for (Integer i = 0; i < k; i++) {
                    List<String> names = MERCHANTS.get(cat);
                    Decimal amt = (amount / k * (80 + rnd(41)) / 100).setScale(2);
                    // a share of dining and shopping is paid from the second account
                    List<Object[]> target = (cat == 'Dining' || cat == 'Shopping') && Math.mod(i, 3) == 2 ? b : a;
                    target.add(new Object[]{ 1 + rnd(days), false, amt, names[rnd(names.size())].startsWith('UPI') ? 'UPI' : 'CARD', names[rnd(names.size())] });
                }
            }
            if (anomalies && m == 3) {
                a.add(new Object[]{ 14, true, income * 4, 'FT', 'IMPS/CR/R K TRADERS/TRANSFER' });
            }
            if (anomalies && (m == 2 || m == 4 || m == 6)) {
                Decimal amt = (income * 0.6 / 1000).setScale(0) * 1000;
                a.add(new Object[]{ 9, false, amt, 'FT', 'IMPS/DR/SUMAN ENTERPRISES/TRANSFER' });
                a.add(new Object[]{ 11, true, amt, 'FT', 'IMPS/CR/SUMAN ENTERPRISES/TRANSFER' });
            }
            if (Math.mod(first.month(), 3) == 0) {
                a.add(new Object[]{ days, true, (balA * 0.007).setScale(0), 'OTHERS', 'INT.PD/SAVINGS INTEREST' });
            }
            a.sort(new ByDay());
            b.sort(new ByDay());
            for (Object[] t : a) {
                Decimal amt = (Decimal) t[2];
                balA += (Boolean) t[1] ? amt : -amt;
                Date d = Date.newInstance(first.year(), first.month(), (Integer) t[0]);
                primary.add(new Map<String, Object>{
                    'txnId' => 'S' + (++n), 'type' => (Boolean) t[1] ? 'CREDIT' : 'DEBIT', 'mode' => t[3],
                    'amount' => String.valueOf(amt.setScale(2)), 'currentBalance' => String.valueOf(balA.setScale(2)),
                    'transactionTimestamp' => Datetime.newInstance(d, Time.newInstance(10, 0, 0, 0)).format('yyyy-MM-dd\'T\'HH:mm:ss') + '+05:30',
                    'valueDate' => Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0)).format('yyyy-MM-dd'),
                    'narration' => t[4], 'reference' => 'REF' + (100000 + n)
                });
            }
            for (Object[] t : b) {
                Decimal amt = (Decimal) t[2];
                balB += (Boolean) t[1] ? amt : -amt;
                Date d = Date.newInstance(first.year(), first.month(), (Integer) t[0]);
                secondary.add(new Map<String, Object>{
                    'id' => 'K' + (++n), 'txnType' => (Boolean) t[1] ? 'CR' : 'DR', 'txnMode' => t[3], 'amt' => amt.setScale(2),
                    'bal' => balB.setScale(2), 'txnDate' => Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0)).format('dd-MM-yyyy'), 'remarks' => t[4]
                });
            }
        }
        String start = Datetime.newInstance(c.dataFrom, Time.newInstance(0, 0, 0, 0)).format('yyyy-MM-dd');
        String finish = Datetime.newInstance(c.dataTo, Time.newInstance(0, 0, 0, 0)).format('yyyy-MM-dd');
        Map<String, Object> fipA = new Map<String, Object>{
            'fipID' => 'HDFC-FIP', 'fipName' => 'HDFC Bank',
            'data' => new List<Object>{ new Map<String, Object>{
                'linkRefNumber' => 'LNK-' + rnd(999999), 'maskedAccNumber' => 'XXXXXXXX' + (4000 + rnd(5999)),
                'decryptedFI' => new Map<String, Object>{ 'account' => new Map<String, Object>{
                    'type' => 'deposit', 'version' => '1.1',
                    'profile' => new Map<String, Object>{ 'holders' => new Map<String, Object>{ 'type' => 'SINGLE',
                        'holder' => new List<Object>{ new Map<String, Object>{ 'name' => holder, 'pan' => pan, 'mobile' => j.Mobile__c, 'ckycCompliance' => 'true' } } } },
                    'summary' => new Map<String, Object>{ 'type' => 'SAVINGS', 'currentBalance' => String.valueOf(balA.setScale(2)), 'currency' => 'INR', 'status' => 'ACTIVE', 'branch' => 'PARK STREET, KOLKATA' },
                    'transactions' => new Map<String, Object>{ 'startDate' => start, 'endDate' => finish, 'transaction' => primary }
                } }
            } }
        };
        Map<String, Object> fipB = new Map<String, Object>{
            'fipID' => 'SBI-FIP', 'fipName' => 'State Bank of India',
            'data' => new List<Object>{ new Map<String, Object>{
                'linkRefNumber' => 'LNK-' + rnd(999999), 'maskedAccNumber' => 'XXXXXXX' + (1000 + rnd(8999)),
                'decryptedFI' => new Map<String, Object>{ 'Account' => new Map<String, Object>{
                    'Type' => 'DEPOSIT',
                    'Profile' => new Map<String, Object>{ 'Holders' => new Map<String, Object>{ 'Holder' => new List<Object>{ new Map<String, Object>{ 'Name' => holder } } } },
                    'Summary' => new Map<String, Object>{ 'Type' => 'SAVINGS', 'CurrentBalance' => balB.setScale(2) },
                    'Transactions' => new Map<String, Object>{ 'StartDate' => start, 'EndDate' => finish, 'Transaction' => secondary }
                } }
            } }
        };
        return JSON.serialize(new Map<String, Object>{
            'ver' => '2.0.0', 'consentId' => c.consentId, 'purpose' => c.purpose, 'FI' => new List<Object>{ fipA, fipB }
        });
    }

    private class ByDay implements Comparator<Object[]> {
        public Integer compare(Object[] x, Object[] y) {
            return (Integer) x[0] - (Integer) y[0];
        }
    }
}
