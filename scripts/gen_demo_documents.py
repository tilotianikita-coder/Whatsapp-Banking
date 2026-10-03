#!/usr/bin/env python3
"""Mock KYC files for the LOS demo: a PAN card image and a 6-month bank statement PDF.

Every page carries a SPECIMEN watermark - these are demo artefacts, not real documents. Figures follow the
mock Perfios report for the applicant so the Credit Review and the files tell the same story.

    python3 scripts/gen_demo_documents.py /tmp/docs
"""
import os
import random
import sys
from datetime import date

from PIL import Image, ImageDraw, ImageFont

APPLICANT = {
    'name': 'PRIYA SHARMA', 'father': 'RAJESH KUMAR SHARMA', 'dob': '30/06/1982', 'pan': 'ABCPS1234K',
    'address': ['Flat 304, Sai Krupa CHS, Andheri West', 'Mumbai, Maharashtra 400060'],
    'bank': 'State Bank of India', 'branch': 'Andheri West, Mumbai', 'ifsc': 'SBIN0001234', 'account': '30871128400',
    'employer': 'INFOSYS LTD', 'salary': 83300,
}
# Month, total credits, total debits (from the Perfios monthly summary).
MONTHS = [(2026, 4, 86600, 83100), (2026, 5, 86600, 77900), (2026, 6, 85800, 76400),
          (2026, 7, 88300, 81200), (2026, 8, 86600, 83100), (2026, 9, 85000, 77400)]
OPENING = 13700

FONT_DIR = '/System/Library/Fonts/Supplemental/'


def font(size, bold=False):
    for name in (('Arial Bold.ttf' if bold else 'Arial.ttf'), 'Arial.ttf'):
        path = os.path.join(FONT_DIR, name)
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def watermark(img, text='SPECIMEN - DEMO ONLY', size=90, alpha=60):
    layer = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    f = font(size, True)
    w = d.textlength(text, font=f)
    d.text(((img.width - w) / 2, img.height / 2 - size / 2), text, font=f, fill=(200, 0, 0, alpha))
    layer = layer.rotate(25, center=(img.width / 2, img.height / 2))
    return Image.alpha_composite(img.convert('RGBA'), layer).convert('RGB')


def pan_card(path):
    a = APPLICANT
    img = Image.new('RGB', (1012, 638), (214, 232, 245))
    d = ImageDraw.Draw(img)
    for y in range(638):
        shade = int(232 - y * 0.05)
        d.line([(0, y), (1012, y)], fill=(214, shade, 245))
    d.rectangle([0, 0, 1012, 92], fill=(18, 72, 140))
    d.text((30, 14), 'INCOME TAX DEPARTMENT', font=font(30, True), fill='white')
    d.text((30, 52), 'Permanent Account Number Card (mock)', font=font(20), fill=(220, 230, 255))
    d.text((680, 30), 'GOVT. OF INDIA', font=font(30, True), fill='white')
    d.rounded_rectangle([40, 130, 270, 420], radius=8, fill=(236, 240, 245), outline=(120, 140, 160), width=2)
    d.ellipse([105, 170, 205, 270], fill=(170, 182, 196))
    d.pieslice([70, 270, 240, 420], 180, 360, fill=(170, 182, 196))
    d.text((112, 430), 'PHOTO', font=font(18), fill=(90, 100, 110))
    x = 320
    rows = [('Permanent Account Number', a['pan']), ('Name', a['name']), ("Father's Name", a['father']), ('Date of Birth', a['dob'])]
    y = 130
    for label, value in rows:
        d.text((x, y), label, font=font(18), fill=(60, 70, 85))
        d.text((x, y + 24), value, font=font(34 if label.startswith('Permanent') else 28, True), fill=(10, 20, 40))
        y += 92
    d.line([(x, 540), (x + 260, 540)], fill=(40, 40, 60), width=2)
    d.text((x, 548), 'Signature', font=font(16), fill=(60, 70, 85))
    d.text((x + 10, 505), 'Priya Sharma', font=font(28), fill=(20, 40, 120))
    img = watermark(img, size=70, alpha=80)
    img.save(path)


def transactions():
    """Salary on the 3rd/4th, rent, SIP, bills, UPI spends and an ATM withdrawal, matching each month's totals."""
    rng = random.Random(APPLICANT['pan'])
    a = APPLICANT
    out = []
    balance = OPENING
    for year, month, credits, debits in MONTHS:
        day = 3 + rng.randint(0, 1)
        rows = [(date(year, month, day), 'NEFT/SAL/' + a['employer'] + '/' + date(year, month, 1).strftime('%b%y').upper(), 0, a['salary'])]
        other_credit = credits - a['salary']
        if other_credit:
            rows.append((date(year, month, 12 + rng.randint(0, 10)), 'UPI/CR/REFUND-' + rng.choice(['AMAZON', 'FLIPKART', 'MYNTRA', 'SWIGGY']), 0, other_credit))
        fixed = [
            (5, 'IMPS/RENT/SAI KRUPA CHS', 20000),
            (7, 'NACH/SIP/SBI MF-' + str(rng.randint(100000, 999999)), 5000),
            (7, 'NACH/RD/SBI RD A/C', 2500),
            (9, 'BILLPAY/MSEDCL ELECTRICITY', 1800 + rng.randint(0, 8) * 100),
            (10, 'BILLPAY/AIRTEL POSTPAID', 999),
            (11, 'BILLPAY/MAHANAGAR GAS', 600 + rng.randint(0, 5) * 50),
            (15, 'ATM WDL/SBI ANDHERI W', 2500),
        ]
        spent = sum(f[2] for f in fixed)
        for d_, desc, amt in fixed:
            rows.append((date(year, month, d_), desc, amt, 0))
        merchants = ['BIGBASKET', 'ZOMATO', 'SWIGGY', 'DMART', 'UBER', 'AMAZON PAY', 'BOOKMYSHOW', 'PHARMEASY', 'CROMA', 'STARBUCKS', 'OLA', 'RELIANCE SMART']
        remaining = debits - spent
        n = 9 + rng.randint(0, 3)
        weights = [rng.uniform(0.5, 1.5) for _ in range(n)]
        parts = [int(remaining * w / sum(weights) / 10) for w in weights]
        parts[-1] += (remaining - sum(p * 10 for p in parts)) // 10
        for p in parts:
            rows.append((date(year, month, 6 + rng.randint(0, 22)), 'UPI/DR/' + rng.choice(merchants), p * 10, 0))
        rows.sort(key=lambda r: (r[0], r[3] == 0))
        for d_, desc, dr, cr in rows:
            balance += cr - dr
            out.append((d_, desc, dr, cr, balance))
    return out


