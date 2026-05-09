import os

lines_to_check = [
    (r'D:\zPython\MakerAi\Source\Agents\uMakerAi.Agents.Node.LLM.pas', 6),
    (r'D:\zPython\MakerAi\Source\Agents\uMakerAi.Agents.Node.LLM.pas', 7),
    (r'D:\zPython\MakerAi\Source\Agents\uMakerAi.Agents.ToolRegistry.pas', 107),
    (r'D:\zPython\MakerAi\Source\Agents\uMakerAi.Agents.ToolRegistry.pas', 134),
    (r'D:\zPython\MakerAi\Source\Agents\uMakerAi.Agents.ToolRegistry.pas', 647),
    (r'D:\zPython\MakerAi\Source\Chat\uMakerAi.Chat.Gemini.pas', 1674),
    (r'D:\zPython\MakerAi\Source\Chat\uMakerAi.Chat.Gemini.pas', 2757),
    (r'D:\zPython\MakerAi\Source\Chat\uMakerAi.Chat.Gemini.pas', 2758),
    (r'D:\zPython\MakerAi\Source\Chat\uMakerAi.Chat.Gemini.pas', 2940),
    (r'D:\zPython\MakerAi\Source\Chat\uMakerAi.Chat.Gemini.pas', 3069),
    (r'D:\zPython\MakerAi\Source\Chat\uMakerAi.Chat.Gemini.pas', 3086),
    (r'D:\zPython\MakerAi\Source\Tools\uMakerAi.Tools.Functions.pas', 1410),
    (r'D:\zPython\MakerAi\Source\Tools\uMakerAi.Tools.Functions.pas', 1416),
    (r'D:\zPython\MakerAi\Source\Tools\uMakerAi.Tools.Functions.pas', 2357),
    (r'D:\zPython\MakerAi\Source\Tools\uMakerAi.Tools.Functions.pas', 2924),
    (r'D:\zPython\MakerAi\Source\Tools\uMakerAi.Tools.Functions.pas', 316),
]

for fp, lineno in lines_to_check:
    with open(fp, 'r', encoding='utf-8-sig') as f:
        lines = f.readlines()
    if lineno <= len(lines):
        print(f'{os.path.basename(fp)}:{lineno}: {lines[lineno-1].rstrip()}')
