"""Generates the Bandhu (Bandhan Bank credit card onboarding) data model under bandhan/main/default/objects.
Run from the project root: python3 scripts/bandhan/gen_model.py
"""
import os
from xml.sax.saxutils import escape

OBJ = 'bandhan/main/default/objects'


def picklist(values, default=None, restricted=True):
    vals = ''.join(f'''            <value>
                <fullName>{escape(v)}</fullName>
                <default>{str(v == default).lower()}</default>
                <label>{escape(v)}</label>
            </value>
''' for v in values)
    return f'''    <type>Picklist</type>
    <valueSet>
        <restricted>{str(restricted).lower()}</restricted>
        <valueSetDefinition>
            <sorted>false</sorted>
{vals}        </valueSetDefinition>
    </valueSet>
'''


def text(n):
    return f'    <type>Text</type>\n    <length>{n}</length>\n'


def number(precision, scale=0, currency=False):
    return f'    <type>{"Currency" if currency else "Number"}</type>\n    <precision>{precision}</precision>\n    <scale>{scale}</scale>\n'


def long_text(n=32768, lines=5):
    return f'    <type>LongTextArea</type>\n    <length>{n}</length>\n    <visibleLines>{lines}</visibleLines>\n'


def lookup(target, rel, rel_label, master=False):
    if master:
        return (f'    <type>MasterDetail</type>\n    <referenceTo>{target}</referenceTo>\n    <relationshipName>{rel}</relationshipName>\n'
                f'    <relationshipLabel>{rel_label}</relationshipLabel>\n    <relationshipOrder>0</relationshipOrder>\n'
                '    <reparentableMasterDetail>false</reparentableMasterDetail>\n    <writeRequiresMasterRead>false</writeRequiresMasterRead>\n')
    return (f'    <type>Lookup</type>\n    <referenceTo>{target}</referenceTo>\n    <relationshipName>{rel}</relationshipName>\n'
            f'    <relationshipLabel>{rel_label}</relationshipLabel>\n    <deleteConstraint>SetNull</deleteConstraint>\n')


CHECKBOX = '    <type>Checkbox</type>\n    <defaultValue>false</defaultValue>\n'
DATE = '    <type>Date</type>\n'
DATETIME = '    <type>DateTime</type>\n'
EMAIL = '    <type>Email</type>\n'
MONEY = number(16, 0, currency=True)

CARDS = ['Sparks', 'Ignite', 'Flare', 'Lumina', 'Voyage', 'Shield']
LANGS = ['EN', 'HI', 'BN']
CHANNELS = ['WhatsApp', 'Web', 'Branch']
STAGES = ['Start', 'Verify', 'Needs', 'Profile', 'Recommend', 'KYC', 'Decision', 'Issued']
GATES = ['Serviceability', 'Consent', 'Dedupe & Fraud', 'Credit Bureau', 'Income', 'Employment', 'Card Eligibility']
CHECKS = ['PAN Verification', 'Aadhaar eKYC', 'Credit Bureau', 'Income Verification', 'Video KYC', 'Dedupe & Fraud', 'Customer Due Diligence', 'Bandhan Score', 'Card Policy']
ETB_TIERS = ['Microfinance', 'Deposit', 'Loan', 'Wealth']
RESULTS = ['Pass', 'Refer', 'Fail', 'Pending']

