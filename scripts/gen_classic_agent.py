"""Generates LoanSeva by Kotak as classic Agentforce metadata (Bot, BotVersion, GenAiPlannerBundle,
GenAiPlugin topics, GenAiFunction actions) so it deploys with the Metadata API.
Use this where `sf agent publish authoring-bundle` is unavailable (Agent API 404). Topic and action
definitions are shared with scripts/gen_agent.py, so both formats stay in sync.
Run from the project root: python3 scripts/gen_classic_agent.py
"""
import json
import os
import re
from xml.sax.saxutils import escape

import gen_agent as ga

ROOT = 'force-app/main/default'
BOT = 'LoanSeva_by_Kotak'
PREFIX = 'LoanSeva_'

# (action name in gen_agent.ACTIONS) -> GenAiFunction developer name
FN = {name: PREFIX + ''.join(p.capitalize() for p in name.split('_')) for name in ga.ACTIONS}

EXTRA_OUT = [
    ('verified', 'boolean', 'Verified', 'True once the OTP has been verified.'),
    ('referenceNumber', 'string', 'Reference Number', 'Application reference number, once the offer is accepted.'),
    ('status', 'string', 'Status', 'Journey status.'),
]

CONTEXT = ("Always pass journeyId = the journeyId output of the most recent LoanSeva action in this conversation (empty on the first call) "
           "and sessionId = the Routable Id (MessagingSession Id) of this conversation; leave sessionId empty if no Routable Id is available.")

RELAY = ("Your reply to the customer MUST be exactly the message output of the action you called, character for character: keep every emoji, "
         "*asterisk*, line break and number. Do not add greetings, summaries, explanations or translations, and never reply with only an acknowledgement (except the one-line receipt for a message that is only an attachment or voice note).")

# Agent role. Kept under 1000 characters (a longer role fails to deploy with an "unexpected error").
# The attachment rule lives here because a message with no text (voice note, photo) is answered before any topic is chosen.
ROLE = ("You are LoanSeva by Kotak, the WhatsApp personal loan assistant of Kotak Mahindra Bank. Be warm and concise. "
        "Never reveal full account numbers or PANs, never promise final approval, stay on Kotak lending topics and offer a Kotak specialist whenever asked. "
        "Call the LoanSeva actions and relay their message exactly; any short text you write yourself must be in the customer's language (English, Hindi or Marathi). "
        "You CAN receive files: LoanSeva records every photo or document and transcribes every voice note by itself, then replies separately. "
        "Never say you can't process a file or that there was an issue with it. "
        "If a message has no text (only a file or voice note, or empty), reply only: 👍 Received, one moment. "
        "(Hindi: 👍 मिल गया, एक पल। Marathi: 👍 मिळालं, एक क्षण.)")
assert len(ROLE) < 1000, len(ROLE)

JOURNEY = """You run the Kotak Personal Loan journey: Top-Up for pre-approved customers and a new Personal Loan application for everyone else. The LoanSeva actions hold the journey state, so never decide yourself which step comes next.
- First message, greeting, Continue Here!, Continue, Hi or Start, or no journeyId yet -> call start_journey.
- A question about Top-Up (uses, rate, difference from a new loan, speed, fees, documents, tenure, eligibility, or similar) rather than an answer -> call answer_question with the question as typed.
- A request to apply for a new personal loan ("apply", "I want a new loan", menu option 4) is not a question: call reply_to_journey.
- Every other customer message, including a request for a human, agent, specialist or RM -> call reply_to_journey with the message exactly as typed. It knows what is pending (menu option, name and mobile, OTP, Yes/No, option numbers, company name, date of birth, PAN, email, PIN code, income, EMIs, amount, tenure, Done or Skip for a document photo, review confirmation, callback time, rating, comment), logs specialist requests for the RM and returns the next message.
- A message with no text of its own (only a photo, PDF, document, voice note, audio or other attachment, or an empty message) -> do NOT call any action and never say there was a problem with the file. LoanSeva processes the file by itself (documents are recorded, voice notes are transcribed and answered) and sends the next message separately. Reply with exactly this one line, in the language the customer is using: English "👍 Received, one moment.", Hindi "👍 मिल गया, एक पल।", Marathi "👍 मिळालं, एक क्षण."
- A photo or file with a caption: call reply_to_journey with the caption text exactly as typed.
- Dates of birth, PAN numbers, email addresses and PIN codes are answers the journey asked for: pass them exactly as typed, never refuse, mask or comment on them. The journey masks the PAN itself.
- When the action output handoff is true (the customer asked for a specialist, disputed their loan details or was locked out), reply with the action message and then escalate the conversation to a human. Never escalate without calling reply_to_journey first: it logs the request for the RM.
- The message you pass is the customer's latest message copied character for character. Never paraphrase or summarise it and never convert it to Yes, No or an option number: "I want to know more about PL" must be passed as "I want to know more about PL", not "Yes".
- Never reveal or repeat an OTP yourself."""

