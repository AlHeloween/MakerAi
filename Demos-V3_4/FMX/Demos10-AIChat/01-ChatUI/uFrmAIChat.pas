unit uFrmAIChat;

// =============================================================================
// MakerAI — Demo FMX Chat UI
// Shows TAIChatView + TAIChatInput on an FMX form.
//
// Components declared in uFrmAIChat.fmx (form designer):
//   TAIChatView  — Skia rendering of bubbles with Markdown
//   TAIChatInput — input bar with attachments, screenshot capture, and microphone
//
// Simulated streaming flow:
//   BtnStream → BeginAssistantMessage → TTimer (30 ms) → AppendToken → FinishMessage
// =============================================================================

{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.StdCtrls, FMX.Layouts,
  AIChat.Types,
  AIChat.Control.FMX,
  AIChat.Input;

type
  TFrmAIChat = class(TForm)
    ToolBar1  : TToolBar;
    BtnLight  : TButton;
    BtnDark   : TButton;
    BtnClear  : TButton;
    BtnLoad   : TButton;
    BtnStream : TButton;
    ChatView  : TAIChatView;
    ChatInput : TAIChatInput;
    procedure FormCreate(Sender: TObject);
    procedure BtnLight_Click (Sender: TObject);
    procedure BtnDark_Click  (Sender: TObject);
    procedure BtnClear_Click (Sender: TObject);
    procedure BtnLoad_Click  (Sender: TObject);
    procedure BtnStream_Click(Sender: TObject);
    procedure ChatView_LinkClick (Sender: TObject; AMsg: TAIChatMessage;
                                   const AURL: string);
    procedure ChatView_AttachOpen(Sender: TObject; AMsg: TAIChatMessage;
                                   AAttach: TAIChatAttachment);
    procedure ChatInput_Send     (Sender: TObject; const APrompt: string;
                                   AAttachments: TAIChatAttachments;
                                   AAudio: TMemoryStream);
    procedure ChatInput_Cancel   (Sender: TObject);
    procedure ChatInput_MicToggle(Sender: TObject; AActivate: Boolean);
  private
    FStreamTimer    : TTimer;
    FStreamMsgIndex : Integer;
    FStreamText     : string;
    FStreamPos      : Integer;
    procedure StreamTimerFired(Sender: TObject);
    procedure LoadSampleConversation;
  end;

var
  FrmAIChat: TFrmAIChat;

implementation

{$R *.fmx}

const
  STREAM_SAMPLE =
    '## AI-generated response' + #10 +
    '' + #10 +
    'This is an example of an assistant **streaming response**.' + #10 +
    '' + #10 +
    'Features include:' + #10 +
    '' + #10 +
    '- Complete **Markdown** rendering' + #10 +
    '- Role-differentiated bubbles' + #10 +
    '- Virtualized scrolling for long conversations' + #10 +
    '- Cross-platform support (Windows, macOS, Android, iOS)' + #10 +
    '' + #10 +
    '```pascal' + #10 +
    'var Msg := ChatView.BeginAssistantMessage;' + #10 +
    'ChatView.AppendToken(Msg.Index, ''token'');' + #10 +
    'ChatView.FinishMessage(Msg.Index);' + #10 +
    '```' + #10 +
    '' + #10 +
    '> **Note**: the component renders Markdown with Skia without child controls.' + #10;

{ TFrmAIChat }

procedure TFrmAIChat.FormCreate(Sender: TObject);
begin
  FStreamMsgIndex := -1;

  FStreamTimer          := TTimer.Create(Self);
  FStreamTimer.Interval := 30;
  FStreamTimer.Enabled  := False;
  FStreamTimer.OnTimer  := StreamTimerFired;

  LoadSampleConversation;
end;

{ ── Toolbar ──────────────────────────────────────────────────────────────── }

procedure TFrmAIChat.BtnLight_Click(Sender: TObject);
begin
  ChatView.ThemeDark := False;
end;

procedure TFrmAIChat.BtnDark_Click(Sender: TObject);
begin
  ChatView.ThemeDark := True;
end;

procedure TFrmAIChat.BtnClear_Click(Sender: TObject);
begin
  FStreamTimer.Enabled := False;
  FStreamMsgIndex      := -1;
  BtnStream.Text       := 'Stream AI';
  ChatView.ClearMessages;
end;

procedure TFrmAIChat.BtnLoad_Click(Sender: TObject);
begin
  FStreamTimer.Enabled := False;
  FStreamMsgIndex      := -1;
  BtnStream.Text       := 'Stream AI';
  ChatView.ClearMessages;
  LoadSampleConversation;
end;

{ ── Streaming simulation ─────────────────────────────────────────────────── }

procedure TFrmAIChat.BtnStream_Click(Sender: TObject);
begin
  if FStreamTimer.Enabled then
  begin
    FStreamTimer.Enabled := False;
    if FStreamMsgIndex >= 0 then
      ChatView.FinishMessage(FStreamMsgIndex);
    FStreamMsgIndex  := -1;
    BtnStream.Text   := 'Stream AI';
    Exit;
  end;

  FStreamText := STREAM_SAMPLE;
  FStreamPos  := 1;
  ChatView.BeginAssistantMessage;
  FStreamMsgIndex := ChatView.MessageCount - 1;

  FStreamTimer.Enabled := True;
  BtnStream.Text       := 'Stop';
end;

procedure TFrmAIChat.StreamTimerFired(Sender: TObject);
const
  CHUNK = 3;
var
  Remaining : Integer;
  Piece     : string;
begin
  if FStreamMsgIndex < 0 then
  begin
    FStreamTimer.Enabled := False;
    BtnStream.Text       := 'Stream AI';
    Exit;
  end;

  Remaining := Length(FStreamText) - FStreamPos + 1;
  if Remaining <= 0 then
  begin
    FStreamTimer.Enabled := False;
    ChatView.FinishMessage(FStreamMsgIndex);
    FStreamMsgIndex := -1;
    BtnStream.Text  := 'Stream AI';
    Exit;
  end;

  Piece := Copy(FStreamText, FStreamPos, Min(CHUNK, Remaining));
  ChatView.AppendToken(FStreamMsgIndex, Piece);
  Inc(FStreamPos, CHUNK);
end;

{ ── TAIChatInput handlers ─────────────────────────────────────────────────── }

procedure TFrmAIChat.ChatInput_Send(Sender: TObject; const APrompt: string;
  AAttachments: TAIChatAttachments; AAudio: TMemoryStream);
begin
  if APrompt <> '' then
    ChatView.AddUserMessage(APrompt)
  else if AAudio <> nil then
    ChatView.AddUserMessage('[Voice message]');
  ChatInput.Busy := False;
  ChatView.ScrollToBottom;
end;

procedure TFrmAIChat.ChatInput_Cancel(Sender: TObject);
begin
  FStreamTimer.Enabled := False;
  if FStreamMsgIndex >= 0 then
    ChatView.FinishMessage(FStreamMsgIndex);
  FStreamMsgIndex  := -1;
  BtnStream.Text   := 'Stream AI';
  ChatInput.Busy   := False;
end;

procedure TFrmAIChat.ChatInput_MicToggle(Sender: TObject; AActivate: Boolean);
begin
  if AActivate then
    ChatInput.NotifyVoiceCalibrated
  else
    ChatInput.NotifyVoiceError;
end;

{ ── TAIChatView events ────────────────────────────────────────────────────── }

procedure TFrmAIChat.ChatView_LinkClick(Sender: TObject; AMsg: TAIChatMessage;
  const AURL: string);
begin
  ShowMessage('Link: ' + AURL);
end;

procedure TFrmAIChat.ChatView_AttachOpen(Sender: TObject; AMsg: TAIChatMessage;
  AAttach: TAIChatAttachment);
begin
  ShowMessage('Attachment: ' + AAttach.FileName);
end;

{ ── Sample conversation ──────────────────────────────────────────────────── }

procedure TFrmAIChat.LoadSampleConversation;
begin
  ChatView.AddUserMessage('Hello, what is TAIChatView?');

  ChatView.AddMessage(TChatRole.crAssistant,
    '**TAIChatView** is an FMX component that renders AI chat conversations ' +
    'using Skia as the painting engine.' + #10 +
    '' + #10 +
    'Main features:' + #10 +
    '- Differentiated user and assistant bubbles' + #10 +
    '- Full Markdown in assistant responses' + #10 +
    '- Real-time token streaming' + #10 +
    '- Virtualization for long conversations' + #10 +
    '- Cross-platform: Windows, Android, macOS, iOS');

  ChatView.AddUserMessage('How do I use it in streaming?');

  ChatView.AddMessage(TChatRole.crAssistant,
    'The flow is simple:' + #10 +
    '' + #10 +
    '```pascal' + #10 +
    '// 1. Iniciar mensaje de asistente' + #10 +
    'ChatView.BeginAssistantMessage;' + #10 +
    'var MsgIdx := ChatView.MessageCount - 1;' + #10 +
    '' + #10 +
    '// 2. Enviar tokens conforme llegan de la API' + #10 +
    'ChatView.AppendToken(MsgIdx, token);' + #10 +
    '' + #10 +
    '// 3. Finalizar' + #10 +
    'ChatView.FinishMessage(MsgIdx);' + #10 +
    '```' + #10 +
    '' + #10 +
    'Press **Stream AI** to see it in action.');

  ChatView.ScrollToBottom;
end;

end.
