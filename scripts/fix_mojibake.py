#!/usr/bin/env python3
"""
Fix mojibake patterns in Delphi .pas files.
The `?` character appears where accented characters should be.
This is NOT a true mojibake (bytes->chars), but actual `?` literals that
should be accented Spanish characters. Replace based on context.
"""

import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, 'Source')

# Map of ?n patterns to their likely correct forms
# These match specific known Spanish words with accented characters
MOJIBAKE_FIXES = [
    # -ión endings (very common: expresión, conexión, etc.)
    (r'\b([Ee]xpresi)o(\?n)\b', r'\1ón'),          # expresión
    (r'\b([Cc]onexi)o(\?n)\b', r'\1ón'),           # conexión
    (r'\b([Cc]olecci)o(\?n)\b', r'\1ón'),           # colección
    (r'\b([Cc]onfiguraci)o(\?n)\b', r'\1ón'),       # configuración
    (r'\b([Ss]elecci)o(\?n)\b', r'\1ón'),           # selección
    (r'\b([Pp]osici)o(\?n)\b', r'\1ón'),           # posición
    (r'\b([Oo]peraci)o(\?n)\b', r'\1ón'),           # operación
    (r'\b([Ii]nstrucci)o(\?n)\b', r'\1ón'),         # instrucción
    (r'\b([Dd]efinici)o(\?n)\b', r'\1ón'),          # definición
    (r'\b([Dd]escripci)o(\?n)\b', r'\1ón'),         # descripción
    (r'\b([Gg]eneraci)o(\?n)\b', r'\1ón'),          # generación
    (r'\b([Ii]nformaci)o(\?n)\b', r'\1ón'),          # información
    (r'\b([Rr]elaci)o(\?n)\b', r'\1ón'),            # relación
    (r'\b([Cc]omparaci)o(\?n)\b', r'\1ón'),          # comparación
    (r'\b([Cc]ancelaci)o(\?n)\b', r'\1ón'),          # cancelación
    (r'\b([Pp]resentaci)o(\?n)\b', r'\1ón'),         # presentación
    (r'\b([Pp]ublicaci)o(\?n)\b', r'\1ón'),          # publicación
    (r'\b([Ee]valuaci)o(\?n)\b', r'\1ón'),           # evaluación
    (r'\b([Ii]nterpretaci)o(\?n)\b', r'\1ón'),        # interpretación
    (r'\b([Cc]lasificaci)o(\?n)\b', r'\1ón'),         # clasificación
    (r'\b([Tt]ransformaci)o(\?n)\b', r'\1ón'),        # transformación
    (r'\b([Cc]omunicaci)o(\?n)\b', r'\1ón'),           # comunicación
    (r'\b([Vv]alidaci)o(\?n)\b', r'\1ón'),           # validación
    (r'\b([Ii]nstalaci)o(\?n)\b', r'\1ón'),          # instalación
    (r'\b([Cc]ompilaci)o(\?n)\b', r'\1ón'),           # compilación
    (r'\b([Ee]jecuci)o(\?n)\b', r'\1ón'),            # ejecución
    (r'\b([Ss]incronizaci)o(\?n)\b', r'\1ón'),        # sincronización
    (r'\b([Tt]raducci)o(\?n)\b', r'\1ón'),           # traducción
    (r'\b([Ii]mportaci)o(\?n)\b', r'\1ón'),          # importación
    (r'\b([Ee]xportaci)o(\?n)\b', r'\1ón'),          # exportación
    (r'\b([Aa]signaci)o(\?n)\b', r'\1ón'),           # asignación
    (r'\b([Dd]uplicaci)o(\?n)\b', r'\1ón'),          # duplicación
    (r'\b([Cc]reaci)o(\?n)\b', r'\1ón'),             # creación
    (r'\b([Aa]ctualizaci)o(\?n)\b', r'\1ón'),         # actualización
    (r'\b([Rr]ecuperaci)o(\?n)\b', r'\1ón'),          # recuperación
    (r'\b([Dd]etec)ión(\?n)\b', r'\1ción'),           # detección
    (r'\b([Ss]oluci)o(\?n)\b', r'\1ón'),             # solución
    (r'\b([Cc]ondici)o(\?n)\b', r'\1ón'),            # condición
    (r'\b([Oo]pci)o(\?n)\b', r'\1ón'),              # opción
    # Indices/issues
    (r'\b([Íí])ndice\b', 'índice'),  # won't match but pattern for later
    # añadir pattern
    (r'([Aa])(\?)adir\b', r'\1ñadir'),              # añadir/a?adir
    # ningún/ninguna
    (r'([Nn])ing(\?)n\b', r'\1ingún'),             # ningún
    # código
    (r'([Cc])o(\?)digo\b', r'\1ódigo'),            # código
    # número
    (r'([Nn])u(\?)mero\b', r'\1úmero'),            # número
    # sólo
    (r'([Ss])o(\?)lo\b', r'\1ólo'),                 # sólo (or solo - can be either)
    # área
    (r'([Áá])rea\b', 'área'),  # no change
    # éxito
    (r'([Eé])xito\b', r'éxito'),                    # é
    # después
    (r'([Dd])espu(\?)s\b', r'\1espués'),             # después
    # más
    (r'([Mm])(\?)s\b', r'\1ás'),                     # más
    # está
    (r'([Ee])st(\?)a(\b|[rs])', r'\1stá\3'),         # está/estás/están
    # sólo (also solo variant)
    (r'([Ss])o(\?)lo\b', r'\1olo'),                  # simple solo
    # Final ? cleanup in specific contexts
    (r'\b([Cc])(\?)mo\b', r'\1ómo'),               # cómo
    (r'\b([Cc]u)(\?)l\b', r'\1uál'),               # cuál
    (r'\b([Cc]u)(\?)ndo\b', r'\1uándo'),           # cuándo
    (r'\b([Dd])(\?)nde\b', r'\1ónde'),             # dónde
    (r'\b([Qq])ui(\?)n\b', r'\1uién'),             # quién
    # last resort: if ? appears between letters, try to guess
]

def process_file(filepath):
    """Fix mojibake in a single file."""
    try:
        with open(filepath, 'r', encoding='utf-8-sig') as f:
            content = f.read()
    except UnicodeDecodeError:
        with open(filepath, 'r', encoding='latin-1') as f:
            content = f.read()
    
    original = content
    for pattern, replacement in MOJIBAKE_FIXES:
        content = re.sub(pattern, replacement, content)
    
    if content != original:
        # Count changes
        changes = 0
        for line_orig, line_new in zip(original.split('\n'), content.split('\n')):
            if line_orig != line_new:
                changes += 1
        
        # Write without BOM then re-add
        if content.startswith('\ufeff'):
            content = content[1:]
        with open(filepath, 'w', encoding='utf-8', newline='\n') as f:
            f.write('\ufeff' + content)
        
        return changes
    return 0


def main():
    total_files = 0
    total_changes = 0
    
    for root, dirs, files in os.walk(SOURCE_DIR):
        dirs[:] = [d for d in dirs if d not in ('Packages', 'Resources', 'hpp')]
        for filename in files:
            if not filename.endswith('.pas'):
                continue
            filepath = os.path.join(root, filename)
            changes = process_file(filepath)
            if changes > 0:
                relpath = os.path.relpath(filepath, SOURCE_DIR)
                print(f'  {relpath}: {changes} mojibake fixes')
                total_files += 1
                total_changes += changes
    
    print(f'\nTotal: {total_changes} mojibake fixes in {total_files} files')


if __name__ == '__main__':
    main()
