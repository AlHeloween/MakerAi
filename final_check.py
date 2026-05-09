import os, re

source_dir = r"D:\zPython\MakerAi\Source"
pas_files = []
for root, dirs, files in os.walk(source_dir):
    for f in files:
        if f.endswith('.pas'):
            pas_files.append(os.path.join(root, f))

spanish_pattern = re.compile(r'[áéíóúüñÁÉÍÓÚÜÑ¿¡]')
remaining = 0
for filepath in pas_files:
    try:
        with open(filepath, 'r', encoding='utf-8-sig') as f:
            content = f.read()
    except:
        continue
    for line in content.split('\n'):
        if '//' in line and spanish_pattern.search(line):
            stripped = line.strip()
            if stripped.startswith('// Author:') or stripped.startswith('// Name:'):
                continue
            if '%C3%A9' in line or '%EF%BD' in line:
                continue
            remaining += 1
            relpath = os.path.relpath(filepath, source_dir)
            lineno = content[:content.index(line)].count('\n') + 1
            print(f'{relpath}:{lineno} | {line.strip()}')

print(f'\nRemaining non-author Spanish comment lines: {remaining}')
