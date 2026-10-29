// MIT License
// MakerAI - Demo 064: PPM Auto Tools
// The LLM discovers, installs, and executes MCP tools from the PPM registry
// autonomously, without user intervention.

program PPMAutoTools;

uses
  System.StartUpCopy,
  FMX.Forms,
  uMainPPMAutoTools in 'uMainPPMAutoTools.pas' {frmPPMAutoTools};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmPPMAutoTools, frmPPMAutoTools);
  Application.Run;
end.
