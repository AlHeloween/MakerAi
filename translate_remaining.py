import os

source_dir = r"D:\zPython\MakerAi\Source"

# Only specific full-line Spanish comments without accented chars
translations = [
    ('// Guarda las transcripciones en los MediaFile,  luego construye la respuesta definitiva con todos los mediafiles',
     '// Saves transcriptions in MediaFile, then builds the definitive response with all mediafiles'),
]

modified_count = 0
translated_lines = 0
modified_files = []

for root, dirs, files in os.walk(source_dir):
    for fname in files:
        if not fname.endswith('.pas'):
            continue
        filepath = os.path.join(root, fname)
        try:
            with open(filepath, 'rb') as f:
                content = f.read()
        except:
            continue

        original = content
        text = content.decode('utf-8', errors='replace')
        changed = False
        count = 0

        for spanish, english in translations:
            if spanish in text:
                text = text.replace(spanish, english)
                changed = True
                count += 1

        if changed:
            new_content = text.encode('utf-8')
            new_content = new_content.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
            with open(filepath, 'wb') as f:
                f.write(new_content)
            modified_count += 1
            translated_lines += count
            modified_files.append(os.path.relpath(filepath, source_dir))

print(f"Files modified: {modified_count}")
print(f"Lines translated: {translated_lines}")
for f in sorted(modified_files):
    print(f"  {f}")
