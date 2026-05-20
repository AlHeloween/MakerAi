#!/usr/bin/env python3
"""Audit all docs (DOCX, PDF, XLSX) for Spanish content."""

import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS_DIR = os.path.join(ROOT, 'Docs')

# Spanish indicators in text
SPANISH_INDICATORS = [
    r'\b(?:el|la|los|las|del|para|por|con|sin|como|cuando|entre|desde|hacia)\b',
    r'\b(?:puede|debe|tiene|hace|requiere|retorna|devuelve|genera|contiene|soporta|permite|obtiene|establece)\b',
    r'\b(?:no se puede|no se pudo|se requiere|se necesita|se debe|ha sido|por defecto)\b',
    r'\b(?:archivo|carpeta|mensaje|solicitud|respuesta|proceso|configuración|ejecución|validación)\b',
    r'\b(?:propiedad|propiedades|método|variable|parámetro|parámetros|función)\b',
    r'\b(?:nodo|arista|grafo|vector|embedding|consulta|búsqueda|metadato)\b',
    r'\b(?:herramienta|servidor|cliente|conexión|descripción|ejemplo|importante)\b',
    r'\b(?:inicializar|liberar|asignar|crear|eliminar|buscar|enviar|recibir|cargar|guardar)\b',
    r'\b(?:procesar|validar|convertir|ejecutar|comprobar|verificar)\b',
    r'\b(?:este|esta|nuevo|nueva|todos|todas|ninguno|ninguna)\b',
    r'\b(?:tamaño|formato|bloque|flujo|pantalla|captura|ventana)\b',
    r'\b(?:primero|segundo|tercero|luego|finalmente|también|además|tampoco)\b',
    r'\b(?:documentación|instalación|publicación|evaluación|generación|información)\b',
    r'[áéíóúñÁÉÍÓÚÑ]',
]


def has_spanish(text):
    """Check if text contains Spanish indicators."""
    if not text:
        return False
    score = 0
    for pattern in SPANISH_INDICATORS:
        matches = re.findall(pattern, text, re.IGNORECASE)
        score += len(matches)
    return score >= 2  # need at least 2 Spanish indicators


def audit_docx(filepath):
    """Extract text from DOCX and check for Spanish."""
    try:
        import docx
        doc = docx.Document(filepath)
        text = ' '.join(p.text for p in doc.paragraphs)
        # Also check tables
        for table in doc.tables:
            for row in table.rows:
                for cell in row.cells:
                    text += ' ' + cell.text
        if has_spanish(text):
            return text
    except Exception as e:
        return f"[ERROR: {e}]"
    return None


def audit_pdf(filepath):
    """Extract text from PDF and check for Spanish."""
    try:
        # Try PyPDF2 first
        try:
            from PyPDF2 import PdfReader
            reader = PdfReader(filepath)
            text = ' '.join(page.extract_text() or '' for page in reader.pages)
            if has_spanish(text):
                return text
        except ImportError:
            pass
        # Try pdfplumber
        try:
            import pdfplumber
            with pdfplumber.open(filepath) as pdf:
                text = ' '.join(page.extract_text() or '' for page in pdf.pages)
            if has_spanish(text):
                return text
        except ImportError:
            return "[SKIP: no PDF library available]"
    except Exception as e:
        return f"[ERROR: {e}]"
    return None


def audit_xlsx(filepath):
    """Extract text from XLSX and check for Spanish."""
    try:
        import openpyxl
        wb = openpyxl.load_workbook(filepath, data_only=True)
        text = ''
        for sheet in wb.worksheets:
            for row in sheet.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        text += ' ' + cell.value
        if has_spanish(text):
            return text
    except Exception as e:
        return f"[ERROR: {e}]"
    return None


def main():
    results = []
    doc_types = {'.docx': audit_docx, '.pdf': audit_pdf, '.xlsx': audit_xlsx}
    
    for root, dirs, files in os.walk(DOCS_DIR):
        # Skip temp files
        dirs[:] = [d for d in dirs if not d.startswith('~')]
        for fn in sorted(files):
            if fn.startswith('~$'):
                continue
            ext = os.path.splitext(fn)[1].lower()
            if ext not in doc_types:
                continue
            filepath = os.path.join(root, fn)
            relpath = os.path.relpath(filepath, ROOT)
            auditor = doc_types[ext]
            text = auditor(filepath)
            if text is None:
                print(f'  [EN] {relpath}')
            elif text.startswith('['):
                print(f'  {text} {relpath}')
            else:
                # Has Spanish
                print(f'  [ES] {relpath} ({len(text)} chars)')
                results.append((relpath, text))
    
    print(f'\n{"="*60}')
    print(f'SPANISH DOCS FOUND: {len(results)}')
    print(f'{"="*60}')
    for relpath, text in results[:20]:
        # Show first 200 chars
        preview = text[:200].replace('\n', ' ')
        print(f'\n{relpath}:')
        print(f'  {preview}...')


if __name__ == '__main__':
    main()
