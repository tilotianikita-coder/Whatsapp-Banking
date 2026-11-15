/**
 * Cash-flow analysis of Account Aggregator data (credit underwriting and card recommendation).
 *
 * 1. Normalise: FI data from any FIP -> one transaction list. Keys are matched case-insensitively and by alias
 *    (transactions / Transactions.Transaction; amount / amt; type CREDIT|DEBIT / txnType CR|DR;
 *    transactionTimestamp / valueDate / txnDate in yyyy-MM-dd or dd-MM-yyyy; narration / remarks), amounts as text or numbers.
 * 2. Categorise each transaction from its narration (rules below): income (salary, business), obligations (EMI), rent,
 *    utilities, investments, cash, self-transfers and the card spend categories (BandhuEligibility.FOCUS).
 * 3. Derive: net monthly income (median of the last 6 months), income stability (100 x (1 - coefficient of variation)),
 *    income trend (last 6 vs first 6 months), obligations and obligation-to-income ratio (FOIR), surplus, average balance,
 *    monthly spend by category, lifestyle signals, seasonality (business inflows) and anomalies:
 *    unexplained large credits, round-trip (circular) transfers, months without salary, declared vs seen income.
 * Rules are explainable on purpose: every figure can be traced back to the transactions.
 */
public inherited sharing class BandhuCashFlow {
    public static final String CAT_SALARY = 'Salary';
    public static final String CAT_BUSINESS = 'Business income';
    public static final String CAT_EMI = 'EMI';
    public static final String CAT_SELF = 'Self transfer';
    public static final String CAT_TRANSFER = 'Transfer';
    public static final Set<String> CAT_INCOME = new Set<String>{ CAT_SALARY, CAT_BUSINESS };

    public class Txn {
        public Date txnDate;
        public Boolean credit;
        public Decimal amount;
        public Decimal balance;
        public String narration;
        public String mode;
        public String fip;
        public String category;
        public String counterparty;
        public Boolean luxury = false;
        public Integer idx;
    }

    public class Analysis {
        public String consentId;
        public String purpose;
        public Integer banks = 0;
        public Integer accounts = 0;
        public Integer months = 0;
        public Integer transactions = 0;
        public Date fromDate;
        public Date toDate;
        public Decimal netMonthlyIncome;
        public String incomeSource;
        public String employer;            // the payer on the salary credits
        public Integer incomeStability;
        public String incomeTrend;
        public Decimal incomeGrowthPct;
        public Decimal monthlyObligations = 0;
        public Decimal foirPct = 0;
        public Decimal avgMonthlyOutflow = 0;
        public Decimal monthlySurplus;
        public Decimal avgBalance;
        public Decimal monthlyCardSpend = 0;
        public Map<String, Decimal> spend = new Map<String, Decimal>();
        public Map<String, Integer> spendCount = new Map<String, Integer>();
        public List<String> topCategories = new List<String>();
        public List<String> lifestyle = new List<String>();
        public String seasonality;
        public List<String> anomalies = new List<String>();
        public Decimal declaredIncome;

        public Decimal share(String category) {
            Decimal s = spend.get(category);
            return s == null || monthlyCardSpend == 0 ? 0 : s / monthlyCardSpend;
        }

        public String topSpendText() {
            List<String> parts = new List<String>();
            for (String c : topCategories) {
                parts.add(c + ' ' + BandhuI18n.inrShort(spend.get(c)));
            }
            return parts.isEmpty() ? '-' : String.join(parts, ' · ');
        }

        /**
         * The customer's view: travel in India and abroad as one figure ("Travel ₹21,262 (₹6,978 of it abroad)"),
         * then the next biggest categories. The engine keeps them apart: cards reward them differently.
         */
        public String customerSpendText(String lang) {
            Decimal travel = (spend.containsKey('Travel') ? spend.get('Travel') : 0) + (spend.containsKey('International') ? spend.get('International') : 0);
            Decimal abroad = spend.containsKey('International') ? spend.get('International') : 0;
            List<String> order = new List<String>();
            List<Decimal> amounts = new List<Decimal>();
            for (String c : spend.keySet()) {
                if (c == 'Travel' || c == 'International') {
                    continue;
                }
                order.add(c);
                amounts.add(spend.get(c));
            }
            if (travel > 0) {
                order.add('Travel');
                amounts.add(travel);
            }
            List<String> parts = new List<String>();
            Set<Integer> used = new Set<Integer>();
            for (Integer n = 0; n < Math.min(3, order.size()); n++) {
                Integer best;
                for (Integer i = 0; i < order.size(); i++) {
                    if (!used.contains(i) && (best == null || amounts[i] > amounts[best])) {
                        best = i;
                    }
                }
                used.add(best);
                if (monthlyCardSpend == 0 || amounts[best] / monthlyCardSpend < 0.1) {
                    break;
                }
                String text = order[best] + ' ' + BandhuI18n.inrShort(amounts[best]);
                if (order[best] == 'Travel' && abroad > 0) {
                    text += ' (' + BandhuI18n.inrShort(abroad) + BandhuI18n.pick(' of it abroad', ' विदेश में', ' বিদেশে', lang) + ')';
                }
                parts.add(text);
            }
            return parts.isEmpty() ? '-' : String.join(parts, ' · ');
        }

        /** A lifestyle signal the spend line doesn't already show (travel is in the spend line). */
        public String extraLifestyle() {
            for (String l : lifestyle) {
                if (!l.startsWith('Frequent traveller') && !l.startsWith('International spends')) {
                    return l;
                }
            }
            return null;
        }

        /** Underwriter-facing lines (the customer sees AA_Insights). */
        public List<String> summaryLines() {
            List<String> l = new List<String>();
            l.add('Consent ' + consentId + ' · purpose: ' + purpose + ' · ' + months + ' months (' + BandhuI18n.formatDate(fromDate) + ' - '
                + BandhuI18n.formatDate(toDate) + ') · ' + banks + ' banks, ' + accounts + ' accounts, ' + transactions + ' transactions');
            l.add('Net monthly income: ' + BandhuI18n.inr(netMonthlyIncome) + ' (' + incomeSource + ')'
                + (declaredIncome == null ? '' : ' · declared ' + BandhuI18n.inr(declaredIncome)));
            l.add('Income stability: ' + incomeStability + '/100 · trend: ' + incomeTrend + ' (' + (incomeGrowthPct >= 0 ? '+' : '') + incomeGrowthPct + '% year on year)');
            l.add('EMIs: ' + BandhuI18n.inr(monthlyObligations) + '/month · FOIR ' + foirPct + '%');
            l.add('Monthly outflow ' + BandhuI18n.inr(avgMonthlyOutflow) + ' · surplus ' + BandhuI18n.inr(monthlySurplus) + ' · average balance ' + BandhuI18n.inr(avgBalance));
            l.add('Card-able spend ' + BandhuI18n.inr(monthlyCardSpend) + '/month: ' + topSpendText());
            if (!lifestyle.isEmpty()) {
                l.add('Lifestyle: ' + String.join(lifestyle, ' · '));
            }
            if (seasonality != null) {
                l.add('Seasonality: ' + seasonality);
            }
            for (String a : anomalies) {
                l.add('⚠ ' + a);
            }
            if (anomalies.isEmpty()) {
                l.add('No anomalies: no unexplained credits, round-trip transfers or income gaps');
            }
            return l;
        }
    }

    /** Merchant and narration rules: first match wins (checked in this order). */
    private static final List<List<String>> RULES = new List<List<String>>{
        new List<String>{ CAT_EMI, ' EMI', 'EMI/', 'LOAN' },
        new List<String>{ 'Rent', 'RENT' },
        new List<String>{ 'Investment', '/SIP/', 'MUTUAL FUND', ' MF', 'PPF', 'NPS' },
        new List<String>{ 'Utilities', 'BILLPAY', 'ELECTRICITY', 'POSTPAID', 'BROADBAND', 'GAS BILL' },
        new List<String>{ 'Cash', 'ATM WDL', 'CASH WDL' },
        new List<String>{ 'International', '/INTL/', 'FOREX', 'INTERNATIONAL' },
        new List<String>{ 'Travel', 'MAKEMYTRIP', 'GOIBIBO', 'INDIGO', 'AIR INDIA', 'VISTARA', 'IRCTC', 'TAJ HOTELS', 'OYO', 'UBER', 'OLA ', 'CLEARTRIP' },
        new List<String>{ 'Dining', 'SWIGGY', 'ZOMATO', 'RESTAURANT', 'MAINLAND CHINA', 'BARBEQUE', 'BALLYGUNGE PLACE', 'EAZYDINER', 'CAFE' },
        new List<String>{ 'Groceries', 'BIGBASKET', 'BLINKIT', 'ZEPTO', 'SPENCERS', 'MORE SUPERMARKET', 'DMART', 'RELIANCE FRESH' },
        new List<String>{ 'Shopping', 'AMAZON', 'FLIPKART', 'MYNTRA', 'AJIO', 'PANTALOONS', 'TANISHQ', 'NYKAA', 'CROMA' },
        new List<String>{ 'Fuel', 'INDIAN OIL', 'HPCL', 'BHARAT PETROLEUM', 'IOCL', 'SHELL' }
    };
    private static final List<String> LUXURY = new List<String>{ 'TANISHQ', 'TAJ HOTELS', 'MARINA BAY', 'LOUIS VUITTON', 'DUTY FREE' };

    // ------------------------------------------------------------------ entry point
    public static Analysis analyse(String fiJson, Decimal declaredIncome, String employment) {
        Analysis a = new Analysis();
        a.declaredIncome = declaredIncome;
        List<Txn> txns = normalise(fiJson, a);
        String holder = holderName(fiJson);
        for (Txn t : txns) {
            categorise(t, holder);
        }
        derive(a, txns, employment == 'Self-employed' || employment == 'Business');
        return a;
    }

    // ------------------------------------------------------------------ 1. normalise
    public static List<Txn> normalise(String fiJson, Analysis a) {
        List<Txn> out = new List<Txn>();
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(fiJson);
        for (Object fipObj : asList(field(root, 'FI', 'fiData'))) {
            Map<String, Object> fip = (Map<String, Object>) fipObj;
            String fipId = String.valueOf(field(fip, 'fipName', 'fipID'));
            a.banks++;
            for (Object dataObj : asList(field(fip, 'data'))) {
                Map<String, Object> account = asMap(field(asMap(field((Map<String, Object>) dataObj, 'decryptedFI', 'FI')), 'account'));
                if (account == null) {
                    continue;
                }
                a.accounts++;
                Map<String, Object> txBlock = asMap(field(account, 'transactions'));
                for (Object txObj : asList(txBlock == null ? null : field(txBlock, 'transaction'))) {
                    Map<String, Object> tx = (Map<String, Object>) txObj;
                    Txn t = new Txn();
                    t.fip = fipId;
                    String txnType = String.valueOf(field(tx, 'type', 'txnType', 'drCr')).toUpperCase();
                    t.credit = txnType.startsWith('C');
                    t.amount = toDecimal(field(tx, 'amount', 'amt', 'txnAmount'));
                    t.balance = toDecimal(field(tx, 'currentBalance', 'bal', 'balance'));
                    t.txnDate = toDate(field(tx, 'valueDate', 'transactionTimestamp', 'txnDate'));
                    Object n = field(tx, 'narration', 'remarks', 'description');
                    t.narration = n == null ? '' : String.valueOf(n).toUpperCase();
                    Object m = field(tx, 'mode', 'txnMode');
                    t.mode = m == null ? 'OTHERS' : String.valueOf(m);
                    if (t.amount != null && t.txnDate != null) {
                        t.idx = out.size();
                        out.add(t);
                    }
                }
            }
        }
        a.transactions = out.size();
        return out;
    }

    /** Case-insensitive lookup over aliases. */
    private static Object field(Map<String, Object> m, String name1, String name2, String name3) {
        if (m == null) {
            return null;
        }
        Set<String> wanted = new Set<String>{ name1.toLowerCase() };
        if (name2 != null) {
            wanted.add(name2.toLowerCase());
        }
        if (name3 != null) {
            wanted.add(name3.toLowerCase());
        }
        for (String name : new List<String>{ name1, name2, name3 }) {
            if (name != null && m.containsKey(name)) {
                return m.get(name);
            }
        }
        for (String k : m.keySet()) {
            if (wanted.contains(k.toLowerCase())) {
                return m.get(k);
            }
        }
        return null;
    }

    private static Object field(Map<String, Object> m, String name1, String name2) {
        return field(m, name1, name2, null);
    }

    private static Object field(Map<String, Object> m, String name1) {
        return field(m, name1, null, null);
    }

    private static List<Object> asList(Object o) {
        if (o == null) {
            return new List<Object>();
        }
        return o instanceof List<Object> ? (List<Object>) o : new List<Object>{ o };
    }

    private static Map<String, Object> asMap(Object o) {
        return o instanceof Map<String, Object> ? (Map<String, Object>) o : null;
    }

    @TestVisible
    private static Decimal toDecimal(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof Decimal) {
            return (Decimal) o;
        }
        String s = String.valueOf(o).replace(',', '').trim();
        return String.isBlank(s) ? null : Decimal.valueOf(s);
    }

    @TestVisible
    private static Date toDate(Object o) {
        if (o == null) {
            return null;
        }
        String s = String.valueOf(o).trim();
        if (Pattern.matches('\\d{4}-\\d{2}-\\d{2}.*', s)) {
            return Date.newInstance(Integer.valueOf(s.substring(0, 4)), Integer.valueOf(s.substring(5, 7)), Integer.valueOf(s.substring(8, 10)));
        }
        if (Pattern.matches('\\d{2}[-/]\\d{2}[-/]\\d{4}.*', s)) {
            return Date.newInstance(Integer.valueOf(s.substring(6, 10)), Integer.valueOf(s.substring(3, 5)), Integer.valueOf(s.substring(0, 2)));
        }
        return null;
    }

    private static String holderName(String fiJson) {
        Matcher m = Pattern.compile('"(?i:name)"\\s*:\\s*"([^"]+)"').matcher(fiJson);
        return m.find() ? m.group(1).toUpperCase() : null;
    }

    // ------------------------------------------------------------------ 2. categorise
    @TestVisible
    private static void categorise(Txn t, String holder) {
        String n = t.narration;
        List<String> parts = n.split('/');
        t.counterparty = parts.size() >= 3 ? parts[2].trim() : null;
        if (n.contains('/SELF/') || (holder != null && n.contains(holder))) {
            t.category = CAT_SELF;
            return;
        }
        if (t.credit) {
            if (n.contains('SALARY') || n.contains('SAL CREDIT')) {
                t.category = CAT_SALARY;
            } else if (n.contains('/SALES') || n.contains('/INV-') || n.contains('SETTLEMENT')) {
                t.category = CAT_BUSINESS;
            } else if (n.contains('INT.PD') || n.contains('INTEREST')) {
                t.category = 'Interest';
            } else if (n.contains('REFUND') || n.contains('REVERSAL')) {
                t.category = 'Refund';
            } else {
                t.category = CAT_TRANSFER;
            }
            return;
        }
        for (List<String> rule : RULES) {
            for (Integer i = 1; i < rule.size(); i++) {
                if (n.contains(rule[i])) {
                    t.category = rule[0];
                    break;
                }
            }
            if (t.category != null) {
                break;
            }
        }
        if (t.category == null) {
            t.category = n.startsWith('IMPS') || n.startsWith('NEFT') || n.startsWith('RTGS') ? CAT_TRANSFER : 'Other';
        }
        for (String l : LUXURY) {
            if (n.contains(l)) {
                t.luxury = true;
            }
        }
    }

    // ------------------------------------------------------------------ 3. derive
    private static void derive(Analysis a, List<Txn> txns, Boolean business) {
        if (txns.isEmpty()) {
            a.incomeSource = 'no transactions shared';
            a.incomeStability = 0;
            a.incomeTrend = 'Unknown';
            a.incomeGrowthPct = 0;
            return;
        }
        Date first;
        Date last;
        for (Txn t : txns) {
            first = first == null || t.txnDate < first ? t.txnDate : first;
            last = last == null || t.txnDate > last ? t.txnDate : last;
        }
        a.fromDate = first.toStartOfMonth();
        a.toDate = last;
        a.months = first.monthsBetween(last) + 1;
        Integer nMonths = a.months;

        List<Decimal> income = zeros(nMonths);
        List<Decimal> outflow = zeros(nMonths);
        List<Decimal> emi = zeros(nMonths);
        List<Decimal> monthEndBalance = new List<Decimal>();
        Map<String, Map<Integer, Decimal>> lastBalance = new Map<String, Map<Integer, Decimal>>();
        Map<String, Decimal> salaryPayers = new Map<String, Decimal>();
        Integer luxuryCount = 0;
        for (Txn t : txns) {
            Integer idx = first.monthsBetween(t.txnDate);
            if (t.credit && CAT_INCOME.contains(t.category) && (business ? t.category == CAT_BUSINESS : t.category == CAT_SALARY || t.category == CAT_BUSINESS)) {
                income[idx] += t.amount;
                if (t.category == CAT_SALARY) {
                    salaryPayers.put(t.counterparty, t.amount);
                }
            }
            if (!t.credit && t.category != CAT_SELF) {
                outflow[idx] += t.amount;
                if (t.category == CAT_EMI) {
                    emi[idx] += t.amount;
                }
                if (BandhuEligibility.FOCUS.contains(t.category)) {
                    a.spend.put(t.category, (a.spend.containsKey(t.category) ? a.spend.get(t.category) : 0) + t.amount);
                    a.spendCount.put(t.category, (a.spendCount.containsKey(t.category) ? a.spendCount.get(t.category) : 0) + 1);
                }
                if (t.luxury) {
                    luxuryCount++;
                }
            }
            if (t.balance != null) {
                if (!lastBalance.containsKey(t.fip)) {
                    lastBalance.put(t.fip, new Map<Integer, Decimal>());
                }
                lastBalance.get(t.fip).put(idx, t.balance);
            }
        }

        // income: median of the last 6 months with income; stability over the whole window
        List<Decimal> recent = new List<Decimal>();
        for (Integer i = Math.max(0, nMonths - 6); i < nMonths; i++) {
            if (income[i] > 0) {
                recent.add(income[i]);
            }
        }
        a.netMonthlyIncome = recent.isEmpty() ? 0 : (median(recent) / 100).round(System.RoundingMode.DOWN) * 100;
        a.employer = salaryPayers.isEmpty() ? null : new List<String>(salaryPayers.keySet())[0];
        a.incomeSource = business ? 'business inflows'
            : salaryPayers.isEmpty() ? 'no salary credits seen' : 'salary credits from ' + String.join(new List<String>(salaryPayers.keySet()), ', ');
        Decimal mean = avg(income);
        Decimal sd = 0;
        for (Decimal v : income) {
            sd += (v - mean) * (v - mean);
        }
        sd = Decimal.valueOf(Math.sqrt((sd / nMonths).doubleValue()));
        a.incomeStability = mean == 0 ? 0 : Math.max(0, Math.min(100, (100 * (1 - sd / mean)).round(System.RoundingMode.HALF_UP).intValue()));
        Integer w = Math.min(6, nMonths / 2);
        Decimal early = avg(slice(income, 0, w));
        Decimal late = avg(slice(income, nMonths - w, nMonths));
        a.incomeGrowthPct = early == 0 ? 0 : ((late - early) / early * 100).setScale(1);
        a.incomeTrend = a.incomeGrowthPct > 5 ? 'Growing' : a.incomeGrowthPct < -5 ? 'Declining' : 'Flat';

        // obligations, outflow, surplus, balances (last 6 months for current obligations)
        a.monthlyObligations = avg(slice(emi, Math.max(0, nMonths - 6), nMonths)).setScale(0);
        a.foirPct = a.netMonthlyIncome == 0 ? 0 : (a.monthlyObligations / a.netMonthlyIncome * 100).setScale(0);
        a.avgMonthlyOutflow = avg(outflow).setScale(0);
        a.monthlySurplus = (avg(income) - a.avgMonthlyOutflow).setScale(0);
        for (Integer i = 0; i < nMonths; i++) {
            Decimal total = 0;
            Boolean hasAny = false;
            for (Map<Integer, Decimal> byMonth : lastBalance.values()) {
                if (byMonth.containsKey(i)) {
                    total += byMonth.get(i);
                    hasAny = true;
                }
            }
            if (hasAny) {
                monthEndBalance.add(total);
            }
        }
        a.avgBalance = monthEndBalance.isEmpty() ? null : avg(monthEndBalance).setScale(0);

        // spend by category, per month
        for (String c : a.spend.keySet()) {
            a.spend.put(c, (a.spend.get(c) / nMonths).setScale(0));
            a.monthlyCardSpend += a.spend.get(c);
        }
        List<String> ranked = new List<String>(a.spend.keySet());
        for (Integer i = 0; i < ranked.size(); i++) {
            for (Integer k = i + 1; k < ranked.size(); k++) {
                if (a.spend.get(ranked[k]) > a.spend.get(ranked[i])) {
                    String tmp = ranked[i];
                    ranked[i] = ranked[k];
                    ranked[k] = tmp;
                }
            }
        }
        for (Integer i = 0; i < Math.min(3, ranked.size()); i++) {
            if (a.share(ranked[i]) >= 0.1) {
                a.topCategories.add(ranked[i]);
            }
        }
        lifestyle(a, luxuryCount, nMonths);
        if (business) {
            seasonality(a, income, first);
        }
        anomalies(a, txns, income, first, business);
    }

    private static void lifestyle(Analysis a, Integer luxuryCount, Integer nMonths) {
        Decimal income = a.netMonthlyIncome == null || a.netMonthlyIncome == 0 ? 1 : a.netMonthlyIncome;
        Decimal travel = nz(a.spend.get('Travel')) + nz(a.spend.get('International'));
        if (travel / income >= 0.08 || count(a, 'Travel') >= nMonths * 1.5) {
            a.lifestyle.add('Frequent traveller (' + BandhuI18n.inrShort(travel) + '/month on travel)');
        }
        if (nz(a.spend.get('International')) > 0) {
            a.lifestyle.add('International spends (' + count(a, 'International') + ' in ' + nMonths + ' months)');
        }
        if (count(a, 'Dining') >= nMonths * 5) {
            a.lifestyle.add('Dines out often (' + (count(a, 'Dining') / nMonths) + ' times a month)');
        }
        if (luxuryCount >= nMonths / 2) {
            a.lifestyle.add('Premium retail and hotels (' + luxuryCount + ' transactions)');
        }
        if (nz(a.spend.get('Fuel')) / income >= 0.05) {
            a.lifestyle.add('Drives a lot (' + BandhuI18n.inrShort(a.spend.get('Fuel')) + '/month on fuel)');
        }
    }

    private static void seasonality(Analysis a, List<Decimal> income, Date first) {
        Map<Integer, List<Decimal>> byCalendarMonth = new Map<Integer, List<Decimal>>();
        for (Integer i = 0; i < income.size(); i++) {
            Integer cm = first.addMonths(i).month();
            if (!byCalendarMonth.containsKey(cm)) {
                byCalendarMonth.put(cm, new List<Decimal>());
            }
            byCalendarMonth.get(cm).add(income[i]);
        }
        Decimal med = median(income);
        Integer peak;
        Decimal peakValue = 0;
        for (Integer cm : byCalendarMonth.keySet()) {
            Decimal v = avg(byCalendarMonth.get(cm));
            if (v > peakValue) {
                peakValue = v;
                peak = cm;
            }
        }
        if (med > 0 && peakValue / med >= 1.3) {
            String name = Datetime.newInstance(2000, peak, 1).format('MMMM');
            a.seasonality = 'Inflows peak in ' + name + ' at ' + (peakValue / med).setScale(1) + 'x the median month'
                + (peak >= 9 && peak <= 11 ? ' (festive season)' : '');
        }
    }

    private static void anomalies(Analysis a, List<Txn> txns, List<Decimal> income, Date first, Boolean business) {
        Decimal base = a.netMonthlyIncome == null || a.netMonthlyIncome == 0 ? null : a.netMonthlyIncome;
        // round trips: money out to a party and back from the same party within 3 days, amount within 5%
        Map<String, Integer> roundTrips = new Map<String, Integer>();
        Set<Integer> matched = new Set<Integer>();
        for (Txn d : txns) {
            if (d.credit || d.category != CAT_TRANSFER || d.counterparty == null) {
                continue;
            }
            for (Txn c : txns) {
                if (c.credit && c.category == CAT_TRANSFER && c.counterparty == d.counterparty && !matched.contains(c.idx)
                        && d.txnDate.daysBetween(c.txnDate) >= 0 && d.txnDate.daysBetween(c.txnDate) <= 3
                        && (c.amount - d.amount).abs() <= d.amount * 0.05) {
                    matched.add(c.idx);
                    roundTrips.put(d.counterparty, (roundTrips.containsKey(d.counterparty) ? roundTrips.get(d.counterparty) : 0) + 1);
                    break;
                }
            }
        }
        for (String party : roundTrips.keySet()) {
            if (roundTrips.get(party) >= 2) {
                a.anomalies.add(roundTrips.get(party) + ' round-trip transfers with ' + party + ' (out and back within 3 days): possible circular transactions');
            }
        }
        // large credits that are neither income nor a round trip
        if (base != null) {
            for (Txn t : txns) {
                if (t.credit && t.category == CAT_TRANSFER && !matched.contains(t.idx) && t.amount > base * 1.5) {
                    a.anomalies.add('Unexplained credit of ' + BandhuI18n.inr(t.amount) + ' on ' + BandhuI18n.formatDate(t.txnDate)
                        + (t.counterparty == null ? '' : ' from ' + t.counterparty) + ' (' + (t.amount / base).setScale(1) + 'x monthly income)');
                }
            }
        }
        // months without salary (salaried)
        if (!business && base != null) {
            List<String> gaps = new List<String>();
            for (Integer i = 0; i < income.size(); i++) {
                if (income[i] == 0) {
                    gaps.add(Datetime.newInstance(first.addMonths(i), Time.newInstance(0, 0, 0, 0)).format('MMM yyyy'));
                }
            }
            if (!gaps.isEmpty()) {
                a.anomalies.add('No salary credit in ' + String.join(gaps, ', '));
            }
        }
        if (a.declaredIncome != null && a.declaredIncome > 0 && base != null && ((a.declaredIncome - base) / a.declaredIncome).abs() > 0.25) {
            a.anomalies.add('Declared income ' + BandhuI18n.inr(a.declaredIncome) + ' vs ' + BandhuI18n.inr(base) + ' seen in the statements');
        }
        if (base == null) {
            a.anomalies.add('No regular income credits found in the statements');
        }
    }

    // ------------------------------------------------------------------ helpers
    private static Integer count(Analysis a, String category) {
        return a.spendCount.containsKey(category) ? a.spendCount.get(category) : 0;
    }

    private static List<Decimal> zeros(Integer n) {
        List<Decimal> l = new List<Decimal>();
        for (Integer i = 0; i < n; i++) {
            l.add(0);
        }
        return l;
    }

    private static List<Decimal> slice(List<Decimal> l, Integer fromIdx, Integer toIdx) {
        List<Decimal> out = new List<Decimal>();
        for (Integer i = Math.max(0, fromIdx); i < Math.min(l.size(), toIdx); i++) {
            out.add(l[i]);
        }
        return out;
    }

    private static Decimal avg(List<Decimal> l) {
        if (l.isEmpty()) {
            return 0;
        }
        Decimal s = 0;
        for (Decimal v : l) {
            s += v;
        }
        return s / l.size();
    }

    private static Decimal median(List<Decimal> l) {
        if (l.isEmpty()) {
            return 0;
        }
        List<Decimal> s = l.clone();
        s.sort();
        Integer n = s.size();
        return Math.mod(n, 2) == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2;
    }

    private static Decimal nz(Decimal d) {
        return d == null ? 0 : d;
    }

    /** The stored analysis on a journey, or null. */
    public static Analysis fromJourney(Card_Journey__c j) {
        if (j == null || String.isBlank(j.AA_Insights__c)) {
            return null;
        }
        try {
            return (Analysis) JSON.deserialize(j.AA_Insights__c, Analysis.class);
        } catch (Exception e) {
            return null;
        }
    }
}