# Shared applicant fields on the journey and the application.
APPLICANT = {
    'Mobile__c': ('Mobile', text(20), '10-digit mobile number (no +91).'),
    'PAN__c': ('PAN', text(10), 'PAN as given by the applicant; shown back masked only.'),
    'Date_Of_Birth__c': ('Date of Birth', DATE, None),
    'Email__c': ('Email', EMAIL, None),
    'PIN_Code__c': ('PIN Code', text(6), None),
    'City__c': ('City', text(60), None),
    'Employment_Type__c': ('Employment Type', picklist(['Salaried', 'Self-employed', 'Business']), 'Primary income source: drives the bureau strategy and product eligibility.'),
    'Company_Name__c': ('Company / Business', text(120), None),
    'Monthly_Income__c': ('Monthly Income', MONEY, 'Declared net monthly income.'),
    'Verified_Income__c': ('Verified Income', MONEY, 'Monthly income verified through Account Aggregator (mock) or bank salary credits.'),
    'Customer_Type__c': ('Customer Type', picklist(['Existing', 'New']), 'Existing = holds a Bandhan Bank account (ETB); New = new to bank (NTB).'),
    'CIBIL_Score__c': ('CIBIL Score', number(3), 'Soft-pull score (mock).'),
    'Eligible_Cards__c': ('Eligible Cards', text(255), 'Semicolon-separated cards the applicant qualifies for.'),
    'Contact__c': ('Contact', None, None),   # filled per object below
}

