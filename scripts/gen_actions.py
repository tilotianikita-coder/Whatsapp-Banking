"""Generates the thin LoanSeva invocable action wrappers (one Apex class per agent action).
Run from the project root: python3 scripts/gen_actions.py"""
import os

B = 'force-app/main/default/classes'
META = '''<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <status>Active</status>
</ApexClass>
'''

COMMON = """        @InvocableVariable(label='Journey Id' description='Loan journey id returned by a previous LoanSeva action, if any')
        public String journeyId;
        @InvocableVariable(label='Messaging Session Id' description='Current MessagingSession id (RoutableId)')
        public String sessionId;
"""

# (class, label, description, [(field, type, label, description, required)], engine call)
ACTIONS = [
    ('LoanSevaStartAction', 'LoanSeva - Start Journey',
     'Starts or resumes the LoanSeva PL Top-Up journey and returns the personalised welcome menu.',
     [('mobile', 'String', 'Mobile', 'Customer mobile number if known (optional)', False)],
     'LoanSevaEngine.start(j)'),
    ('LoanSevaFaqAction', 'LoanSeva - Answer Top-Up Question',
     'Answers a customer question about Kotak Personal Loan Top-Up from approved FAQ content, then nudges towards the personalised offer.',
     [('question', 'String', 'Question', 'The question exactly as the customer typed it', True)],
     'LoanSevaEngine.answerFaq(j, r.question)'),
    ('LoanSevaLanguageAction', 'LoanSeva - Switch Language',
     'Switches the conversation language (EN, HI for Hindi, MR for Marathi) and re-asks the pending question in that language.',
     [('language', 'String', 'Language', 'EN, HI or MR (or the language name)', True)],
     'LoanSevaEngine.setLanguage(j, r.language)'),
    ('LoanSevaVerifyAction', 'LoanSeva - Verify Customer',
     'Looks up the customer by name and registered mobile number and sends the OTP.',
     [('customerName', 'String', 'Customer Name', 'Full name as given by the customer (leave empty to ask for it)', False),
      ('registeredMobile', 'String', 'Registered Mobile', 'Registered 10-digit mobile number as given by the customer (leave empty to ask for it)', False)],
     'LoanSevaEngine.verifyCustomer(j, r.customerName, r.registeredMobile)'),
    ('LoanSevaOtpAction', 'LoanSeva - Verify OTP',
     'Checks the 6-digit OTP. On success returns the existing loan snapshot; after the maximum attempts it exits gracefully and creates an RM task.',
     [('otp', 'String', 'OTP', 'The code typed by the customer', True)],
     'LoanSevaEngine.verifyOtp(j, r.otp)'),
    ('LoanSevaConfirmLoanAction', 'LoanSeva - Confirm Loan Details',
     'Records whether the customer confirms the existing loan snapshot, then starts personalisation.',
     [('confirmed', 'Boolean', 'Confirmed', 'True if the customer says the loan details are correct', True)],
     'LoanSevaEngine.confirmLoan(j, r.confirmed)'),
    ('LoanSevaPersonaliseAction', 'LoanSeva - Capture Personalisation Answer',
     'Saves the answer to the current personalisation question (employment, company, income, purpose, amount) and returns the next question, or the offer when complete.',
     [('answer', 'String', 'Answer', 'The reply exactly as the customer typed it (option number or text)', True)],
     'LoanSevaEngine.personalise(j, r.answer)'),
    ('LoanSevaOfferAction', 'LoanSeva - Get or Update Offer',
     'Runs the eligibility check and returns the personalised preliminary offer. Pass amount and/or tenure when the customer wants to change them.',
     [('amount', 'String', 'Amount', 'New desired amount as typed, e.g. 3 lakh (optional)', False),
      ('tenure', 'String', 'Tenure', 'New tenure as typed, e.g. 48 months or 4 years (optional)', False)],
     'LoanSevaEngine.offer(j, r.amount, r.tenure)'),
    ('LoanSevaAcceptOfferAction', 'LoanSeva - Accept Offer',
     'Accepts the current offer, generates the reference number and returns callback slot options.',
     [],
     'LoanSevaEngine.acceptOffer(j)'),
    ('LoanSevaCallbackAction', 'LoanSeva - Schedule Callback',
     'Books the specialist callback from the customer choice and creates the RM Task and Event. Returns the confirmation plus the first feedback question.',
     [('preference', 'String', 'Preference', 'The reply exactly as typed: an option number or a date/time such as Thu 11am', True),
      ('preferredDateTime', 'String', 'Preferred Date Time (ISO)', 'Optional ISO 8601 IST date-time (yyyy-MM-ddTHH:mm) if the customer named a specific time', False)],
     'LoanSevaEngine.scheduleCallback(j, r.preference, r.preferredDateTime)'),
    ('LoanSevaFeedbackAction', 'LoanSeva - Capture Feedback',
     'Captures the answer to the current feedback question (CSAT 1-5, resolution, optional comment) and returns the next question or the sign-off. Pass an empty answer to start the survey.',
     [('answer', 'String', 'Answer', 'The reply exactly as the customer typed it', False)],
     'LoanSevaEngine.feedback(j, r.answer)'),
    ('LoanSevaReplyAction', 'LoanSeva - Reply to Journey',
     'Handles any customer reply to the question the journey is waiting for (name and mobile, OTP, loan confirmation, personalisation answers, offer decision, amount or tenure change, callback time, feedback). Routes on the saved journey state and returns the next message.',
     [('message', 'String', 'Customer Message', 'The customer message exactly as typed', True)],
     'LoanSevaEngine.reply(j, r.message)'),
    ('LoanSevaEscalateAction', 'LoanSeva - Escalate to Specialist',
     'Logs a high-priority RM task with the intent summary before handing off to a human specialist.',
     [('reason', 'String', 'Reason', 'Short reason for the handoff', False)],
     'LoanSevaEngine.escalate(j, r.reason)'),
]

TEMPLATE = """public with sharing class {name} {{
    public class Request {{
{common}{fields}    }}

    @InvocableMethod(label='{label}' description='{desc}' category='LoanSeva')
    public static List<LoanSevaActionResult> run(List<Request> requests) {{
        List<LoanSevaActionResult> results = new List<LoanSevaActionResult>();
        for (Request r : requests) {{
            try {{
                Loan_Journey__c j = LoanSevaJourneyService.resolve(r.journeyId, r.sessionId, {mobile});
                results.add(LoanSevaActionResult.of({call}));
            }} catch (Exception e) {{
                results.add(LoanSevaActionResult.error(e, r.journeyId));
            }}
        }}
        return results;
    }}
}}
"""

for name, label, desc, fields, call in ACTIONS:
    decl = ''.join(
        "        @InvocableVariable(label='{}' description='{}'{})\n        public {} {};\n".format(
            fl, fd, ' required=true' if req else '', ft, fn)
        for fn, ft, fl, fd, req in fields)
    mobile = 'r.mobile' if any(f[0] == 'mobile' for f in fields) else 'null'
    with open(os.path.join(B, name + '.cls'), 'w') as fh:
        fh.write(TEMPLATE.format(name=name, common=COMMON, fields=decl, label=label, desc=desc, mobile=mobile, call=call))
    with open(os.path.join(B, name + '.cls-meta.xml'), 'w') as fh:
        fh.write(META)

# meta files for hand-written classes
for f in os.listdir(B):
    if f.endswith('.cls') and not os.path.exists(os.path.join(B, f + '-meta.xml')):
        with open(os.path.join(B, f + '-meta.xml'), 'w') as fh:
            fh.write(META)
print('generated', len(ACTIONS), 'actions')
