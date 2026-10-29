program MediaFile;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — Chapter 8: TAiMediaFile — The Universal Envelope for Files
// =============================================================================
// Demonstrates the capabilities of TAiMediaFile: the abstraction that allows
// sending images, audio, PDF and any file to the same code
// regardless of the provider.
//
// Demonstrates:
//   - Demo 1: The 4 loading forms and their automatic metadata.
//             LoadFromFile, LoadFromBase64, LoadFromStream, LoadFromUrl.
//   - Demo 2: Categories and global utility functions.
//             GetContentCategory, GetMimeTypeFromFileName,
//             GetFileExtensionFromMimeType, StreamToBase64.
//   - Demo 3: Complete serialization — ToJsonObject / LoadFromJsonObject.
//             Preserves IdFile/CloudName to reuse already uploaded files.
//   - Demo 4: Adaptive prompt according to the detected file type.
//             The same code chooses the correct prompt for each FileCategory.
//             Includes a real call to Groq with a text file.
//
// Demos 1, 2 and 3 do not require any API key (local operations only).
// Demo 4 uses GROQ_API_KEY to demonstrate sending a text file.
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.TypInfo,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Groq;   // For Demo 4

const
  DRIVER  = 'Groq';
  MODEL   = 'llama-3.3-70b-versatile';
  API_KEY = '@GROQ_API_KEY';

  // Image always available on Windows
  IMG_PATH  = 'C:\Windows\Web\Wallpaper\Windows\img0.jpg';

  // Text file always available on Windows (for Demo 1/2)
  TXT_PATH      = 'C:\Windows\win.ini';
  // .txt file created by Demo 4 (extension .txt → Tfc_Text)
  DEMO4_TXT     = '.\demo_cap08_config.txt';

procedure Separador(const Titulo: string);
begin
  WriteLn('');
  WriteLn(StringOfChar('-', 62));
  WriteLn('  ', Titulo);
  WriteLn(StringOfChar('-', 62));
end;

procedure MostrarMF(const Etiqueta: string; MF: TAiMediaFile);
begin
  WriteLn('  [', Etiqueta, ']');
  WriteLn('    FileName     : ', MF.FileName);
  WriteLn('    FileCategory : ', GetEnumName(TypeInfo(TAiFileCategory),
                                             Ord(MF.FileCategory)));
  WriteLn('    MimeType     : ', MF.MimeType);
  WriteLn('    Bytes        : ', MF.Bytes);
  WriteLn('    Base64 len   : ', Length(MF.Base64), ' chars');
end;

// =============================================================================
//  Demo 1 — The 4 ways to load a TAiMediaFile
//
//  All forms produce the same result: a TAiMediaFile with
//  FileName, FileCategory, MimeType y Bytes correctamente rellenos.
//  The type is detected automatically by the file name extension.
// =============================================================================
procedure Demo1_FormasDeCarga;
var
  MF     : TAiMediaFile;
  Stream : TMemoryStream;
  Base64 : string;
