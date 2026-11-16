# Builds the Bandhan deck from a copy of the Axis template (keeps masters, fonts, title / thank-you art).
import sys, copy
sys.path.append('/Users/ntilotia/Library/Python/3.9/lib/python/site-packages')
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.oxml.ns import qn
from lxml import etree

SRC, OUT = sys.argv[1], sys.argv[2]
LOGO = '/tmp/axis_tpl/x/ppt/media/image12.png'
prs = Presentation(SRC)

NAVY = RGBColor(0x15, 0x36, 0x52)      # architecture text
SF_FILL, SF_LINE = RGBColor(0xEA, 0xF4, 0xFF), RGBColor(0x92, 0xAB, 0xC0)
BB_FILL, BB_LINE = RGBColor(0xF2, 0xF2, 0xF2), RGBColor(0x92, 0xAB, 0xC0)
AI_FILL, AI_LINE = SF_FILL, SF_LINE   # Agentforce is Salesforce scope: same blue
ARROW = RGBColor(0x68, 0x7C, 0x8E)
BLUE = RGBColor(0x1B, 0x5F, 0xD9)       # card-grid headings (Axis deck)
DARK = RGBColor(0x0B, 0x22, 0x47)
INK = RGBColor(0x1F, 0x2A, 0x37)
GREY = RGBColor(0x68, 0x7C, 0x8E)
FONT_ARCH, FONT_HEAD = 'Verdana', 'Salesforce Sans'

# ---------------------------------------------------------------- keep slide 1 (title) and 13 (thank you), drop the rest
sldIdLst = prs.slides._sldIdLst
ids = list(sldIdLst)
keep_title, keep_thanks = ids[0], ids[12]
for sid in ids:
    if sid is not keep_title and sid is not keep_thanks:
        rId = sid.get(qn('r:id'))
        prs.part.drop_rel(rId)
        sldIdLst.remove(sid)
title = prs.slides[0]
for sh in title.shapes:
    if sh.has_text_frame and 'Axis' in sh.text_frame.text:
        r = sh.text_frame.paragraphs[0].runs[0]; r.text = 'Bandhan Bank - Credit Cards'
        for extra in sh.text_frame.paragraphs[0].runs[1:]: extra.text = ''
    elif sh.has_text_frame and '2026' in sh.text_frame.text:
        r = sh.text_frame.paragraphs[0].runs[0]; r.text = 'Bandhu: WhatsApp and DIY demo architecture  ·  November 2026'
        for extra in sh.text_frame.paragraphs[0].runs[1:]: extra.text = ''

blank = next(l for l in prs.slide_layouts if l.name == 'BLANK')
default = next((l for l in prs.slide_layouts if l.name == 'DEFAULT'), blank)

def move_before_thanks(slide):
    lst = prs.slides._sldIdLst
    el = lst[-1]; lst.remove(el); lst.insert(len(lst) - 1, el)

def text(slide, x, y, w, h, runs, size=10, color=NAVY, bold=False, align=PP_ALIGN.LEFT, font=FONT_ARCH, anchor=MSO_ANCHOR.TOP):
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame; tf.word_wrap = True
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    tf.vertical_anchor = anchor
    lines = runs if isinstance(runs, list) else [runs]
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        segs = line if isinstance(line, list) else [(line, bold, color, size)]
        for seg in segs:
            t, b, c, sz = (seg + (None, None, None))[:4] if isinstance(seg, tuple) else (seg, bold, color, size)
            r = p.add_run(); r.text = t
            r.font.name = font; r.font.size = Pt(sz or size); r.font.bold = bool(b if b is not None else bold)
            r.font.color.rgb = c or color
    return tb

