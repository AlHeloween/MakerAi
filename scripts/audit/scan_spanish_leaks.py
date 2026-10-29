#!/usr/bin/env python3
"""Scan Delphi sources for leftover Spanish text: comment text (full-line AND trailing)
and user-facing string literals.

Usage:
    python scripts/audit/scan_spanish_leaks.py [root ...]

Default roots: Source. Exit code 1 when leaks are found, 0 when clean.
Protocol/API-ish single-token strings (JSON keys, model names, paths) are NOT reported -
they must not be translated.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from find_spanish_comments import SPANISH_WORDS  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

STRING_RE = re.compile(r"'((?:[^']|'')*)'")
# Single-token protocol-ish strings: lowercase words joined by _ - . / : (e.g. json keys, urls)
PROTOCOLISH = re.compile(r"^[a-z0-9_\-\./:@#%+~]*$")


ESCAPE_RE = re.compile(r'#(\$[0-9A-Fa-f]+|[0-9]+)')
NO_ACCENT = str.maketrans('áéíóúñüÁÉÍÓÚÑÜ', 'aeiounuAEIOUNU')
# An accent escape can only ever render an accented letter. English needs none, so its
# presence in a .pas/.dfm/.fmx file is by itself proof of non-English text — a signal with
# no false positives on a word list that happens to lack a given Spanish word.
ACCENT_ESCAPE = re.compile(r'#(?:225|233|237|243|250|241|252|191|161)')
ACCENT_CHARS = set('áéíóúñüÁÉÍÓÚÑÜ¿¡')


def visible_text(line):
    """The text a user would SEE on this line: quoted fragments joined, `#NNN` rendered.

    A Spanish message is often split by an escape (`'Escriba un texto de b' + #250 +
    'squeda.'`). Judged fragment by fragment neither piece looks Spanish, so the line
    escaped detection while the user saw Spanish. The expression is one text.
    """
    out = []
    i, n = 0, len(line)
    while i < n:
        c = line[i]
        if c == "'":
            i += 1
            while i < n:
                if line[i] == "'":
                    if i + 1 < n and line[i + 1] == "'":
                        out.append("'")
                        i += 2
                        continue
                    i += 1
                    break
                out.append(line[i])
                i += 1
            continue
        m = ESCAPE_RE.match(line, i)
        if m:
            tok = m.group(1)
            try:
                code = int(tok[1:], 16) if tok.startswith('$') else int(tok)
            except ValueError:
                code = 0
            if 32 <= code <= 0x2FFF:
                out.append(chr(code))
            i = m.end()
            continue
        i += 1
    return ''.join(out)


def has_spanish_text(text):
    """has_spanish for visible text: accents stripped so an accented word matches its
    unaccented entry in the word list."""
    return has_spanish(text) or has_spanish(text.translate(NO_ACCENT))

def has_spanish(text):
    lower = text.lower()
    for w in SPANISH_WORDS:
        pat = w.strip()
        if not pat:
            continue
        try:
            if re.search(r'(?<![a-z\u00e1\u00e9\u00ed\u00f3\u00fa\u00f1])' + pat + r'(?![a-z\u00e1\u00e9\u00ed\u00f3\u00fa\u00f1])', lower):
                return True
        except re.error:
            if pat in lower:
                return True
    return False


def strip_strings(line):
    return STRING_RE.sub("''", line)


def analyze(path):
    comment_hits, string_hits = [], []
    try:
        content = open(path, "r", encoding="utf-8-sig").read()
    except (UnicodeDecodeError, FileNotFoundError):
        return None
    for i, raw in enumerate(content.split("\n"), 1):
        stripped = raw.lstrip()
        if stripped.startswith("//") or stripped.startswith("(*"):
            if has_spanish(stripped):
                comment_hits.append((i, stripped[:110]))
            continue
        if stripped.startswith("{"):
            if stripped.startswith("{$"):
                # compiler directive; region labels are still translatable text
                if "region" in stripped[:12].lower() and has_spanish(stripped):
                    comment_hits.append((i, stripped[:110]))
            elif has_spanish(stripped):
                comment_hits.append((i, stripped[:110]))
            continue
        code_only = strip_strings(raw)
        j = code_only.find("//")
        if j >= 0:
            tail = raw[j:]
            if has_spanish(tail) or any(ch in ACCENT_CHARS for ch in tail):
                comment_hits.append((i, tail[:110]))
        # The fragments of ONE string expression are judged together — see visible_text.
        # An accent ESCAPE is a hit on its own: English text never needs one.
        visible = visible_text(raw)
        accent = ACCENT_ESCAPE.search(raw) is not None or any(ch in ACCENT_CHARS for ch in visible)
        if accent or (len(visible) >= 7 and not PROTOCOLISH.match(visible)):
            if accent or has_spanish_text(visible):
                string_hits.append((i, (visible[:110] or raw.strip()[:110])))
    return comment_hits, string_hits


def main():
    roots = sys.argv[1:] or ["Source"]
    total_c = total_s = files_c = files_s = 0
    for root in roots:
        base = os.path.join(ROOT, root)
        if not os.path.isdir(base):
            print(f"!! root not found: {base}")
            return 2
        for dirpath, dirs, files in os.walk(base):
            dirs[:] = [d for d in dirs if d not in ("Packages", "Resources", "hpp", "__history")]
            for fn in sorted(files):
                if not fn.endswith(".pas"):
                    continue
                fp = os.path.join(dirpath, fn)
                r = analyze(fp)
                if r is None:
                    continue
                c, s = r
                if not c and not s:
                    continue
                rel = os.path.relpath(fp, ROOT)
                print(f"\n== {rel} (comments {len(c)}, strings {len(s)}) ==")
                for ln, t in c:
                    print(f"  C{ln}: {t}")
                for ln, t in s:
                    print(f"  S{ln}: {t}")
                total_c += len(c)
                total_s += len(s)
                files_c += 1 if c else 0
                files_s += 1 if s else 0
    print(f"\n\nTOTAL: {total_c} Spanish comment hits ({files_c} files), "
          f"{total_s} Spanish string hits ({files_s} files)")
    return 1 if (total_c or total_s) else 0


if __name__ == "__main__":
    sys.exit(main())