FIELDS = {
    'Card_Journey__c': {
        **{k: v for k, v in APPLICANT.items() if k != 'Contact__c'},
        'Contact__c': ('Contact', lookup('Contact', 'Card_Journeys', 'Card Journeys'), 'Existing customer, when the mobile matches.'),
        'Lead__c': ('Lead', lookup('Lead', 'Card_Journeys', 'Card Journeys'), 'Prospect lead for a new-to-bank applicant.'),
        'Card_Application__c': ('Card Application', lookup('Card_Application__c', 'Journeys', 'Journeys'), None),
        'Channel__c': ('Channel', picklist(CHANNELS, 'WhatsApp'), None),
        'Language__c': ('Language', picklist(LANGS, 'EN'), None),
        'Status__c': ('Status', picklist(['Active', 'Dropped', 'Completed', 'Exited'], 'Active'), None),
        'Stage__c': ('Stage', picklist(STAGES, 'Start'), None),
        'Step__c': ('Step', text(40), 'What the journey is waiting for (the engine routes on this).'),
        'Customer_Name__c': ('Customer Name', text(120), None),
        'Consent__c': ('Consent', CHECKBOX, 'DPDP consent to process data for this application.'),
        'Consent_At__c': ('Consent At', DATETIME, None),
        'Bureau_Consent__c': ('Bureau Consent', CHECKBOX, 'Consent to a soft credit bureau check.'),
        'OTP_Verified__c': ('OTP Verified', CHECKBOX, None),
        'OTP_Attempts__c': ('OTP Attempts', number(2), None),
        'Spend_Focus__c': ('Spend Focus', text(255), 'Semicolon-separated: Travel; International; Dining; Groceries; Shopping; Fuel.'),
        'Monthly_Spend__c': ('Monthly Card Spend', MONEY, 'Expected monthly spend on the card.'),
        'Travel_Frequency__c': ('Travel', picklist(['Rarely', 'Domestic', 'International']), None),
        'Fee_Preference__c': ('Fee Preference', picklist(['Lowest fee', 'Best benefits']), None),
        'Recommended_Card__c': ('Recommended Card', picklist(CARDS), None),
        'Alternative_Card__c': ('Alternative Card', picklist(CARDS), None),
        'Upgrade_Card__c': ('Next Card Up', picklist(CARDS), 'The next card the applicant would qualify for with a higher income or score.'),
        'Recommendation_Reason__c': ('Recommendation Reason', long_text(32768, 4), None),
        'Chosen_Card__c': ('Chosen Card', picklist(CARDS), None),
        'Credit_Limit__c': ('Indicative Credit Limit', MONEY, None),
        'KYC_Status__c': ('KYC Status', picklist(['Not started', 'Aadhaar verified', 'Video KYC pending', 'Complete'], 'Not started'), None),
        'Messaging_Session_Id__c': ('Messaging Session Id', text(18), None),
        'Web_Token__c': ('Web Session Token', text(40), 'Opaque token binding a web chat to this journey.'),
        'Reference_Number__c': ('Reference Number', text(30), None),
        'Last_Activity__c': ('Last Activity', DATETIME, None),
        'Dropped_At__c': ('Dropped At', DATETIME, None),
        'Drop_Point__c': ('Drop Point', text(80), None),
        'Fields_Done__c': ('Details Shared', number(3), None),
        'Nudges_Sent__c': ('Nudges Sent', number(2), None),
        'Last_Nudged__c': ('Last Nudged', DATETIME, None),
        'Escalated__c': ('Escalated', CHECKBOX, None),
        'Last_Send_Status__c': ('Last Send Status', text(255), None),
        'Bandhan_Score__c': ('Bandhan Score', number(4), 'Bandhan scorecard (BandhuScore), 0-1000.'),
        'Applied_Card__c': ('Applied-for Card', picklist(CARDS), 'The card the customer asked for, when they do not qualify for it.'),
        'FD_Amount__c': ('FD Amount', MONEY, 'Secured card: the fixed deposit to book (recommended from the limit needed).'),
        'ETB_Tier__c': ('Customer Tier', picklist(ETB_TIERS), 'Existing customers: Microfinance only / Deposit (savings, current, salary, FD) / Loan / Wealth (balances, FDs and holdings of 10 lakh+).'),
        'Relationship_Score__c': ('Relationship Score', number(3), 'Existing customers, out of 100: balance, vintage, product breadth and repayment.'),
        'Hold_Reason__c': ('Hold Reason', text(255), 'Why the journey is on hold before it can go on (dormant account, KYC due, AML review). Internal.'),
        'Bureau_Data__c': ('Bureau Report', long_text(32768, 3), 'Soft-pull bureau report (mock) as JSON: accounts, DPD, enquiries, utilisation, write-offs.'),
        'Bureau_At__c': ('Bureau Pulled At', DATETIME, None),
        'AA_Consent_Id__c': ('AA Consent Id', text(40), 'Account Aggregator consent artefact (mock FIU): credit underwriting, 24 months, valid 30 days.'),
        'AA_Consent_At__c': ('AA Consent At', DATETIME, None),
        'AA_Insights__c': ('AA Cash-flow Analysis', long_text(32768, 4), 'BandhuCashFlow analysis of the Account Aggregator statements (JSON): income, stability, FOIR, spend by category, lifestyle, anomalies.'),
    },
    'Card_Application__c': {
        **{k: v for k, v in APPLICANT.items() if k != 'Contact__c'},
        'Contact__c': ('Contact', lookup('Contact', 'Card_Applications', 'Card Applications'), None),
        'Lead__c': ('Lead', lookup('Lead', 'Card_Applications', 'Card Applications'), None),
        'Card_Journey__c': ('Card Journey', lookup('Card_Journey__c', 'Card_Applications', 'Card Applications'), None),
        'Applicant_Name__c': ('Applicant Name', text(120), None),
        'Bandhan_Score__c': ('Bandhan Score', number(4), 'Bandhan scorecard (BandhuScore), 0-1000, at submission.'),
        'Score_Band__c': ('Score Band', text(2), None),
        'Score_Factors__c': ('Score Factors', long_text(32768, 4), 'Audit log: each scorecard factor, its value and points (JSON).'),
        'Model_Version__c': ('Model Version', text(60), None),
        'Limit_Range__c': ('Recommended Limit Range', text(60), None),
        'FD_Amount__c': ('FD Amount', MONEY, 'Secured card: the fixed deposit under lien.'),
        'Card_Product__c': ('Card', picklist(CARDS), None),
        'Credit_Limit__c': ('Credit Limit', MONEY, None),
        'Channel__c': ('Channel', picklist(CHANNELS), None),
        'Recommendation__c': ('Recommendation', picklist(['Approve', 'Refer', 'Decline']), 'From the decision rules (assist only: the underwriter decides on a refer).'),
        'Recommendation_Reasons__c': ('Recommendation Reasons', long_text(32768, 6), None),
        'Fit_Summary__c': ('Why This Card', long_text(32768, 4), None),
        'Status__c': ('Status', picklist(['Submitted', 'Under Review', 'Approved', 'Card Issued', 'Declined', 'Cancelled'], 'Submitted'), None),
        'MITC_Sent_At__c': ('MITC Sent At', DATETIME, 'Most Important Terms and Conditions delivered (RBI Master Direction on Credit Cards, 2022).'),
        'Activation_Due__c': ('Activation Due', DATE, 'Issue date + 30 days: without OTP activation consent by then, the card is closed (RBI MD 2022).'),
        'Activated_At__c': ('Activated At', DATETIME, 'Card activated with the customer\'s OTP consent.'),
        'Cooling_Off_Until__c': ('Cooling-off Until', DATE, 'The customer can cancel without charges until this date (PLACEHOLDER: 7 days).'),
        'Hard_Enquiry_At__c': ('Hard Enquiry Declared At', DATETIME, 'The customer was told a hard credit enquiry runs on submission, and confirmed.'),
        'Decision__c': ('Decision', picklist(['Approved', 'Declined']), None),
        'Decision_Notes__c': ('Decision Notes', long_text(32768, 4), None),
        'Decision_By__c': ('Decision By', lookup('User', 'Card_Decisions', 'Card Decisions'), None),
        'Decision_At__c': ('Decision At', DATETIME, None),
        'Submitted_At__c': ('Submitted At', DATETIME, None),
        'Reference_Number__c': ('Reference Number', text(30), None),
        'Card_Number_Masked__c': ('Virtual Card', text(19), 'Masked virtual card number (mock issuance).'),
        'Card_Issued_At__c': ('Card Issued At', DATETIME, None),
    },
    'Card_Check__c': {
        'Card_Application__c': ('Card Application', lookup('Card_Application__c', 'Card_Checks', 'Checks', master=True), None),
        'Check__c': ('Check', picklist(CHECKS), None),
        'Provider__c': ('Provider', text(80), None),
        'Result__c': ('Result', picklist(RESULTS), None),
        'Score__c': ('Score', number(6), None),
        'Summary__c': ('Summary', text(255), None),
        'Details__c': ('Details', long_text(32768, 6), None),
        'Report_Data__c': ('Report Data', long_text(131072, 3), 'Mock provider report as JSON.'),
        'Sort_Order__c': ('Sort Order', number(3), None),
        'Run_At__c': ('Run At', DATETIME, None),
    },
    'Bank_Relationship__c': {
        'Contact__c': ('Customer', lookup('Contact', 'Bank_Relationships', 'Bandhan Bank Relationships'), None),
        'Relationship_Type__c': ('Relationship', picklist(['Savings Account', 'Salary Account', 'Current Account', 'Fixed Deposit', 'Loan',
                                                            'Home Loan', 'Personal Loan', 'Microfinance Loan', 'Demat', 'Insurance']), None),
        'Account_Status__c': ('Account Status', picklist(['Active', 'Dormant', 'Inoperative', 'Closed'], 'Active'), 'Dormant / inoperative accounts must be reactivated before a card journey.'),
        'KYC_Status__c': ('KYC Status', picklist(['Complete', 'Re-KYC due', 'Incomplete'], 'Complete'), None),
        'AML_Flag__c': ('AML Flag', CHECKBOX, 'Under AML review: the card journey is held for compliance.'),
        'Outstanding__c': ('Loan Outstanding', MONEY, None),
        'Monthly_EMI__c': ('Monthly EMI', MONEY, None),
        'Max_DPD_12M__c': ('Max DPD (12 months)', number(4), 'Repayment track on this loan: worst days past due in the last 12 months.'),
        'Holding_Value__c': ('Holding Value', MONEY, 'Demat / mutual fund value, or insurance sum assured.'),
        'Account_Number__c': ('Account Number', text(20), None),
        'Average_Balance__c': ('Average Monthly Balance', MONEY, None),
        'FD_Value__c': ('FD Value', MONEY, None),
        'Monthly_Salary_Credit__c': ('Monthly Salary Credit', MONEY, None),
        'Vintage_Months__c': ('Relationship Vintage (months)', number(4), None),
        'PAN__c': ('PAN on file', text(10), 'KYC already done for this customer (mock core banking).'),
        'Pre_Approved_Card__c': ('Pre-approved Card', picklist(CARDS), 'From the bank\'s pre-approved offer base (mock).'),
        'Pre_Approved_Limit__c': ('Pre-approved Limit', MONEY, None),
    },
    'Contact': {
        'Bandhu_Bureau_Data__c': ('Bandhu Bureau Report', long_text(32768, 3), 'Cached soft-pull bureau report (mock) for the card journey; reused for 30 days.'),
        'Bandhu_Bureau_At__c': ('Bandhu Bureau Pulled At', DATETIME, None),
    },
    'Lead': {
        'Bandhu_Journey__c': ('Card Journey', lookup('Card_Journey__c', 'Bandhu_Leads', 'Leads'), None),
        'Bandhu_Intent_Score__c': ('Card Intent Score', number(3), 'Out of 100: how far the applicant got and what they told us.'),
        'Bandhu_Credit_Score__c': ('Card Credit Score', number(3), 'Out of 100: CIBIL, income headroom and checks run so far.'),
        'Bandhu_Combined_Score__c': ('Card Combined Score', number(3), None),
        'Bandhu_CIBIL__c': ('CIBIL (soft pull)', number(3), None),
        'Bandhu_Recommended_Card__c': ('Recommended Card', picklist(CARDS, restricted=False), 'Unrestricted: Lead record types do not pick up new card values.'),
        'Bandhu_Eligible_Cards__c': ('Eligible Cards', text(255), None),
        'Bandhu_Drop_Point__c': ('Drop Point', text(80), None),
        'Bandhu_Score_Detail__c': ('Score Detail', long_text(32768, 6), None),
        'Bandhu_Last_Nudged__c': ('Last Nudged', DATETIME, None),
        'Bandhu_Stage_Gate__c': ('Card Stage Gate', text(80), 'Qualified, Waiting at <gate> or Knocked out at <gate>.'),
        'Bandhu_Region__c': ('Card Region', text(80), None),
        'Bandhu_Serviceable__c': ('Serviceable', CHECKBOX, None),
        'Bandhu_Credit_Confidence__c': ('Credit Confidence', text(20), 'High / Medium / Low: how many credit gates had data.'),
    },
    'Bandhu_Consent__c': {
        'Card_Journey__c': ('Card Journey', lookup('Card_Journey__c', 'Consents', 'Consents'), None),
        'Card_Application__c': ('Card Application', lookup('Card_Application__c', 'Consents', 'Consents'), None),
        'Contact__c': ('Customer', lookup('Contact', 'Bandhu_Consents', 'Card Consents'), None),
        'Type__c': ('Type', picklist(['DPDP data processing', 'Soft credit check', 'Account Aggregator', 'Hard credit enquiry', 'MITC delivered',
                                      'Card activation', 'Limit enhancement', 'Card cancellation', 'Consent withdrawn']), None),
        'Purpose__c': ('Purpose', text(255), None),
        'Given_At__c': ('Given At', DATETIME, None),
        'Expires_On__c': ('Expires On', DATE, 'Time-bound consents (Account Aggregator, offers).'),
        'Retain_Until__c': ('Retain Until', DATE, 'DPDP retention: PLACEHOLDER 180 days for journeys that did not become a customer, 5 years after closure for cardholders.'),
        'Channel__c': ('Channel', text(20), None),
        'Reference__c': ('Reference', text(80), 'Consent artefact / OTP reference / document version.'),
        'Text_Shown__c': ('Text Shown', long_text(32768, 3), 'The exact wording the customer saw.'),
        'Status__c': ('Status', picklist(['Active', 'Withdrawn', 'Expired'], 'Active'), None),
    },
    'Bandhu_Lead_Check__c': {
        'Lead__c': ('Lead', lookup('Lead', 'Bandhu_Lead_Checks', 'Card Qualification Checks'), None),
        'Card_Journey__c': ('Card Journey', lookup('Card_Journey__c', 'Lead_Checks', 'Lead Checks'), None),
        'Gate__c': ('Gate', picklist(GATES), None),
        'Check__c': ('Check', text(80), None),
        'Provider__c': ('Provider', text(80), None),
        'Result__c': ('Result', picklist(RESULTS + ['Skipped']), None),
        'Score__c': ('Score', number(6), 'Provider score (CIBIL score, verified income, fraud hits).'),
        'Points__c': ('Credit Points', number(3), 'Points this gate adds to the credit score.'),
        'Max_Points__c': ('Max Points', number(3), None),
        'Knockout__c': ('Knock-out', CHECKBOX, 'This gate disqualifies the lead (no RM task, no nudge).'),
        'Summary__c': ('Summary', text(255), None),
        'Details__c': ('Details', long_text(32768, 4), None),
        'Sort_Order__c': ('Sort Order', number(3), None),
        'Run_At__c': ('Run At', DATETIME, None),
    },
    'Bandhu_Region__mdt': {
        'PIN_Prefixes__c': ('PIN Prefixes', text(255), 'Comma-separated PIN code prefixes; the longest match wins; * = everything else.'),
        'Serviceable__c': ('Serviceable', CHECKBOX, None),
        'RM_Username__c': ('RM Username', text(120), 'Username of the RM who owns leads in this region (blank = Bandhu_Config RM).'),
    },
    'Bandhu_Card__mdt': {
        'Tier__c': ('Tier', number(2), '1 = entry ... 4 = premium.'),
        'Tagline__c': ('Tagline', text(120), None),
        'Joining_Fee__c': ('Joining Fee', number(8), 'PLACEHOLDER: confirm with the Bandhan Bank schedule of charges.'),
        'Annual_Fee__c': ('Annual Fee', number(8), 'PLACEHOLDER.'),
        'Fee_Waiver__c': ('Fee Waiver', text(160), 'PLACEHOLDER.'),
        'Rewards__c': ('Rewards', text(160), None),
        'Accelerated__c': ('Accelerated Rewards', text(160), None),
        'Welcome__c': ('Welcome Benefit', text(200), None),
        'Milestone__c': ('Milestone', text(200), None),
        'Lounge__c': ('Lounge', text(160), None),
        'Dining__c': ('Dining', text(160), None),
        'Movies__c': ('Movies', text(160), None),
        'Fuel__c': ('Fuel', text(160), None),
        'Extras__c': ('Extras', text(255), None),
        'Min_Monthly_Income__c': ('Min Monthly Income', number(10), 'PLACEHOLDER eligibility threshold.'),
        'Min_Cibil__c': ('Min CIBIL', number(3), 'PLACEHOLDER: at or above qualifies.'),
        'Refer_Cibil__c': ('Refer CIBIL', number(3), 'Between this and Min CIBIL: underwriter refer.'),
        'ETB_Min_Balance__c': ('ETB Relationship Route', number(12), 'Existing customers with this average balance + FD value also qualify (relationship route).'),
        'ETB_Tiers__c': ('ETB Tiers', text(120), 'Existing-customer tiers this card is offered to (semicolon-separated: Microfinance; Deposit; Loan; Wealth).'),
        'Limit_Multiple__c': ('Limit Multiple', number(4, 1), 'Credit limit = monthly income x this.'),
        'Limit_Min__c': ('Limit Min', number(10), None),
        'Limit_Max__c': ('Limit Max', number(10), None),
        'Fit_Travel__c': ('Fit: Travel', number(1), '0-5 weight for the recommendation.'),
        'Fit_International__c': ('Fit: International', number(1), None),
        'Fit_Dining__c': ('Fit: Dining & Movies', number(1), None),
        'Fit_Groceries__c': ('Fit: Groceries', number(1), None),
        'Fit_Shopping__c': ('Fit: Shopping', number(1), None),
        'Fit_Fuel__c': ('Fit: Fuel', number(1), None),
        'Fit_Low_Fee__c': ('Fit: Low Fee', number(1), None),
        'Fit_High_Spend__c': ('Fit: High Spend', number(1), None),
        'Tier_Label__c': ('Tier Label', text(40), 'Classic / Silver / Gold / Platinum / Co-branded / Secured.'),
        'Co_Brand__c': ('Co-brand Partner', text(80), 'PLACEHOLDER partner for co-branded cards.'),
        'Secured__c': ('Secured (against FD)', CHECKBOX, 'Issued against a fixed deposit lien: no income or bureau threshold.'),
        'FD_Limit_Pct__c': ('Limit as % of FD', number(3), 'Secured cards: credit limit as a percentage of the FD.'),
        'Limit_Multiple_Max__c': ('Max Income Multiple', number(3, 2), 'Cap on the income multiple after score and relationship uplifts.'),
        'Color__c': ('Card Colour', text(20), 'Hex colour for the card art on the web journey.'),
    },
    'Bandhu_Config__mdt': {
        'Demo_OTP__c': ('Demo OTP', text(6), None),
        'Max_OTP_Attempts__c': ('Max OTP Attempts', number(2), None),
        'Min_Age__c': ('Min Age', number(3), None),
        'Max_Age_Salaried__c': ('Max Age Salaried', number(3), None),
        'Max_Age_Self_Employed__c': ('Max Age Self-employed', number(3), None),
        'Decline_Cibil__c': ('Decline CIBIL', number(3), 'Below this: decline for every card.'),
        'Send_Mode__c': ('Send Mode', text(40), 'ConversationMessage or LogOnly.'),
        'WhatsApp_Channel__c': ('WhatsApp Channel', text(80), None),
        'Nudge_Definition__c': ('Nudge Definition', text(80), None),
        'Country_Code__c': ('Country Code', text(4), None),
        'Idle_Minutes__c': ('Idle Minutes Before Drop', number(5), None),
        'RM_Username__c': ('RM Username', text(120), None),
        'Site_Url__c': ('Web Journey URL', text(255), None),
        'Reference_Prefix__c': ('Reference Prefix', text(20), None),
        'Card_Bin__c': ('Card BIN (mock)', text(6), None),
    },
    'Bandhu_Message__mdt': {
        'English__c': ('English', long_text(32768, 6), None),
        'Hindi__c': ('Hindi', long_text(32768, 6), None),
        'Bengali__c': ('Bengali', long_text(32768, 6), None),
    },
}

