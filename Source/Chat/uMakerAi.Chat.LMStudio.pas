unit uMakerAi.Chat.LMStudio;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.StrUtils,
  System.Generics.Collections, System.Net.URLClient, System.Net.HttpClient,
  System.Net.HttpClientComponent, REST.Types, REST.Client,

{$IF CompilerVersion < 35}
  uJSONHelper,
{$ENDIF}

  uMakerAi.ParamsRegistry,
  uMakerAi.Chat,
  uMakerAi.Core;

type
  TAiLMStudioChat = class(TAiChat)
  private
  protected
  public
    constructor Create(Sender: TComponent); override;
    destructor Destroy; override;

    class function GetDriverName: string; override;
    class procedure RegisterDefaultParams(Params: TStrings); override;
    class function CreateInstance(Sender: TComponent): TAiChat; override;
  published
  end;


procedure Register;

implementation

const
  GlLMStudioUrl = 'http://127.0.0.1:1234/v1/';

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiLMStudioChat]);
end;

{ TAiLMStudioChat }

class function TAiLMStudioChat.GetDriverName: string;
begin
  Result := 'LMStudio';
end;

class procedure TAiLMStudioChat.RegisterDefaultParams(Params: TStrings);
begin
  Params.Clear;
  Params.Add('ApiKey=1234'); // LMStudio normally does not require an API key
  Params.Add('Model=lmstudio-local');
  Params.Add('Max_Tokens=4096');
  Params.Add('URL='+GlLMStudioUrl);
end;

class function TAiLMStudioChat.CreateInstance(Sender: TComponent): TAiChat;
begin
  Result := TAiLMStudioChat.Create(Sender);
end;

constructor TAiLMStudioChat.Create(Sender: TComponent);
begin
  inherited;
  ApiKey := '1234'; // local, no authentication required
  Model := 'lmstudio-local';
  Url := GlLMStudioUrl;
end;

destructor TAiLMStudioChat.Destroy;
begin
  inherited;
end;


initialization
  TAiChatFactory.Instance.RegisterDriver(TAiLMStudioChat);

end.
