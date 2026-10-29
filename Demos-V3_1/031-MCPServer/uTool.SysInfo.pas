// MIT License
//
// Copyright (c) 2013 Gustavo Enríquez - CimaMaker
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// o use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// HE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// Name: Gustavo Enríquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/


unit uTool.SysInfo;

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils,
  System.Classes,
  System.JSON; // <-- Añadir System.JSON

type
  TSysInfoParams = class
  private
    FInfoType: string;
    FIncludeDetails: Boolean;
    FFormatAsJson: Boolean; // <-- Nuevo parámetro
  public
    [AiMCPSchemaDescription('Type of information: "basic", "memory", "disk", "network" or "all"')]
    property InfoType: string read FInfoType write FInfoType;

    [AiMCPOptional]
    [AiMCPSchemaDescription('Include additional details (default: false)')]
    property IncludeDetails: Boolean read FIncludeDetails write FIncludeDetails;

    [AiMCPOptional]
    // <-- New parameter to control output format
    [AiMCPSchemaDescription
      ('Devolver la información como un objeto JSON estructurado (default: true). Si es false, devuelve texto formateado.')]
    property FormatAsJson: Boolean read FFormatAsJson write FFormatAsJson;
  end;

  TSysInfoTool = class(TAiMCPToolBase<TSysInfoParams>)
  private
    // Functions that return JSON
    function GetBasicInfoAsJson: TJSONObject;
    function GetMemoryInfoAsJson: TJSONObject;
    function GetDiskInfoAsJson: TJSONArray;
    function GetNetworkInfoAsJson: TJSONObject;
    function GetAllInfoAsJson(IncludeDetails: Boolean): TJSONObject;

    // Old functions that return text (for backward compatibility)
    function GetBasicInfoAsText: string;
    function GetMemoryInfoAsText: string;
    function GetDiskInfoAsText: string;
    function GetNetworkInfoAsText: string;
    function GetAllInfoAsText(IncludeDetails: Boolean): string;

  protected
    // CHANGE: The signature now returns TJSONObject
    function ExecuteWithParams(const AParams: TSysInfoParams; const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; Override;
  end;

procedure RegisterTools(ALogicServer: TAiMCPServer);

implementation

uses
  Winapi.Windows;

{ TSysInfoTool }

procedure RegisterTools(ALogicServer: TAiMCPServer);
begin
  if not Assigned(ALogicServer) then
    raise Exception.Create('LogicServer cannot be null to register tools.');

  ALogicServer.RegisterTool('system_info',
    function: IAiMCPTool
    begin
      Result := TSysInfoTool.Create;
    end);
end;

constructor TSysInfoTool.Create;
begin
  inherited Create;
  FName := 'system_info';
  FDescription :=
    'Obtiene información del sistema (CPU, memoria, disco, etc.) donde se está ejecutando el servidor. Puede devolver la información como texto formateado o como un objeto JSON estructurado.';
  // By default, FormatAsJson will be True
  TSysInfoParams.Create.FFormatAsJson := True;
end;

// CHANGE: The main function now returns TJSONObject and decides the format
function TSysInfoTool.ExecuteWithParams(const AParams: TSysInfoParams; const AuthContext: TAiAuthContext): TJSONObject;
var
  LInfoType: string;
  ResultText: string;
  ResultJson: TJSONObject;
begin
  LInfoType := Trim(LowerCase(AParams.InfoType));
  ResultText := '';
  try
    // Decidir si se devuelve JSON o texto
    if AParams.FormatAsJson then
    begin
      // --- Logic to return JSON ---
      if (LInfoType = 'basic') then
        ResultJson := GetBasicInfoAsJson
      else if (LInfoType = 'memory') then
        ResultJson := GetMemoryInfoAsJson
      else if (LInfoType = 'disk') then
      begin
        ResultJson := TJSONObject.Create;
        ResultJson.AddPair('disks', GetDiskInfoAsJson);
      end
      else if (LInfoType = 'network') then
        ResultJson := GetNetworkInfoAsJson
      else if (LInfoType = 'all') or (LInfoType = '') then
        ResultJson := GetAllInfoAsJson(AParams.IncludeDetails)
      else
        raise Exception.Create('Invalid information type. Use: basic, memory, disk, network, all');

      // Add user info to JSON
      if Assigned(ResultJson) then
        ResultJson.AddPair('executedBy', AuthContext.UserID);

      // We use the builder to add the JSON as text. The AI will parse it.
      Result := TAiMCPResponseBuilder.New.AddText(ResultJson.ToJSON).Build;
      ResultJson.Free; // Liberamos el JSON que creamos
    end
    else
    begin
      // --- Logic to return Text (as before) ---
      if (LInfoType = 'basic') then
        ResultText := GetBasicInfoAsText
      else if (LInfoType = 'memory') then
        ResultText := GetMemoryInfoAsText
      else if (LInfoType = 'disk') then
        ResultText := GetDiskInfoAsText
      else if (LInfoType = 'network') then
        ResultText := GetNetworkInfoAsText
      else if (LInfoType = 'all') or (LInfoType = '') then
        ResultText := GetAllInfoAsText(AParams.IncludeDetails)
      else
        ResultText := '❌ Invalid information type. Use: basic, memory, disk, network, all';

      // Add user info to text
      if AuthContext.IsAuthenticated then
        ResultText := ResultText + sLineBreak + sLineBreak + '✅ Executed by user: ' + AuthContext.UserID
      else
        ResultText := ResultText + sLineBreak + sLineBreak + '⚠️ Executed by an anonymous user.';

      Result := TAiMCPResponseBuilder.New.AddText(ResultText).Build;
    end;
  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New.AddText('❌ Error obtaining system information: ' + E.Message).Build;
  end;
end;

// =============================================================================
// Implementation of functions that return JSON
// =============================================================================

function TSysInfoTool.GetBasicInfoAsJson: TJSONObject;
var
  ComputerName: array [0 .. MAX_COMPUTERNAME_LENGTH] of Char;
  Size: DWORD;
begin
  Result := TJSONObject.Create;
  Size := MAX_COMPUTERNAME_LENGTH + 1;
  if GetComputerName(ComputerName, Size) then
    Result.AddPair('computerName', string(ComputerName));

  var
  LWinVer := TJSONObject.Create;
  LWinVer.AddPair('major', TJSONNumber.Create(Int64(TOSVersion.Major)));
  LWinVer.AddPair('minor', TJSONNumber.Create(Int64(TOSVersion.Minor)));
  LWinVer.AddPair('build', TJSONNumber.Create(Int64(TOSVersion.Build)));
  Result.AddPair('windowsVersion', LWinVer);

{$IFDEF WIN64}
  Result.AddPair('architecture', '64-bit');
{$ELSE}
  Result.AddPair('architecture', '32-bit');
{$ENDIF}
  Result.AddPair('currentDateTime', FormatDateTime('c', Now)); // ISO 8601 format
end;

function TSysInfoTool.GetMemoryInfoAsJson: TJSONObject;
var
  MemStatus: TMemoryStatusEx;
begin
  Result := TJSONObject.Create;
  MemStatus.dwLength := SizeOf(TMemoryStatusEx);
  if GlobalMemoryStatusEx(MemStatus) then
  begin
    Result.AddPair('totalPhysical_gb', TJSONNumber.Create(MemStatus.ullTotalPhys / (1024 * 1024 * 1024)));
    Result.AddPair('availablePhysical_gb', TJSONNumber.Create(MemStatus.ullAvailPhys / (1024 * 1024 * 1024)));
    Result.AddPair('memoryLoad_percent', TJSONNumber.Create(Int64(MemStatus.dwMemoryLoad)));
  end;
end;

function TSysInfoTool.GetDiskInfoAsJson: TJSONArray;
var
  Drive: Char;
  RootPath: string;
  FreeBytesAvailable, TotalBytes, TotalFreeBytes: Int64;
  LDisk: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Drive := 'A' to 'Z' do
  begin
    RootPath := Drive + ':\';
    if GetDriveType(PChar(RootPath)) = DRIVE_FIXED then
    begin
      if GetDiskFreeSpaceEx(PChar(RootPath), FreeBytesAvailable, TotalBytes, @TotalFreeBytes) then
      begin
        LDisk := TJSONObject.Create;
        LDisk.AddPair('drive', RootPath);
        LDisk.AddPair('total_gb', TJSONNumber.Create(TotalBytes / (1024 * 1024 * 1024)));
        LDisk.AddPair('free_gb', TJSONNumber.Create(TotalFreeBytes / (1024 * 1024 * 1024)));
        Result.AddElement(LDisk);
      end;
    end;
  end;
end;

function TSysInfoTool.GetNetworkInfoAsJson: TJSONObject;
var
  ComputerName: array [0 .. MAX_COMPUTERNAME_LENGTH] of Char;
  Size: DWORD;
begin
  Result := TJSONObject.Create;
  Size := MAX_COMPUTERNAME_LENGTH + 1;
  if GetComputerName(ComputerName, Size) then
    Result.AddPair('networkName', string(ComputerName));
  Result.AddPair('details', 'For more network details, specific APIs are required.');
end;

function TSysInfoTool.GetAllInfoAsJson(IncludeDetails: Boolean): TJSONObject;
begin
  Result := GetBasicInfoAsJson;
  Result.AddPair('memory', GetMemoryInfoAsJson);
  Result.AddPair('disks', GetDiskInfoAsJson);
  Result.AddPair('network', GetNetworkInfoAsJson);

  if IncludeDetails then
  begin
    var
    LDetails := TJSONObject.Create;
    LDetails.AddPair('mcpServerPath', ExtractFilePath(ParamStr(0)));
    LDetails.AddPair('delphiVersion', '12.2'); // O obtenerlo dinámicamente si es posible
    Result.AddPair('extraDetails', LDetails);
  end;
end;


// =============================================================================
// Implementation of Text functions (unchanged, only renamed)
// =============================================================================

function TSysInfoTool.GetBasicInfoAsText: string;
var
  ComputerName: array [0 .. MAX_COMPUTERNAME_LENGTH] of Char;
  Size: DWORD;
begin
  // Original code of GetBasicInfo
  Result := '🖥️ BASIC SYSTEM INFORMATION' + sLineBreak + sLineBreak;
  Size := MAX_COMPUTERNAME_LENGTH + 1;
  if GetComputerName(ComputerName, Size) then
    Result := Result + 'Computer name: ' + string(ComputerName) + sLineBreak;
  Result := Result + Format('Windows: %d.%d (Build %d)', [TOSVersion.Major, TOSVersion.Minor, TOSVersion.Build]) + sLineBreak;
{$IFDEF WIN64}
  Result := Result + 'Architecture: 64-bit' + sLineBreak;
{$ELSE}
  Result := Result + 'Architecture: 32-bit' + sLineBreak;
{$ENDIF}
  Result := Result + 'Date/Time: ' + FormatDateTime('dd/mm/yyyy hh:nn:ss', Now);
end;

function TSysInfoTool.GetMemoryInfoAsText: string;
begin
  // Original code of GetMemoryInfo
  var
    MemStatus: TMemoryStatusEx;
  Result := '💾 MEMORY INFORMATION' + sLineBreak + sLineBreak;
  MemStatus.dwLength := SizeOf(TMemoryStatusEx);
  if GlobalMemoryStatusEx(MemStatus) then
  begin
    Result := Result + Format('Total physical memory: %.2f GB', [MemStatus.ullTotalPhys / (1024 * 1024 * 1024)]) + sLineBreak;
    Result := Result + Format('Available physical memory: %.2f GB', [MemStatus.ullAvailPhys / (1024 * 1024 * 1024)]) + sLineBreak;
    Result := Result + Format('Memory usage: %d%%', [MemStatus.dwMemoryLoad]);
  end;
end;

function TSysInfoTool.GetDiskInfoAsText: string;
var
  Drive: Char;
  RootPath: string;
  FreeBytesAvailable, TotalBytes, TotalFreeBytes: Int64;
begin
  Result := '💿 DISK INFORMATION' + sLineBreak;
  for Drive := 'A' to 'Z' do
  begin
    RootPath := Drive + ':\';
    if GetDriveType(PChar(RootPath)) = DRIVE_FIXED then
    begin
      if GetDiskFreeSpaceEx(PChar(RootPath), FreeBytesAvailable, TotalBytes, @TotalFreeBytes) then
        Result := Result + sLineBreak + Format('Drive %s: %.2f GB free of %.2f GB total',
          [RootPath, TotalFreeBytes / (1024 * 1024 * 1024), TotalBytes / (1024 * 1024 * 1024)]);
    end;
  end;
end;

function TSysInfoTool.GetNetworkInfoAsText: string;
  var
    ComputerName: array [0 .. MAX_COMPUTERNAME_LENGTH] of Char;
    Size: DWORD;
begin
  Result := '🌐 NETWORK INFORMATION' + sLineBreak + sLineBreak;
  Size := MAX_COMPUTERNAME_LENGTH + 1;
  if GetComputerName(ComputerName, Size) then
    Result := Result + 'Network name: ' + string(ComputerName) + sLineBreak;
  Result := Result + 'Note: For more network details, specific APIs are required.';
end;

function TSysInfoTool.GetAllInfoAsText(IncludeDetails: Boolean): string;
begin
  // Original code of GetAllInfo
  Result := GetBasicInfoAsText + sLineBreak + sLineBreak + GetMemoryInfoAsText + sLineBreak + sLineBreak + GetDiskInfoAsText + sLineBreak +
    sLineBreak + GetNetworkInfoAsText;
  if IncludeDetails then
    Result := Result + sLineBreak + sLineBreak + '📊 ADDITIONAL DETAILS' + sLineBreak + 'MCP server running from: ' +
      ExtractFilePath(ParamStr(0)) + sLineBreak + 'Compiled with: Delphi 12.2';
end;

end.
