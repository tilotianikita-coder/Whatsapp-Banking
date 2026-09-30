"""Runs an anonymous Apex file and prints compile/runtime errors plus '###' debug lines.
Usage: python3 scripts/runapex.py scripts/apex/smoke.apex"""
import json, re, subprocess, sys
out = subprocess.run(['sf', 'apex', 'run', '-f', sys.argv[1], '-o', 'kotak-demo', '--json'], capture_output=True, text=True).stdout
raw = json.loads(out[out.index('{'):])
d = raw.get('result') or raw.get('data') or {}
if raw.get('message') and not raw.get('result'):
    print('ERROR', raw['message'])
for k in ('compileProblem', 'exceptionMessage', 'exceptionStackTrace'):
    if d.get(k):
        print(k.upper(), d[k])
for m in re.findall(r'USER_DEBUG\|\[\d+\]\|DEBUG\|(### .*?)(?=\n\d\d:\d\d:\d\d|\Z)', d.get('logs', ''), re.S):
    print(m.strip()); print('---')
