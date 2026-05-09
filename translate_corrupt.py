import os

source_dir = r"D:\zPython\MakerAi\Source"

translations = [
    ('// aqui lleva el Prompt Inicial + la conversi?n de los MediaFiles a texto si el usuario lo permite',
     '// here goes the Initial Prompt + conversion of MediaFiles to text if the user allows'),
]

modified_count = 0
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

        text = content.decode('utf-8', errors='replace')
        changed = False

        for spanish, english in translations:
            if spanish in text:
                text = text.replace(spanish, english)
                changed = True

        if changed:
            new_content = text.encode('utf-8')
            new_content = new_content.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
            with open(filepath, 'wb') as f:
                f.write(new_content)
            modified_count += 1

print(f"Files modified: {modified_count}")
