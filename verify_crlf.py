import os

source_dir = r"D:\zPython\MakerAi\Source"
ok = True
for root, dirs, files in os.walk(source_dir):
    for f in files:
        if not f.endswith('.pas'):
            continue
        fp = os.path.join(root, f)
        with open(fp, 'rb') as fh:
            content = fh.read()
        normalized = content.replace(b'\r\n', b'')
        if b'\n' in normalized:
            print(f'LF only: {f}')
            ok = False
        if b'\r\r\n' in content:
            print(f'Double CR: {f}')
            ok = False
if ok:
    print('All .pas files have correct CRLF line endings')
