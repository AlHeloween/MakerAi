#!/usr/bin/env python3
"""Find ALL remaining ? in comments more aggressively."""
import os, re

src = r'D:\zPython\MakerAi\Source'
missing = set()
examples = []

for root, dirs, files in os.walk(src):
    dirs[:] = [d for d in dirs if d not in ('Packages','Resources','hpp')]
    for fn in files:
        if not fn.endswith('.pas'):
            continue
        fp = os.path.join(root, fn)
        try:
            with open(fp, 'r', encoding='utf-8-sig') as f:
                content = f.read()
        except:
            try:
                with open(fp, 'r', encoding='latin-1') as f:
                    content = f.read()
            except:
                continue
        for i, line in enumerate(content.split('\n')):
            stripped = line.strip()
            if not (stripped.startswith('//') or stripped.startswith('{') or stripped.startswith('(*')):
                continue
            lower = stripped.lower()
            if any(s in lower for s in ['mit license','copyright','permission is','the software','warranty','furnished to','above copyright']):
                continue
            if '?' not in stripped:
                continue
            # Find all words with ?
            for w in re.findall(r'[a-zA-Z\?]{3,}', stripped):
                if '?' in w:
                    wl = w.lower()
                    if wl not in missing:
                        missing.add(wl)
                        if len(examples) < 50:
                            rel = os.path.relpath(fp, src)
                            examples.append(f'{rel}:L{i+1}: "{w}"')

for w in sorted(missing):
    print(w)
print(f'\n{len(missing)} unique ?-words')
print('\nFirst examples:')
for ex in examples[:30]:
    print(f'  {ex}')
