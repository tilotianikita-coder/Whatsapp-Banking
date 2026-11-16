"""Generates the Bandhu permission sets from the metadata under bandhan/. Run from the project root:
python3 scripts/bandhan/gen_permsets.py
  Bandhu_Admin  - RMs, underwriters, admins: full access to the card objects, fields, tabs and classes.
  Bandhu_Agent  - the Agentforce agent user: runs the Bandhu actions across customers.
  Bandhu_Guest  - the public site guest: the web journey page and its controller only.
"""
import os

BASE = 'bandhan/main/default'
OBJ = os.path.join(BASE, 'objects')
OUT = os.path.join(BASE, 'permissionsets')
CUSTOM = ['Card_Journey__c', 'Card_Application__c', 'Card_Check__c', 'Bank_Relationship__c', 'Bandhu_Lead_Check__c', 'Bandhu_Consent__c', 'Bandhu_Document__c']
FIELD_ONLY = ['Lead', 'Contact']
MDT = ['Bandhu_Card__mdt', 'Bandhu_Config__mdt', 'Bandhu_Message__mdt', 'Bandhu_Region__mdt']
TABS = ['Bandhu_Leads', 'Card_Journey__c', 'Card_Application__c', 'WhatsApp_Demo_Component']


def fields(obj):
    d = os.path.join(OBJ, obj, 'fields')
    out = []
    for f in sorted(os.listdir(d)):
        xml = open(os.path.join(d, f)).read()
        if '<type>MasterDetail</type>' in xml or '<required>true</required>' in xml:
            continue
        out.append((f.replace('.field-meta.xml', ''), '<formula>' not in xml))
    return out


def classes(include_tests=False):
    names = sorted(f[:-4] for f in os.listdir(os.path.join(BASE, 'classes')) if f.endswith('.cls'))
    return [n for n in names if include_tests or not n.endswith('Test') and n != 'BandhuTestData']


def objperm(obj, c, e, d, v, m):
    return (f'    <objectPermissions>\n        <allowCreate>{c}</allowCreate>\n        <allowDelete>{d}</allowDelete>\n'
            f'        <allowEdit>{e}</allowEdit>\n        <allowRead>true</allowRead>\n        <modifyAllRecords>{m}</modifyAllRecords>\n'
            f'        <object>{obj}</object>\n        <viewAllRecords>{v}</viewAllRecords>\n    </objectPermissions>\n')


def write(name, label, desc, class_list, pages=(), objects=True, perms=None, tabs=True, extra_objects=''):
    parts = [f'<?xml version="1.0" encoding="UTF-8"?>\n<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">\n'
             f'    <description>{desc}</description>\n    <hasActivationRequired>false</hasActivationRequired>\n    <label>{label}</label>\n']
    if name == 'Bandhu_Admin':
        parts.append('    <applicationVisibilities>\n        <application>Bandhu_Cards</application>\n        <visible>true</visible>\n    </applicationVisibilities>\n')
    for c in class_list:
        parts.append(f'    <classAccesses>\n        <apexClass>{c}</apexClass>\n        <enabled>true</enabled>\n    </classAccesses>\n')
    for m in MDT:
        parts.append(f'    <customMetadataTypeAccesses>\n        <enabled>true</enabled>\n        <name>{m}</name>\n    </customMetadataTypeAccesses>\n')
    if objects:
        for obj in CUSTOM + FIELD_ONLY:
            for f, editable in fields(obj):
                parts.append(f'    <fieldPermissions>\n        <editable>{str(editable).lower()}</editable>\n        <field>{obj}.{f}</field>\n'
                             f'        <readable>true</readable>\n    </fieldPermissions>\n')
        for obj in CUSTOM:
            parts.append(objperm(obj, *perms))
        parts.append(extra_objects)
    for p in pages:
        parts.append(f'    <pageAccesses>\n        <apexPage>{p}</apexPage>\n        <enabled>true</enabled>\n    </pageAccesses>\n')
    if tabs:
        for t in TABS:
            parts.append(f'    <tabSettings>\n        <tab>{t}</tab>\n        <visibility>Visible</visibility>\n    </tabSettings>\n')
    parts.append('</PermissionSet>\n')
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + '.permissionset-meta.xml'), 'w') as fh:
        fh.write(''.join(parts))


def std(obj, c, e, v):
    return objperm(obj, c, e, 'false', v, 'false')


pages = [p[:-5] for p in os.listdir(os.path.join(BASE, 'pages')) if p.endswith('.page')] if os.path.isdir(os.path.join(BASE, 'pages')) else []
write('Bandhu_Admin', 'Bandhu Admin', 'Full access to the Bandhu credit card objects, fields and Apex (RMs, underwriters, admins).',
      classes(), pages=pages, perms=('true', 'true', 'true', 'true', 'true'))
write('Bandhu_Agent', 'Bandhu Agent', 'Assigned to the Bandhu Agentforce agent user: runs the Bandhu actions across customers.',
      classes(), perms=('true', 'true', 'false', 'true', 'false'), tabs=False,
      extra_objects=std('Lead', 'true', 'true', 'false') + std('Contact', 'false', 'true', 'false')
      + std('MessagingEndUser', 'false', 'false', 'false') + std('MessagingSession', 'false', 'false', 'false'))
write('Bandhu_Guest', 'Bandhu Guest', 'Public site guest: the Bandhu web journey page and its controller only (the controller runs without sharing behind a per-journey token).',
      ['BandhuWebController'], pages=pages, objects=False, tabs=False)
print('permsets generated')
