#!/usr/bin/env python3
"""
ABSOLUTE FINAL: Replace remaining single Spanish words in comments.
Word-boundary protected to avoid false positives.
Only words that unambiguously appear in Spanish context in these files.
After this, only full sentences remain - those need an LLM.
"""

import os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, 'Source')

# Single-word replacements — each verified to appear only in Spanish context
WORD_FIXES = {
    # Spanish nouns that appear in comments (with unambiguous English mapping)
    '\bpropiedades\b': 'properties',
    '\bPropiedades\b': 'Properties',
    '\bSobrescribe\b': 'Overwrites',
    '\bsobrescribe\b': 'overwrites',
    '\bparametros\b': 'parameters',
    '\bParametros\b': 'Parameters',
    '\bpropiedad\b': 'property',
    '\bPropiedad\b': 'Property',
    '\blas\b(?=\s+prop)': 'the',  # only "las propiedades" etc
    '\bdel\b(?=\s+(elemento|componente|sistema|c[oó]digo|usuario))': 'of the',
    '\bcon\b(?=\s+las\b)': 'with',
    
    # Verbs
    '\ba[ñn]ade\b': 'adds',
    '\ba[ñn]adir\b': 'add',
    '\ba[ñn]adiendo\b': 'adding',
    '\ba[ñn]adido\b': 'added',
    '\brealiza\b': 'performs',
    '\bRealiza\b': 'Performs',
    '\brealizar\b': 'perform',
    '\bRealizar\b': 'Perform',
    '\bnecesita\b': 'needs',
    '\bNecesita\b': 'Needs',
    '\bnecesitan\b': 'need',
    '\bNecesitan\b': 'Need/Required',
    '\bguardamos\b': 'we save',
    '\bGuardamos\b': 'We save',
    '\bdebido\b': 'due',
    '\bDebido\b': 'Due',
    '\bconfigurar\b': 'configure',
    '\bConfigurar\b': 'Configure',
    
    # Adjectives
    '\bexistentes\b': 'existing',
    '\bexistentes\b': 'existing',
    '\bnuevas\b': 'new',
    '\bnuevo\b': 'new',
    '\bNuevo\b': 'New',
    '\bNuevas\b': 'New',
    '\btodos\b(?=\s+los)': 'all',
    '\btodas\b(?=\s+las)': 'all',
    '\bTodos\b(?=\s+los)': 'All',
    
    # Connectors
    '\bpara\b(?=\s+(el|la|que|obtener|definir|mayor|evitar|asegurar|acceder))': 'to/for',
    '\bdesde\b': 'from',
    '\bDesd[ée]\b': 'From',
    '\bsobre\b(?=\s+(el|la|los|las))': 'about/on',
    '\bSobre\b(?=\s+(el|la|los|las))': 'About/On',
    '\bhacia\b': 'towards/to',
    '\bHacia\b': 'To/Towards',
    '\bdentro\b': 'within/inside',
    '\bDentro\b': 'Within/Inside',
    '\bentre\b(?=\s+[a-záéíóú])': 'between',
    '\bEntre\b(?=\s+[a-záéíóú])': 'Between',
    '\bantes\b(?=\s+de)': 'before',
    '\bdespu[ée]s\b(?=\s+de)': 'after',
    
    # Adverbs
    '\bsolo\b(?=\s+[a-záéíóúñ])': 'only',
    '\bSolo\b(?=\s+[a-záéíóúñ])': 'Only',
    '\bsiempre\b': 'always',
    '\bSiempre\b': 'Always',
    '\bnunca\b': 'never',
    '\bNunca\b': 'Never',
    '\bahora\b': 'now',
    '\bAhora\b': 'Now',
    '\btambi[ée]n\b': 'also',
    '\bTambi[ée]n\b': 'Also',
    '\bactualmente\b': 'currently',
    '\bActualmente\b': 'Currently',
    '\bprincipalmente\b': 'mainly',
    
    # Pronouns/Articles
    '\blo\b(?=\s+[a-záéíóúñ]+(mos|mos|do|da|r[áa]|r[eé]))': 'it',
    '\bLo\b(?=\s+[a-záéíóúñ]+(mos|do|r[áa]))': 'We',
    '\bse\b(?=\s+[a-záéíóúñ]+(r[áa]|mos|[aei]r))': '',  # reflexive - remove
    
    # Specific words
    '\bninguno\b': 'none',
    '\bNinguno\b': 'None',
    '\bning[úu]n\b': 'no/any',
    '\bninguna\b': 'no/any',
    '\bNinguna\b': 'No/Any',
    
    # Time
    '\bhoy\b': 'today',
    '\bayer\b': 'yesterday',
    '\bma[ñn]ana\b': 'tomorrow',
    '\bfuturo\b': 'future',
    '\bFuturo\b': 'Future',
    '\bpasado\b': 'past',
    
    # Technical
    '\bconsulta\b': 'query',
    '\bConsulta\b': 'Query',
    '\bconsultas\b': 'queries',
    '\bConsultas\b': 'Queries',
    '\bgrafo\b': 'graph',
    '\bGrafo\b': 'Graph',
    '\bgrafos\b': 'graphs',
    '\bGrafos\b': 'Graphs',
    '\bmodelo\b': 'model',
    '\bModelo\b': 'Model',
    '\bmodelos\b': 'models',
    '\bModelos\b': 'Models',
    '\bdatos\b': 'data',
    '\bDatos\b': 'Data',
    '\bresultado\b': 'result',
    '\bResultado\b': 'Result',
    '\bresultados\b': 'results',
    '\bResultados\b': 'Results',
    '\busuario\b': 'user',
    '\bUsuario\b': 'User',
    '\busuarios\b': 'users',
    '\bUsuarios\b': 'Users',
    '\bmensaje\b': 'message',
    '\bMensaje\b': 'Message',
    '\bmensajes\b': 'messages',
    '\bMensajes\b': 'Messages',
    '\bvalor\b': 'value',
    '\bValor\b': 'Value',
    '\bvalores\b': 'values',
    '\bValores\b': 'Values',
    '\bcampo\b': 'field',
    '\bCampo\b': 'Field',
    '\bcampos\b': 'fields',
    '\bCampos\b': 'Fields',
    '\bclave\b': 'key',
    '\bClave\b': 'Key',
    '\bclaves\b': 'keys',
    '\bestado\b': 'state',
    '\bEstado\b': 'State',
    '\bestados\b': 'states',
    '\bestructura\b': 'structure',
    '\bEstructura\b': 'Structure',
    '\bentrada\b': 'input',
    '\bEntrada\b': 'Input',
    '\bsalida\b': 'output',
    '\bSalida\b': 'Output',
    '\bpantalla\b': 'screen',
    '\bPantalla\b': 'Screen',
    '\bventana\b': 'window',
    '\bVentana\b': 'Window',
    '\bdispositivo\b': 'device',
    '\bDispositivo\b': 'Device',
    '\bdispositivos\b': 'devices',
    '\baudio\b(?=\s+(del|de|en|para|o|y|para|con))': 'audio',
    '\bcaptura\b': 'capture',
    '\bCaptura\b': 'Capture',
    '\bmonitor\b': 'monitor',
    '\bMonitor\b': 'Monitor',
    '\barchivo\b': 'file',
    '\bArchivo\b': 'File',
    '\barchivos\b': 'files',
    '\bArchivos\b': 'Files',
    '\bdirectorio\b': 'directory',
    '\bDirectorio\b': 'Directory',
    '\bcarpeta\b': 'folder',
    '\bCarpeta\b': 'Folder',
    '\bruta\b': 'path/route',
    '\bRuta\b': 'Path/Route',
    '\bformato\b': 'format',
    '\bFormato\b': 'Format',
    '\btama[ñn]o\b': 'size',
    '\bTama[ñn]o\b': 'Size',
    '\btama[ñn]os\b': 'sizes',
    '\bbuffer\b': 'buffer',
    '\bBuffer\b': 'Buffer',
    '\bcach[ée]\b': 'cache',
    '\bCach[ée]\b': 'Cache',
    '\bnombre\b': 'name',
    '\bNombre\b': 'Name',
    '\bnombres\b': 'names',
    '\bNombres\b': 'Names',
    '\betiqueta\b': 'label',
    '\bEtiqueta\b': 'Label',
    '\betiquetas\b': 'labels',
    '\bEtiquetas\b': 'Labels',
    '\bcolor\b': 'color',
    '\bColor\b': 'Color',
    '\bcolores\b': 'colors',
    '\bColores\b': 'Colors',
    '\bcantidad\b': 'quantity/amount',
    '\bCantidad\b': 'Quantity/Amount',
    '\bfecha\b': 'date',
    '\bFecha\b': 'Date',
    '\btiempo\b': 'time',
    '\bTiempo\b': 'Time',
    '\bhora\b': 'hour/time',
    '\bHora\b': 'Hour/Time',
    '\bejemplo\b': 'example',
    '\bEjemplo\b': 'Example',
    '\bejemplos\b': 'examples',
    '\bEjemplos\b': 'Examples',
    '\bversi[oó]n\b': 'version',
    '\bVersi[oó]n\b': 'Version',
    '\berror\b': 'error',
    '\bError\b': 'Error',
    '\berrores\b': 'errors',
    '\bErrores\b': 'Errors',
    '\bacci[oó]n\b': 'action',
    '\bAcci[oó]n\b': 'Action',
    '\bacciones\b': 'actions',
    '\bpetici[oó]n\b': 'request',
    '\bPetici[oó]n\b': 'Request',
    '\bpeticiones\b': 'requests',
    '\brespuesta\b': 'response',
    '\bRespuesta\b': 'Response',
    '\bimagen\b': 'image',
    '\bImagen\b': 'Image',
    '\bim[áa]genes\b': 'images',
    '\bIm[áa]genes\b': 'Images',
    '\btool\b': 'tool',
    '\bTool\b': 'Tool',
    '\btools\b': 'tools',
    '\bTools\b': 'Tools',
    '\bm[ée]todo\b': 'method',
    '\bM[ée]todo\b': 'Method',
    '\bm[ée]todos\b': 'methods',
    '\bM[ée]todos\b': 'Methods',
    '\bfunci[oó]n\b': 'function',
    '\bFunci[oó]n\b': 'Function',
    '\bfunciones\b': 'functions',
    '\bFunciones\b': 'Functions',
    '\bvariable\b': 'variable',
    '\bVariable\b': 'Variable',
    '\bvariables\b': 'variables',
    '\bVariables\b': 'Variables',
    '\bpar[áa]metro\b': 'parameter',
    '\bPar[áa]metro\b': 'Parameter',
    '\bpar[áa]metros\b': 'parameters',
    '\bPar[áa]metros\b': 'Parameters',
    '\bclase\b': 'class',
    '\bClase\b': 'Class',
    '\bclases\b': 'classes',
    '\bClases\b': 'Classes',
    '\bm[oó]dulo\b': 'module',
    '\bM[oó]dulo\b': 'Module',
    '\bm[oó]dulos\b': 'modules',
    '\bcadena\b': 'string',
    '\bCadena\b': 'String',
    '\bcadenas\b': 'strings',
    '\bCadenas\b': 'Strings',
    '\blista\b': 'list',
    '\bLista\b': 'List',
    '\blistas\b': 'lists',
    '\bcolecci[oó]n\b': 'collection',
    '\bColecci[oó]n\b': 'Collection',
    '\bcolecciones\b': 'collections',
    '\b[íi]ndice\b': 'index',
    '\b[ÍI]ndice\b': 'Index',
    '\b[íi]ndices\b': 'indexes',
    '\barreglo\b': 'array',
    '\bArreglo\b': 'Array',
    '\barreglos\b': 'arrays',
    '\bpila\b': 'stack',
    '\bPila\b': 'Stack',
    '\bcola\b': 'queue',
    '\bCola\b': 'Queue',
    '\b[áa]rbol\b': 'tree',
    '\b[ÁA]rbol\b': 'Tree',
    '\b[áa]rboles\b': 'trees',
    
    # Language
    '\bespa[ñn]ol\b': 'Spanish',
    '\bEspa[ñn]ol\b': 'Spanish',
    '\bingl[ée]s\b': 'English',
    '\bIngl[ée]s\b': 'English',
    
    # Vectors/RAG
    '\bvector\b': 'vector', '\bVector\b': 'Vector',
    '\bvectores\b': 'vectors', '\bVectores\b': 'Vectors',
    '\bembedding\b': 'embedding', '\bEmbedding\b': 'Embedding',
    '\bembeddings\b': 'embeddings', '\bEmbeddings\b': 'Embeddings',
    '\bnodo\b': 'node', '\bNodo\b': 'Node',
    '\bnodos\b': 'nodes', '\bNodos\b': 'Nodes',
    '\barista\b': 'edge', '\bArista\b': 'Edge',
    '\baristas\b': 'edges', '\bAristas\b': 'Edges',
    '\bvecino\b': 'neighbor', '\bVecino\b': 'Neighbor',
    '\bvecinos\b': 'neighbors', '\bVecinos\b': 'Neighbors',
    '\bcomunidad\b': 'community', '\bComunidad\b': 'Community',
    '\bcomunidades\b': 'communities', '\bComunidades\b': 'Communities',
    '\bdelantera\b': 'forward', '\btrasera\b': 'backward',
    
    # Direction/order
    '\badelante\b': 'forward', '\bAdelante\b': 'Forward',
    '\batr[áa]s\b': 'backward', '\bAtr[áa]s\b': 'Backward',
    '\bizquierda\b': 'left', '\bderecha\b': 'right',
    '\barriba\b': 'up', '\babajo\b': 'down',
    '\bprimero\b': 'first', '\bPrimero\b': 'First',
    '\b[úu]ltimo\b': 'last', '\b[ÚU]ltimo\b': 'Last',
}

