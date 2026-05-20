#!/usr/bin/env python3
"""
Fix literal '?' characters that replaced accented Spanish characters.
Only processes comment lines (// and { } blocks).
The '?' appears in patterns like ?n, ?s, ?a which are clearly corruptions.
"""

import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, 'Source')

# These patterns have unambiguous fixes
KNOWN_FIXES = [
    # -ión words (most common)
    ('expresi?n', 'expression'), ('operaci?n', 'operation'),
    ('instrucci?n', 'instruction'), ('definici?n', 'definition'),
    ('informaci?n', 'information'), ('generaci?n', 'generation'),
    ('relaci?n', 'relation'), ('comparaci?n', 'comparison'),
    ('cancelaci?n', 'cancellation'), ('presentaci?n', 'presentation'),
    ('publicaci?n', 'publication'), ('evaluaci?n', 'evaluation'),
    ('interpretaci?n', 'interpretation'), ('clasificaci?n', 'classification'),
    ('transformaci?n', 'transformation'), ('comunicaci?n', 'communication'),
    ('soluci?n', 'solution'), ('opci?n', 'option'), ('condici?n', 'condition'),
    # Other -ión patterns
    ('colecci?n', 'collection'), ('selecci?n', 'selection'),
    ('posici?n', 'position'), ('descripci?n', 'description'),
    ('conexi?n', 'connection'), ('configuraci?n', 'configuration'),
    ('validaci?n', 'validation'), ('ejecuci?n', 'execution'),
    ('compilaci?n', 'compilation'), ('traducci?n', 'translation'),
    ('instalaci?n', 'installation'), ('recuperaci?n', 'retrieval'),
    ('sincronizaci?n', 'synchronization'), ('duplicaci?n', 'duplication'),
    ('creaci?n', 'creation'), ('actualizaci?n', 'update/actualization'),
    ('importaci?n', 'importation'), ('exportaci?n', 'exportation'),
    ('asignaci?n', 'assignment'), ('detecci?n', 'detection'),
    ('inicializaci?n', 'initialization'), 
    ('conversi?n', 'conversion'),
    ('expansi?n', 'expansion'), ('serializaci?n', 'serialization'),
    ('hidrataci?n', 'hydration'), ('gesti?n', 'management'),
    ('verificaci?n', 'verification'), ('identidad', 'identity'),
    ('reconstrucci?n', 'reconstruction'), ('optimizaci?n', 'optimization'),
    ('delegaci?n', 'delegation'), ('localizaci?n', 'localization'),
    ('destino', 'destination'), ('direcci?n', 'direction'),
    ('conversi?n', 'conversion'), ('reversi?n', 'reversion'),
    ('extensi?n', 'extension'), ('sustituci?n', 'substitution'),
    ('inyecci?n', 'injection'), ('sanitizaci?n', 'sanitization'),
    ('aprobaci?n', 'approval'),
    
    # -ción/ción
    ('funci?n', 'function'),
    ('dimensi?n', 'dimension'),
    ('secci?n', 'section'),
    ('cl?usula', 'clause'),
    ('versi?n', 'version'),
    
    # Single words
    ('a?adir', 'add'), ('a?adido', 'added'), ('a?adiendo', 'adding'),
    ('ning?n', 'no/not any'),
    ('c?digo', 'code'),
    ('n?mero', 'number'), ('n?meros', 'numbers'),
    ('despu?s', 'after'), ('despu\u00e9s', 'after'),  # if real char
    ('m?s', 'more'), ('m\u00e1s', 'more'),
    
    # está/están  
    ('est?', 'is'), ('est?n', 'are'), 
    
    # cómo/cuál/cuándo/dónde/quién
    ('c?mo', 'how'), ('cu?l', 'which'), ('cu?ndo', 'when'),
    ('d?nde', 'where'), ('qui?n', 'who'),
    
    # s?lo
    ('s?lo', 'only'),
    
    # Specific words
    ('patr?n', 'pattern'), ('patrones', 'patterns'),
    ('b?squeda', 'search'), ('b?squedas', 'searches'),
    ('l?gica', 'logic'), ('l?gico', 'logical'), ('l?gicos', 'logical'),
    ('h?brida', 'hybrid'), ('h?brido', 'hybrid'),
    ('sem?ntica', 'semantic'), ('sem?ntico', 'semantic'),
    ('gr?fico', 'graphic'),
    ('r?pida', 'fast/quick'), ('r?pido', 'fast/quick'),
    ('r?pidas', 'fast/quick'), ('r?pidos', 'fast/quick'),
    ('m?todo', 'method'), ('m?todos', 'methods'),
    ('m?trica', 'metric'), ('m?tricas', 'metrics'),
    ('est?ndar', 'standard'), ('est?ndares', 'standards'),
    ('cl?sica', 'classic'), ('cl?sico', 'classic'),
    ('espec?fica', 'specific'), ('espec?fico', 'specific'),
    ('gen?rica', 'generic'), ('gen?rico', 'generic'),
    ('b?sica', 'basic'), ('b?sico', 'basic'),
    ('m?xima', 'maximum'), ('m?ximo', 'maximum'),
    ('m?nima', 'minimum'), ('m?nimo', 'minimum'),
    ('pr?ximo', 'next/upcoming'),
    ('cr?tica', 'critical'), ('cr?tico', 'critical'),
    ('t?cnica', 'technical'), ('t?cnico', 'technical'),
    ('?ltima', 'last'), ('?ltimo', 'last'),
    ('?nica', 'unique/only'), ('?nico', 'unique/only'),
    ('?nica', 'unique'), ('?nicos', 'unique'),
    ('din?mica', 'dynamic'), ('din?mico', 'dynamic'),
    ('din?micas', 'dynamic'), ('din?micos', 'dynamic'),
    ('autom?tica', 'automatic'), ('autom?tico', 'automatic'),
    ('autom?ticamente', 'automatically'),
    ('est?tica', 'static'), ('est?tico', 'static'),
    ('externo', 'external'),
    ('?rea', 'area'), ('?reas', 'areas'),
    ('?ngulo', 'angle'), ('?ngulos', 'angles'),
    ('el?ctrica', 'electrical'),
    ('n?cleo', 'core/nucleus'),
    ('n?mero', 'number'),
    ('p?blica', 'public'), ('p?blico', 'public'),
    ('int?rprete', 'interpreter'),
    ('m?quina', 'machine'),
    ('?til', 'useful'),
    ('?tiles', 'useful'),
    
    # índices
    ('?ndice', 'index'), ('?ndices', 'indexes/indices'),
    
    # éxito
    ('?xito', 'success'),
    
    # excepción
    ('excepci?n', 'exception'), ('excepciones', 'exceptions'),
    
    # Other -dad 
    ('propiedad', 'property'), ('propiedades', 'properties'),
    ('cantidad', 'quantity'), ('cantidades', 'quantities'),
    
    # Other specific
    ('tambi?n', 'also'),
    ('despu?s', 'after'),
    ('m?s', 'more'),
    ('s?lo', 'only'),
    ('despu\u00e9s', 'after'),
    ('m\u00e1s', 'more'),
    ('s\u00f3lo', 'only'),
    
    # More patterns found in code
    ('Enr?quez', 'Enriquez'),
    ('Enr\u00edquez', 'Enriquez'),
    ('Enr?quez', 'Enriquez'),
    ('Enriquez', 'Enriquez'),  # already correct
    
    # Paragraph connectors
    ('aqu?', 'here'), ('all?', 'there'),
    ('ahora', 'now'), ('luego', 'then'),
    ('siempre', 'always'), ('nunca', 'never'),
    ('mientras', 'while'), ('durante', 'during'),
    ('entonces', 'then'), ('todav?a', 'still/yet'),
    ('quiz?s', 'perhaps/maybe'),
    
    # Common verbs
    ('podr?a', 'could'), ('podr?an', 'could'),
    ('deber?a', 'should'), ('deber?an', 'should'),
    ('habr?a', 'would have'), ('habr?an', 'would have'),
    ('ser?a', 'would be'), ('ser?an', 'would be'),
    ('tendr?a', 'would have'), ('tendr?an', 'would have'),
    ('har?a', 'would do'), ('har?an', 'would do'),
    ('dir?a', 'would say'), ('dir?an', 'would say'),
    ('vendr?a', 'would come'), ('vendr?an', 'would come'),
    ('querr?a', 'would want'), ('querr?an', 'would want'),
    ('sabr?a', 'would know'), ('sabr?an', 'would know'),
    ('causar?a', 'would cause'), ('causar?an', 'would cause'),
    ('requerir?a', 'would require'), ('requerir?an', 'would require'),
    ('necesitar?a', 'would need'), ('necesitar?an', 'would need'),
    ('permitir?a', 'would allow'), ('permitir?an', 'would allow'),
    ('devolver?a', 'would return'), ('devolver?an', 'would return'),
    
    # Future tense
    ('ser?', 'will be'), ('estar?', 'will be'),
    ('har?', 'will do'), ('dir?', 'will say'),
    ('tendr?', 'will have'), ('vendr?', 'will come'),
    ('habr?', 'there will be'), ('podr?', 'could/will be able to'),
    ('querr?', 'will want'), ('sabr?', 'will know'),
    
    # More -ción
    ('depuraci?n', 'debugging'),
    ('notificaci?n', 'notification'),
    ('modificaci?n', 'modification'),
    ('especificaci?n', 'specification'),
    ('simplificaci?n', 'simplification'),
    ('identificaci?n', 'identification'),
    ('verificaci?n', 'verification'),
    ('certificaci?n', 'certification'),
    ('justificaci?n', 'justification'),
    ('planificaci?n', 'planning'),
    ('purificaci?n', 'purification'),
    ('calificaci?n', 'qualification'),
    ('intensificaci?n', 'intensification'),
    ('diversificaci?n', 'diversification'),
    ('amplificaci?n', 'amplification'),
    ('simplificaci?n', 'simplification'),
    ('multiplicaci?n', 'multiplication'),
    ('complicaci?n', 'complication'),
    ('explicaci?n', 'explanation'),
    ('aplicaci?n', 'application'),
    ('implicaci?n', 'implication'),
    ('publicaci?n', 'publication'),
    ('comunicaci?n', 'communication'),
    ('educaci?n', 'education'),
    ('indicaci?n', 'indication'),
    ('dedicaci?n', 'dedication'),
    ('predicaci?n', 'predication'),
    ('fabricaci?n', 'fabrication'),
    ('lubricaci?n', 'lubrication'),
    ('falsificaci?n', 'falsification'),
]