def box(slide, x, y, w, h, title_, sub, kind='sf'):
    fill, line = {'sf': (SF_FILL, SF_LINE), 'bb': (BB_FILL, BB_LINE), 'ai': (AI_FILL, AI_LINE)}[kind]
    s = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    s.adjustments[0] = 0.12
    s.fill.solid(); s.fill.fore_color.rgb = fill
    s.line.color.rgb = line; s.line.width = Pt(0.75)
    s.shadow.inherit = False
    tf = s.text_frame; tf.clear()
    tf.margin_left = tf.margin_right = Inches(0.06); tf.margin_top = tf.margin_bottom = Inches(0.03)
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE; tf.word_wrap = True
    p = tf.paragraphs[0]; p.alignment = PP_ALIGN.CENTER
    r = p.add_run(); r.text = title_; r.font.name = FONT_ARCH; r.font.size = Pt(10); r.font.bold = True; r.font.color.rgb = NAVY
    for ln in (sub if isinstance(sub, list) else [sub]):
        if not ln: continue
        q = tf.add_paragraph(); q.alignment = PP_ALIGN.CENTER
        rr = q.add_run(); rr.text = ln; rr.font.name = FONT_ARCH; rr.font.size = Pt(7); rr.font.color.rgb = NAVY
    return s

def arrow(slide, x1, y1, x2, y2, both=False):
    c = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    c.line.color.rgb = ARROW; c.line.width = Pt(1)
    ln = c.line._get_or_add_ln()
    tail = etree.SubElement(ln, qn('a:tailEnd')); tail.set('type', 'triangle'); tail.set('w', 'sm'); tail.set('len', 'sm')
    if both:
        head = etree.SubElement(ln, qn('a:headEnd')); head.set('type', 'triangle'); head.set('w', 'sm'); head.set('len', 'sm')
    return c

def header(slide, t, sub, n, total):
    text(slide, 0.42, 0.22, 9.1, 0.36, t, size=22, color=NAVY, font=FONT_HEAD)
    text(slide, 0.42, 0.6, 9.1, 0.2, sub, size=8, color=NAVY)
    text(slide, 0.42, 5.3, 8.4, 0.18, 'Blue: Salesforce (Service Cloud, Data 360, Agentforce, Experience Cloud)     Grey: Bandhan / external systems', size=6, color=NAVY)
    text(slide, 9.0, 5.3, 0.6, 0.18, f'{n} / {total}', size=6, color=NAVY, align=PP_ALIGN.RIGHT)

TOTAL = 4

# ================================================================ slide 2: WhatsApp architecture (Data 360 at the core)
D360_FILL, D360_LINE = SF_FILL, SF_LINE   # Data 360 is Salesforce scope: same blue

def box2(slide, x, y, w, h, t, sub, kind):
    if kind == 'd360':
        b = box(slide, x, y, w, h, t, sub, 'sf')
        b.fill.fore_color.rgb = D360_FILL; b.line.color.rgb = D360_LINE; b.line.width = Pt(0.75)
        return b
    return box(slide, x, y, w, h, t, sub, kind)

def legend2(slide):
    # replace the default legend line with one that names Data 360
    for sh in list(slide.shapes):
        if sh.has_text_frame and sh.text_frame.text.startswith('Blue: Salesforce'):
            sh._element.getparent().remove(sh._element)
    text(slide, 0.42, 5.3, 8.4, 0.18, 'Blue: Salesforce (Service Cloud, Data 360, Agentforce, Experience Cloud)     Grey: Bandhan / external systems', size=6, color=NAVY)

