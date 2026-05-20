import docx, os
files = [
    (r'D:\zPython\MakerAi\Docs\Version 3\EN\uMakerAi.Chat\uMakerAi.Chat_EN.docx', 'Chat EN'),
    (r'D:\zPython\MakerAi\Docs\Version 3\EN\RAG\uMakerAi-RAG_EN.docx', 'RAG EN'),
    (r'D:\zPython\MakerAi\Docs\Version 3\EN\Manual-Installation\Manual-Installation_EN.docx', 'Install EN'),
    (r'D:\zPython\MakerAi\Docs\Version 3\ES\uMakerAi.Chat.docx', 'Chat ES'),
    (r'D:\zPython\MakerAi\Docs\Version 3\ES\RAG\uMakerAi-RAG.docx', 'RAG ES'),
]
for fp, label in files:
    if not os.path.exists(fp):
        print(f'{label}: MISSING')
        continue
    try:
        doc = docx.Document(fp)
        text = ' '.join(p.text for p in doc.paragraphs[:5])
        print(f'\n=== {label} ({os.path.getsize(fp)/1024:.0f}KB) ===')
        print(text[:250])
    except Exception as e:
        print(f'{label}: ERROR {e}')
