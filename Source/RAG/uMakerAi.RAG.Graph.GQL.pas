unit uMakerAi.RAG.Graph.GQL;

interface

uses

  System.SysUtils, System.Character, System.Generics.Collections, System.Variants, System.TypInfo,
  uMakerAi.RAG.Graph.Core, // Required for TBinaryOp, TGraphExpression, etc.
  uMakerAi.RAG.MetaData; // Required for TFilterOperator

type
  { Token types supported by the MakerAI GQL Lite language }
  TTokenKind = (tkEOF,

    // Structure and Delimiters
    tkLParen, // (
    tkRParen, // )
    tkLBracket, // [
    tkRBracket, // ]
    tkLBrace, // {
    tkRBrace, // }
    tkColon, // :
    tkComma, // ,
    tkDot, // .
    tkDash, // -
    tkArrowLeft, // <-
    tkArrowRight, // ->

    // Literals
    tkIdentifier, // Variables, labels, keys
    tkString, // 'Text' or "Text"
    tkNumber, // 123, 123.45
    tkBoolean, // TRUE, FALSE
    tkNull, // NULL

    // Reserved Words: Query Structure
    tkMatch, tkWhere, tkReturn, tkShow, tkLabels, tkEdges,

    // Logical operators
    tkAnd, tkOr, tkNot, // New: For NOT IN, IS NOT NULL

    // Comparison and Text operators (Aligned with TAiFilterCriteria)
    tkEqual, // =
    tkNotEqual, // <>
    tkGreater, // >
    tkGreaterEqual, // >=
    tkLess, // <
    tkLessEqual, // <=
    tkLike, // LIKE (New)
    tkILike, // ILIKE (New)
    tkContains, // CONTAINS
    tkIn, // IN
    tkIs, // IS
    tkAsterisk,

    // Aggregate functions and Modifiers
    tkCount, tkSum, tkAvg, tkDepth,

    // Reserved Words: Graph Algorithms
    tkShortest, tkPath, tkTo, tkGet, tkCentrality, tkDegrees, tkTop);

  TGraphCommandType = (cmdNone, cmdShowLabels, cmdShowEdges, cmdShortestPath, cmdCentrality, cmdDegrees);

  TToken = record
    Kind: TTokenKind;
    Text: string;
    Position: Integer;
  end;

  { Lexical analyzer (Lexer) }
  TGraphLexer = class
  private
    FText: string;
    FPos: Integer;

    // internal navigation methods
    function Peek: Char;
    function Next: Char;
    procedure SkipWhitespace;
    function IsEOF: Boolean;

    // methods for reading specific token types
    function ReadIdentifier: TToken;
    function ReadString: TToken;
    function ReadNumber: TToken;
  public
    constructor Create(const AText: string);
    function NextToken: TToken;
  end;

  // ================================================
  // ============ GRAPH PARSER ======================
  // ================================================

  TGraphParser = class
  private
    FLexer: TGraphLexer;
    FCurrent: TToken;
    FNodeVariables: TDictionary<string, TMatchNodePattern>;
    FCommandType: TGraphCommandType;
    FCommandSourcePattern: TMatchNodePattern;
    FCommandTargetPattern: TMatchNodePattern;
    FCommandLimit: Integer;

    procedure Next;
    function GetTokenTextAndNext: string;
    procedure Expect(AKind: TTokenKind);

    // internal parsing methods
    function ParseNode(AQuery: TGraphMatchQuery): TMatchNodePattern;
    function ParseEdge(out ADirection: TGraphDirection): TMatchEdgePattern;
    procedure ParseProperties(AProps: TDictionary<string, Variant>);

    // expression parsing methods (new)
    function ParseExpression: TGraphExpression;
    function ParseAndExpression: TGraphExpression;
    function ParseComparison: TGraphExpression;
    function ParsePrimary: TGraphExpression;
    function ParseValueList: Variant;

    procedure ParseMatchClause(AQuery: TGraphMatchQuery);
    procedure ParseWhereClause(AQuery: TGraphMatchQuery);
    procedure ParseReturnClause(AQuery: TGraphMatchQuery);
    procedure ClearCommandPatterns;

  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    function Parse: TGraphMatchQuery;

    property CommandType: TGraphCommandType read FCommandType;
    property CommandSourcePattern: TMatchNodePattern read FCommandSourcePattern;
    property CommandTargetPattern: TMatchNodePattern read FCommandTargetPattern;
    property CommandLimit: Integer read FCommandLimit;
  end;

