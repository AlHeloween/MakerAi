// MIT License
//
// Copyright (c) <year> <copyright holders>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// Name: Gustavo Enriquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.Agents.Tools.Approval;

// Human-in-the-loop suspension tool.
// When a node executes this tool, the graph execution is suspended
// and the TAIAgentManager.OnSuspend event is triggered.
// Execution is resumed by calling TAIAgentManager.ResumeThread.
//
// Usage:
//   LNode.Tool := TAiWaitApprovalTool.Create(LNode);
//   TAiWaitApprovalTool(LNode.Tool).SuspendReason := 'Requires approval';
//   TAiWaitApprovalTool(LNode.Tool).ContextKey    := 'previous_result';

interface

uses
  System.SysUtils, System.StrUtils,
  uMakerAi.Agents, uMakerAi.Agents.Attributes, uMakerAi.Agents.EngineRegistry;

type
  [TToolAttribute('WaitApproval',
                  'Suspends execution until a human operator approves the step',
                  'Control')]
  TAiWaitApprovalTool = class(TAiToolBase)
  private
    FSuspendReason: string;
    FContextKey:    string;
  protected
    procedure Execute(ANode: TAIAgentsNode; const AInput: string;
                      var AOutput: string); override;
  published
    [TToolParameterAttribute('Suspension reason',
                             'Human-readable message explaining why approval is required',
                             'Operator approval is required')]
    property SuspendReason: string read FSuspendReason write FSuspendReason;

    [TToolParameterAttribute('Context key',
                             'Blackboard key whose value is included as context',
                             '')]
    property ContextKey: string read FContextKey write FContextKey;
  end;

implementation

{ TAiWaitApprovalTool }

procedure TAiWaitApprovalTool.Execute(ANode: TAIAgentsNode;
  const AInput: string; var AOutput: string);
var
  LContext: string;
  LReason:  string;
  LKey:     string;
begin
  // Pass-through: when resumed, AInput is the human's response
  AOutput := AInput;

  if not Assigned(ANode) then
    Exit;

  // ResumeThread re-executes this node (DoExecute with aBeforeNode=nil),
  // so the tool runs TWICE: when suspending and when resuming. The mark in
  // the blackboard distinguishes both cases —same pattern as the demo
  // 10-HumanInTheLoop— and travels in the checkpoint, so it survives a
  // process restart.
  LKey := 'approval.' + ANode.Name + '.pending';
  if Assigned(ANode.Graph) and
     (ANode.Graph.Blackboard.GetString(LKey) = '1') then
  begin
    // Resumption: do not suspend again; AOutput already contains the response.
    ANode.Graph.Blackboard.SetString(LKey, '');
    Exit;
  end;

  LContext := '';
  if (FContextKey <> '') and Assigned(ANode.Graph) then
    LContext := ANode.Graph.Blackboard.GetString(FContextKey);

  LReason := IfThen(FSuspendReason <> '',
                    FSuspendReason,
                    'Waiting for human approval');

  if Assigned(ANode.Graph) then
    ANode.Graph.Blackboard.SetString(LKey, '1');
  ANode.Suspend(LReason, LContext);
end;

initialization
  TEngineRegistry.Instance.RegisterTool(
    TAiWaitApprovalTool, 'uMakerAi.Agents.Tools.Approval');

end.
