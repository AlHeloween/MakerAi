#!/usr/bin/env python3
"""Scan Markdown files for leftover Spanish (accented chars or Spanish word hits).

Usage: python scripts/audit/scan_spanish_md.py [root ...]
Default root: . (repo), skipping Demos*/Apps/archives. Exit 1 when leaks found.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from find_spanish_comments import SPANISH_WORDS  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ACCENT = re.compile(r"[áéíóúüñ¿¡ÁÉÍÓÚÜÑ]")
SKIP_DIRS = {"Demos", "Demos-V3_1", "Demos-V3_4", "Demos-Book", "Apps", ".git",
             "logs", "__history", "node_modules", ".codegraph", "tool-output"}


def spanish_line(line):
    if ACCENT.search(line):
        return True
    lower = line.lower()
    hits = sum(1 for w in SPANISH_WORDS if re.search(r"\b" + w.strip() + r"\b", lower))
    return hits >= 2


def main():
    roots = sys.argv[1:] or ["."]
    total = 0
    for root in roots:
        base = os.path.join(ROOT, root)
        for dirpath, dirs, files in os.walk(base):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for fn in sorted(files):
                if not fn.lower().endswith(".md"):
                    continue
                fp = os.path.join(dirpath, fn)
                try:
                    content = open(fp, "r", encoding="utf-8-sig").read()
                except (UnicodeDecodeError, FileNotFoundError):
                    continue
                hits = sum(1 for ln in content.split("\n") if spanish_line(ln))
                if hits:
                    rel = os.path.relpath(fp, ROOT)
                    print(f"{hits:6d}  {rel}")
                    total += hits
    print(f"\nTOTAL: {total} Spanish-ish lines in Markdown")
    return 1 if total else 0

if __name__ == "__main__":
    sys.exit(main())
