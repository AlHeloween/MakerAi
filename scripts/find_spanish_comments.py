#!/usr/bin/env python3
"""Find remaining Spanish content in Delphi .pas files."""

import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, 'Source')

# Words that are clear Spanish indicators (not false positives in English)
SPANISH_WORDS = {
    'el ', 'la ', 'los ', 'las ', 'del ', 'al ', 'por ', 'para ', 'con ', 'sin ',
    'como ', 'cuando ', 'entre ', 'desde ', 'hacia ', 'sobre ', 'pero ', 'todo ',
    'nuevo', 'tipo ', 'datos', 'proceso', 'manejo', 'creado',
    'bloque', 'flujo ', 'puede', 'debe ', 'tiene', 'hace ',
    'requiere', 'retorna', 'devuelve', 'genera', 'contiene',
    'soporta', 'permite', 'obtiene', 'establece', 'asignar',
    'liberar', 'buscar', 'crear', 'eliminar', 'enviar',
    'recibir', 'cargar', 'guardar', 'procesar', 'validar',
    'convertir', 'inicializar', 'comprobar',
    'archivo', 'carpeta', 'mensaje', 'solicitud', 'respuesta',
    'resultado', 'propiedad', 'método', 'm[eé]todo',
    'variable', 'parámetro', 'par[áa]metro',
    'configuración', 'configuraci[oó]n',
    'colección', 'colecci[oó]n',
    'cadena', 'registro', 'evento', 'etiqueta',
    'contenido', 'descripción', 'descripci[oó]n',
    'ejecución', 'ejecuci[oó]n',
    'compilación', 'compilaci[oó]n',
    'dependencia', 'conexión', 'conexi[oó]n',
    'referencia', 'instancia', 'módulo', 'm[oó]dulo',
    'clase ', 'método', 'nombre ', 'valor ',
    'tiempo ', 'fecha ', 'entrada ', 'salida ',
    'selección', 'selecci[oó]n',
    'posición', 'posici[oó]n',
    'cantidad', 'pantalla', 'ventana', 'captura',
    'primero', 'segundo', 'tercero',
    'también', 'tambi[eé]n',
    'tampoco', 'además', 'adem[áa]s',
    'ejemplo',
    'predeterminado',
    'vacío', 'vac[ií]o',
    'nulo', 'temporal', 'permanente',
    'actual ', 'anterior ', 'siguiente ',
    'defecto', 'través', 'trav[eé]s',
    'manera', 'forma ',
    # Common Spanish structure words in comments
    'se puede', 'se debe', 'se necesita', 'se requiere',
    'se asigna', 'se crea', 'se elimina', 'se envía', 'se envi[íi]a',
    'se recibe', 'se procesa', 'se valida', 'se convierte',
    'se ejecuta', 'se guarda', 'se carga', 'se libera',
    'se inicializa', 'se devuelve', 'se retorna', 'se utiliza', 'se usa',
    'no se puede', 'no se debe', 'no se ha', 'no se pueden',
    'ha sido', 'han sido', 'puede ser', 'debe ser',
    'por defecto', 'a través',
    'en lugar', 'en este', 'en el ', 'en la ',
    'del sistema', 'del usuario', 'del modelo', 'del código', 'del c[oó]digo',
    'del servidor', 'del cliente', 'de los datos', 'de la aplicación',
    # RAG specific
    'grafo', 'nodo', 'arista', 'vecino', 'vecindario', 'comunidad',
    'blackboard', 'pizarra', 'similitud', 'distancia',
    'coseno', 'euclidiano', 'semántica', 'sem[áa]ntica',
    'consulta', 'incrustación', 'incrustaci[oó]n',
    'fragmento', 'metadato', 'indización', 'indizaci[oó]n',
    'recuperación', 'recuperaci[oó]n',
    # Also with ? for accented chars
    'expresi', 'operaci', 'instrucci', 'definici',
    'generaci', 'informaci', 'relaci', 'comparaci',
    'cancelaci', 'solucion', 'solucion',
    'a?adir', 'ning?n',
    'c?digo', 'n?mero',
    'despu?s', 'm?s',
    'est?', 'est?n',
    'c?mo', 'cu?l', 'cu?ndo', 'd?nde', 'qui?n',
}


def is_comment(line):
    """Check if a line is a comment line (single or block)."""
    stripped = line.lstrip()
    return (stripped.startswith('//') or stripped.startswith('{') or 
            stripped.startswith('(*') or False)


def has_spanish(comment_text):
    """Check if comment text contains Spanish indicators."""
    lower = comment_text.lower()
    for word in SPANISH_WORDS:
        if re.search(word, lower):
            return True
    return False


def main():
    results = []
    
    for root, dirs, files in os.walk(SOURCE_DIR):
        dirs[:] = [d for d in dirs if d not in ('Packages', 'Resources', 'hpp')]
        for filename in files:
            if not filename.endswith('.pas'):
                continue
            filepath = os.path.join(root, filename)
            relpath = os.path.relpath(filepath, SOURCE_DIR)
            
            try:
                with open(filepath, 'r', encoding='utf-8-sig') as f:
                    content = f.read()
            except (UnicodeDecodeError, FileNotFoundError):
                continue
            
            lines = content.split('\n')
            spanish_lines = []
            
            for i, line in enumerate(lines, 1):
                stripped = line.strip()
                if not is_comment(line):
                    continue
                if has_spanish(stripped):
                    # Truncate for display
                    display = stripped[:120]
                    spanish_lines.append((i, display))
            
            if spanish_lines:
                results.append((relpath, spanish_lines))
    
    # Sort by number of Spanish lines
    results.sort(key=lambda x: -len(x[1]))
    
    total_spanish = 0
    for relpath, slines in results:
        header_printed = False
        for lineno, text in slines:
            if not header_printed:
                print(f'\n== {relpath} ({len(slines)} lines) ==')
                header_printed = True
            print(f'  L{lineno}: {text}')
            total_spanish += 1
    
    print(f'\n\nTOTAL: {total_spanish} Spanish comment lines in {len(results)} files')


if __name__ == '__main__':
    main()
