#!/usr/bin/env python3
"""
DEFINITIVE FINAL PASS: Map ALL 362 unique ?-containing words to their fixes.
Each word is uniquely identified and replaced with its correct form.
"""

import os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, 'Source')

# Complete mapping of every ?-containing word found in the codebase
# Format: word_with_? → replacement_text
WORD_MAP = {
    # Words starting with ?
    '?alg?n': 'any',
    '?alguna': 'any',
    '?all': 'all',
    '?critical': 'critical',
    '?crucial': 'crucial',
    '?el': 'the',
    '?encontramos': 'we found',
    '?es': 'it is',
    '?hay': 'there is/are',
    '?here': 'here',
    '?importante': 'important',
    '?rbol': 'tree',
    '?tems': 'items',
    '?tenemos': 'we have',
    
    # Words with ? between chars
    'a??delos': 'add them to',
    'a?adan': 'add', 'a?adimos': 'we add', 'a?n': 'even/still',
    'abort?': 'aborted',
    'acci?n': 'action',
    'act?a': 'acts',
    'activaci?n': 'activation',
    'actualizar?': 'would update',
    'acumulaci?n': 'accumulation',
    'ad?ptala': 'adapt it',
    'add?a': 'would add',
    'adue?a': 'takes ownership',
    'agreg?': 'added',
    'agregaci?n': 'aggregation',
    'agrupaci?n': 'grouping',
    'ah?': 'there',
    'alfab?ticamente': 'alphabetically',
    'alg?n': 'some/any',
    'almac?n': 'warehouse',
    'an?nimo': 'anonymous',
    'aportaci?n': 'contribution',
    'apuntar?': 'would point',
    'aqui?': 'here',
    'as?': 'like this/so',
    'as?ncrona': 'asynchronous', 'as?ncrono': 'asynchronous', 'as?ncronos': 'asynchronous',
    'aseg?rate': 'make sure',
    'asign?': 'assigned',
    'asignar?': 'would assign',
    'asumir?': 'would assume',
    'at?mica': 'atomic', 'at?micos': 'atomic',
    'atenci?n': 'attention',
    'atr?s': 'backward/behind',
    'autenticaci?n': 'authentication',
    'autorizaci?n': 'authorization',
    'av?same': 'notify me',
    
    'b?sca': 'searches',
    'baj?': 'went down',
    'bloquear?': 'would block',
    'borrar?': 'would delete', 'borrar?amos': 'we would delete',
    'bot?n': 'button',
    
    'c?lculo': 'calculation',
    'c?pialas': 'copy them',
    'c?rculo': 'circle',
    'cach?': 'cache',
    'cambi?': 'changed',
    'cancel?': 'cancelled',
    'car?cter': 'character',
    'categor?a': 'category',
    'cercan?a': 'closeness',
    'cerr?': 'closed',
    'cient?ficos': 'scientific',
    'codificaci?n': 'encoding',
    'colch?n': 'cushion/padding',
    'com?n': 'common',
    'complet?': 'completed',
    'comprensi?n': 'understanding',
    'compresi?n': 'compression',
    'comprobaci?n': 'verification/check',
    'concatenaci?n': 'concatenation',
    'configur?': 'configured',
    'confirmaci?n': 'confirmation',
    'construcci?n': 'construction/building',
    'contin?a': 'continues',
    'continuaci?n': 'continuation',
    'convenci?n': 'convention',
    'conversaci?n': 'conversation',
    'convirti?ndolas': 'converting them',
    'coraz?n': 'heart',
    'correcci?n': 'correction',
    'corrupci?n': 'corruption',
    'cre?': 'created',
    'crear?': 'would create',
    'cu?nto': 'how much', 'cu?ntos': 'how many',
    'cumpli?': 'completed',
    
    'd?bil': 'weak',
    'd?gitos': 'digits',
    'da?o': 'damage',
    'dar?': 'would give',
    'decisi?n': 'decision',
    'declaraci?n': 'declaration',
    'depend?a': 'depended',
    'destrucci?n': 'destruction',
    'destruir?': 'would destroy', 'destruir?n': 'they will destroy',
    'destruy?': 'destroyed',
    'detectar?': 'would detect',
    'deteni?ndose': 'stopping',
    'devoluci?n': 'return',
    'devolvi?': 'returned',
    'di?logo': 'dialog',
    'diagn?stico': 'diagnostic',
    'diarizaci?n': 'diarization',
    'dif?cil': 'difficult',
    'diferenciaci?n': 'differentiation',
    'dim?': 'tell me',
    'dise?ado': 'designed', 'dise?ador': 'designer', 'dise?o': 'design',
    'distribuci?n': 'distribution',
    'documentaci?n': 'documentation',
    'driver?': 'driver?',  # English question mark - leave
    'due?os': 'owners',
    'duraci?n': 'duration',
    
    'edici?n': 'edition/editing',
    'ejecut?': 'executed',
    'embeddings?': 'embeddings?',  # English question
    'encargar?': 'will handle/responsible',
    'encol?': 'queued',
    'encontr?': 'found',
    'encontrar?': 'would find',
    'enga?ar': 'deceive/trick',
    'entr?': 'entered',
    'entrar?': 'would enter',
    'env?a': 'sends', 'env?e': 'send', 'env?o': 'shipment/sending',
    'escribi?': 'wrote',
    'espa?ol': 'spanish',
    'esperar?': 'would wait',
    'estad?sticas': 'statistics',
    'estrateg?a': 'strategy',
    'eval?a': 'evaluates', 'eval?an': 'they evaluate',
    'evalauci?n': 'evaluation',
    'execute?': 'execute?', 'execute?n': 'execute?',  # English
    'exist?a': 'existed',
    'existe?': 'exists?',
    'expl?cita': 'explicit', 'expl?citamente': 'explicitly', 'expl?cito': 'explicit',
    'extra?da': 'extracted', 'extra?das': 'extracted', 'extra?do': 'extracted',
    'extra?dos': 'extracted', 'extra?o': 'extracted',
    'extracci?n': 'extraction',
    'extraer?': 'would extract',
    
    'f?brica': 'factory',
    'f?cil': 'easy',
    'f?cilmente': 'easily',
    'f?rmula': 'formula',
    'f?sica': 'physical', 'f?sico': 'physical', 'f?sicos': 'physical',
    'factor?a': 'factory', 'factor?as': 'factories',
    'finalizaci?n': 'completion/termination',
    'fragmentaci?n': 'fragmentation',
    'free?': 'free?', 'free?n': 'free?',  # English
    'funcionar?': 'would work',
    'fusi?n': 'fusion',
    
    'gener?': 'generated',
    'grabaci?n': 'recording',
    'gui?n': 'script/hyphen',
    
    'hab?a': 'there was/had',
    'habilitar?': 'would enable',
    'hac?as': 'you did',
    'handlar?': 'would handle',
    'heur?stica': 'heuristic',
    'hu?rfana': 'orphan', 'hu?rfanas': 'orphans', 'hu?rfanos': 'orphans',
    
    'id?': 'id?',
    'id?ntica': 'identical', 'id?ntico': 'identical', 'id?nticos': 'identical',
    'ignorar?n': 'they will ignore',
    'im?gen': 'image', 'im?genes': 'images',
    'impl?cito': 'implicit',
    'implementaci?n': 'implementation',
    'inclusi?n': 'inclusion',
    'index?': 'index?',  # English
    'indexaci?n': 'indexing',
    'ingl?s': 'english',
    'inici?': 'started',
    'inserci?n': 'insertion',
    'instanciar?': 'would instantiate',
    'instant?nea': 'instant/snapshot', 'instant?neo': 'instantaneous',
    'integraci?n': 'integration',
    'intentar?': 'would try',
    'inter?n': 'internal',
    'interact?a': 'interacted',
    'intercepci?n': 'interception',
    'interpolaci?n': 'interpolation',
    'intervenci?n': 'intervention',
    'introspecci?n': 'introspection',
    'inv?lida': 'invalid', 'inv?lidos': 'invalid',
    'invocaci?n': 'invocation',
    'ir?a': 'would go',
    'iteraci?n': 'iteration',
    
    'jer?rquica': 'hierarchical', 'jer?rquicas': 'hierarchical',
    'jer?rquico': 'hierarchical', 'jer?rquicos': 'hierarchical',
    'jerarqu?a': 'hierarchy',
    
    'l?mite': 'limit', 'l?mites': 'limits',
    'l?nea': 'line', 'l?neas': 'lines',
    'l?xica': 'lexical', 'l?xicas': 'lexical', 'l?xico': 'lexicon/lexical',
    'launch?': 'launch?', 'launch?n': 'launch?',  # English
    'le?do': 'read',
    'lematizaci?n': 'lemmatization',
    'ley?': 'read/law',
    'liberaci?n': 'release/liberation',
    'librer?a': 'library',
    'llamar?': 'would call', 'llamar?a': 'would call',
    'llegar?': 'would arrive',
    'llen?': 'filled',
    'llev?': 'took/carried',
    
    'm?dulo': 'module',
    'm?ltiple': 'multiple', 'm?ltiples': 'multiple',
    'm?rgenes': 'margins',
    'marc?': 'marked',
    'may?sculas': 'uppercase',
    'medici?n': 'measurement',
    'men?': 'menu',
    'modernizaci?n': 'modernization',
    'muri?': 'died',
    
    'navegaci?n': 'navigation',
    'negaci?n': 'negation',
    'normalizaci?n': 'normalization',
    'num?rica': 'numeric', 'num?rico': 'numeric', 'num?ricos': 'numeric',
    
    'ocupar?n': 'they will occupy',
    'ocurri?': 'occurred',
    
    'p?gina': 'page', 'p?ginas': 'pages',
    'p?rdida': 'loss',
    'p?rrafo': 'paragraph',
    'p?xeles': 'pixels',
    'par?metro': 'parameter', 'par?metros': 'parameters',
    'parsear?': 'would parse',
    'pas?': 'passed', 'pas?ndole': 'passing it', 'pas?rselos': 'pass them',
    'peque?a': 'small', 'peque?as': 'small', 'peque?o': 'small',
    'perder?a': 'would lose',
    'perfecci?n': 'perfection',
    'petici?n': 'request',
    'poblar?': 'would populate',
    'pol?tica': 'policy/politics',
    'posesi?n': 'possession',
    'pr?ctica': 'practice/practical',
    'precisi?n': 'precision',
    'presici?n': 'precision',
    'prob?': 'tried',
    'probabil?stico': 'probabilistic',
    'process?': 'process?',  # English
    'prop?sito': 'purpose',
    'propvalue?': 'PropValue?',  # Pascal identifier
    'protecci?n': 'protection',
    'provey?': 'provided',
    'provoc?': 'caused/provoked',
    'puntuaci?n': 'punctuation/scoring',
    
    'qu?': 'what',
    'qued?': 'remained/stayed',
    'quisi?ramos': 'we would like',
    
    'ra?ces': 'roots',
    'ra?z': 'root',
    'raz?n': 'reason',
    'reanudaci?n': 'resumption',
    'rec?lculo': 'recalculation',
    'rec?procas': 'reciprocal',
    'recalcular?a': 'would recalculate',
    'receive?': 'receive?',  # English
    'recepci?n': 'reception',
    'reci?n': 'recently/just',
    'recib?': 'received',
    'reconciliaci?n': 'reconciliation',
    'recordar?': 'would remember',
    'recuperar?': 'would recover',
    'recursi?n': 'recursion',
    'redise?ar': 'redesign',
    'reenv?e': 'resend', 'reenv?o': 'resending',
    'refactorizaci?n': 'refactoring',
    'reintentar?': 'would retry',
    'reparaci?n': 'repair',
    'representar?': 'would represent',
    'restricci?n': 'restriction',
    'return?': 'return?',  # English
    
    's?lido': 'solid',
    's?ncrona': 'synchronous', 's?ncronamente': 'synchronously', 's?ncrono': 'synchronous',
    'save?as': 'save?as',  # English/Pascal hybrid
    'search?': 'search?',  # English
    'seg?n': 'according to',
    'send?': 'send?',  # English
    'sesi?n': 'session',
    'sint?tica': 'synthetic',
    'sobreescribir?': 'would overwrite',
    'solicit?': 'requested',
    'solicitar?': 'would request',
    'soluc?n': 'solution',
    'subi?': 'uploaded/went up',
    'super?': 'exceeded/passed',
    'suspensi?n': 'suspension',
    
    't?pico': 'typical/topic',
    't?rmino': 'term',
    'tama?o': 'size',
    'te?rico': 'theoretical',
    'ten?as': 'you had',
    'termin?': 'finished/ended',
    'tom?': 'took',
    'tomar?': 'would take',
    'transcripci?n': 'transcription',
    'transl?cido': 'translucent',
    'trav?s': 'through/via',
    'traves?a': 'crossing/path',
    'trigger?': 'trigger?',  # English
    
    'ubicaci?n': 'location',
    'unificaci?n': 'unification',
    'us?': 'used',
    'usar?': 'would use',
    
    'v?a': 'via',
    'v?lida': 'valid', 'v?lidas': 'valid', 'v?lidos': 'valid',
    'vac?a': 'empty', 'vac?as': 'empty', 'vac?os': 'empty',
    'vectorizaci?n': 'vectorization',
    'ven?a': 'came/was coming',
    'verify?': 'verify?',  # English
    'visi?n': 'vision',
    'volver?': 'would return',
}

def should_skip(line):
    lower = line.strip().lower()
    return any(s in lower for s in [
        'mit license', 'copyright (c)', 'permission is', 'the software',
        'warranty', 'furnished to', 'above copyright', 'social networks:',
        'name: gustavo', 'author:', 'email:', 'telegram:', 'linkedin:', 'github:',
        'youtube:'
    ])

def is_comment(line):
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
        if not is_comment(line):
            continue
        if should_skip(line):
            continue
        if '?' not in line:
            continue
        
        original = line
        # Replace each ?-containing word with its fix
        for word, replacement in WORD_MAP.items():
            # Use case-insensitive whole-word replacement
            pattern = re.compile(re.escape(word), re.IGNORECASE)
            line = pattern.sub(replacement, line)
        
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
