unit uMakerAi.RAG.Vectors.VQL;


interface

uses
  System.SysUtils, System.Variants, System.Character, System.TypInfo, System.Generics.Collections,
  uMakerAi.RAG.MetaData;

type
  // Token types
  TVGQLTokenKind = (
    // Control
    tkEOF,

    tkStartsWith, tkEndsWith, tkLike, tkILike, tkIn, tkBetween,
    tkIs, tkNot, tkExists, tkExistsAny, tkExistsAll,

    // Literals
    tkIdentifier, tkString, tkNumber, tkBoolean, tkNull,

    // Delimiters
    tkLParen, tkRParen, tkColon, tkComma, tkDot,

    // Comparison operators
    tkEqual, tkNotEqual, tkGreater, tkGreaterEqual, tkLess, tkLessEqual, tkContains,

    // Logical operators
    tkAnd, tkOr,

    // Reserved words / clauses
    tkMatch, tkSearch, tkUsing, tkWhere, tkRerank, tkThreshold, tkOptimize, tkReturn,
    tkWith, tkLimit, tkHybrid, tkEmbeddings, tkBm25, tkWeights, tkLanguage, tkFusion,
    tkRrf, tkWeighted, tkRegenerate, tkGlobal, tkSemantic, tkLexical,
    tkReorder, tkAbc, tkText, tkMetadata, tkScore,

    // --- NEW TOKENS v2 ---
    tkOffset,    // OFFSET n — pagination
    tkDistinct,  // DISTINCT ON field — deduplication
    tkOn,        // ON (part of DISTINCT ON / ORDER BY)
    tkOrder,     // ORDER
    tkBy,        // BY (part of ORDER BY)
    tkAsc,       // ASC — ascending direction
    tkDesc,      // DESC — descending direction
    tkExplain,   // EXPLAIN — show plan without executing
    tkId,        // ID — extended return field
    tkRank,      // RANK — extended return field
    tkMmr,       // MMR — optimization mode
    tkModel,     // MODEL — extended return field
    tkTop        // TOP — alias for LIMIT (reserved)
  );

  TVGQLToken = record
    Kind: TVGQLTokenKind;
    Text: string;
    Position: Integer;
  end;

  TVGQLLexer = class
  private
    FText: string;
    FPos: Integer;

    function IsEOF: Boolean;
    function Peek: Char;
    function Next: Char;
    procedure SkipWhitespace;

    function ReadIdentifier: TVGQLToken;
    function ReadString: TVGQLToken;
    function ReadNumber: TVGQLToken;

  public
    constructor Create(const AText: string);
    function NextToken: TVGQLToken;
  end;

  //==================================
  //============ AST =================
  //==================================

  // ===== BASE =====
  TASTNode = class
  private
    FPosition: Integer;
  public
    constructor Create(APosition: Integer = 0); virtual;
    property Position: Integer read FPosition;
  end;

  // ===== EXPRESSIONS =====
  TExpression = class(TASTNode);

  TLiteralType = (ltString, ltNumber, ltBoolean, ltNull);

  TLiteralExpression = class(TExpression)
  private
    FLiteralType: TLiteralType;
    FValue: string;
  public
    property LiteralType: TLiteralType read FLiteralType write FLiteralType;
    property Value: string read FValue write FValue;
  end;

  TIdentifierExpression = class(TExpression)
  private
    FName: string;
  public
    property Name: string read FName write FName;
  end;

