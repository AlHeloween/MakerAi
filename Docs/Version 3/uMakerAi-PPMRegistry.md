# IntegraciÃ³n con PPM Registry

**MakerAI v3.3 â€” DocumentaciÃ³n TÃ©cnica**
Ãšltima actualizaciÃ³n: Marzo 2026

---

## Tabla de Contenidos

1. [Â¿QuÃ© es PPM?](#1-quÃ©-es-ppm)
2. [TAiPrompts â€” IntegraciÃ³n con Prompts](#2-taiprompts--integraciÃ³n-con-prompts)
   - [Propiedad PPMRegistryUrl](#21-propiedad-ppmregistryurl)
   - [SearchPPM â€” Buscar prompts](#22-searchppm--buscar-prompts)
   - [LoadFromPPM â€” Importar un prompt](#23-loadfromppm--importar-un-prompt)
   - [ConversiÃ³n de placeholders](#24-conversiÃ³n-de-placeholders)
3. [TAiFunctions â€” IntegraciÃ³n con Herramientas MCP](#3-taifunctions--integraciÃ³n-con-herramientas-mcp)
   - [SearchPPMMCP â€” Descubrir herramientas](#31-searchppmmcp--descubrir-herramientas)
   - [ImportMCPFromPPM â€” Registrar una herramienta](#32-importmcpfromppm--registrar-una-herramienta)
4. [Ejemplos completos](#4-ejemplos-completos)
5. [Referencia de la API REST de PPM](#5-referencia-de-la-api-rest-de-ppm)
6. [Archivos fuente](#6-archivos-fuente)

---

## 1. Â¿QuÃ© es PPM?

**PPM (PascalAI Package Manager)** es un registry pÃºblico de paquetes para el ecosistema Pascal/Delphi AI. Permite publicar y consumir:

| Tipo | DescripciÃ³n |
|------|-------------|
| `prompt` | Plantillas de prompts reutilizables con variables `{{nombre}}` |
| `mcp` | Definiciones de herramientas MCP con JSON Schema |
| `pai` | Paquetes de librerÃ­as Pascal AI |
| `clib` | Bindings de librerÃ­as C |

**URL oficial del registry:** `https://registry.pascalai.org`

MakerAI se integra con los tipos `prompt` y `mcp` a travÃ©s de `TAiPrompts` y `TAiFunctions` respectivamente. Los endpoints pÃºblicos de bÃºsqueda y descarga **no requieren autenticaciÃ³n**.

---

## 2. TAiPrompts â€” IntegraciÃ³n con Prompts

Archivo fuente: `Source/Core/uMakerAi.Prompts.pas`

### 2.1 Propiedad PPMRegistryUrl

```pascal
property PPMRegistryUrl: String;  // published
```

URL base del registry PPM. Por defecto apunta al registry oficial. Solo es necesario cambiarla si se usa una instancia privada del servidor.

```pascal
// Usar el registry oficial (por defecto, no hace falta asignarlo)
AiPrompts1.PPMRegistryUrl := 'https://registry.pascalai.org';

// Usar un registry privado interno
AiPrompts1.PPMRegistryUrl := 'http://mi-servidor-interno:8080';
```

La propiedad es visible en el Object Inspector del IDE y se puede configurar en tiempo de diseÃ±o.

---

### 2.2 SearchPPM â€” Buscar prompts

```pascal
function SearchPPM(
  const AQuery: String;
  const AType: String = 'prompt';
  APage: Integer = 1;
  APerPage: Integer = 20
): TJSONObject;
```

Busca paquetes en el registry. Devuelve el JSON de resultados. **El llamador es responsable de liberar el objeto devuelto.**

**ParÃ¡metros:**

| ParÃ¡metro | Tipo | DescripciÃ³n |
|-----------|------|-------------|
| `AQuery` | String | Texto de bÃºsqueda (busca en nombre y descripciÃ³n) |
| `AType` | String | Filtro de tipo: `'prompt'`, `'mcp'`, `'pai'`, `'clib'` |
| `APage` | Integer | PÃ¡gina de resultados (base 1) |
| `APerPage` | Integer | Resultados por pÃ¡gina (mÃ¡ximo 100) |

**Estructura del JSON devuelto:**

```json
{
  "packages": [
    {
      "name": "code-review",
      "type": "prompt",
      "description": "Prompt para revisiÃ³n de cÃ³digo con anÃ¡lisis de seguridad",
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

**Ejemplo de uso:**

```pascal
var
  LResult: TJSONObject;
  LPackages: TJSONArray;
  I: Integer;
begin
  LResult := AiPrompts1.SearchPPM('code review');
  if not Assigned(LResult) then
  begin
    ShowMessage('Error al conectar con el registry.');
    Exit;
  end;
  try
    LPackages := LResult.GetValue<TJSONArray>('packages');
    for I := 0 to LPackages.Count - 1 do
    begin
      var LPkg := LPackages.Items[I] as TJSONObject;
      Memo1.Lines.Add(Format('%s v%s â€” %s',
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

### 2.3 LoadFromPPM â€” Importar un prompt

```pascal
function LoadFromPPM(
  const AName: String;
  const AVersion: String = ''
): TAiPromptItem;
```

Descarga un prompt del registry y lo agrega a la colecciÃ³n `Items` del componente. Si ya existe un prompt con el mismo nombre, lo actualiza en lugar de duplicarlo.

**ParÃ¡metros:**

| ParÃ¡metro | Tipo | DescripciÃ³n |
|-----------|------|-------------|
| `AName` | String | Nombre exacto del paquete en el registry |
| `AVersion` | String | VersiÃ³n a descargar. Si estÃ¡ vacÃ­o, resuelve automÃ¡ticamente la Ãºltima versiÃ³n disponible |

**Retorno:** `TAiPromptItem` cargado, o `nil` si el paquete no existe o hay un error de red.

**Ejemplo bÃ¡sico:**

```pascal
var
  LItem: TAiPromptItem;
begin
  // Cargar la Ãºltima versiÃ³n disponible
  LItem := AiPrompts1.LoadFromPPM('code-review');
  if Assigned(LItem) then
    ShowMessage('Prompt cargado: ' + LItem.Nombre)
  else
    ShowMessage('No se pudo cargar el prompt.');
end;
```

**Ejemplo con versiÃ³n especÃ­fica:**

```pascal
LItem := AiPrompts1.LoadFromPPM('sql-generator', '2.1.0');
```

**Usar el prompt despuÃ©s de importarlo:**

```pascal
// DespuÃ©s de LoadFromPPM, el prompt estÃ¡ disponible como cualquier otro:
var LTexto := AiPrompts1.GetTemplate('code-review', ['language=Delphi', 'focus=security']);

// Con TStringList:
var LParams := TStringList.Create;
try
  LParams.Values['language'] := 'Delphi';
  LParams.Values['focus'] := 'performance';
  LTexto := AiPrompts1.GetTemplate('code-review', LParams);
finally
  LParams.Free;
end;
```

---

### 2.4 ConversiÃ³n de placeholders

Los prompts en PPM usan la sintaxis `{{nombre_variable}}`. Al importarlos con `LoadFromPPM`, MakerAI los convierte **automÃ¡ticamente** al formato nativo `<#nombre_variable>`.

| Formato PPM | Formato MakerAI | DescripciÃ³n |
|-------------|-----------------|-------------|
| `{{language}}` | `<#language>` | Variable de texto simple |
| `{{code_to_review}}` | `<#code_to_review>` | Variable con guiÃ³n bajo |
| `{{focus}}` | `<#focus>` | Variable de foco |

**Ejemplo de prompt en PPM (`code-review.prompt`):**

```
Eres un revisor de cÃ³digo experto en {{language}}.

Analiza el siguiente cÃ³digo:

{{code_to_review}}

Aspectos a revisar: {{focus}}
```

**DespuÃ©s de `LoadFromPPM`, el prompt queda en MakerAI como:**

```
Eres un revisor de cÃ³digo experto en <#language>.

Analiza el siguiente cÃ³digo:

<#code_to_review>

Aspectos a revisar: <#focus>
```

---

## 3. TAiFunctions â€” IntegraciÃ³n con Herramientas MCP

Archivo fuente: `Source/Tools/uMakerAi.Tools.Functions.pas`

Los paquetes MCP en PPM contienen un **JSON Schema** que describe quÃ© parÃ¡metros acepta una herramienta. A diferencia de los prompts, la herramienta MCP en sÃ­ (el servidor que la ejecuta) no estÃ¡ incluida en PPM â€” el registry funciona como **catÃ¡logo de descubrimiento**. El desarrollador debe configurar la URL o comando del servidor MCP por separado.

---

### 3.1 SearchPPMMCP â€” Descubrir herramientas

```pascal
function SearchPPMMCP(
  const AQuery: String;
  APage: Integer = 1;
  APerPage: Integer = 20;
  const ARegistryUrl: String = 'https://registry.pascalai.org'
): TJSONObject;
```

Busca herramientas MCP disponibles en el registry. El resultado incluye el JSON Schema de cada herramienta inline. **El llamador es responsable de liberar el objeto devuelto.**

**Ejemplo de JSON devuelto:**

```json
{
  "tools": [
    {
      "name": "mcp-web-search",
      "description": "BÃºsqueda web con Brave Search API",
      "version": "1.2.0",
      "downloads": 3500,
      "schema": {
        "type": "object",
        "title": "Web Search",
        "properties": {
          "query": { "type": "string", "description": "TÃ©rmino de bÃºsqueda" },
          "count": { "type": "integer", "description": "NÃºmero de resultados" }
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

**Ejemplo de uso:**

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
      ListBox1.Items.Add(Format('%s â€” %s',
        [LTool.GetValue<String>('name'),
         LTool.GetValue<String>('description')]));
    end;
  finally
    LResult.Free;
  end;
end;
```

---

### 3.2 ImportMCPFromPPM â€” Registrar una herramienta

```pascal
function ImportMCPFromPPM(
  const AName: String;
  const AVersion: String = '';
  const ARegistryUrl: String = 'https://registry.pascalai.org'
): TMCPClientItem;
```

Registra una herramienta MCP del registry como un nuevo `TMCPClientItem` en la colecciÃ³n `MCPClients` del componente. El item se crea con:

- `TransportType = tpHttp`
- `URL = ''` (vacÃ­a â€” requiere configuraciÃ³n)
- `Enabled = False` (deshabilitado hasta configurar el servidor)

Si ya existe un cliente con el mismo nombre, devuelve el existente sin duplicar.

**ParÃ¡metros:**

| ParÃ¡metro | Tipo | DescripciÃ³n |
|-----------|------|-------------|
| `AName` | String | Nombre del paquete MCP en el registry |
| `AVersion` | String | VersiÃ³n especÃ­fica, o vacÃ­o para la Ãºltima |
| `ARegistryUrl` | String | URL del registry (por defecto: oficial) |

**Flujo de uso tÃ­pico:**

```pascal
var
  LItem: TMCPClientItem;
begin
  // 1. Importar del registry (crea stub deshabilitado)
  LItem := AiFunctions1.ImportMCPFromPPM('mcp-web-search');
  if not Assigned(LItem) then
  begin
    ShowMessage('Herramienta no encontrada en el registry.');
    Exit;
  end;

  // 2. Configurar la URL del servidor MCP real
  LItem.Params.Values['URL'] := 'http://localhost:3000/mcp';

  // 3. Habilitar y sincronizar
  LItem.Enabled := True;
  LItem.UpdateClientProperties;

  // 4. Inicializar la conexiÃ³n
  if LItem.MCPClient <> nil then
    LItem.MCPClient.Initialize;
end;
```

---

## 4. Ejemplos completos

### Ejemplo 1 â€” Cargar un prompt de PPM y usarlo en un chat

```pascal
procedure TForm1.BtnCargarPromptClick(Sender: TObject);
var
  LItem: TAiPromptItem;
  LPrompt: String;
begin
  // Importar desde PPM
  LItem := AiPrompts1.LoadFromPPM('delphi-code-review');
  if not Assigned(LItem) then
  begin
    ShowMessage('No se encontrÃ³ el prompt en PPM.');
    Exit;
  end;

  // Sustituir variables y enviar al LLM
  LPrompt := AiPrompts1.GetTemplate('delphi-code-review',
    ['language=Delphi', 'focus=memory management', 'code=' + Memo1.Text]);

  AiConnection1.NewChat;
  AiConnection1.Run(LPrompt);
end;
```

---

### Ejemplo 2 â€” Explorar el catÃ¡logo de prompts en una lista

```pascal
procedure TForm1.BtnBuscarClick(Sender: TObject);
var
  LResult: TJSONObject;
  LPackages: TJSONArray;
begin
  ListBox1.Clear;
  LResult := AiPrompts1.SearchPPM(EdtBusqueda.Text, 'prompt', 1, 50);
  if not Assigned(LResult) then
  begin
    ShowMessage('Error al conectar con registry.pascalai.org');
    Exit;
  end;
  try
    LPackages := LResult.GetValue<TJSONArray>('packages');
    for var I := 0 to LPackages.Count - 1 do
    begin
      var LPkg := LPackages.Items[I] as TJSONObject;
      // Guardar el nombre del paquete en el Data del item
      ListBox1.Items.AddObject(
        Format('[v%s] %s â€” %s', [
          LPkg.GetValue<String>('version'),
          LPkg.GetValue<String>('name'),
          LPkg.GetValue<String>('description')
        ]),
        TObject(LPackages.Items[I])  // referencia temporal
      );
    end;
    LblTotal.Text := Format('%d prompts encontrados', [LResult.GetValue<Integer>('total')]);
  finally
    LResult.Free;
  end;
end;

// Al hacer doble clic en la lista, importar el prompt seleccionado
procedure TForm1.ListBox1DblClick(Sender: TObject);
var
  LNombre: String;
  LItem: TAiPromptItem;
begin
  if ListBox1.ItemIndex < 0 then Exit;
  // Extraer nombre del texto "[v1.0.0] nombre-prompt â€” descripciÃ³n"
  LNombre := ListBox1.Items[ListBox1.ItemIndex];
  LNombre := Copy(LNombre, Pos('] ', LNombre) + 2, MaxInt);
  LNombre := Copy(LNombre, 1, Pos(' â€” ', LNombre) - 1);

  LItem := AiPrompts1.LoadFromPPM(LNombre);
  if Assigned(LItem) then
    ShowMessage('Prompt "' + LItem.Nombre + '" importado correctamente.')
  else
    ShowMessage('Error al importar el prompt.');
end;
```

---

### Ejemplo 3 â€” Descubrir e integrar una herramienta MCP

```pascal
procedure TForm1.BtnIntegrarMCPClick(Sender: TObject);
var
  LResult: TJSONObject;
  LTools: TJSONArray;
  LNombre: String;
  LItem: TMCPClientItem;
begin
  // Buscar calculadoras disponibles
  LResult := AiFunctions1.SearchPPMMCP('calculator');
  if not Assigned(LResult) then Exit;
  try
    LTools := LResult.GetValue<TJSONArray>('tools');
    if LTools.Count = 0 then
    begin
      ShowMessage('No se encontraron herramientas MCP de tipo "calculator".');
      Exit;
    end;
    LNombre := (LTools.Items[0] as TJSONObject).GetValue<String>('name');
  finally
    LResult.Free;
  end;

  // Importar la primera encontrada
  LItem := AiFunctions1.ImportMCPFromPPM(LNombre);
  if not Assigned(LItem) then Exit;

  // Completar configuraciÃ³n con la URL del servidor local
  LItem.Params.Values['URL'] := 'http://localhost:4000/mcp';
  LItem.Enabled := True;
  LItem.UpdateClientProperties;

  if Assigned(LItem.MCPClient) then
    LItem.MCPClient.Initialize;

  ShowMessage(Format('Herramienta "%s" integrada y lista para usar.', [LNombre]));
end;
```

---

## 5. Referencia de la API REST de PPM

Los mÃ©todos de MakerAI llaman internamente a estos endpoints. Se documentan aquÃ­ para referencia o para implementar llamadas directas.

| Endpoint | MÃ©todo | DescripciÃ³n |
|----------|--------|-------------|
| `/v1/search?q=...&type=prompt` | GET | Buscar paquetes |
| `/v1/packages/:name` | GET | Info de un paquete (versiones, autor, etc.) |
| `/v1/packages/:name/:version/raw` | GET | Texto plano del prompt (sin sustituciÃ³n) |
| `/v1/packages/:name/:version/render?var=val` | GET | Prompt con variables sustituidas (server-side) |
| `/v1/mcp/discover?q=...` | GET | Buscar herramientas MCP con schemas inline |
| `/v1/packages/:name/:version/schema` | GET | JSON Schema de una herramienta MCP |

**Notas:**
- Todos los endpoints de consulta son **pÃºblicos** (no requieren autenticaciÃ³n).
- La autenticaciÃ³n (`Authorization: Bearer ppm_...`) solo es necesaria para publicar paquetes.
- La versiÃ³n `latest` no existe como path literal â€” `LoadFromPPM` y `ImportMCPFromPPM` la resuelven consultando el endpoint de info del paquete y seleccionando la primera versiÃ³n no anulada (*yanked*).

---

## 6. Archivos fuente

| Archivo | Contenido relevante |
|---------|---------------------|
| `Source/Core/uMakerAi.Prompts.pas` | `TAiPrompts`, `TAiPromptItem`, mÃ©todos PPM para prompts |
| `Source/Tools/uMakerAi.Tools.Functions.pas` | `TAiFunctions`, `TMCPClientItems`, mÃ©todos PPM para MCP |

### Constantes y defaults

```pascal
// uMakerAi.Prompts.pas
const
  PPM_DEFAULT_REGISTRY = 'https://registry.pascalai.org';

// uMakerAi.Tools.Functions.pas
// La URL por defecto se pasa como valor por defecto del parÃ¡metro ARegistryUrl:
//   const ARegistryUrl: String = 'https://registry.pascalai.org'
```

### Dependencias aÃ±adidas

Los dos archivos usan:
- `System.Net.HttpClient` â€” cliente HTTP (`THTTPClient`, `IHTTPResponse`)
- `System.NetEncoding` â€” codificaciÃ³n de parÃ¡metros URL (`TNetEncoding.URL.Encode`)
- `System.RegularExpressions` â€” conversiÃ³n de placeholders `{{var}}` â†’ `<#var>` (solo en Prompts)

Estas unidades forman parte del RTL estÃ¡ndar de Delphi y estÃ¡n disponibles desde Delphi 10.4 Sydney.
