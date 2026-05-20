#!/usr/bin/env python3
"""Batch translate Spanish comments to English in Delphi .pas files."""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, 'Source')

# Safe translations — only applied to lines that start a single-line comment
# Pattern: "// exact_spanish_pattern rest_of_line" -> "// english_pattern rest_of_line"
SINGLE_LINE_TRANSLATIONS = [
    # Verbs
    (r'^(//\s*)Inicializar(\s)', r'\1Initialize\2'),
    (r'^(//\s*)Liberar(\s)', r'\1Free\2'),
    (r'^(//\s*)Obtener(\s)', r'\1Get\2'),
    (r'^(//\s*)Establecer(\s)', r'\1Set\2'),
    (r'^(//\s*)Asignar(\s)', r'\1Assign\2'),
    (r'^(//\s*)Procesar(\s)', r'\1Process\2'),
    (r'^(//\s*)Validar(\s)', r'\1Validate\2'),
    (r'^(//\s*)Convertir(\s)', r'\1Convert\2'),
    (r'^(//\s*)Cargar(\s)', r'\1Load\2'),
    (r'^(//\s*)Guardar(\s)', r'\1Save\2'),
    (r'^(//\s*)Enviar(\s)', r'\1Send\2'),
    (r'^(//\s*)Recibir(\s)', r'\1Receive\2'),
    (r'^(//\s*)Crear(\s)', r'\1Create\2'),
    (r'^(//\s*)Eliminar(\s)', r'\1Delete\2'),
    (r'^(//\s*)Buscar(\s)', r'\1Find\2'),
    (r'^(//\s*)Comprobar(\s)', r'\1Check\2'),
    (r'^(//\s*)Verificar(\s)', r'\1Verify\2'),
    (r'^(//\s*)Manejar(\s)', r'\1Handle\2'),
    (r'^(//\s*)Soporta(\s)', r'\1Supports\2'),
    (r'^(//\s*)Permite(\s)', r'\1Allows\2'),
    (r'^(//\s*)Retorna(\s)', r'\1Returns\2'),
    (r'^(//\s*)Devuelve(\s)', r'\1Returns\2'),
    (r'^(//\s*)Genera(\s)', r'\1Generates\2'),
    (r'^(//\s*)Contiene(\s)', r'\1Contains\2'),
    (r'^(//\s*)Requiere(\s)', r'\1Requires\2'),
    # Connectors
    (r'^(//\s*)Primero,(\s)', r'\1First,\2'),
    (r'^(//\s*)Luego,(\s)', r'\1Then,\2'),
    (r'^(//\s*)Luego(\s)', r'\1Then\2'),
    (r'^(//\s*)Finalmente,(\s)', r'\1Finally,\2'),
    (r'^(//\s*)Despu[eé]s,(\s)', r'\1After,\2'),
    # Adjectives
    (r'^(//\s*)Nuevo(\s)', r'\1New\2'),
    (r'^(//\s*)Todos(\s)', r'\1All\2'),
    (r'^(//\s*)Todas(\s)', r'\1All\2'),
    (r'^(//\s*)Ninguno(\s)', r'\1None\2'),
    (r'^(//\s*)Predeterminado(\s)', r'\1Default\2'),
    (r'^(//\s*)Vac[ií]o(\s)', r'\1Empty\2'),
    (r'^(//\s*)Nulo(\s)', r'\1Null\2'),
    (r'^(//\s*)Temporal(\s)', r'\1Temporary\2'),
    (r'^(//\s*)Permanente(\s)', r'\1Permanent\2'),
    (r'^(//\s*)Actual(\s)', r'\1Current\2'),
    (r'^(//\s*)Anterior(\s)', r'\1Previous\2'),
    (r'^(//\s*)Siguiente(\s)', r'\1Next\2'),
    # Nouns
    (r'^(//\s*)Archivo(\s)', r'\1File\2'),
    (r'^(//\s*)Carpeta(\s)', r'\1Folder\2'),
    (r'^(//\s*)Mensaje(\s)', r'\1Message\2'),
    (r'^(//\s*)Solicitud(\s)', r'\1Request\2'),
    (r'^(//\s*)Respuesta(\s)', r'\1Response\2'),
    (r'^(//\s*)Formato(\s)', r'\1Format\2'),
    (r'^(//\s*)Bloque(\s)', r'\1Block\2'),
    (r'^(//\s*)Flujo(\s)', r'\1Stream\2'),
    (r'^(//\s*)Tama[ñn]o(\s)', r'\1Size\2'),
    (r'^(//\s*)Resultado(\s)', r'\1Result\2'),
    (r'^(//\s*)Propiedad(\s)', r'\1Property\2'),
    (r'^(//\s*)Prop[oó]sito(\s)', r'\1Purpose\2'),
    (r'^(//\s*)Funci[oó]n(\s)', r'\1Function\2'),
    (r'^(//\s*)Variable(\s)', r'\1Variable\2'),
    (r'^(//\s*)Par[áa]metro(\s)', r'\1Parameter\2'),
    (r'^(//\s*)Par[áa]metros(\s)', r'\1Parameters\2'),
    (r'^(//\s*)Configuraci[oó]n(\s)', r'\1Configuration\2'),
    (r'^(//\s*)Colecci[oó]n(\s)', r'\1Collection\2'),
    (r'^(//\s*)Lista(\s)', r'\1List\2'),
    (r'^(//\s*)Cadena(\s)', r'\1String\2'),
    (r'^(//\s*)Registro(\s)', r'\1Record\2'),
    (r'^(//\s*)Evento(\s)', r'\1Event\2'),
    (r'^(//\s*)Etiqueta(\s)', r'\1Label\2'),
    (r'^(//\s*)Contenido(\s)', r'\1Content\2'),
    (r'^(//\s*)Descripci[oó]n(\s)', r'\1Description\2'),
    (r'^(//\s*)Ejecuci[oó]n(\s)', r'\1Execution\2'),
    (r'^(//\s*)Compilaci[oó]n(\s)', r'\1Compilation\2'),
    (r'^(//\s*)Dependencia(\s)', r'\1Dependency\2'),
    (r'^(//\s*)Conexi[oó]n(\s)', r'\1Connection\2'),
    (r'^(//\s*)Referencia(\s)', r'\1Reference\2'),
    (r'^(//\s*)Instancia(\s)', r'\1Instance\2'),
    (r'^(//\s*)M[oó]dulo(\s)', r'\1Module\2'),
    (r'^(//\s*)Clase(\s)', r'\1Class\2'),
    (r'^(//\s*)M[eé]todo(\s)', r'\1Method\2'),
    (r'^(//\s*)Nombre(\s)', r'\1Name\2'),
    (r'^(//\s*)Valor(\s)', r'\1Value\2'),
    (r'^(//\s*)Tiempo(\s)', r'\1Time\2'),
    (r'^(//\s*)Fecha(\s)', r'\1Date\2'),
    (r'^(//\s*)Entrada(\s)', r'\1Input\2'),
    (r'^(//\s*)Salida(\s)', r'\1Output\2'),
    (r'^(//\s*)Selecci[oó]n(\s)', r'\1Selection\2'),
    (r'^(//\s*)Posici[oó]n(\s)', r'\1Position\2'),
    (r'^(//\s*)Cantidad(\s)', r'\1Quantity\2'),
    (r'^(//\s*)Pantalla(\s)', r'\1Screen\2'),
    (r'^(//\s*)Ventana(\s)', r'\1Window\2'),
    (r'^(//\s*)Captura(\s)', r'\1Capture\2'),
    (r'^(//\s*)[ÁA]rea(\s)', r'\1Area\2'),
    # Common phrases
    (r'^(//\s*)No se puede(\s)', r'\1Cannot\2'),
    (r'^(//\s*)No se pudo(\s)', r'\1Could not\2'),
    (r'^(//\s*)Se requiere(\s)', r'\1Required: \2'),
    (r'^(//\s*)Debe ser(\s)', r'\1Must be\2'),
    (r'^(//\s*)No se ha(\s)', r'\1Has not been\2'),
    (r'^(//\s*)Se debe(\s)', r'\1Must\2'),
    (r'^(//\s*)No se pueden(\s)', r'\1Cannot\2'),
    (r'^(//\s*)Por defecto(\s)', r'\1By default\2'),
    (r'^(//\s*)por defecto(\s)', r'\1by default\2'),
    (r'^(//\s*)Se ha(\s)', r'\1Has been\2'),
    (r'^(//\s*)Se usa(\s)', r'\1Used\2'),
    (r'^(//\s*)Se ejecuta(\s)', r'\1Executes\2'),
    (r'^(//\s*)Se utiliza(\s)', r'\1Used\2'),
    # Directional
    (r'^(//\s*)dentro de(\s)', r'\1inside\2'),
    (r'^(//\s*)fuera de(\s)', r'\1outside of\2'),
    (r'^(//\s*)encima de(\s)', r'\1above\2'),
    (r'^(//\s*)debajo de(\s)', r'\1below\2'),
    # Code pattern comments
    (r'^(//\s*)Caso(\s*\d)', r'\1Case\2'),
    (r'^(//\s*)Ejemplo(\s)', r'\1Example\2'),
    (r'^(//\s*)Nota:(\s)', r'\1Note:\2'),
    (r'^(//\s*)Atenci[oó]n:(\s)', r'\1Attention:\2'),
    # ---
    (r'^(//\s*)---\s*(CAMBIO|Cambio)\s+(\d)', r'\1--- CHANGE \2'),
    (r'^(//\s*)---\s*([^-\s])', r'\1--- \2'),  # preserve other --- markers
]

