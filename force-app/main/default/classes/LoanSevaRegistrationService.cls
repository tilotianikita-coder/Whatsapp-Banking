/**
 * Stage 0 -> Stage 1: a customer registers (QR / link page), we link them to a Contact (or capture a Lead),
 * open a Loan_Journey__c at stage Nudge and send the personalised WhatsApp nudge. Fully bulkified.
 */
public with sharing class LoanSevaRegistrationService {
    public static final String EVENT_REGISTER = 'Register';

    public class Registration {
        public String mobile;
        public String name;
        public String language;
        public String source;
        public Boolean consent;
    }

    /** Called from the guest page: validates, then hands off via platform event (guest users cannot create messaging records). */
    public static void publish(Registration r) {
        EventBus.publish(new LoanSeva_Event__e(
            Event_Type__c = EVENT_REGISTER,
            Mobile__c = LoanSevaJourneyService.normalizeMobile(r.mobile),
            Customer_Name__c = r.name == null ? null : r.name.trim().abbreviate(120),
            Language__c = r.language,
            Source__c = r.source,
            Consent__c = r.consent == true
        ));
    }

    public static void handleEvents(List<LoanSeva_Event__e> events) {
        List<Registration> regs = new List<Registration>();
        for (LoanSeva_Event__e e : events) {
            if (e.Event_Type__c == EVENT_REGISTER) {
                Registration r = new Registration();
                r.mobile = e.Mobile__c;
                r.name = e.Customer_Name__c;
                r.language = e.Language__c;
                r.source = e.Source__c;
                r.consent = e.Consent__c;
                regs.add(r);
            }
        }
        register(regs);
    }

    /** Returns journeys by mobile. Invalid mobiles and missing consent are skipped. */
    public static Map<String, Loan_Journey__c> register(List<Registration> regs) {
        Map<String, Registration> byMobile = new Map<String, Registration>();
        for (Registration r : regs) {
            String m = LoanSevaJourneyService.normalizeMobile(r.mobile);
            if (m != null && LoanSevaJourneyService.isValidIndianMobile(m) && r.consent == true) {
                byMobile.put(m, r);
            }
        }
        if (byMobile.isEmpty()) {
            return new Map<String, Loan_Journey__c>();
        }

        List<String> variants = new List<String>();
        for (String m : byMobile.keySet()) {
            variants.addAll(LoanSevaJourneyService.mobileVariants(m));
        }
        Map<String, Contact> contacts = new Map<String, Contact>();
        for (Contact c : [
            SELECT Id, FirstName, LastName, Name, MobilePhone, Phone
            FROM Contact
            WHERE MobilePhone IN :variants OR Phone IN :variants
            ORDER BY CreatedDate ASC
        ]) {
            for (String p : new List<String>{ c.MobilePhone, c.Phone }) {
                String m = LoanSevaJourneyService.normalizeMobile(p);
                if (m != null && byMobile.containsKey(m) && !contacts.containsKey(m)) {
                    contacts.put(m, c);
                }
            }
        }
        Map<Id, Existing_Loan__c> loanByContact = new Map<Id, Existing_Loan__c>();
        for (Existing_Loan__c l : [
            SELECT Id, Contact__c, Pre_Approved_Limit__c
            FROM Existing_Loan__c
            WHERE Contact__c IN :new Map<Id, Contact>(contacts.values()).keySet() AND Status__c = 'Active'
            ORDER BY Pre_Approved_Limit__c DESC NULLS LAST
        ]) {
            if (!loanByContact.containsKey(l.Contact__c)) {
                loanByContact.put(l.Contact__c, l);
            }
        }

        // Prospects without a Contact are captured as Leads so the RM still gets the intent.
        Map<String, Lead> leads = new Map<String, Lead>();
        Set<String> leadMobiles = new Set<String>(byMobile.keySet());
        leadMobiles.removeAll(contacts.keySet());
        if (!leadMobiles.isEmpty()) {
            for (Lead l : [SELECT Id, MobilePhone FROM Lead WHERE MobilePhone IN :leadMobiles AND IsConverted = false]) {
                leads.put(l.MobilePhone, l);
            }
            List<Lead> newLeads = new List<Lead>();
            for (String m : leadMobiles) {
                if (!leads.containsKey(m)) {
                    String name = byMobile.get(m).name;
                    Lead l = new Lead(
                        LastName = String.isBlank(name) ? 'WhatsApp ' + m.right(4) : name.abbreviate(80),
                        Company = 'Individual',
                        MobilePhone = m,
                        LeadSource = 'Other',
                        Description = 'Registered for Kotak PL Top-Up via LoanSeva (' + byMobile.get(m).source + ')'
                    );
                    newLeads.add(l);
                    leads.put(m, l);
                }
            }
            insert newLeads;
        }

        // Reuse an open journey for the same mobile rather than creating duplicates.
        Map<String, Loan_Journey__c> journeys = new Map<String, Loan_Journey__c>();
        for (Loan_Journey__c j : [
            SELECT Id, Mobile__c, Stage__c, Status__c
            FROM Loan_Journey__c
            WHERE Mobile__c IN :byMobile.keySet() AND Status__c IN ('Active', 'Dropped')
            ORDER BY CreatedDate ASC
        ]) {
            journeys.put(j.Mobile__c, j);
        }
        Datetime now = Datetime.now();
        for (String m : byMobile.keySet()) {
            Registration r = byMobile.get(m);
            Contact c = contacts.get(m);
            Loan_Journey__c j = journeys.containsKey(m) ? journeys.get(m) : new Loan_Journey__c(Stage__c = 'Nudge', Mobile__c = m);
            j.Status__c = LoanSevaJourneyService.STATUS_ACTIVE;
            j.Source__c = r.source == 'Link' ? 'Link' : 'QR';
            String lang = LoanSevaI18n.parseLanguage(r.language);
            j.Language__c = lang == null ? LoanSevaI18n.EN : lang;
            j.Consent_WhatsApp__c = true;
            j.Contact__c = c == null ? null : c.Id;
            j.Lead__c = c == null && leads.containsKey(m) ? leads.get(m).Id : null;
            // Existing_Loan__c is linked only after identity verification (the engine uses it as the verified-identity marker)
            j.Customer_Name__c = c != null ? c.Name : r.name;
            j.Nudge_Sent_At__c = now;
            j.Last_Activity__c = now;
            journeys.put(m, j);
        }
        upsert journeys.values();

        List<LoanSevaWhatsAppSender.Outbound> outbound = new List<LoanSevaWhatsAppSender.Outbound>();
        String definition = LoanSevaConfig.get().Nudge_Definition__c;
        for (String m : journeys.keySet()) {
            Loan_Journey__c j = journeys.get(m);
            Contact c = contacts.get(m);
            Existing_Loan__c loan = c == null ? null : loanByContact.get(c.Id);
            outbound.add(new LoanSevaWhatsAppSender.Outbound(j.Id, nudgeText(c, loan, j.Language__c), definition));
        }
        LoanSevaWhatsAppSender.enqueue(outbound);
        return journeys;
    }

    public static String nudgeText(Contact c, Existing_Loan__c loan, String lang) {
        if (c != null && loan != null && loan.Pre_Approved_Limit__c != null) {
            return LoanSevaI18n.msg('Nudge', lang, new Map<String, Object>{
                'name' => String.isBlank(c.FirstName) ? c.LastName : c.FirstName,
                'limit' => LoanSevaI18n.inrShort(loan.Pre_Approved_Limit__c)
            });
        }
        return LoanSevaI18n.msg('Nudge_Generic', lang);
    }
}
