#!/usr/bin/env python3
"""Aggressive final pass: fix ALL remaining ? in comments across all .pas files."""

import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, 'Source')

# Patterns where ? + trailing chars can be unambiguously fixed
# Format: (regex_pattern, replacement)
# The ? is always a literal question mark
AMBIGUOUS_FIXES = [
    # -ión words
    (r'\b(expresi)o(\?)n\b', r'\1ion'),
    (r'\b(operaci)o(\?)n\b', r'\1ion'),
    (r'\b(instrucci)o(\?)n\b', r'\1ion'),
    (r'\b(definici)o(\?)n\b', r'\1ion'),
    (r'\b(informaci)o(\?)n\b', r'\1ion'),
    (r'\b(generaci)o(\?)n\b', r'\1ion'),
    (r'\b(relaci)o(\?)n\b', r'\1ion'),
    (r'\b(comparaci)o(\?)n\b', r'\1ion'),
    (r'\b(cancelaci)o(\?)n\b', r'\1ion'),
    (r'\b(presentaci)o(\?)n\b', r'\1ion'),
    (r'\b(publicaci)o(\?)n\b', r'\1ion'),
    (r'\b(evaluaci)o(\?)n\b', r'\1ion'),
    (r'\b(interpretaci)o(\?)n\b', r'\1ion'),
    (r'\b(clasificaci)o(\?)n\b', r'\1ion'),
    (r'\b(transformaci)o(\?)n\b', r'\1ion'),
    (r'\b(comunicaci)o(\?)n\b', r'\1ion'),
    (r'\b(soluci)o(\?)n\b', r'\1ion'),
    (r'\b(opci)o(\?)n\b', r'\1ion'),
    (r'\b(condici)o(\?)n\b', r'\1ion'),
    (r'\b(colecci)o(\?)n\b', r'\1ion'),
    (r'\b(selecci)o(\?)n\b', r'\1ion'),
    (r'\b(posici)o(\?)n\b', r'\1ion'),
    (r'\b(descripci)o(\?)n\b', r'\1ion'),
    (r'\b(conexi)o(\?)n\b', r'\1ion'),
    (r'\b(configuraci)o(\?)n\b', r'\1ion'),
    (r'\b(validaci)o(\?)n\b', r'\1ion'),
    (r'\b(ejecuci)o(\?)n\b', r'\1ion'),
    (r'\b(compilaci)o(\?)n\b', r'\1ion'),
    (r'\b(traducci)o(\?)n\b', r'\1ion'),
    (r'\b(instalaci)o(\?)n\b', r'\1ion'),
    (r'\b(recuperaci)o(\?)n\b', r'\1ion'),
    (r'\b(sincronizaci)o(\?)n\b', r'\1ion'),
    (r'\b(duplicaci)o(\?)n\b', r'\1ion'),
    (r'\b(creaci)o(\?)n\b', r'\1ion'),
    (r'\b(actualizaci)o(\?)n\b', r'\1ion'),
    (r'\b(importaci)o(\?)n\b', r'\1ion'),
    (r'\b(exportaci)o(\?)n\b', r'\1ion'),
    (r'\b(asignaci)o(\?)n\b', r'\1ion'),
    (r'\b(detecci)o(\?)n\b', r'\1ion'),
    (r'\b(inicializaci)o(\?)n\b', r'\1ion'),
    (r'\b(conversi)o(\?)n\b', r'\1ion'),
    (r'\b(expansi)o(\?)n\b', r'\1ion'),
    (r'\b(serializaci)o(\?)n\b', r'\1ion'),
    (r'\b(hidrataci)o(\?)n\b', r'\1ion'),
    (r'\b(gesti)o(\?)n\b', r'\1ion'),
    (r'\b(verificaci)o(\?)n\b', r'\1ion'),
    (r'\b(reconstrucci)o(\?)n\b', r'\1ion'),
    (r'\b(optimizaci)o(\?)n\b', r'\1ion'),
    (r'\b(delegaci)o(\?)n\b', r'\1ion'),
    (r'\b(localizaci)o(\?)n\b', r'\1ion'),
    (r'\b(direcci)o(\?)n\b', r'\1ion'),
    (r'\b(reversi)o(\?)n\b', r'\1ion'),
    (r'\b(extensi)o(\?)n\b', r'\1ion'),
    (r'\b(sustituci)o(\?)n\b', r'\1ion'),
    (r'\b(inyecci)o(\?)n\b', r'\1ion'),
    (r'\b(sanitizaci)o(\?)n\b', r'\1ion'),
    (r'\b(aprobaci)o(\?)n\b', r'\1ion'),
    (r'\b(notificaci)o(\?)n\b', r'\1ion'),
    (r'\b(modificaci)o(\?)n\b', r'\1ion'),
    (r'\b(especificaci)o(\?)n\b', r'\1ion'),
    (r'\b(simplificaci)o(\?)n\b', r'\1ion'),
    (r'\b(identificaci)o(\?)n\b', r'\1ion'),
    (r'\b(justificaci)o(\?)n\b', r'\1ion'),
    (r'\b(planificaci)o(\?)n\b', r'\1ion'),
    (r'\b(calificaci)o(\?)n\b', r'\1ion'),
    (r'\b(explicaci)o(\?)n\b', r'\1ion'),
    (r'\b(aplicaci)o(\?)n\b', r'\1ion'),
    (r'\b(implicaci)o(\?)n\b', r'\1ion'),
    (r'\b(indicaci)o(\?)n\b', r'\1ion'),
    (r'\b(depuraci)o(\?)n\b', r'\1ion'),
    # -ción words
    (r'\b(funci)o(\?)n\b', r'\1ion'),
    (r'\b(dimensi)o(\?)n\b', r'\1ion'),
    (r'\b(secci)o(\?)n\b', r'\1ion'),
    (r'\b(versi)o(\?)n\b', r'\1ion'),
    # á... patterns
    (r'\b(\?)rbol\b', r'tree'),
    (r'\b(\?)rea\b', r'area'),
    (r'\b(\?)reas\b', r'areas'),
    (r'\ba(\?)adir\b', r'add'),
    (r'\ba(\?)adiendo\b', r'adding'),
    (r'\ba(\?)adido\b', r'added'),
    (r'\ba(\?)ade\b', r'adds'),
    # é patterns
    (r'\b(\?)xito\b', r'success'),
    (r'\bexcepci(\?)n\b', r'exception'),
    # í patterns  
    (r'\b(\?)ndice\b', r'index'),
    (r'\b(\?)ndices\b', r'indexes'),
    # ó patterns
    (r'\bc(\?)digo\b', r'code'),
    (r'\bn(\?)mero\b', r'number'),
    (r'\bn(\?)meros\b', r'numbers'),
    (r'\bs(\?)lo\b', r'only'),
    (r'\bdespu(\?)s\b', r'after'),
    (r'\bm(\?)s\b', r'more'),
    (r'\best(\?)\b', r'is'),
    (r'\best(\?)n\b', r'are'),
    (r'\bc(\?)mo\b', r'how'),
    (r'\bcu(\?)l\b', r'which'),
    (r'\bcu(\?)ndo\b', r'when'),
    (r'\bd(\?)nde\b', r'where'),
    (r'\bqui(\?)n\b', r'who'),
    (r'\bpodr(\?)a\b', r'could'),
    (r'\bpodr(\?)an\b', r'could'),
    # ú patterns
    (r'\b(\?)nico\b', r'unique'),
    (r'\b(\?)nica\b', r'unique'),
    (r'\b(\?)nicos\b', r'unique'),
    (r'\b(\?)ltimo\b', r'last'),
    (r'\b(\?)ltima\b', r'last'),
    (r'\b(\?)til\b', r'useful'),
    (r'\b(\?)tiles\b', r'useful'),
    # More common patterns
    (r'\bcl(\?)usula\b', r'clause'),
    (r'\bpatr(\?)n\b', r'pattern'),
    (r'\bpatrones\b', r'patterns'),  # no fix needed if correct
    (r'\bb(\?)squeda\b', r'search'),
    (r'\bb(\?)squedas\b', r'searches'),
    (r'\bl(\?)gica\b', r'logic'),
    (r'\bl(\?)gico\b', r'logical'),
    (r'\bl(\?)gicos\b', r'logical'),
    (r'\bh(\?)brida\b', r'hybrid'),
    (r'\bh(\?)brido\b', r'hybrid'),
    (r'\bsem(\?)ntica\b', r'semantic'),
    (r'\bsem(\?)ntico\b', r'semantic'),
    (r'\bm(\?)todo\b', r'method'),
    (r'\bm(\?)todos\b', r'methods'),
    (r'\bm(\?)trica\b', r'metric'),
    (r'\bm(\?)tricas\b', r'metrics'),
    (r'\best(\?)ndar\b', r'standard'),
    (r'\best(\?)ndares\b', r'standards'),
    (r'\bcl(\?)sica\b', r'classic'),
    (r'\bcl(\?)sico\b', r'classic'),
    (r'\bespec(\?)fica\b', r'specific'),
    (r'\bespec(\?)fico\b', r'specific'),
    (r'\bm(\?)xima\b', r'maximum'),
    (r'\bm(\?)ximo\b', r'maximum'),
    (r'\bm(\?)nimo\b', r'minimum'),
    (r'\bm(\?)nima\b', r'minimum'),
    (r'\bcr(\?)tica\b', r'critical'),
    (r'\bcr(\?)tico\b', r'critical'),
    (r'\bt(\?)cnica\b', r'technical'),
    (r'\bt(\?)cnico\b', r'technical'),
    (r'\bdin(\?)mica\b', r'dynamic'),
    (r'\bdin(\?)mico\b', r'dynamic'),
    (r'\bdin(\?)micas\b', r'dynamic'),
    (r'\bdin(\?)micos\b', r'dynamic'),
    (r'\bautom(\?)tica\b', r'automatic'),
    (r'\bautom(\?)tico\b', r'automatic'),
    (r'\bautom(\?)ticamente\b', r'automatically'),
    (r'\best(\?)tica\b', r'static'),
    (r'\bv(\?)lido\b', r'valid'),
    (r'\binv(\?)lido\b', r'invalid'),
    (r'\bvac(\?)o\b', r'empty'),
    (r'\bning(\?)n\b', r'no'),
    (r'\btambi(\?)n\b', r'also'),
    (r'\btodav(\?)a\b', r'still'),
    (r'\baqu(\?)\b', r'here'),
    (r'\ball(\?)\b', r'there'),
    (r'\bp(\?)blica\b', r'public'),
    (r'\bp(\?)blico\b', r'public'),
    (r'\bpr(\?)ximo\b', r'next'),
    (r'\bencontrado(\?)a\b', r'found'),
    (r'\bdevolvi(\?)a\b', r'returned'),
    (r'\bdevolvi(\?)an\b', r'would return'),
    (r'\bser(\?)a\b', r'would be'),
    (r'\bser(\?)an\b', r'would be'),
    (r'\bestar(\?)a\b', r'would be'),
    (r'\bestar(\?)an\b', r'would be'),
    (r'\btendr(\?)a\b', r'would have'),
    (r'\btendr(\?)an\b', r'would have'),
    (r'\bhabr(\?)a\b', r'would have'),
    (r'\bhabr(\?)an\b', r'would have'),
    (r'\brecorrer(\?)a\b', r'would traverse'),
    (r'\brequerir(\?)a\b', r'would require'),
    (r'\bnecesitar(\?)a\b', r'would need'),
    (r'\bpermitir(\?)a\b', r'would allow'),
    (r'\bcausar(\?)a\b', r'would cause'),
    (r'\bhar(\?)a\b', r'would do'),
    (r'\bhar(\?)an\b', r'would do'),
    (r'\bdir(\?)a\b', r'would say'),
    (r'\bdir(\?)an\b', r'would say'),
    (r'\bsabr(\?)a\b', r'would know'),
    (r'\bsabr(\?)an\b', r'would know'),
    (r'\bquerr(\?)a\b', r'would want'),
    (r'\bquerr(\?)an\b', r'would want'),
    (r'\bpodr(\?)a\b', r'could'),
    (r'\bpodr(\?)an\b', r'could'),
    (r'\bdeber(\?)a\b', r'should'),
    (r'\bdeber(\?)an\b', r'should'),
    (r'\bser(\?)\b', r'will be'),
    (r'\bestar(\?)\b', r'will be'),
    (r'\bhar(\?)\b', r'will do'),
    (r'\bdir(\?)\b', r'will say'),
    (r'\btendr(\?)\b', r'will have'),
    (r'\bhabr(\?)\b', r'there will be'),
]

def is_comment_line(line):
    stripped = line.strip()
    return stripped.startswith('//') or stripped.startswith('{') or stripped.startswith('(*')

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
        if '?' not in line:
            continue
        if not is_comment_line(line):
            continue
        
        # Skip copyright/license headers
        stripped = line.strip().lower()
        if any(s in stripped for s in ['mit license', 'copyright (c)', 'permission is hereby', 
                'the software', 'warranty', 'furnished to do so']):
            continue
        
        original = line
        for pattern, replacement in AMBIGUOUS_FIXES:
            line = re.sub(pattern, replacement, line, flags=re.IGNORECASE)
        
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
    
    print(f'\nTotal: {total_changes} fixes in {total_files} files')


if __name__ == '__main__':
    main()
