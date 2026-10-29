program Vision;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 02-ChatTools / 03-Vision
// =============================================================================
// Sends images to the LLM so it can describe, analyze, or extract information from them.
//
// Concepts it covers:
//   - Attach images with TAiMediaFile.LoadFromFile()
//   - Pass mediafiles in AddMessageAndRun()
//   - Enable vision capability (ChatMediaSupports)
//   - Difference between models with native vision vs. automatic bridge
//   - Use cases: description, OCR, technical analysis, comparison
//
// Providers with native vision:
//   Claude, OpenAI (GPT-4V), Gemini → use the image directly
// Providers without native vision:
//   Ollama (gemma3:4b), Groq → MakerAI activates an automatic OCR bridge
//
// Test images: create image files in the same folder or adjust
// the IMG_PATH path to an existing image on your system.
// =============================================================================

uses
  System.SysUtils,
  System.IOUtils,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Claude,
  uMakerAi.Chat.OpenAi,
  uMakerAi.Chat.Gemini,
  uMakerAi.Chat.Ollama;

const
  DRIVER  = 'Claude';
  MODEL   = 'claude-haiku-4-5-20251001';
  API_KEY = '@CLAUDE_API_KEY';

  // Adjust these paths to real images on your system
  IMG_SCREENSHOT = 'C:\Windows\Web\Wallpaper\Windows\img0.jpg';  // Default wallpaper
  IMG_CUSTOM     = '';  // Leave empty if you don't have another image

// =============================================================================
//  Envía una imagen con una pregunta y muestra la respuesta
// =============================================================================
procedure AskAboutImage(Conn: TAiChatConnection;
                        const ImagePath, Question, SectionTitle: String);
var
  MediaFile : TAiMediaFile;
  MediaList : TAiMediaFilesArray;
  Response  : String;
begin
  if not TFile.Exists(ImagePath) then
  begin
    Writeln(Format('  [%s] — Image not found: %s', [SectionTitle, ImagePath]));
    Writeln('  Adjust IMG_SCREENSHOT to an existing image on your system.');
    Exit;
  end;

  Writeln(StringOfChar('-', 60));
  Writeln(Format('  %s', [SectionTitle]));
  Writeln(Format('  Image   : %s', [TPath.GetFileName(ImagePath)]));
  Writeln(Format('  Question: %s', [Question]));
  Writeln;

  Conn.Messages.Clear;

  MediaFile := TAiMediaFile.Create;
  try
    MediaFile.LoadFromFile(ImagePath);
    SetLength(MediaList, 1);
    MediaList[0] := MediaFile;

    Response := Conn.AddMessageAndRun(Question, 'user', MediaList);
    Writeln('  Response:');
    Writeln('  ', Response);
  finally
    MediaFile.Free;
  end;
  Writeln;
end;

// =============================================================================
//  DEMO principal
// =============================================================================
procedure RunDemo;
var
  Conn    : TAiChatConnection;
  ImgPath : String;
begin
  Writeln('=== Vision ===');
  Writeln('Driver: ', DRIVER, ' / Model: ', MODEL);
  Writeln;

  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;

    Conn.Params.Values['ApiKey']            := API_KEY;
    Conn.Params.Values['Asynchronous']      := 'False';
    Conn.Params.Values['Max_Tokens']        := '1024';

    Conn.SystemPrompt.Text :=
      'Eres un asistente experto en análisis de imágenes. ' +
      'Describe what you see in detail and accurately. Respond in Spanish.';

    // Determine image to use
    ImgPath := IMG_SCREENSHOT;
    if (IMG_CUSTOM <> '') and TFile.Exists(IMG_CUSTOM) then
      ImgPath := IMG_CUSTOM;

    // ── Demo 1: general description ──────────────────────────────────────
    AskAboutImage(Conn, ImgPath,
      'Describe this image in detail: what do you see? colors, objects, context.',
      'General description');

    // ── Demo 2: specific analysis ──────────────────────────────────────
    AskAboutImage(Conn, ImgPath,
      'Which colors predominate in this image? List the 3 most important.',
      'Color analysis');

    // ── Demo 3: concrete question ────────────────────────────────────────
    AskAboutImage(Conn, ImgPath,
      'Is there visible text in the image? If so, transcribe it exactly.',
      'Text extraction (OCR)');

    // ── Demo 4: custom image if provided ───────────────────
    if (IMG_CUSTOM <> '') and TFile.Exists(IMG_CUSTOM) then
      AskAboutImage(Conn, IMG_CUSTOM,
        'Analyze this image from a technical or artistic point of view.',
        'Custom image analysis');

    Writeln('Note: Try changing DRIVER to "Gemini" or "OpenAI" to');
    Writeln('compare how each model describes the same image.');

  finally
    Conn.Free;
  end;
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      Writeln('ERROR: ', E.ClassName, ' — ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
