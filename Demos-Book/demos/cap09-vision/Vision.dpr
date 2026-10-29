program Vision;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — Chapter 9: Artificial Vision with Ollama (100% local)
// =============================================================================
// Demonstrates image analysis using multimodal models in Ollama.
// The image never leaves your machine — total privacy, no API key.
//
// Model: gemma3:4b (native vision, ModelCaps = [cap_Image])
//   → ollama pull gemma3:4b
//   Alternativas: 'llava:latest', 'llama3.2-vision:latest', 'moondream:latest'
//
// Demonstrates:
//   - Demo 1: General description of an image — the base vision pattern.
//   - Demo 2: OCR — extraction of visible text in the image.
//   - Demo 3: Structured extraction — request JSON with detected elements.
//   - Demo 4: Multi-turn conversation with image — the model remembers the
//             image in following turns without resending it.
//   - Demo 5: Comparison of two images — multiple files in one message.
//
// Prerequisite:
//   Ollama running on localhost:11434 with model gemma3:4b.
//   Instalar: https://ollama.com
//   Modelo:   ollama pull gemma3:4b
// =============================================================================

uses
  System.SysUtils,
  System.IOUtils,
  System.Net.HttpClient,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Ollama;   // DriverName = 'Ollama'

const
  DRIVER = 'Ollama';
  MODEL  = 'gemma3:4b';   // Vision + texto. Alternativas: llava:latest

  OLLAMA_URL = 'http://localhost:11434/';

  // Windows wallpaper — present in all installations
  IMG1 = 'C:\Windows\Web\Wallpaper\Windows\img0.jpg';

  // Second image for Demo 5 (comparison)
  // If it does not exist, the demo automatically searches for another image in the system
  IMG2 = 'C:\Windows\Web\Wallpaper\Windows\img0.jpg';  // reemplazar si tienes otra

procedure Separador(const Titulo: string);
begin
  WriteLn('');
  WriteLn(StringOfChar('-', 62));
  WriteLn('  ', Titulo);
  WriteLn(StringOfChar('-', 62));
end;

// =============================================================================
//  Verifica que Ollama esté corriendo.
// =============================================================================
function OllamaActivo: Boolean;
var
  Client: THTTPClient;
begin
  Result := False;
  Client := THTTPClient.Create;
  try
    try
      Client.Get(OLLAMA_URL);
      Result := True;
    except
      Result := False;
    end;
  finally
    Client.Free;
  end;
end;

// =============================================================================
//  Crea y configura la conexión Ollama con gemma3:4b.
//  El llamador es responsable de liberar con Free.
// =============================================================================
function CrearConexion: TAiChatConnection;
begin
  Result := TAiChatConnection.Create(nil);
  Result.DriverName := DRIVER;
  Result.Model      := MODEL;
  Result.Params.Values['Asynchronous'] := 'False';  // Ollama default es True
  Result.Params.Values['Max_Tokens']   := '512';
  Result.SystemPrompt.Text :=
    'Eres un asistente experto en análisis visual. ' +
    'Describe lo que ves de forma clara y concisa. Responde en español.';
end;

// =============================================================================
//  Demo 1 — Descripción general
//
//  The base vision pattern with MakerAI:
//    1. Create a TAiMediaFile and load the image
//    2. Pass it as the third parameter of AddMessageAndRun
//    3. The model receives it and generates a description
//
//  gemma3:4b has ModelCaps=[cap_Image] → native vision, without bridge.
// =============================================================================
procedure Demo1_Descripcion(Conn: TAiChatConnection);
var
  MF   : TAiMediaFile;
  Files: TAiMediaFilesArray;
  R    : string;
begin
  Separador('Demo 1 — General description of the image');

  MF := TAiMediaFile.Create;
  MF.LoadFromFile(IMG1);
  WriteLn('  Image: ', MF.FileName);
  WriteLn('  Type  : ', MF.MimeType, '  (', MF.Bytes div 1024, ' KB)');
  WriteLn('');

  SetLength(Files, 1);
  Files[0] := MF;

  Conn.NewChat;
  Write('  Describing image... ');
  R := Conn.AddMessageAndRun(
    'Describe this image in detail: what do you see? objects, colors, atmosphere.',
    'user', Files);
  WriteLn('OK');
  WriteLn('');
  WriteLn('  Description:');
  WriteLn('  ', R);

  WriteLn('');
  WriteLn('→ Base pattern: MF.LoadFromFile + AddMessageAndRun([MF]).');
  WriteLn('  gemma3:4b processes the image natively (ModelCaps=[cap_Image]).');