def channel_slide(title, sub, n, channel_title, channel_sub, side_title, side_sub):
    s = prs.slides.add_slide(blank); move_before_thanks(s)
    header(s, title, sub, n, TOTAL); legend2(s)
    C, L, R, W = 3.7, 0.5, 6.9, 2.6
    box2(s, C, 0.88, W, 0.38, 'Customer', 'English / Hindi / Bengali', 'bb')
    box2(s, C, 1.4, W, 0.5, channel_title, channel_sub, 'sf')
    box2(s, L, 1.4, W, 0.5, side_title, side_sub, 'sf')
    box2(s, R, 1.4, W, 0.5, 'Bandhan API gateway', ['Live calls: OTP, KYC, bureau pull,', 'AA consent, card issue, Neev sync'], 'bb')
    box2(s, C, 2.05, W, 0.62, 'Agentforce', ['Bandhu agent + Prompt Builder:', 'answers, notes, underwriter brief;', 'actions run the Bandhu journey'], 'ai')
    box2(s, L, 2.05, W, 0.62, 'Bandhu journey + decisioning', ['Eligibility, CIBIL bands, Bandhan', 'Score, limits: rules decide'], 'sf')
    box2(s, R, 2.05, W, 0.62, 'Leads + underwriting', ['Service Cloud: leads (7 gates, scores,', 'nudges), underwriting; synced to Neev'], 'sf')
    box2(s, L, 2.85, 8.9, 0.62, 'Data 360: one Bandhan customer profile', ['Identity resolution on mobile / PAN  ·  calculated insights: cash flow, FOIR, stability, spend by category, lifestyle, Bandhan Score inputs', 'Grounds Agentforce (retrieval)  ·  segments for re-approach and limit offers  ·  journey and consent events streamed in'], 'd360')
    srcs = [('Account Aggregator', ['24 months of statements', 'via Bandhan FIU']), ('CIBIL / bureau', ['Report, DPD, enquiries,', 'utilisation']),
            ('Core banking (CBS)', ['Accounts, balances, FDs,', 'loans, tier']), ('KYC, GST, AIS', ['UIDAI, NSDL, GSTN,', 'Form 26AS / AIS'])]
    sw = 2.12
    for k, (t, d) in enumerate(srcs):
        x = L + k * (sw + 0.14)
        box2(s, x, 3.68, sw, 0.55, t, d, 'bb')
        arrow(s, x + sw / 2, 3.68, x + sw / 2, 3.47)
    box2(s, L, 4.4, 4.35, 0.78, 'How the data arrives', ['Real-time: Ingestion API from the gateway for AA, bureau and KYC', 'Batch / Zero Copy: CBS and the warehouse, no data copies', 'Streaming: journey steps, consents, card events'], 'd360')
    box2(s, L + 4.55, 4.4, 4.35, 0.78, 'Shared responsibilities', ['Bandhan: FIU and bureau contracts, gateway APIs, credit policy, Neev', 'Salesforce: Service Cloud, Data 360, Agentforce, Experience Cloud, journey', 'AI writes; the rules decide; underwriters approve'], 'bb')
    # arrows: customer <-> channel <-> agentforce ; agentforce <-> journey, <-> leads ; data 360 up to the three ; gateway down to sources
    arrow(s, 5.0, 1.26, 5.0, 1.4, True); arrow(s, 5.0, 1.9, 5.0, 2.05, True)
    arrow(s, 3.7, 1.65, 3.1, 1.65, True)
    arrow(s, 3.7, 2.36, 3.1, 2.36, True); arrow(s, 6.3, 2.36, 6.9, 2.36, True)
    arrow(s, 8.2, 1.9, 8.2, 2.05, True)
    arrow(s, 1.8, 2.85, 1.8, 2.67); arrow(s, 5.0, 2.85, 5.0, 2.67); arrow(s, 8.2, 2.85, 8.2, 2.67)
    return s

TOTAL = 4
channel_slide('WhatsApp Architecture', 'Bandhu on WhatsApp: bank and bureau data unified in Data 360; Agentforce works on top of one customer profile', 1,
              'WhatsApp on Service Cloud', ['Messaging for WhatsApp (BSP),', 'Omni-Channel routing'], 'Service Cloud handoff', ['Service Console + Bandhu panel:', 'every answer, why they asked'])
channel_slide('Salesforce DIY architecture', 'The web journey on Experience Cloud: the same Data 360 profile, Agentforce and journey as WhatsApp', 2,
              'Salesforce DIY journey', ['Experience Cloud page: card range,', 'chat, tiles, language switch'], 'Branch-assisted', ['Service Cloud RM 360: card to pitch;', 'customer finishes on chat'])

