import os
import re
import sys

source_dir = r"D:\zPython\MakerAi\Source"

# Find all .pas files
pas_files = []
for root, dirs, files in os.walk(source_dir):
    for f in files:
        if f.endswith('.pas'):
            pas_files.append(os.path.join(root, f))

# Spanish accented characters pattern
spanish_pattern = re.compile(r'[áéíóúüñÁÉÍÓÚÜÑ¿¡]')

results = []
for filepath in pas_files:
    try:
        with open(filepath, 'r', encoding='utf-8-sig') as f:
            lines = f.readlines()
    except:
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                lines = f.readlines()
        except:
            continue
    
    relpath = os.path.relpath(filepath, source_dir)
    for i, line in enumerate(lines, 1):
        if '//' in line and spanish_pattern.search(line):
            results.append(f"{relpath}:{i} | {line.rstrip()}")

print(f"Total Spanish comment lines found: {len(results)}")
for r in sorted(set(results)):
    print(r)
