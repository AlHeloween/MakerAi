#!/usr/bin/env python3
"""
FINAL PASS: Translate ALL remaining Spanish + fix ALL mojibake in ALL .pas comments.
This script must be exhaustive - nothing Spanish should remain after running it.
"""

import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, 'Source')

def make_fix_map():
    """Build the complete translation map."""
    fixes = []
    
    # === MOJIBAKE ? FIXES ===
    # Patterns where ? replaces an accented character in Spanish words
    
    # -ión endings
    for base in ['expresi','operaci','instrucci','definici','informaci','generaci',
                 'relaci','comparaci','cancelaci','presentaci','publicaci','evaluaci',
                 'interpretaci','clasificaci','transformaci','comunicaci','soluci',
                 'opci','condici','colecci','selecci','posici','descripci','conexi',
                 'configuraci','validaci','ejecuci','compilaci','traducci','instalaci',
                 'recuperaci','sincronizaci','duplicaci','creaci','actualizaci',
                 'importaci','exportaci','asignaci','detecci','inicializaci','conversi',
                 'expansi','serializaci','hidrataci','gesti','verificaci',
                 'reconstrucci','optimizaci','delegaci','localizaci','direcci',
                 'reversi','extensi','sustituci','inyecci','sanitizaci','aprobaci',
                 'depuraci','notificaci','modificaci','especificaci','simplificaci',
                 'identificaci','justificaci','planificaci','calificaci',
                 'explicaci','aplicaci','implicaci','indicaci',
                 'funci','dimensi','secci','versi','excepci']:
        fixes.append((re.compile(r'\b(' + base + r')o\?n\b', re.IGNORECASE), r'\1ion'))
    
    # Words with replaced accented vowels
    word_fixes = {
        r'\b\?rbol\b': 'tree',
        r'\b\?rea\b': 'area', r'\b\?reas\b': 'areas',
        r'\ba\?adir\b': 'add', r'\ba\?adiendo\b': 'adding',
        r'\ba\?adido\b': 'added', r'\ba\?ade\b': 'adds',
        r'\b\?xito\b': 'success',
        r'\b\?ndice\b': 'index', r'\b\?ndices\b': 'indexes',
        r'\bc\?digo\b': 'code', r'\bn\?mero\b': 'number', r'\bn\?meros\b': 'numbers',
        r'\bs\?lo\b': 'only', r'\bdespu\?s\b': 'after', r'\bm\?s\b': 'more',
        r'\best\?\b': 'is', r'\best\?n\b': 'are',
        r'\bc\?mo\b': 'how', r'\bcu\?l\b': 'which', r'\bcu\?ndo\b': 'when',
        r'\bd\?nde\b': 'where', r'\bqui\?n\b': 'who', r'\ball\?\b': 'there',
        r'\baqu\?\b': 'here', r'\bquiz\?s\b': 'perhaps',
        r'\bcl\?usula\b': 'clause', r'\bconclusi\?n\b': 'conclusion',
        r'\bpatr\?n\b': 'pattern', r'\bpatrones\b': 'patterns',
        r'\bb\?squeda\b': 'search', r'\bb\?squedas\b': 'searches',
        r'\bl\?gica\b': 'logic', r'\bl\?gico\b': 'logical', r'\bl\?gicos\b': 'logical',
        r'\bh\?brida\b': 'hybrid', r'\bh\?brido\b': 'hybrid',
        r'\bsem\?ntica\b': 'semantic', r'\bsem\?ntico\b': 'semantic',
        r'\bm\?todo\b': 'method', r'\bm\?todos\b': 'methods',
        r'\bm\?trica\b': 'metric', r'\bm\?tricas\b': 'metrics',
        r'\best\?ndar\b': 'standard', r'\best\?ndares\b': 'standards',
        r'\bcl\?sica\b': 'classic', r'\bcl\?sico\b': 'classic',
        r'\bespec\?fica\b': 'specific', r'\bespec\?fico\b': 'specific',
        r'\bm\?xima\b': 'maximum', r'\bm\?ximo\b': 'maximum',
        r'\bm\?nimo\b': 'minimum', r'\bm\?nima\b': 'minimum',
        r'\bcr\?tica\b': 'critical', r'\bcr\?tico\b': 'critical',
        r'\bt\?cnica\b': 'technical', r'\bt\?cnico\b': 'technical',
        r'\bdin\?mica\b': 'dynamic', r'\bdin\?mico\b': 'dynamic',
        r'\bdin\?micas\b': 'dynamic', r'\bdin\?micos\b': 'dynamic',
        r'\bautom\?tica\b': 'automatic', r'\bautom\?tico\b': 'automatic',
        r'\bautom\?ticamente\b': 'automatically',
        r'\best\?tica\b': 'static', r'\best\?tico\b': 'static',
        r'\bv\?lido\b': 'valid', r'\binv\?lido\b': 'invalid',
        r'\bvac\?o\b': 'empty', r'\bning\?n\b': 'no',
        r'\btambi\?n\b': 'also', r'\btodav\?a\b': 'still',
        r'\bp\?blica\b': 'public', r'\bp\?blico\b': 'public',
        r'\bpr\?ximo\b': 'next', r'\b\?nica\b': 'unique',
        r'\b\?nico\b': 'unique', r'\b\?nicos\b': 'unique',
        r'\b\?ltimo\b': 'last', r'\b\?ltima\b': 'last',
        r'\b\?til\b': 'useful', r'\b\?tiles\b': 'useful',
        r'\bm\?quina\b': 'machine',
        r'\bgen\?rica\b': 'generic', r'\bgen\?rico\b': 'generic',
        r'\bb\?sica\b': 'basic', r'\bb\?sico\b': 'basic',
        r'\bel\?ctrica\b': 'electric', r'\bn\?cleo\b': 'core',
        r'\bgr\?fico\b': 'graphic', r'\bgr\?fica\b': 'graphic',
        r'\br\?pida\b': 'fast', r'\br\?pido\b': 'fast',
        r'\br\?pidas\b': 'fast', r'\br\?pidos\b': 'fast',
        r'\bint\?rprete\b': 'interpreter',
        r'\bdue\?o\b': 'owner', r'\bdue\?a\b': 'owner',
        r'\bansi\b': 'ANSII',  # probably ANSI typo
        # Future/conditional verb forms
        r'\bencontrar\?([a-z]+)\b': r'would find\1',
        r'\bpodr\?([a-z]+)\b': r'could\1',
        r'\bdeber\?([a-z]+)\b': r'should\1',
        r'\bser\?([a-z]*)\b': r'would be\1',
        r'\bestar\?([a-z]*)\b': r'would be\1',
        r'\btendr\?([a-z]+)\b': r'would have\1',
        r'\bhabr\?([a-z]+)\b': r'would have\1',
        r'\bhar\?([a-z]*)\b': r'would do\1',
        r'\bdir\?([a-z]+)\b': r'would say\1',
        r'\bsabr\?([a-z]+)\b': r'would know\1',
        r'\bquerr\?([a-z]+)\b': r'would want\1',
        r'\bnecesitar\?([a-z]+)\b': r'would need\1',
        r'\bpermitir\?([a-z]+)\b': r'would allow\1',
        r'\brequerir\?([a-z]+)\b': r'would require\1',
        r'\bcausar\?([a-z]+)\b': r'would cause\1',
        r'\bdevolver\?([a-z]+)\b': r'would return\1',
        r'\brecorrer\?([a-z]+)\b': r'would traverse\1',
        r'\bdevolvi\?([a-z]+)\b': r'would return\1',
    }
    
    for pattern, repl in word_fixes.items():
        fixes.append((re.compile(pattern, re.IGNORECASE), repl))
    
    # === SPANISH PHRASE TRANSLATIONS ===
    # These replace common Spanish phrases in comments
    phrase_fixes = [
        # Common connector phrases  
        (r'\bNo se puede\b', 'Cannot'),
        (r'\bNo se pudo\b', 'Could not'),
        (r'\bNo se deben\b', 'Must not'),
        (r'\bNo se pueden\b', 'Cannot'),
        (r'\bNo se ha\b', 'Has not been'),
        (r'\bSe requiere\b', 'Is required'),
        (r'\bSe necesita\b', 'Is needed'),
        (r'\bSe debe\b', 'Must'),
        (r'\bSe puede\b', 'Can be'),
        (r'\bSe usa\b', 'Is used'),
        (r'\bSe utiliza\b', 'Is used'),
        (r'\bSe ejecuta\b', 'Is executed'),
        (r'\bSe asigna\b', 'Is assigned'),
        (r'\bSe crea\b', 'Is created'),
        (r'\bSe elimina\b', 'Is deleted'),
        (r'\bSe env[aíi]a\b', 'Is sent'),
        (r'\bSe recibe\b', 'Is received'),
        (r'\bSe procesa\b', 'Is processed'),
        (r'\bSe valida\b', 'Is validated'),
        (r'\bSe convierte\b', 'Is converted'),
        (r'\bSe guarda\b', 'Is saved'),
        (r'\bSe carga\b', 'Is loaded'),
        (r'\bSe libera\b', 'Is freed'),
        (r'\bSe inicializa\b', 'Is initialized'),
        (r'\bSe devuelve\b', 'Is returned'),
        (r'\bSe retorna\b', 'Is returned'),
        (r'\bSe encarga\b', 'Is responsible'),
        (r'\bHa sido\b', 'Has been'),
        (r'\bHan sido\b', 'Have been'),
        (r'\bDebe ser\b', 'Must be'),
        (r'\bPuede ser\b', 'May be'),
        (r'\bDebe tener\b', 'Must have'),
        (r'\bTiene que\b', 'Must'),
        (r'\bPor defecto\b', 'By default'),
        (r'\bA trav[eé]s de\b', 'Through'),
        (r'\bEn lugar de\b', 'Instead of'),
        (r'\bAntes de\b', 'Before'),
        (r'\bDespu[eé]s de\b', 'After'),
        (r'\bJunto con\b', 'Together with'),
        (r'\bEn paralelo\b', 'In parallel'),
        (r'\bEn secuencia\b', 'Sequentially'),
        (r'\bEn cascada\b', 'In cascade'),
        (r'\bDe forma\b', 'In a'),
        (r'\bDe manera\b', 'In a'),
        (r'\bA partir de\b', 'From'),
        (r'\bCon el fin de\b', 'In order to'),
        (r'\bPor lo tanto\b', 'Therefore'),
        (r'\bSin embargo\b', 'However'),
        (r'\bEs decir\b', 'That is'),
        (r'\bO sea\b', 'In other words'),
        (r'\bCon respecto a\b', 'Regarding'),
        (r'\bEn este caso\b', 'In this case'),
        (r'\bEn el futuro\b', 'In the future'),
        (r'\bdel sistema\b', 'of the system'),
        (r'\bdel usuario\b', 'of the user'),
        (r'\bdel modelo\b', 'of the model'),
        (r'\bdel c[oó]digo\b', 'of the code'),
        (r'\bdel servidor\b', 'of the server'),
        (r'\bdel cliente\b', 'of the client'),
        (r'\bdel componente\b', 'of the component'),
        (r'\bde los datos\b', 'of the data'),
        (r'\bde la aplicaci[oó]n\b', 'of the application'),
        (r'\bde la respuesta\b', 'of the response'),
        (r'\ben el sistema\b', 'in the system'),
        (r'\ben la base\b', 'in the database'),
        (r'\ben la memoria\b', 'in memory'),
        
        # Single words (lower priority - only in clear Spanish contexts)
        # These are applied inside comment lines only, so false positives are minimal
        (r'\bMan[eé]j(o|ar)\b', r'Handl\1'),
        (r'\bArchi[vV]o\b', 'File'), (r'\barchi[vV]o\b', 'file'),
        (r'\bCarpe[tT]a\b', 'Folder'), (r'\bcarpe[tT]a\b', 'folder'),
        (r'\bPant[aá]ll[aá]\b', 'Screen'), (r'\bpant[aá]ll[aá]\b', 'screen'),
        (r'\bVentan[aá]\b', 'Window'), (r'\bventan[aá]\b', 'window'),
        (r'\bCaptur[aá]\b', 'Capture'), (r'\bcaptur[aá]\b', 'capture'),
        (r'\bHerramient[aá]\b', 'Tool'), (r'\bherramient[aá]\b', 'tool'),
        (r'\bHerramientas\b', 'Tools'), (r'\bherramientas\b', 'tools'),
        (r'\bl[íi]ne[aá]\b', 'line'), (r'\bl[íi]ne[áa]s\b', 'lines'),
        (r'\bLlamad[aá]\b', 'Call'), (r'\bllamad[aá]\b', 'call'),
        (r'\bB[úu]squed[aá]\b', 'Search'), (r'\bb[úu]squed[aá]\b', 'search'),
        (r'\bCadena\b', 'String'), (r'\bcadena\b', 'string'),
        (r'\bColecci[oó]n\b', 'Collection'), (r'\bcolecci[oó]n\b', 'collection'),
        (r'\bList[áa]\b', 'List'), (r'\blist[áa]\b', 'list'),  # too broad?
        (r'\bRegistr[óo]\b', 'Record'),
        (r'\bContenid[óo]\b', 'Content'), (r'\bcontenid[óo]\b', 'content'),
        (r'\bForm[áa]t[óo]\b', 'Format'), (r'\bform[áa]t[óo]\b', 'format'),
        (r'\bBloqu[eé]\b', 'Block'), (r'\bbloqu[eé]\b', 'block'),
        (r'\bFluj[óo]\b', 'Stream'), (r'\bfluj[óo]\b', 'stream'),
        (r'\bTama[ñn]ó\b', 'Size'), (r'\btama[ñn]ó\b', 'size'),
        (r'\bSolicit[úu]d\b', 'Request'), (r'\bsolicit[úu]d\b', 'request'),
        (r'\bRespuest[áa]\b', 'Response'), (r'\brespuest[áa]\b', 'response'),
        (r'\bPropied[áa]d\b', 'Property'), (r'\bpropied[áa]d\b', 'property'),
        (r'\bPropiedades\b', 'Properties'), (r'\bpropiedades\b', 'properties'),
        (r'\bProp[óo]sit[óo]\b', 'Purpose'), (r'\bprop[óo]sit[óo]\b', 'purpose'),
        (r'\bMensaj[eé]\b', 'Message'), (r'\bmensaj[eé]\b', 'message'),
        (r'\bResult[áa]d[óo]\b', 'Result'), (r'\bresult[áa]d[óo]\b', 'result'),
        (r'\bResultados\b', 'Results'), (r'\bresultados\b', 'results'),
        (r'\bPar[áa]metr[óo]\b', 'Parameter'), (r'\bpar[áa]metr[óo]\b', 'parameter'),
        (r'\bPar[áa]metr[óo]s\b', 'Parameters'), (r'\bpar[áa]metr[óo]s\b', 'parameters'),
        (r'\bConfiguraci[óo]n\b', 'Configuration'), (r'\bconfiguraci[óo]n\b', 'configuration'),
        (r'\bEjecuci[óo]n\b', 'Execution'), (r'\bejecuci[óo]n\b', 'execution'),
        (r'\bValidaci[óo]n\b', 'Validation'), (r'\bvalidaci[óo]n\b', 'validation'),
        (r'\bConexi[óo]n\b', 'Connection'), (r'\bconexi[óo]n\b', 'connection'),
        (r'\bDescripci[óo]n\b', 'Description'), (r'\bdescripci[óo]n\b', 'description'),
        (r'\bSelecci[óo]n\b', 'Selection'), (r'\bselecci[óo]n\b', 'selection'),
        (r'\bPosici[óo]n\b', 'Position'), (r'\bposici[óo]n\b', 'position'),
        (r'\bInst[rR]ucci[óo]n\b', 'Instruction'), (r'\binst[rR]ucci[óo]n\b', 'instruction'),
        (r'\bInformaci[óo]n\b', 'Information'), (r'\binformaci[óo]n\b', 'information'),
        (r'\bPublicaci[óo]n\b', 'Publication'), (r'\bpublicaci[óo]n\b', 'publication'),
        (r'\bEvaluaci[óo]n\b', 'Evaluation'), (r'\bevaluaci[óo]n\b', 'evaluation'),
        (r'\bDefinici[óo]n\b', 'Definition'), (r'\bdefinici[óo]n\b', 'definition'),
        (r'\bGeneraci[óo]n\b', 'Generation'), (r'\bgeneraci[óo]n\b', 'generation'),
        (r'\bComparaci[óo]n\b', 'Comparison'), (r'\bcomparaci[óo]n\b', 'comparison'),
        (r'\bClasificaci[óo]n\b', 'Classification'), (r'\bclasificaci[óo]n\b', 'classification'),
        (r'\bComunicaci[óo]n\b', 'Communication'), (r'\bcomunicaci[óo]n\b', 'communication'),
        (r'\bSoluci[óo]n\b', 'Solution'), (r'\bsoluci[óo]n\b', 'solution'),
        (r'\bOpci[óo]n\b', 'Option'), (r'\bopci[óo]n\b', 'option'),
        (r'\bCondici[óo]n\b', 'Condition'), (r'\bcondici[óo]n\b', 'condition'),
        (r'\bRelaci[óo]n\b', 'Relation'), (r'\brelaci[óo]n\b', 'relation'),
        (r'\bDepuraci[óo]n\b', 'Debugging'), (r'\bdepuraci[óo]n\b', 'debugging'),
        (r'\bTraducci[óo]n\b', 'Translation'), (r'\btraducci[óo]n\b', 'translation'),
        (r'\bCompilaci[óo]n\b', 'Compilation'), (r'\bcompilaci[óo]n\b', 'compilation'),
        (r'\bInstalaci[óo]n\b', 'Installation'), (r'\binstalaci[óo]n\b', 'installation'),
        (r'\bRecuperaci[óo]n\b', 'Retrieval'), (r'\brecuperaci[óo]n\b', 'retrieval'),
        (r'\bSincronizaci[óo]n\b', 'Synchronization'), (r'\bsincronizaci[óo]n\b', 'synchronization'),
        (r'\bInicializaci[óo]n\b', 'Initialization'), (r'\binicializaci[óo]n\b', 'initialization'),
        (r'\bModificaci[óo]n\b', 'Modification'), (r'\bmodificaci[óo]n\b', 'modification'),
        (r'\bNotificaci[óo]n\b', 'Notification'), (r'\bnotificaci[óo]n\b', 'notification'),
        (r'\bIdentificaci[óo]n\b', 'Identification'), (r'\bidentificaci[óo]n\b', 'identification'),
        (r'\bSimplificaci[óo]n\b', 'Simplification'), (r'\bsimplificaci[óo]n\b', 'simplification'),
        (r'\bOptimizaci[óo]n\b', 'Optimization'), (r'\boptimizaci[óo]n\b', 'optimization'),
        (r'\bAsignaci[óo]n\b', 'Assignment'), (r'\basignaci[óo]n\b', 'assignment'),
        (r'\bDelegaci[óo]n\b', 'Delegation'), (r'\bdelegaci[óo]n\b', 'delegation'),
        (r'\bReconstrucci[óo]n\b', 'Reconstruction'), (r'\breconstrucci[óo]n\b', 'reconstruction'),
        (r'\bExpansi[óo]n\b', 'Expansion'), (r'\bexpansi[óo]n\b', 'expansion'),
        (r'\bSerializaci[óo]n\b', 'Serialization'), (r'\bserializaci[óo]n\b', 'serialization'),
        (r'\bHidrataci[óo]n\b', 'Hydration'), (r'\bhidrataci[óo]n\b', 'hydration'),
        (r'\bExtensi[óo]n\b', 'Extension'), (r'\bextensi[óo]n\b', 'extension'),
        (r'\bConversi[óo]n\b', 'Conversion'), (r'\bconversi[óo]n\b', 'conversion'),
        
        # More specific words
        (r'\bDetecci[óo]n\b', 'Detection'), (r'\bdetecci[óo]n\b', 'detection'),
        (r'\bAprobaci[óo]n\b', 'Approval'), (r'\baprobaci[óo]n\b', 'approval'),
        (r'\bVerificaci[óo]n\b', 'Verification'), (r'\bverificaci[óo]n\b', 'verification'),
        (r'\bAutenticaci[óo]n\b', 'Authentication'),
        (r'\bAncla\b', 'Anchor'), (r'\bancla\b', 'anchor'),
        (r'\bAnclaje\b', 'Anchoring'), (r'\banclaje\b', 'anchoring'),
        (r'\bNod[óo]\b', 'Node'), (r'\bnod[óo]\b', 'node'), (r'\bNod[óo]s\b', 'Nodes'), (r'\bnod[óo]s\b', 'nodes'),
        (r'\bArist[áa]\b', 'Edge'), (r'\barist[áá]\b', 'edge'), (r'\bArist[áa]s\b', 'Edges'), (r'\barist[áa]s\b', 'edges'),
        (r'\bGr[áa]f[óo]\b', 'Graph'), (r'\bgr[áa]f[óo]\b', 'graph'),
        (r'\bPizarr[áa]\b', 'Blackboard'), (r'\bpizarr[áa]\b', 'blackboard'),
        (r'\bVecin[óo]\b', 'Neighbor'), (r'\bvecin[óó]\b', 'neighbor'),
        (r'\bVecinos\b', 'Neighbors'), (r'\bvecinos\b', 'neighbors'),
        (r'\bVecindario\b', 'Neighborhood'), (r'\bvecindario\b', 'neighborhood'),
        (r'\bComunid[áa]d\b', 'Community'), (r'\bcomunid[áa]d\b', 'community'),
        (r'\bComunidades\b', 'Communities'), (r'\bcomunidades\b', 'communities'),
        
        # Specific Spanish verbs often used in comments
        (r'\bSobrescrib[eé]\b', 'Overwrites'), (r'\bsobrescrib[eé]\b', 'overwrites'),
        (r'\bSobrescribir\b', 'Overwrite'), (r'\bsobrescribir\b', 'overwrite'),
        (r'\bRealiz[áa]\b', 'Performs'), (r'\brealiz[áa]\b', 'performs'),
        (r'\bRealizar\b', 'Perform'), (r'\brealizar\b', 'perform'),
        (r'\bDispar[áa]\b', 'Triggers'), (r'\bdispar[áa]\b', 'triggers'),
        (r'\bDisparar\b', 'Trigger'), (r'\bdisparar\b', 'trigger'),
        (r'\bDespu[eé]s\b', 'After'), (r'\bdespu[eé]s\b', 'after'),
        (r'\bLanz[áa]\b', 'Launches'), (r'\blanz[áa]\b', 'launches'),
        (r'\bLanzar\b', 'Launch'), (r'\blanzar\b', 'launch'),
        (r'\bAsegur[áa]\b', 'Ensures'), (r'\basegur[áa]\b', 'ensures'),
        (r'\bAsegurar\b', 'Ensure'), (r'\basegurar\b', 'ensure'),
        (r'\bComprueb[áa]\b', 'Checks'), (r'\bcomprueb[áa]\b', 'checks'),
        (r'\bComprobar\b', 'Check'), (r'\bcomprobar\b', 'check'),
        (r'\bVerific[áa]\b', 'Verifies'), (r'\bverific[áá]\b', 'verifies'),
        (r'\bVerificar\b', 'Verify'), (r'\bverificar\b', 'verify'),
        (r'\bManej[áa]\b', 'Handles'), (r'\bmanej[áa]\b', 'handles'),
        (r'\bManejar\b', 'Handle'), (r'\bmanejar\b', 'handle'),
        (r'\bSoport[áa]\b', 'Supports'), (r'\bsoport[áa]\b', 'supports'),
        (r'\bSoportar\b', 'Support'), (r'\bsoportar\b', 'support'),
        (r'\bPermit[ée]\b', 'Allows'), (r'\bpermit[ée]\b', 'allows'),
        (r'\bPermitir\b', 'Allow'), (r'\bpermitir\b', 'allow'),
        (r'\bRequier[ée]\b', 'Requires'), (r'\brequier[ée]\b', 'requires'),
        (r'\bRequerir\b', 'Require'), (r'\brequerir\b', 'require'),
        (r'\bRetorn[áá]\b', 'Returns'), (r'\bretorn[áá]\b', 'returns'),
        (r'\bRetornar\b', 'Return'), (r'\bretornar\b', 'return'),
        (r'\bDevuelv[ée]\b', 'Returns'), (r'\bdevuelv[ée]\b', 'returns'),
        (r'\bDevolver\b', 'Return'), (r'\bdevolver\b', 'return'),
        (r'\bContien[ée]\b', 'Contains'), (r'\bcontien[ée]\b', 'contains'),
        (r'\bContener\b', 'Contain'), (r'\bcontener\b', 'contain'),
        (r'\bGener[áa]\b', 'Generates'), (r'\bgener[áa]\b', 'generates'),
        (r'\bGenerar\b', 'Generate'), (r'\bgenerar\b', 'generate'),
        (r'\bEjecut[áa]\b', 'Executes'), (r'\bejecut[áa]\b', 'executes'),
        (r'\bEjecutar\b', 'Execute'), (r'\bejecutar\b', 'execute'),
        (r'\bProces[áa]\b', 'Processes'), (r'\bproces[áa]\b', 'processes'),
        (r'\bProcesar\b', 'Process'), (r'\bprocesar\b', 'process'),
        (r'\bValid[áa]\b', 'Validates'), (r'\bvalid[áa]\b', 'validates'),
        (r'\bValidar\b', 'Validate'), (r'\bvalidar\b', 'validate'),
        (r'\bConviert[ée]\b', 'Convert'), (r'\bconviert[ée]\b', 'convert'),
        (r'\bConvertir\b', 'Convert'), (r'\bconvertir\b', 'convert'),
        (r'\bCarg[áa]\b', 'Loads'), (r'\bcarg[áa]\b', 'loads'),
        (r'\bCargar\b', 'Load'), (r'\bcargar\b', 'load'),
        (r'\bGuard[áá]\b', 'Saves'), (r'\bguard[áá]\b', 'saves'),
        (r'\bGuardar\b', 'Save'), (r'\bguardar\b', 'save'),
        (r'\bEnvi[áa]\b', 'Sends'), (r'\benvi[áa]\b', 'sends'),
        (r'\bEnviar\b', 'Send'), (r'\benviar\b', 'send'),
        (r'\bRecib[ée]\b', 'Receives'), (r'\brecib[ée]\b', 'receives'),
        (r'\bRecibir\b', 'Receive'), (r'\brecibir\b', 'receive'),
        (r'\bElimin[áa]\b', 'Deletes'), (r'\belimin[áa]\b', 'deletes'),
        (r'\bEliminar\b', 'Delete'), (r'\beliminar\b', 'delete'),
        (r'\bCopia\b', 'Copy'), (r'\bcopia\b', 'copy'),
        (r'\bCopiar\b', 'Copy'), (r'\bcopiar\b', 'copy'),
        (r'\bLimpi[áa]\b', 'Clears'), (r'\blimpi[áa]\b', 'clears'),
        (r'\bLimpiar\b', 'Clear'), (r'\blimpiar\b', 'clear'),
        (r'\bLliber[áa]\b', 'Frees'),  # typo
        (r'\bLiber[áa]\b', 'Frees'), (r'\bliber[áa]\b', 'frees'),
        (r'\bLiberar\b', 'Free'), (r'\bliberar\b', 'free'),
        (r'\bInicializ[áa]\b', 'Initializes'), (r'\binicializ[áa]\b', 'initializes'),
        (r'\bInicializar\b', 'Initialize'), (r'\binicializar\b', 'initialize'),
        
        # Adverbs and adjectives  
        (r'\bCorrect[áa]mente\b', 'Correctly'), (r'\bcorrect[áa]mente\b', 'correctly'),
        (r'\bAutom[áa]ticamente\b', 'Automatically'), (r'\bautom[áa]ticamente\b', 'automatically'),
        (r'\bManualmente\b', 'Manually'), (r'\bmanualmente\b', 'manually'),
        (r'\bDirect[áa]mente\b', 'Directly'), (r'\bdirect[áa]mente\b', 'directly'),
        (r'\bF[áa]cilmente\b', 'Easily'), (r'\bf[áa]cilmente\b', 'easily'),
        (r'\bPrincipalmente\b', 'Mainly'), (r'\bprincipalmente\b', 'mainly'),
        (r'\bGeneralmente\b', 'Generally'), (r'\bgeneralmente\b', 'generally'),
        (r'\bNormalmente\b', 'Normally'), (r'\bnormalmente\b', 'normally'),
        (r'\bEspecialmente\b', 'Especially'), (r'\bespecialmente\b', 'especially'),
        (r'\bExactamente\b', 'Exactly'), (r'\bexactamente\b', 'exactly'),
        (r'\bAproximadamente\b', 'Approximately'), (r'\baproximadamente\b', 'approximately'),
        (r'\bCompletamente\b', 'Completely'), (r'\bcompletamente\b', 'completely'),
        (r'\bTotalmente\b', 'Totally'), (r'\btotalmente\b', 'totally'),
        (r'\bAbsolutamente\b', 'Absolutely'), (r'\babsolutamente\b', 'absolutely'),
        (r'\bRelativamente\b', 'Relatively'), (r'\brelativamente\b', 'relatively'),
        (r'\bNuevamente\b', 'Again'), (r'\bnuevamente\b', 'again'),
        
        # Specific
        (r'\bsentido\b', 'direction'),  # often means direction/sense
        (r'\bpaso anterior\b', 'previous step'),
        (r'\bel primer paso\b', 'the first step'),
        (r'\bpaso siguiente\b', 'next step'),
        (r'\bEs due[ñn]o\b', 'Owns'), (r'\bes due[ñn]o\b', 'owns'),
    ]
    
    for pattern, repl in phrase_fixes:
        fixes.append((re.compile(pattern, re.IGNORECASE), repl))
    
    return fixes