OBJECTS = {
    'Bandhu_Consent__c': ('Card Consent', 'Card Consents', 'CN-{000000}', 'Consent Number',
                          'Consent and disclosure log (DPDP Act 2023, RBI credit card and KYC directions, AA): what, when, purpose, expiry and retention.', 'ReadWrite'),
    'Card_Journey__c': ('Card Journey', 'Card Journeys', 'CJ-{000000}', 'Journey Number',
                        'One Bandhu credit card conversation (WhatsApp or web): answers, recommendation, KYC and outcome.', 'ReadWrite'),
    'Card_Application__c': ('Card Application', 'Card Applications', 'CA-{000000}', 'Application Number',
                            'A submitted Bandhan Bank credit card application with its checks and decision.', 'ReadWrite'),
    'Card_Check__c': ('Card Check', 'Card Checks', 'CC-{000000}', 'Check Number',
                      'One verification on a card application (PAN, Aadhaar, bureau, income, Video KYC, fraud, policy).', 'ControlledByParent'),
    'Bandhu_Lead_Check__c': ('Card Qualification Check', 'Card Qualification Checks', 'LQ-{000000}', 'Check Number',
                             'One lead-stage qualification gate for a Bandhu card prospect (serviceability, consent, fraud, bureau, income, employment, card eligibility).', 'ReadWrite'),
    'Bank_Relationship__c': ('Bank Relationship', 'Bank Relationships', 'BR-{000000}', 'Relationship Number',
                             'An existing customer\'s Bandhan Bank account or deposit (mock core banking).', 'ReadWrite'),
}
MDT = {
    'Bandhu_Card__mdt': ('Bandhu Card', 'Bandhu Cards', 'Bandhan Bank credit cards: benefits, fees, eligibility and fit weights.'),
    'Bandhu_Config__mdt': ('Bandhu Config', 'Bandhu Configs', 'Bandhu journey settings.'),
    'Bandhu_Region__mdt': ('Bandhu Region', 'Bandhu Regions', 'Card serviceability and RM ownership by PIN code prefix.'),
    'Bandhu_Message__mdt': ('Bandhu Message', 'Bandhu Messages', 'Customer copy in English, Hindi and Bengali.'),
}