begin
  Separador('Demo 1 — The 4 ways to load a TAiMediaFile');

  // ── Form 1: LoadFromFile ─────────────────────────────────────────────────
  WriteLn('  Form 1: LoadFromFile (the most common)');
  if TFile.Exists(IMG_PATH) then
  begin
    MF := TAiMediaFile.Create;
    try
      MF.LoadFromFile(IMG_PATH);
      MostrarMF('LoadFromFile', MF);
      Base64 := MF.Base64;   // save for Form 3
    finally
      MF.Free;
    end;
  end
  else
    WriteLn('  Image not found: ', IMG_PATH);

  // ── Form 2: LoadFromBase64 ───────────────────────────────────────────────
  WriteLn('');
  WriteLn('  Form 2: LoadFromBase64 (from data received from another API)');
  if Base64 <> '' then
  begin
    MF := TAiMediaFile.Create;
    try
      MF.LoadFromBase64('imagen_recibida.jpg', Base64);
      MostrarMF('LoadFromBase64', MF);
    finally
      MF.Free;
    end;
  end;

  // ── Form 3: LoadFromStream ───────────────────────────────────────────────
  WriteLn('');
  WriteLn('  Form 3: LoadFromStream (from TMemoryStream in memory)');
  if TFile.Exists(TXT_PATH) then
  begin
    Stream := TMemoryStream.Create;
    try
      Stream.LoadFromFile(TXT_PATH);
      Stream.Position := 0;

      MF := TAiMediaFile.Create;
      try
        MF.LoadFromStream('configuracion.txt', Stream);
        MostrarMF('LoadFromStream', MF);
      finally
        MF.Free;
      end;
    finally
      Stream.Free;
    end;
  end;

  // ── Form 4: LoadFromUrl (lazy loading) ──────────────────────────────────
  WriteLn('');
  WriteLn('  Form 4: LoadFromUrl (download is lazy — occurs when accessing Content)');
  WriteLn('  Usage example (without real download in this demo):');
  WriteLn('');
  WriteLn('    MF.LoadFromUrl(''https://example.com/contract.pdf'');');
  WriteLn('    // FileName = "contract.pdf", FileCategory = Tfc_Pdf');
  WriteLn('    // Content not downloaded yet — lazy download on first access');
  WriteLn('    Respuesta := AiConn.AddMessageAndRun(''Summarize...'', ''user'', [MF]);');
  WriteLn('    // MakerAI accesses Content when building the request → download occurs here');

  WriteLn('');
  WriteLn('→ The 4 forms produce the same TAiMediaFile.');
  WriteLn('  The type is detected automatically by the file name extension.');
end;

// =============================================================================
//  Demo 2 — Global utility functions
//
//  MakerAI exposes three functions from uMakerAi.Core to inspect file
//  types without needing to create a TAiMediaFile.
// =============================================================================
procedure Demo2_Utilitarios;
type
  TExtRec = record Ext, Desc: string; end;
const
  EXTENSIONES: array[0..11] of TExtRec = (
    (Ext: '.jpg';  Desc: 'imagen JPEG'),
    (Ext: '.png';  Desc: 'imagen PNG'),
    (Ext: '.mp3';  Desc: 'audio MP3'),
    (Ext: '.mp4';  Desc: 'video MP4'),
    (Ext: '.pdf';  Desc: 'documento PDF'),
    (Ext: '.docx'; Desc: 'Word'),
    (Ext: '.xlsx'; Desc: 'Excel'),
    (Ext: '.txt';  Desc: 'texto plano'),
    (Ext: '.py';   Desc: 'Python'),
    (Ext: '.zip';  Desc: 'comprimido'),
    (Ext: '.glb';  Desc: '3D/CAD'),
    (Ext: '.epub'; Desc: 'ebook')
  );
  MIMES: array[0..5] of string = (
    'image/jpeg', 'audio/mpeg', 'video/mp4',
    'application/pdf', 'text/plain', 'image/webp'
  );
var
  Rec : TExtRec;
  Mime: string;
  Cat : TAiFileCategory;
begin
  Separador('Demo 2 — Funciones utilitarias globales (uMakerAi.Core)');

  WriteLn('  GetContentCategory(extension) — file category:');
  WriteLn('');
  WriteLn('  Extension  Category                 MimeType');
  WriteLn('  ' + StringOfChar('-', 58));
  for Rec in EXTENSIONES do
  begin
    Cat := GetContentCategory(Rec.Ext);
    WriteLn(Format('  %-10s %-24s %s',
      [Rec.Ext,
       GetEnumName(TypeInfo(TAiFileCategory), Ord(Cat)),
       GetMimeTypeFromFileName(Rec.Ext)]));
  end;

  WriteLn('');
  WriteLn('  GetFileExtensionFromMimeType(mime) — extension from MIME type:');
  WriteLn('');
  for Mime in MIMES do
    WriteLn(Format('  %-40s -> .%s', [Mime, GetFileExtensionFromMimeType(Mime)]));

  WriteLn('');
  WriteLn('  StreamToBase64(stream) — converts TMemoryStream to clean Base64:');
  if TFile.Exists(TXT_PATH) then
  begin
    var St := TMemoryStream.Create;
    try
      St.LoadFromFile(TXT_PATH);
      St.Position := 0;
      var B64 := StreamToBase64(St);
      WriteLn('  (', TPath.GetFileName(TXT_PATH), ' → Base64 of ', Length(B64), ' chars)');
      WriteLn('  First 60 chars: ', Copy(B64, 1, 60), '...');
    finally
      St.Free;
    end;
  end;

  WriteLn('');
  WriteLn('→ These functions work only with extensions/MIME types.');
  WriteLn('  They do not need to read the file — they are table-based resolutions.');
