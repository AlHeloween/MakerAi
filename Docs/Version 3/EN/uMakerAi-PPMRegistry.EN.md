# PPM Registry Integration

**MakerAI v3.3 — Technical Documentation**
Last updated: March 2026

---

## Table of Contents

1. [What is PPM?](#1-what-is-ppm)
2. [TAiPrompts — Integration with Prompts](#2-taiprompts--integration-with-prompts)
   - [PPMRegistryUrl Property](#21-ppmregistryurl-property)
   - [SearchPPM — Search Prompts](#22-searchppm--search-prompts)
   - [LoadFromPPM — Import a Prompt](#23-loadfromppm--import-a-prompt)
   - [Placeholder Conversion](#24-placeholder-conversion)
3. [TAiFunctions — Integration with MCP Tools](#3-taifunctions--integration-with-mcp-tools)
   - [SearchPPMMCP — Discover Tools](#31-searchppmmcp--discover-tools)
   - [ImportMCPFromPPM — Register a Tool](#32-importmcpfromppm--register-a-tool)
4. [Complete Examples](#4-complete-examples)
5. [PPM REST API Reference](#5-ppm-rest-api-reference)
6. [Source Files](#6-source-files)

---

## 1. What is PPM?

**PPM (PascalAI Package Manager)** is a public package registry for the Pascal/Delphi AI ecosystem. It allows publishing and consuming:

| Type | Description |
|------|-------------|
| `prompt` | Reusable prompt templates with `{{name}}` variables |
| `mcp` | MCP tool definitions with JSON Schema |
| `pai` | Pascal AI library packages |
| `clib` | C library bindings |

**Official registry URL:** `https://registry.pascalai.org`

MakerAI integrates with `prompt` and `mcp` types through `TAiPrompts` and `TAiFunctions` respectively. Public search and download endpoints **do not require authentication**.

---

## 2. TAiPrompts — Integration with Prompts

Source file: `Source/Core/uMakerAi.Prompts.pas`

### 2.1 PPMRegistryUrl Property

```pascal
property PPMRegistryUrl: String;  // published
```

Base URL of the PPM registry. By default points to the official registry. Only needs changing if using a private server instance.

```pascal
// Use official registry (default, no need to assign)
AiPrompts1.PPMRegistryUrl := 'https://registry.pascalai.org';

// Use a private internal registry
AiPrompts1.PPMRegistryUrl := 'http://my-internal-server:8080';
```

The property is visible in the IDE Object Inspector and can be configured at design time.

---

### 2.2 SearchPPM — Search Prompts

```pascal
function SearchPPM(
  const AQuery: String;
  const AType: String = 'prompt';
  APage: Integer = 1;
  APerPage: Integer = 20
): TJSONObject;
```

Searches packages in the registry. Returns the results JSON. **The caller is responsible for freeing the returned object.**

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `AQuery` | String | Search text (searches in name and description) |
| `AType` | String | Type filter: `'prompt'`, `'mcp'`, `'pai'`, `'clib'` |
| `APage` | Integer | Results page (base 1) |
| `APerPage` | Integer | Results per page (maximum 100) |

**Returned JSON structure:**

```json
{
  "packages": [
    {
      "name": "code-review",
      "type": "prompt",
      "description": "Prompt for code review with security analysis",
      "version": "1.2.0",
      "author": "gustavoeenriquez",
      "downloads": 850
    }
  ],
  "total": 42,
  "page": 1,
  "per_page": 20
}
```

**Usage example:**

```pascal
var
  LResult: TJSONObject;
  LPackages: TJSONArray;
  I: Integer;
begin
  LResult := AiPrompts1.SearchPPM('code review');
  if not Assigned(LResult) then
  begin
    ShowMessage('Error connecting to registry.');
    Exit;
  end;
  try
    LPackages := LResult.GetValue<TJSONArray>('packages');
    for I := 0 to LPackages.Count - 1 do
    begin
      var LPkg := LPackages.Items[I] as TJSONObject;
      Memo1.Lines.Add(Format('%s v%s — %s',
        [LPkg.GetValue<String>('name'),
         LPkg.GetValue<String>('version'),
         LPkg.GetValue<String>('description')]));
    end;
  finally
    LResult.Free;
  end;
end;
```

---

### 2.3 LoadFromPPM — Import a Prompt

```pascal
function LoadFromPPM(
  const AName: String;
  const AVersion: String = ''
): TAiPromptItem;
```

Downloads a prompt from the registry and adds it to the component's `Items` collection. If a prompt with the same name already exists, it updates it instead of duplicating.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `AName` | String | Exact package name in the registry |
| `AVersion` | String | Version to download. If empty, automatically resolves the latest available version |

**Return:** Loaded `TAiPromptItem`, or `nil` if the package doesn't exist or there's a network error.

**Basic example:**

```pascal
var
  LItem: TAiPromptItem;
begin
  // Load latest available version
  LItem := AiPrompts1.LoadFromPPM('code-review');
  if Assigned(LItem) then
    ShowMessage('Prompt loaded: ' + LItem.Nombre)
  else
    ShowMessage('Could not load prompt.');
end;
```

**Example with specific version:**

```pascal
LItem := AiPrompts1.LoadFromPPM('sql-generator', '2.1.0');
```

**Use the prompt after importing:**

```pascal
// After LoadFromPPM, the prompt is available like any other:
var LText := AiPrompts1.GetTemplate('code-review', ['language=Delphi', 'focus=security']);

// With TStringList:
var LParams := TStringList.Create;
try
  LParams.Values['language'] := 'Delphi';
  LParams.Values['focus'] := 'performance';
  LText := AiPrompts1.GetTemplate('code-review', LParams);
finally
  LParams.Free;
end;
```

---

### 2.4 Placeholder Conversion

Prompts in PPM use the `{{variable_name}}` syntax. When importing with `LoadFromPPM`, MakerAI **automatically** converts them to the native `<#variable_name>` format.

| PPM Format | MakerAI Format | Description |
|------------|----------------|-------------|
| `{{language}}` | `<#language>` | Simple text variable |
| `{{code_to_review}}` | `<#code_to_review>` | Variable with underscore |
| `{{focus}}` | `<#focus>` | Focus variable |

**Example prompt in PPM (`code-review.prompt`):**

```
You are an expert code reviewer in {{language}}.

Analyze the following code:

{{code_to_review}}

Aspects to review: {{focus}}
```

**After `LoadFromPPM`, the prompt in MakerAI becomes:**

```
You are an expert code reviewer in <#language>.

Analyze the following code:

<#code_to_review>

Aspects to review: <#focus>
```

---

## 3. TAiFunctions — Integration with MCP Tools

Source file: `Source/Tools/uMakerAi.Tools.Functions.pas`

MCP packages in PPM contain a **JSON Schema** describing what parameters a tool accepts. Unlike prompts, the MCP tool itself (the server that executes it) is not included in PPM — the registry functions as a **discovery catalog**. The developer must configure the MCP server URL or command separately.

---

### 3.1 SearchPPMMCP — Discover Tools

```pascal
function SearchPPMMCP(
  const AQuery: String;
  APage: Integer = 1;
  APerPage: Integer = 20;
  const ARegistryUrl: String = 'https://registry.pascalai.org'
): TJSONObject;
```

Searches MCP tools available in the registry. The result includes each tool's JSON Schema inline. **The caller is responsible for freeing the returned object.**

**Example returned JSON:**

```json
{
  "tools": [
    {
      "name": "mcp-web-search",
      "description": "Web search with Brave Search API",
      "version": "1.2.0",
      "downloads": 3500,
      "schema": {
        "type": "object",
        "title": "Web Search",
        "properties": {
          "query": { "type": "string", "description": "Search term" },
          "count": { "type": "integer", "description": "Number of results" }
        },
        "required": ["query"]
      }
    }
  ],
  "total": 47,
  "page": 1,
  "per_page": 20
}
```

**Usage example:**

```pascal
var
  LResult: TJSONObject;
  LTools: TJSONArray;
begin
  LResult := AiFunctions1.SearchPPMMCP('web search');
  if not Assigned(LResult) then Exit;
  try
    LTools := LResult.GetValue<TJSONArray>('tools');
    for var I := 0 to LTools.Count - 1 do
    begin
      var LTool := LTools.Items[I] as TJSONObject;
      ListBox1.Items.Add(Format('%s — %s',
        [LTool.GetValue<String>('name'),
         LTool.GetValue<String>('description')]));
    end;
  finally
    LResult.Free;
  end;
end;
```

---

### 3.2 ImportMCPFromPPM — Register a Tool

```pascal
function ImportMCPFromPPM(
  const AName: String;
  const AVersion: String = '';
  const ARegistryUrl: String = 'https://registry.pascalai.org'
): TMCPClientItem;
```

Registers an MCP tool from the registry as a new `TMCPClientItem` in the component's `MCPClients` collection. The item is created with:

- `TransportType = tpHttp`
- `URL = ''` (empty — requires configuration)
- `Enabled = False` (disabled until server is configured)

If a client with the same name already exists, returns the existing one without duplicating.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `AName` | String | MCP package name in the registry |
| `AVersion` | String | Specific version, or empty for latest |
| `ARegistryUrl` | String | Registry URL (default: official) |

**Typical usage flow:**

```pascal
var
  LItem: TMCPClientItem;
begin
  // 1. Import from registry (creates disabled stub)
  LItem := AiFunctions1.ImportMCPFromPPM('mcp-web-search');
  if not Assigned(LItem) then
  begin
    ShowMessage('Tool not found in registry.');
    Exit;
  end;

  // 2. Configure the real MCP server URL
  LItem.Params.Values['URL'] := 'http://localhost:3000/mcp';

  // 3. Enable and synchronize
  LItem.Enabled := True;
  LItem.UpdateClientProperties;

  // 4. Initialize the connection
  if LItem.MCPClient <> nil then
    LItem.MCPClient.Initialize;
end;
```

---

## 4. Complete Examples

### Example 1 — Load a PPM Prompt and Use it in Chat

```pascal
procedure TForm1.BtnLoadPromptClick(Sender: TObject);
var
  LItem: TAiPromptItem;
  LPrompt: String;
begin
  // Import from PPM
  LItem := AiPrompts1.LoadFromPPM('delphi-code-review');
  if not Assigned(LItem) then
  begin
    ShowMessage('Prompt not found in PPM.');
    Exit;
  end;

  // Substitute variables and send to LLM
  LPrompt := AiPrompts1.GetTemplate('delphi-code-review',
    ['language=Delphi', 'focus=memory management', 'code=' + Memo1.Text]);

  AiConnection1.NewChat;
  AiConnection1.Run(LPrompt);
end;
```

---

### Example 2 — Browse the Prompt Catalog in a List

```pascal
procedure TForm1.BtnSearchClick(Sender: TObject);
var
  LResult: TJSONObject;
  LPackages: TJSONArray;
begin
  ListBox1.Clear;
  LResult := AiPrompts1.SearchPPM(EdtSearch.Text, 'prompt', 1, 50);
  if not Assigned(LResult) then
  begin
    ShowMessage('Error connecting to registry.pascalai.org');
    Exit;
  end;
  try
    LPackages := LResult.GetValue<TJSONArray>('packages');
    for var I := 0 to LPackages.Count - 1 do
    begin
      var LPkg := LPackages.Items[I] as TJSONObject;
      // Store package name in item Data
      ListBox1.Items.AddObject(
        Format('[v%s] %s — %s', [
          LPkg.GetValue<String>('version'),
          LPkg.GetValue<String>('name'),
          LPkg.GetValue<String>('description')
        ]),
        TObject(LPackages.Items[I])  // temporary reference
      );
    end;
    LblTotal.Text := Format('%d prompts found', [LResult.GetValue<Integer>('total')]);
  finally
    LResult.Free;
  end;
end;

// On double-click in list, import selected prompt
procedure TForm1.ListBox1DblClick(Sender: TObject);
var
  LName: String;
  LItem: TAiPromptItem;
begin
  if ListBox1.ItemIndex < 0 then Exit;
  // Extract name from text "[v1.0.0] prompt-name — description"
  LName := ListBox1.Items[ListBox1.ItemIndex];
  LName := Copy(LName, Pos('] ', LName) + 2, MaxInt);
  LName := Copy(LName, 1, Pos(' — ', LName) - 1);

  LItem := AiPrompts1.LoadFromPPM(LName);
  if Assigned(LItem) then
    ShowMessage('Prompt "' + LItem.Nombre + '" imported successfully.')
  else
    ShowMessage('Error importing prompt.');
end;
```

---

### Example 3 — Discover and Integrate an MCP Tool

```pascal
procedure TForm1.BtnIntegrateMCPClick(Sender: TObject);
var
  LResult: TJSONObject;
  LTools: TJSONArray;
  LName: String;
  LItem: TMCPClientItem;
begin
  // Search available calculators
  LResult := AiFunctions1.SearchPPMMCP('calculator');
  if not Assigned(LResult) then Exit;
  try
    LTools := LResult.GetValue<TJSONArray>('tools');
    if LTools.Count = 0 then
    begin
      ShowMessage('No MCP tools of type "calculator" found.');
      Exit;
    end;
    LName := (LTools.Items[0] as TJSONObject).GetValue<String>('name');
  finally
    LResult.Free;
  end;

  // Import the first one found
  LItem := AiFunctions1.ImportMCPFromPPM(LName);
  if not Assigned(LItem) then Exit;

  // Complete configuration with local server URL
  LItem.Params.Values['URL'] := 'http://localhost:4000/mcp';
  LItem.Enabled := True;
  LItem.UpdateClientProperties;

  if Assigned(LItem.MCPClient) then
    LItem.MCPClient.Initialize;

  ShowMessage(Format('Tool "%s" integrated and ready to use.', [LName]));
end;
```

---

## 5. PPM REST API Reference

MakerAI methods internally call these endpoints. Documented here for reference or to implement direct calls.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/search?q=...&type=prompt` | GET | Search packages |
| `/v1/packages/:name` | GET | Package info (versions, author, etc.) |
| `/v1/packages/:name/:version/raw` | GET | Plain text of prompt (no substitution) |
| `/v1/packages/:name/:version/render?var=val` | GET | Prompt with substituted variables (server-side) |
| `/v1/mcp/discover?q=...` | GET | Search MCP tools with inline schemas |
| `/v1/packages/:name/:version/schema` | GET | JSON Schema of an MCP tool |

**Notes:**
- All query endpoints are **public** (no authentication required).
- Authentication (`Authorization: Bearer ppm_...`) is only needed to publish packages.
- The `latest` version doesn't exist as a literal path — `LoadFromPPM` and `ImportMCPFromPPM` resolve it by querying the package info endpoint and selecting the first non-yanked version.

---

## 6. Source Files

| File | Relevant Content |
|------|------------------|
| `Source/Core/uMakerAi.Prompts.pas` | `TAiPrompts`, `TAiPromptItem`, PPM methods for prompts |
| `Source/Tools/uMakerAi.Tools.Functions.pas` | `TAiFunctions`, `TMCPClientItems`, PPM methods for MCP |

### Constants and Defaults

```pascal
// uMakerAi.Prompts.pas
const
  PPM_DEFAULT_REGISTRY = 'https://registry.pascalai.org';

// uMakerAi.Tools.Functions.pas
// Default URL is passed as default parameter value:
//   const ARegistryUrl: String = 'https://registry.pascalai.org'
```

### Added Dependencies

Both files use:
- `System.Net.HttpClient` — HTTP client (`THTTPClient`, `IHTTPResponse`)
- `System.NetEncoding` — URL parameter encoding (`TNetEncoding.URL.Encode`)
- `System.RegularExpressions` — placeholder conversion `{{var}}` → `<#var>` (only in Prompts)

These units are part of the standard Delphi RTL and have been available since Delphi 10.4 Sydney.