TBinaryOperator = (
    boAnd, boOr,
    boEqual, boNotEqual,
    boGreater, boGreaterEqual,
    boLess, boLessEqual,
    boContains,
    // --- NEW FOR COORDINATION WITH LEXER AND METADATA ---
    boLike, boILike,
    boIn, boNotIn,
    boBetween,
    boStartsWith, boEndsWith,
    boIsNull, boIsNotNull,
    boExists, boExistsAny, boExistsAll
  );

  TBinaryExpression = class(TExpression)
  private
    FLeft: TExpression;
    FOperator: TBinaryOperator;
    FRight: TExpression;
  public
    destructor Destroy; override;
    property Left: TExpression read FLeft write FLeft;
    property Operator: TBinaryOperator read FOperator write FOperator;
    property Right: TExpression read FRight write FRight;
  end;


  TInExpression = class(TExpression)
  private
    FLeft: TExpression;
    FValues: TList<TExpression>;
    FIsNot: Boolean;
  public
    constructor Create(APosition: Integer = 0); override;
    destructor Destroy; override;
    property Left: TExpression read FLeft write FLeft;
    property Values: TList<TExpression> read FValues;
    property IsNot: Boolean read FIsNot write FIsNot; // True if "NOT IN"
  end;

  // Expression for: field BETWEEN min AND max
  TBetweenExpression = class(TExpression)
  private
    FLeft: TExpression;
    FMin: TExpression;
    FMax: TExpression;
  public
    destructor Destroy; override;
    property Left: TExpression read FLeft write FLeft;
    property Min: TExpression read FMin write FMin;
    property Max: TExpression read FMax write FMax;
  end;

  // ===== CLAUSES =====
  TMatchClause = class(TASTNode)
  private
    FEntityName: string;
    FAlias: string;
  public
    property EntityName: string read FEntityName write FEntityName;
    property Alias: string read FAlias write FAlias;
  end;

  TSearchClause = class(TASTNode)
  private
    FQueryText: string;
  public
    property QueryText: string read FQueryText write FQueryText;
  end;

  TSearchMode = (smHybrid, smEmbeddings, smBM25);
  TFusionMode = (fmWeighted, fmRRF);


  TUsingClause = class(TASTNode)
  private
    FMode: TSearchMode;
    FSemanticWeight: Double;
    FLexicalWeight: Double;
    FFusion: string;
    FLanguage: string;
  public
    constructor Create(APosition: Integer = 0); override;
    property Mode: TSearchMode read FMode write FMode;
    property SemanticWeight: Double read FSemanticWeight write FSemanticWeight;
    property LexicalWeight: Double read FLexicalWeight write FLexicalWeight;
    property Fusion: string read FFusion write FFusion;
    property Language: string read FLanguage write FLanguage;
  end;

  TWhereClause = class(TASTNode)
  private
    FExpression: TExpression;
  public
    destructor Destroy; override;
    property Expression: TExpression read FExpression write FExpression;
  end;

  TRerankClause = class(TASTNode)
  private
    FQuery: string;
    FRegenerate: Boolean;
  public
    property Query: string read FQuery write FQuery;
    property Regenerate: Boolean read FRegenerate write FRegenerate;
  end;

  TThresholdScope = (tsGlobal, tsSemantic, tsLexical);

  TThresholdClause = class(TASTNode)
  private
    FScope: TThresholdScope;
    FValue: Double;
  public
    property Scope: TThresholdScope read FScope write FScope;
    property Value: Double read FValue write FValue;
  end;

  TOptimizeMode = (omNone, omReorderABC, omMMR);

  TOptimizeClause = class(TASTNode)
  private
    FMode: TOptimizeMode;
    FLambda: Double;
  public
    constructor Create(APosition: Integer = 0); override;
    property Mode: TOptimizeMode read FMode write FMode;
    // Lambda parameter for MMR (0..1): higher = more relevant, lower = more diverse
    property Lambda: Double read FLambda write FLambda;
  end;

  TReturnField = (rfText, rfMetadata, rfScore, rfId, rfRank, rfModel);

  TReturnClause = class(TASTNode)
  private
    FFields: TList<TReturnField>;
  public
    constructor Create(APosition: Integer = 0); override;
    destructor Destroy; override;
    property Fields: TList<TReturnField> read FFields;
  end;

  // --- NEW CLAUSES v2 ---

  // Direction for ORDER BY fields
  TOrderDirection = (odAsc, odDesc);

  // A single field specification in ORDER BY
  TOrderByField = record
    FieldName: string;
    Direction: TOrderDirection;
  end;

  TDistinctClause = class(TASTNode)
  private
    FField: string;
  public
    property Field: string read FField write FField;
  end;

  TOrderByClause = class(TASTNode)
  private
    FFields: TList<TOrderByField>;
  public
    constructor Create(APosition: Integer = 0); override;
    destructor Destroy; override;
    property Fields: TList<TOrderByField> read FFields;
  end;

  // ===== MAIN QUERY =====
  TVGQLQuery = class(TASTNode)
  private
    FMatch: TMatchClause;
    FSearch: TSearchClause;
    FUsing: TUsingClause;
    FWhere: TWhereClause;
    FRerank: TRerankClause;
    FThreshold: TThresholdClause;
    FOptimize: TOptimizeClause;
    FReturn: TReturnClause;
    FLimit: Integer;
    // --- New v2 fields ---
    FOffset: Integer;
    FDistinct: TDistinctClause;
    FOrderBy: TOrderByClause;
    FExplain: Boolean;
  public
    constructor Create; reintroduce;
    destructor Destroy; override;

    property Match: TMatchClause read FMatch write FMatch;
    property Search: TSearchClause read FSearch write FSearch;
    property UsingClause: TUsingClause read FUsing write FUsing;
    property WhereClause: TWhereClause read FWhere write FWhere;
    property RerankClause: TRerankClause read FRerank write FRerank;
    property ThresholdClause: TThresholdClause read FThreshold write FThreshold;
    property OptimizeClause: TOptimizeClause read FOptimize write FOptimize;
    property ReturnClause: TReturnClause read FReturn write FReturn;
    property Limit: Integer read FLimit write FLimit;
    // New v2 properties
    property Offset: Integer read FOffset write FOffset;
    property DistinctClause: TDistinctClause read FDistinct write FDistinct;
    property OrderByClause: TOrderByClause read FOrderBy write FOrderBy;
    property Explain: Boolean read FExplain write FExplain;
  end;


  //=====================================
  //============ PARSER =================
  //=====================================


  EVGQLParserError = class(Exception);

  TVGQLParser = class
  private
    FLexer: TVGQLLexer;
    FCurrent: TVGQLToken;

    procedure Next;
    procedure Expect(AKind: TVGQLTokenKind; const AMsg: string = '');
    function Check(AKind: TVGQLTokenKind): Boolean;
    function Match(AKind: TVGQLTokenKind): Boolean;

    // Clause parsers
    function ParseMatch: TMatchClause;
    function ParseSearch: TSearchClause;
    function ParseUsing: TUsingClause;
    function ParseWhere: TWhereClause;
    function ParseRerank: TRerankClause;
    function ParseThreshold: TThresholdClause;
    function ParseOptimize: TOptimizeClause;
    function ParseReturn: TReturnClause;
    // New v2 parsers
    function ParseDistinct: TDistinctClause;
    function ParseOrderBy: TOrderByClause;

    // Expression parser (precedence climbing)
    function ParseExpression: TExpression;
    function ParseOr: TExpression;
    function ParseAnd: TExpression;
    function ParseComparison: TExpression;
    function ParsePrimary: TExpression;
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    function Parse: TVGQLQuery;
  end;


  //======================================
  //============ REQUEST =================
  //======================================


  TVGQLRequest = class
  public
    // MATCH
    Entity: string;
    ALabel: string;

    // SEARCH
    Query: string;

    // USING
    Mode: TSearchMode;
    WeightSemantic: Double;
    WeightLexical: Double;
    Language: string;
    Fusion: TFusionMode;
    // Marks if the clause was written in VQL. Without this we cannot distinguish
    // an explicit "FUSION WEIGHTED" from the default value, and the
    // request executor does not know if it can impose its own default.
    FusionSpecified: Boolean;
    LanguageSpecified: Boolean;

    // WHERE
    // CHANGE: Now we use native Criteria, not plain MetaData
    Filter: TAiFilterCriteria;

    // RERANK
    RerankQuery: string;
    RerankRegenerate: Boolean;

    // THRESHOLD
    MinGlobal: Double;
    MinSemantic: Double;
    MinLexical: Double;

    // OPTIMIZE
    UseReorderABC: Boolean;
    UseMMR: Boolean;
    MmrLambda: Double;

    // RETURN
    Limit: Integer;
    IncludeMetadata: Boolean;
    IncludeScore: Boolean;
    // New return fields v2
    IncludeId: Boolean;
    IncludeRank: Boolean;
    IncludeModel: Boolean;

    // NEW v2 fields
    Offset: Integer;
    DistinctField: string;
    OrderByFields: TList<TOrderByField>;
    Explain: Boolean;

    constructor Create;
    destructor Destroy; override;
  end;

  //=======================================
  //============ COMPILER =================
  //=======================================

  EVGQLTranslationError = class(Exception);

  { The Compiler transforms the AST (Syntax) into a TVGQLRequest (Execution) }
  TVGQLCompiler = class
  private
    FRequest: TVGQLRequest;

    // Clause translation methods
    procedure TranslateMatch(AClause: TMatchClause);
    procedure TranslateSearch(AClause: TSearchClause);
    procedure TranslateUsing(AClause: TUsingClause);
    procedure TranslateWhere(AClause: TWhereClause);
    procedure TranslateRerank(AClause: TRerankClause);
    procedure TranslateThreshold(AClause: TThresholdClause);
    procedure TranslateOptimize(AClause: TOptimizeClause);
    procedure TranslateReturn(AClause: TReturnClause);
    // New v2 translators
    procedure TranslateDistinct(AClause: TDistinctClause);
    procedure TranslateOrderBy(AClause: TOrderByClause);

    // Expression translation engine (Recursive)
    procedure BuildFilter(AExpr: TExpression; ACriteria: TAiFilterCriteria);
    function GetLiteralValue(AExpr: TExpression): Variant;

  public
    function Translate(AQuery: TVGQLQuery): TVGQLRequest;
  end;




implementation

{ TVGQLLexer }

constructor TVGQLLexer.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
end;

function TVGQLLexer.IsEOF: Boolean;
begin
  Result := FPos > Length(FText);
end;

function TVGQLLexer.Peek: Char;
begin
  if IsEOF then
    Result := #0
  else
    Result := FText[FPos];
end;

function TVGQLLexer.Next: Char;
begin
  Result := Peek;
  Inc(FPos);
end;