end;

// =============================================================================
//  Demo 2 — OCR: extracción de texto visible
//
//  Vision models can read text in images as if it were OCR.
//  For scanned documents, screenshots with text, signs, etc.
// =============================================================================
procedure Demo2_OCR(Conn: TAiChatConnection);
var
  MF   : TAiMediaFile;
  Files: TAiMediaFilesArray;
  R    : string;
begin
  Separador('Demo 2 — OCR: extraction of visible text');

  MF := TAiMediaFile.Create;
  MF.LoadFromFile(IMG1);

  SetLength(Files, 1);
  Files[0] := MF;

  Conn.NewChat;
  Write('  Extracting visible text... ');
  R := Conn.AddMessageAndRun(
    'Is there visible text in this image? ' +
    'If yes, transcribe it exactly. ' +
    'If there is no text, respond: "No visible text."',
    'user', Files);
  WriteLn('OK');
  WriteLn('');
  WriteLn('  Text found:');
  WriteLn('  ', R);

  WriteLn('');
  WriteLn('→ Multimodal models perform intelligent OCR: they understand context,');
  WriteLn('  position and format of the text, not just the characters.');
end;

// =============================================================================
//  Demo 3 — Extracción estructurada (JSON)
//
//  Ask the model to return the data in structured JSON format.
//  Useful for direct integration with applications: parse with TJSONObject.
// =============================================================================
procedure Demo3_JSON(Conn: TAiChatConnection);
var
  MF   : TAiMediaFile;
  Files: TAiMediaFilesArray;
  R    : string;
begin
  Separador('Demo 3 — Structured extraction (JSON response)');

  MF := TAiMediaFile.Create;
  MF.LoadFromFile(IMG1);

  SetLength(Files, 1);
  Files[0] := MF;

  Conn.NewChat;
  Conn.SystemPrompt.Text :=
    'You are a visual analysis system. ' +
    'Responde ÚNICAMENTE con JSON válido. Sin texto adicional fuera del JSON.';

  Write('  Extracting structured data... ');
  R := Conn.AddMessageAndRun(
    'Analyze this image and return a JSON with this exact format: ' +
    '{"escena": "brief description", ' +
    '"colores_principales": ["color1", "color2", "color3"], ' +
    '"objetos": ["obj1", "obj2"], ' +
    '"hay_texto": false, ' +
    '"ambiente": "indoor|outdoor|abstract"}',
    'user', Files);
  WriteLn('OK');
  WriteLn('');
  WriteLn('  JSON returned:');
  WriteLn('  ', R);

  // Restore system prompt for following demos
  Conn.SystemPrompt.Text :=
    'Eres un asistente experto en análisis visual. ' +
    'Describe lo que ves de forma clara y concisa. Responde en español.';

  WriteLn('');
  WriteLn('→ JSON in SystemPrompt + format example = parseable response.');
  WriteLn('  Combine with TJSONObject.ParseJSONValue() to process in Delphi.');
end;

// =============================================================================
//  Demo 4 — Conversación multi-turno con imagen
//
//  Once the image is sent in the first turn, the model "remembers" its
//  content in the following turns. There is no need to resend the image.
//  This allows a natural conversation about the same image.
// =============================================================================
procedure Demo4_MultiTurno(Conn: TAiChatConnection);
var
  MF   : TAiMediaFile;
  Files: TAiMediaFilesArray;
  R    : string;
begin
  Separador('Demo 4 — Multi-turn conversation about the image');

  MF := TAiMediaFile.Create;
  MF.LoadFromFile(IMG1);

  SetLength(Files, 1);
  Files[0] := MF;

  Conn.NewChat;

  // Turno 1: enviar la imagen con la primera pregunta
  Write('  [Turn 1] Sending image... ');
  R := Conn.AddMessageAndRun(
    'Look at this image. What is the most prominent element you see?',
    'user', Files);
  WriteLn('OK');
  WriteLn('  Response: ', R);
  WriteLn('  [History: ', Conn.Messages.Count, ' messages]');

  // Turno 2: segunda pregunta SIN reenviar la imagen
  WriteLn('');
  Write('  [Turn 2] Follow-up question (without resending image)... ');
  R := Conn.AddMessageAndRun(
    'What colors predominate in that area?',
    'user', []);  // ← without image in the array
  WriteLn('OK');
  WriteLn('  Response: ', R);
  WriteLn('  [History: ', Conn.Messages.Count, ' messages]');

  // Turno 3: otra pregunta de contexto
  WriteLn('');
  Write('  [Turn 3] Another context question... ');
  R := Conn.AddMessageAndRun(
    'What mood or feeling does this image convey?',
    'user', []);
  WriteLn('OK');
  WriteLn('  Response: ', R);
  WriteLn('  [History: ', Conn.Messages.Count, ' messages]');

  WriteLn('');
  WriteLn('→ The image is sent only ONCE (Turn 1).');
  WriteLn('  Turns 2 and 3 use the history to maintain context.');
  WriteLn('  The orchestrator does not resend the image — saves tokens and time.');