# topic developer name -> (label, description, scope, instruction text, action names, can escalate)
# No separate escalation topic: the platform's built-in escalation skipped our actions, so the RM Task was never
# logged. Requests for a human go through reply_to_journey (LoanSevaEngine.escalate logs the Task); the journey
# topic then transfers to Omni-Channel (channel fallback queue) when the output says handoff.
TOPICS = {
    'Top_Up_Journey': ('Top-Up Journey',
        'Always use for the first message and for short replies such as Continue Here!, Continue, Hi, Hello, Start, Yes, No, Skip, Done, Apply, a bare number, a name, a mobile number, an OTP, a company name, a date of birth, a PAN, an email address, a PIN code, an amount or a day and time, and for photos, documents, voice notes, audio, attachments and empty messages with no text: they belong to the ongoing loan journey, never ambiguous, and the instructions say exactly how to reply to them. Covers the whole Kotak Personal Loan journey on WhatsApp: welcome and menu, Top-Up questions, verification (name, mobile, OTP, loan confirmation), personalisation answers, offer and changes, acceptance, a new Personal Loan application for customers without a pre-approved offer (KYC details, income, documents, review and consent), callback booking and feedback. Also covers requests for a human, agent, specialist or RM: the journey logs them for a Kotak RM. Use for every customer message except language changes.',
        'Run the Kotak Personal Loan Top-Up journey and new Personal Loan applications using LoanSeva actions only.',
        JOURNEY, ['start_journey', 'reply_to_journey', 'answer_question'], True),
    'Language_Switch': ('Language Switch',
        'Switches the conversation between English, Hindi and Marathi at any point, e.g. HI, MR, EN, Hindi, Marathi, हिंदी, मराठी.',
        'Change the conversation language using the LoanSeva switch language action.',
        ga.LANGUAGE, ['switch_language'], False),
}


def x(s):
    return escape(s, {'"': '&quot;', "'": '&apos;'})


def clean(text):
    """Agent Script instruction text -> list of plain sentences for classic topic instructions."""
    text = re.sub(r'\{REROUTE\}\s*', '', text)
    text = text.replace('{!@variables.awaiting}', 'the awaiting output of the last LoanSeva action')
    text = text.replace('({!@variables.language})', '')
    text = re.sub(r'go_to_(\w+)', lambda m: {'escalation': 'the Escalate to Human topic', 'language_switch': 'the Language Switch topic'}.get(m.group(1), m.group(1)), text)
    lines = [re.sub(r'\s+', ' ', l).strip() for l in text.split('\n')]
    out = []
    for l in lines:
        if not l:
            continue
        if l.startswith('- ') or not out:
            out.append(l[2:] if l.startswith('- ') else l)
        else:
            out[-1] += ' ' + l
    for name, fn in FN.items():
        out = [re.sub(rf'\b{name}\b', fn, l) for l in out]
    return out


def schema_prop(ptype, label, desc, is_input, displayable=False):
    p = {
        'title': label,
        'description': desc,
        'lightning:type': 'lightning__booleanType' if ptype == 'boolean' else 'lightning__textType',
        'lightning:isPII': False,
    }
    if is_input:
        p['copilotAction:isUserInput'] = False
    else:
        p['copilotAction:isDisplayable'] = displayable
        p['copilotAction:isUsedByPlanner'] = True
    return p


def write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as fh:
        fh.write(content)


def functions():
    for name, (cls, label, desc, inputs) in ga.ACTIONS.items():
        fn = FN[name]
        base = f'{ROOT}/genAiFunctions/{fn}'
        write(f'{base}/{fn}.genAiFunction-meta.xml', f'''<?xml version="1.0" encoding="UTF-8"?>
<GenAiFunction xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>{x(desc + ' ' + CONTEXT)}</description>
    <invocationTarget>{cls}</invocationTarget>
    <invocationTargetType>apex</invocationTargetType>
    <isConfirmationRequired>false</isConfirmationRequired>
    <isIncludeInProgressIndicator>false</isIncludeInProgressIndicator>
    <masterLabel>{x('LoanSeva - ' + label)}</masterLabel>
</GenAiFunction>
''')
        props, required = {}, []
        for iname, itype, ilabel, idesc, req in [
            ('journeyId', 'string', 'Journey Id', 'journeyId output of the most recent LoanSeva action; empty on the first call.', False),
            ('sessionId', 'string', 'Messaging Session Id', 'Routable Id (MessagingSession Id) of this conversation.', False),
        ] + inputs:
            props[iname] = schema_prop(itype, ilabel, idesc, True)
            if req:
                required.append(iname)
        schema = {'required': required, 'unevaluatedProperties': False, 'properties': props, 'lightning:type': 'lightning__objectType'}
        write(f'{base}/input/schema.json', json.dumps(schema, indent=2, ensure_ascii=False) + '\n')
        outs = {o: schema_prop(t, l, d, False) for o, t, l, d in ga.COMMON_OUT + EXTRA_OUT}
        schema = {'unevaluatedProperties': False, 'properties': outs, 'lightning:type': 'lightning__objectType'}
        write(f'{base}/output/schema.json', json.dumps(schema, indent=2, ensure_ascii=False) + '\n')


