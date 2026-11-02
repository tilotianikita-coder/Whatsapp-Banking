/**
 * External data providers, one interface each: credit bureau (CIBIL), fraud and dedupe (Hunter), employment (Karza /
 * EPFO / GST) and bank statement analysis (Perfios). LoanSeva_Provider__mdt names the class behind each one, so going
 * live is a metadata change: a live class implements the same interface, calls callout:<Named_Credential__c>, maps the
 * provider response into the same Underwriting_Check__c shape (with the raw report in Report_Data__c), and sets
 * Callout__c so it only ever runs from the qualification job.
 *
 * The mocks reuse the deterministic underwriting reports, so a demo PAN gives the same result at lead stage and in
 * the LOS. Both callers (LoanSevaQualification, LoanSevaUnderwriting) pass a Loan_Application__c as the subject; at
 * lead stage it is built in memory from the journey and never saved.
 */
public with sharing class LoanSevaProviders {
    public static final String CIBIL = 'CIBIL';
    public static final String HUNTER = 'Hunter';
    public static final String KARZA = 'Karza_EPFO';
    public static final String PERFIOS = 'Perfios';

    public interface BureauProvider {
        Underwriting_Check__c pull(Loan_Application__c subject);
    }

    public interface FraudProvider {
        Underwriting_Check__c screen(Loan_Application__c subject);
    }

    public interface EmploymentProvider {
        Underwriting_Check__c verify(Loan_Application__c subject, Set<String> documents);
    }

    public interface BankStatementProvider {
        Underwriting_Check__c analyse(Loan_Application__c subject, Set<String> documents);
    }

    public class MockCibil implements BureauProvider {
        public Underwriting_Check__c pull(Loan_Application__c subject) {
            return LoanSevaUnderwriting.bureauCheck(subject);
        }
    }

    public class MockHunter implements FraudProvider {
        public Underwriting_Check__c screen(Loan_Application__c subject) {
            return LoanSevaUnderwriting.dedupeCheck(subject);
        }
    }

    public class MockKarza implements EmploymentProvider {
        public Underwriting_Check__c verify(Loan_Application__c subject, Set<String> documents) {
            return LoanSevaUnderwriting.employmentCheck(subject, documents);
        }
    }

    public class MockPerfios implements BankStatementProvider {
        public Underwriting_Check__c analyse(Loan_Application__c subject, Set<String> documents) {
            return LoanSevaUnderwriting.bankStatementCheck(subject, documents);
        }
    }

    @TestVisible
    private static Map<String, LoanSeva_Provider__mdt> configs;

    public static BureauProvider bureau() {
        return (BureauProvider) instance(CIBIL, 'LoanSevaProviders.MockCibil');
    }

    public static FraudProvider fraud() {
        return (FraudProvider) instance(HUNTER, 'LoanSevaProviders.MockHunter');
    }

    public static EmploymentProvider employment() {
        return (EmploymentProvider) instance(KARZA, 'LoanSevaProviders.MockKarza');
    }

    public static BankStatementProvider bankStatements() {
        return (BankStatementProvider) instance(PERFIOS, 'LoanSevaProviders.MockPerfios');
    }

    /** True if the provider's class calls out: it then runs only in the qualification job, never inline. */
    public static Boolean makesCallouts(String provider) {
        LoanSeva_Provider__mdt c = config(provider);
        return c != null && c.Callout__c == true;
    }

    /** Days a result for the same PAN is reused instead of calling the provider again. */
    public static Integer cacheDays(String provider) {
        LoanSeva_Provider__mdt c = config(provider);
        return c == null || c.Cache_Days__c == null ? 0 : c.Cache_Days__c.intValue();
    }

    private static LoanSeva_Provider__mdt config(String provider) {
        if (configs == null) {
            configs = LoanSeva_Provider__mdt.getAll();
        }
        return configs.get(provider);
    }

    private static Object instance(String provider, String mock) {
        LoanSeva_Provider__mdt c = config(provider);
        String className = c == null || String.isBlank(c.Apex_Class__c) ? mock : c.Apex_Class__c;
        Type t = Type.forName(className);
        if (t == null) {
            throw new LoanSevaException('Provider class not found for ' + provider + ': ' + className);
        }
        return t.newInstance();
    }
}