# ================================================================ slide 4: Data 360 + Agentforce integration (left to right)
s = prs.slides.add_slide(blank); move_before_thanks(s)
header(s, 'Data 360 and Agentforce integration', 'Every source lands once in Data 360; Agentforce, the journey and the consoles read the same profile', 3, TOTAL); legend2(s)
cols = [0.45, 2.85, 5.45, 7.75]
TOP, BOT = 1.12, 4.98
text(s, cols[0], 0.9, 2.1, 0.2, 'SOURCES · BANDHAN / EXTERNAL', size=7, bold=True, color=GREY)
text(s, cols[1], 0.9, 2.3, 0.2, 'DATA 360 · SALESFORCE', size=7, bold=True, color=BLUE)
text(s, cols[2], 0.9, 2.0, 0.2, 'AGENTFORCE · SALESFORCE', size=7, bold=True, color=BLUE)
text(s, cols[3], 0.9, 1.8, 0.2, 'SERVICE + EXPERIENCE CLOUD', size=7, bold=True, color=BLUE)
# sources: 7 boxes, each arrow lands on the Data 360 band
sources = [('Account Aggregator', 'FIU · consent-scoped · real-time'), ('CIBIL / bureau', 'soft + hard pull · real-time'),
           ('Core banking (CBS)', 'accounts, FDs, loans · Zero Copy'), ('KYC: UIDAI, NSDL', 'eKYC, PAN · real-time'),
           ('GSTN, 26AS / AIS', 'income cross-checks · on demand'), ('Card platform', 'issue, activation, spend · events'),
           ('Neev (leads)', 'two-way lead sync · API')]
sh_, gap = 0.48, (BOT - TOP - 7 * 0.48) / 6
for k, (t, d) in enumerate(sources):
    y = TOP + k * (sh_ + gap)
    box2(s, cols[0], y, 2.1, sh_, t, d, 'bb')
    arrow(s, cols[0] + 2.1, y + sh_ / 2, cols[1], y + sh_ / 2, k == 6)
# Data 360: one band, the capabilities stacked inside
band = box2(s, cols[1], TOP, 2.3, BOT - TOP, '', '', 'd360')
inner = [('Ingestion', 'Ingestion API · streams · Zero Copy'), ('Harmonise + identity', 'one profile on mobile / PAN'),
         ('Calculated insights', 'cash flow, FOIR, stability, spend, lifestyle, Bandhan Score inputs'),
         ('Segments + triggers', 'drop-offs, re-approach, limit offers'), ('Consent + governance', 'DPDP purpose, AA expiry, retention')]
iy = TOP + 0.08
for t, d in inner:
    h = 0.66 if t == 'Calculated insights' else 0.56
    b = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(cols[1] + 0.1), Inches(iy), Inches(2.1), Inches(h)); b.adjustments[0] = 0.12
    b.fill.solid(); b.fill.fore_color.rgb = RGBColor(0xFF, 0xFF, 0xFF); b.line.color.rgb = D360_LINE; b.line.width = Pt(0.5); b.shadow.inherit = False
    text(s, cols[1] + 0.16, iy + 0.06, 1.98, 0.2, t, size=8.5, bold=True, color=NAVY, align=PP_ALIGN.CENTER)
    text(s, cols[1] + 0.16, iy + 0.27, 1.98, h - 0.3, d, size=6.5, color=NAVY, align=PP_ALIGN.CENTER)
    iy += h + 0.1
# one arrow Data 360 -> Agentforce, at mid height
arrow(s, cols[1] + 2.3, (TOP + 3.3) / 2 + 0.6, cols[2], (TOP + 3.3) / 2 + 0.6, True)
# Agentforce: one band, capabilities inside
AF_BOT = 3.3
box2(s, cols[2], TOP, 2.05, AF_BOT - TOP, '', '', 'ai')
af = [('Grounding (RAG)', 'profile + insights + card catalogue'), ('Bandhu agent', 'conversation + journey actions'),
      ('Prompt Builder', 'card answers · notes · underwriter brief'), ('Trust Layer', 'masking · no retention · audit')]
iy = TOP + 0.07
for t, d in af:
    b = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(cols[2] + 0.1), Inches(iy), Inches(1.85), Inches(0.44)); b.adjustments[0] = 0.12
    b.fill.solid(); b.fill.fore_color.rgb = RGBColor(0xFF, 0xFF, 0xFF); b.line.color.rgb = AI_LINE; b.line.width = Pt(0.5); b.shadow.inherit = False
    text(s, cols[2] + 0.14, iy + 0.04, 1.77, 0.18, t, size=8, bold=True, color=NAVY, align=PP_ALIGN.CENTER)
    text(s, cols[2] + 0.14, iy + 0.23, 1.77, 0.2, d, size=6, color=NAVY, align=PP_ALIGN.CENTER)
    iy += 0.53
