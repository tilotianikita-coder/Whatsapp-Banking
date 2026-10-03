"""Generates LoanSeva permission sets from the object/class metadata in force-app.
Run from the project root: python3 scripts/gen_permsets.py"""
import os, re

BASE = 'force-app/main/default'
OBJ = os.path.join(BASE, 'objects')
OUT = os.path.join(BASE, 'permissionsets')
CUSTOM_OBJECTS = ['Existing_Loan__c', 'Loan_Journey__c', 'Loan_Application__c', 'Journey_Feedback__c', 'Underwriting_Check__c', 'Loan_Document__c']


def fields(obj):
    result = []
    d = os.path.join(OBJ, obj, 'fields')
    for f in sorted(os.listdir(d)):
        xml = open(os.path.join(d, f)).read()
        name = f.replace('.field-meta.xml', '')
        required = '<required>true</required>' in xml or '<type>MasterDetail</type>' in xml
        formula = '<formula>' in xml
        if required:
            continue  # required fields are always accessible and cannot be listed
        result.append((name, not formula))
    return result


def classes(prefix='LoanSeva'):
    return sorted(f[:-4] for f in os.listdir(os.path.join(BASE, 'classes'))
                  if f.endswith('.cls') and f.startswith(prefix) and not f[:-4].endswith('Test'))


def permset(name, label, desc, obj_perms, field_edit=True, extra='', apps=(), principals=()):
    parts = [f'<?xml version="1.0" encoding="UTF-8"?>\n<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">\n'
             f'    <label>{label}</label>\n    <description>{desc}</description>\n    <hasActivationRequired>false</hasActivationRequired>\n']
    for app in apps:
        parts.append(f'    <applicationVisibilities>\n        <application>{app}</application>\n        <visible>true</visible>\n    </applicationVisibilities>\n')
    for c in classes():
        parts.append(f'    <classAccesses>\n        <apexClass>{c}</apexClass>\n        <enabled>true</enabled>\n    </classAccesses>\n')
    parts.append('    <customMetadataTypeAccesses>\n        <enabled>true</enabled>\n        <name>LoanSeva_Config__mdt</name>\n    </customMetadataTypeAccesses>\n'
                 '    <customMetadataTypeAccesses>\n        <enabled>true</enabled>\n        <name>LoanSeva_FAQ__mdt</name>\n    </customMetadataTypeAccesses>\n'
                 '    <customMetadataTypeAccesses>\n        <enabled>true</enabled>\n        <name>LoanSeva_Message__mdt</name>\n    </customMetadataTypeAccesses>\n')
    for principal in principals:
        parts.append(f'    <externalCredentialPrincipalAccesses>\n        <enabled>true</enabled>\n'
                     f'        <externalCredentialPrincipal>{principal}</externalCredentialPrincipal>\n    </externalCredentialPrincipalAccesses>\n')
    for obj in CUSTOM_OBJECTS:
        for fname, editable in fields(obj):
            parts.append(f'    <fieldPermissions>\n        <editable>{str(editable and field_edit).lower()}</editable>\n'
                         f'        <field>{obj}.{fname}</field>\n        <readable>true</readable>\n    </fieldPermissions>\n')
    for obj in CUSTOM_OBJECTS:
        p = obj_perms
        parts.append(f'    <objectPermissions>\n        <allowCreate>{p["c"]}</allowCreate>\n        <allowDelete>{p["d"]}</allowDelete>\n'
                     f'        <allowEdit>{p["e"]}</allowEdit>\n        <allowRead>true</allowRead>\n'
                     f'        <modifyAllRecords>{p["m"]}</modifyAllRecords>\n        <object>{obj}</object>\n'
                     f'        <viewAllRecords>{p["v"]}</viewAllRecords>\n    </objectPermissions>\n')
    parts.append(extra)  # extra object permissions follow the custom ones; tab settings come after all of them
    for obj in CUSTOM_OBJECTS:
        parts.append(f'    <tabSettings>\n        <tab>{obj}</tab>\n        <visibility>Visible</visibility>\n    </tabSettings>\n') if os.path.exists(os.path.join(BASE, 'tabs', obj + '.tab-meta.xml')) else None
    parts.append('</PermissionSet>\n')
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + '.permissionset-meta.xml'), 'w') as fh:
        fh.write(''.join(parts))


ALL = {'c': 'true', 'd': 'true', 'e': 'true', 'm': 'true', 'v': 'true'}
permset('LoanSeva_Admin', 'LoanSeva Admin', 'Full access to LoanSeva objects, fields and Apex (demo admins, RMs, running users).', ALL, apps=['LoanSeva_LOS'],
        principals=['LoanSeva_ElevenLabs-Default'])  # the voice-note subscriber runs as an admin
# Agent user: runs every action; needs to read/write journey data across customers.
def std(obj, c, e, v):
    return (f'    <objectPermissions>\n        <allowCreate>{c}</allowCreate>\n        <allowDelete>false</allowDelete>\n'
            f'        <allowEdit>{e}</allowEdit>\n        <allowRead>true</allowRead>\n        <modifyAllRecords>false</modifyAllRecords>\n'
            f'        <object>{obj}</object>\n        <viewAllRecords>{v}</viewAllRecords>\n    </objectPermissions>\n')


def uperm(name):
    return f'    <userPermissions>\n        <enabled>true</enabled>\n        <name>{name}</name>\n    </userPermissions>\n'


AGENT_EXTRA = (std('Contact', 'true', 'true', 'false')  # new-loan applicants become Contacts on submit
               + std('Lead', 'true', 'true', 'false') + std('Account', 'false', 'false', 'false')
)
permset('LoanSeva_Agent', 'LoanSeva Agent', 'Assigned to the LoanSeva Agentforce agent user: runs the LoanSeva actions across customers.',
        {'c': 'true', 'd': 'false', 'e': 'true', 'm': 'false', 'v': 'true'}, extra=AGENT_EXTRA)
print('permsets generated')
