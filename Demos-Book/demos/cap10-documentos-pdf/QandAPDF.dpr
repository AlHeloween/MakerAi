program QandAPDF;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — Chapter 10: PDF Document Processing
// =============================================================================
// Demonstrates two complementary strategies for working with documents:
//
//   Strategy A — Native PDF with Gemini (requires GEMINI_API_KEY):
//     gemini-2.5-flash receives the PDF directly (ModelCaps includes cap_Pdf).
//     The model processes text, tables and images of the PDF in full.
//
//   Strategy B — Embedded text with Ollama (100% local, no API key):
//     Ollama has no native PDF support → we read the text and send it
//     as context in the SystemPrompt. Total privacy: the document
//     never leaves your machine.
//
// Demos:
//   1. Native PDF with Gemini — executive summary of the document
//   2. Multi-turn over PDF — the model remembers the document in history
//   3. JSON extraction from PDF — structured data to process in Delphi
//   4. Ollama + text context — local Q&A without native PDF support
//
// Requirements:
//   Demos 1-3: GEMINI_API_KEY in environment variables
//              An accessible .pdf file (adjust PDF_PATH or the path at runtime)
//   Demo 4   : Ollama on localhost:11434 with gemma3:4b
//              Install: https://ollama.com  |  ollama pull gemma3:4b
// =============================================================================

uses
  System.SysUtils,
  System.IOUtils,
  System.Net.HttpClient,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Gemini,    // DriverName = 'Gemini' — auto-registers on import
  uMakerAi.Chat.Ollama;    // DriverName = 'Ollama' — auto-registers on import

const
  GEMINI_DRIVER = 'Gemini';
  GEMINI_MODEL  = 'gemini-3-flash-preview';

  OLLAMA_DRIVER = 'Ollama';
  OLLAMA_MODEL  = 'gemma3:4b';
  OLLAMA_URL    = 'http://localhost:11434/';

  // Path to the test PDF for Demos 1-3.
  // If the file does not exist, those demos are skipped with instructions.
  // You can use any PDF: a contract, invoice, manual, report...
  PDF_PATH = 'C:\Users\Public\Documents\sample.pdf';

// =============================================================================
procedure Separador(const Titulo: string);
begin
  WriteLn('');
  WriteLn(StringOfChar('-', 62));
  WriteLn('  ', Titulo);
  WriteLn(StringOfChar('-', 62));
end;

// =============================================================================
//  Checks that Ollama is running on localhost.
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
//  Checks that the GEMINI_API_KEY environment variable is configured.
// =============================================================================
function GeminiApiKeyDisponible: Boolean;
begin
  Result := GetEnvironmentVariable('GEMINI_API_KEY') <> '';
end;

// =============================================================================
//  Searches for a PDF in PDF_PATH and in the current directory.
//  Returns the path if found, empty string if not.
// =============================================================================
function EncontrarPDF: string;
var
  RutaLocal: string;
begin
  if TFile.Exists(PDF_PATH) then
    Exit(PDF_PATH);

  // Also search in the executable directory
  RutaLocal := ExtractFilePath(ParamStr(0)) + 'sample.pdf';
  if TFile.Exists(RutaLocal) then
    Exit(RutaLocal);

  // Search for any PDF in the current directory
  var Archivos := TDirectory.GetFiles(
    ExtractFilePath(ParamStr(0)), '*.pdf', TSearchOption.soTopDirectoryOnly);
  if Length(Archivos) > 0 then
    Exit(Archivos[0]);

  Result := '';
end;