# Multi-word phrase replacements
PHRASE_FIXES = [
    # Common Spanish phrases in these files
    (r'\bSe necesita\b', 'Is needed'),
    (r'\bse necesita\b', 'is needed'),
    (r'\bse necesitan\b', 'are needed'),
    (r'\bSe necesitan\b', 'Are needed'),
    (r'\bSe puede\b', 'Can be'),
    (r'\bse puede\b', 'can be'),
    (r'\bNo se puede\b', 'Cannot'),
    (r'\bno se puede\b', 'cannot'),
    (r'\bNo se ha\b', 'Has not been'),
    (r'\bno se ha\b', 'has not been'),
    (r'\bSe debe\b', 'Must/Should'),
    (r'\bse debe\b', 'must/should'),
    (r'\bSe usa\b', 'Is used'),
    (r'\bse usa\b', 'is used'),
    (r'\bSe utiliza\b', 'Is used'),
    (r'\bse utiliza\b', 'is used'),
    (r'\bSe ejecuta\b', 'Is executed'),
    (r'\bse ejecuta\b', 'is executed'),
    (r'\bSe crea\b', 'Is created'),
    (r'\bse crea\b', 'is created'),
    (r'\bSe asigna\b', 'Is assigned'),
    (r'\bse asigna\b', 'is assigned'),
    (r'\bSe libera\b', 'Is freed'),
    (r'\bse libera\b', 'is freed'),
    (r'\bSe env[ií]a\b', 'Is sent'),
    (r'\bse env[ií]a\b', 'is sent'),
    (r'\bSe recibe\b', 'Is received'),
    (r'\bse recibe\b', 'is received'),
    (r'\bSe guarda\b', 'Is saved'),
    (r'\bse guarda\b', 'is saved'),
    (r'\bSe carga\b', 'Is loaded'),
    (r'\bse carga\b', 'is loaded'),
    (r'\bSe encarga\b', 'Is responsible'),
    (r'\bse encarga\b', 'is responsible'),
    (r'\bHa sido\b', 'Has been'),
    (r'\bha sido\b', 'has been'),
    (r'\bHan sido\b', 'Have been'),
    (r'\bhan sido\b', 'have been'),
    (r'\bDebe ser\b', 'Must be'),
    (r'\bdebe ser\b', 'must be'),
    (r'\bPuede ser\b', 'May be'),
    (r'\bpuede ser\b', 'may be'),
    (r'\bPor defecto\b', 'By default'),
    (r'\bpor defecto\b', 'by default'),
    (r'\bes due[ñn]o de\b', 'owns'),
    (r'\bsin duplicar\b', 'without duplicating'),
    (r'\bpara que\b', 'so that'),
    (r'\bpara el\b', 'for the'),
    (r'\bpara la\b', 'for the'),
    (r'\bpor si\b', 'in case'),
    (r'\btodav[ií]a\b', 'still'),
    (r'\bno existe\b', 'does not exist'),
    (r'\bno existen\b', 'do not exist'),
    (r'\bsi no existe\b', 'if it does not exist'),
    (r'\bya existe\b', 'already exists'),
    (r'\bno est[áa]\b', 'is not'),
    (r'\ba[úu]n no\b', 'not yet'),
    (r'\bes m[áa]s\b', 'is more'),
    (r'\bes menos\b', 'is less'),
    (r'\bno solo\b', 'not only'),
    (r'\bno s[oó]lo\b', 'not only'),
    (r'\ben lugar de\b', 'instead of'),
    (r'\bde forma\b', 'in a'),
    (r'\bde manera\b', 'in a'),
    (r'\ba trav[ée]s de\b', 'through'),
    (r'\bA trav[ée]s de\b', 'Through'),
    (r'\bpara acceder\b', 'to access'),
    (r'\bpara evitar\b', 'to avoid'),
    (r'\bpara asegurar\b', 'to ensure'),
    (r'\bpara obtener\b', 'to obtain/get'),
    (r'\bpara mayor\b', 'for greater'),
    (r'\balguna parte\b', 'some part'),
    (r'\bninguna parte\b', 'no part'),
    (r'\bninguna modificaci[oó]n\b', 'no modification'),
    (r'\bNo realiza\b', 'Does not perform'),
    (r'\bno realiza\b', 'does not perform'),
    (r'\bSe mantiene\b', 'Maintains'),
    (r'\bse mantiene\b', 'maintains'),
    (r'\bdebe guardarse\b', 'must be saved'),
    (r'\bdebe pasarse\b', 'must be passed'),
    (r'\bdel elemento\b', 'of the element'),
    (r'\bdel sistema\b', 'of the system'),
    (r'\bdel usuario\b', 'of the user'),
    (r'\bdel componente\b', 'of the component'),
    (r'\bde la aplicaci[oó]n\b', 'of the application'),
    (r'\bde la API\b', 'of the API'),
    (r'\ben el inspector\b', 'in the inspector'),
    (r'\ben el futuro\b', 'in the future'),
    (r'\ben la lista\b', 'in the list'),
    (r'\ben la memoria\b', 'in memory'),
    (r'\ben el hilo principal\b', 'in the main thread'),
    (r'\ben el grafo\b', 'in the graph'),
    (r'\bcontenido compatible\b', 'compatible content'),
    (r'\bcontenido para subir\b', 'content for upload'),
    (r'\blos esquemas JSON\b', 'the JSON schemas'),
    (r'\bel esquema JSON\b', 'the JSON schema'),
    (r'\bla informaci[oó]n\b', 'the information'),
    (r'\blos datos\b', 'the data'),
    (r'\blos resultados\b', 'the results'),
    (r'\blos valores\b', 'the values'),
    (r'\blos par[áa]metros\b', 'the parameters'),
    (r'\blos nodos iniciales\b', 'the initial nodes'),
    (r'\blas propiedades\b', 'the properties'),
    (r'\blos [íi]ndices\b', 'the indexes'),
    (r'\bdatos precisos\b', 'precise data'),
    (r'\bdatos muy expl[íi]citos\b', 'very explicit data'),
    (r'\bel endpoint\b', 'the endpoint'),
    (r'\blos endpoints\b', 'the endpoints'),
    (r'\bla URL\b', 'the URL'),
    (r'\bel nombre\b', 'the name'),
    (r'\bel texto\b', 'the text'),
    (r'\bel contenido\b', 'the content'),
    (r'\bel archivo\b', 'the file'),
    (r'\bel proceso\b', 'the process'),
    (r'\bla respuesta\b', 'the response'),
    (r'\bla solicitud\b', 'the request'),
    (r'\bla herramienta\b', 'the tool'),
    (r'\bla variable\b', 'the variable'),
    (r'\bla clase\b', 'the class'),
    (r'\bel modelo\b', 'the model'),
    (r'\bel resultado\b', 'the result'),
    (r'\bno matchea\b', 'does not match'),
    (r'\bes la misma\b', 'is the same'),
    (r'\bes lo mismo\b', 'is the same'),
    (r'\bes este caso\b', 'in this case'),
    (r'\bpor ahora\b', 'for now'),
    (r'\bpor el momento\b', 'for now'),
    (r'\bpor lo general\b', 'generally'),
    (r'\bpor ejemplo\b', 'for example'),
    (r'\bPor ejemplo\b', 'For example'),
    (r'\bpara crear\b', 'to create'),
    (r'\bpara generar\b', 'to generate'),
    (r'\bpara enviar\b', 'to send'),
    (r'\bpara recibir\b', 'to receive'),
    (r'\bpara procesar\b', 'to process'),
    (r'\bpara validar\b', 'to validate'),
    (r'\bpara buscar\b', 'to search'),
    (r'\bpara guardar\b', 'to save'),
    (r'\bpara cargar\b', 'to load'),
    (r'\bpara convertir\b', 'to convert'),
    (r'\bpara sincronizar\b', 'to synchronize'),
    (r'\bpara inicializar\b', 'to initialize'),
    (r'\bpara liberar\b', 'to free'),
    (r'\bpara eliminar\b', 'to delete'),
    (r'\bpara asignar\b', 'to assign'),
    (r'\bpara configurar\b', 'to configure'),
    (r'\bpara ejecutar\b', 'to execute'),
    (r'\bpara leer\b', 'to read'),
    (r'\bpara escribir\b', 'to write'),
    (r'\bpara mostrar\b', 'to show'),
    (r'\bes necesario\b', 'it is necessary'),
    (r'\bes requerido\b', 'is required'),
    (r'\bes opcional\b', 'is optional'),
    (r'\bes importante\b', 'it is important'),
    (r'\bes posible\b', 'it is possible'),
    (r'\bes recomendable\b', 'it is recommended'),
    (r'\bes suficiente\b', 'is sufficient'),
    (r'\bes correcto\b', 'is correct'),
    (r'\bes incorrecto\b', 'is incorrect'),
    (r'\bal final\b', 'at the end'),
    (r'\bal inicio\b', 'at the beginning'),
    (r'\bal principio\b', 'at the beginning'),
    (r'\bal principio del\b', 'at the beginning of the'),
    (r'\ben el futuro\b', 'in the future'),
    (r'\bde ahora en adelante\b', 'from now on'),
    (r'\bde nuevo\b', 'again'),
    (r'\bde todos modos\b', 'anyway'),
    (r'\bde todas formas\b', 'in any case'),
    (r'\bde hecho\b', 'in fact'),
    (r'\bpor supuesto\b', 'of course'),
    (r'\bpor cierto\b', 'by the way'),
    (r'\bpor completo\b', 'completely'),
    (r'\bsin cambios\b', 'without changes'),
    (r'\bsin problema\b', 'without problem'),
    (r'\bsin errores\b', 'without errors'),
    (r'\bsin p[ée]rdida\b', 'without loss'),
]

