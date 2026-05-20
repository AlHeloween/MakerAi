#!/usr/bin/env python3
"""FINAL: Apply 362-word dict to ALL comment types including trailing comments."""
import os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, 'Source')

# ===== 362-word dictionary from extract_q_words.py (all verified non-English ?-words) =====
WORD_MAP = {}

# Build from the complete list
_raw = """?alg?n:any|?alguna:any|?all:all|?critical:critical|?crucial:crucial|?el:the|?encontramos:we found|?es:it is|?hay:there is|?here:here|?importante:important|?rbol:tree|?tems:items|?tenemos:we have|a??delos:add them to|a?adan:add|a?adimos:we add|a?n:even|abort?:aborted|acci?n:action|act?a:acts|activaci?n:activation|actualizar?:would update|acumulaci?n:accumulation|ad?ptala:adapt it|add?a:would add|adue?a:takes ownership|agreg?:added|agregaci?n:aggregation|agrupaci?n:grouping|ah?:there|alfab?ticamente:alphabetically|alg?n:some|almac?n:warehouse|an?nimo:anonymous|aportaci?n:contribution|apuntar?:would point|aqui?:here|as?:like this|as?ncrona:asynchronous|as?ncrono:asynchronous|as?ncronos:asynchronous|aseg?rate:make sure|asign?:assigned|asignar?:would assign|asumir?:would assume|at?mica:atomic|at?micos:atomic|atenci?n:attention|atr?s:backward|autenticaci?n:authentication|autorizaci?n:authorization|av?same:notify me|b?sca:searches|baj?:went down|bloquear?:would block|borrar?amos:we would delete|bot?n:button|c?lculo:calculation|c?pialas:copy them|c?rculo:circle|cach?:cache|cambi?:changed|cancel?:cancelled|car?cter:character|categor?a:category|cercan?a:closeness|cerr?:closed|cient?ficos:scientific|codificaci?n:encoding|colch?n:cushion|com?n:common|complet?:completed|comprensi?n:understanding|compresi?n:compression|comprobaci?n:verification|concatenaci?n:concatenation|configur?:configured|confirmaci?n:confirmation|construcci?n:construction|contin?a:continues|continuaci?n:continuation|convenci?n:convention|conversaci?n:conversation|convirti?ndolas:converting them|coraz?n:heart|correcci?n:correction|corrupci?n:corruption|cre?:created|crear?:would create|cu?nto:how much|cu?ntos:how many|cumpli?:completed|d?bil:weak|d?gitos:digits|da?o:damage|dar?:would give|decisi?n:decision|declaraci?n:declaration|depend?a:depended|destrucci?n:destruction|destruir?:would destroy|destruir?n:they will destroy|destruy?:destroyed|detectar?:would detect|deteni?ndose:stopping|devoluci?n:return|devolvi?:returned|di?logo:dialog|diagn?stico:diagnostic|diarizaci?n:diarization|dif?cil:difficult|diferenciaci?n:differentiation|dim?:tell me|dise?ado:designed|dise?ador:designer|dise?o:design|distribuci?n:distribution|documentaci?n:documentation|due?os:owners|duraci?n:duration|edici?n:edition|ejecut?:executed|encargar?:will handle|encol?:queued|encontr?:found|encontrar?:would find|enga?ar:deceive|entr?:entered|entrar?:would enter|env?a:sends|env?e:send|env?o:sending|escribi?:wrote|espa?ol:Spanish|esperar?:would wait|estad?sticas:statistics|estrateg?a:strategy|eval?a:evaluates|eval?an:they evaluate|evalauci?n:evaluation|exist?a:existed|expl?cita:explicit|expl?citamente:explicitly|expl?cito:explicit|extra?da:extracted|extra?das:extracted|extra?do:extracted|extra?dos:extracted|extra?o:extracted|extracci?n:extraction|extraer?:would extract|f?brica:factory|f?cil:easy|f?cilmente:easily|f?rmula:formula|f?sica:physical|f?sico:physical|f?sicos:physical|factor?a:factory|factor?as:factories|finalizaci?n:completion|fragmentaci?n:fragmentation|funcionar?:would work|fusi?n:fusion|gener?:generated|grabaci?n:recording|gui?n:script|hab?a:there was|habilitar?:would enable|hac?as:you did|handlar?:would handle|heur?stica:heuristic|hu?rfana:orphan|hu?rfanas:orphans|hu?rfanos:orphans|id?ntica:identical|id?ntico:identical|id?nticos:identical|ignorar?n:they will ignore|im?gen:image|im?genes:images|impl?cito:implicit|implementaci?n:implementation|inclusi?n:inclusion|indexaci?n:indexing|ingl?s:English|inici?:started|inserci?n:insertion|instanciar?:would instantiate|instant?nea:instantaneous|instant?neo:instantaneous|integraci?n:integration|intentar?:would try|inter?n:internal|interact?a:interacted|intercepci?n:interception|interpolaci?n:interpolation|intervenci?n:intervention|introspecci?n:introspection|inv?lida:invalid|inv?lidos:invalid|invocaci?n:invocation|ir?a:would go|iteraci?n:iteration|jer?rquica:hierarchical|jer?rquicas:hierarchical|jer?rquico:hierarchical|jer?rquicos:hierarchical|jerarqu?a:hierarchy|l?mite:limit|l?mites:limits|l?nea:line|l?neas:lines|l?xica:lexical|l?xicas:lexical|l?xico:lexical|le?do:read|lematizaci?n:lemmatization|ley?:read|liberaci?n:release|liberar?:would free|liberar?n:they will free|librer?a:library|llamar?:would call|llamar?a:would call|llegar?:would arrive|llen?:filled|llev?:took|m?dulo:module|m?ltiple:multiple|m?ltiples:multiple|m?rgenes:margins|marc?:marked|may?sculas:uppercase|medici?n:measurement|men?:menu|modernizaci?n:modernization|muri?:died|navegaci?n:navigation|negaci?n:negation|normalizaci?n:normalization|num?rica:numeric|num?rico:numeric|num?ricos:numeric|ocupar?n:they will occupy|ocurri?:occurred|p?gina:page|p?ginas:pages|p?rdida:loss|p?rrafo:paragraph|p?xeles:pixels|par?metro:parameter|par?metros:parameters|parsear?:would parse|pas?:passed|pas?ndole:passing it|pas?rselos:pass them|peque?a:small|peque?as:small|peque?o:small|perder?a:would lose|perfecci?n:perfection|petici?n:request|poblar?:would populate|pol?tica:policy|posesi?n:possession|pr?ctica:practical|precisi?n:precision|presici?n:precision|prob?:tried|probabil?stico:probabilistic|prop?sito:purpose|protecci?n:protection|provey?:provided|provoc?:caused|puntuaci?n:scoring|qu?:what|qued?:remained|quisi?ramos:we would like|ra?ces:roots|ra?z:root|raz?n:reason|reanudaci?n:resumption|rec?lculo:recalculation|rec?procas:reciprocal|recalcular?a:would recalculate|recepci?n:reception|reci?n:recently|recib?:received|reconciliaci?n:reconciliation|recordar?:would remember|recuperar?:would recover|recuperar?n:they will recover|recursi?n:recursion|redise?ar:redesign|reenv?e:resend|reenv?o:resending|refactorizaci?n:refactoring|reintentar?:would retry|reparaci?n:repair|representar?:would represent|restricci?n:restriction|s?lido:solid|s?ncrona:synchronous|s?ncronamente:synchronously|s?ncrono:synchronous|seg?n:according to|sesi?n:session|sint?tica:synthetic|sobreescribir?:would overwrite|solicit?:requested|solicitar?:would request|soluc?n:solution|subi?:uploaded|super?:exceeded|suspensi?n:suspension|t?pico:typical|t?rmino:term|tama?o:size|te?rico:theoretical|ten?as:you had|termin?:finished|tom?:took|tomar?:would take|transcripci?n:transcription|transl?cido:translucent|trav?s:through|traves?a:crossing|ubicaci?n:location|unificaci?n:unification|us?:used|usar?:would use|v?a:via|v?lida:valid|v?lidas:valid|v?lidos:valid|vac?a:empty|vac?as:empty|vac?os:empty|vectorizaci?n:vectorization|ven?a:came|visi?n:vision|volver?:would return|m?s:more|despu?s:after|s?lo:only|tambi?n:also|todav?a:still|ning?n:no|c?digo:code|n?mero:number|n?meros:numbers|est?:is|est?n:are|c?mo:how|cu?l:which|cu?ndo:when|d?nde:where|qui?n:who|podr?a:could|podr?an:could|podr?amos:could|podr?as:could|deber?a:should|deber?an:should|deber?as:should|ser?:will be|ser?n:will be|estar?:will be|tendr?:will have|tendr?an:would have|habr?:there will be|habr?a:would have|sabr?a:would know|querr?a:would want|necesitar?as:would need|necesitar?s:will need|guardar?as:would save|disparar?:would trigger|ejecutar?:would execute|ejecutar?n:they will execute|enviar?:would send|recibir?:would receive|retornar?:would return|devolver?:would return|lanzar?:would launch|lanzar?n:they will launch|manejar?:would handle|usar?:would use|causar?a:would cause|b?squeda:search|b?squedas:searches|b?squeda?:search|patr?n:pattern|l?gica:logic|l?gico:logical|h?brida:hybrid|h?bridas:hybrid|h?brido:hybrid|sem?ntica:semantic|sem?nticamente:semantically|sem?ntico:semantic|m?todo:method|m?todos:methods|m?nima:minimum|m?nimos:minimal|m?xima:maximum|m?ximo:maximum|cl?sica:classic|cl?sico:classic|espec?fica:specific|espec?ficas:specific|espec?ficamente:specifically|espec?fico:specific|espec?ficos:specific|cr?tica:critical|cr?tico:critical|t?cnica:technical|t?cnicos:technical|t?cnico:technical|din?mica:dynamic|din?micas:dynamic|din?mico:dynamic|din?micos:dynamic|autom?tica:automatic|autom?ticamente:automatically|autom?tico:automatic|est?tica:static|est?tico:static|est?ticos:static|b?sica:basic|b?sicas:basic|b?sico:basic|b?sicos:basic|gen?rica:generic|gen?rico:generic|gen?ricos:generic|r?pida:fast|r?pidas:fast|r?pido:fast|p?blico:public|p?blicos:public|p?blicas:public|pr?ximo:next|?nico:unique|?nicos:unique|?nica:unique|?ltimo:last|?ltima:last|?til:useful|?tiles:useful|?xito:success|?ndice:index|?ndices:indexes|?cr?tico:critical|el?ndice:the index|all?:there|existe?:exists|Enr?quez:Enriquez|a?ade:adds|a?adido:added|a?adidos:added|a?adiendo:adding|a?adir:add|a?adirlo:add it|ning?n:no|soluci?n:solution|cl?usula:clause|expresi?n:expression|operaci?n:operation|instrucci?n:instruction|definici?n:definition|informaci?n:information|generaci?n:generation|relaci?n:relation|comparaci?n:comparison|cancelaci?n:cancellation|publicaci?n:publication|evaluaci?n:evaluation|clasificaci?n:classification|transformaci?n:transformation|comunicaci?n:communication|opci?n:option|condici?n:condition|colecci?n:collection|selecci?n:selection|posici?n:position|descripci?n:description|conexi?n:connection|configuraci?n:configuration|validaci?n:validation|ejecuci?n:execution|compilaci?n:compilation|traducci?n:translation|instalaci?n:installation|recuperaci?n:retrieval|sincronizaci?n:synchronization|duplicaci?n:duplication|creaci?n:creation|actualizaci?n:update|importaci?n:import|exportaci?n:export|asignaci?n:assignment|detecci?n:detection|inicializaci?n:initialization|conversi?n:conversion|expansi?n:expansion|serializaci?n:serialization|hidrataci?n:hydration|gesti?n:management|verificaci?n:verification|reconstrucci?n:reconstruction|optimizaci?n:optimization|delegaci?n:delegation|localizaci?n:localization|direcci?n:direction|reversi?n:reversion|extensi?n:extension|sustituci?n:substitution|inyecci?n:injection|sanitizaci?n:sanitization|aprobaci?n:approval|depuraci?n:debugging|notificaci?n:notification|modificaci?n:modification|especificaci?n:specification|simplificaci?n:simplification|identificaci?n:identification|aplicaci?n:application|n?cleo:core|gr?fico:graphic|Enr?quez:Enriquez|desconexi?n:disconnection|deserializaci?n:deserialization|resoluci?n:resolution|uni?n:union|sincr?nicamente:syncronically|sincr?nico:syncronic|Enr?quez:Enriquez"""