OVERRIDES = {
    'Card_Application__c': '''    <actionOverrides>
        <actionName>View</actionName>
        <comment>Underwriter review: stage gates, recommendation and decision</comment>
        <content>Card_Application_Record_Page</content>
        <formFactor>Large</formFactor>
        <skipRecordTypeSelect>false</skipRecordTypeSelect>
        <type>Flexipage</type>
    </actionOverrides>
''',
}


def field_xml(name, label, body, desc, mdt):
    d = (f'    <description>{escape(desc)}</description>\n' + ('' if mdt else f'    <inlineHelpText>{escape(desc)}</inlineHelpText>\n')) if desc else ''
    extra = '    <fieldManageability>DeveloperControlled</fieldManageability>\n' if mdt else ''
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>{name}</fullName>
{d}{extra}    <label>{escape(label)}</label>
{body}</CustomField>
'''


def main():
    for obj, (label, plural, fmt, name_label, desc, sharing) in OBJECTS.items():
        os.makedirs(f'{OBJ}/{obj}/fields', exist_ok=True)
        with open(f'{OBJ}/{obj}/{obj}.object-meta.xml', 'w') as fh:
            fh.write(f'''<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
{OVERRIDES.get(obj, '')}    <deploymentStatus>Deployed</deploymentStatus>
    <description>{escape(desc)}</description>
    <enableActivities>true</enableActivities>
    <enableHistory>false</enableHistory>
    <enableReports>true</enableReports>
    <enableSearch>true</enableSearch>
    <label>{label}</label>
    <nameField><displayFormat>{fmt}</displayFormat><label>{name_label}</label><type>AutoNumber</type></nameField>
    <pluralLabel>{plural}</pluralLabel>
    <sharingModel>{sharing}</sharingModel>
    <visibility>Public</visibility>