implementation

{ TGraphLexer }

constructor TGraphLexer.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
end;

function TGraphLexer.Peek: Char;
begin
  if FPos > Length(FText) then
    Result := #0
  else
    Result := FText[FPos];
end;

function TGraphLexer.Next: Char;
begin
  Result := Peek;
  Inc(FPos);
end;

function TGraphLexer.IsEOF: Boolean;
begin
  Result := FPos > Length(FText);
end;

procedure TGraphLexer.SkipWhitespace;
begin
  while (not IsEOF) and Peek.IsWhiteSpace do
    Next;
end;

function TGraphLexer.ReadString: TToken;
var
  Quote: Char;
  Start: Integer;
begin
  Quote := Next; // Consume opening quote (' or ")
  Start := FPos;

  // Read until closing quote or EOF
  while (not IsEOF) and (Peek <> Quote) do
    Next;

  Result.Kind := tkString;
  // Extract the text WITHOUT the quotes
  Result.Text := Copy(FText, Start, FPos - Start);
  Result.Position := Start - 1; // position of the start of the string

  if not IsEOF then
    Next; // Consume closing quote
end;

function TGraphLexer.ReadNumber: TToken;
var
  Start: Integer;
  HasDot: Boolean;
begin
  Start := FPos;
  HasDot := False;

  while (not IsEOF) and (Peek.IsDigit or (Peek = '.')) do
  begin
    if Peek = '.' then
    begin
      // only allow one decimal point
      if HasDot then
        Break;
      HasDot := True;
    end;
    Next;
  end;

  Result.Kind := tkNumber;
  Result.Text := Copy(FText, Start, FPos - Start);
  Result.Position := Start;
end;

function TGraphLexer.ReadIdentifier: TToken;
var
  Start: Integer;
  UpperText: string;
begin
  Start := FPos;

  // Read letters, digits or underscores
  while (not IsEOF) and (Peek.IsLetterOrDigit or (Peek = '_')) do
    Next;

  Result.Text := Copy(FText, Start, FPos - Start);
  Result.Position := Start;

  // Normalize to uppercase to check reserved words
  UpperText := Result.Text.ToUpper;

  // --- RESERVED WORD MAPPING ---

  // Basic structure
  if UpperText = 'MATCH' then
    Result.Kind := tkMatch
  else if UpperText = 'WHERE' then
    Result.Kind := tkWhere
  else if UpperText = 'RETURN' then
    Result.Kind := tkReturn

    // Logical operators
  else if UpperText = 'AND' then
    Result.Kind := tkAnd
  else if UpperText = 'OR' then
    Result.Kind := tkOr
  else if UpperText = 'NOT' then
    Result.Kind := tkNot

    // Boolean values / Nulls
  else if (UpperText = 'TRUE') or (UpperText = 'FALSE') then
    Result.Kind := tkBoolean
  else if UpperText = 'NULL' then
    Result.Kind := tkNull

    // Introspection
  else if UpperText = 'SHOW' then
    Result.Kind := tkShow
  else if UpperText = 'LABELS' then
    Result.Kind := tkLabels
  else if UpperText = 'EDGES' then
    Result.Kind := tkEdges

    // Textual comparison operators and Lists
  else if UpperText = 'CONTAINS' then
    Result.Kind := tkContains
  else if UpperText = 'LIKE' then
    Result.Kind := tkLike
  else if UpperText = 'ILIKE' then
    Result.Kind := tkILike
  else if UpperText = 'IN' then
    Result.Kind := tkIn
  else if UpperText = 'IS' then
    Result.Kind := tkIs

    // Aggregation and Modifiers
  else if UpperText = 'SUM' then
    Result.Kind := tkSum
  else if UpperText = 'AVG' then
    Result.Kind := tkAvg
  else if UpperText = 'COUNT' then
    Result.Kind := tkCount
  else if UpperText = 'DEPTH' then
    Result.Kind := tkDepth

    // Graph Algorithms
  else if UpperText = 'SHORTEST' then
    Result.Kind := tkShortest
  else if UpperText = 'PATH' then
    Result.Kind := tkPath
  else if UpperText = 'TO' then
    Result.Kind := tkTo
  else if UpperText = 'GET' then
    Result.Kind := tkGet
  else if UpperText = 'CENTRALITY' then
    Result.Kind := tkCentrality
  else if UpperText = 'DEGREES' then
    Result.Kind := tkDegrees
  else if UpperText = 'TOP' then
    Result.Kind := tkTop

    // If not reserved, it's an identifier
  else
    Result.Kind := tkIdentifier;