def plugins():
    folder = f'{ROOT}/genAiPlugins'
    for f in os.listdir(folder) if os.path.isdir(folder) else []:
        if f.startswith(PREFIX) and f[len(PREFIX):].split('.')[0] not in TOPICS:
            os.remove(os.path.join(folder, f))  # topic dropped from TOPICS: delete it from the org too
    for dev, (label, desc, scope, text, actions, can_escalate) in TOPICS.items():
        instr = clean(text) + [CONTEXT, RELAY]
        items = '\n'.join(f'''    <genAiPluginInstructions>
        <description>{x(t)}</description>
        <developerName>instruction_{i}</developerName>
        <language>en_US</language>
        <masterLabel>instruction_{i}</masterLabel>
        <sortOrder>{i}</sortOrder>
    </genAiPluginInstructions>''' for i, t in enumerate(instr))
        fns = '\n'.join(f'''    <genAiFunctions>
        <functionName>{FN[a]}</functionName>
    </genAiFunctions>''' for a in actions)
        write(f'{ROOT}/genAiPlugins/{PREFIX}{dev}.genAiPlugin-meta.xml', f'''<?xml version="1.0" encoding="UTF-8"?>
<GenAiPlugin xmlns="http://soap.sforce.com/2006/04/metadata">
    <canEscalate>{str(can_escalate).lower()}</canEscalate>
    <description>{x(desc)}</description>
    <developerName>{PREFIX}{dev}</developerName>
{fns}
{items}
    <language>en_US</language>
    <masterLabel>{x('LoanSeva ' + label)}</masterLabel>
    <pluginType>Topic</pluginType>
    <scope>{x(scope)}</scope>
</GenAiPlugin>
''')


def planner():
    links = '\n'.join(f'''    <genAiPlugins>
        <genAiPluginName>{PREFIX}{dev}</genAiPluginName>
    </genAiPlugins>''' for dev in TOPICS)
    write(f'{ROOT}/genAiPlannerBundles/{BOT}/{BOT}.genAiPlannerBundle', f'''<?xml version="1.0" encoding="UTF-8"?>
<GenAiPlannerBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>LoanSeva by Kotak planner: routes WhatsApp messages to the Top-Up journey topics.</description>
{links}
    <masterLabel>{BOT}</masterLabel>
    <plannerType>AiCopilot__ReAct</plannerType>
</GenAiPlannerBundle>
''')


CONTEXT_VARS = [
    ('EndUserId', 'Id', 'End User Id', 'MessagingSession', 'MessagingSession.MessagingEndUserId', 'This variable may also be referred to as MessagingEndUser Id', True),
    ('RoutableId', 'Id', 'Routable Id', 'MessagingSession', 'MessagingSession.Id', 'This variable may also be referred to as MessagingSession Id', True),
    ('ContactId', 'Id', 'Contact Id', 'MessagingEndUser', 'MessagingEndUser.ContactId', 'This variable may also be referred to as MessagingEndUser ContactId', False),
    ('EndUserLanguage', 'Text', 'End User Language', 'MessagingSession', 'MessagingSession.EndUserLanguage', 'This variable may also be referred to as MessagingSession EndUserLanguage', False),
]
MESSAGE_TYPES = ['Custom', 'WhatsApp', 'EmbeddedMessaging', 'Text']