end;

// =============================================================================
//  Demo 5 — Dos imágenes en un mismo mensaje (comparación)
//
//  MakerAI allows sending multiple TAiMediaFile in a single call.
//  The model receives both images and can compare them, contrast them
//  or analyze them jointly.
// =============================================================================
procedure Demo5_DosImagenes(Conn: TAiChatConnection);
var
  MF1, MF2  : TAiMediaFile;
  Files     : TAiMediaFilesArray;
  R         : string;
  Img2Path  : string;
begin
  Separador('Demo 5 — Comparison of two images');

  // Buscar una segunda imagen en el sistema si IMG2 es igual a IMG1
  Img2Path := IMG2;
  if SameText(Img2Path, IMG1) then
  begin
    // Buscar en carpetas de wallpapers de Windows
    var Candidatos := TDirectory.GetFiles(
      'C:\Windows\Web', '*.jpg', TSearchOption.soAllDirectories);
    for var Ruta in Candidatos do
    begin
      if not SameText(Ruta, IMG1) then
      begin
        Img2Path := Ruta;
        Break;
      end;
    end;
  end;

  if SameText(Img2Path, IMG1) then
  begin
    WriteLn('  Only one different image was found.');
    WriteLn('  For this demo, adjust IMG2 to another image on your system.');
    WriteLn('  (Showing the pattern with the same image twice)');
    WriteLn('');
  end;

  MF1 := TAiMediaFile.Create;
  MF2 := TAiMediaFile.Create;
  MF1.LoadFromFile(IMG1);
  MF2.LoadFromFile(Img2Path);

  WriteLn('  Image 1: ', MF1.FileName);
  WriteLn('  Image 2: ', MF2.FileName);
  WriteLn('');

  // Enviar las dos imágenes en el mismo mensaje
  SetLength(Files, 2);
  Files[0] := MF1;
  Files[1] := MF2;

  Conn.NewChat;
  Write('  Comparing two images... ');
  R := Conn.AddMessageAndRun(
    'Analyze these two images. ' +
    'What do they have in common? What are the main differences? ' +
    'Respond in 3-4 sentences.',
    'user', Files);
  WriteLn('OK');
  WriteLn('');
  WriteLn('  Comparative analysis:');
  WriteLn('  ', R);

  WriteLn('');
  WriteLn('→ Multi-image pattern: SetLength(Files, N) + assign each MF.');
  WriteLn('  The model receives both images in the same message context.');
end;

// =============================================================================
//  MAIN
// =============================================================================
procedure RunDemo;
var
  Conn: TAiChatConnection;
begin
  WriteLn('=== MakerAI — Chapter 9: Vision with Ollama (100% local) ===');
  WriteLn('Model: ', MODEL, '  [ModelCaps = cap_Image — native vision]');
  WriteLn('The image never leaves your machine.');

  if not OllamaActivo then
  begin
    WriteLn('');
    WriteLn('[!!] Ollama not detected at ', OLLAMA_URL);
    WriteLn('     Install : https://ollama.com');
    WriteLn('     Model   : ollama pull gemma3:4b');
    WriteLn('     Start    : ollama serve');
    Exit;
  end;

  WriteLn('');
  WriteLn('[OK] Ollama detected. Using ', DRIVER, ' / ', MODEL);

  if not TFile.Exists(IMG1) then
  begin
    WriteLn('');
    WriteLn('[!!] Test image not found: ', IMG1);
    WriteLn('     Adjust the IMG1 constant to a JPEG image on your system.');
    Exit;
  end;

  Conn := CrearConexion;
  try
    Demo1_Descripcion(Conn);
    Demo2_OCR(Conn);
    Demo3_JSON(Conn);
    Demo4_MultiTurno(Conn);
    Demo5_DosImagenes(Conn);
  finally
    Conn.Free;
  end;

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