# channels: each one arrow from the Agentforce band
users = [('WhatsApp', 'Service Cloud messaging'), ('DIY web', 'Experience Cloud'), ('Branch RM', 'Service Cloud · RM 360'), ('Underwriter', 'Service Cloud console'), ('Leads team', 'Service Cloud · nudges')]
uh, ugap = 0.4, (AF_BOT - TOP - 5 * 0.4) / 4
for k, (t, d) in enumerate(users):
    y = TOP + k * (uh + ugap)
    box2(s, cols[3], y, 1.8, uh, t, d, 'sf')
    arrow(s, cols[2] + 2.05, y + uh / 2, cols[3], y + uh / 2, True)
box2(s, cols[2], 3.48, 4.1, 1.5, 'Rules decide, AI writes', ['Eligibility, CIBIL bands, Bandhan Score and limits run as explainable rules on Data 360 insights', 'Agentforce answers, explains and drafts; underwriters approve', 'Every decision logs its factors; consent and data purpose enforced in Data 360', 'Same profile and rules on WhatsApp, web and branch'], 'sf')

# ================================================================ slide 4: one lead, three channels (journey + lead flow)
s = prs.slides.add_slide(blank); move_before_thanks(s)
header(s, 'From first message to card: one record', 'The lead is created, scored and nudged on the Data 360 profile and kept in step with Neev; the customer never repeats an answer', 4, TOTAL)
steps = [
    ('1', 'Hi on WhatsApp or the web', 'Consent, name, mobile OTP: existing customers recognised'),
    ('2', 'Details, income, statements', 'AA + CIBIL into Data 360: insights in seconds'),
    ('3', 'Needs in one run', 'What they spend on, how much, fee preference'),
    ('4', 'Recommendation + AI note', 'Card that fits the statements, why, limit range'),
    ('5', 'KYC and decision', 'Straight-through, or the underwriter with a brief'),
    ('6', 'Card, rewards tip, activation', 'Virtual card, MITC, earn-more tip, OTP activation'),
]
x0, y0, bw, bh = 0.5, 0.98, 1.43, 1.12
for i, (n, t, d) in enumerate(steps):
    x = x0 + i * (bw + 0.08)
    b = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y0), Inches(bw), Inches(bh)); b.adjustments[0] = 0.1
    b.fill.solid(); b.fill.fore_color.rgb = AI_FILL if n in ('2', '4') else SF_FILL; b.line.color.rgb = AI_LINE if n in ('2', '4') else SF_LINE; b.line.width = Pt(0.75); b.shadow.inherit = False
    text(s, x + 0.08, y0 + 0.06, bw - 0.16, 0.2, n, size=12, bold=True, color=BLUE)
    text(s, x + 0.08, y0 + 0.3, bw - 0.16, 0.32, t, size=7.5, bold=True, color=NAVY)
    text(s, x + 0.08, y0 + 0.63, bw - 0.16, 0.4, d, size=6.5, color=NAVY)
    if i < len(steps) - 1:
        arrow(s, x + bw, y0 + bh / 2, x + bw + 0.08, y0 + bh / 2)
# the lead lane
lane = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.5), Inches(2.3), Inches(8.9), Inches(1.35)); lane.adjustments[0] = 0.06
lane.fill.solid(); lane.fill.fore_color.rgb = SF_FILL; lane.line.color.rgb = SF_LINE; lane.line.width = Pt(0.75); lane.shadow.inherit = False
text(s, 0.65, 2.38, 8.6, 0.22, 'Lead management in Service Cloud, in step with Neev', size=10, bold=True, color=NAVY)
lanes = [
    ('Created at the OTP', 'New-to-bank: a Lead the moment the mobile is verified; existing customers stay on their Contact'),
    ('7 qualification gates', 'Serviceability, consent, dedupe & fraud, CIBIL, income, employment, card eligibility: knock-outs stop the nudges'),
    ('Scored live', 'Intent and credit scores, rating Hot / Warm / Cold, drop point and journey path on one page'),
    ('Nudged and resumed', 'Drop-off after a few minutes: RM task, WhatsApp nudge, "Continue" returns to the same question'),
    ('Kept in step with Neev', 'Lead, status and outcome synced through the API gateway so Neev reporting is unchanged'),
]
lx, lw = 0.65, 1.67
for i, (t, d) in enumerate(lanes):
    x = lx + i * (lw + 0.05)
    text(s, x, 2.68, lw - 0.05, 0.2, t, size=8, bold=True, color=BLUE)
    text(s, x, 2.9, lw - 0.05, 0.72, d, size=6.5, color=NAVY)
