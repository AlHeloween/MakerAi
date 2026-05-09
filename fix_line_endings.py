import os

source_dir = r"D:\zPython\MakerAi\Source"

for root, dirs, files in os.walk(source_dir):
    for fname in files:
        if not fname.endswith('.pas'):
            continue
        filepath = os.path.join(root, fname)
        try:
            with open(filepath, 'rb') as f:
                content = f.read()
            # Convert standalone LF to CRLF (but don't double up existing CRLF)
            content = content.replace(b'\r\n', b'\n')  # normalize to LF first
            content = content.replace(b'\n', b'\r\n')  # then convert all to CRLF
            with open(filepath, 'wb') as f:
                f.write(content)
        except Exception as e:
            print(f"Error: {filepath}: {e}")

print("Done - all .pas files converted to CRLF")
