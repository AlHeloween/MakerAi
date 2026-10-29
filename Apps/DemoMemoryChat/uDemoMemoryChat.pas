unit uDemoMemoryChat;

interface

procedure RunDemo;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, System.Math,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Messages,
  uMakerAi.Memory,
  uMakerAi.Memory.Types;

// ---------------------------------------------------------------------------
// Helpers de consola
// ---------------------------------------------------------------------------

procedure PrintLine(const S: string = '');
begin
  Writeln(S);
end;

procedure PrintColor(const S: string; AColor: Byte);
begin
  // ANSI colors: 32=green, 33=yellow, 34=blue, 36=cyan, 90=gray
  Write(#27'[', AColor, 'm', S, #27'[0m');
end;

procedure PrintSep;
begin
  PrintLine('─────────────────────────────────────────────────────────────');
end;

// ---------------------------------------------------------------------------

function ReadApiKey(const AProvider: string): string;
var
  EnvVar: string;
begin
  // Try environment variable first
  EnvVar := UpperCase(AProvider) + '_API_KEY';
  // Some providers have compound names
  if AProvider = 'OpenAI'  then EnvVar := 'OPENAI_API_KEY';
  if AProvider = 'Claude'  then EnvVar := 'CLAUDE_API_KEY';
  if AProvider = 'Gemini'  then EnvVar := 'GEMINI_API_KEY';
  if AProvider = 'Groq'    then EnvVar := 'GROQ_API_KEY';

  Result := GetEnvironmentVariable(EnvVar);
  if Result <> '' then
  begin
    PrintColor('  API key read from $' + EnvVar, 32);
    PrintLine;
    Exit;
  end;

  Write('  API key for ', AProvider, ' (or press Enter to skip): ');
  Readln(Result);
end;

// ---------------------------------------------------------------------------

procedure ShowStats(AMemory: TAiMemory);
var
  S: TMemoryStats;
begin
  S := AMemory.Stats;
  PrintColor(Format('  Memories: %d  |  Average importance: %.1f  |  Average decay: %.2f',
    [S.TotalCount, S.AvgImportance, S.AvgDecay]), 36);
  PrintLine;
end;

procedure ShowMemories(AMemory: TAiMemory; const AQuery: string);
var
  Results: TMemorySearchResults;
  I: Integer;
begin
  if AQuery <> '' then
  begin
    Results := AMemory.Search(AQuery, 10, ms_Hybrid);
    PrintColor(Format('  Results for "%s":', [AQuery]), 33);
    PrintLine;
  end
  else
  begin
    Results := AMemory.Search('', 10, ms_FTS);
    PrintColor('  Latest memories:', 33);
    PrintLine;
  end;

  if Length(Results) = 0 then
  begin
    PrintLine('  (no results)');
    Exit;
  end;

  for I := 0 to High(Results) do
  begin
    var E := Results[I].Entry;
    PrintColor(Format('  [%d] imp:%d decay:%.2f score:%.3f',
      [E.Id, E.Importance, E.DecayScore, Results[I].Score]), 90);
    PrintLine;
    PrintLine('       ' + E.Content);
    E.Free;
  end;
end;

// ---------------------------------------------------------------------------

procedure RunDemo;
var
  Conn            : TAiChatConnection;
  AnalyzerConn    : TAiChatConnection;
  Memory          : TAiMemory;
  Provider, Model : string;
  DbPath          : string;
  Input           : string;
  NextImportance  : Integer;
  DebugMode       : Boolean;
  // streaming state
  StreamBuffer    : string;
  StreamDone      : Boolean;
begin
  PrintLine;
  PrintSep;
  PrintColor('  MakerAI — DemoMemoryChat', 36);
  PrintLine;
  PrintColor('  Chat with persistent memory across sessions', 90);
  PrintLine;
  PrintSep;
  PrintLine;

  // ── Configuration ─────────────────────────────────────────────────────────
  Provider := 'Claude';
  Model    := 'claude-haiku-4-5-20251001';
  DbPath   := TPath.Combine(TPath.GetHomePath, 'makerAI_memory_demo.db');

  PrintLine('Configuration (Enter = use default value):');
  Write(Format('  Provider [%s]: ', [Provider]));
  var Tmp: string;
  Readln(Tmp);
  if Tmp <> '' then Provider := Tmp;

  Write(Format('  Model [%s]: ', [Model]));
  Readln(Tmp);
  if Tmp <> '' then Model := Tmp;

  Write(Format('  DB path [%s]: ', [DbPath]));
  Readln(Tmp);
  if Tmp <> '' then DbPath := Tmp;

  PrintLine;
  var ApiKey := ReadApiKey(Provider);
  PrintLine;

  // ── Initialize memory ────────────────────────────────────────────────────
  Memory       := TAiMemory.Create(nil);
  Conn         := TAiChatConnection.Create(nil);
  AnalyzerConn := TAiChatConnection.Create(nil);
  try
    Memory.DbPath  := DbPath;
    Memory.Namespace := 'demo';

    Conn.DriverName := Provider;
    Conn.Model      := Model;
    Conn.Params.Values['ApiKey']       := ApiKey;
    Conn.Params.Values['Asynchronous'] := 'False';
    Conn.Params.Values['Max_Tokens']   := '1024';
    Conn.SystemPrompt.Text :=
      'Eres un asistente útil con memoria persistente. ' +
      'Cuando el contexto de memoria esté disponible, úsalo para personalizar tus respuestas. ' +
      'Responde en el mismo idioma del usuario.';

    Conn.PersistentMemory  := Memory;
    Conn.MemoryTokenBudget := 1500;
    Conn.AutoStoreMemories := True;

    // ── Analyzer LLM (cheap/fast) for automatic memory extraction ──
    AnalyzerConn.DriverName := 'Groq';
    AnalyzerConn.Model      := 'llama-3.1-8b-instant';
    AnalyzerConn.Params.Values['ApiKey']       := ReadApiKey('Groq');
    AnalyzerConn.Params.Values['Asynchronous'] := 'False';
    Memory.Analyzer         := AnalyzerConn;
    Memory.AnalysisInterval := 3; // cada 3 intercambios, para probar rápido

    NextImportance := 5;
    DebugMode      := False;

    PrintSep;
    PrintColor(Format('  Provider : %s / %s', [Provider, Model]), 32);
    PrintLine;
    PrintColor(Format('  Memory  : %s', [DbPath]), 32);
    PrintLine;
    PrintColor('  AutoStore: ON  |  TokenBudget: 1500', 32);
    PrintLine;
    PrintColor('  Analyzer : Groq / llama-3.1-8b-instant  |  AnalysisInterval: 3', 32);
    PrintLine;
    PrintSep;
    PrintLine;

    ShowStats(Memory);
    PrintLine;
    PrintLine('Commands: /quit /new /stats /memories [query] /store <text>');
    PrintLine('          /importance N  /debug  /analyze');
    PrintLine;

    // ── REPL ──────────────────────────────────────────────────────────────
    while True do
    begin
      PrintColor('> ', 32);
      Readln(Input);
      Input := Trim(Input);
      if Input = '' then Continue;

      // ── Commands ────────────────────────────────────────────────────────
      if Input = '/quit' then Break;

      if Input = '/new' then
      begin
        Conn.NewChat;
        PrintColor('  New session started (memory preserved)', 33);
        PrintLine;
        Continue;
      end;

      if Input = '/stats' then
      begin
        ShowStats(Memory);
        Continue;
      end;

      if Input = '/debug' then
      begin
        DebugMode := not DebugMode;
        PrintColor(Format('  Debug mode: %s', [BoolToStr(DebugMode, True)]), 33);
        PrintLine;
        Continue;
      end;

      if Input = '/analyze' then
      begin
        var N := Memory.AnalyzeNow;
        PrintColor(Format('  Analyzer → %d memory/memories extracted from the accumulated buffer', [N]), 33);
        PrintLine;
        Continue;
      end;

      if Input.StartsWith('/memories') then
      begin
        var Q := Trim(Input.Substring(9));
        ShowMemories(Memory, Q);
        Continue;
      end;

      if Input.StartsWith('/store ') then
      begin
        var Content := Trim(Input.Substring(7));
        if Content <> '' then
        begin
          var Id := Memory.Store(Content, mt_Fact, NextImportance);
          PrintColor(Format('  Guardado → id=%d  imp=%d', [Id, NextImportance]), 33);
          PrintLine;
        end;
        Continue;
      end;

      if Input.StartsWith('/importance ') then
      begin
        var N := StrToIntDef(Trim(Input.Substring(12)), 5);
        NextImportance := Max(1, Min(10, N));
        PrintColor(Format('  Importancia para /store: %d', [NextImportance]), 33);
        PrintLine;
        Continue;
      end;

      // ── Debug: show context to inject ──────────────────────────────
      if DebugMode then
      begin
        var Ctx := Memory.Context(Input, 1500);
        if Ctx.MemoryCount > 0 then
        begin
          PrintColor(Format('  [memory] %d entry/entries to inject:', [Ctx.MemoryCount]), 90);
          PrintLine;
          for var Line in Ctx.FormattedText.Split([#10]) do
            if Line.Trim <> '' then
            begin
              PrintColor('    ' + Line.Trim, 90);
              PrintLine;
            end;
          PrintLine;
        end
        else
        begin
          PrintColor('  [memory] no relevant context', 90);
          PrintLine;
        end;
      end;

      // ── LLM call (synchronous) ─────────────────────────────────────
      try
        var LMsg := Conn.AddMessage(Input, 'user');
        PrintLine;
        PrintColor('AI: ', 34);
        var Response := Conn.Run(LMsg);
        if Response = '' then
          Response := '(no response)';
        // La respuesta ya se imprimió en streaming si hay OnReceiveData,
        // pero como es síncrona sin handler imprimimos el resultado final
        Writeln(Response);
        PrintLine;
      except
        on E: Exception do
        begin
          PrintColor('  Error: ' + E.Message, 31);
          PrintLine;
        end;
      end;
    end;

  finally
    Conn.PersistentMemory := nil;
    Memory.Analyzer       := nil;
    Conn.Free;
    AnalyzerConn.Free;
    Memory.Free;
  end;

  PrintLine;
  PrintColor('  Session ended. Memory saved to: ' + DbPath, 32);
  PrintLine;
  PrintLine;
end;

end.