def is_comment_line(line):
    stripped = line.strip()
    return stripped.startswith('//') or stripped.startswith('{') or stripped.startswith('(*')

def process_file(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8-sig') as f:
            content = f.read()
    except (UnicodeDecodeError, FileNotFoundError):
        with open(filepath, 'r', encoding='latin-1') as f:
            content = f.read()
    
    lines = content.split('\n')
    changes = 0
    
    for i, line in enumerate(lines):
        if not is_comment_line(line):
            continue
        
        # Skip lines that have no ?
        if '?' not in line:
            continue
        
        # Skip lines that are MIT license or copyright headers (already English)
        stripped = line.strip()
        if any(s in stripped.lower() for s in ['mit license', 'copyright (c)', 'permission is hereby', 
                'the software', 'warranty', 'furnished to do so', 'author:', 'email:', 'telegram:', 
                'linkedin:', 'github:', 'social networks:', 'name: gustavo', 'youtube:']):
            continue
        
        original = line
        # Apply fixes
        for old, new in KNOWN_FIXES:
            # Case insensitive replacement
            pattern = re.compile(re.escape(old), re.IGNORECASE)
            # Find matches
            matches = list(pattern.finditer(line))
            for match in reversed(matches):  # replace from end to preserve positions
                start, end = match.span()
                line = line[:start] + new + line[end:]
        
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
        for filename in files:
            if not filename.endswith('.pas'):
                continue
            filepath = os.path.join(root, filename)
            changes = process_file(filepath)
            if changes > 0:
                relpath = os.path.relpath(filepath, SOURCE_DIR)
                print(f'  {relpath}: {changes} fixes')
                total_files += 1
                total_changes += changes
    
    print(f'\nTotal: {total_changes} mojibake fixes in {total_files} files')


if __name__ == '__main__':
    main()
