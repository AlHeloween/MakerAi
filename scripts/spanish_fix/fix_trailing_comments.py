#!/usr/bin/env python3
"""
FINAL FINAL PASS: Fix ALL ? in comments, including trailing comments on code lines.
Processes the actual comment portion of lines (after //, inside {}, etc.)
"""

import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, 'Source')

# All known ?-words that need fixing (from analysis + manual additions)
WORD_MAP = {
    # Trailing comment words (missed by earlier scripts)
    'a?ade': 'adds',
    'ning?n': 'no',
    'Sobrescribe': 'Overwrites', 'sobrescribe': 'overwrites',
    'propiedades': 'properties',
    'existentes': 'existing',
    'nuevas': 'new',
    'existen': 'exist',
    'realiza': 'performs',
    'cambio': 'change',
    'elemento': 'element',
    'existente': 'existing',
    'ubicaci?n': 'location',
    'solo': 'only',
    
    # Remaining Spanish words in trailing comments
    'consultas': 'queries',
    'hibridas': 'hybrid',
    'iniciales': 'initial',
    'dentro': 'inside',
    'explicitos': 'explicit',
    'precisos': 'precise',
    'modelo': 'model',
    'Planificador de consultas': 'Query planner',
    'Un modelo para': 'A model for',
    'realizar consultas': 'perform queries',
    'al grafo': 'on the graph',
    'primero obtiene con embeddings los nodos iniciales': 'first gets initial nodes using embeddings',
    'luego busca dentro del grafo datos muy explicitos para obtener datos precisos del grafo': 'then searches within the graph for very explicit data to obtain precise graph results',
    'Solo': 'Only',
    'propiedades que no existen': 'properties that do not exist',
    'No realiza': 'Does not perform',
    'ning?n': 'any',
    'cambio en las propiedades del elemento existente': 'change on the existing element properties',
    'las propiedades existentes con las nuevas': 'existing properties with the new ones',
    
    # Additional common phrase fixes
    'se encarga de': 'is responsible for',
    'se encargar? de': 'will handle',
    'es due?o de': 'owns',
    'es due?a de': 'owns',
    'tomar? posesi?n de': 'will take ownership of',
    'no debemos': 'we must not',
    'lo a?adimos': 'we add it',
    'los incluimos': 'we include them',
    'lo m?s com?n': 'the most common',
    'lo construimos': 'we build it',
    'nos encargamos de': 'we handle',
    'nos aseguramos de': 'we ensure',
    'a?adimos una copia': 'we add a copy',
    'se encargar? de liberar': 'will free',
    'tomar? posesi?n': 'will take ownership',
    'no somos sus due?os': 'we are not the owners',
    'El due?o de': 'The owner of',
}

def has_comment(line):
    """Check if line has any form of comment."""
    return '//' in line or '{' in line or '(*' in line

def should_skip(line):
    lower = line.lower()
    return any(s in lower for s in [
        'mit license', 'copyright (c)', 'permission is granted', 
        'the software', 'without warranty', 'furnished to do so',
        'above copyright notice', 'all copies or substantial',
        'social networks:', 'name: gustavo', 'author:',
        'email:', 'telegram:', 'linkedin:', 'github:', 'youtube:',
    ])

def process_file(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8-sig') as f:
            content = f.read()
    except (UnicodeDecodeError, FileNotFoundError):
        try:
            with open(filepath, 'r', encoding='latin-1') as f:
                content = f.read()
        except:
            return 0
    
    lines = content.split('\n')
    changes = 0
    
    for i, line in enumerate(lines):
        if not has_comment(line):
            continue
        if should_skip(line):
            continue
        if '?' not in line and not any(w in line for w in ['Sobrescribe', 'propiedades', 'Solo', 'hibridas', 'consultas', 'dentro del', 'al grafo', 'luego busca']):
            continue
        
        original = line
        # Apply word replacements with word boundaries
        for word, replacement in WORD_MAP.items():
            if len(word) >= 2:
                try:
                    # Use \b word boundaries to avoid matching inside other words
                    pattern = re.compile(r'\b' + re.escape(word) + r'\b', re.IGNORECASE)
                    line = pattern.sub(replacement, line)
                except:
                    pass
        
        if line != original:
            lines[i] = line
            changes += 1
    
    if changes > 0:
        new_content = '\n'.join(lines)
        if new_content.startswith('\ufeff'):
            new_content = new_content[1:]
        with open(filepath, 'w', encoding='utf-8', newline='\n') as f:
            f.write('\ufeff' + new_content)
    
    return changes


def main():
    total_files = 0
    total_changes = 0
    
    for root, dirs, files in os.walk(SOURCE_DIR):
        dirs[:] = [d for d in dirs if d not in ('Packages', 'Resources', 'hpp')]
        for filename in sorted(files):
            if not filename.endswith('.pas'):
                continue
            filepath = os.path.join(root, filename)
            changes = process_file(filepath)
            if changes > 0:
                relpath = os.path.relpath(filepath, SOURCE_DIR)
                print(f'  {relpath}: {changes} fixes')
                total_files += 1
                total_changes += changes
    
    print(f'\n{total_changes} fixes in {total_files} files')


if __name__ == '__main__':
    main()