// =============================================================================
//  Creates the connection with Gemini 2.5 Flash for PDF processing.
//  gemini-2.5-flash has ModelCaps that include cap_Pdf — native support.
//  The caller is responsible for freeing with Free.
// =============================================================================
function CrearConexionGemini: TAiChatConnection;
begin
  Result := TAiChatConnection.Create(nil);
  Result.DriverName := GEMINI_DRIVER;
  Result.Model      := GEMINI_MODEL;
  Result.Params.Values['ApiKey']       := '@GEMINI_API_KEY';
  Result.Params.Values['Asynchronous'] := 'False';
  Result.Params.Values['Max_Tokens']   := '1024';
  Result.SystemPrompt.Text :=
    'You are an assistant specialized in document analysis. ' +
    'Base your answers ONLY on the attached document content. ' +
    'If the information is not in the document, say so clearly. ' +
    'Respond concisely and precisely in Spanish.';
end;

// =============================================================================
//  Creates the connection with Ollama (gemma3:4b) for local Q&A.
//  The caller is responsible for freeing with Free.
// =============================================================================
function CrearConexionOllama: TAiChatConnection;
begin
  Result := TAiChatConnection.Create(nil);
  Result.DriverName := OLLAMA_DRIVER;
  Result.Model      := OLLAMA_MODEL;
  Result.Params.Values['Asynchronous'] := 'False';  // Ollama default is True
  Result.Params.Values['Max_Tokens']   := '512';
  Result.SystemPrompt.Text :=
    'You are a helpful assistant. Respond concisely and precisely in Spanish.';
end;

// =============================================================================
//  Demo 1 — Native PDF with Gemini
//
//  The base PDF pattern with MakerAI is identical to that of images:
//    1. Create TAiMediaFile and load the PDF with LoadFromFile
//    2. MF.FileCategory becomes fcDocument automatically
//    3. Pass it in AddMessageAndRun — Gemini processes it natively
//
//  MakerAI detects that Gemini has cap_Pdf and sends the file directly.
//  No additional configuration is needed.
// =============================================================================
procedure Demo1_PdfNativoGemini(const PdfPath: string; Conn: TAiChatConnection);
var
  MF   : TAiMediaFile;
  Files: TAiMediaFilesArray;
  R    : string;
begin
  Separador('Demo 1 — Native PDF with Gemini (Strategy A)');

  MF := TAiMediaFile.Create;
  MF.LoadFromFile(PdfPath);
  WriteLn('  File: ', MF.FileName);
  WriteLn('  Type   : ', MF.MimeType, '  (', MF.Bytes div 1024, ' KB)');
  WriteLn('');

  SetLength(Files, 1);
  Files[0] := MF;

  Conn.NewChat;
  Write('  Sending PDF to Gemini... ');
  R := Conn.AddMessageAndRun(
    'Read this document and give me an executive summary with: ' +
    '(1) main topic, (2) key points, (3) conclusion or required action. ' +
    'Maximum 5 lines in total.',
    'user', Files);
  WriteLn('OK');
  WriteLn('');
  WriteLn('  Summary:');
  WriteLn('  ', R);

  WriteLn('');
  WriteLn('→ Base pattern: MF.LoadFromFile(pdf) + AddMessageAndRun([MF]).');
  WriteLn('  Gemini 2.5 Flash processes the PDF in full (ModelCaps=[cap_Pdf]).');
  WriteLn('  Claude works the same — change DriverName to "Claude".');
end;

// =============================================================================
//  Demo 2 — Multi-turn Q&A over a PDF
//
//  Once attached in the first message, the model "remembers" the document
//  in the following turns without needing to resend it.
//  This allows a natural and efficient Q&A session.
// =============================================================================
procedure Demo2_MultiturnoGemini(const PdfPath: string; Conn: TAiChatConnection);
var
  MF   : TAiMediaFile;
  Files: TAiMediaFilesArray;
  R    : string;