# bottom row: what the RM and underwriter see
for i, (t, d) in enumerate([
    ('RM · Service Cloud', 'Full-width lead page with card, scores and the next best action; RM 360 for existing customers with the card to pitch'),
    ('Underwriter · Service Cloud', 'Checks, Account Aggregator cash flow, Bandhan Score factors and an Agentforce brief, on one page'),
    ('Customer', 'Same journey on WhatsApp and the web, in English, Hindi or Bengali; resumes anywhere'),
]):
    x = 0.5 + i * 3.0
    b = box(s, x, 3.85, 2.9, 0.95, t, [d], 'sf')   # Salesforce screens: blue
text(s, 0.5, 4.92, 8.9, 0.3, 'Neev integration shown as the target design: in the demo, leads live in Salesforce only.', size=6.5, color=GREY)

# ================================================================ slide 5: what Salesforce brings (Axis "What Salesforce solves" card grid)
s = prs.slides.add_slide(default); move_before_thanks(s)
for sh in list(s.shapes):
    if sh.is_placeholder: sh._element.getparent().remove(sh._element)
text(s, 0.45, 0.42, 8.4, 0.5, 'What Salesforce brings to Bandhan', size=22, bold=True, color=DARK, font=FONT_HEAD)
s.shapes.add_picture(LOGO, Emu(8275320), Emu(425196), Emu(475488), Emu(332842))
text(s, 0.45, 0.93, 8.4, 0.3, 'From a lead list in Neev to one live, AI-assisted customer thread', size=13, color=BLUE, font=FONT_HEAD)
cards = [
    ('One journey, every channel', 'Service Cloud messaging, Experience Cloud and branch share one engine and record. A rule changes once, everywhere.'),
    ('Leads that self-qualify', 'Service Cloud leads: seven gates, intent and credit scores, drop point, RM nudge. Live, not T+1; synced to Neev.'),
    ('Decisions from real cash flow', 'Account Aggregator statements, CIBIL bands and the Bandhan Score: explainable, factor by factor.'),
    ('Agentforce where it helps', 'Free-form card answers, a personal note in Hindi or Bengali, an underwriter brief. AI writes; rules decide.'),
    ('Compliance built in', 'DPDP consent, AA purpose and expiry, hard-enquiry notice, MITC, activation and cooling-off, logged.'),
    ('Configure, don\'t rebuild', 'Cards, thresholds, messages and AI prompts are configuration. New capability, no app release.'),
]
cw, ch = 2.85, 1.42
for i, (t, d) in enumerate(cards):
    col, row = i % 3, i // 3
    x, y = 0.45 + col * (cw + 0.13), 1.45 + row * (ch + 0.18)
    b = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(cw), Inches(ch)); b.adjustments[0] = 0.06
    b.fill.solid(); b.fill.fore_color.rgb = RGBColor(0xFF, 0xFF, 0xFF); b.line.color.rgb = RGBColor(0xE6, 0xEA, 0xF0); b.line.width = Pt(0.75)
    text(s, x + 0.2, y + 0.16, cw - 0.4, 0.3, t, size=10.5, bold=True, color=BLUE, font=FONT_HEAD)
    text(s, x + 0.2, y + 0.52, cw - 0.4, 0.86, d, size=8.5, color=INK, font=FONT_HEAD)

# ================================================================ slide 6: how Salesforce grows card sales (facts sourced; levers)
s = prs.slides.add_slide(default); move_before_thanks(s)
for sh in list(s.shapes):
    if sh.is_placeholder: sh._element.getparent().remove(sh._element)
