import os
import re

source_dir = r"D:\zPython\MakerAi\Source"

# Pass 3 - remaining Spanish phrases
translations = [
    # Lines with "debe ser" / "para que" etc.
    (r'// Tool_Active debe ser True para que el driver env\xede las tools al LLM\.',
     '// Tool_Active must be True for the driver to send the tools to the LLM.'),
    (r'// llamar herramientas del TAiToolRegistry autom\xe1ticamente\. El loop LLM тЖТ',
     '// call tools from TAiToolRegistry automatically. The LLM тЖТ'),
    (r'// Tool тЖТ Observaci\xf3n es manejado internamente por TAiChatConnection',
     '// Tool тЖТ Observation is handled internally by TAiChatConnection'),
    (r'// Si est\xe1 vac\xedo usa %APPDATA%\\MakerAI\\tools\\',
     '// If empty uses %APPDATA%\\MakerAI\\tools\\'),
    (r'// ref d\xe9bil тАФ no owning',
     '// weak ref тАФ not owning'),
    (r'// Directorio de extracci\xf3n: tools\\mcp-nombre\\',
     '// Extraction directory: tools\\mcp-name\\'),
    (r'// En ParseChat normal \(s\xe9ncrono o final de async\), Prompt suele estar vac\xedo al inicio del parseo de este frame\.',
     '// In normal ParseChat (sync or async end), Prompt is usually empty at the start of parsing this frame.'),
    (r'// Archivos devueltos por el tool MCP \(im\xe1genes, PDFs\) тЖТ ToolMsg para que el LLM los vea',
     '// Files returned by MCP tool (images, PDFs) тЖТ ToolMsg so the LLM can see them'),
    (r'// Esto es imprescindible porque Run\(\) liberar\xe1 el ResMsg que nos pas\xf3',
     '// This is essential because Run() will free the ResMsg passed to us'),
    (r'// \(LOwnsResMsg=True\) justo despu\xe9s de que retornemos\. Si us\xe1ramos ese',
     '// (LOwnsResMsg=True) right after we return. If we used that'),
    (r'// Forzar modo s\xe9ncrono en FClient y restaurar despu\xe9s',
     '// Force sync mode in FClient and restore after'),
    (r'// Convertir a WAV \(24kHz, Mono, 16bit тАФ est\xe1ndar Gemini TTS\)',
     '// Convert to WAV (24kHz, Mono, 16bit тАФ Gemini TTS standard)'),
    (r'// Break; // Esperar m\xe1s datos o buffer vac\xedo',
     '// Break; // Wait for more data or empty buffer'),
    (r'// Detectar escape para la siguiente iteraci\xf3n \(ej: \\\\"\)',
     '// Detect escape for next iteration (e.g. \\\\")'),
    (r'// PARSEO EXITOSO: Ahora s\xe9 borramos del buffer',
     '// PARSE SUCCESSFUL: Now we delete from buffer'),
    (r'// Hacemos la llamada s\xe9ncrona, pero Ollama devuelve el stream completo de una vez',
     '// We make the sync call, but Ollama returns the complete stream at once'),
    (r'// Ollama ahora s\xe9 incluye un \'id\', pero lo generamos como fallback por si acaso\.',
     '// Ollama now includes an \'id\', but we generate it as fallback just in case.'),
    (r'// En s\xe9ncrono, TAiChat\.Run a\xf1ade el mensaje al finalizar\.',
     '// In sync, TAiChat.Run adds the message at the end.'),
    (r'// Formato 1 тАФ OpenAI est\xe1ndar:',
     '// Format 1 тАФ Standard OpenAI:'),
    (r'// Evento de validaci\xf3n custom',
     '// Custom validation event'),
    (r'// No borrar de IDList aqu\xed тАФ lo reemplazaremos al agregar',
     '// Do not delete from IDList here тАФ will replace when adding'),
    (r'// sqlite-vec fall\xf3 en runtime тЖТ fallback',
     '// sqlite-vec failed at runtime тЖТ fallback'),
    (r'// Ruta completa a sqlite_vec\.dll/\.so тАФ vac\xedo = modo Delphi \(brute-force cosine\)',
     '// Full path to sqlite_vec.dll/.so тАФ empty = Delphi mode (brute-force cosine)'),
    (r'// luego el INSERT dispara _ai тАФ as\xed FTS5 queda siempre consistente\.',
     '// then INSERT fires _ai тАФ thus FTS5 stays always consistent.'),
    (r'// Adecuado para colecciones peque\xf1as/medianas \(тЙд 50K nodos\)\.',
     '// Suitable for small/medium collections (тЙд 50K nodes).'),
    (r'// FTS5 bm25\(\) devuelve valores тЙд 0 \(m\xe1s negativo = m\xe1s relevante\)\.',
     '// FTS5 bm25() returns values тЙд 0 (more negative = more relevant).'),
    (r'// Query FTS inv\xe1lida \(caracteres especiales sin escapar\) тАФ devolver vac\xedo',
     '// Invalid FTS query (special characters unescaped) тАФ return empty'),
    (r'// temporal тАФ se normaliza despu\xe9s',
     '// temporal тАФ normalized later'),
    (r'// Llamada directa siempre тАФ nunca TTask\.Run aqu\xed:',
     '// Direct call always тАФ never TTask.Run here:'),
    (r'//   pod\xeda liberarse antes de que el TTask terminara тЖТ access violation\.',
     '//   could be freed before the TTask finished тЖТ access violation.'),
    (r'// Archivos extra\xeddos тЖТ ToolCall\.MediaFiles \(los drivers los transfieren',
     '// Extracted files тЖТ ToolCall.MediaFiles (drivers transfer them'),
    (r'// original тЖТ ToolMsg \(v\xeda driver\)',
     '// original тЖТ ToolMsg (via driver)'),
    (r'// Active=True  тЖТ crea las funciones si a\xfan no existen \(lazy\)\.',
     '// Active=True  тЖТ creates functions if they do not exist yet (lazy).'),
    (r'// Orden: OnAutoMCPRequest тЖТ Whitelist \(si no vac\xeda\) тЖТ Blacklist тЖТ permitir\.',
     '// Order: OnAutoMCPRequest тЖТ Whitelist (if not empty) тЖТ Blacklist тЖТ allow.'),
    (r'// ConfigFile si est\xe1 asignado, sino <exedir>\\mcp_servers\.json',
     '// ConfigFile if assigned, otherwise <exedir>\\mcp_servers.json'),
    # Remaining individual Spanish words in comments
    (r'// est\xe1ndar', '// standard'),
    (r'// vac\xedo', '// empty'),
    (r'// vac\xeda', '// empty'),
    (r'// a\xfan', '// still'),
    (r'// env\xede', '// send'),
    (r'// d\xe9bil', '// weak'),
    (r'// im\xe1genes', '// images'),
    (r'// despu\xe9s', '// after'),
    (r'// m\xe1s', '// more'),
    (r'// aqu\xed', '// here'),
    (r'// all\xed', '// there'),
    (r'// autom\xe1ticamente', '// automatically'),
    (r'// autom\xe1tico', '// automatic'),
    (r'// disponible', '// available'),
    (r'// espec\xedfico', '// specific'),
    (r'// expl\xedcito', '// explicit'),
    (r'// gen\xe9rico', '// generic'),
    (r'// l\xf3gica', '// logic'),
    (r'// l\xf3gico', '// logical'),
    (r'// p\xfablico', '// public'),
    (r'// r\xe1pido', '// fast'),
    (r'// tambi\xe9n', '// also'),
    (r'// t\xe9cnico', '// technical'),
    (r'// \xfanica', '// only/unique'),
    (r'// \xfaltima', '// last'),
    (r'// \xfaltimas', '// last'),
    (r'// \xfaltimos', '// last'),
    (r'// \xfatil', '// useful'),
    (r'// b\xfasqueda', '// search'),
    (r'// c\xf3digo', '// code'),
    (r'// car\xe1cter', '// character'),
    (r'// acci\xf3n', '// action'),
    (r'// a\xf1ade', '// adds'),
    (r'// a\xf1adir', '// add'),
    (r'// a\xf1adido', '// added'),
    (r'// configuraci\xf3n', '// configuration'),
    (r'// conexi\xf3n', '// connection'),
    (r'// creaci\xf3n', '// creation'),
    (r'// descripci\xf3n', '// description'),
    (r'// direcci\xf3n', '// address'),
    (r'// ejecuci\xf3n', '// execution'),
    (r'// emisi\xf3n', '// emission'),
    (r'// extracci\xf3n', '// extraction'),
    (r'// funci\xf3n', '// function'),
    (r'// gesti\xf3n', '// management'),
    (r'// \xedndice', '// index'),
    (r'// \xedndices', '// indices'),
    (r'// inicializaci\xf3n', '// initialization'),
    (r'// instrucci\xf3n', '// instruction'),
    (r'// interfaz', '// interface'),
    (r'// m\xe1ximo', '// maximum'),
    (r'// m\xe9todo', '// method'),
    (r'// m\xf3dulo', '// module'),
    (r'// n\xfamero', '// number'),
    (r'// operaci\xf3n', '// operation'),
    (r'// opci\xf3n', '// option'),
    (r'// par\xe1metro', '// parameter'),
    (r'// par\xe1metros', '// parameters'),
    (r'// petici\xf3n', '// request'),
    (r'// p\xe1gina', '// page'),
    (r'// raz\xf3n', '// reason'),
    (r'// respuesta', '// response'),
    (r'// secci\xf3n', '// section'),
    (r'// sesi\xf3n', '// session'),
    (r'// sistema', '// system'),
    (r'// transmisi\xf3n', '// transmission'),
    (r'// \xfaltimo', '// last'),
    (r'// \xfanico', '// unique'),
    (r'// \xe9xito', '// success'),
]

