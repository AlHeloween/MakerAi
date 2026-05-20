"""Check all EN docs for actual Spanish content (not false positives)."""
import docx, os, re

ROOT = r'D:\zPython\MakerAi\Docs\Version 3\EN'

# Find Spanish sentences (not just isolated words)
SPANISH_SENTENCE = [
    r'\b(?:Requisitos|previos|Tener instalado|Opcional|clonar el|el repositorio|en tu|tu sistema)\b',
    r'\b(?:documentación|manual de|guía de|instalación|configuración)\b',
    r'\b(?:No se puede|Se requiere|Se necesita|Debe tener|Es necesario)\b',
    r'\b(?:Esta es|Este es|Esto es|Aquí|Allí|Ahora|Luego|Después)\b',
]

def check_file(fp, label):
    if not os.path.exists(fp):
        return None
    try:
        doc = docx.Document(fp)
    except:
        return None
    all_text = []
    spanish_lines = []
    for p in doc.paragraphs:
        text = p.text.strip()
        if not text:
            continue
        all_text.append(text)
        for pat in SPANISH_SENTENCE:
            if re.search(pat, text, re.IGNORECASE):
                spanish_lines.append(text[:150])
                break
    # Also check tables
    for table in doc.tables:
        for row in table.rows:
            for cell in row.cells:
                text = cell.text.strip()
                if not text:
                    continue
                for pat in SPANISH_SENTENCE:
                    if re.search(pat, text, re.IGNORECASE):
                        spanish_lines.append(text[:150])
                        break
    if spanish_lines:
        print(f'\n[ES-LEAK] {label} ({len(spanish_lines)} segments)')
        for s in spanish_lines[:5]:
            print(f'  "{s[:120]}"')
        return 'leak'
    else:
        total = len(' '.join(all_text))
        first_words = ' '.join(all_text[:3])[:100] if all_text else '(empty)'
        print(f'[OK] {label} ({total} chars) — {first_words}')
        return 'ok'

# Walk all EN docs
results = {}
for root, dirs, files in os.walk(ROOT):
    for fn in sorted(files):
        if fn.startswith('~$'):
            continue
        fp = os.path.join(root, fn)
        ext = os.path.splitext(fn)[1].lower()
        if ext == '.docx':
            rel = os.path.relpath(fp, ROOT)
            results[rel] = check_file(fp, rel)
        elif ext == '.md':
            with open(fp, 'r', encoding='utf-8-sig') as f:
                text = f.read()
            total = len(text)
            leaks = 0
            for pat in SPANISH_SENTENCE:
                if re.search(pat, text, re.IGNORECASE):
                    leaks += 1
            if leaks:
                print(f'\n[ES-LEAK] {fn} ({leaks} patterns)')
            else:
                first = text[:100].replace('\n', ' ')
                print(f'[OK] {fn} ({total} chars) — {first}')

print(f'\n{"="*40}')
leaks = [k for k, v in results.items() if v == 'leak']
oks = [k for k, v in results.items() if v == 'ok']
print(f'Clean: {len(oks)}, Leaks: {len(leaks)}')
if leaks:
    print(f'Leaking files:')
    for l in leaks:
        print(f'  - {l}')
