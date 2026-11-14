/**
 * Existing-to-bank (ETB) customer profile from the bank's records (mock core banking = Bank_Relationship__c; going live,
 * a real-time CBS / CRM API behind relationships()).
 *
 * Tier (product eligibility differs by tier, Bandhu_Card__mdt.ETB_Tiers__c):
 *   Wealth       balances + FDs + holdings of 10 lakh or more
 *   Loan         holds a retail loan (home, personal, other)
 *   Deposit      savings, salary or current account, or an FD
 *   Microfinance only microfinance loans (Bandhan's group-lending base): entry card only, on a clean repayment track
 * Relationship score (0-100): average balance 30, vintage 25, product breadth 25, repayment 20.
 * Blockers (journey held before anything else): a dormant / inoperative account, KYC not complete, an AML flag.
 */
public inherited sharing class BandhuCustomer {
    public static final String MICROFINANCE = 'Microfinance';
    public static final String DEPOSIT = 'Deposit';
    public static final String LOAN = 'Loan';
    public static final String WEALTH = 'Wealth';
    public static final Decimal WEALTH_THRESHOLD = 1000000;
    private static final Set<String> DEPOSITS = new Set<String>{ 'Savings Account', 'Salary Account', 'Current Account', 'Fixed Deposit' };
    private static final Set<String> RETAIL_LOANS = new Set<String>{ 'Loan', 'Home Loan', 'Personal Loan' };

    public class Insight {
        public String tier;
        public Integer score = 0;
        public Decimal averageBalance = 0;
        public Decimal fdValue = 0;
        public Decimal holdings = 0;
        public Decimal relationshipValue = 0;
        public Integer vintageMonths = 0;
        public Integer products = 0;
        public Decimal loanOutstanding = 0;
        public Decimal monthlyEmi = 0;
        public Integer maxDpd = 0;
        public Decimal salaryCredit;
        public String pan;
        public String preApprovedCard;
        public Decimal preApprovedLimit;
        public String blocker;          // internal reason
        public String blockerKind;      // Dormant / KYC / AML
        public List<String> holdingsList = new List<String>();
        public List<String> scoreParts = new List<String>();

        public List<String> lines() {
            List<String> l = new List<String>();
            l.add('Tier: ' + tier + ' · relationship score ' + score + '/100 (' + String.join(scoreParts, ', ') + ')');
            l.add('Products: ' + String.join(holdingsList, ' · '));
            l.add('Average balance ' + BandhuI18n.inr(averageBalance) + ' · FDs ' + BandhuI18n.inr(fdValue) + ' · holdings ' + BandhuI18n.inr(holdings)
                + ' · vintage ' + vintageMonths + ' months');
            if (loanOutstanding > 0) {
                l.add('Loans outstanding ' + BandhuI18n.inr(loanOutstanding) + ' · EMIs ' + BandhuI18n.inr(monthlyEmi) + '/month · worst DPD (12 months) ' + maxDpd);
            }
            if (blocker != null) {
                l.add('⚠ On hold: ' + blocker);
            }
            return l;
        }
    }

    public static Insight forContact(Id contactId) {
        return build(BandhuJourneyService.relationships(contactId));
    }

    public static Insight build(List<Bank_Relationship__c> rels) {
        Insight i = new Insight();
        if (rels.isEmpty()) {
            return null;
        }
        Set<String> types = new Set<String>();
        Boolean hasDeposit = false;
        Boolean hasRetailLoan = false;
        Boolean hasMicrofinance = false;
        for (Bank_Relationship__c r : rels) {
            if (r.Account_Status__c == 'Closed') {
                continue;
            }
            types.add(r.Relationship_Type__c);
            i.averageBalance += nz(r.Average_Balance__c);
            i.fdValue += nz(r.FD_Value__c);
            i.holdings += r.Relationship_Type__c == 'Demat' ? nz(r.Holding_Value__c) : 0;
            i.vintageMonths = Math.max(i.vintageMonths, r.Vintage_Months__c == null ? 0 : r.Vintage_Months__c.intValue());
            i.loanOutstanding += nz(r.Outstanding__c);
            i.monthlyEmi += nz(r.Monthly_EMI__c);
            i.maxDpd = Math.max(i.maxDpd, r.Max_DPD_12M__c == null ? 0 : r.Max_DPD_12M__c.intValue());
            hasDeposit |= DEPOSITS.contains(r.Relationship_Type__c);
            hasRetailLoan |= RETAIL_LOANS.contains(r.Relationship_Type__c);
            hasMicrofinance |= r.Relationship_Type__c == 'Microfinance Loan';
            if (r.Relationship_Type__c == 'Salary Account' && r.Monthly_Salary_Credit__c != null) {
                i.salaryCredit = r.Monthly_Salary_Credit__c;
            }
            if (String.isNotBlank(r.PAN__c) && i.pan == null) {
                i.pan = r.PAN__c;
            }
            if (r.Pre_Approved_Card__c != null && i.preApprovedCard == null) {
                i.preApprovedCard = r.Pre_Approved_Card__c;
                i.preApprovedLimit = r.Pre_Approved_Limit__c;
            }
            i.holdingsList.add(r.Relationship_Type__c + holdingNote(r));
            // blockers, most serious first
            if (r.AML_Flag__c == true) {
                setBlocker(i, 'AML', 'AML review open on the customer');
            } else if ((r.Account_Status__c == 'Dormant' || r.Account_Status__c == 'Inoperative') && i.blockerKind != 'AML') {
                setBlocker(i, 'Dormant', r.Relationship_Type__c + ' ' + mask(r.Account_Number__c) + ' is ' + r.Account_Status__c.toLowerCase() + ': reactivate first');
            } else if (r.KYC_Status__c != null && r.KYC_Status__c != 'Complete' && i.blocker == null) {
                setBlocker(i, 'KYC', 'KYC ' + r.KYC_Status__c.toLowerCase() + ' on ' + r.Relationship_Type__c);
            }
        }
        i.products = types.size();
        i.relationshipValue = i.averageBalance + i.fdValue + i.holdings;
        i.tier = i.relationshipValue >= WEALTH_THRESHOLD ? WEALTH : hasRetailLoan ? LOAN : hasDeposit ? DEPOSIT : hasMicrofinance ? MICROFINANCE : DEPOSIT;

        Integer bal = Math.min(30, (i.averageBalance / 20000).intValue());
        Integer vin = Math.min(25, i.vintageMonths * 25 / 60);
        Integer breadth = Math.min(25, i.products * 8);
        Integer repay = i.loanOutstanding == 0 && !hasMicrofinance ? 12 : i.maxDpd == 0 ? 20 : i.maxDpd <= 30 ? 8 : 0;
        i.score = bal + vin + breadth + repay;
        i.scoreParts = new List<String>{ 'balance ' + bal + '/30', 'vintage ' + vin + '/25', 'products ' + breadth + '/25', 'repayment ' + repay + '/20' };
        return i;
    }

    private static void setBlocker(Insight i, String kind, String reason) {
        i.blockerKind = kind;
        i.blocker = reason;
    }

    private static String holdingNote(Bank_Relationship__c r) {
        if (r.Relationship_Type__c == 'Fixed Deposit') {
            return ' ' + BandhuI18n.inrShort(r.FD_Value__c);
        }
        if (r.Relationship_Type__c == 'Demat' || r.Relationship_Type__c == 'Insurance') {
            return ' ' + BandhuI18n.inrShort(r.Holding_Value__c);
        }
        if (r.Outstanding__c != null) {
            return ' ' + BandhuI18n.inrShort(r.Outstanding__c) + ' outstanding';
        }
        return r.Average_Balance__c == null ? '' : ' AMB ' + BandhuI18n.inrShort(r.Average_Balance__c);
    }

    private static String mask(String acc) {
        return String.isBlank(acc) ? '' : 'XX' + acc.right(4);
    }

    private static Decimal nz(Decimal d) {
        return d == null ? 0 : d;
    }
}
