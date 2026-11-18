"""Sucht alle benutzersichtbaren Texte im Code: SwiftUI-Texte (LocalizedStringKey) und String(localized:)."""
import glob
import json
import re
import sys
lit=r'"((?:[^"\\]|\\.)*)"'
call=re.compile(r'\b(?:Text|Button|Label|Toggle|Picker|Section|NavigationLink|TextField|SecureField|LabeledContent|Menu|Tab)\(\s*'+lit)
mod=re.compile(r'\.(?:navigationTitle|accessibilityLabel|accessibilityHint|alert|confirmationDialog|searchable)\(\s*(?:text:[^,]+,\s*prompt:\s*)?'+lit)
prompt=re.compile(r'prompt:\s*'+lit)
loc=re.compile(r'String\(localized:\s*'+lit)
lsk=re.compile(r'LocalizedStringKey\(([^\n]*)\)')
anylit=re.compile(lit)
def extract():
    keys={}
    for f in glob.glob('Packages/*/Sources/**/*.swift', recursive=True):
        s=open(f).read()
        for p in (call,mod,prompt,loc):
            for m in p.finditer(s):
                keys.setdefault(m.group(1),set()).add(f.split('/')[-1])
        for m in lsk.finditer(s):
            for l in anylit.finditer(m.group(1)):
                keys.setdefault(l.group(1),set()).add(f.split('/')[-1])
    return keys
if __name__=='__main__':
    keys=extract()
    ignore=lambda k: k=='' or re.fullmatch(r'[a-z0-9._\-]+',k) or k.startswith('%') or k in ('–',)
    ks=sorted(k for k in keys if not ignore(k))
    print(len(ks))
    for k in ks:
        if '\\(' in k: print('I:',k)
