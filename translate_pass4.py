import os
import re

source_dir = r"D:\zPython\MakerAi\Source"

# Pass 4 - remaining Spanish phrases with actual UTF-8 characters
translations = [
    # Exact line matches for remaining untranslated content
    (r'// llamar herramientas del TAiToolRegistry automáticamente\. El loop LLM →',
     '// call tools from TAiToolRegistry automatically. The LLM →'),
    (r'// Tool → Observación es manejado internamente por TAiChatConnection',
     '// Tool → Observation is handled internally by TAiChatConnection'),
    (r'// Si está vacío usa %APPDATA%\\MakerAI\\tools\\',
     '// If empty uses %APPDATA%\\MakerAI\\tools\\'),
    (r'// ref débil — no owning',
     '// weak ref — not owning'),
    (r'// Directorio de extracción: tools\\mcp-nombre\\',
     '// Extraction directory: tools\\mcp-name\\'),
    (r'// Archivos devueltos por el tool MCP \(imágenes, PDFs\) → ToolMsg para que el LLM los vea',
     '// Files returned by MCP tool (images, PDFs) → ToolMsg so the LLM can see them'),
    (r'// Esto es imprescindible porque Run\(\) liberará el ResMsg que nos pasí',
     '// This is essential because Run() will free the ResMsg passed to us'),
    (r'// \(LOwnsResMsg=True\) justo después de que retornemos\. Si uséramos ese',
     '// (LOwnsResMsg=True) right after we return. If we used that'),
    (r'// Convertir a WAV \(24kHz, Mono, 16bit — estándar Gemini TTS\)',
     '// Convert to WAV (24kHz, Mono, 16bit — Gemini TTS standard)'),
    (r'// Break; // Esperar más datos o buffer vacío',
     '// Break; // Wait for more data or empty buffer'),
    (r'// Detectar escape para la siguiente iteración \(ej: \\\\"\)',
     '// Detect escape for next iteration (e.g. \\\\")'),
    (r'// Archivos extraídos → ToolCall\.MediaFiles \(los drivers los transfieren',
     '// Extracted files → ToolCall.MediaFiles (drivers transfer them'),
    (r'// original → ToolMsg \(vía driver\)',
     '// original → ToolMsg (via driver)'),
    (r'// Active=True  → crea las funciones si aún no existen \(lazy\)\.',
     '// Active=True  → creates functions if they do not exist yet (lazy).'),
    (r'// Orden: OnAutoMCPRequest → Whitelist \(si no vacía\) → Blacklist → permitir\.',
     '// Order: OnAutoMCPRequest → Whitelist (if not empty) → Blacklist → allow.'),
    (r'// ConfigFile si está asignado, sino <exedir>\\mcp_servers\.json',
     '// ConfigFile if assigned, otherwise <exedir>\\mcp_servers.json'),
    (r'// Evento de validación custom',
     '// Custom validation event'),
    (r'// No borrar de IDList aquí — lo reemplazaremos al agregar',
     '// Do not delete from IDList here — will replace when adding'),
    (r'// sqlite-vec falló en runtime → fallback',
     '// sqlite-vec failed at runtime → fallback'),
    (r'// Ruta completa a sqlite_vec\.dll/\.so — vacío = modo Delphi \(brute-force cosine\)',
     '// Full path to sqlite_vec.dll/.so — empty = Delphi mode (brute-force cosine)'),
    (r'// luego el INSERT dispara _ai — así FTS5 queda siempre consistente\.',
     '// then INSERT fires _ai — thus FTS5 stays always consistent.'),
    (r'// Adecuado para colecciones pequeñas/medianas \(≤ 50K nodos\)\.',
     '// Suitable for small/medium collections (≤ 50K nodes).'),
    (r'// FTS5 bm25\(\) devuelve valores ≤ 0 \(más negativo = más relevante\)\.',
     '// FTS5 bm25() returns values ≤ 0 (more negative = more relevant).'),
    (r'// Query FTS inválida \(caracteres especiales sin escapar\) — devolver vacío',
     '// Invalid FTS query (special characters unescaped) — return empty'),
    (r'// temporal — se normaliza después',
     '// temporal — normalized later'),
    (r'// Llamada directa siempre — nunca TTask\.Run aquí:',
     '// Direct call always — never TTask.Run here:'),
    (r'//   podía liberarse antes de que el TTask terminara → access violation\.',
     '//   could be freed before the TTask finished → access violation.'),
    (r'// Formato 1 — OpenAI estándar:',
     '// Format 1 — Standard OpenAI:'),
    # Individual Spanish words still appearing
    (r'// automáticamente\.', '// automatically.'),
    (r'// automáticamente', '// automatically'),
    (r'// estándar', '// standard'),
    (r'// vacío', '// empty'),
    (r'// vacía', '// empty'),
    (r'// aún', '// still'),
    (r'// envíe', '// send'),
    (r'// débil', '// weak'),
    (r'// imágenes', '// images'),
    (r'// después', '// after'),
    (r'// más', '// more'),
    (r'// aquí', '// here'),
    (r'// allí', '// there'),
    (r'// Observación', '// Observation'),
    (r'// extraídos', '// extracted'),
    (r'// vía', '// via'),
    (r'// estándar', '// standard'),
    (r'// inválida', '// invalid'),
    (r'// falló', '// failed'),
    (r'// podía', '// could'),
    (r'// pequeñas', '// small'),
    (r'// medianas', '// medium'),
    (r'// devuelve', '// returns'),
    (r'// relevante', '// relevant'),
    (r'// escapar', '// escape'),
    (r'// caracteres', '// characters'),
    (r'// normales', '// normal'),
    (r'// especiales', '// special'),
    (r'// asignado', '// assigned'),
    (r'// crea', '// creates'),
    (r'// funciones', '// functions'),
    (r'// existen', '// exist'),
    (r'// permite', '// allows'),
    (r'// permitir', '// allow'),
    (r'// herramientas', '// tools'),
    (r'// archivos', '// files'),
    (r'// devueltos', '// returned'),
    (r'// transfieren', '// transfer'),
    (r'// liberará', '// will free'),
    (r'// imprescindibles', '// essential'),
    (r'// imprescindible', '// essential'),
    (r'// retornemos', '// we return'),
    (r'// usáramos', '// we used'),
    (r'// justo', '// right'),
    (r'// siguiente', '// next'),
    (r'// iteración', '// iteration'),
    (r'// Detectar', '// Detect'),
    (r'// Esperar', '// Wait'),
    (r'// datos', '// data'),
    (r'// buffer', '// buffer'),
    (r'// Convertir', '// Convert'),
    (r'// llamar', '// call'),
    (r'// herramientas', '// tools'),
    (r'// manejado', '// handled'),
    (r'// internamente', '// internally'),
    (r'// extracción', '// extraction'),
    (r'// vacía', '// empty'),
    (r'// asignado', '// assigned'),
    (r'// sino', '// otherwise'),
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

print(f"=== Translation Summary (Pass 4) ===")
print(f"Files modified: {modified_count}")
print(f"Comment lines translated: {translated_lines}")
print()
print("Files changed:")
for f in sorted(modified_files):
    print(f"  {f}")