procedure TVGQLLexer.SkipWhitespace;
begin
  while (not IsEOF) and Peek.IsWhiteSpace do
    Next;
end;

function TVGQLLexer.ReadString: TVGQLToken;
var
  Quote: Char;
  Start: Integer;
begin
  Quote := Next; // ' or "
  Start := FPos;
  while (not IsEOF) and (Peek <> Quote) do
    Next;

  Result.Kind := tkString;
  Result.Text := Copy(FText, Start, FPos - Start);
  Result.Position := Start - 1;

  if not IsEOF then
    Next; // close quote
end;

function TVGQLLexer.ReadNumber: TVGQLToken;
var
  Start: Integer;
begin
  Start := FPos;
  while (not IsEOF) and (Peek.IsDigit or (Peek = '.')) do
    Next;

  Result.Kind := tkNumber;
  Result.Text := Copy(FText, Start, FPos - Start);
  Result.Position := Start;
end;

function TVGQLLexer.ReadIdentifier: TVGQLToken;
var
  Start: Integer;
  S, U: string;
begin
  Start := FPos;
  // Allow letters, digits and underscores (typical for identifiers/keys)
  while (not IsEOF) and (Peek.IsLetterOrDigit or (Peek = '_')) do
    Next;

  S := Copy(FText, Start, FPos - Start);
  U := S.ToUpper; // For case-insensitive comparison

  Result.Text := S;
  Result.Position := Start;

  // --- MAIN CLAUSES ---
  if U = 'MATCH' then Result.Kind := tkMatch
  else if U = 'SEARCH' then Result.Kind := tkSearch
  else if U = 'USING' then Result.Kind := tkUsing
  else if U = 'WHERE' then Result.Kind := tkWhere
  else if U = 'RERANK' then Result.Kind := tkRerank
  else if U = 'RETURN' then Result.Kind := tkReturn
  else if U = 'WITH' then Result.Kind := tkWith
  else if U = 'LIMIT' then Result.Kind := tkLimit
  else if U = 'OPTIMIZE' then Result.Kind := tkOptimize
  else if U = 'THRESHOLD' then Result.Kind := tkThreshold

  // --- NEW CLAUSES v2 ---
  else if U = 'OFFSET' then Result.Kind := tkOffset
  else if U = 'DISTINCT' then Result.Kind := tkDistinct
  else if U = 'ON' then Result.Kind := tkOn
  else if U = 'ORDER' then Result.Kind := tkOrder
  else if U = 'BY' then Result.Kind := tkBy
  else if U = 'ASC' then Result.Kind := tkAsc
  else if U = 'DESC' then Result.Kind := tkDesc
  else if U = 'EXPLAIN' then Result.Kind := tkExplain
  else if U = 'MMR' then Result.Kind := tkMmr
  else if U = 'TOP' then Result.Kind := tkTop

  // --- LOGICAL OPERATORS ---
  else if U = 'AND' then Result.Kind := tkAnd
  else if U = 'OR' then Result.Kind := tkOr
  else if U = 'NOT' then Result.Kind := tkNot

  // --- FILTER OPERATORS (Synchronized with MetaData) ---
  else if U = 'CONTAINS' then Result.Kind := tkContains
  else if U = 'LIKE' then Result.Kind := tkLike
  else if U = 'ILIKE' then Result.Kind := tkILike
  else if U = 'IN' then Result.Kind := tkIn
  else if U = 'BETWEEN' then Result.Kind := tkBetween
  else if U = 'STARTS_WITH' then Result.Kind := tkStartsWith
  else if U = 'ENDS_WITH' then Result.Kind := tkEndsWith
  else if U = 'IS' then Result.Kind := tkIs
  else if U = 'EXISTS' then Result.Kind := tkExists
  else if U = 'EXISTS_ANY' then Result.Kind := tkExistsAny
  else if U = 'EXISTS_ALL' then Result.Kind := tkExistsAll

  // --- SEARCH / RAG CONFIGURATION ---
  else if U = 'HYBRID' then Result.Kind := tkHybrid
  else if U = 'EMBEDDINGS' then Result.Kind := tkEmbeddings
  else if U = 'BM25' then Result.Kind := tkBm25
  else if U = 'WEIGHTS' then Result.Kind := tkWeights
  else if U = 'LANGUAGE' then Result.Kind := tkLanguage
  else if U = 'FUSION' then Result.Kind := tkFusion
  else if U = 'RRF' then Result.Kind := tkRrf
  else if U = 'WEIGHTED' then Result.Kind := tkWeighted

  // --- MODES AND STRATEGIES ---
  else if U = 'REGENERATE' then Result.Kind := tkRegenerate
  else if U = 'GLOBAL' then Result.Kind := tkGlobal
  else if U = 'SEMANTIC' then Result.Kind := tkSemantic
  else if U = 'LEXICAL' then Result.Kind := tkLexical
  else if U = 'REORDER' then Result.Kind := tkReorder
  else if U = 'ABC' then Result.Kind := tkAbc

  // --- RETURN FIELDS ---
  else if U = 'TEXT' then Result.Kind := tkText
  else if U = 'METADATA' then Result.Kind := tkMetadata
  else if U = 'SCORE' then Result.Kind := tkScore
  // New return fields v2
  else if U = 'ID' then Result.Kind := tkId
  else if U = 'RANK' then Result.Kind := tkRank
  else if U = 'MODEL' then Result.Kind := tkModel

  // --- BOOL / NULL LITERALS ---
  else if (U = 'TRUE') or (U = 'FALSE') then Result.Kind := tkBoolean
  else if U = 'NULL' then Result.Kind := tkNull

  // --- IF NOT A RESERVED WORD, IT IS AN IDENTIFIER (Field name, etc.) ---
  else
    Result.Kind := tkIdentifier;
end;