# More context-dependent translations — match line containing, replace whole
# Only applied to comment lines, match == starts with //
MID_LINE_TRANSLATIONS = [
    (r'\ba\s+trav[eé]s\s+de\b', 'through'),
    (r'\bpor\s+ejemplo\b', 'for example'),
    (r'\bcon\s+respecto\b', 'regarding'),
    (r'\ben\s+lugar\s+de\b', 'instead of'),
    (r'\bantes\s+de\b', 'before'),
    (r'\bdespu[eé]s\s+de\b', 'after'),
    (r'\bjunto\s+con\b', 'together with'),
    (r'\ben\s+paralelo\b', 'in parallel'),
    (r'\ben\s+secuencia\b', 'in sequence'),
    (r'\ben\s+cascada\b', 'in cascade'),
    (r'\bde\s+forma\b', 'in a'),
    (r'\bde\s+manera\b', 'in a'),
    (r'\bse\s+puede\b', 'can be'),
    (r'\bse\s+debe\b', 'must be'),
    (r'\bse\s+necesita\b', 'is needed'),
    (r'\bse\s+asigna\b', 'is assigned'),
    (r'\bse\s+crea\b', 'is created'),
    (r'\bse\s+elimina\b', 'is deleted'),
    (r'\bse\s+env[ií]a\b', 'is sent'),
    (r'\bse\s+recibe\b', 'is received'),
    (r'\bse\s+procesa\b', 'is processed'),
    (r'\bse\s+valida\b', 'is validated'),
    (r'\bse\s+convierte\b', 'is converted'),
    (r'\bse\s+ejecuta\b', 'is executed'),
    (r'\bse\s+guarda\b', 'is saved'),
    (r'\bse\s+carga\b', 'is loaded'),
    (r'\bse\s+libera\b', 'is freed'),
    (r'\bse\s+inicializa\b', 'is initialized'),
    (r'\bse\s+devuelve\b', 'is returned'),
    (r'\bse\s+retorna\b', 'is returned'),
    (r'\bse\s+utiliza\b', 'is used'),
    (r'\bse\s+usa\b', 'is used'),
    (r'\bse\s+est[áa]\b', 'it is'),
    (r'\bno\s+se\s+debe\b', 'must not'),
    (r'\bno\s+se\s+puede\b', 'cannot be'),
    (r'\bno\s+est[áa]\b', 'is not'),
    (r'\bpuede\s+ser\b', 'may be'),
    (r'\bdebe\s+tener\b', 'must have'),
    (r'\bdebe\s+ser\b', 'must be'),
    (r'\bha\s+sido\b', 'has been'),
    (r'\bhan\s+sido\b', 'have been'),
    (r'\btiene\s+que\b', 'must'),
    (r'\btodo\s+el\b', 'all the'),
    (r'\btodos\s+los\b', 'all the'),
    (r'\btodas\s+las\b', 'all the'),
    (r'\bcada\s+uno\b', 'each one'),
    (r'\bcada\s+vez\b', 'each time'),
    (r'\buna\s+vez\b', 'once'),
    (r'\bahora\b', 'now'),
    (r'\besta\s+funci[oó]n\b', 'this function'),
    (r'\beste\s+m[eé]todo\b', 'this method'),
    (r'\besta\s+propiedad\b', 'this property'),
    (r'\beste\s+bloque\b', 'this block'),
    (r'\besta\s+configuraci[oó]n\b', 'this configuration'),
    (r'\beste\s+archivo\b', 'this file'),
    (r'\besta\s+variable\b', 'this variable'),
    (r'\beste\s+valor\b', 'this value'),
    (r'\besta\s+opci[oó]n\b', 'this option'),
    (r'\bdel\s+sistema\b', 'of the system'),
    (r'\bdel\s+usuario\b', "of the user"),
    (r'\bdel\s+modelo\b', 'of the model'),
    (r'\bdel\s+c[oó]digo\b', 'of the code'),
    (r'\bdel\s+servidor\b', 'of the server'),
    (r'\bdel\s+cliente\b', 'of the client'),
    (r'\bdel\s+componente\b', 'of the component'),
    (r'\bde\s+los\s+datos\b', 'of the data'),
    (r'\bde\s+la\s+aplicaci[oó]n\b', 'of the application'),
    (r'\bde\s+la\s+respuesta\b', 'of the response'),
    (r'\ben\s+el\s+sistema\b', 'in the system'),
    (r'\ben\s+el\s+c[oó]digo\b', 'in the code'),
    (r'\ben\s+el\s+archivo\b', 'in the file'),
    (r'\ben\s+la\s+base\b', 'in the database'),
    (r'\ben\s+la\s+memoria\b', 'in memory'),
    (r'\ben\s+este\s+caso\b', 'in this case'),
    (r'\ben\s+el\s+futuro\b', 'in the future'),
    (r'\ben\s+tiempo\s+de\b', 'at design time' if False else 'at'),  # handled specially
    (r'\ba\s+partir\s+de\b', 'from'),
    (r'\bcon\s+el\s+fin\s+de\b', 'in order to'),
    (r'\bpara\s+que\b', 'so that'),
    (r'\bpor\s+lo\s+tanto\b', 'therefore'),
    (r'\bsin\s+embargo\b', 'however'),
    (r'\badem[aá]s\b', 'additionally'),
    (r'\btambi[eé]n\b', 'also'),
    (r'\btampoco\b', 'neither'),
    (r'\bsolamente\b', 'only'),
    (r'\bs[oó]lo\b', 'only'),
    (r'\bprincipalmente\b', 'primarily'),
    (r'\bnormalmente\b', 'normally'),
    (r'\bgeneralmente\b', 'generally'),
    (r'\bes\s+decir\b', 'that is'),
    (r'\bo\s+sea\b', 'in other words'),
]

