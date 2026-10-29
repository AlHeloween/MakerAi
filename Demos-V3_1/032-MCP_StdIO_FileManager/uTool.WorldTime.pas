unit uTool.WorldTime;

interface

uses
  uMakerAi.MCPServer.Core,
  System.SysUtils, System.StrUtils,
  System.JSON;

type
  // =============================================================================
  // TOOL TO GET THE TIME OF A CITY
  // =============================================================================
  
  TGetCityTimeParams = class
  private
    FCountry: string;
    FCity: string;
  public
    [AiMCPSchemaDescription('Country of the city (e.g.: "Spain", "Mexico", "Argentina")')]
    property Country: string read FCountry write FCountry;
    
    [AiMCPSchemaDescription('Name of the city (e.g.: "Madrid", "Mexico City", "Buenos Aires")')]
    property City: string read FCity write FCity;
  end;

  TGetCityTimeTool = class(TAiMCPToolBase<TGetCityTimeParams>)
  protected
    function ExecuteWithParams(const AParams: TGetCityTimeParams; const AuthContext: TAiAuthContext): TJSONObject; override;
  public
    constructor Create; override;
  end;

procedure RegisterWorldTimeTool(ALogicServer: TAiMCPServer);

implementation

{ TGetCityTimeTool }

constructor TGetCityTimeTool.Create;
begin
  inherited;
  FName := 'get_city_time';
  FDescription := 'Gets the current date and time of a specific city in a given country';
end;

function TGetCityTimeTool.ExecuteWithParams(const AParams: TGetCityTimeParams; 
  const AuthContext: TAiAuthContext): TJSONObject;
var
  ResultObject: TJSONObject;
  CurrentDateTime: TDateTime;
  TimeZoneOffset: Integer;
  CityDateTime: TDateTime;
begin
  try
    // Validate required parameters
    if AParams.Country.IsEmpty then
      raise Exception.Create('The "Country" parameter is required');
      
    if AParams.City.IsEmpty then
      raise Exception.Create('The "City" parameter is required');

    // =========================================================================
    // IMPLEMENT YOUR LOGIC HERE TO GET THE CITY TIME
    // =========================================================================
    // You can:
    // 1. Query an external time zone API (WorldTimeAPI, TimeZoneDB, etc.)
    // 2. Use a local database with time zone information
    // 3. Implement your own time zone conversion logic
    //
    // Example of structure you could return:
    // - DateTime: current date and time in that city
    // - TimeZone: name of the time zone (e.g.: "UTC-5", "Europe/Madrid")
    // - UTCOffset: difference in hours from UTC
    // - IsDST: whether it is in daylight saving time
    
    // TEMPORARY EXAMPLE (replace with real implementation):                 ewrqwr
    CurrentDateTime := Now;
    TimeZoneOffset := 0; // Calculate the real offset according to the city
    CityDateTime := CurrentDateTime; // Adjust according to time zone

    // =========================================================================
    // END OF IMPLEMENTATION SPACE
    // =========================================================================

    // Build structured response
    ResultObject := TJSONObject.Create;
    try
      ResultObject.AddPair('country', AParams.Country);
      ResultObject.AddPair('city', AParams.City);
      ResultObject.AddPair('datetime', FormatDateTime('yyyy-mm-dd hh:nn:ss', CityDateTime));
      ResultObject.AddPair('date', FormatDateTime('yyyy-mm-dd', CityDateTime));
      ResultObject.AddPair('time', FormatDateTime('hh:nn:ss', CityDateTime));
      ResultObject.AddPair('timezone', 'UTC' + IfThen(TimeZoneOffset >= 0, '+', '') + IntToStr(TimeZoneOffset));
      ResultObject.AddPair('utc_offset', TimeZoneOffset);
      ResultObject.AddPair('message', Format('Current time in %s, %s', [AParams.City, AParams.Country]));

      Result := TAiMCPResponseBuilder.New
        .AddText(ResultObject.ToJSON)
        .Build;
    finally
      ResultObject.Free;
    end;

  except
    on E: Exception do
      Result := TAiMCPResponseBuilder.New
        .AddText('❌ Error getting city time: ' + E.Message)
        .Build;
  end;
end;

procedure RegisterWorldTimeTool(ALogicServer: TAiMCPServer);
begin
  if not Assigned(ALogicServer) then
    raise Exception.Create('LogicServer cannot be null to register tools.');
    
  ALogicServer.RegisterTool('get_city_time', 
    function: IAiMCPTool 
    begin 
      Result := TGetCityTimeTool.Create; 
    end);
end;

end.