FIXES = make_fix_map()


def is_comment_line(line):
    stripped = line.strip()
    return stripped.startswith('//') or stripped.startswith('{') or stripped.startswith('(*')


def should_skip(line):
    """Skip lines that are clearly English headers."""
    lower = line.strip().lower()
    skippable = ['mit license', 'copyright (c)', 'permission is hereby',
                 'the software', 'without warranty', 'furnished to do so',
                 'author:', 'email:', 'telegram:', 'linkedin:', 'github:',
                 'social networks:', 'name: gustavo', 'youtube:',
                 'interface', 'implementation']
    return any(s in lower for s in skippable)


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
        if not is_comment_line(line):
            continue
        if should_skip(line):
            continue
        if not line.strip():  # empty
            continue
        
        # Check if comment has Spanish-looking content
        stripped = line.strip()
        has_spanish = False
        for indicator in ['?', 'á', 'é', 'í', 'ó', 'ú', 'ñ', 'Á', 'É', 'Í', 'Ó', 'Ú', 'Ñ',
                           'Solo ', 'Sobrescrib', 'Realiz', 'Dispar', 'Lanz', 'Asegur',
                           'Comprueb', 'Manej', 'Soport', 'Permit', 'Requier', 'Retorn',
                           'Devolv', 'Contien', 'Gener', 'Ejecut', 'Proces', 'Conviert',
                           'Carg', 'Guard', 'Envi', 'Recib', 'Elimin', 'Copi', 'Limpi',
                           'Liber', 'Inicializ']:
            if indicator in stripped:
                has_spanish = True
                break
        
        if not has_spanish:
            continue
        
        original = line
        for pattern, replacement in FIXES:
            try:
                line = pattern.sub(replacement, line)
            except:
                pass  # skip patterns that don't compile
        
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
    
    print(f'\nTotal: {total_changes} fixes in {total_files} files')


if __name__ == '__main__':
    main()
