unit uFireDACTool;

// =============================================================================
// mcp-firedac  —  Universal MCP server for databases via FireDAC
//
// Supports any FireDAC driver: SQLite, PostgreSQL, Firebird, MySQL,
// MSSQL, Oracle, InterBase, etc.
//
// Exposed tools:
//   db_query    — Executes SELECT, returns results as a text table or JSON
//   db_execute  — Executes INSERT/UPDATE/DELETE/DDL
//   db_tables   — Lists tables and views of the database
//   db_describe — Describes the columns of a table
//   db_info     — Information about the active connection
//
// Configuration (passed from the .dpr after parsing CLI args):
//   TDbConfig.Driver      — FireDAC DriverID (SQLite, PG, FB, MySQL, MSSQL...)
//   TDbConfig.Database    — File path (SQLite) or database name (others)
//   TDbConfig.Host        — Server (network drivers only)
//   TDbConfig.Port        — Port (0 = use driver default)
//   TDbConfig.Username    — User
//   TDbConfig.Password    — Password
//   TDbConfig.Charset     — Charset (optional, e.g. UTF8)
//   TDbConfig.ConnString  — Complete FireDAC connection string (alternative)
// =============================================================================

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.StrUtils,
  System.Math,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Def,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Async,
  FireDAC.Phys.Intf,
  FireDAC.DApt.Intf,
  FireDAC.DApt,
  FireDAC.Stan.ExprFuncs,
  uMakerAi.MCPServer.Core;

// =============================================================================
// Configuración global de conexión
// =============================================================================

type
  TDbConfig = record
    Driver     : string;  // FireDAC DriverID
    Database   : string;  // file (SQLite) or database name
    Host       : string;
    Port       : Integer; // 0 = default del driver
    Username   : string;
    Password   : string;
    Charset    : string;
    ConnString : string;  // if a direct connection string is used
    MaxRows    : Integer; // global row limit (default 200)
  end;

var
  GDbConfig: TDbConfig;

// Inicializar y conectar (llamar desde .dpr antes de Server.Start)
procedure DbConnect;
procedure DbDisconnect;
function  DbConnection: TFDConnection;

// =============================================================================
// Parámetros de herramientas
// =============================================================================