</CustomObject>
''')
    for obj, (label, plural, desc) in MDT.items():
        os.makedirs(f'{OBJ}/{obj}/fields', exist_ok=True)
        with open(f'{OBJ}/{obj}/{obj}.object-meta.xml', 'w') as fh:
            fh.write(f'''<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>{escape(desc)}</description>
    <label>{label}</label>
    <pluralLabel>{plural}</pluralLabel>
    <visibility>Public</visibility>
</CustomObject>
''')
    n = 0
    for obj, fields in FIELDS.items():
        os.makedirs(f'{OBJ}/{obj}/fields', exist_ok=True)
        for name, (label, body, desc) in fields.items():
            with open(f'{OBJ}/{obj}/fields/{name}.field-meta.xml', 'w') as fh:
                fh.write(field_xml(name, label, body, desc, obj.endswith('__mdt')))
            n += 1
    os.makedirs('bandhan/main/default/tabs', exist_ok=True)
    for obj, motif in (('Card_Journey__c', 'Custom62: Chalkboard'), ('Card_Application__c', 'Custom40: Credit Card')):
        with open(f'bandhan/main/default/tabs/{obj}.tab-meta.xml', 'w') as fh:
            fh.write(f'''<?xml version="1.0" encoding="UTF-8"?>
<CustomTab xmlns="http://soap.sforce.com/2006/04/metadata">
    <customObject>true</customObject>
    <motif>{motif}</motif>
</CustomTab>
''')
    print(f'Bandhu model generated: {len(OBJECTS) + len(MDT)} objects, {n} fields')


if __name__ == '__main__':
    main()
