program ComputerUseServer;

// Computer Use against the cimamaker server (manual loop, OpenAI format).
// The form is built 100% in code (no .fmx) -> CreateNew + manual MainForm.

uses
  System.StartUpCopy,
  FMX.Forms,
  uMainCUServer in 'uMainCUServer.pas';

{$R *.res}

begin
  Application.Initialize;
  FormCUServer := TFormCUServer.CreateNew(Application);
  Application.MainForm := FormCUServer;
  FormCUServer.Show;
  Application.Run;
end.