ALREADY_ENGLISH_PATTERNS = [
    'the ', 'this ', 'that ', 'with ', 'from ', 'when ', 'where ', 'which ',
    'interface', 'implementation', 'constructor', 'destructor',
    'copyright', 'license', 'permission', 'software', 'notice',
    'MIT', 'warranty', 'without', 'including', 'subject',
    'Author:', 'Email:', 'Telegram:', 'LinkedIn:', 'GitHub:', 'Name:',
]


def is_comment_line(line):
    """Check if a line is a single-line comment."""
    stripped = line.lstrip()
    return stripped.startswith('//') and not stripped.startswith('///')


def is_already_english(line):
    """Heuristic: check if comment line is already substantially English."""
    comment_text = line.lstrip().lstrip('/').strip()
    if not comment_text:
        return True
    lower = comment_text.lower()
    for pattern in ALREADY_ENGLISH_PATTERNS:
        if lower.startswith(pattern):
            return True
    return False


def apply_single_line_translations(line):
    """Apply pattern-based translations to a comment line."""
    original = line
    indent = line[:len(line) - len(line.lstrip())]
    comment_text = line.lstrip()
    
    for pattern, replacement in SINGLE_LINE_TRANSLATIONS:
        new_text = re.sub(pattern, replacement, comment_text)
        if new_text != comment_text:
            return indent + new_text
        # Also try with leading spaces in comment: //  Text
        comment_text = new_text
    
    return original


