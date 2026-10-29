program ChatbotDocumentacion;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Initializations,
  uMakerAi.RAG.Vectors,
  uMakerAi.Embeddings;

const
  INDEX_FILE  = 'kb\index.bin';
  DOCS_FOLDER = 'documentos\';

var
  AiConn  : TAiChatConnection;
  RAG     : TAiRAGVector;
  Emb     : TAiEmbeddings;
  Pregunta: string;

procedure IndexarDocumentos(const Carpeta: string);
var
  Archivos: TArray<string>;
  Archivo : string;
  Count   : Integer;
begin
  Archivos := TDirectory.GetFiles(Carpeta, '*.txt');
  WriteLn('Indexing ', Length(Archivos), ' documents...');
  for Archivo in Archivos do
  begin
    Count := RAG.AddItemsFromPlainText(
      TFile.ReadAllText(Archivo),
      nil,   // metadata
      500,   // chunk size (caracteres)
      10     // overlap %
    );
    WriteLn('  + ', ExtractFileName(Archivo), ' -> ', Count, ' chunks');
  end;
  RAG.BuildIndex;
  RAG.SaveToFile(INDEX_FILE);
  WriteLn('Indexing complete: ', RAG.Count, ' total fragments.');
end;

function ObtenerContexto(const Pregunta: string): string;
begin
  // SearchText returns the most similar fragments as a formatted string
  Result := RAG.SearchText(Pregunta, 4, 0.6, nil, False, False);
end;

procedure CrearDocumentosEjemplo;
begin
  ForceDirectories(DOCS_FOLDER);
  TFile.WriteAllText(DOCS_FOLDER + 'politicas.txt',
    'RETURNS POLICY' + sLineBreak +
    'Customers can return products within 30 days of purchase.' + sLineBreak +
    'The original purchase receipt is required.' + sLineBreak +
    'Electronic products have a 15-day warranty.' + sLineBreak +
    sLineBreak +
    'SHIPPING POLICY' + sLineBreak +
    'Free shipping on purchases over $50.' + sLineBreak +
    'Estimated delivery time: 3 to 5 business days.' + sLineBreak +
    'Returns have shipping cost charged to the customer.'
  );
  TFile.WriteAllText(DOCS_FOLDER + 'productos.txt',
    'PRODUCT CATALOG 2025' + sLineBreak +
    'Laptop Pro X: $1200 — i9 processor, 32GB RAM, 1TB SSD.' + sLineBreak +
    'Basic Laptop: $450 — i5 processor, 16GB RAM, 512GB SSD.' + sLineBreak +
    '27" 4K Monitor: $350 — IPS panel, 144Hz, HDR.' + sLineBreak +
    'Mechanical Keyboard: $80 — Cherry MX Blue switches.' + sLineBreak +
    sLineBreak +
    'All products include a 1-year warranty.'
  );
  WriteLn('Sample documents created in: ', DOCS_FOLDER);
end;

begin
  WriteLn('=================================================');
  WriteLn('  Ch. 22 - Vector RAG: Chatbot Demo');
  WriteLn('=================================================');
  WriteLn;

  Emb    := TAiEmbeddings.Create(nil);
  RAG    := TAiRAGVector.Create(nil);
  AiConn := TAiChatConnection.Create(nil);
  try
    // Configure embedder
    Emb.ApiKey     := '@OPENAI_API_KEY';
    RAG.Embeddings := Emb;

    // Create or load index
    if TFile.Exists(INDEX_FILE) then
    begin
      RAG.LoadFromFile(INDEX_FILE);
      WriteLn('Index loaded: ', RAG.Count, ' fragments.');
    end
    else
    begin
      // Create sample documents if they do not exist
      if not TDirectory.Exists(DOCS_FOLDER) then
        CrearDocumentosEjemplo;

      ForceDirectories('kb');
      IndexarDocumentos(DOCS_FOLDER);
    end;

    // Configure LLM (Groq llama-3.3-70b — fast and free tier)
    AiConn.DriverName                    := 'Groq';
    AiConn.Params.Values['ApiKey']       := '@GROQ_API_KEY';
    AiConn.Model                          := 'llama-3.3-70b-versatile';
    AiConn.Params.Values['Asynchronous'] := 'False';

    WriteLn;
    WriteLn('RAG chatbot ready. Example questions:');
    WriteLn('  "What is the deadline to return a product?"');
    WriteLn('  "How much does the Laptop Pro X cost?"');
    WriteLn('  "Is shipping free?"');
    WriteLn('Type "exit" to quit.');
    WriteLn;

    repeat
      Write('You > ');
      ReadLn(Pregunta);
      if SameText(Trim(Pregunta), 'exit') then Break;
      if Trim(Pregunta) = '' then Continue;

      // 1. Retrieve relevant fragments from the index
      var Contexto := ObtenerContexto(Pregunta);

      if Contexto = '' then
      begin
        WriteLn('AI  > No relevant information found in the knowledge base.');
        WriteLn;
        Continue;
      end;

      // 2. Configure system prompt with the retrieved context
      AiConn.NewChat;
      AiConn.SystemPrompt.Text :=
        'You are an assistant that answers questions based ONLY on the ' +
        'company documentation provided. ' +
        'If the answer is not in the context, say: "I have no information about that."' +
        sLineBreak + sLineBreak +
        'DOCUMENTATION:' + sLineBreak + Contexto;

      // 3. Get response from the LLM
      var Respuesta := AiConn.AddMessageAndRun(Pregunta, 'user', []);
      WriteLn('AI  > ', Respuesta);
      WriteLn;

    until False;

  finally
    AiConn.Free;
    RAG.Free;
    Emb.Free;
  end;
end.