def bot():
    cvs = []
    for dev, dtype, label, obj, field, desc, in_prompt in CONTEXT_VARS:
        maps = '\n'.join(f'''        <contextVariableMappings>
            <SObjectType>{obj}</SObjectType>
            <fieldName>{field}</fieldName>
            <messageType>{mt}</messageType>
        </contextVariableMappings>''' for mt in MESSAGE_TYPES)
        cvs.append(f'''    <contextVariables>
{maps}
        <dataType>{dtype}</dataType>
        <description>{x(desc)}</description>
        <developerName>{dev}</developerName>
        <includeInPrompt>{str(in_prompt).lower()}</includeInPrompt>
        <label>{label}</label>
    </contextVariables>''')
    base = f'{ROOT}/bots/{BOT}'
    write(f'{base}/{BOT}.bot-meta.xml', f'''<?xml version="1.0" encoding="UTF-8"?>
<Bot xmlns="http://soap.sforce.com/2006/04/metadata">
    <agentDSLEnabled>false</agentDSLEnabled>
    <agentType>EinsteinServiceAgent</agentType>
    <botMlDomain>
        <label>LoanSeva by Kotak</label>
        <name>{BOT}</name>
    </botMlDomain>
    <botSource>None</botSource>
    <botUser>{ga.AGENT_USER}</botUser>
{chr(10).join(cvs)}
    <description>{x('WhatsApp assistant for the Kotak Personal Loan Top-Up journey and new Personal Loan applications: grounded FAQ, OTP verification, personalisation, offer, document collection, callback booking and feedback, in English, Hindi and Marathi.')}</description>
    <label>LoanSeva by Kotak</label>
    <logPrivateConversationData>false</logPrivateConversationData>
    <richContentEnabled>true</richContentEnabled>
    <sessionTimeout>30</sessionTimeout>
    <type>ExternalCopilot</type>
</Bot>
''')
    welcome = "Hi! 👋 I'm LoanSeva by Kotak. Reply Continue Here! to see your Personal Loan Top-Up offer."
    error = "Sorry, I hit a small snag on my side. 🙏 Reply Agent to connect with a Kotak specialist."
    write(f'{base}/v1.botVersion-meta.xml', f'''<?xml version="1.0" encoding="UTF-8"?>
<BotVersion xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>v1</fullName>
    <articleAnswersGPTEnabled>false</articleAnswersGPTEnabled>
    <botDialogs>
        <botSteps>
            <botMessages>
                <message>{x(welcome)}</message>
                <messageIdentifier>6f1d8a52-3c1e-4b8e-9a51-1b2c3d4e5f01</messageIdentifier>
            </botMessages>
            <stepIdentifier>6f1d8a52-3c1e-4b8e-9a51-1b2c3d4e5f02</stepIdentifier>
            <type>Message</type>
        </botSteps>
        <botSteps>
            <stepIdentifier>6f1d8a52-3c1e-4b8e-9a51-1b2c3d4e5f03</stepIdentifier>
            <type>Wait</type>
        </botSteps>
        <developerName>Welcome</developerName>
        <isPlaceholderDialog>false</isPlaceholderDialog>
        <label>Welcome</label>
        <showInFooterMenu>false</showInFooterMenu>
    </botDialogs>
    <botDialogs>
        <botSteps>
            <botMessages>
                <message>{x(error)}</message>
                <messageIdentifier>6f1d8a52-3c1e-4b8e-9a51-1b2c3d4e5f04</messageIdentifier>
            </botMessages>
            <stepIdentifier>6f1d8a52-3c1e-4b8e-9a51-1b2c3d4e5f05</stepIdentifier>
            <type>Message</type>
        </botSteps>
        <botSteps>
            <stepIdentifier>6f1d8a52-3c1e-4b8e-9a51-1b2c3d4e5f06</stepIdentifier>
            <type>Wait</type>
        </botSteps>
        <developerName>Error_Handler</developerName>
        <isPlaceholderDialog>false</isPlaceholderDialog>
        <label>Error Handler</label>
        <showInFooterMenu>false</showInFooterMenu>
    </botDialogs>
    <botDialogs>
        <botSteps>
            <conversationSystemMessage>
                <type>Transfer</type>
            </conversationSystemMessage>
            <stepIdentifier>6f1d8a52-3c1e-4b8e-9a51-1b2c3d4e5f07</stepIdentifier>
            <type>SystemMessage</type>
        </botSteps>
        <developerName>Transfer_To_Agent</developerName>
        <isPlaceholderDialog>false</isPlaceholderDialog>
        <label>Transfer To Agent</label>
        <showInFooterMenu>false</showInFooterMenu>
    </botDialogs>
    <citationsEnabled>false</citationsEnabled>
    <conversationDefinitionPlanners>
        <genAiPlannerName>{BOT}</genAiPlannerName>
    </conversationDefinitionPlanners>
    <conversationSystemDialogs>
        <dialog>Error_Handler</dialog>
        <type>ErrorHandling</type>
    </conversationSystemDialogs>
    <entryDialog>Welcome</entryDialog>
    <intentDisambiguationEnabled>false</intentDisambiguationEnabled>
    <intentV3Enabled>false</intentV3Enabled>
    <knowledgeFallbackEnabled>false</knowledgeFallbackEnabled>
    <role>{x(ROLE)}</role>
    <smallTalkEnabled>false</smallTalkEnabled>
    <toneType>Casual</toneType>
</BotVersion>
''')


if __name__ == '__main__':
    functions()
    plugins()
    planner()
    bot()
    print(f'classic agent generated: {len(FN)} actions, {len(TOPICS)} topics')