def apply_mid_line_translations(line):
    """Apply context-dependent mid-line translations."""
    for pattern, replacement in MID_LINE_TRANSLATIONS:
        line = re.sub(pattern, replacement, line, flags=re.IGNORECASE)
    return line


def process_file(filepath):
    """Process a single .pas file, translating comment lines."""
    try:
        with open(filepath, 'r', encoding='utf-8-sig') as f:
            content = f.read()
    except UnicodeDecodeError:
        with open(filepath, 'r', encoding='latin-1') as f:
            content = f.read()
    
    lines = content.split('\n')
    changes = 0
    
    for i, line in enumerate(lines):
        if not is_comment_line(line):
            continue
        if is_already_english(line):
            continue
        
        original = line
        # First apply single-line start-of-comment translations
        line = apply_single_line_translations(line)
        # Then apply mid-line context translations
        line = apply_mid_line_translations(line)
        
        if line != original:
            changes += 1
            lines[i] = line
    
    if changes > 0:
        new_content = '\n'.join(lines)
        with open(filepath, 'w', encoding='utf-8-sig', newline='\n') as f:
            # Write without BOM
            if new_content.startswith('\ufeff'):
                new_content = new_content[1:]
            f.write(new_content)
        # Re-add BOM
        with open(filepath, 'r+', encoding='utf-8') as f:
            content_without_bom = f.read()
            f.seek(0, 0)
            f.write('\ufeff' + content_without_bom)
        
        return changes
    return 0


def main():
    total_files = 0
    total_changes = 0
    
    for root, dirs, files in os.walk(SOURCE_DIR):
        # Skip package and resource directories
        dirs[:] = [d for d in dirs if d not in ('Packages', 'Resources', 'hpp')]
        for filename in files:
            if not filename.endswith('.pas'):
                continue
            filepath = os.path.join(root, filename)
            changes = process_file(filepath)
            if changes > 0:
                relpath = os.path.relpath(filepath, SOURCE_DIR)
                print(f'  {relpath}: {changes} lines translated')
                total_files += 1
                total_changes += changes
    
    print(f'\nTotal: {total_changes} comment lines translated in {total_files} files')


if __name__ == '__main__':
    main()