begin
  Separador('Demo 2 — Multi-turn Q&A over PDF (the model remembers)');

  MF := TAiMediaFile.Create;
  MF.LoadFromFile(PdfPath);
  SetLength(Files, 1);
  Files[0] := MF;

  Conn.NewChat;

  // Turn 1: we send the PDF with the first question
  Write('  [Turn 1] Sending PDF... ');
  R := Conn.AddMessageAndRun(
    'I have attached a document. Confirm that you received it and say what it is about in one sentence.',
    'user', Files);
  WriteLn('OK');
  WriteLn('  Response: ', R);
  WriteLn('  [History: ', Conn.Messages.Count, ' messages]');

  // Turn 2: second question WITHOUT resending the PDF
  WriteLn('');
  Write('  [Turn 2] Question without resending PDF... ');
  R := Conn.AddMessageAndRun(
    'What are the three most important points in the document?',
    'user', []);   // ← without PDF in the array
  WriteLn('OK');
  WriteLn('  Response: ', R);
  WriteLn('  [History: ', Conn.Messages.Count, ' messages]');

  // Turn 3: detail question
  WriteLn('');
  Write('  [Turn 3] Detail question... ');
  R := Conn.AddMessageAndRun(
    'Are there important dates, amounts, or figures? Mention the most relevant ones.',
    'user', []);
  WriteLn('OK');
  WriteLn('  Response: ', R);
  WriteLn('  [History: ', Conn.Messages.Count, ' messages]');

  WriteLn('');
  WriteLn('→ The PDF is attached only ONCE (Turn 1).');
  WriteLn('  Turns 2 and 3 pass [] — the model remembers it in history.');
  WriteLn('  Conn.Messages.Count grows with each turn: system + user + assistant.');
end;

// =============================================================================
//  Demo 3 — Structured JSON extraction from PDF
//
//  Forcing a JSON response allows direct integration with the application:
//  parse with TJSONObject, save to database, etc.
//  Useful for invoices, contracts, forms, reports.
// =============================================================================
procedure Demo3_ExtraccionJSON(const PdfPath: string; Conn: TAiChatConnection);
var
  MF    : TAiMediaFile;
  Files : TAiMediaFilesArray;
  R     : string;
  OldSP : string;
begin
  Separador('Demo 3 — Structured extraction (JSON) from PDF');

  MF := TAiMediaFile.Create;
  MF.LoadFromFile(PdfPath);
  SetLength(Files, 1);
  Files[0] := MF;

  Conn.NewChat;

  // Save and replace the SystemPrompt to force JSON
  OldSP := Conn.SystemPrompt.Text;
  Conn.SystemPrompt.Text :=
    'You are a document data extractor. ' +
    'Respond ONLY with valid JSON. No additional text outside the JSON. ' +
    'If a field does not appear in the document, use null.';

  Write('  Extracting structured data... ');
  R := Conn.AddMessageAndRun(
    'Analyze this document and return a JSON with this exact schema: ' +
    '{"tipo_documento": "...", ' +
    '"fecha": "YYYY-MM-DD or null", ' +
    '"partes": ["name1", "name2"], ' +
    '"monto_total": 0.0, ' +
    '"moneda": "MXN/USD/EUR or null", ' +
    '"resumen": "one sentence"}',
    'user', Files);
  WriteLn('OK');
  WriteLn('');
  WriteLn('  Extracted JSON:');
  WriteLn('  ', R);

  // Restore SystemPrompt for following demos
  Conn.SystemPrompt.Text := OldSP;

  WriteLn('');
  WriteLn('→ SystemPrompt + JSON schema = parseable data.');
  WriteLn('  In Delphi: TJSONObject.ParseJSONValue(R) to process the result.');
  WriteLn('  Haiku (Claude) or Flash (Gemini) are the most economical options for batches.');
end;

// =============================================================================
//  Demo 4 — Ollama + embedded text (Strategy B, 100% local)
//
//  Ollama has no native PDF support (without cap_Pdf).
//  Practical alternative: extract the PDF text with Delphi and send it
//  as context in the SystemPrompt. The model does Q&A over that text.
//
//  For this demo we use an internal sample document (fictional invoice).
//  In production: use iTextSharp, PdfiumLib, or TAiNativePdfTool
//  (available in the AiMaker.ChatTools repo) for real text extraction.
// =============================================================================
procedure Demo4_OllamaTextoLocal(Conn: TAiChatConnection);
var
  Texto: string;
  R    : string;