text(s, 0.45, 0.32, 7.6, 0.45, 'Growing card sales from Bandhan\'s base', size=20, bold=True, color=DARK, font=FONT_HEAD)
s.shapes.add_picture(LOGO, Emu(8275320), Emu(300000), Emu(475488), Emu(332842))
text(s, 0.45, 0.8, 8.6, 0.28, 'Cards launched in Q2 FY27: the bank names cross-sell, salary customers and digital as the path', size=10, color=BLUE, font=FONT_HEAD)
# fact strip (sourced)
facts = [('Q2 FY27', 'credit cards launched:', 'Sparks · Ignite · Flare · Lumina'), ('2,001 + 4,414', 'branches + banking units', 'to sell and service'),
         ('1.72 lakh cr', 'INR deposits: a large existing', 'base to cross-sell'), ('8,642 / month', 'retail leads on Neev today', '(Y1 sizing, in-scope loans)')]
fw = 2.12
for k, (big, l1, l2) in enumerate(facts):
    x = 0.45 + k * (fw + 0.1)
    b = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(1.16), Inches(fw), Inches(0.78)); b.adjustments[0] = 0.08
    b.fill.solid(); b.fill.fore_color.rgb = SF_FILL; b.line.color.rgb = SF_LINE; b.line.width = Pt(0.75); b.shadow.inherit = False
    text(s, x + 0.14, 1.22, fw - 0.28, 0.3, big, size=15, bold=True, color=DARK, font=FONT_HEAD)
    text(s, x + 0.14, 1.53, fw - 0.28, 0.4, [l1, l2], size=7.5, color=INK, font=FONT_HEAD)
# levers: 6 cards, each = what Salesforce does (and what the demo already shows)
levers = [
    ('Find who is ready', 'Data 360 scores existing savings, salary and loan customers on cash flow and spend: a ranked, pre-approved list per branch.'),
    ('Sell where they already are', 'Bandhu on WhatsApp, the web and mBandhan: apply in minutes, in English, Hindi or Bengali, AA instead of documents.'),
    ('Corporate salary accounts', 'Payroll customers recognised on login: pre-filled journey, pre-approved card, no income proof.'),
    ('Arm 2,001 branches', 'Service Cloud RM 360 shows the card to pitch and starts the application; the customer finishes on their phone.'),
    ('Win back drop-offs', 'Service Cloud scores every lead live; WhatsApp nudges in minutes; declined customers re-approached when they qualify.'),
    ('Grow every card', 'Earn-more tips from spend data, consented limit and upgrade offers, activation in 30 days tracked.'),
]
cw, ch = 2.85, 1.05
for i, (t, d) in enumerate(levers):
    col, row = i % 3, i // 3
    x, y = 0.45 + col * (cw + 0.13), 2.12 + row * (ch + 0.12)
    b = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(cw), Inches(ch)); b.adjustments[0] = 0.06
    b.fill.solid(); b.fill.fore_color.rgb = RGBColor(0xFF, 0xFF, 0xFF); b.line.color.rgb = RGBColor(0xE6, 0xEA, 0xF0); b.line.width = Pt(0.75)
    text(s, x + 0.18, y + 0.12, cw - 0.36, 0.26, t, size=10.5, bold=True, color=BLUE, font=FONT_HEAD)
    text(s, x + 0.18, y + 0.42, cw - 0.36, 0.62, d, size=8, color=INK, font=FONT_HEAD)
text(s, 0.45, 4.48, 9.1, 0.32, [[('Measure it: ', True, DARK, 8.5), ('leads, approvals, cards, activation and spend by channel, branch and campaign, live in Salesforce (not a monthly MIS).', False, INK, 8.5)]], font=FONT_HEAD)
text(s, 0.45, 5.12, 9.1, 0.35, 'Sources: Bandhan Bank Q2 FY27 earnings call (28 Oct 2026) and Q2 FY27 results (deposits, branches, card launch); Bandhan retail asset licence sizing (Neev leads, Y1). No card volumes published yet.', size=6.5, color=GREY, font=FONT_HEAD)

prs.save(OUT)
print('saved', OUT, 'slides', len(prs.slides))
