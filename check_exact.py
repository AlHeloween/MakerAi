import os

files_to_check = [
    (r'D:\zPython\MakerAi\Source\Agents\uMakerAi.Agents.ToolRegistry.pas', 647),
    (r'D:\zPython\MakerAi\Source\Chat\uMakerAi.Chat.Gemini.pas', 3086),
    (r'D:\zPython\MakerAi\Source\MCPServer\uMakerAi.MCPServer.Core.pas', 1510),
]

for fp, lineno in files_to_check:
    with open(fp, 'r', encoding='utf-8-sig') as f:
        lines = f.readlines()
    if lineno <= len(lines):
        line = lines[lineno-1]
        print(f'{os.path.basename(fp)}:{lineno}:')
        print(f'  repr: {repr(line.rstrip())}')
        print(f'  text: {line.rstrip()}')
        print()