begin
  Separador('Demo 4 — Ollama + Embedded Text (Strategy B, 100% local)');

  WriteLn('  Ollama does not process PDF natively — but we can embed');
  WriteLn('  the extracted text directly in the SystemPrompt.');
  WriteLn('  Result: Q&A over the document without it leaving your machine.');
  WriteLn('');

  // Sample document: fictional invoice
  // In production this text would come from a PDF reader:
  //   - TAiNativePdfTool (AiMaker.ChatTools): extractor 100% Delphi + Skia
  //   - PdfiumLib (open source Delphi component)
  //   - System.PDF.PDFium (Delphi 12+ in beta)
  Texto :=
    'ELECTRONIC INVOICE No. FE-2025-0142' + sLineBreak +
    'Issue date: March 10, 2025' + sLineBreak +
    sLineBreak +
    'SUPPLIER: Distribuidora Norte S.A. de C.V.' + sLineBreak +
    'RFC: DNO820315AB8' + sLineBreak +
    'Address: Calle Reforma 450, Col. Centro, CDMX 06040' + sLineBreak +
    sLineBreak +
    'CLIENT: Tech Solutions Monterrey S.A.' + sLineBreak +
    'RFC: TSM970612CD4' + sLineBreak +
    'Address: Av. Constitución 1200, Monterrey, N.L. 64000' + sLineBreak +
    sLineBreak +
    'ITEMS:' + sLineBreak +
    '  1. Laptop Dell XPS 15 (quantity: 3)        $ 45,000.00' + sLineBreak +
    '  2. Monitor LG 27 inches 4K (quantity: 5) $ 18,750.00' + sLineBreak +
    '  3. Switch Cisco 24 ports (quantity: 1)   $  8,200.00' + sLineBreak +
    '  4. Installation and configuration             $  3,500.00' + sLineBreak +
    sLineBreak +
    'SUBTOTAL:                                    $ 75,450.00' + sLineBreak +
    'VAT (16%):                                   $ 12,072.00' + sLineBreak +
    'TOTAL TO PAY:                               $ 87,522.00' + sLineBreak +
    sLineBreak +
    'Payment method: Bank transfer 30 days' + sLineBreak +
    'Bank: BBVA  CLABE: 012345678901234567' + sLineBreak +
    sLineBreak +
    'Notes: Includes 12-month warranty on equipment.' + sLineBreak +
    'Agreed installation date: March 15, 2025 at 9:00' + sLineBreak +
    'Supplier contact: ventas@distribnorte.com.mx  Phone: 55-1234-5678';

  WriteLn('  Document: Invoice FE-2025-0142 (internal sample)');
  WriteLn('  Content: ', Length(Texto), ' characters');
  WriteLn('');

  // The document text goes in the SystemPrompt
  // The model receives the full content as part of its initial context
  Conn.NewChat;
  Conn.SystemPrompt.Text :=
    'You are an assistant specialized in document analysis.' + sLineBreak +
    'Base your answers ONLY on the following content.' + sLineBreak +
    'If the information is not in the document, say: "Not mentioned in the document".' + sLineBreak +
    'Respond concisely in English.' + sLineBreak +
    sLineBreak +
    '=== DOCUMENT ===' + sLineBreak +
    Texto + sLineBreak +
    '=== END OF DOCUMENT ===';

  // Turn 1: document identification
  Write('  [Turn 1] Identifying document... ');
  R := Conn.AddMessageAndRun(
    'What type of document is this and what are the main data?',
    'user', []);
  WriteLn('OK');
  WriteLn('  Response: ', R);

  // Turn 2: financial figures
  WriteLn('');
  Write('  [Turn 2] Financial data... ');
  R := Conn.AddMessageAndRun(
    'What is the total to pay and how much is the VAT?',
    'user', []);
  WriteLn('OK');
  WriteLn('  Response: ', R);

  // Turn 3: product breakdown
  WriteLn('');
  Write('  [Turn 3] Products purchased... ');
  R := Conn.AddMessageAndRun(
    'List all products with their quantities and unit prices.',
    'user', []);
  WriteLn('OK');
  WriteLn('  Response: ', R);

  WriteLn('');
  WriteLn('→ Strategy B pattern: document text in SystemPrompt.');
  WriteLn('  Without native cap_Pdf — but effective and 100% local with Ollama.');
  WriteLn('  To automate text extraction from a real PDF:');
  WriteLn('    TAiNativePdfTool (AiMaker.ChatTools)  — pure Delphi extractor');
  WriteLn('    PdfiumLib  — Delphi binding to PDFium (open source)');