end;

function TGraphLexer.NextToken: TToken;
begin
  SkipWhitespace;

  Result.Position := FPos;
  Result.Text := '';

  if IsEOF then
  begin
    Result.Kind := tkEOF;
    Exit;
  end;

  case Peek of
    // Simple Delimiters
    '(':
      begin
        Result.Text := '(';
        Next;
        Result.Kind := tkLParen;
      end;
    ')':
      begin
        Result.Text := ')';
        Next;
        Result.Kind := tkRParen;
      end;
    '[':
      begin
        Result.Text := '[';
        Next;
        Result.Kind := tkLBracket;
      end;
    ']':
      begin
        Result.Text := ']';
        Next;
        Result.Kind := tkRBracket;
      end;
    '{':
      begin
        Result.Text := '{';
        Next;
        Result.Kind := tkLBrace;
      end;
    '}':
      begin
        Result.Text := '}';
        Next;
        Result.Kind := tkRBrace;
      end;
    ':':
      begin
        Result.Text := ':';
        Next;
        Result.Kind := tkColon;
      end;
    ',':
      begin
        Result.Text := ',';
        Next;
        Result.Kind := tkComma;
      end;
    '.':
      begin
        Result.Text := '.';
        Next;
        Result.Kind := tkDot;
      end;
    '=':
      begin
        Result.Text := '=';
        Next;
        Result.Kind := tkEqual;
      end;
    '*':
      begin
        Result.Text := '*';
        Next;
        Result.Kind := tkAsterisk; // Or use a generic token if you prefer
      end;

    // Compound Operators starting with '<'
    '<':
      begin
        Next;
        if Peek = '-' then
        begin
          Next;
          Result.Kind := tkArrowLeft; // <-
          Result.Text := '<-';
        end
        else if Peek = '>' then
        begin
          Next;
          Result.Kind := tkNotEqual; // <>
          Result.Text := '<>';
        end
        else if Peek = '=' then
        begin
          Next;
          Result.Kind := tkLessEqual; // <=
          Result.Text := '<=';
        end
        else
        begin
          Result.Kind := tkLess; // <
          Result.Text := '<';
        end;
      end;

    // Compound Operators starting with '>'
    '>':
      begin
        Next;
        if Peek = '=' then
        begin
          Next;
          Result.Kind := tkGreaterEqual; // >=
          Result.Text := '>=';
        end
        else
        begin
          Result.Kind := tkGreater; // >
          Result.Text := '>';
        end;
      end;

    // Compound Operators starting with '-'
    '-':
      begin
        Next;
        if Peek = '>' then
        begin
          Next;
          Result.Kind := tkArrowRight; // ->
          Result.Text := '->';
        end
        else
        begin
          Result.Kind := tkDash; // -
          Result.Text := '-';
        end;
      end;

    // Text strings
    '''', '"':
      begin
        Result := ReadString;
      end;

  else
    // Identifiers and numbers
    if Peek.IsLetter or (Peek = '_') then
      Result := ReadIdentifier
    else if Peek.IsDigit then
      Result := ReadNumber
    else
      // Error: unexpected character
      raise Exception.CreateFmt('Lexical error: Unexpected character "%s" at position %d', [Peek, FPos]);
  end;
end;


// ================================================
// ============ GRAPH PARSER ======================
// ================================================

{ TGraphParser }

constructor TGraphParser.Create(const AText: string);
begin
  inherited Create;
  FLexer := TGraphLexer.Create(AText);
  FNodeVariables := TDictionary<string, TMatchNodePattern>.Create;
  FCommandType := cmdNone;
  FCommandSourcePattern := nil;
  FCommandTargetPattern := nil;
  FCommandLimit := 0;
  Next;
end;

destructor TGraphParser.Destroy;
begin
  ClearCommandPatterns;
  FNodeVariables.Free;
  FLexer.Free;
  inherited;
end;

procedure TGraphParser.ClearCommandPatterns;
begin
  if Assigned(FCommandSourcePattern) then
    FreeAndNil(FCommandSourcePattern);
  if Assigned(FCommandTargetPattern) then
    FreeAndNil(FCommandTargetPattern);
end;

procedure TGraphParser.Next;
begin
  FCurrent := FLexer.NextToken;
end;

function TGraphParser.GetTokenTextAndNext: string;
begin
  Result := FCurrent.Text;
  Next;
end;

procedure TGraphParser.Expect(AKind: TTokenKind);
begin
  if FCurrent.Kind <> AKind then
    raise Exception.CreateFmt('Syntax error: Expected %s but found "%s" at position %d', [GetEnumName(TypeInfo(TTokenKind), Ord(AKind)), FCurrent.Text, FCurrent.Position]);
  Next;
end;

function TGraphParser.ParseValueList: Variant;
var
  Values: TArray<Variant>;
  I: Integer;
begin
  // Format:  [value1, value2, value3]
  Expect(tkLBracket);
  var
  ValueList := TList<Variant>.Create;
  try
    if FCurrent.Kind <> tkRBracket then
    begin
      while True do
      begin
        // --- PARSING A VALUE ---
        case FCurrent.Kind of
          tkString:
            ValueList.Add(FCurrent.Text);
          tkNumber:
            ValueList.Add(StrToFloat(FCurrent.Text, TFormatSettings.Invariant));
          tkBoolean:
            ValueList.Add(SameText(FCurrent.Text, 'TRUE')); // Case insensitive
        else
          raise Exception.CreateFmt('Error: Invalid list value. Expected String, Number or Boolean, found "%s".', [FCurrent.Text]);
        end;
        Next;

        // --- SEPARATOR: COMMA ---
        if FCurrent.Kind = tkComma then
          Next
        else
          Break; // End of list
      end;
    end;
    Expect(tkRBracket);

    // --- CONVERSION TO VARIANT ARRAY (for compatibility) ---
    SetLength(Values, ValueList.Count);
    for I := 0 to ValueList.Count - 1 do
      Values[I] := ValueList[I];

    Result := Values;
  finally
    ValueList.Free;
  end;
end;

function TGraphParser.ParseNode(AQuery: TGraphMatchQuery): TMatchNodePattern;
var
  VarName, LblName: string;
begin
  Expect(tkLParen);
  VarName := '';
  LblName := '';

  // Optional variable: (p)
  if FCurrent.Kind = tkIdentifier then
    VarName := GetTokenTextAndNext;

  // Optional label: (:Person)
  if FCurrent.Kind = tkColon then
  begin
    Next;
    LblName := FCurrent.Text;
    Expect(tkIdentifier);
  end;

  // Binding or creation of Variable
  if (VarName <> '') and FNodeVariables.TryGetValue(VarName, Result) then
  begin
    // Reuse node if exists. Update label if provided.
    if (Result.NodeLabel = '') and (LblName <> '') then
      Result.NodeLabel := LblName;
  end
  else
  begin
    // New variable (or anonymous Node)
    Result := TMatchNodePattern.Create;
    Result.Variable := VarName;
    Result.NodeLabel := LblName;

    if VarName <> '' then
      FNodeVariables.Add(VarName, Result);

    AQuery.AddNodePattern(Result);
  end;

  // Optional properties: {name: 'Juan'}
  if FCurrent.Kind = tkLBrace then
    ParseProperties(Result.Properties);

  Expect(tkRParen);
end;

function TGraphParser.ParseEdge(out ADirection: TGraphDirection): TMatchEdgePattern;
var
  Left, Right: Boolean;
begin
  // Detect left arrow <-
  Left := (FCurrent.Kind = tkArrowLeft);
  if Left then
    Next
  else
    Expect(tkDash);

  Expect(tkLBracket);
  Result := TMatchEdgePattern.Create;

  // Optional edge variable [r]
  if FCurrent.Kind = tkIdentifier then
    Result.Variable := GetTokenTextAndNext;

  // Optional relationship type [:KNOWS]
  if FCurrent.Kind = tkColon then
  begin
    Next;
    Result.EdgeLabel := FCurrent.Text;
    Expect(tkIdentifier);
  end;

  // Edge properties {since: 2020}
  if FCurrent.Kind = tkLBrace then
    ParseProperties(Result.Properties);

  Expect(tkRBracket);

  // Detect right arrow ->
  Right := (FCurrent.Kind = tkArrowRight);
  if Right then
    Next
  else
    Expect(tkDash);

  // Determine direction
  if Left and Right then
    ADirection := gdBoth
  else if Left then
    ADirection := gdIncoming
  else if Right then
    ADirection := gdOutgoing
  else
    ADirection := gdBoth; // If only dashes -[]-
end;

procedure TGraphParser.ParseProperties(AProps: TDictionary<string, Variant>);
var
  Key: string;
begin
  Expect(tkLBrace);
  while FCurrent.Kind <> tkRBrace do
  begin
    Key := FCurrent.Text;
    Expect(tkIdentifier);
    Expect(tkColon);

    // --- Read the Property Value ---
    case FCurrent.Kind of
      tkString:
        AProps.Add(Key, GetTokenTextAndNext);
      tkNumber:
        AProps.Add(Key, StrToFloat(GetTokenTextAndNext, TFormatSettings.Invariant));
      tkBoolean:
        AProps.Add(Key, SameText(GetTokenTextAndNext, 'true')); // case insensitive
      tkNull:
        begin
          AProps.Add(Key, Null);
          Next;
        end;
    else
      raise Exception.CreateFmt('Error: Unsupported property value. Expected String, Number, Boolean or Null, found "%s".', [FCurrent.Text]);
    end;

    if FCurrent.Kind = tkComma then
      Next;
  end;
  Expect(tkRBrace);
end;

procedure TGraphParser.ParseWhereClause(AQuery: TGraphMatchQuery);
begin
  Expect(tkWhere);
  AQuery.WhereClause := ParseExpression;
end;

// --- EXPRESSION PARSER (WHERE) ---

function TGraphParser.ParseExpression: TGraphExpression;
var
  L: TGraphExpression;
begin
  L := ParseAndExpression;
  while FCurrent.Kind = tkOr do
  begin
    Next;
    L := TBinaryExpr.Create(L, opOr, ParseAndExpression);
  end;
  Result := L;
end;

procedure TGraphParser.ParseMatchClause(AQuery: TGraphMatchQuery);
var
  SrcNode, DstNode: TMatchNodePattern;
  Edge: TMatchEdgePattern;
  Dir: TGraphDirection;
begin
  // 1. Parse the initial node of the pattern: (a)
  SrcNode := ParseNode(AQuery);

  // 2. Loop for chained relationships.
  // Example: (a)-[r1]->(b)-[r2]->(c)
  // The loop continues while the current token indicates the start of an Edge
  // (a dash/hyphen '-' or a left arrow '<-').
  while FCurrent.Kind in [tkDash, tkArrowLeft] do
  begin
    // A. Parse the edge structure -[...]-, ->, <-
    // This returns the edge pattern object and the detected direction.
    Edge := ParseEdge(Dir);
    Edge.Direction := Dir; // Assign the direction to the pattern

    // B. Parse the next node in the chain
    DstNode := ParseNode(AQuery);

    // C. Create the match clause
    // A clause connects "SourceVariable + EdgePattern + DestinationVariable"
    // Note: TMatchClause takes ownership of the 'Edge' object's memory.
    AQuery.AddMatchClause(TMatchClause.Create(SrcNode.Variable, Edge, DstNode.Variable));

    // D. Advance the pivot:
    // The node we just found as destination (b) is converted
    // into the source for the next possible connection in the chain.
    SrcNode := DstNode;
  end;
end;

function TGraphParser.ParseAndExpression: TGraphExpression;
var
  L: TGraphExpression;
begin
  L := ParseComparison;
  while FCurrent.Kind = tkAnd do
  begin
    Next;
    L := TBinaryExpr.Create(L, opAnd, ParseComparison);
  end;
  Result := L;
end;

function TGraphParser.ParseComparison: TGraphExpression;
var
  L: TGraphExpression;
  Op: TBinaryOp;
  InList: Variant;
begin
  L := ParsePrimary;

  // --- IS Operators (IS NULL, IS NOT NULL) ---
  if FCurrent.Kind = tkIs then
  begin
    Next; // Consume IS
    if FCurrent.Kind = tkNot then
    begin
      Next; // Consume NOT
      Expect(tkNull);
      Result := TBinaryExpr.Create(L, opIsNotNull, nil); // Unary: Left is the property
    end
    else if FCurrent.Kind = tkNull then
    begin
      Next; // Consume NULL
      Result := TBinaryExpr.Create(L, opIsNull, nil); // Unary: Left is the property
    end
    else
      raise Exception.Create('Error: Expected NULL or NOT NULL after IS.');
    Exit;
  end;

  // --- NOT Operators (NOT IN) ---
  if FCurrent.Kind = tkNot then
  begin
    Next; // Consume NOT
    if FCurrent.Kind = tkIn then
    begin
      Next; // Consume IN
      InList := ParseValueList;
      Result := TBinaryExpr.Create(L, opNotIn, TLiteralExpr.Create(InList));
      Exit;
    end
    else
      raise Exception.Create('Syntax error: Invalid use of NOT. Expected NOT IN.');
  end;

  // --- Binary Operators (IN, LIKE, =, etc.) ---
  if FCurrent.Kind in [tkEqual, tkNotEqual, tkGreater, tkGreaterEqual, tkLess, tkLessEqual, tkContains, tkLike, tkILike, tkIn] then
  begin
    // Determine the operator
    case FCurrent.Kind of
      tkEqual:
        Op := opEqual;
      tkNotEqual:
        Op := opNotEqual;
      tkGreater:
        Op := opGreater;
      tkGreaterEqual:
        Op := opGreaterEqual;
      tkLess:
        Op := opLess;
      tkLessEqual:
        Op := opLessEqual;
      tkContains:
        Op := opContains; // already in the Lexer
      tkLike:
        Op := opLike;
      tkILike:
        Op := opILike;
      tkIn:
        Op := opIn;
    else
      Op := opEqual; // Default (should never happen)
    end;
    Next; // Consume the operator

    // For IN, the right-hand side is a list
    if Op = opIn then
    begin
      InList := ParseValueList;
      Result := TBinaryExpr.Create(L, Op, TLiteralExpr.Create(InList));
    end
    else
      {
        Result := TBinaryExpr.Create(L, Op, ParsePrimary); // <-- Original
        Result := TBinaryExpr.Create(L, Op, ParseExpression); // <-- New version
      }
      Result := TBinaryExpr.Create(L, Op, ParsePrimary);
  end
  else
    Result := L;
end;

function TGraphParser.ParsePrimary: TGraphExpression;
var
  V, P: string;
  Negate: Boolean;
begin
  Negate := False;
  case FCurrent.Kind of
    tkLParen: // grouping: (expression)
      begin
        Next;
        Result := ParseExpression;
        Expect(tkRParen);
      end;
    // Property access (e.g.: n.name)
    tkIdentifier:
      begin
        // Variable (n)
        V := GetTokenTextAndNext; // Consume variable
        Expect(tkDot); // Consume dot
        P := FCurrent.Text; // Name of the property (name)
        Expect(tkIdentifier); // Consume property name
        Result := TPropertyExpr.Create(V, P);
      end;
    // Literals (strings, numbers, booleans, null)
    tkString:
      Result := TLiteralExpr.Create(GetTokenTextAndNext);
    tkBoolean:
      Result := TLiteralExpr.Create(SameText(GetTokenTextAndNext, 'true'));

    tkNumber:
      begin
        // Apply negative if present
        if Negate then
          Result := TLiteralExpr.Create(-StrToFloat(GetTokenTextAndNext, TFormatSettings.Invariant))
        else
          Result := TLiteralExpr.Create(StrToFloat(GetTokenTextAndNext, TFormatSettings.Invariant));
      end;

    tkNull:
      begin
        Next;
        Result := TLiteralExpr.Create(Null);
      end;
  else
    raise Exception.CreateFmt('Error: Expected a valid expression in WHERE. Found "%s".', [FCurrent.Text]);
  end;
end;

Procedure TGraphParser.ParseReturnClause(AQuery: TGraphMatchQuery);
begin
  Expect(tkReturn);

  // Verify that there is at least one element
  if FCurrent.Kind = tkEOF then
    raise Exception.Create('Error: Expected an expression after RETURN.');

  while True do
  begin
    // --- CASE A: Aggregate functions (COUNT, SUM, AVG) ---
    if FCurrent.Kind in [tkCount, tkSum, tkAvg] then
    begin
      Next; // Consume function
      Expect(tkLParen);

      // argument may be variable (p), property (p.value) or * (all)
      if FCurrent.Kind = tkIdentifier then
      begin
        Next; // Consume identifier (p)
        if FCurrent.Kind = tkDot then
        begin
          Next; // Consume the dot
          Expect(tkIdentifier); // Consume property
        end;
      end
      else if FCurrent.Text = '*' then
        Next // Consume *
      else
        raise Exception.Create('Error: Expected a variable or property inside the function.');

      Expect(tkRParen);
    end
    // --- CASE B: Simple Identifier or Property Access ---
    else if FCurrent.Kind = tkIdentifier then
    begin
      Next; // Consume the identifier

      if FCurrent.Kind = tkDot then
      begin
        Next; // Consume the dot
        Expect(tkIdentifier); // Consume the property
      end;
    end
    // --- CASE C: Literals (String, Number, Boolean, Null) ---
    else if FCurrent.Kind in [tkString, tkNumber, tkBoolean, tkNull] then
    begin
      Next;
    end
    else
      raise Exception.CreateFmt('Syntax error: Invalid return expression "%s".', [FCurrent.Text]);

    // --- SUPPORT FOR "AS" ALIAS ---
    if (FCurrent.Kind = tkIdentifier) and SameText(FCurrent.Text, 'AS') then
    begin
      Next; // Consume 'AS'
      Expect(tkIdentifier); // Consume alias
    end;

    // --- SEPARATOR: Comma ',' ---
    if FCurrent.Kind = tkComma then
      Next // Consume comma
    else
      Break;
  end; // End of WHILE
end;

function TGraphParser.Parse: TGraphMatchQuery;
var
  TempQuery: TGraphMatchQuery;
  Src, Dst: TMatchNodePattern;
begin
  Result := nil;
  FCommandType := cmdNone;
  ClearCommandPatterns;

  // 1. Introspection commands (SHOW...)
  if FCurrent.Kind = tkShow then
  begin
    Next; // Consume 'SHOW'
    if FCurrent.Kind = tkLabels then
      FCommandType := cmdShowLabels
      // etc.
    else if FCurrent.Kind = tkEdges then
      FCommandType := cmdShowEdges
    else
      raise Exception.Create('Syntax error: Expected LABELS or EDGES after SHOW.');
    Next; // Advance after the show command
    Exit;
  end;

  // 2. Graph Algorithm Commands
  if FCurrent.Kind = tkShortest then
  begin
    Next; // Consume 'SHORTEST'
    Expect(tkPath);
    FCommandType := cmdShortestPath;
    TempQuery := TGraphMatchQuery.Create;
    try
      Src := ParseNode(TempQuery);
      TempQuery.NodePatterns.Extract(Src);
      FCommandSourcePattern := Src;
      Expect(tkTo);
      Dst := ParseNode(TempQuery);
      TempQuery.NodePatterns.Extract(Dst);
      FCommandTargetPattern := Dst;
    finally
      TempQuery.Free;
    end;
    Exit;
  end;
  // ... (complete with the rest of commands like get centrality...)

  if FCurrent.Kind = tkGet then
  begin
    Next;
    if FCurrent.Kind = tkCentrality then
    begin
      Next;
      FCommandType := cmdCentrality;
      TempQuery := TGraphMatchQuery.Create;
      try
        Src := ParseNode(TempQuery);
        TempQuery.NodePatterns.Extract(Src);
        FCommandSourcePattern := Src;
      finally
        TempQuery.Free;
      end;
    end
    else if FCurrent.Kind = tkDegrees then
    begin
      Next;
      FCommandType := cmdDegrees;
      Expect(tkTop);
      FCommandLimit := StrToIntDef(GetTokenTextAndNext, 10);
    end
    else
      raise Exception.Create('Syntax error: Expected CENTRALITY or DEGREES after GET.');
    Exit;
  end;

  // 3. Standard MATCH queries (The most complex)
  Result := TGraphMatchQuery.Create;
  try
    if FCurrent.Kind = tkMatch then
      Next; // Consume MATCH

    // --- PARSING MATCH clauses (a)-[]->(b), (c)-[]->(d) ---
    ParseMatchClause(Result);
    while FCurrent.Kind = tkComma do // Support for multiple patterns separated by comma
    begin
      Next; // Consume the comma
      ParseMatchClause(Result);
    end;

    // 4. DEPTH (Optional)
    if FCurrent.Kind = tkDepth then
    begin
      Next;
      if FCurrent.Kind = tkNumber then
        Result.Depth := Trunc(StrToFloat(GetTokenTextAndNext, TFormatSettings.Invariant))
      else
        raise Exception.Create('Error: Expected a number after DEPTH.');
    end;

    // 5. WHERE (Optional)
    if FCurrent.Kind = tkWhere then
      ParseWhereClause(Result);

    // 6. RETURN (Optional)
    if FCurrent.Kind = tkReturn then
      ParseReturnClause(Result);

    // 7. EOF verification
    if FCurrent.Kind <> tkEOF then
      raise Exception.CreateFmt('Error: Incorrect syntax. Expected EOF, found "%s" at position %d', [FCurrent.Text, FCurrent.Position]);
  except
    Result.Free;
    raise;
  end;
end;

end.
