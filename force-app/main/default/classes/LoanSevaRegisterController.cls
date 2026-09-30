/**
 * Public (guest) registration page behind the QR code / link. Validates input and publishes
 * LoanSeva_Event__e; the subscriber creates the journey and sends the WhatsApp nudge.
 * The guest user never reads or writes CRM records directly.
 */
public with sharing class LoanSevaRegisterController {
    public String fullName { get; set; }
    public String mobile { get; set; }
    public String language { get; set; }
    public Boolean consent { get; set; }
    public String source { get; private set; }
    public Boolean submitted { get; private set; }
    public String errorMessage { get; private set; }
    public String maskedMobile { get; private set; }

    public LoanSevaRegisterController() {
        String src = ApexPages.currentPage() == null ? null : ApexPages.currentPage().getParameters().get('src');
        source = 'link'.equalsIgnoreCase(src) ? 'Link' : 'QR';
        language = LoanSevaI18n.EN;
        consent = false;
        submitted = false;
    }

    public List<SelectOption> getLanguageOptions() {
        return new List<SelectOption>{
            new SelectOption(LoanSevaI18n.EN, 'English'),
            new SelectOption(LoanSevaI18n.HI, 'हिंदी'),
            new SelectOption(LoanSevaI18n.MR, 'मराठी')
        };
    }

    public PageReference submit() {
        errorMessage = validate();
        if (errorMessage != null) {
            return null;
        }
        LoanSevaRegistrationService.Registration r = new LoanSevaRegistrationService.Registration();
        r.name = fullName.trim();
        r.mobile = mobile;
        r.language = language;
        r.source = source;
        r.consent = consent;
        try {
            LoanSevaRegistrationService.publish(r);
            maskedMobile = '+91 XXXXXX' + LoanSevaJourneyService.normalizeMobile(mobile).right(4);
            submitted = true;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'LoanSeva registration failed: ' + e.getMessage());
            errorMessage = 'Something went wrong on our side. Please try again in a moment.';
        }
        return null;
    }

    @TestVisible
    private String validate() {
        if (String.isBlank(fullName) || fullName.trim().length() < 2) {
            return 'Please enter your full name.';
        }
        if (!LoanSevaJourneyService.isValidIndianMobile(mobile)) {
            return 'Please enter a valid 10-digit Indian mobile number.';
        }
        if (consent != true) {
            return 'Please agree to receive messages on WhatsApp so we can send your offer.';
        }
        return null;
    }
}
