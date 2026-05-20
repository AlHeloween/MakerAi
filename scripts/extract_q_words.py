#!/usr/bin/env python3
"""Extract all unique ?-containing words from comments in .pas files."""
import os, re

src = r'D:\zPython\MakerAi\Source'
words = set()
file_words = {}

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
        file_set = set()
        for line in content.split('\n'):
            stripped = line.strip()
            if not (stripped.startswith('//') or stripped.startswith('{') or stripped.startswith('(*')):
                continue
            lower = stripped.lower()
            if any(s in lower for s in ['mit license', 'copyright (c)', 'permission is', 'the software', 'warranty', 'furnished to', 'above copyright']):
                continue
            for w in re.findall(r'[a-z\?]{3,}', lower):
                if '?' in w:
                    words.add(w)
                    file_set.add(w)
        if file_set:
            file_words[os.path.relpath(fp, src)] = sorted(file_set)

for w in sorted(words):
    print(w)

print(f'\n=== {len(words)} unique ?-containing words ===')
print(f'\n=== By file ===')
for fp, ws in sorted(file_words.items()):
    print(f'{fp}: {", ".join(ws)}')
