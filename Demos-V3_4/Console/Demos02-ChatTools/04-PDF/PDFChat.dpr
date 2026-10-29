program PDFChat;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 02-ChatTools / 04-PDF
// =============================================================================
// Sends PDF documents to the LLM so it can read, summarize, and answer questions
// about their content.
//
// Concepts covered:
//   - Attach PDFs just like images (TAiMediaFile.LoadFromFile)
//   - Enable Tfc_Pdf in NativeInputFiles and Tcm_Pdf in ChatMediaSupports
//   - Extract structured information from documents
//   - Q&A about the PDF content
//   - Automatic summary
//   - Providers with native support: Claude, Gemini
//
// Note: If you don't have a PDF available, the demo creates a test one.
// =============================================================================

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Claude,
  uMakerAi.Chat.OpenAi,
  uMakerAi.Chat.Gemini;

const
  DRIVER  = 'Claude';
  MODEL   = 'claude-haiku-4-5-20251001';
  API_KEY = '@CLAUDE_API_KEY';

  // Path to your test PDF — adjust according to your system
  // If the file does not exist, the demo explains how to get one
  PDF_PATH = 'C:\Users\Public\Documents\sample.pdf';

  PDF_FALLBACK_URL = 'https://www.w3.org/WAI/WCAG21/wcag21.pdf';

// =============================================================================
//  Envía un PDF con una pregunta
// =============================================================================
function AskAboutPDF(Conn: TAiChatConnection;
                     const PdfPath, Question: String): String;
var
  MediaFile : TAiMediaFile;
  MediaList : TAiMediaFilesArray;
begin
  Conn.Messages.Clear;

  MediaFile := TAiMediaFile.Create;
  try
    MediaFile.LoadFromFile(PdfPath);
    SetLength(MediaList, 1);
    MediaList[0] := MediaFile;

    Result := Conn.AddMessageAndRun(Question, 'user', MediaList);
  finally
    MediaFile.Free;
  end;
end;

// =============================================================================
//  DEMO principal
// =============================================================================
procedure RunDemo;
var
  Conn    : TAiChatConnection;
  PdfPath : String;
  Response: String;
begin
  Writeln('=== PDFChat ===');
  Writeln('Driver: ', DRIVER, ' / Model: ', MODEL);
  Writeln;

  // Verify that the PDF exists
  PdfPath := PDF_PATH;

  // Search for a system PDF if the configured one does not exist
  if not TFile.Exists(PdfPath) then
  begin
    Writeln('Test PDF not found at: ', PdfPath);
    Writeln;
    Writeln('To run this demo you need a PDF file.');
    Writeln('Options:');
    Writeln('  1. Edit PDF_PATH in the code with the path to your PDF');
    Writeln('  2. Download a test one: ', PDF_FALLBACK_URL);
    Writeln('  3. Use any PDF you have on your system');
    Writeln;

    // Search for any PDF in Documents
    var Files := TDirectory.GetFiles(
      TPath.GetDocumentsPath, '*.pdf', TSearchOption.soAllDirectories);

    if Length(Files) > 0 then
    begin
      PdfPath := Files[0];
      Writeln(Format('PDF found automatically: %s', [PdfPath]));
      Writeln;
    end
    else
    begin
      Writeln('No PDF found. Demo canceled.');
      Exit;
    end;
  end;

  Writeln(Format('PDF to analyze: %s', [TPath.GetFileName(PdfPath)]));
  Writeln(Format('Size         : %.1f KB', [TFile.GetSize(PdfPath) / 1024]));
  Writeln;

  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;

    Conn.Params.Values['ApiKey']            := API_KEY;
    Conn.Params.Values['Asynchronous']      := 'False';
    Conn.Params.Values['Max_Tokens']        := '2048';
    Conn.Params.Values['ResponseTimeOut']   := '120000';

    // Activar soporte de PDF
    Conn.Params.Values['NativeInputFiles']  := '[Tfc_Pdf]';
    Conn.Params.Values['ChatMediaSupports'] := '[Tcm_Pdf]';

    Conn.SystemPrompt.Text :=
      'You are an assistant specialized in document analysis. ' +
      'Read the attached document carefully and respond accurately. ' +
      'Respond in Spanish.';

    // ── Demo 1: Executive summary ─────────────────────────────────────────
    Writeln(StringOfChar('-', 60));
    Writeln('1. Executive summary of the document');
    Response := AskAboutPDF(Conn, PdfPath,
      'Please provide an executive summary of this document in ' +
      'maximum 5 key points.');
    Writeln(Response);
    Writeln;

    // ── Demo 2: Specific questions ─────────────────────────────────────
    Writeln(StringOfChar('-', 60));
    Writeln('2. Specific questions about the content');

    Response := AskAboutPDF(Conn, PdfPath,
      'What are the main topics covered in this document? ' +
      'List only the titles or sections you find.');
    Writeln(Response);
    Writeln;

    // ── Demo 3: Data extraction ───────────────────────────────────────
    Writeln(StringOfChar('-', 60));
    Writeln('3. Structured data extraction');

    Response := AskAboutPDF(Conn, PdfPath,
      'Extract the following data from the document in JSON format: ' +
      '{"titulo": "", "autor": "", "fecha": "", "paginas_aproximadas": 0, ' +
      '"idioma": ""}. If you do not find any data, set it to null.');
    Writeln(Response);

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
