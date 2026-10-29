program AllCapabilities;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 02-ChatTools / 06-AllCapabilities
// =============================================================================
// Shows how to configure TAiChatConnection with multiple capabilities and how
// the Gap system (SessionCaps - ModelCaps) automatically activates the
// corresponding ChatTools bridges.
//
// Capabilities demonstrated:
//   cap_Image      — image analysis (Vision)
//   cap_WebSearch  — web search
//   cap_Pdf        — text extraction from PDFs
//   cap_GenImage   — image generation
//   cap_GenAudio   — voice synthesis (TTS)
//
// To run the modes that require external API keys, configure the
// corresponding environment variables (OPENAI_API_KEY, GEMINI_API_KEY, etc.)
// =============================================================================

uses
  System.SysUtils,
  System.Classes,
  uMakerAi.Core,
  uMakerAi.Chat,
  uMakerAi.Chat.AiConnection,
  uMakerAi.Chat.Initializations;

procedure PrintCapabilities(const ATitle: string; ACaps: TAiCapabilities);
const
  CapNames: array[TAiCapability] of string = (
    'Image', 'Audio', 'Video', 'Pdf', 'WebSearch',
    'Reasoning', 'CodeInterpreter', 'Memory', 'TextEditor',
    'ComputerUse', 'Shell',
    'GenImage', 'GenAudio', 'GenVideo', 'GenReport', 'ExtractCode'
  );
var
  Cap: TAiCapability;
  Parts: TArray<string>;
  i: Integer;
begin
  SetLength(Parts, 0);
  for Cap := Low(TAiCapability) to High(TAiCapability) do
    if Cap in ACaps then
    begin
      SetLength(Parts, Length(Parts) + 1);
      Parts[High(Parts)] := CapNames[Cap];
    end;
  if Length(Parts) = 0 then
    Writeln('  ', ATitle, ': []')
  else
    Writeln('  ', ATitle, ': [', string.Join(', ', Parts), ']');
end;

procedure DemoCapabilityConfig(const ADriver, AModel: string;
  AModelCaps, ASessionCaps: TAiCapabilities);
var
  Conn: TAiChatConnection;
  Gap: TAiCapabilities;
begin
  Writeln;
  Writeln('Driver: ', ADriver, ' | Model: ', AModel);
  Writeln(StringOfChar('-', 60));

  Conn := TAiChatConnection.Create(nil);
  try
    Conn.DriverName := ADriver;
    Conn.Model      := AModel;
    Conn.Params.Values['ApiKey'] := '@' + UpperCase(ADriver) + '_API_KEY';

    Conn.ModelConfig.ModelCaps   := AModelCaps;
    Conn.ModelConfig.SessionCaps := ASessionCaps;

    PrintCapabilities('ModelCaps  ', AModelCaps);
    PrintCapabilities('SessionCaps', ASessionCaps);

    Gap := ASessionCaps - AModelCaps;
    PrintCapabilities('Gap (bridges)', Gap);

    if Gap = [] then
      Writeln('  -> No bridges needed (all native)')
    else
      Writeln('  -> Bridges automatically activated by the engine');
  finally
    Conn.Free;
  end;
end;

begin
  Writeln('=============================================================');
  Writeln('  MakerAI - AllCapabilities: configuration patterns');
  Writeln('=============================================================');

  // Gemini with native vision and search, TTS via bridge
  DemoCapabilityConfig(
    'Gemini', 'gemini-2.0-flash',
    [cap_Image, cap_WebSearch],
    [cap_Image, cap_WebSearch, cap_GenAudio]
  );

  // Local Ollama — no native capabilities, everything via bridges
  DemoCapabilityConfig(
    'Ollama', 'gemma3:4b',
    [],
    [cap_Image, cap_WebSearch, cap_GenImage]
  );

  // OpenAI with native vision, image generation via DALL-E bridge
  DemoCapabilityConfig(
    'OpenAI', 'gpt-4.1',
    [cap_Image, cap_WebSearch],
    [cap_Image, cap_WebSearch, cap_GenImage]
  );

  // Claude with native vision and reasoning
  DemoCapabilityConfig(
    'Claude', 'claude-opus-4-7',
    [cap_Image, cap_Reasoning],
    [cap_Image, cap_Reasoning, cap_WebSearch]
  );

  Writeln;
  Writeln('=============================================================');
  Writeln('See the individual demos (03-Vision, 05-WebSearch,');
  Writeln('07-AudioBridge, 09-ImageGeneration) for complete examples.');
  Writeln('=============================================================');

  Write('Press Enter to exit...');
  Readln;
end.
