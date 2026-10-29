program ComputerUseTest;

uses
  System.StartUpCopy,
  FMX.Types,
  FMX.Forms,
  uMainComputerUseTest in 'uMainComputerUseTest.pas' {FormComputerUse};

{$R *.res}

begin
  {$IFDEF MSWINDOWS}
  // Software rendering (WARP). Needed on Remote Desktop (RDP), virtual
  // machines or GPUs whose Direct2D does not compose the window (the thumbnail shows in
  // the taskbar but not the window). No visible effect on normal hardware.
  GlobalUseDXSoftware := True;
  {$ENDIF}
  Application.Initialize;
  Application.CreateForm(TFormComputerUse, FormComputerUse);
  Application.Run;
end.