type

  // ── db_query ────────────────────────────────────────────────────────────────
  TDbQueryParams = class
  private
    FSQL    : string;
    FMaxRows: Integer;
    FFormat : string;
  public
    [AiMCPSchemaDescription('SQL SELECT query to execute')]
    property SQL: string read FSQL write FSQL;

    [AiMCPSchemaDescription('Maximum number of rows to return. Default: 100')]
    [AiMCPOptional]
    property MaxRows: Integer read FMaxRows write FMaxRows;

    [AiMCPSchemaDescription('Output format: "table" (default, ASCII grid), "json" (JSON array), "csv"')]
    [AiMCPOptional]
    property Format: string read FFormat write FFormat;
  end;

  TDbQueryTool = class(TAiMCPToolBase<TDbQueryParams>)
  protected
    function ExecuteWithParams(const AParams: TDbQueryParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

  // ── db_execute ──────────────────────────────────────────────────────────────
  TDbExecuteParams = class
  private
    FSQL       : string;
    FAutoCommit: Boolean;
  public
    [AiMCPSchemaDescription('SQL statement to execute: INSERT, UPDATE, DELETE, CREATE TABLE, DROP, ALTER, etc.')]
    property SQL: string read FSQL write FSQL;

    [AiMCPSchemaDescription('Auto-commit after execution. Default: true')]
    [AiMCPOptional]
    property AutoCommit: Boolean read FAutoCommit write FAutoCommit;
  end;

  TDbExecuteTool = class(TAiMCPToolBase<TDbExecuteParams>)
  protected
    function ExecuteWithParams(const AParams: TDbExecuteParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

  // ── db_tables ───────────────────────────────────────────────────────────────
  TDbTablesParams = class
  private
    FSchema     : string;
    FIncludeType: string;
  public
    [AiMCPSchemaDescription('Schema/owner filter (optional). Leave empty for all schemas.')]
    [AiMCPOptional]
    property Schema: string read FSchema write FSchema;

    [AiMCPSchemaDescription('Object types to include: "tables" (default), "views", "all"')]
    [AiMCPOptional]
    property IncludeType: string read FIncludeType write FIncludeType;
  end;

  TDbTablesTool = class(TAiMCPToolBase<TDbTablesParams>)
  protected
    function ExecuteWithParams(const AParams: TDbTablesParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

  // ── db_describe ─────────────────────────────────────────────────────────────
  TDbDescribeParams = class
  private
    FTableName: string;
    FSchema   : string;
  public
    [AiMCPSchemaDescription('Name of the table or view to describe')]
    property TableName: string read FTableName write FTableName;

    [AiMCPSchemaDescription('Schema/owner (optional)')]
    [AiMCPOptional]
    property Schema: string read FSchema write FSchema;
  end;

  TDbDescribeTool = class(TAiMCPToolBase<TDbDescribeParams>)
  protected
    function ExecuteWithParams(const AParams: TDbDescribeParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

  // ── db_info ─────────────────────────────────────────────────────────────────
  TDbInfoParams = class
  end;

  TDbInfoTool = class(TAiMCPToolBase<TDbInfoParams>)
  protected
    function ExecuteWithParams(const AParams: TDbInfoParams;
      const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

implementation

// =============================================================================
// Gestión de conexión global
// =============================================================================

var
  GConnection: TFDConnection = nil;

procedure DbConnect;
var
  Params: TStrings;
begin
  if Assigned(GConnection) then
    GConnection.Free;

  GConnection := TFDConnection.Create(nil);
  GConnection.LoginPrompt := False;

  if GDbConfig.ConnString <> '' then
  begin
    // Direct connection string mode
    Params := TStringList.Create;
    try
      TStringList(Params).Delimiter     := ';';
      TStringList(Params).DelimitedText := GDbConfig.ConnString;
      GConnection.Params.Assign(Params);
    finally
      Params.Free;
    end;
  end
  else
  begin
    // Individual parameters mode
    GConnection.Params.DriverID := GDbConfig.Driver;

    if GDbConfig.Database <> '' then
      GConnection.Params.Database := GDbConfig.Database;

    if GDbConfig.Host <> '' then
      GConnection.Params.Values['Server'] := GDbConfig.Host;

    if GDbConfig.Port > 0 then
      GConnection.Params.Values['Port'] := IntToStr(GDbConfig.Port);

    if GDbConfig.Username <> '' then
      GConnection.Params.UserName := GDbConfig.Username;

    if GDbConfig.Password <> '' then
      GConnection.Params.Password := GDbConfig.Password;

    if GDbConfig.Charset <> '' then
      GConnection.Params.Values['CharacterSet'] := GDbConfig.Charset;
  end;

  GConnection.Connected := True;
end;

procedure DbDisconnect;
begin
  FreeAndNil(GConnection);
end;

function DbConnection: TFDConnection;
begin
  if not Assigned(GConnection) or not GConnection.Connected then
  begin
    try
      DbConnect;
    except on E: Exception do
      raise Exception.CreateFmt('Cannot connect to database: %s', [E.Message]);
    end;
  end;
  Result := GConnection;
end;

// =============================================================================
// Formateo de resultados
// =============================================================================

// Returns a field value as a readable string
function FieldToStr(Field: TField): string;
begin
  if Field.IsNull then
    Result := 'NULL'
  else
    case Field.DataType of
      ftFloat, ftCurrency, ftBCD, ftFMTBcd:
        Result := FloatToStr(Field.AsFloat);
      ftDate:
        Result := FormatDateTime('yyyy-mm-dd', Field.AsDateTime);
      ftTime:
        Result := FormatDateTime('hh:nn:ss', Field.AsDateTime);
      ftDateTime, ftTimeStamp:
        Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', Field.AsDateTime);
      ftBoolean:
        Result := BoolToStr(Field.AsBoolean, True);
      ftBlob, ftMemo, ftWideMemo, ftGraphic:
        Result := Format('<BLOB %d bytes>', [Field.DataSize]);
    else
      Result := Field.AsString;
    end;
end;

// Formats a query result as an ASCII table
function ResultToTable(AQuery: TFDQuery; AMaxRows: Integer): string;
var
  ColWidths  : array of Integer;
  I, Row     : Integer;
  SB         : TStringBuilder;
  FieldVal   : string;
  TotalWidth : Integer;
  Sep        : string;
begin
  if AQuery.RecordCount = 0 then
  begin
    Result := '(0 rows)';
    Exit;
  end;

  SetLength(ColWidths, AQuery.FieldCount);

  // Calculate widths: minimum = length of column name
  for I := 0 to AQuery.FieldCount - 1 do
    ColWidths[I] := Length(AQuery.Fields[I].FieldName);

  // First pass: calculate maximum widths (limited to 50 chars for readability)
  AQuery.First;
  Row := 0;
  while not AQuery.Eof and (Row < AMaxRows) do
  begin
    for I := 0 to AQuery.FieldCount - 1 do
    begin
      FieldVal := FieldToStr(AQuery.Fields[I]);
      if Length(FieldVal) > ColWidths[I] then
        ColWidths[I] := Min(Length(FieldVal), 50);
    end;
    AQuery.Next;
    Inc(Row);
  end;

  SB := TStringBuilder.Create;
  try
    // Separator
    TotalWidth := 1;
    for I := 0 to AQuery.FieldCount - 1 do
      Inc(TotalWidth, ColWidths[I] + 3);
    Sep := '+' + StringOfChar('-', TotalWidth - 2) + '+';

    // Rebuild separator by columns
    Sep := '+';
    for I := 0 to AQuery.FieldCount - 1 do
      Sep := Sep + StringOfChar('-', ColWidths[I] + 2) + '+';

    // Encabezado
    SB.AppendLine(Sep);
    var HeaderLine: string := '|';
    for I := 0 to AQuery.FieldCount - 1 do
    begin
      var ColName := AQuery.Fields[I].FieldName;
      HeaderLine := HeaderLine + ' ' + ColName.PadRight(ColWidths[I]) + ' |';
    end;
    SB.AppendLine(HeaderLine);
    SB.AppendLine(Sep);

    // Filas
    AQuery.First;
    Row := 0;
    while not AQuery.Eof and (Row < AMaxRows) do
    begin
      var RowLine: string := '|';
      for I := 0 to AQuery.FieldCount - 1 do
      begin
        FieldVal := FieldToStr(AQuery.Fields[I]);
        if Length(FieldVal) > ColWidths[I] then
          FieldVal := Copy(FieldVal, 1, ColWidths[I] - 3) + '...';
        // Numbers right-aligned
        if AQuery.Fields[I].DataType in [ftInteger, ftLargeint, ftSmallint,
            ftWord, ftFloat, ftCurrency, ftBCD, ftFMTBcd, ftAutoInc] then
          RowLine := RowLine + ' ' + FieldVal.PadLeft(ColWidths[I]) + ' |'
        else
          RowLine := RowLine + ' ' + FieldVal.PadRight(ColWidths[I]) + ' |';
      end;
      SB.AppendLine(RowLine);
      AQuery.Next;
      Inc(Row);
    end;
    SB.AppendLine(Sep);

    var RowCount := AQuery.RecordCount;
    if Row < RowCount then
      SB.AppendFormat('(%d of %d rows — use MaxRows to see more)', [Row, RowCount]).AppendLine
    else
      SB.AppendFormat('(%d row%s)', [Row, IfThen(Row = 1, '', 's')]).AppendLine;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Formats the result as a JSON array of objects
function ResultToJSON(AQuery: TFDQuery; AMaxRows: Integer): string;
var
  JArr  : TJSONArray;
  JRow  : TJSONObject;
  I     : Integer;
  Row   : Integer;
  Field : TField;
begin
  JArr := TJSONArray.Create;
  try
    AQuery.First;
    Row := 0;
    while not AQuery.Eof and (Row < AMaxRows) do
    begin
      JRow := TJSONObject.Create;
      for I := 0 to AQuery.FieldCount - 1 do
      begin
        Field := AQuery.Fields[I];
        if Field.IsNull then
          JRow.AddPair(Field.FieldName, TJSONNull.Create)
        else
          case Field.DataType of
            ftInteger, ftSmallint, ftWord, ftAutoInc:
              JRow.AddPair(Field.FieldName, TJSONNumber.Create(Field.AsInteger));
            ftLargeint:
              JRow.AddPair(Field.FieldName, TJSONNumber.Create(Field.AsLargeInt));
            ftFloat, ftCurrency, ftBCD, ftFMTBcd:
              JRow.AddPair(Field.FieldName, TJSONNumber.Create(Field.AsFloat));
            ftBoolean:
              JRow.AddPair(Field.FieldName, TJSONBool.Create(Field.AsBoolean));
          else
            JRow.AddPair(Field.FieldName, FieldToStr(Field));
          end;
      end;
      JArr.Add(JRow);
      AQuery.Next;
      Inc(Row);
    end;
    Result := JArr.Format(2);
  finally
    JArr.Free;
  end;
end;

// Formats the result as CSV
function ResultToCSV(AQuery: TFDQuery; AMaxRows: Integer): string;
var
  SB  : TStringBuilder;
  I   : Integer;
  Row : Integer;
begin
  SB := TStringBuilder.Create;
  try
    // Encabezado
    for I := 0 to AQuery.FieldCount - 1 do
    begin
      if I > 0 then SB.Append(',');
      SB.Append('"').Append(AQuery.Fields[I].FieldName).Append('"');
    end;
    SB.AppendLine;

    // Filas
    AQuery.First;
    Row := 0;
    while not AQuery.Eof and (Row < AMaxRows) do
    begin
      for I := 0 to AQuery.FieldCount - 1 do
      begin
        if I > 0 then SB.Append(',');
        var Val := FieldToStr(AQuery.Fields[I]);
        if Val.Contains(',') or Val.Contains('"') or Val.Contains(#10) then
          SB.Append('"').Append(StringReplace(Val, '"', '""', [rfReplaceAll])).Append('"')
        else
          SB.Append(Val);
      end;
      SB.AppendLine;
      AQuery.Next;
      Inc(Row);
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// =============================================================================
// TDbQueryTool
// =============================================================================

constructor TDbQueryTool.Create;
begin
  inherited;
  FName        := 'db_query';
  FDescription :=
    'Execute a SQL SELECT query and return the results. ' +
    'Supports format options: "table" (ASCII grid, default), "json" (JSON array), "csv". ' +
    'Use MaxRows to limit the number of rows returned (default 100).';
end;

function TDbQueryTool.ExecuteWithParams(const AParams: TDbQueryParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Query   : TFDQuery;
  MaxRows : Integer;
  Fmt     : string;
  Output  : string;
begin
  if Trim(AParams.SQL) = '' then
    raise Exception.Create('SQL parameter is required');

  // Basic security validation: only SELECT allowed in db_query
  var SQLUp := UpperCase(Trim(AParams.SQL));
  if not (SQLUp.StartsWith('SELECT') or SQLUp.StartsWith('WITH')
      or SQLUp.StartsWith('SHOW') or SQLUp.StartsWith('EXPLAIN')
      or SQLUp.StartsWith('DESCRIBE') or SQLUp.StartsWith('PRAGMA')) then
    raise Exception.Create('db_query only accepts SELECT/WITH/SHOW/EXPLAIN/PRAGMA. Use db_execute for DML/DDL.');

  MaxRows := AParams.MaxRows;
  if MaxRows <= 0 then MaxRows := 100;
  MaxRows := Min(MaxRows, GDbConfig.MaxRows);

  Fmt := LowerCase(Trim(AParams.Format));
  if Fmt = '' then Fmt := 'table';

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := DbConnection;
    Query.SQL.Text   := AParams.SQL;
    Query.Open;

    case AnsiIndexStr(Fmt, ['json', 'csv', 'table']) of
      0: Output := ResultToJSON(Query, MaxRows);
      1: Output := ResultToCSV(Query, MaxRows);
    else  Output := ResultToTable(Query, MaxRows);
    end;

    Result := TAiMCPResponseBuilder.New.AddText(Output).Build;
  finally
    Query.Free;
  end;
end;

// =============================================================================
// TDbExecuteTool
// =============================================================================

constructor TDbExecuteTool.Create;
begin
  inherited;
  FName        := 'db_execute';
  FDescription :=
    'Execute a SQL statement: INSERT, UPDATE, DELETE, CREATE TABLE, DROP, ALTER, etc. ' +
    'Returns the number of affected rows. ' +
    'WARNING: DDL statements (CREATE, DROP, ALTER) are irreversible — use with care.';
end;

function TDbExecuteTool.ExecuteWithParams(const AParams: TDbExecuteParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Query       : TFDQuery;
  RowsAffected: Integer;
  AutoCommit  : Boolean;
begin
  if Trim(AParams.SQL) = '' then
    raise Exception.Create('SQL parameter is required');

  AutoCommit := AParams.AutoCommit;
  if not AutoCommit then
    AutoCommit := True; // default: True

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := DbConnection;
    Query.SQL.Text   := AParams.SQL;

    if not AutoCommit then
      DbConnection.StartTransaction;
    try
      Query.ExecSQL;
      RowsAffected := Query.RowsAffected;
      if not AutoCommit then
        DbConnection.Commit;
    except
      if not AutoCommit then
        DbConnection.Rollback;
      raise;
    end;

    Result := TAiMCPResponseBuilder.New
      .AddText(Format('OK — %d row(s) affected.', [RowsAffected]))
      .Build;
  finally
    Query.Free;
  end;
end;

// =============================================================================
// TDbTablesTool
// =============================================================================

constructor TDbTablesTool.Create;
begin
  inherited;
  FName        := 'db_tables';
  FDescription :=
    'List all tables and/or views in the connected database. ' +
    'Optionally filter by schema/owner. ' +
    'IncludeType: "tables" (default), "views", "all".';
end;

function TDbTablesTool.ExecuteWithParams(const AParams: TDbTablesParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  List    : TStringList;
  Meta    : TFDMetaInfoQuery;
  SB      : TStringBuilder;
  IncType : string;
begin
  IncType := LowerCase(Trim(AParams.IncludeType));
  if IncType = '' then IncType := 'tables';

  Meta := TFDMetaInfoQuery.Create(nil);
  List := TStringList.Create;
  SB   := TStringBuilder.Create;
  try
    Meta.Connection   := DbConnection;
    // mkTables returns both tables and views; filter by TABLE_TYPE
    Meta.MetaInfoKind := mkTables;
    if AParams.Schema <> '' then
      Meta.SchemaName := AParams.Schema;
    Meta.Open;

    while not Meta.Eof do
    begin
      var SchemaField := Meta.FindField('TABLE_SCHEMA');
      var SchemaStr   := '';
      if Assigned(SchemaField) then SchemaStr := SchemaField.AsString;
      var TName       := Meta.FieldByName('TABLE_NAME').AsString;
      var TypeField   := Meta.FindField('TABLE_TYPE');
      var TableType   := '';
      if Assigned(TypeField) then TableType := UpperCase(Trim(TypeField.AsString));

      var IsView  := (TableType = 'VIEW') or (TableType = 'V');
      var IsTable := not IsView;

      var Include :=
        (IncType = 'all') or
        ((IncType = 'tables') and IsTable) or
        ((IncType = 'views')  and IsView);

      if Include then
      begin
        var Prefix: string := IfThen(IsView, 'VIEW  ', 'TABLE ');
        if SchemaStr <> '' then
          List.Add(Prefix + ' ' + SchemaStr + '.' + TName)
        else
          List.Add(Prefix + ' ' + TName);
      end;

      Meta.Next;
    end;
    Meta.Close;

    List.Sort;

    if List.Count = 0 then
      SB.Append('(no objects found)')
    else
    begin
      SB.AppendFormat('%d object(s) found:', [List.Count]).AppendLine;
      for var S in List do
        SB.AppendLine('  ' + S);
    end;

    Result := TAiMCPResponseBuilder.New.AddText(SB.ToString).Build;
  finally
    Meta.Free;
    List.Free;
    SB.Free;
  end;
end;

// =============================================================================
// TDbDescribeTool
// =============================================================================

constructor TDbDescribeTool.Create;
begin
  inherited;
  FName        := 'db_describe';
  FDescription :=
    'Describe the columns of a table or view: column name, data type, ' +
    'nullable, default value, primary key flag.';
end;

function TDbDescribeTool.ExecuteWithParams(const AParams: TDbDescribeParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Meta  : TFDMetaInfoQuery;
  SB    : TStringBuilder;
begin
  if Trim(AParams.TableName) = '' then
    raise Exception.Create('TableName parameter is required');

  Meta := TFDMetaInfoQuery.Create(nil);
  SB   := TStringBuilder.Create;
  try
    Meta.Connection    := DbConnection;
    Meta.MetaInfoKind  := mkTableFields;
    Meta.ObjectName    := AParams.TableName;
    if AParams.Schema <> '' then
      Meta.SchemaName := AParams.Schema;
    Meta.Open;

    if Meta.RecordCount = 0 then
    begin
      SB.AppendFormat('Table "%s" not found or has no columns.', [AParams.TableName]);
      Result := TAiMCPResponseBuilder.New.AddText(SB.ToString).Build;
      Exit;
    end;

    SB.AppendFormat('Table: %s', [AParams.TableName]).AppendLine;
    SB.AppendLine(StringOfChar('-', 80));
    SB.AppendLine(Format('%-30s %-20s %-8s %-8s %s',
      ['Column', 'Type', 'Nullable', 'PK', 'Default']));
    SB.AppendLine(StringOfChar('-', 80));

    while not Meta.Eof do
    begin
      var ColName  := Meta.FieldByName('COLUMN_NAME').AsString;
      var ColType  := Meta.FieldByName('COLUMN_TYPENAME').AsString;
      var Len      := Meta.FieldByName('COLUMN_LENGTH').AsInteger;
      var Nullable := IfThen(Meta.FieldByName('COLUMN_NULLABLE').AsBoolean, 'YES', 'NO');
      var IsPK     := IfThen(not Meta.FieldByName('COLUMN_PKEY').IsNull and
                             Meta.FieldByName('COLUMN_PKEY').AsBoolean, 'PK', '');
      var ColDefault := '';
      if not Meta.FieldByName('COLUMN_DEFAULT').IsNull then
        ColDefault := Meta.FieldByName('COLUMN_DEFAULT').AsString;

      // Show length for types that support it
      var TypeStr := ColType;
      if Len > 0 then
        TypeStr := Format('%s(%d)', [ColType, Len]);

      SB.AppendLine(Format('%-30s %-20s %-8s %-8s %s',
        [ColName, TypeStr, Nullable, IsPK, ColDefault]));

      Meta.Next;
    end;
    SB.AppendLine(StringOfChar('-', 80));

    Result := TAiMCPResponseBuilder.New.AddText(SB.ToString).Build;
  finally
    Meta.Free;
    SB.Free;
  end;
end;

// =============================================================================
// TDbInfoTool
// =============================================================================

constructor TDbInfoTool.Create;
begin
  inherited;
  FName        := 'db_info';
  FDescription :=
    'Returns information about the active database connection: ' +
    'driver, server version, database name, and connection status.';
end;

function TDbInfoTool.ExecuteWithParams(const AParams: TDbInfoParams;
  const AuthContext: TAiAuthContext): TJSONObject;
var
  Conn : TFDConnection;
  SB   : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    try
      Conn := DbConnection;
      SB.AppendFormat('Status    : Connected', []).AppendLine;
      SB.AppendFormat('Driver    : %s', [Conn.Params.DriverID]).AppendLine;
      SB.AppendFormat('Database  : %s', [Conn.Params.Database]).AppendLine;
      if Conn.Params.Values['Server'] <> '' then
        SB.AppendFormat('Server    : %s', [Conn.Params.Values['Server']]).AppendLine;
    except on E: Exception do
      SB.AppendFormat('Status    : ERROR — %s', [E.Message]).AppendLine;
    end;

    // Show global config (without password)
    SB.AppendLine;
    SB.AppendFormat('MaxRows   : %d', [GDbConfig.MaxRows]).AppendLine;

    Result := TAiMCPResponseBuilder.New.AddText(SB.ToString).Build;
  finally
    SB.Free;
  end;
end;

initialization
  GDbConfig.Driver  := 'SQLite';
  GDbConfig.MaxRows := 500;

finalization
  DbDisconnect;

end.
