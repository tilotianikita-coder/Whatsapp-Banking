"""Generates the new-loan LOS data model: KYC/underwriting fields on the journey and application,
the Underwriting_Check__c and Loan_Document__c child objects, and the new config fields.
Run from the project root: python3 scripts/gen_los_model.py (then python3 scripts/gen_permsets.py)
"""
import os
from xml.sax.saxutils import escape

OBJ = 'force-app/main/default/objects'


def picklist(values, default=None):
    vals = ''.join(f'''            <value>
                <fullName>{escape(v)}</fullName>
                <default>{str(v == default).lower()}</default>
                <label>{escape(v)}</label>
            </value>
''' for v in values)
    return f'''    <type>Picklist</type>
    <valueSet>
        <restricted>true</restricted>
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

JOURNEY_TYPES = ['Top-Up', 'New Loan']
CHECKS = ['PAN Verification', 'Credit Bureau', 'Bank Statement Analysis', 'Employment Verification', 'Policy & FOIR', 'Dedupe & Fraud']
DOC_TYPES = ['PAN Card', 'Bank Statement', 'Salary Slips', 'Other']

KYC = {
    'Date_Of_Birth__c': ('Date of Birth', DATE, None),
    'PAN__c': ('PAN', text(10), 'Permanent Account Number as given by the applicant. Never shown back in full to the customer.'),
    'Email__c': ('Email', EMAIL, None),
    'City__c': ('City', text(60), None),
    'PIN_Code__c': ('PIN Code', text(6), None),
    'Monthly_Income__c': ('Monthly Income', number(16, 0, True), 'Declared monthly take-home income.'),
    'Existing_EMIs__c': ('Existing EMIs', number(16, 0, True), 'Declared EMIs per month on other loans and cards.'),
}

FIELDS = {
    'Loan_Journey__c': dict(KYC, **{
        'Journey_Type__c': ('Journey Type', picklist(JOURNEY_TYPES, 'Top-Up'), 'Top-Up for pre-approved customers; New Loan when there is no pre-approved offer.'),
        'Apply_Offered__c': ('New Loan Offered', CHECKBOX, 'The customer was told there is no pre-approved offer and offered a new-loan application.'),
        'Doc_Step__c': ('Document Step', number(2), '1 PAN, 2 bank statement, 3 salary slips, 4 review and consent.'),
        'Docs_Skipped__c': ('Documents Skipped', text(255), 'Documents the customer chose to send later.'),
        'Submitted_At__c': ('Submitted At', DATETIME, None),
    }),
    'Loan_Application__c': dict(KYC, **{
        'Application_Type__c': ('Application Type', picklist(JOURNEY_TYPES, 'Top-Up'), None),
        'Applicant_Name__c': ('Applicant Name', text(120), None),
        'Mobile__c': ('Mobile', text(20), None),
        'Bureau_Consent__c': ('Bureau Consent', CHECKBOX, 'Customer consented to a credit bureau pull and bank statement analysis.'),
        'Consent_At__c': ('Consent At', DATETIME, None),
        'Submitted_At__c': ('Submitted At', DATETIME, None),
        'CIBIL_Score__c': ('CIBIL Score', number(3), 'Mock bureau score from the underwriting run.'),
        'Underwriting_Status__c': ('Underwriting Status', picklist(['Not Started', 'In Progress', 'Completed', 'Error'], 'Not Started'), None),
        'Recommendation__c': ('Recommendation', picklist(['Approve', 'Refer', 'Decline']), 'System recommendation from the mock underwriting checks; the RM decides.'),
        'Underwriting_Summary__c': ('Underwriting Summary', long_text(), None),
        'Decision__c': ('Decision', picklist(['Approved', 'Rejected']), None),
        'Decision_By__c': ('Decision By', lookup('User', 'LoanSeva_Decisions', 'LoanSeva Decisions'), None),
        'Decision_At__c': ('Decision At', DATETIME, None),
        'Decision_Notes__c': ('Decision Notes', long_text(4000, 3), 'Internal RM notes; never sent to the customer.'),
        'Loan_Account__c': ('Loan Account', lookup('Existing_Loan__c', 'Sanctioned_Applications', 'Sanctioned Applications'), 'Loan account (LAN) created when the RM approves.'),
    }),
    'Underwriting_Check__c': {
        'Loan_Application__c': ('Loan Application', lookup('Loan_Application__c', 'Underwriting_Checks', 'Underwriting Checks', master=True), None),
        'Check__c': ('Check', picklist(CHECKS), None),
        'Provider__c': ('Provider', text(80), None),
        'Result__c': ('Result', picklist(['Pass', 'Refer', 'Fail', 'Pending']), None),
        'Score__c': ('Score', number(6), None),
        'Summary__c': ('Summary', text(255), None),
        'Details__c': ('Details', long_text(32768, 8), None),
        'Report_Data__c': ('Report Data', long_text(131072, 3), 'Full mock provider report as JSON, shown on the Credit Review panel.'),
        'Request_Id__c': ('Request Id', text(40), 'Mock provider request id.'),
        'Run_At__c': ('Run At', DATETIME, None),
        'Sort_Order__c': ('Sort Order', number(3), None),
    },
    'Loan_Document__c': {
        'Loan_Application__c': ('Loan Application', lookup('Loan_Application__c', 'Loan_Documents', 'Documents', master=True), None),
        'Document_Type__c': ('Document Type', picklist(DOC_TYPES), None),
        'Status__c': ('Status', picklist(['Received', 'Verified', 'Rejected'], 'Received'), None),
        'Content_Document_Id__c': ('File Id', text(18), 'ContentDocument Id of the shared file.'),
        'File_Name__c': ('File Name', text(255), None),
        'Received_At__c': ('Received At', DATETIME, None),
        'Source__c': ('Source', picklist(['WhatsApp', 'RM'], 'WhatsApp'), None),
    },
    'LoanSeva_Config__mdt': {
        'Lan_Prefix__c': ('LAN Prefix', text(4), 'Prefix of loan account numbers created on approval.'),
        'New_Loan_Reference_Prefix__c': ('New Loan Reference Prefix', text(20), None),
        'New_Loan_Rate_Premium__c': ('New Loan Rate Premium', number(5, 2), 'Added to Base_Rate__c for customers without an existing Kotak loan.'),
        'New_Loan_Min_Amount__c': ('New Loan Min Amount', number(16), None),
        'New_Loan_Max_Amount__c': ('New Loan Max Amount', number(16), None),
        'New_Loan_Income_Multiple__c': ('New Loan Income Multiple', number(4), 'Maximum loan as a multiple of monthly income.'),
        'New_Loan_Min_Income__c': ('New Loan Min Income', number(16), None),
        'Min_Age__c': ('Min Age', number(3), None),
        'Max_Age_At_Maturity__c': ('Max Age At Maturity', number(3), None),
        'Min_Cibil_Score__c': ('Min CIBIL Score', number(3), 'At or above: pass.'),
        'Decline_Cibil_Score__c': ('Decline CIBIL Score', number(3), 'Below: fail. In between: refer.'),
    },
}

OBJECTS = {
    'Underwriting_Check__c': ('Underwriting Check', 'Underwriting Checks', 'UWC-{0000}', 'Check Number',
                              'One mock underwriting check (PAN, bureau, bank statement, employment, policy, dedupe) on a loan application.'),
    'Loan_Document__c': ('Loan Document', 'Loan Documents', 'DOC-{0000}', 'Document Number',
                         'A document the applicant shared (PAN card, bank statement, salary slips), with the file linked to the application.'),
}


def field_xml(name, label, body, desc, mdt):
    d = f'    <description>{escape(desc)}</description>\n    <inlineHelpText>{escape(desc)}</inlineHelpText>\n' if desc and not mdt else (
        f'    <description>{escape(desc)}</description>\n' if desc else '')
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>{name}</fullName>
{d}    <label>{escape(label)}</label>
{body}</CustomField>
'''


