program PPMDemo;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.JSON,
  uMakerAi.Prompts;

procedure MostrarTemplateLocal(Prompts: TAiPrompts);
var
  S: string;
begin
  WriteLn('--- Local templates ---');
  Prompts.AddString('reporte',
    'REPORTE DE VENTAS' + sLineBreak +
    'Cliente : <#Cliente>'  + sLineBreak +
    'Periodo : <#Periodo>'  + sLineBreak +
    'Total   : <#Total>');

  S := Prompts.GetTemplate('reporte',
    ['Cliente=Acme Corp', 'Periodo=Mayo 2026', 'Total=$14,500']);
  WriteLn(S);
  WriteLn;
end;

procedure BuscarEnRegistry(Prompts: TAiPrompts);
var
  SearchResult: TJSONObject;
  Results     : TJSONValue;
  Pkg         : TJSONObject;
  Name, Desc  : string;
  I, Count    : Integer;
begin
  WriteLn('--- Search in the PPM registry ---');
  WriteLn('Registry: ', Prompts.PPMRegistryUrl);
  SearchResult := Prompts.SearchPPM('commit', 'prompt');
  if not Assigned(SearchResult) then
  begin
    WriteLn('Could not connect to the registry.');
    WriteLn;
    Exit;
  end;
  try
    Results := SearchResult.FindValue('packages');
    if Assigned(Results) and (Results is TJSONArray) then
    begin
      Count := TJSONArray(Results).Count;
      WriteLn('Packages found: ', Count);
      for I := 0 to Count - 1 do
      begin
        if I >= 5 then Break;
        Pkg  := TJSONArray(Results).Items[I] as TJSONObject;
        Name := ''; Desc := '';
        Pkg.TryGetValue<String>('name', Name);
        Pkg.TryGetValue<String>('description', Desc);
        WriteLn('  ', I + 1, '. ', Name, ' -- ', Desc);
      end;
    end
    else
      WriteLn(SearchResult.ToJSON);
  finally
    SearchResult.Free;
  end;
  WriteLn;
end;

procedure DescargarPrompt(Prompts: TAiPrompts);
var
  Item: TAiPromptItem;
  S   : string;
begin
  WriteLn('--- LoadFromPPM ---');
  Item := Prompts.LoadFromPPM('commit-message');
  if not Assigned(Item) then
  begin
    WriteLn('Could not find "commit-message" in the registry.');
    WriteLn;
    Exit;
  end;
  WriteLn('Downloaded : ', Item.Nombre);
  WriteLn('Description: ', Item.Descripcion);
  S := Prompts.GetTemplate('commit-message',
    ['commit_type=feat', 'scope=clientes',
     'change_summary=agrega busqueda en lista de clientes']);
  WriteLn;
  WriteLn('Prompt with variables:');
  WriteLn(S);
  WriteLn;
end;

var
  Prompts: TAiPrompts;
begin
  WriteLn('=============================================');
  WriteLn('  Ch. 31 -- PPM: MakerAI Package Manager');
  WriteLn('=============================================');
  WriteLn;

  Prompts := TAiPrompts.Create(nil);
  try
    MostrarTemplateLocal(Prompts);
    BuscarEnRegistry(Prompts);
    DescargarPrompt(Prompts);
  finally
    Prompts.Free;
  end;

  WriteLn('Demo completed. Press Enter to exit.');
  ReadLn;
end.