def translate_comment(line):
    result = line
    for pattern, replacement in translations:
        try:
            new_result = re.sub(pattern, replacement, result, flags=re.IGNORECASE)
            if new_result != result:
                result = new_result
        except re.error:
            pass
    return result

modified_count = 0
translated_lines = 0
modified_files = []

for root, dirs, files in os.walk(source_dir):
    for fname in files:
        if not fname.endswith('.pas'):
            continue
        filepath = os.path.join(root, fname)
        try:
            with open(filepath, 'r', encoding='utf-8-sig') as f:
                content = f.read()
        except:
            continue

        original = content
        lines = content.split('\n')
        new_lines = []
        file_changed = False
        file_translated = 0

        for line in lines:
            if '//' in line and re.search(r'[áéíóúüñÁÉÍÓÚÜÑ]', line):
                new_line = translate_comment(line)
                if new_line != line:
                    file_translated += 1
                    file_changed = True
                new_lines.append(new_line)
            else:
                new_lines.append(line)

        if file_changed:
            new_content = '\n'.join(new_lines)
            if '\r\n' in original:
                new_content = new_content.replace('\n', '\r\n')
            with open(filepath, 'w', encoding='utf-8', newline='') as f:
                f.write(new_content)
            modified_count += 1
            translated_lines += file_translated
            modified_files.append(os.path.relpath(filepath, source_dir))

print(f"=== Translation Summary (Pass 3) ===")
print(f"Files modified: {modified_count}")
print(f"Comment lines translated: {translated_lines}")
print()
print("Files changed:")
for f in sorted(modified_files):
    print(f"  {f}")