# Parse the raw string
for pair in _raw.split('|'):
    if ':' in pair:
        k, v = pair.split(':', 1)
        WORD_MAP[k.strip()] = v.strip()

# Add key missing words that should have been in the extract
EXTRA = {
    'expresi?n': 'expression', 'expresiones': 'expressions',
    'operaci?n': 'operation', 'operaciones': 'operations',
    'secci?n': 'section', 'secciones': 'sections',
    'versi?n': 'version', 'versiones': 'versions',
    'funci?n': 'function', 'funciones': 'functions',
    'dimensi?n': 'dimension', 'dimensiones': 'dimensions',
    'ejecuci?n': 'execution', 'ejecuciones': 'executions',
    'conexi?n': 'connection', 'conexiones': 'connections',
    'soluci?n': 'solution', 'soluciones': 'solutions',
    'excepci?n': 'exception', 'excepciones': 'exceptions',
    'observaci?n': 'observation', 'observaciones': 'observations',
}
WORD_MAP.update(EXTRA)

def has_comment(line):
    return '//' in line or '{' in line or '(*' in line

def should_skip(line):
    lower = line.lower()
    return any(s in lower for s in [
        'mit license', 'copyright (c)', 'permission is', 'the software',
        'warranty', 'furnished to', 'above copyright', 'social networks:',
        'name: gustavo', 'author:', 'email:', 'telegram:', 'linkedin:',
        'github:', 'youtube:'
    ])

def process_file(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8-sig') as f:
            content = f.read()
    except:
        try:
            with open(filepath, 'r', encoding='latin-1') as f:
                content = f.read()
        except:
            return 0
    
    lines = content.split('\n')
    changes = 0
    
    for i, line in enumerate(lines):
        if not has_comment(line): continue
        if should_skip(line): continue
        if '?' not in line: continue
        
        original = line
        for word, replacement in WORD_MAP.items():
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
        dirs[:] = [d for d in dirs if d not in ('Packages','Resources','hpp')]
        for fn in sorted(files):
            if not fn.endswith('.pas'): continue
            ch = process_file(os.path.join(root, fn))
            if ch > 0:
                total_files += 1
                total_changes += ch
                print(f'  {os.path.relpath(os.path.join(root, fn), SOURCE_DIR)}: {ch}')
    print(f'\n{total_changes} fixes in {total_files} files')

if __name__ == '__main__':
    main()