end;

// =============================================================================
//  Demo 3 — Serialization: ToJsonObject / LoadFromJsonObject
//
//  TAiMediaFile can export and import its complete state as JSON.
//  Key use case: save IdFile/CloudName to reuse a file
//  already uploaded to the provider in a future session without re-uploading it.
// =============================================================================
procedure Demo3_Serializacion;
const
  JSON_ESTADO = '.\estado_mediafile.json';
var
  MF       : TAiMediaFile;
  MF2      : TAiMediaFile;
  JObj     : TJSONObject;
  JStr     : string;
  JCargado : TJSONObject;
begin
  Separador('Demo 3 — Serialization (ToJsonObject / LoadFromJsonObject)');

  if not TFile.Exists(IMG_PATH) then
  begin
    WriteLn('  Image not found: ', IMG_PATH);
    Exit;
  end;

  // Simulate a file already uploaded to a provider (IdFile assigned)
  MF := TAiMediaFile.Create;
  try
    MF.LoadFromFile(IMG_PATH);

    // Simulate that the provider assigned an IdFile (it would do so automatically in real use)
    MF.IdFile := 'file-abc12345xyz';   // OpenAI
    MF.Detail := 'high';               // OpenAI analysis quality

    // Exportar estado completo a JSON
    JObj := MF.ToJsonObject;
    try
      JStr := JObj.Format;
      TFile.WriteAllText(JSON_ESTADO, JStr, TEncoding.UTF8);
      WriteLn('  State saved in: ', JSON_ESTADO);
      WriteLn('  Fields in JSON: FileName, MimeType, Base64, IdFile, Detail...');

      // Show JSON fragment (first 300 chars)
      var Fragmento := Copy(JStr, 1, 300);
      WriteLn('');
      WriteLn('  JSON fragment:');
      WriteLn('  ', Fragmento, '...');
    finally
      JObj.Free;
    end;
  finally
    MF.Free;
  end;

  WriteLn('');

  // Restore from JSON in a "new session"
  WriteLn('  Restoring from JSON (simulates new session)...');
  MF2 := TAiMediaFile.Create;
  try
    JCargado := TJSONObject.ParseJSONValue(
      TFile.ReadAllText(JSON_ESTADO, TEncoding.UTF8)) as TJSONObject;
    try
      MF2.LoadFromJsonObject(JCargado);
    finally
      JCargado.Free;
    end;

    WriteLn('  State restored:');
    WriteLn('    FileName : ', MF2.FileName);
    WriteLn('    MimeType : ', MF2.MimeType);
    WriteLn('    Bytes    : ', MF2.Bytes);
    WriteLn('    IdFile   : ', MF2.IdFile, '  ← the provider does not re-upload the file');
    WriteLn('    Detail   : ', MF2.Detail);
  finally
    MF2.Free;
  end;

  // Clean up temporary file
  if TFile.Exists(JSON_ESTADO) then
    TFile.Delete(JSON_ESTADO);

  WriteLn('');
  WriteLn('→ With IdFile/CloudName restored, MakerAI uses the file already');
  WriteLn('  uploaded without needing to re-upload it. Saves time and bandwidth.');
end;

// =============================================================================
//  Demo 4 — Adaptive prompt by file type + send to Groq
//
//  The same code chooses the correct prompt according to MF.FileCategory.
//  In this demo, we send an .ini file (Tfc_Text) to Groq to demonstrate
//  the complete flow: load → type detection → send → response.
// =============================================================================
procedure Demo4_PromptAdaptativo;
const
  TXT_CONTENIDO =
    'Configuration of the application MiApp v2.5.3' + #13#10 +
    'modo_oscuro=true' + #13#10 +
    'idioma=es' + #13#10 +
    'max_usuarios=100' + #13#10 +
    'servidor=api.miapp.com' + #13#10 +
    'puerto=8443' + #13#10 +
    'timeout_ms=30000';

  function ElegirPrompt(MF: TAiMediaFile): string;
  begin
    case MF.FileCategory of
      Tfc_Image:
        Result := 'Describe this image in detail: objects, colors, context.';
      Tfc_Audio:
        Result := 'Transcribe and summarize the content of this audio.';
      Tfc_Video:
        Result := 'Describe what happens in this video, scene by scene.';
      Tfc_Pdf,
      Tfc_Document:
        Result := 'Summarize the key points of this document in 5 points.';
      Tfc_CalcSheet:
        Result := 'Analyze the data in this spreadsheet and provide statistics.';
      Tfc_Text,
      Tfc_Web,
      Tfc_ExtractTextFile:
        Result := 'Analyze the content of this text file and explain its purpose.';
    else
      Result := 'Analyze the content of this file and describe what you find.';
    end;
  end;

