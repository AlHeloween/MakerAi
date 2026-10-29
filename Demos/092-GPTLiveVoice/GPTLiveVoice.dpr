program GPTLiveVoice;

// MakerAI — Demo 092: OpenAI GPT-Live (full-duplex voice with delegation).
// See uMainGPTLive.pas and CLAUDE.md.

uses
  System.StartUpCopy,
  FMX.Forms,
  uMainGPTLive in 'uMainGPTLive.pas' {FormGPTLive};

{$R *.res}

begin
  ReportMemoryLeaksOnShutdown := True;
  Application.Initialize;
  Application.CreateForm(TFormGPTLive, FormGPTLive);
  Application.Run;
end.
