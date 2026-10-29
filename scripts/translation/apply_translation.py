"""Apply a machine-translated Delphi file: strip fences, verify code skeleton, overwrite original.

Usage: python scripts/translation/apply_translation.py <original.pas> <translated.txt>
Exit 0 applied, 1 skeleton mismatch, 2 error.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'audit'))
from check_edit_skeleton import skeleton  # noqa: E402


def clean(text):
    lines = text.split('\n')
    if lines and lines[0].strip().startswith('```'):
        lines = lines[1:]
    if lines and lines[0].strip().startswith('--- BEGIN FILE'):
        lines = lines[1:]
    while lines and lines[0].strip().strip('-=').strip() == '':
        lines = lines[1:]
    while lines and lines[-1].strip() == '':
        lines.pop()
    if lines and lines[-1].strip().startswith('```'):
        lines = lines[:-1]
        while lines and lines[-1].strip() == '':
            lines.pop()
    if lines and lines[-1].strip().startswith('--- END FILE'):
        lines = lines[:-1]
    while lines and lines[-1].strip().strip('-=').strip() == '':
        lines = lines[:-1]
    while lines and lines[-1].strip() == '':
        lines.pop()
    return '\n'.join(lines) + '\n'


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    orig, tr = sys.argv[1], sys.argv[2]
    raw = open(tr, 'rb').read()
    has_bom = raw.startswith(b'\xef\xbb\xbf')
    text = raw.decode('utf-8-sig', errors='replace')
    text = clean(text)
    with open(tr, 'w', encoding='utf-8', newline='') as fh:
        fh.write(text)
    a, b = skeleton(orig), skeleton(tr)
    if a is None or b is None:
        print(f'!! cannot read: {orig if a is None else tr}')
        return 2
    if a != b:
        for i, (x, y) in enumerate(zip(a, b)):
            if x != y:
                print(f'SKELETON-DIFF at normalized line {i + 1}:\n  orig: {x[:150]}\n  new : {y[:150]}')
                break
        else:
            print(f'SKELETON-DIFF line count {len(a)} vs {len(b)}')
        return 1
    orig_raw = open(orig, 'rb').read()
    orig_bom = orig_raw.startswith(b'\xef\xbb\xbf')
    crlf = b'\r\n' in orig_raw
    out = text.replace('\r\n', '\n')
    if crlf:
        out = out.replace('\n', '\r\n')
    data = out.encode('utf-8')
    if orig_bom:
        data = b'\xef\xbb\xbf' + data
    with open(orig, 'wb') as fh:
        fh.write(data)
    print(f'APPLIED  {orig}  ({len(a)} code lines verified, bom={orig_bom}, crlf={crlf})')
    return 0


if __name__ == '__main__':
    sys.exit(main())