def money(v):
    if not v:
        return ''
    s = f'{v:,.2f}'
    whole, frac = s.split('.')
    digits = whole.replace(',', '')
    if len(digits) > 3:
        head, tail = digits[:-3], digits[-3:]
        groups = []
        while len(head) > 2:
            groups.insert(0, head[-2:])
            head = head[:-2]
        if head:
            groups.insert(0, head)
        whole = ','.join(groups) + ',' + tail
    return whole + '.' + frac


def bank_statement(path):
    a = APPLICANT
    W, H = 1240, 1754
    txns = transactions()
    per_page = 36
    pages = []
    chunks = [txns[i:i + per_page] for i in range(0, len(txns), per_page)]
    for n, chunk in enumerate(chunks, 1):
        img = Image.new('RGB', (W, H), 'white')
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, W, 110], fill=(0, 82, 155))
        d.text((60, 28), a['bank'].upper(), font=font(38, True), fill='white')
        d.text((60, 74), 'Statement of Account (mock)', font=font(20), fill=(210, 225, 245))
        d.text((W - 300, 74), f'Page {n} of {len(chunks)}', font=font(20), fill='white')
        y = 140
        if n == 1:
            left = [('Account holder', a['name']), ('Address', a['address'][0]), ('', a['address'][1]), ('Account type', 'Savings - Salary')]
            right = [('Account number', 'XXXXXXX' + a['account'][-4:]), ('Branch', a['branch']), ('IFSC', a['ifsc']),
                     ('Period', '01 Apr 2026 to 30 Sep 2026')]
            for i, ((l1, v1), (l2, v2)) in enumerate(zip(left, right)):
                d.text((60, y + i * 30), l1, font=font(18), fill=(90, 90, 90))
                d.text((240, y + i * 30), v1, font=font(18, True), fill='black')
                d.text((680, y + i * 30), l2, font=font(18), fill=(90, 90, 90))
                d.text((860, y + i * 30), v2, font=font(18, True), fill='black')
            y += 140
            total_cr = sum(t[3] for t in txns)
            total_dr = sum(t[2] for t in txns)
            d.rectangle([60, y, W - 60, y + 60], fill=(240, 245, 250), outline=(200, 210, 220))
            summary = [('Opening balance', money(OPENING)), ('Total credits', money(total_cr)), ('Total debits', money(total_dr)), ('Closing balance', money(txns[-1][4]))]
            for i, (l, v) in enumerate(summary):
                d.text((80 + i * 280, y + 8), l, font=font(16), fill=(90, 90, 90))
                d.text((80 + i * 280, y + 30), 'INR ' + v, font=font(18, True), fill='black')
            y += 90
        cols = [(60, 'Date'), (190, 'Narration'), (780, 'Debit'), (920, 'Credit'), (1060, 'Balance')]
        d.rectangle([60, y, W - 60, y + 34], fill=(0, 82, 155))
        for x, label in cols:
            d.text((x + 8, y + 7), label, font=font(17, True), fill='white')
        y += 40
        for i, (dt, desc, dr, cr, bal) in enumerate(chunk):
            if i % 2:
                d.rectangle([60, y - 3, W - 60, y + 30], fill=(247, 249, 252))
            d.text((68, y), dt.strftime('%d-%m-%Y'), font=font(16), fill='black')
            d.text((198, y), desc[:52], font=font(16), fill='black')
            for x, v in ((780, dr), (920, cr), (1060, bal)):
                s = money(v)
                d.text((x + 120 - d.textlength(s, font=font(16)), y), s, font=font(16), fill=(170, 0, 0) if x == 780 else 'black')
            y += 34
        d.text((60, H - 70), 'Computer-generated mock statement for the LoanSeva demo. Not a real bank document.', font=font(15), fill=(120, 120, 120))
        pages.append(watermark(img, size=90, alpha=45))
    pages[0].save(path, save_all=True, append_images=pages[1:], resolution=150)


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else '/tmp/docs'
    os.makedirs(out, exist_ok=True)
    pan_card(os.path.join(out, 'Priya_Sharma_PAN_Card.png'))
    bank_statement(os.path.join(out, 'Priya_Sharma_SBI_Statement_Apr-Sep_2026.pdf'))
    print('written to', out)
