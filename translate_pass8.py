import os
import re

source_dir = r"D:\zPython\MakerAi\Source"

# Pass 8 - last remaining line
translations = [
    ('Detect escape para la siguiente iteración (ej: \\\\")',
     'Detect escape for next iteration (e.g. \\\\")'),
    ('Detect escape para la siguiente iteración (ej: \\")',
     'Detect escape for next iteration (e.g. \\")'),
]

def translate_comment(line):
    result = line
    for spanish, english in translations:
        if spanish in result:
            result = result.replace(spanish, english)
    return result

modified_count = 0
translated_lines = 0
modified_files = []

for root, dirs, files in os.walk(source_dir):
    for fname in files:
        if not fname.endswith('.pas'):
            continue
        filepath = os.path.join(root, fname)
        try:
            with open(filepath, 'r', encoding='utf-8-sig') as f:
                content = f.read()
        except:
            continue

        original = content
        lines = content.split('\n')
        new_lines = []
        file_changed = False
        file_translated = 0

        for line in lines:
            if '//' in line and re.search(r'[áéíóúüñÁÉÍÓÚÜÑ]', line):
                new_line = translate_comment(line)
                if new_line != line:
                    file_translated += 1
                    file_changed = True
                new_lines.append(new_line)
            else:
                new_lines.append(line)

        if file_changed:
            new_content = '\n'.join(new_lines)
            if '\r\n' in original:
                new_content = new_content.replace('\n', '\r\n')
            with open(filepath, 'w', encoding='utf-8', newline='') as f:
                f.write(new_content)
            modified_count += 1
            translated_lines += file_translated
            modified_files.append(os.path.relpath(filepath, source_dir))

print(f"=== Translation Summary (Pass 8) ===")
print(f"Files modified: {modified_count}")
print(f"Comment lines translated: {translated_lines}")
print()
print("Files changed:")
for f in sorted(modified_files):
    print(f"  {f}")
