"""Generates the Bandhu agent (Bandhan Bank credit card advisor) as classic Agentforce metadata: Bot, BotVersion,
GenAiPlannerBundle, one GenAiPlugin topic and three GenAiFunction actions, under bandhan/main/default.
The Bandhu Apex engine owns the journey; the agent routes every message to it and relays the reply verbatim.
Run from the project root: python3 scripts/bandhan/gen_agent.py
"""
import json
import os
from xml.sax.saxutils import escape

ROOT = 'bandhan/main/default'
BOT = 'Bandhu'
AGENT_USER = 'bandhu.agent.00dbm000019hbvj@example.com'   # created by scripts/bandhan/apex/create_agent_user.apex

CONTEXT = ("Always pass journeyId = the journeyId output of the most recent Bandhu action in this conversation (empty on the first call) "
           "and sessionId = the Routable Id (MessagingSession Id) of this conversation; leave sessionId empty if no Routable Id is available.")
RELAY = ("Your reply to the customer MUST be exactly the message output of the action you called, character for character: keep every emoji, "
         "*asterisk*, line break and number. Do not add greetings, summaries, explanations or translations, and never reply with only an acknowledgement.")

ROLE = ("You are Bandhu, the credit card advisor of Bandhan Bank on WhatsApp. Be warm and concise. "
        "Never reveal full PANs, Aadhaar or card numbers, never promise approval before the application is decided, stay on Bandhan Bank card topics "
        "and offer a Bandhan Bank specialist whenever asked. Call the Bandhu actions and relay their message exactly; any short text you write "
        "yourself must be in the customer's language (English, Hindi or Bengali).")
assert len(ROLE) < 1000, len(ROLE)

JOURNEY = [
    'You run the Bandhan Bank credit card journey: card advice, comparison, eligibility, application, KYC and the decision. The Bandhu actions hold the journey state, so never decide yourself which step comes next.',
    'First message, a greeting such as Hi, Hello, Start or Namaste, or no journeyId yet: call Bandhu_StartJourney.',
    'Every other customer message: call Bandhu_ReplyToJourney with the message exactly as typed. That includes option numbers, Yes/No, names, mobile numbers, OTPs, spend choices like "1, 3", incomes, PANs, dates of birth, PIN codes, emails, Aadhaar digits, Done, card names, questions about cards, fees, rewards or lounges, requests to compare cards, language changes (HI, BN, EN, Hindi, Bangla) and requests for a human, agent or specialist. It knows what is pending and returns the next message.',
    'PANs, dates of birth, PIN codes, emails and Aadhaar digits are answers the journey asked for: pass them exactly as typed, never refuse, mask or comment on them. The journey masks them itself. Never repeat an OTP yourself.',
    'When the action output handoff is true (the customer asked for a specialist, was locked out or is not eligible and wants help), reply with the action message and then escalate the conversation to a human. Never escalate without calling Bandhu_ReplyToJourney first: it records the request for the RM.',
    'The message you pass is the customer\'s latest message copied character for character. Never paraphrase or summarise it and never turn it into Yes, No or an option number.',
]

COMMON_OUT = [
    ('message', 'string', 'Message', 'Reply to send to the customer exactly as written, already localised and formatted for WhatsApp.'),
    ('journeyId', 'string', 'Journey Id', 'Card journey record id.'),
    ('awaiting', 'string', 'Awaiting', 'What the journey needs next.'),
    ('language', 'string', 'Language', 'Conversation language: EN, HI or BN.'),
    ('handoff', 'boolean', 'Handoff Recommended', 'True when a human specialist should take over.'),
    ('success', 'boolean', 'Success', 'False when the input could not be used and the customer is being re-asked.'),
]

# developer name -> (apex class, label, description, extra inputs)
ACTIONS = {
    'Bandhu_StartJourney': ('BandhuStartAction', 'Start Card Journey',
        'Starts or resumes the Bandhan Bank credit card advisor journey and returns the welcome menu.', []),
    'Bandhu_ReplyToJourney': ('BandhuReplyAction', 'Reply to Card Journey',
        'Handles every customer reply in the credit card journey and returns the next message. Routes on the saved journey state, so pass the customer message exactly as typed.',
        [('message', 'string', 'Customer Message', 'The customer\'s latest message copied character for character. Never paraphrase, translate or summarise it.', True)]),
    'Bandhu_LogEscalation': ('BandhuEscalateAction', 'Log Specialist Request',
        'Creates a high-priority task for a Bandhan Bank card specialist with everything captured so far, before handing off.',
        [('reason', 'string', 'Reason', 'Short reason for the handoff, in English.', False)]),
}
TOPIC = ('Bandhu_Card_Journey', 'Card Journey',
         'Use for every customer message: greetings, menu choices, short replies such as a number, Yes, No, Done, a name, a mobile number, an OTP, an income, a PAN, a date of birth or a PIN code, questions about Bandhan Bank credit cards (Sparks, Ignite, Flare, Lumina: fees, rewards, lounges, eligibility, documents), comparisons, language changes and requests for a human or specialist. Covers the whole Bandhan Bank credit card journey on WhatsApp.',
         'Advise on and apply for a Bandhan Bank credit card using the Bandhu actions only.',
         ['Bandhu_StartJourney', 'Bandhu_ReplyToJourney', 'Bandhu_LogEscalation'])


def x(s):
    return escape(s, {'"': '&quot;', "'": '&apos;'})


def write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(content)