end;

// =============================================================================
//  MAIN
// =============================================================================
procedure RunDemo;
var
  ConnGemini : TAiChatConnection;
  ConnOllama : TAiChatConnection;
  PdfPath    : string;
  TieneGemini: Boolean;
  TienePDF   : Boolean;
  TieneOllama: Boolean;
begin
  WriteLn('=== MakerAI — Chapter 10: PDF Document Processing ===');
  WriteLn('Strategy A: Native PDF with Gemini (ModelCaps=[cap_Pdf])');
  WriteLn('Strategy B: Embedded text with Ollama (100% local)');

  // Check availability of each resource
  TieneGemini := GeminiApiKeyDisponible;
  PdfPath     := EncontrarPDF;
  TienePDF    := PdfPath <> '';
  TieneOllama := OllamaActivo;

  WriteLn('');
  WriteLn('  Status:');
  if TieneGemini then
    WriteLn('  [OK] GEMINI_API_KEY detected')
  else
    WriteLn('  [--] GEMINI_API_KEY not configured → Demos 1-3 will be skipped');

  if TienePDF then
    WriteLn('  [OK] PDF found: ', ExtractFileName(PdfPath))
  else
    WriteLn('  [--] PDF not found (PDF_PATH=', PDF_PATH, ') → Demos 1-3 will be skipped');

  if TieneOllama then
    WriteLn('  [OK] Ollama active at ', OLLAMA_URL, ' — Demo 4 available')
  else
    WriteLn('  [--] Ollama not detected at ', OLLAMA_URL, ' → Demo 4 will be skipped');

  // ── Demos with Gemini (Strategy A) ─────────────────────────────────────
  if TieneGemini and TienePDF then
  begin
    ConnGemini := CrearConexionGemini;
    try
      Demo1_PdfNativoGemini(PdfPath, ConnGemini);
      Demo2_MultiturnoGemini(PdfPath, ConnGemini);
      Demo3_ExtraccionJSON(PdfPath, ConnGemini);
    finally
      ConnGemini.Free;
    end;
  end
  else if not TieneGemini or not TienePDF then
  begin
    WriteLn('');
    WriteLn('--- Demos 1-3 skipped (Gemini / PDF not available) ---');
    if not TieneGemini then
      WriteLn('  To enable: configure the GEMINI_API_KEY environment variable');
    if not TienePDF then
      WriteLn('  To enable: place a .pdf in ', PDF_PATH);
  end;

  // ── Demo with Ollama (Strategy B) ──────────────────────────────────────
  if TieneOllama then
  begin
    ConnOllama := CrearConexionOllama;
    try
      Demo4_OllamaTextoLocal(ConnOllama);
    finally
      ConnOllama.Free;
    end;
  end
  else
  begin
    WriteLn('');
    WriteLn('--- Demo 4 skipped (Ollama not available) ---');
    WriteLn('  To enable: ollama serve  |  ollama pull gemma3:4b');
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