var
  MF    : TAiMediaFile;
  Conn  : TAiChatConnection;
  Files : TAiMediaFilesArray;
  Prompt: string;
  R     : string;
begin
  Separador('Demo 4 — Adaptive prompt by type + sending to Groq');

  // Create temporary .txt file with known content
  TFile.WriteAllText(DEMO4_TXT, TXT_CONTENIDO, TEncoding.UTF8);

  MF := TAiMediaFile.Create;
  MF.LoadFromFile(DEMO4_TXT);

    WriteLn('  File       : ', MF.FileName);
    WriteLn('  Category   : ', GetEnumName(TypeInfo(TAiFileCategory), Ord(MF.FileCategory)));
    WriteLn('  MimeType   : ', MF.MimeType);
    WriteLn('  Bytes      : ', MF.Bytes);

    Prompt := ElegirPrompt(MF);
    WriteLn('');
    WriteLn('  Prompt chosen automatically:');
    WriteLn('  "', Prompt, '"');
    WriteLn('');

    // Send to LLM
    Conn := TAiChatConnection.Create(nil);
    try
      Conn.DriverName := DRIVER;
      Conn.Model      := MODEL;
      Conn.Params.Values['ApiKey']       := API_KEY;
      Conn.Params.Values['Asynchronous'] := 'False';
      Conn.Params.Values['Max_Tokens']   := '300';

      Conn.SystemPrompt.Text :=
        'You are an assistant that analyzes files. Respond in Spanish, concisely.';

      // For text-only models (Groq, DeepSeek, etc.) file content
    // goes inline in the prompt — not as a binary attachment.
    // For multimodal models (Gemini, Claude, OpenAI) you would use Files[0] := MF.
    var FileContent := TFile.ReadAllText(DEMO4_TXT, TEncoding.UTF8);
    var PromptFinal := Prompt + #13#10#13#10 +
      '--- File content ---' + #13#10 + FileContent;

    Write('  Sending to Groq (inline content)... ');
    try
      R := Conn.AddMessageAndRun(PromptFinal, 'user', []);
      WriteLn('OK');
      WriteLn('');
      WriteLn('  Groq response:');
      WriteLn('  ', R);
    except
      on E: Exception do
      begin
        WriteLn('ERROR');
        WriteLn('  ', E.Message);
      end;
    end;

    MF.Free;  // MF was not passed to AddMessageAndRun — normal release
  finally
    Conn.Free;
  end;

  // Clean up temporary file
  if TFile.Exists(DEMO4_TXT) then
    TFile.Delete(DEMO4_TXT);

  WriteLn('');
  WriteLn('→ The same code works with any file type.');
  WriteLn('  Change TXT_PATH to an image, PDF or audio (with the correct provider).');
end;

// =============================================================================
//  MAIN
// =============================================================================
procedure RunDemo;
begin
  WriteLn('=== MakerAI — Chapter 8: TAiMediaFile ===');
  WriteLn('The universal envelope: the same class for image, audio, PDF, text...');

  Demo1_FormasDeCarga;
  Demo2_Utilitarios;
  Demo3_Serializacion;
  Demo4_PromptAdaptativo;

  WriteLn('');
  WriteLn(StringOfChar('=', 62));
  WriteLn('  Demo completed.');
  WriteLn(StringOfChar('=', 62));
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      WriteLn('ERROR: ', E.ClassName, ' — ', E.Message);
  end;
  WriteLn('');
  WriteLn('Press Enter to exit...');
  ReadLn;
end.
