#!/usr/bin/env python3
"""Verify that an edit changed ONLY comments and string literals.

Usage: python scripts/audit/check_edit_skeleton.py <original.pas> <edited.pas>
Exit 0 = code skeleton identical (only comment/string text changed).
Exit 1 = divergence, prints the first differing normalized line.
Compiler directives ({$...}, (*$...*)) are treated as CODE and compared.
"""
import sys

def escape_end(text, i):
    """End index of a `#NNN` / `#$HH` Pascal character escape starting at i, or None."""
    n = len(text)
    if i >= n or text[i] != "#":
        return None
    j = i + 1
    if j < n and text[j] == "$":
        start = j + 1
        j = start
        while j < n and text[j] in "0123456789abcdefABCDEF":
            j += 1
        return j if j > start else None
    start = j
    while j < n and text[j].isdigit():
        j += 1
    return j if j > start else None


def string_expr_end(text, i):
    """End index of one string expression: quoted parts and char escapes joined by `+`.

    A `#NNN` between quoted parts is string DATA, not code, so `'jer' + #225 + 'rquico'`
    and a literal carrying the same accented letter normalize to the same unit. The
    expression never crosses a line break, so the trailing `+` of a multi-line
    concatenation stays CODE and a merge of two lines still shows up as a line-count
    difference.
    """
    n = len(text)
    while True:
        if i < n and text[i] == "'":
            i += 1
            while i < n:
                if text[i] == "'":
                    if i + 1 < n and text[i + 1] == "'":
                        i += 2
                        continue
                    i += 1
                    break
                i += 1
        else:
            end = escape_end(text, i)
            if end is None:
                return i
            i = end
        k = i
        while k < n and text[k] in " \t":
            k += 1
        if k < n and text[k] == "+":
            m = k + 1
            while m < n and text[m] in " \t":
                m += 1
            if m < n and (text[m] == "'" or escape_end(text, m) is not None):
                i = m
                continue
            return i
        # Adjacent parts need no `+`: Pascal glues `'s'#237'ntesis'` into one value.
        if k < n and (text[k] == "'" or escape_end(text, k) is not None):
            i = k
            continue
        return i
def strip_comments_strings(text):
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "'":  # string expression: literals and #NNN escapes joined by +
            out.append(" '<S>' ")
            i = string_expr_end(text, i)
            continue
        if c == "#" and escape_end(text, i) is not None:  # expression starting at an escape
            out.append(" '<S>' ")
            i = string_expr_end(text, i)
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            out.append(" ")
            i = n if j < 0 else j
            continue
        if c == "{":
            j = text.find("}", i)
            if j < 0:
                i = n
                continue
            inner = text[i + 1:j]
            if inner.startswith("$"):  # compiler directive = code (region labels normalized)
                low = inner.lower()
                if low.startswith("$region") or low.startswith("$endregion"):
                    out.append("{<REGION>}")
                else:
                    out.append(text[i:j + 1])
            else:
                out.append(" ")
            i = j + 1
            continue
        if c == "(" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*)", i)
            if j < 0:
                i = n
                continue
            inner = text[i + 2:j]
            if inner.startswith("$"):
                low = inner.lower()
                if low.startswith("$region") or low.startswith("$endregion"):
                    out.append("{<REGION>}")
                else:
                    out.append(text[i:j + 2])
            else:
                out.append(" ")
            i = j + 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def skeleton(path):
    try:
        text = open(path, "r", encoding="utf-8-sig", errors="replace").read()
    except FileNotFoundError:
        return None
    body = strip_comments_strings(text)
    lines = [" ".join(ln.split()) for ln in body.split("\n")]
    # Delphi/Pascal is case-insensitive: keyword and identifier case changes are not code changes.
    return [ln.lower() for ln in lines if ln]


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    a, b = skeleton(sys.argv[1]), skeleton(sys.argv[2])
    if a is None or b is None:
        print(f"!! missing file: {sys.argv[1] if a is None else sys.argv[2]}")
        return 2
    if a == b:
        print(f"SKELETON-OK  {len(a)} code line(s) identical")
        return 0
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            print(f"SKELETON-DIFF at normalized line {i + 1}:\n  A: {x[:160]}\n  B: {y[:160]}")
            break
    else:
        print(f"SKELETON-DIFF: line count {len(a)} vs {len(b)}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
