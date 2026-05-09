import os
import re

source_dir = r"D:\zPython\MakerAi\Source"

# Spanish words without accents that appear in comments
translations = [
    ('// Guarda las transcripciones en los MediaFile,  luego construye la respuesta definitiva con todos los mediafiles',
     '// Saves transcriptions in MediaFile, then builds the definitive response with all mediafiles'),
    ('// aqui lleva el Prompt Inicial + la conversi',
     '// here goes the Initial Prompt + conversion'),
    ('de los MediaFiles a texto si el usuario lo permite',
     'of MediaFiles to text if the user allows'),
    ('// Originalmente en TAiChatMessage.GetMediaAsBase64',
     '// Originally in TAiChatMessage.GetMediaAsBase64'),
    ('// Sobreescribe InternalRun para manejar el flujo de herramientas',
     '// Override InternalRun to handle tool flow'),
    ('// Respuesta de completion',
     '// Completion response'),
    ('// Herramientas',
     '// Tools'),
    ('// Mensajes',
     '// Messages'),
    ('// Mensaje',
     '// Message'),
    ('// Respuesta',
     '// Response'),
    ('// Peticion',
     '// Request'),
    ('// Pregunta',
     '// Question'),
    ('// Parametros',
     '// Parameters'),
    ('// Opcion',
     '// Option'),
    ('// Opciones',
     '// Options'),
    ('// Funciones',
     '// Functions'),
    ('// Funcion',
     '// Function'),
    ('// Conexion',
     '// Connection'),
    ('// Conexion',
     '// Connection'),
    ('// Ejecutar',
     '// Execute'),
    ('// Ejecucion',
     '// Execution'),
    ('// Leer',
     '// Read'),
    ('// Escribir',
     '// Write'),
    ('// Archivo',
     '// File'),
    ('// Archivos',
     '// Files'),
    ('// Imagen',
     '// Image'),
    ('// Imagenes',
     '// Images'),
    ('// Audio',
     '// Audio'),
    ('// Video',
     '// Video'),
    ('// Texto',
     '// Text'),
    ('// Palabra',
     '// Word'),
    ('// Palabras',
     '// Words'),
    ('// Frase',
     '// Phrase'),
    ('// Frases',
     '// Phrases'),
    ('// Oracion',
     '// Sentence'),
    ('// Oraciones',
     '// Sentences'),
    ('// Parrafo',
     '// Paragraph'),
    ('// Parrafos',
     '// Paragraphs'),
    ('// Capitulo',
     '// Chapter'),
    ('// Capitulos',
     '// Chapters'),
    ('// Seccion',
     '// Section'),
    ('// Secciones',
     '// Sections'),
    ('// Tabla',
     '// Table'),
    ('// Tablas',
     '// Tables'),
    ('// Columna',
     '// Column'),
    ('// Columnas',
     '// Columns'),
    ('// Fila',
     '// Row'),
    ('// Filas',
     '// Rows'),
    ('// Dato',
     '// Data'),
    ('// Datos',
     '// Data'),
    ('// Informacion',
     '// Information'),
    ('// Consulta',
     '// Query'),
    ('// Consultas',
     '// Queries'),
    ('// Resultado',
     '// Result'),
    ('// Resultados',
     '// Results'),
    ('// Error',
     '// Error'),
    ('// Errores',
     '// Errors'),
    ('// Advertencia',
     '// Warning'),
    ('// Advertencias',
     '// Warnings'),
    ('// Exito',
     '// Success'),
    ('// Fracaso',
     '// Failure'),
    ('// Inicio',
     '// Start'),
    ('// Fin',
     '// End'),
    ('// Principio',
     '// Beginning'),
    ('// Final',
     '// End'),
    ('// Primero',
     '// First'),
    ('// Ultimo',
     '// Last'),
    ('// Anterior',
     '// Previous'),
    ('// Siguiente',
     '// Next'),
    ('// Ahora',
     '// Now'),
    ('// Despues',
     '// After'),
    ('// Antes',
     '// Before'),
    ('// Durante',
     '// During'),
    ('// Mientras',
     '// While'),
    ('// Siempre',
     '// Always'),
    ('// Nunca',
     '// Never'),
    ('// Tambien',
     '// Also'),
    ('// Tampoco',
     '// Neither'),
    ('// Todavia',
     '// Still'),
    ('// Ya',
     '// Already'),
    ('// Solo',
     '// Only'),
    ('// Solamente',
     '// Only'),
    ('// Incluso',
     '// Even'),
    ('// Quizas',
     '// Perhaps'),
    ('// Tal',
     '// Such'),
    ('// Como',
     '// Like/As'),
    ('// Cuando',
     '// When'),
    ('// Donde',
     '// Where'),
    ('// Porque',
     '// Because'),
    ('// Pero',
     '// But'),
    ('// Aunque',
     '// Although'),
    ('// Entonces',
     '// Then'),
    ('// Luego',
     '// Then/Later'),
    ('// Si',
     '// If'),
    ('// No',
     '// No/Not'),
    ('// Ni',
     '// Nor'),
    ('// O',
     '// Or'),
    ('// U',
     '// Or'),
    ('// Y',
     '// And'),
    ('// E',
     '// And'),
    ('// Con',
     '// With'),
    ('// Sin',
     '// Without'),
    ('// Por',
     '// By/For'),
    ('// Para',
     '// For'),
    ('// De',
     '// Of'),
    ('// Desde',
     '// From'),
    ('// Hasta',
     '// Until'),
    ('// Sobre',
     '// About/On'),
    ('// Bajo',
     '// Under'),
    ('// Entre',
     '// Between'),
    ('// Contra',
     '// Against'),
    ('// Hacia',
     '// Towards'),
    ('// Segun',
     '// According to'),
    ('// Durante',
     '// During'),
    ('// Mediante',
     '// Through'),
    ('// Tras',
     '// After'),
    ('// Via',
     '// Via'),
]

modified_count = 0
translated_lines = 0
modified_files = []

for root, dirs, files in os.walk(source_dir):
    for fname in files:
        if not fname.endswith('.pas'):
            continue
        filepath = os.path.join(root, fname)
        try:
            with open(filepath, 'rb') as f:
                content = f.read()
        except:
            continue

        original = content
        text = content.decode('utf-8', errors='replace')
        lines = text.split('\n')
        new_lines = []
        file_changed = False
        file_translated = 0

        for line in lines:
            new_line = line
            for spanish, english in translations:
                if spanish in new_line:
                    new_line = new_line.replace(spanish, english)
            if new_line != line:
                file_translated += 1
                file_changed = True
            new_lines.append(new_line)

        if file_changed:
            new_text = '\n'.join(new_lines)
            new_content = new_text.encode('utf-8')
            # Ensure CRLF
            new_content = new_content.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
            with open(filepath, 'wb') as f:
                f.write(new_content)
            modified_count += 1
            translated_lines += file_translated
            modified_files.append(os.path.relpath(filepath, source_dir))

print(f"=== Translation Summary (Pass - no accents) ===")
print(f"Files modified: {modified_count}")
print(f"Comment lines translated: {translated_lines}")
if modified_files:
    print("\nFiles changed:")
    for f in sorted(modified_files):
        print(f"  {f}")
