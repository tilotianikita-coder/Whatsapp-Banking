#!/bin/bash
# Deploy a path and print a compact result. Usage: scripts/deploy.sh <path> [extra sf flags]
P=${1:-force-app}; shift
sf project deploy start -d "$P" -o kotak-demo --wait 30 --json "$@" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin); r=d.get('result',{}) or {}
print(r.get('status'), d.get('message','') if r.get('status')!='Succeeded' else '', 'components:', r.get('numberComponentsDeployed'))
det=r.get('details',{}) or {}
fs=det.get('componentFailures',[])
if isinstance(fs,dict): fs=[fs]
for f in fs: print('  FAIL', f.get('componentType'), f.get('fullName'), f.get('lineNumber'), (f.get('problem') or '')[:300])
rt=det.get('runTestResult',{}) or {}
tf=rt.get('failures',[])
if isinstance(tf,dict): tf=[tf]
for t in tf: print('  TESTFAIL', t.get('name'), t.get('methodName'), (t.get('message') or '')[:300], (t.get('stackTrace') or '')[:200])
if rt: print('  tests run:', rt.get('numTestsRun'), 'failures:', rt.get('numFailures'))
"