function TVGQLLexer.NextToken: TVGQLToken;
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

    '(':
      Begin
        Next;
        Result.Kind := tkLParen;
        Result.Text := '('
      end;

    ')':
      Begin
        Next;
        Result.Kind := tkRParen;
        Result.Text := ')'
      end;
    ':':
      Begin
        Next;
        Result.Kind := tkColon;
        Result.Text := ':'
      end;
    ',':
      Begin
        Next;
        Result.Kind := tkComma;
        Result.Text := ','
      end;
    '.':
      Begin
        Next;
        Result.Kind := tkDot;
        Result.Text := '.'
      end;
    '=':
      Begin
        Next;
        Result.Kind := tkEqual;
        Result.Text := '='
      end;

    '<':
      begin
        Next;
        if Peek = '>' then
        begin
          Next;
          Result.Kind := tkNotEqual;
          Result.Text := '<>';
        end
        else if Peek = '=' then
        begin
          Next;
          Result.Kind := tkLessEqual;
          Result.Text := '<=';
        end
        else
          Result.Kind := tkLess;
        Result.Text := '<';
      end;
    '>':
      begin
        Next;
        if Peek = '=' then
        begin
          Next;
          Result.Kind := tkGreaterEqual;
          Result.Text := '>=';
        end
        else
          Result.Kind := tkGreater;
        Result.Text := '>';
      end;
    '''', '"':
      Exit(ReadString);
    '0' .. '9':
      Exit(ReadNumber);
  else
    if Peek.IsLetter or (Peek = '_') then
      Exit(ReadIdentifier)
    else
      raise Exception.CreateFmt('Lexical error: unexpected character "%s" at position %d', [Peek, FPos]);
  end;
end;



  //==================================
  //============ AST =================
  //==================================


{ TASTNode }

constructor TASTNode.Create(APosition: Integer);
begin
  inherited Create;
  FPosition := APosition;
end;

{ TBinaryExpression }

destructor TBinaryExpression.Destroy;
begin
  FLeft.Free;
  FRight.Free;
  inherited;
end;

{ TUsingClause }

constructor TUsingClause.Create(APosition: Integer);
begin
  inherited Create(APosition);
  FSemanticWeight := 0.5;
  FLexicalWeight := 0.5;
  FFusion := '';
  FLanguage := '';
end;

{ TWhereClause }

destructor TWhereClause.Destroy;
begin
  FExpression.Free;
  inherited;
end;

{ TOptimizeClause }

constructor TOptimizeClause.Create(APosition: Integer);
begin
  inherited Create(APosition);
  FMode := omNone;
  FLambda := 0.7;
end;

{ TReturnClause }

constructor TReturnClause.Create(APosition: Integer);
begin
  inherited Create(APosition);
  FFields := TList<TReturnField>.Create;
end;

destructor TReturnClause.Destroy;
begin
  FFields.Free;
  inherited;
end;

{ TOrderByClause }

constructor TOrderByClause.Create(APosition: Integer);
begin
  inherited Create(APosition);
  FFields := TList<TOrderByField>.Create;
end;

destructor TOrderByClause.Destroy;
begin
  FFields.Free;
  inherited;
end;

{ TVGQLQuery }

constructor TVGQLQuery.Create;
begin
  inherited Create(0);
  FMatch := nil;
  FSearch := nil;
  FUsing := nil;
  FWhere := nil;
  FRerank := nil;
  FThreshold := nil;
  FOptimize := nil;
  FReturn := nil;
  FLimit := -1;
  FOffset := 0;
  FDistinct := nil;
  FOrderBy := nil;
  FExplain := False;
end;

destructor TVGQLQuery.Destroy;
begin
  FMatch.Free;
  FSearch.Free;
  FUsing.Free;
  FWhere.Free;
  FRerank.Free;
  FThreshold.Free;
  FOptimize.Free;
  FReturn.Free;
  FDistinct.Free;
  FOrderBy.Free;
  inherited;
end;

{ TInExpression }

constructor TInExpression.Create(APosition: Integer);
begin
  inherited Create(APosition);
  FValues := TList<TExpression>.Create;
  FIsNot := False;
end;

destructor TInExpression.Destroy;
var
  Expr: TExpression;
begin
  FLeft.Free;
  // Free each expression in the values list
  for Expr in FValues do
    Expr.Free;
  FValues.Free;
  inherited;
end;

{ TBetweenExpression }

destructor TBetweenExpression.Destroy;
begin
  FLeft.Free;
  FMin.Free;
  FMax.Free;
  inherited;
end;

  //=====================================
  //============ PARSER =================
  //=====================================

{ TVGQLParser }

constructor TVGQLParser.Create(const AText: string);
begin
  inherited Create;
  FLexer := TVGQLLexer.Create(AText);
  Next; // Load first token
end;

destructor TVGQLParser.Destroy;
begin
  FLexer.Free;
  inherited;
end;

procedure TVGQLParser.Next;
begin
  FCurrent := FLexer.NextToken;
end;

function TVGQLParser.Check(AKind: TVGQLTokenKind): Boolean;
begin
  Result := FCurrent.Kind = AKind;
end;

function TVGQLParser.Match(AKind: TVGQLTokenKind): Boolean;
begin
  Result := Check(AKind);
  if Result then
    Next;
end;

procedure TVGQLParser.Expect(AKind: TVGQLTokenKind; const AMsg: string);
var
  ErrorMsg: string;
begin
  if not Check(AKind) then
  begin
    if AMsg <> '' then
      ErrorMsg := Format('Line %d: expected %s (%s)', [FCurrent.Position, GetEnumName(TypeInfo(TVGQLTokenKind), Ord(AKind)), AMsg])
    else
      ErrorMsg := Format('Line %d: expected %s', [FCurrent.Position, GetEnumName(TypeInfo(TVGQLTokenKind), Ord(AKind))]);
    raise EVGQLParserError.Create(ErrorMsg);
  end;
  Next;
end;

{ ===== MAIN PARSER ===== }

function TVGQLParser.Parse: TVGQLQuery;
begin
  Result := TVGQLQuery.Create;
  try
    // EXPLAIN (optional, must be first)
    if Match(tkExplain) then
      Result.Explain := True;

    // MATCH (optional)
    if Check(tkMatch) then
      Result.Match := ParseMatch;

    // SEARCH (mandatory)
    if Check(tkSearch) then
      Result.Search := ParseSearch
    else
      raise EVGQLParserError.Create('SEARCH clause required');

    // USING (optional)
    if Check(tkUsing) then
      Result.UsingClause := ParseUsing;

    // WHERE (optional)
    if Check(tkWhere) then
      Result.WhereClause := ParseWhere;

    // RERANK (optional)
    if Check(tkRerank) then
      Result.RerankClause := ParseRerank;

    // THRESHOLD (optional)
    if Check(tkThreshold) then
      Result.ThresholdClause := ParseThreshold;

    // OPTIMIZE (optional)
    if Check(tkOptimize) then
      Result.OptimizeClause := ParseOptimize;

    // DISTINCT ON field (optional)
    if Check(tkDistinct) then
      Result.DistinctClause := ParseDistinct;

    // ORDER BY (optional)
    if Check(tkOrder) then
      Result.OrderByClause := ParseOrderBy;

    // RETURN (optional)
    if Check(tkReturn) then
      Result.ReturnClause := ParseReturn;

    // LIMIT (optional)
    if Match(tkLimit) then
    begin
      // After Match(tkLimit), we have already consumed the token "LIMIT"
      // Now FCurrent points to the supposed number
      if Check(tkNumber) then
      begin
        Result.Limit := StrToInt(FCurrent.Text);
        Next; // Now consume the number to move to the next token
      end
      else
        raise EVGQLParserError.Create('A numeric value is required for the LIMIT clause');
    end;

    // OFFSET (optional) — pagination
    if Match(tkOffset) then
    begin
      if Check(tkNumber) then
      begin
        Result.Offset := StrToInt(FCurrent.Text);
        Next;
      end
      else
        raise EVGQLParserError.Create('A numeric value is required for the OFFSET clause');
    end;

    // Verify end of query
    Expect(tkEOF, 'end of query');
  except
    Result.Free;
    raise;
  end;
end;

{ ===== MATCH ===== }

function TVGQLParser.ParseMatch: TMatchClause;
begin
  Result := TMatchClause.Create(FCurrent.Position);
  try
    Next; // consume MATCH
    Expect(tkLParen, '(');

    if Check(tkIdentifier) then
    begin
      Result.EntityName := FCurrent.Text; // Capture text BEFORE advancing
      Next;
    end
    else
      Expect(tkIdentifier, 'entity name');

    // Optional alias
    if Match(tkColon) then
    begin
      if Check(tkIdentifier) then
      begin
        Result.Alias := FCurrent.Text;
        Next;
      end
      else
        Expect(tkIdentifier, 'alias');
    end;

    Expect(tkRParen, ')');
  except
    Result.Free;
    raise;
  end;
end;

{ ===== SEARCH ===== }

function TVGQLParser.ParseSearch: TSearchClause;
begin
  Result := TSearchClause.Create(FCurrent.Position);
  try
    Next; // consume SEARCH
    if Check(tkString) then
    begin
      Result.QueryText := FCurrent.Text; // Capture the string value
      Next; // Advance
    end
    else
      Expect(tkString, 'search text');
  except
    Result.Free;
    raise;
  end;
end;

{ ===== USING ===== }

function TVGQLParser.ParseUsing: TUsingClause;
begin
  Result := TUsingClause.Create(FCurrent.Position);
  try
    Next; // consume USING

    case FCurrent.Kind of
      tkHybrid:
        Result.Mode := smHybrid;
      tkEmbeddings:
        Result.Mode := smEmbeddings;
      tkBm25:
        Result.Mode := smBM25;
    else
      raise EVGQLParserError.CreateFmt('Invalid USING mode at %d', [FCurrent.Position]);
    end;
    Next; // Consume the mode

    // WITH WEIGHTS
    if Match(tkWith) then
    begin
      Expect(tkWeights);
      Expect(tkLParen);
      if Check(tkNumber) then
      begin
        Result.SemanticWeight := StrToFloat(FCurrent.Text, TFormatSettings.Invariant);
        Next;
      end;
      Expect(tkComma);
      if Check(tkNumber) then
      begin
        Result.LexicalWeight := StrToFloat(FCurrent.Text, TFormatSettings.Invariant);
        Next;
      end;
      Expect(tkRParen);
    end;

    // FUSION
   if Match(tkFusion) then
    begin
      // CORRECTION: Accept tkIdentifier OR specific tokens RRF/WEIGHTED
      if Check(tkIdentifier) or Check(tkRrf) or Check(tkWeighted) then
      begin
        Result.Fusion := FCurrent.Text;
        Next;
      end
      else
        raise EVGQLParserError.CreateFmt('Expected a valid fusion mode (RRF, WEIGHTED) at position %d', [FCurrent.Position]);
    end;

    // LANGUAGE identifier — optional, sets the language for the BM25 lexical engine
    if Match(tkLanguage) then
    begin
      // Accept any identifier as language name
      if Check(tkIdentifier) or Check(tkSemantic) or Check(tkLexical) or Check(tkGlobal) then
      begin
        Result.Language := FCurrent.Text;
        Next;
      end
      else if Check(tkString) then
      begin
        Result.Language := FCurrent.Text;
        Next;
      end
      else
        raise EVGQLParserError.CreateFmt('Expected a language identifier after LANGUAGE at position %d', [FCurrent.Position]);
    end;

  except
    Result.Free;
    raise;
  end;
end;

{ ===== WHERE ===== }

function TVGQLParser.ParseWhere: TWhereClause;
begin
  Result := TWhereClause.Create(FCurrent.Position);
  try
    Next; // consume WHERE
    Result.Expression := ParseExpression;
  except
    Result.Free;
    raise;
  end;
end;

{ ===== EXPRESSIONS ===== }

function TVGQLParser.ParseExpression: TExpression;
begin
  Result := ParseOr;
end;

function TVGQLParser.ParseOr: TExpression;
var
  Left, Right: TExpression;
  BinExpr: TBinaryExpression;
begin
  Left := ParseAnd;
  Result := Left;

  while Match(tkOr) do
  begin
    Right := ParseAnd;
    BinExpr := TBinaryExpression.Create;
    BinExpr.Left := Left;
    BinExpr.Operator := boOr;
    BinExpr.Right := Right;
    Result := BinExpr;
    Left := Result;
  end;
end;

function TVGQLParser.ParseAnd: TExpression;
var
  Left, Right: TExpression;
  BinExpr: TBinaryExpression;
begin
  Left := ParseComparison;
  Result := Left;

  while Match(tkAnd) do
  begin
    Right := ParseComparison;
    BinExpr := TBinaryExpression.Create;
    BinExpr.Left := Left;
    BinExpr.Operator := boAnd;
    BinExpr.Right := Right;
    Result := BinExpr;
    Left := Result;
  end;
end;

function TVGQLParser.ParseComparison: TExpression;
var
  Left, Right, Min, Max: TExpression;
  InExpr: TInExpression;
  BetExpr: TBetweenExpression;
  BinExpr: TBinaryExpression;
  Op: TBinaryOperator;
  IsNegated: Boolean;
begin
  Left := ParsePrimary;
  Result := Left;

  // 1. Case: IS [NOT] NULL
  if Match(tkIs) then
  begin
    IsNegated := Match(tkNot);
    Expect(tkNull, 'NULL after IS');

    BinExpr := TBinaryExpression.Create;
    BinExpr.Left := Left;
    if IsNegated then
      BinExpr.Operator := boIsNotNull
    else
      BinExpr.Operator := boIsNull;
    BinExpr.Right := nil; // No right operand needed
    Exit(BinExpr);
  end;

  // 2. Case: [NOT] IN (val1, val2...)
  IsNegated := Match(tkNot); // Support for NOT IN
  if Match(tkIn) then
  begin
    InExpr := TInExpression.Create(FCurrent.Position);
    InExpr.Left := Left;
    InExpr.IsNot := IsNegated;
    Expect(tkLParen, '(');
    repeat
      InExpr.Values.Add(ParsePrimary);
      if not Match(tkComma) then
        Break;
    until False;
    Expect(tkRParen, ')');
    Exit(InExpr);
  end;

  // 3. Case: BETWEEN min AND max
  if Match(tkBetween) then
  begin
    Min := ParsePrimary;
    Expect(tkAnd, 'AND between BETWEEN values');
    Max := ParsePrimary;

    BetExpr := TBetweenExpression.Create;
    BetExpr.Left := Left;
    BetExpr.Min := Min;
    BetExpr.Max := Max;
    Exit(BetExpr);
  end;

  // 4. Case: Standard and Text Binary Operators
  if FCurrent.Kind in [tkEqual, tkNotEqual, tkGreater, tkGreaterEqual, tkLess, tkLessEqual, tkContains, tkLike, tkILike, tkStartsWith, tkEndsWith] then
  begin
    case FCurrent.Kind of
      tkEqual:
        Op := boEqual;
      tkNotEqual:
        Op := boNotEqual;
      tkGreater:
        Op := boGreater;
      tkGreaterEqual:
        Op := boGreaterEqual;
      tkLess:
        Op := boLess;
      tkLessEqual:
        Op := boLessEqual;
      tkContains:
        Op := boContains;
      tkLike:
        Op := boLike;
      tkILike:
        Op := boILike;
      tkStartsWith:
        Op := boStartsWith;
      tkEndsWith:
        Op := boEndsWith;
    else
      Op := boEqual;
    end;

    Next; // consume operator
    Right := ParsePrimary;

    BinExpr := TBinaryExpression.Create;
    BinExpr.Left := Left;
    BinExpr.Operator := Op;
    BinExpr.Right := Right;
    Result := BinExpr;
  end;
end;

function TVGQLParser.ParsePrimary: TExpression;
var
  LitExpr: TLiteralExpression;
  IdExpr: TIdentifierExpression;
  FullName: string;
begin
  case FCurrent.Kind of

    // Identifiers and words that can be used as field names
    tkIdentifier, tkText, tkMetadata, tkScore, tkId, tkRank, tkModel:
      begin
        FullName := FCurrent.Text;
        Next;

        while Match(tkDot) do
        begin
          // Also allow reserved words after a dot (e.g., meta.text)
          if FCurrent.Kind in [tkIdentifier, tkText, tkMetadata, tkScore, tkId, tkRank, tkModel] then
          begin
            FullName := FullName + '.' + FCurrent.Text;
            Next;
          end
          else
            raise EVGQLParserError.CreateFmt('Expected a name at position %d', [FCurrent.Position]);
        end;

        IdExpr := TIdentifierExpression.Create;
        IdExpr.Name := FullName;
        Result := IdExpr;
      end;

    tkString:
      begin
        LitExpr := TLiteralExpression.Create;
        LitExpr.LiteralType := ltString;
        LitExpr.Value := FCurrent.Text;
        Next;
        Result := LitExpr;
      end;

    tkNumber:
      begin
        LitExpr := TLiteralExpression.Create;
        LitExpr.LiteralType := ltNumber;
        LitExpr.Value := FCurrent.Text;
        Next;
        Result := LitExpr;
      end;

    tkBoolean:
      begin
        LitExpr := TLiteralExpression.Create;
        LitExpr.LiteralType := ltBoolean;
        LitExpr.Value := FCurrent.Text;
        Next;
        Result := LitExpr;
      end;

    tkNull:
      begin
        LitExpr := TLiteralExpression.Create;
        LitExpr.LiteralType := ltNull;
        LitExpr.Value := 'NULL';
        Next;
        Result := LitExpr;
      end;

    tkLParen:
      begin
        Next; // consume (
        Result := ParseExpression;
        Expect(tkRParen, ')');
      end;
  else
    raise EVGQLParserError.CreateFmt('Invalid expression at position %d: unexpected token "%s"', [FCurrent.Position, FCurrent.Text]);
  end;
end;

{ ===== RERANK ===== }

function TVGQLParser.ParseRerank: TRerankClause;
begin
  Result := TRerankClause.Create(FCurrent.Position);
  try
    Next; // Consume the token 'RERANK'

    // CORRECTION: Check first, assign, then advance.
    if Check(tkString) then
    begin
      Result.Query := FCurrent.Text; // Capture the CURRENT text
      Next; // Advance to the next token
    end
    else
    begin
      // If you want the string to be mandatory:
      Expect(tkString, 'text for rerank');

      // NOTE: If you wanted the string to be OPTIONAL (to use the original query),
      // you would simply remove the 'else' and the 'Expect'.
    end;

    // REGENERATE optional
    if Match(tkRegenerate) then
      Result.Regenerate := True;
  except
    Result.Free;
    raise;
  end;
end;

{ ===== THRESHOLD ===== }

function TVGQLParser.ParseThreshold: TThresholdClause;
begin
  Result := TThresholdClause.Create(FCurrent.Position);
  try
    Next; // Consume 'THRESHOLD'

    // 1. Identify Scope
    case FCurrent.Kind of
      tkGlobal:   Result.Scope := tsGlobal;
      tkSemantic: Result.Scope := tsSemantic;
      tkLexical:  Result.Scope := tsLexical;
    else
      raise EVGQLParserError.CreateFmt('Invalid THRESHOLD scope at %d. Use GLOBAL, SEMANTIC or LEXICAL', [FCurrent.Position]);
    end;
    Next; // Consume the Scope (e.g., GLOBAL)

    // 2. Read the number BEFORE advancing
    if Check(tkNumber) then
    begin
      Result.Value := StrToFloat(FCurrent.Text, TFormatSettings.Invariant);
      Next; // Now advance to the next token
    end
    else
      raise EVGQLParserError.CreateFmt('Expected a numeric value for the threshold at position %d', [FCurrent.Position]);

  except
    Result.Free;
    raise;
  end;
end;

{ ===== OPTIMIZE ===== }

function TVGQLParser.ParseOptimize: TOptimizeClause;
begin
  Result := TOptimizeClause.Create(FCurrent.Position);
  try
    Next; // consume OPTIMIZE

    // MMR(lambda) — Maximal Marginal Relevance
    if Match(tkMmr) then
    begin
      Result.Mode := omMMR;
      // Optional lambda: MMR(0.7)
      if Match(tkLParen) then
      begin
        if Check(tkNumber) then
        begin
          Result.Lambda := StrToFloat(FCurrent.Text, TFormatSettings.Invariant);
          Next;
        end;
        Expect(tkRParen, ')');
      end;
    end
    // REORDER ABC — LLM context window optimization
    else if Match(tkReorder) then
    begin
      Expect(tkAbc, 'ABC');
      Result.Mode := omReorderABC;
    end
    else
      raise EVGQLParserError.CreateFmt('Invalid OPTIMIZE mode at %d. Use: MMR[(lambda)] or REORDER ABC', [FCurrent.Position]);

  except
    Result.Free;
    raise;
  end;
end;

{ ===== RETURN ===== }

function TVGQLParser.ParseReturn: TReturnClause;
begin
  Result := TReturnClause.Create(FCurrent.Position);
  try
    Next; // consume RETURN

    // Parse fields
    repeat
      case FCurrent.Kind of
        tkText:
          Result.Fields.Add(rfText);
        tkMetadata:
          Result.Fields.Add(rfMetadata);
        tkScore:
          Result.Fields.Add(rfScore);
        // New return fields v2
        tkId:
          Result.Fields.Add(rfId);
        tkRank:
          Result.Fields.Add(rfRank);
        tkModel:
          Result.Fields.Add(rfModel);
      else
        raise EVGQLParserError.CreateFmt(
          'Invalid RETURN field at position %d. Use: TEXT, METADATA, SCORE, ID, RANK or MODEL',
          [FCurrent.Position]);
      end;
      Next;

      if not Match(tkComma) then
        Break;
    until False;

    if Result.Fields.Count = 0 then
      raise EVGQLParserError.Create('RETURN requires at least one field');
  except
    Result.Free;
    raise;
  end;
end;

{ ===== DISTINCT ON ===== }

function TVGQLParser.ParseDistinct: TDistinctClause;
begin
  Result := TDistinctClause.Create(FCurrent.Position);
  try
    Next; // consume DISTINCT
    Expect(tkOn, 'ON after DISTINCT');

    // The field can be an identifier or a return token used as a field
    if FCurrent.Kind in [tkIdentifier, tkText, tkMetadata, tkScore, tkId, tkRank, tkModel] then
    begin
      Result.Field := FCurrent.Text;
      Next;
    end
    else
      raise EVGQLParserError.CreateFmt('Expected a field name after DISTINCT ON at position %d', [FCurrent.Position]);
  except
    Result.Free;
    raise;
  end;
end;

{ ===== ORDER BY ===== }

function TVGQLParser.ParseOrderBy: TOrderByClause;
var
  OBField: TOrderByField;
begin
  Result := TOrderByClause.Create(FCurrent.Position);
  try
    Next; // consume ORDER
    Expect(tkBy, 'BY after ORDER');

    // Parse field list: field1 [ASC|DESC], field2 [ASC|DESC], ...
    repeat
      // Field name
      if FCurrent.Kind in [tkIdentifier, tkText, tkMetadata, tkScore, tkId, tkRank, tkModel] then
      begin
        OBField.FieldName := FCurrent.Text;
        Next;
      end
      else
        raise EVGQLParserError.CreateFmt('Expected a field name in ORDER BY, position %d', [FCurrent.Position]);

      // Optional direction (default ASC)
      if Match(tkDesc) then
        OBField.Direction := odDesc
      else
      begin
        Match(tkAsc); // optional, default ASC
        OBField.Direction := odAsc;
      end;

      Result.Fields.Add(OBField);

      if not Match(tkComma) then
        Break;
    until False;

    if Result.Fields.Count = 0 then
      raise EVGQLParserError.Create('ORDER BY requires at least one field');
  except
    Result.Free;
    raise;
  end;
end;

  //=======================================
  //============ COMPILER =================
  //=======================================

{ TVGQLCompiler }

function TVGQLCompiler.Translate(AQuery: TVGQLQuery): TVGQLRequest;
begin
  if not Assigned(AQuery) then
    raise EVGQLTranslationError.Create('Null query AST');

  FRequest := TVGQLRequest.Create;
  try
    // 1. MATCH (Entity and Alias)
    if Assigned(AQuery.Match) then
      TranslateMatch(AQuery.Match);

    // 2. SEARCH (Search text - MANDATORY)
    if Assigned(AQuery.Search) then
      TranslateSearch(AQuery.Search)
    else
      raise EVGQLTranslationError.Create('SEARCH clause is mandatory');

    // 3. USING (Mode and weights)
    if Assigned(AQuery.UsingClause) then
      TranslateUsing(AQuery.UsingClause);

    // 4. WHERE (Complex metadata filters)
    if Assigned(AQuery.WhereClause) then
      TranslateWhere(AQuery.WhereClause);

    // 5. RERANK
    if Assigned(AQuery.RerankClause) then
      TranslateRerank(AQuery.RerankClause);

    // 6. THRESHOLD
    if Assigned(AQuery.ThresholdClause) then
      TranslateThreshold(AQuery.ThresholdClause);

    // 7. OPTIMIZE
    if Assigned(AQuery.OptimizeClause) then
      TranslateOptimize(AQuery.OptimizeClause);

    // 8. RETURN
    if Assigned(AQuery.ReturnClause) then
      TranslateReturn(AQuery.ReturnClause);

    // 9. LIMIT
    if AQuery.Limit > 0 then
      FRequest.Limit := AQuery.Limit;

    // 10. OFFSET — pagination
    FRequest.Offset := AQuery.Offset;

    // 11. DISTINCT ON
    if Assigned(AQuery.DistinctClause) then
      TranslateDistinct(AQuery.DistinctClause);

    // 12. ORDER BY
    if Assigned(AQuery.OrderByClause) then
      TranslateOrderBy(AQuery.OrderByClause);

    // 13. EXPLAIN
    FRequest.Explain := AQuery.Explain;

    Result := FRequest;
    FRequest := nil; // Transfer ownership to the caller
  except
    on E: Exception do
    begin
      FRequest.Free;
      raise EVGQLTranslationError.CreateFmt('VQL compilation error: %s', [E.Message]);
    end;
  end;
end;

procedure TVGQLCompiler.TranslateMatch(AClause: TMatchClause);
begin
  FRequest.Entity := AClause.EntityName;
  FRequest.ALabel := AClause.Alias;
end;

procedure TVGQLCompiler.TranslateSearch(AClause: TSearchClause);
begin
  FRequest.Query := AClause.QueryText;
end;

procedure TVGQLCompiler.TranslateUsing(AClause: TUsingClause);
var
  TotalWeight: Double;
begin
  // 1. Mode Mapping and Weight Normalization
  case AClause.Mode of
    TSearchMode.smHybrid:
    begin
      FRequest.Mode := smHybrid;

      // In hybrid mode, ensure weights sum exactly 1.0
      TotalWeight := AClause.SemanticWeight + AClause.LexicalWeight;

      if TotalWeight > 0 then
      begin
        FRequest.WeightSemantic := AClause.SemanticWeight / TotalWeight;
        FRequest.WeightLexical := AClause.LexicalWeight / TotalWeight;
      end
      else
      begin
        // Fallback if weights are zero
        FRequest.WeightSemantic := 0.5;
        FRequest.WeightLexical := 0.5;
      end;
    end;

    TSearchMode.smEmbeddings:
    begin
      FRequest.Mode := smEmbeddings;
      // If only embeddings, semantic weight MUST be 100%
      FRequest.WeightSemantic := 1.0;
      FRequest.WeightLexical := 0.0;
    end;

    TSearchMode.smBM25:
    begin
      FRequest.Mode := TSearchMode.smBM25;
      // If only BM25, lexical weight MUST be 100%
      FRequest.WeightSemantic := 0.0;
      FRequest.WeightLexical := 1.0;
    end;
  end;

  // 2. Fusion (Only relevant if mode is Hybrid)
  if AClause.Fusion <> '' then
  begin
    FRequest.FusionSpecified := True;
    if SameText(AClause.Fusion, 'RRF') then
      FRequest.Fusion := fmRRF
    else if SameText(AClause.Fusion, 'WEIGHTED') then
      FRequest.Fusion := fmWeighted
    else
      raise EVGQLTranslationError.CreateFmt('Unknown fusion mode: %s', [AClause.Fusion]);
  end;

  // 3. Language — overrides the BM25 engine language when specified in USING
  if AClause.Language <> '' then
  begin
    FRequest.Language := AClause.Language;
    FRequest.LanguageSpecified := True;
  end;
end;

procedure TVGQLCompiler.TranslateWhere(AClause: TWhereClause);
begin
  if Assigned(AClause.Expression) then
  begin
    FRequest.Filter.Clear;
    FRequest.Filter.LogicalOp := loAnd; // Root defaults to AND
    BuildFilter(AClause.Expression, FRequest.Filter);
  end;
end;

{ --- EXPRESSION COMPILATION ENGINE --- }

function TVGQLCompiler.GetLiteralValue(AExpr: TExpression): Variant;
var
  Lit: TLiteralExpression;
begin
  if not(AExpr is TLiteralExpression) then
    raise EVGQLTranslationError.Create('Expected a literal value (String, Number or Boolean)');

  Lit := TLiteralExpression(AExpr);
  case Lit.LiteralType of
    ltString:
      Result := Lit.Value;
    ltNumber:
      Result := StrToFloatDef(Lit.Value.Replace(',', '.'), 0);
    ltBoolean:
      Result := SameText(Lit.Value, 'TRUE');
    ltNull:
      Result := Null;
  else
    Result := Unassigned;
  end;
end;

procedure TVGQLCompiler.BuildFilter(AExpr: TExpression; ACriteria: TAiFilterCriteria);
var
  Bin: TBinaryExpression;
  Bet: TBetweenExpression;
  InExp: TInExpression;
  FieldName: string;
  VArray: Variant;
  i: Integer;
begin
  if not Assigned(AExpr) then
    Exit;

  // 1. LOGICAL GROUPS (AND / OR)
  if (AExpr is TBinaryExpression) and (TBinaryExpression(AExpr).Operator in [boAnd, boOr]) then
  begin
    Bin := TBinaryExpression(AExpr);

    // If the node operator matches the current level, continue in the same list
    // If it changes (e.g., an OR inside an AND), create a recursive subgroup
    if ((Bin.Operator = boAnd) and (ACriteria.LogicalOp = loAnd)) or ((Bin.Operator = boOr) and (ACriteria.LogicalOp = loOr)) then
    begin
      BuildFilter(Bin.Left, ACriteria);
      BuildFilter(Bin.Right, ACriteria);
    end
    else
    begin
      // Logic change detected -> Create Group Node
      if Bin.Operator = boAnd then
        BuildFilter(Bin, ACriteria.AddGroup(loAnd))
      else
        BuildFilter(Bin, ACriteria.AddGroup(loOr));
    end;
  end

  // 2. BETWEEN COMPARISON
  else if AExpr is TBetweenExpression then
  begin
    Bet := TBetweenExpression(AExpr);
    if not(Bet.Left is TIdentifierExpression) then
      raise EVGQLTranslationError.Create('BETWEEN requires a metadata identifier');

    ACriteria.AddBetween(TIdentifierExpression(Bet.Left).Name, GetLiteralValue(Bet.Min), GetLiteralValue(Bet.Max));
  end

  // 3. LIST COMPARISON (IN)
  else if AExpr is TInExpression then
  begin
    InExp := TInExpression(AExpr);
    if not(InExp.Left is TIdentifierExpression) then
      raise EVGQLTranslationError.Create('IN requires a metadata identifier');

    FieldName := TIdentifierExpression(InExp.Left).Name;
    VArray := VarArrayCreate([0, InExp.Values.Count - 1], varVariant);
    for i := 0 to InExp.Values.Count - 1 do
      VArray[i] := GetLiteralValue(InExp.Values[i]);

    if InExp.IsNot then
      ACriteria.Add(FieldName, foNotIn, VArray)
    else
      ACriteria.AddIn(FieldName, VArray);
  end

  // 4. STANDARD BINARY COMPARISONS
  else if AExpr is TBinaryExpression then
  begin
    Bin := TBinaryExpression(AExpr);
    if not(Bin.Left is TIdentifierExpression) then
      raise EVGQLTranslationError.Create('Left side of comparison must be a field');

    FieldName := TIdentifierExpression(Bin.Left).Name;

    case Bin.Operator of
      boEqual:
        ACriteria.AddEqual(FieldName, GetLiteralValue(Bin.Right));
      boNotEqual:
        ACriteria.Add(FieldName, foNotEqual, GetLiteralValue(Bin.Right));
      boGreater:
        ACriteria.AddGreater(FieldName, GetLiteralValue(Bin.Right));
      boGreaterEqual:
        ACriteria.Add(FieldName, foGreaterOrEqual, GetLiteralValue(Bin.Right));
      boLess:
        ACriteria.AddLess(FieldName, GetLiteralValue(Bin.Right));
      boLessEqual:
        ACriteria.Add(FieldName, foLessOrEqual, GetLiteralValue(Bin.Right));
      boContains:
        ACriteria.Add(FieldName, foContains, GetLiteralValue(Bin.Right));
      boStartsWith:
        ACriteria.Add(FieldName, foStartsWith, GetLiteralValue(Bin.Right));
      boEndsWith:
        ACriteria.Add(FieldName, foEndsWith, GetLiteralValue(Bin.Right));
      boLike:
        ACriteria.Add(FieldName, foLike, GetLiteralValue(Bin.Right));
      boILike:
        ACriteria.Add(FieldName, foILike, GetLiteralValue(Bin.Right));
      boIsNull:
        ACriteria.Add(FieldName, foIsNull, Null);
      boIsNotNull:
        ACriteria.Add(FieldName, foIsNotNull, Null);
    end;
  end;
end;

procedure TVGQLCompiler.TranslateRerank(AClause: TRerankClause);
begin
  FRequest.RerankQuery := AClause.Query;
  FRequest.RerankRegenerate := AClause.Regenerate;
end;

procedure TVGQLCompiler.TranslateThreshold(AClause: TThresholdClause);
begin
  case AClause.Scope of
    tsGlobal:
      FRequest.MinGlobal := AClause.Value;
    tsSemantic:
      FRequest.MinSemantic := AClause.Value;
    tsLexical:
      FRequest.MinLexical := AClause.Value;
  end;
end;

procedure TVGQLCompiler.TranslateOptimize(AClause: TOptimizeClause);
begin
  case AClause.Mode of
    omReorderABC:
    begin
      FRequest.UseReorderABC := True;
      FRequest.UseMMR := False;
    end;
    omMMR:
    begin
      FRequest.UseMMR := True;
      FRequest.UseReorderABC := False;
      FRequest.MmrLambda := AClause.Lambda;
    end;
  else
    FRequest.UseReorderABC := False;
    FRequest.UseMMR := False;
  end;
end;

procedure TVGQLCompiler.TranslateReturn(AClause: TReturnClause);
var
  Field: TReturnField;
begin
  for Field in AClause.Fields do
  begin
    case Field of
      rfMetadata:
        FRequest.IncludeMetadata := True;
      rfScore:
        FRequest.IncludeScore := True;
      // New return fields v2
      rfId:
        FRequest.IncludeId := True;
      rfRank:
        FRequest.IncludeRank := True;
      rfModel:
        FRequest.IncludeModel := True;
    end;
  end;
end;

procedure TVGQLCompiler.TranslateDistinct(AClause: TDistinctClause);
begin
  FRequest.DistinctField := AClause.Field;
end;

procedure TVGQLCompiler.TranslateOrderBy(AClause: TOrderByClause);
var
  F: TOrderByField;
begin
  for F in AClause.Fields do
    FRequest.OrderByFields.Add(F);
end;

  //======================================
  //============ REQUEST =================
  //======================================

constructor TVGQLRequest.Create;
begin
  Filter := TAiFilterCriteria.Create; // Initialize the criteria container
  OrderByFields := TList<TOrderByField>.Create;
  Mode := smHybrid;
  WeightSemantic := 0.7;
  WeightLexical := 0.3;
  Limit := 10;
  Offset := 0;
  Fusion := fmWeighted;
  FusionSpecified := False;
  Language := 'spanish';
  LanguageSpecified := False;
  MmrLambda := 0.7;
end;

destructor TVGQLRequest.Destroy;
begin
  Filter.Free;
  OrderByFields.Free;
  inherited;
end;



end.
