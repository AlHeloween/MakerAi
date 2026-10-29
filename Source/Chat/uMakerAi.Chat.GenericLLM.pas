unit uMakerAi.Chat.GenericLLM;

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
  uMakerAi.Core,
  uMakerAi.Embeddings;

type
  TAiGenericChat = class(TAiChat)
  private
    FCustomDriverName: string;
    procedure SetCustomDriverName(const Value: string);
  protected
  public
    constructor Create(Sender: TComponent); override;
    destructor Destroy; override;

    class function GetDriverName: string; override;
    class procedure RegisterDefaultParams(Params: TStrings); override;
    class function CreateInstance(Sender: TComponent): TAiChat; override;
  published
    // Custom name with which this component registers in the factory.
    // Allows using multiple instances of TAiGenericChat pointing to different APIs.
    property CustomDriverName: string read FCustomDriverName write SetCustomDriverName;
  end;



procedure Register;

implementation

const
  GlGenericUrl = 'http://127.0.0.1:1234/v1/';

procedure Register;
begin
  RegisterComponents('MakerAI', [TAiGenericChat]);
end;

{ TAiGenericChat }

procedure TAiGenericChat.SetCustomDriverName(const Value: string);
begin
  if FCustomDriverName = Value then Exit;
  FCustomDriverName := Value;
  // Register the class in the factory under the custom name.
  // 'GenericLLM' always remains registered (via initialization).
  if Value <> '' then
    TAiChatFactory.Instance.RegisterDriver(TAiGenericChat, Value);
end;

class function TAiGenericChat.GetDriverName: string;
begin
  Result := 'GenericLLM';
end;

class procedure TAiGenericChat.RegisterDefaultParams(Params: TStrings);
begin
  Params.Clear;
  Params.Add('ApiKey=1234'); // LMStudio normally does not require API key
  Params.Add('Model=generic-local');
  Params.Add('Max_Tokens=4096');
  Params.Add('URL='+GlGenericUrl);
end;

class function TAiGenericChat.CreateInstance(Sender: TComponent): TAiChat;
begin
  Result := TAiGenericChat.Create(Sender);
end;

constructor TAiGenericChat.Create(Sender: TComponent);
begin
  inherited;
  ApiKey := '1234'; // local, no authentication required
  Model := 'generic-local';
  Url := GlGenericUrl;
end;

destructor TAiGenericChat.Destroy;
begin
  inherited;
end;



initialization
  TAiChatFactory.Instance.RegisterDriver(TAiGenericChat);

end.