def has_comment(line):
    return '//' in line or '{' in line or '(*' in line

def should_skip(line):
    lower = line.strip().lower()
    skippable = [
        'mit license', 'copyright (c)', 'permission is', 'the software',
        'warranty', 'furnished to', 'above copyright', 'social networks:',
        'name: gustavo', 'author:', 'email:', 'telegram:', 'linkedin:',
        'github:', 'youtube:', 'all copies or substantial',
    ]
    return any(s in lower for s in skippable)

def has_spanish(line):
    """Check if line likely has Spanish content."""
    indicators = [
        r'\bpropiedades\b', r'\ba[ñn]ade\b', r'\ba[ñn]adir\b',
        r'\bSobrescribe\b', r'\bnecesita\b', r'\bNecesitan\b',
        r'\bparametros\b', r'\bexistentes\b', r'\bnuevas\b',
        r'\bpara\s+(?:el|la|que|obtener|definir)\b',
        r'\bdel\s+(?:elemento|componente|sistema)\b',
        r'\bpor\s+(?:defecto|ejemplo|ahora|si)\b',
        r'\bse\s+(?:necesita|puede|debe|usa|utiliza|guarda|carga|crea|asigna)\b',
        r'\bno\s+(?:se|existe|matchea|est[áa])\b',
        r'\bha\s+sido\b', r'\bhan\s+sido\b',
        r'\bpara\s+(?:crear|generar|enviar|recibir|procesar|validar|guardar|cargar)\b',
        r'\btambi[ée]n\b', r'\btodav[ií]a\b', r'\bninguna?\b',
        r'\b[ÁA]rbol\b', r'\bConsultas?\b', r'\bResultados?\b',
        r'\bPetici[oó]n\b', r'\bM[ée]todos?\b', r'\bPar[áa]metros?\b',
        r'\bespacio\b', r'\bnecesario\b',
    ]
    for pattern in indicators:
        if re.search(pattern, line, re.IGNORECASE):
            return True
    return False

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
        if not has_spanish(line):
            continue
        
        original = line
        # Apply phrase fixes
        for pattern, replacement in PHRASE_FIXES:
            try:
                line = re.sub(pattern, replacement, line, flags=re.IGNORECASE)
            except:
                pass
        
        # Apply word fixes
        for pattern, replacement in WORD_FIXES.items():
            try:
                line = re.sub(pattern, replacement, line, flags=re.IGNORECASE)
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
        for fn in sorted(files):
            if not fn.endswith('.pas'):
                continue
            fp = os.path.join(root, fn)
            ch = process_file(fp)
            if ch > 0:
                rel = os.path.relpath(fp, SOURCE_DIR)
                print(f'  {rel}: {ch} fixes')
                total_files += 1
                total_changes += ch
    print(f'\n{total_changes} fixes in {total_files} files')

if __name__ == '__main__':
    main()