def main():
    for obj, (label, plural, fmt, name_label, desc) in OBJECTS.items():
        os.makedirs(f'{OBJ}/{obj}/fields', exist_ok=True)
        with open(f'{OBJ}/{obj}/{obj}.object-meta.xml', 'w') as fh:
            fh.write(f'''<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <deploymentStatus>Deployed</deploymentStatus>
    <description>{escape(desc)}</description>
    <enableActivities>false</enableActivities>
    <enableHistory>false</enableHistory>
    <enableReports>true</enableReports>
    <enableSearch>false</enableSearch>
    <label>{label}</label>
    <nameField><displayFormat>{fmt}</displayFormat><label>{name_label}</label><type>AutoNumber</type></nameField>
    <pluralLabel>{plural}</pluralLabel>
    <sharingModel>ControlledByParent</sharingModel>
    <visibility>Public</visibility>
</CustomObject>
''')
    n = 0
    for obj, fields in FIELDS.items():
        for name, (label, body, desc) in fields.items():
            with open(f'{OBJ}/{obj}/fields/{name}.field-meta.xml', 'w') as fh:
                fh.write(field_xml(name, label, body, desc, obj.endswith('__mdt')))
            n += 1
    print(f'LOS model generated: {len(OBJECTS)} objects, {n} fields')


if __name__ == '__main__':
    main()