def prop(ptype, label, desc, is_input):
    p = {'title': label, 'description': desc, 'lightning:type': 'lightning__booleanType' if ptype == 'boolean' else 'lightning__textType',
         'lightning:isPII': False}
    if is_input:
        p['copilotAction:isUserInput'] = False
    else:
        p['copilotAction:isDisplayable'] = False
        p['copilotAction:isUsedByPlanner'] = True
    return p


def functions():
    for fn, (cls, label, desc, inputs) in ACTIONS.items():
        base = f'{ROOT}/genAiFunctions/{fn}'
        write(f'{base}/{fn}.genAiFunction-meta.xml', f'''<?xml version="1.0" encoding="UTF-8"?>
<GenAiFunction xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>{x(desc + ' ' + CONTEXT)}</description>
    <invocationTarget>{cls}</invocationTarget>
    <invocationTargetType>apex</invocationTargetType>
    <isConfirmationRequired>false</isConfirmationRequired>
    <isIncludeInProgressIndicator>false</isIncludeInProgressIndicator>
    <masterLabel>{x('Bandhu - ' + label)}</masterLabel>
</GenAiFunction>
''')
        props, required = {}, []
        for name, ptype, plabel, pdesc, req in [
            ('journeyId', 'string', 'Journey Id', 'journeyId output of the most recent Bandhu action; empty on the first call.', False),
            ('sessionId', 'string', 'Messaging Session Id', 'Routable Id (MessagingSession Id) of this conversation.', False),
        ] + inputs:
            props[name] = prop(ptype, plabel, pdesc, True)
            if req:
                required.append(name)
        write(f'{base}/input/schema.json', json.dumps({'required': required, 'unevaluatedProperties': False, 'properties': props,
                                                        'lightning:type': 'lightning__objectType'}, indent=2, ensure_ascii=False) + '\n')
        outs = {n: prop(t, l, d, False) for n, t, l, d in COMMON_OUT}
        write(f'{base}/output/schema.json', json.dumps({'unevaluatedProperties': False, 'properties': outs,
                                                         'lightning:type': 'lightning__objectType'}, indent=2, ensure_ascii=False) + '\n')


def plugin():
    dev, label, desc, scope, fns = TOPIC
    instr = JOURNEY + [CONTEXT, RELAY]
    items = '\n'.join(f'''    <genAiPluginInstructions>
        <description>{x(t)}</description>
        <developerName>instruction_{i}</developerName>
        <language>en_US</language>
        <masterLabel>instruction_{i}</masterLabel>
        <sortOrder>{i}</sortOrder>
    </genAiPluginInstructions>''' for i, t in enumerate(instr))
    links = '\n'.join(f'''    <genAiFunctions>
        <functionName>{f}</functionName>
    </genAiFunctions>''' for f in fns)
    write(f'{ROOT}/genAiPlugins/{dev}.genAiPlugin-meta.xml', f'''<?xml version="1.0" encoding="UTF-8"?>
<GenAiPlugin xmlns="http://soap.sforce.com/2006/04/metadata">
    <canEscalate>true</canEscalate>
    <description>{x(desc)}</description>
    <developerName>{dev}</developerName>
{links}
{items}
    <language>en_US</language>
    <masterLabel>{x('Bandhu ' + label)}</masterLabel>
    <pluginType>Topic</pluginType>
    <scope>{x(scope)}</scope>
</GenAiPlugin>
''')


def planner():
    write(f'{ROOT}/genAiPlannerBundles/{BOT}/{BOT}.genAiPlannerBundle', f'''<?xml version="1.0" encoding="UTF-8"?>
<GenAiPlannerBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Bandhu planner: routes WhatsApp messages to the Bandhan Bank credit card journey.</description>
    <genAiPlugins>
        <genAiPluginName>{TOPIC[0]}</genAiPluginName>
    </genAiPlugins>
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
        <label>Bandhu</label>
        <name>{BOT}</name>
    </botMlDomain>
    <botSource>None</botSource>
    <botUser>{AGENT_USER}</botUser>
{chr(10).join(cvs)}
    <description>Bandhan Bank credit card advisor on WhatsApp: card recommendation from needs and eligibility, application, KYC and decision, in English, Hindi and Bengali.</description>
    <label>Bandhu - Bandhan Bank Card Advisor</label>
    <logPrivateConversationData>false</logPrivateConversationData>
    <richContentEnabled>true</richContentEnabled>
    <sessionTimeout>30</sessionTimeout>
    <type>ExternalCopilot</type>
</Bot>
''')
    error = "Sorry, I hit a small snag on my side. 🙏 Reply Agent to talk to a Bandhan Bank specialist."
    write(f'{base}/v1.botVersion-meta.xml', f'''<?xml version="1.0" encoding="UTF-8"?>
<BotVersion xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>v1</fullName>
    <articleAnswersGPTEnabled>false</articleAnswersGPTEnabled>
    <botDialogs>
        <botSteps>
            <stepIdentifier>8a2e9b63-4d2f-4c9f-8b62-2c3d4e5f6a03</stepIdentifier>
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
                <messageIdentifier>8a2e9b63-4d2f-4c9f-8b62-2c3d4e5f6a04</messageIdentifier>
            </botMessages>
            <stepIdentifier>8a2e9b63-4d2f-4c9f-8b62-2c3d4e5f6a05</stepIdentifier>
            <type>Message</type>
        </botSteps>
        <botSteps>
            <stepIdentifier>8a2e9b63-4d2f-4c9f-8b62-2c3d4e5f6a06</stepIdentifier>
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
            <stepIdentifier>8a2e9b63-4d2f-4c9f-8b62-2c3d4e5f6a07</stepIdentifier>
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
    plugin()
    planner()
    bot()
    print(f'Bandhu agent generated: {len(ACTIONS)} actions, 1 topic')
