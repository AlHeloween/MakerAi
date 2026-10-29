program RAGInMemory;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 04-RAGVector / 01-InMemory
// =============================================================================
// RAG (Retrieval-Augmented Generation) with in-memory vector store.
// Creates a document index, searches for the most relevant ones and uses the LLM
// to answer questions with that context.
//
// Concepts covered:
//   - TAiRAGVector as an in-memory vector store
//   - AddItem() to index text documents
//   - BuildIndex() / BuildLexicalIndex() to optimize search
//   - SearchText() to retrieve relevant fragments
//   - Complete pattern: question → retrieve context → generate answer
//
// RAG flow:
//   1. Index documents (once)
//   2. For each question: search top-K relevant fragments
//   3. Build prompt with [context + question]
//   4. LLM generates an answer grounded in the context
// =============================================================================

uses
  System.SysUtils,
  uMakerAi.Embeddings.core,
  uMakerAi.Embeddings.Connection,
  uMakerAi.Embeddings.OpenAi,
  uMakerAi.RAG.Vectors,
  uMakerAi.RAG.Vectors.Index,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Claude,
  uMakerAi.Chat.OpenAi;

const
  // Embeddings provider
  EMB_DRIVER  = 'OpenAI';
  EMB_MODEL   = 'text-embedding-3-small';
  EMB_API_KEY = '@OPENAI_API_KEY';

  // Response generation provider
  LLM_DRIVER  = 'Claude';
  LLM_MODEL   = 'claude-haiku-4-5-20251001';
  LLM_API_KEY = '@CLAUDE_API_KEY';

// =============================================================================
//  Example knowledge base
// =============================================================================
const
  DOCUMENTOS: array[0..8] of String = (
    'MakerAI es una suite Delphi para integrar LLMs en aplicaciones FMX. ' +
    'Soporta Claude, OpenAI, Gemini, Groq, Ollama y otros proveedores.',

    'TAiChatConnection es el componente central de MakerAI. ' +
    'Permite chatear con cualquier LLM cambiando solo DriverName y Model.',

    'Los embeddings son representaciones vectoriales de texto. ' +
    'Textos semanticamente similares tienen vectores parecidos en el espacio vectorial.',

    'RAG (Retrieval-Augmented Generation) combina busqueda vectorial con LLMs. ' +
    'Permite responder preguntas usando informacion que no esta en el modelo.',

    'TAiRAGVector almacena embeddings en memoria RAM. ' +
    'Soporta busqueda hibrida: vectorial (semantica) + lexica (BM25).',

    'Para instalar MakerAI en Delphi debes abrir el grupo de proyectos ' +
    'MakerAI.groupproj y compilar los paquetes en orden: Core, RAG, UI, DSG.',

    'El proveedor Ollama permite usar LLMs locales sin internet. ' +
    'Modelos populares: llama3.2, gemma3, mistral, codellama.',

    'La similitud coseno mide el angulo entre dos vectores. ' +
    'Un valor cercano a 1.0 indica alta similitud semantica.',

    'MCP (Model Context Protocol) es un estandar de Anthropic ' +
    'para conectar LLMs con herramientas externas de forma estandarizada.'
  );

// =============================================================================
//  Ask the RAG and generate an answer with the LLM
// =============================================================================
procedure AskRAG(RAG: TAiRAGVector; Chat: TAiChatConnection; const Question: String);
var
  Contexto: String;
  Prompt  : String;
  Response: String;
begin
  Writeln(StringOfChar('-', 60));
  Writeln('Question: ', Question);
  Writeln;

  // Retrieve relevant fragments
  Contexto := RAG.SearchText(Question, 3, 0.4, nil, False, True);

  if Contexto = '' then
  begin
    Writeln('(No context retrieved)');
    Exit;
  end;

  Writeln('Retrieved context:');
  Writeln(Contexto);

  // Build RAG prompt
  Prompt :=
    'Reference context:' + sLineBreak +
    Contexto + sLineBreak +
    'User question: ' + Question + sLineBreak +
    'Answer based ONLY on the provided context. ' +
    'If the information is not in the context, say so.';

  // Generate response
  Chat.Messages.Clear;
  Response := Chat.AddMessageAndRun(Prompt, 'user', []);
  Writeln('LLM answer:');
  Writeln(Response);
  Writeln;
end;

// =============================================================================
//  DEMO
// =============================================================================
procedure RunDemo;
var
  EmbConn: TAiEmbeddingConnection;
  RAG    : TAiRAGVector;
  Chat   : TAiChatConnection;
  I      : Integer;
begin
  Writeln('=== RAGInMemory ===');
  Writeln('Embeddings: ', EMB_DRIVER, ' / ', EMB_MODEL);
  Writeln('LLM       : ', LLM_DRIVER, ' / ', LLM_MODEL);
  Writeln;

  EmbConn := TAiEmbeddingConnection.Create(nil);
  RAG     := TAiRAGVector.Create(nil);
  Chat    := TAiChatConnection.Create(nil);
  try
    // ── Configure embeddings ─────────────────────────────────────────────
    EmbConn.DriverName := EMB_DRIVER;
    EmbConn.Model      := EMB_MODEL;
    EmbConn.ApiKey     := EMB_API_KEY;

    // ── Configure RAG ────────────────────────────────────────────────────
    RAG.Embeddings          := EmbConn.AiEmbeddings;
    RAG.NameVec             := 'KnowledgeBase';
    RAG.InMemoryIndexType   := TAIHNSWIndex;

    // ── Index documents ────────────────────────────────────────────────
    Writeln('Indexing ', Length(DOCUMENTOS), ' documents...');
    for I := 0 to High(DOCUMENTOS) do
    begin
      RAG.AddItem(DOCUMENTOS[I]);
      Write('.');
    end;
    Writeln;

    RAG.BuildIndex;
    RAG.BuildLexicalIndex;
    Writeln(Format('Index built: %d documents', [RAG.Count]));
    Writeln;

    // ── Configure LLM ────────────────────────────────────────────────────
    Chat.DriverName := LLM_DRIVER;
    Chat.Model      := LLM_MODEL;
    Chat.Params.Values['ApiKey']       := LLM_API_KEY;
    Chat.Params.Values['Asynchronous'] := 'False';
    Chat.Params.Values['Max_Tokens']   := '512';
    Chat.SystemPrompt.Text :=
      'You are a MakerAI technical assistant. ' +
      'Answer in Spanish concisely and precisely.';

    // ── Questions to RAG ──────────────────────────────────────────────────
    AskRAG(RAG, Chat, 'Que es MakerAI y para que sirve?');
    AskRAG(RAG, Chat, 'Como puedo usar un LLM local sin internet?');
    AskRAG(RAG, Chat, 'Que es RAG y como funciona?');

  finally
    Chat.Free;
    RAG.Free;
    EmbConn.Free;
  end;
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      Writeln('ERROR: ', E.ClassName, ' - ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
