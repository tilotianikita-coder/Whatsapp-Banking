"""Runs every scenario in scripts/apex/options_check.apex against kotak-demo (each rolled back).
Usage: python3 scripts/options_check.py [scenario ...]"""
import re, subprocess, sys
src = open('scripts/apex/options_check.apex').read()
names = sys.argv[1:] or re.findall(r"'(\w+)'\s*=>", src)
for n in names:
    path = f'/tmp/options_{n}.apex'
    open(path, 'w').write(src.replace("'SCENARIO'", f"'{n}'"))
    print(subprocess.run(['python3', 'scripts/runapex.py', path], capture_output=True, text=True).stdout)
