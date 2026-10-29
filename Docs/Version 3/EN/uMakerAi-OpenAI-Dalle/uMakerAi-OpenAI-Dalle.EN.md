# TAiDalle — Image Generation and Editing with OpenAI

**Unit:** `uMakerAi.OpenAi.Dalle`  
**Components:** `TAiDalle`, `TAiDalleImageTool`  
**MakerAI Version:** 3.4+  
**Last updated:** 04/28/2026

---

## Contents

1. [General overview](#1-general-overview)
2. [Types and enumerations](#2-types-and-enumerations)
3. [TAiDalleImage — result object](#3-taidalleimage--result-object)
4. [TAiDalle — main component](#4-taidalle--main-component)
   - 4.1 [Properties](#41-properties)
   - 4.2 [Generate method](#42-generate-method)
   - 4.3 [Edit method](#43-edit-method)
   - 4.4 [Variation method](#44-variation-method)
   - 4.5 [Upscale method](#45-upscale-method)
   - 4.6 [Streaming](#46-streaming)
5. [TAiDalleImageTool — integration with TAiChatConnection](#5-taidalleimagetool--integration-with-taichatconnection)
6. [Model compatibility](#6-model-compatibility)
7. [API Key](#7-api-key)
8. [Complete examples](#8-complete-examples)

---

## 1. General overview

`TAiDalle` is a Delphi component (`TComponent`) that wraps the OpenAI Images API (`/v1/images/`). It can be used in two ways:

**Standalone mode** — direct calls to `Generate`, `Edit`, `Variation` without a chat:
```pascal
Dalle := TAiDalle.Create(nil);
Dalle.Model  := imGptImage2;
Dalle.ApiKey := '@OPENAI_API_KEY';
Img := Dalle.Generate('a red panda coding', '', is1024x1024);
```

**Integrated mode** — connected to `TAiChatConnection` through `TAiDalleImageTool`. When the model has `SessionCaps=[cap_GenImage]` and `ModelCaps=[]`, the framework detects the gap and delegates generation to the tool automatically:
```pascal
Tool := TAiDalleImageTool.Create(nil);
Tool.ApiKey := '@OPENAI_API_KEY';
Tool.Model  := imGptImage2;
AiConn.ChatTools.ImageTool := Tool;
AiConn.Run('Generate an image of an astronaut cat');
```

---

## 2. Types and enumerations

### TAiImageModel — available models

| Value | API string | Notes |
|-------|-----------|-------|
| `imDallE2` | `dall-e-2` | Deprecated May 2026. Supports Variation |
| `imDallE3` | `dall-e-3` | Deprecated May 2026. n=1 always |
| `imGptImage1` | `gpt-image-1` | Current. Supports streaming |
| `imGptImage1Mini` | `gpt-image-1-mini` | Faster and cheaper. Supports streaming |
| `imGptImage15` | `gpt-image-1.5` | Intermediate. Supports streaming |
| `imGptImage2` | `gpt-image-2` | **Most recent.** No streaming. n=1..8 max |
| `imChatGptImageLatest` | `chatgpt-image-latest` | Alias to the most recent model. Supports streaming |
| `imSDXL` | `sdxl` | Custom endpoint (not official OpenAI) |

### TAiImageSize — image sizes

| Value | Resolution | Compatible with |
|-------|-----------|----------------|
| `is256x256` | 256×256 | dall-e-2 |
| `is512x512` | 512×512 | dall-e-2 |
| `is768x768` | 768×768 | SDXL |
| `is832x1216` | 832×1216 | SDXL portrait |
| `is1024x1024` | 1024×1024 | All |
| `is1024x1536` | 1024×1536 | gpt-image-* portrait |
| `is1024x1792` | 1024×1792 | dall-e-3 portrait |
| `is1216x832` | 1216×832 | SDXL landscape |
| `is1536x1024` | 1536×1024 | gpt-image-* landscape |
| `is1792x1024` | 1792×1024 | dall-e-3 landscape |
| `isAuto` | auto | GPT Image only (the API chooses) |
| `is3840x2160` | 3840×2160 | gpt-image-2 (4K, experimental) |

### TAiImageQuality — generation quality

| Value | API string | Compatible with |
|-------|-----------|----------------|
| `iqAuto` | *(not sent)* | All (default) |
| `iqStandard` | `standard` | dall-e-3 |
| `iqHD` | `hd` | dall-e-3 |
| `iqHigh` | `high` | gpt-image-* |
| `iqMedium` | `medium` | gpt-image-* |
| `iqLow` | `low` | gpt-image-* |

> **dall-e-3:** use `iqHD` for maximum quality (mapped to `'hd'`). `iqHigh` also enables HD.  
> **gpt-image-*:** use `iqHigh`/`iqMedium`/`iqLow`. `iqAuto` lets the API choose.

### TAiImageOutputFormat — output format

| Value | Format | Notes |
|-------|---------|-------|
| `ifPng` | PNG | Default. Does not require sending a parameter |
| `ifJpeg` | JPEG | Supports `OutputCompression` |
| `ifWebp` | WebP | Supports `OutputCompression` |

> Only available on GPT Image models. dall-e-2 and dall-e-3 always return PNG.

### TAiImageBackground — image background

| Value | API string | Notes |
|-------|-----------|-------|
| `ibAuto` | *(not sent)* | Default |
| `ibTransparent` | `transparent` | gpt-image-1/mini/1.5 only. **NOT gpt-image-2** |
| `ibOpaque` | `opaque` | All GPT Image models |

### TAiImageStyle — style (dall-e-3 only)

| Value | API string |
|-------|-----------|
| `isVivid` | `vivid` |
| `isNatural` | `natural` |

### TAiImageModeration — content moderation

| Value | API string | Effect |
|-------|-----------|--------|
| `imodAuto` | *(not sent)* | Default — standard moderation |
| `imodLow` | `low` | Reduced moderation for specific use cases |

### TAiInputFidelity — edit fidelity (Edit only)

| Value | API string | Effect |
|-------|-----------|--------|
| `ifdDefault` | *(not sent)* | Default |
| `ifdHigh` | `high` | Preserves the original image as much as possible |
| `ifdLow` | `low` | Allows more creativity in the edit |

> **gpt-image-2:** `InputFidelity` is ignored — the API always applies high fidelity automatically.

### TAiImageResponseFormat — response format (dall-e-2/3 only)

| Value | Effect |
|-------|--------|
| `irfUrl` | Responds with a temporary URL |
| `irfBase64Json` | Responds with the image in base64 |

> GPT Image models **always** respond in base64. This parameter is ignored for them.

---

## 3. TAiDalleImage — result object

`TAiDalleImage` is the class that contains a generated image. It is returned by `Generate`, `Edit`, and `Variation`.

**Do not free manually** — it belongs to the internal `FImages` array of `TAiDalle` and is freed on the next call or when `TAiDalle` is destroyed.

### TAiDalleImage properties

| Property | Type | Description |
|-----------|------|-------------|
| `Image` | `TMemoryStream` | Stream with the image bytes. If received by URL, downloads when accessed. Always positioned at 0 |
| `Base64` | `string` | Base64 representation of the image |
| `UrlFile` | `string` | Temporary URL (dall-e-2/3 only with `irfUrl`). Empty in GPT Image |
| `RevisedPrompt` | `string` | Prompt revised/expanded by the API (dall-e-3) |
| `Background` | `string` | Background value received in the response |
| `OutputFormat` | `string` | Output format received (`png`, `jpeg`, `webp`) |
| `Quality` | `string` | Quality received in the response |
| `Size` | `string` | Resolution received (e.g. `"1024x1024"`) |
| `Usage` | `TJSONObject` | Token usage if the API includes it. May be `nil` |

### Save the image to disk

```pascal
var
  Img: TAiDalleImage;
  FS: TFileStream;
begin
  Img := Dalle.Generate('a blue dragon', '', is1024x1024);
  if Assigned(Img) and (Img.Image.Size > 0) then
  begin
    FS := TFileStream.Create('dragon.png', fmCreate);
    try
      Img.Image.Position := 0;
      FS.CopyFrom(Img.Image, Img.Image.Size);
    finally
      FS.Free;
    end;
  end;
end;
```

---

## 4. TAiDalle — main component

### 4.1 Properties

| Property | Type | Default | Description |
|-----------|------|---------|-------------|
| `ApiKey` | `string` | — | OpenAI API key. Supports `@VAR_NAME` to read from an environment variable |
| `Url` | `string` | `https://api.openai.com/v1/` | Base URL. Change for proxies or compatible endpoints |
| `Model` | `TAiImageModel` | `imDallE3` | Model to use |
| `Quality` | `TAiImageQuality` | `iqAuto` | Generation quality |
| `Style` | `TAiImageStyle` | `isVivid` | Visual style (dall-e-3 only) |
| `ResponseFormat` | `TAiImageResponseFormat` | `irfUrl` | URL or base64 (dall-e-2/3 only) |
| `Background` | `TAiImageBackground` | `ibAuto` | Background (GPT Image only, not gpt-image-2 transparent) |
| `OutputFormat` | `TAiImageOutputFormat` | `ifPng` | Output format (GPT Image only) |
| `OutputCompression` | `Integer` | `0` | Compression 0-100 for jpeg/webp. 0 = do not send |
| `Moderation` | `TAiImageModeration` | `imodAuto` | Moderation level (GPT Image only) |
| `InputFidelity` | `TAiInputFidelity` | `ifdDefault` | Edit fidelity (not applicable to gpt-image-2) |
| `Stream` | `Boolean` | `False` | Enable SSE streaming (not available in gpt-image-2) |
| `PartialImages` | `Integer` | `1` | Number of partial images in streaming (0-3) |
| `NegativePrompt` | `TStrings` | — | Negative prompt (SDXL only) |
| `User` | `string` | `'user'` | User identifier for auditing |
| `Prompt` | `string` | — | Read-only. Last prompt sent |

**SDXL properties** (custom endpoint only):

| Property | Type | Default | Description |
|-----------|------|---------|-------------|
| `Steps` | `Integer` | `30` | Diffusion steps |
| `GuidanceScale` | `Single` | `7.0` | Guidance scale |
| `Seed` | `Int64` | `-1` | Seed (-1 = random) |
| `UseRefiner` | `Boolean` | `False` | Use SDXL-XL refiner |
| `Strength` | `Single` | `0` | img2img strength |
| `LoraPath` | `string` | — | Path to LoRA adapter |
| `AutoUpscale` | `Boolean` | `False` | Automatic upscale |
| `EnhanceFace` | `Boolean` | `False` | Face enhancement |

### 4.2 Generate method

```pascal
function Generate(
  const aPrompt        : string;         // Generation prompt
  const aNegativePrompt: string;         // Negative prompt (SDXL only; empty for OpenAI)
  ASize                : TAiImageSize;   // Desired resolution
  N                    : Integer = 1;    // Number of images (see limits per model)
  aImage               : TMemoryStream = nil  // Reference image (SDXL img2img only)
): TAiDalleImage;
```

Returns the **first generated image**. To access multiple images (N>1), use the internal array — although in most cases N=1 is sufficient.

**N limit per model:**

| Model | Maximum N |
|--------|---------|
| dall-e-2 | 10 |
| dall-e-3 | 1 (always) |
| gpt-image-1/mini/1.5 | 10 |
| **gpt-image-2** | **8** |
| chatgpt-image-latest | 10 |

**Basic example:**
```pascal
var
  Dalle: TAiDalle;
  Img  : TAiDalleImage;
begin
  Dalle := TAiDalle.Create(nil);
  try
    Dalle.ApiKey  := '@OPENAI_API_KEY';
    Dalle.Model   := imGptImage2;
    Dalle.Quality := iqHigh;

    Img := Dalle.Generate(
      'A futuristic Delphi IDE with holographic code floating in the air',
      '',          // negative prompt — empty for OpenAI
      is1024x1024  // size
    );

    if Assigned(Img) and (Img.Image.Size > 0) then
      Img.Image.SaveToFile('output.png');
  finally
    Dalle.Free;
  end;
end;
```

**Example with WebP + compression:**
```pascal
Dalle.Model             := imGptImage1;
Dalle.OutputFormat      := ifWebp;
Dalle.OutputCompression := 80;  // 80% quality
Dalle.Quality           := iqMedium;
Img := Dalle.Generate('landscape at sunset', '', is1536x1024);
```

**4K example with gpt-image-2:**
```pascal
Dalle.Model   := imGptImage2;
Dalle.Quality := iqHigh;
Img := Dalle.Generate('epic mountain range', '', is3840x2160);
// Note: 4K is experimental in gpt-image-2 and may be slower
```

### 4.3 Edit method

Edits one or more existing images using a prompt. Optionally accepts a mask for inpainting.

```pascal
function Edit(
  aMediaFiles: TAiMediaFiles;   // Input images (TAiMediaFiles = TList<TAiMediaFile>)
  aMaskFile  : TAiMediaFile;    // Optional mask (PNG with alpha channel). nil = no mask
  const aPrompt: string;        // Description of the edit
  ASize      : TAiImageSize;    // Output size
  N          : Integer = 1      // Number of variants
): TAiDalleImage;
```

**Model compatibility for Edit:**
- `imDallE2` — 1 image, with or without mask, PNG only
- `imGptImage1`, `imGptImage1Mini`, `imGptImage15`, `imGptImage2`, `imChatGptImageLatest` — up to 10 input images, PNG/JPEG/WebP

**Mask for inpainting:**
- Must be PNG with alpha channel (RGBA)
- **Transparent** areas (alpha=0) = areas to edit
- **Opaque** areas (alpha=255) = areas to preserve

**Prepare images with TAiMediaFile:**
```pascal
uses uMakerAi.Core;

var
  Dalle     : TAiDalle;
  MediaFiles: TAiMediaFiles;
  Img, Mask : TAiMediaFile;
  Result    : TAiDalleImage;
begin
  Dalle := TAiDalle.Create(nil);
  try
    Dalle.ApiKey := '@OPENAI_API_KEY';
    Dalle.Model  := imGptImage2;

    MediaFiles := TAiMediaFiles.Create;
    Img  := TAiMediaFile.Create;
    Img.LoadFromFile('photo.jpg');
    MediaFiles.Add(Img);

    // Without mask — global edit
    Result := Dalle.Edit(MediaFiles, nil,
      'Remove the background and replace with a sunny beach',
      is1024x1024);

    if Assigned(Result) then
      Result.Image.SaveToFile('edited.png');
  finally
    MediaFiles.Free;  // frees the internal TAiMediaFile objects
    Dalle.Free;
  end;
end;
```

**With mask (inpainting):**
```pascal
Mask := TAiMediaFile.Create;
Mask.LoadFromFile('mask.png');  // PNG RGBA: transparent=edit, opaque=preserve

Result := Dalle.Edit(MediaFiles, Mask,
  'Replace the masked area with a golden sunset sky',
  is1024x1024);
Mask.Free;
```

> **gpt-image-2 + InputFidelity:** This model ignores the `InputFidelity` property — it always processes in high fidelity automatically. It is not necessary to configure it.

### 4.4 Variation method

Generates variations of an existing image. **Only available for dall-e-2.**

```pascal
function Variation(
  aImageFile: TAiMediaFile;  // Square PNG image (256, 512, or 1024px)
  ASize     : TAiImageSize;  // Output size
  N         : Integer = 1    // Number of variations
): TAiDalleImage;
```

```pascal
Dalle.Model := imDallE2;

var OriginalImg := TAiMediaFile.Create;
OriginalImg.LoadFromFile('original.png');

var Variant := Dalle.Variation(OriginalImg, is1024x1024, 3);
// Returns the first variation; the others remain in the internal array

OriginalImg.Free;
```

### 4.5 Upscale method

Increases the resolution of an image using Real-ESRGAN (custom endpoint — not available in the official OpenAI API).

```pascal
function Upscale(
  aImage     : TAiMediaFile;
  AScale     : Integer = 2;         // Scale factor (2x, 4x)
  AFaceEnhance: Boolean = False     // Face-specific enhancement
): TAiMediaFile;
```

```pascal
Dalle.Url := 'http://my-custom-server/v1/';  // custom endpoint
var Upscaled := Dalle.Upscale(OriginalMediaFile, 4, True);
if Assigned(Upscaled) then
begin
  Upscaled.Content.SaveToFile('upscaled.png');
  Upscaled.Free;
end;
```

> `Upscale` returns a new `TAiMediaFile` that **must be freed** by the caller.

### 4.6 Streaming

SSE streaming allows receiving partial images during generation. Available on gpt-image-1, gpt-image-1-mini, gpt-image-1.5, and chatgpt-image-latest. **gpt-image-2 does NOT support streaming.**

**Activation:**
```pascal
Dalle.Model         := imGptImage1;
Dalle.Stream        := True;
Dalle.PartialImages := 2;  // 0-3 intermediate images
```

**Streaming events:**

```pascal
// Fires for each partial image received
Dalle.OnPartialImageReceived := procedure(Sender: TObject;
  const APartialImage: TAiDalleImage; AIndex: Integer)
begin
  // AIndex: 0, 1, 2... according to the number of partial images configured
  // APartialImage.Image has the intermediate state of the image
  TThread.Queue(nil, procedure
  begin
    // Update UI with the partial image
    ImageControl.Bitmap.LoadFromStream(APartialImage.Image);
    APartialImage.Free;  // the event transfers ownership to the handler
  end);
end;

// Fires when the final image is ready
Dalle.OnStreamCompleted := procedure(Sender: TObject;
  const AFinalImage: TAiDalleImage)
begin
  TThread.Queue(nil, procedure
  begin
    ImageControl.Bitmap.LoadFromStream(AFinalImage.Image);
    AFinalImage.Image.SaveToFile('final.png');
    AFinalImage.Free;
  end);
end;

// Fires if there is an error during streaming
Dalle.OnStreamError := procedure(Sender: TObject; const AErrorMessage: string)
begin
  TThread.Queue(nil, procedure
  begin
    ShowMessage('Streaming error: ' + AErrorMessage);
  end);
end;
```

> Streaming in `TAiDalle.Generate` is **blocking** on the calling thread. Run it in a separate thread or use `TTask.Run`.

---

## 5. TAiDalleImageTool — integration with TAiChatConnection

`TAiDalleImageTool` inherits from `TAiImageToolBase` and acts as a bridge between the conversational chat and `TAiDalle`. When `TAiChatConnection` detects the `cap_GenImage` gap, it delegates generation to this tool automatically.

### TAiDalleImageTool properties

All relevant `TAiDalle` properties are exposed as delegates:

| Property | Type | Description |
|-----------|------|-------------|
| `ApiKey` | `string` | API key (supports `@VAR_NAME`) |
| `Url` | `string` | Base URL |
| `Model` | `TAiImageModel` | Model to use |
| `Quality` | `TAiImageQuality` | Quality |
| `Style` | `TAiImageStyle` | Style (dall-e-3) |
| `OutputFormat` | `TAiImageOutputFormat` | Output format |
| `Background` | `TAiImageBackground` | Background |
| `OutputCompression` | `Integer` | jpeg/webp compression |
| `Moderation` | `TAiImageModeration` | Moderation |
| `InputFidelity` | `TAiInputFidelity` | Edit fidelity |
| `NegativePrompt` | `TStrings` | Negative prompt |
| `ImageSize` | `TAiImageSize` | Generated image size |
| `Dalle` | `TAiDalle` | Allows injecting a preconfigured `TAiDalle` |

### Registration in TAiChatConnection

For the framework to use `TAiDalleImageTool`, the model must be registered in `uMakerAi.Chat.Initializations.pas` with `SessionCaps=[cap_GenImage]` and `ModelCaps=[]`:

```pascal
// Already registered for OpenAI models:
TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'gpt-image-2',
  'ModelCaps',   '[]');
TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'gpt-image-2',
  'SessionCaps', '[cap_GenImage]');
TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'gpt-image-2',
  'Tool_Active', 'False');
```

### Basic usage with TAiChatConnection

```pascal
var
  AiConn : TAiChatConnection;
  Tool   : TAiDalleImageTool;
begin
  AiConn := TAiChatConnection.Create(nil);
  Tool   := TAiDalleImageTool.Create(nil);
  try
    // Configure the tool
    Tool.ApiKey    := '@OPENAI_API_KEY';
    Tool.Model     := imGptImage2;
    Tool.Quality   := iqHigh;
    Tool.ImageSize := is1024x1024;

    // Connect to chat
    AiConn.DriverName  := 'OpenAi';
    AiConn.Model       := 'gpt-image-2';
    AiConn.Params.Values['ApiKey'] := '@OPENAI_API_KEY';
    AiConn.ChatTools.ImageTool := Tool;
    AiConn.Params.Values['Asynchronous'] := 'True';

    // The chat interprets the prompt and generates the image
    AiConn.OnReceiveDataEnd := procedure(...)
    begin
      // ResMsg.MediaFiles[0] contains the generated image
    end;

    AiConn.Run('Generate a photorealistic image of a mountain at sunset');
  finally
    AiConn.ChatTools.ImageTool := nil;
    Tool.Free;
    AiConn.Free;
  end;
end;
```

### Injecting a preconfigured TAiDalle

```pascal
var
  LDalle: TAiDalle;
  LTool : TAiDalleImageTool;
begin
  LDalle        := TAiDalle.Create(nil);
  LDalle.ApiKey := '@OPENAI_API_KEY';
  LDalle.Model  := imGptImage2;
  LDalle.Quality := iqMedium;

  LTool       := TAiDalleImageTool.Create(nil);
  LTool.Dalle := LDalle;       // Inject the configured TAiDalle
  LTool.ImageSize := is1536x1024;

  AiConn.ChatTools.ImageTool := LTool;
  // ...

  // Upon freeing: LTool frees the original internal TAiDalle (framework component).
  // LDalle must be freed by the caller explicitly.
  LTool.Free;
  LDalle.Free;
end;
```

### Asynchronous mode (required for chat integration)

`TAiDalleImageTool.ExecuteImageGeneration` calls `TAiDalle.Generate` in a **blocking** manner inside the framework's background thread. This requires `TAiChatConnection` to be in asynchronous mode:

```pascal
AiConn.Params.Values['Asynchronous'] := 'True';  // REQUIRED for image generation with tool
// or:
AiConn.Params.Values['Asynchronous'] := 'True';
```

In synchronous mode, `TTask.Run` would cause `RunNew` to fire `DoDataEnd` before the image is ready.

---

## 6. Model compatibility

| Feature | dall-e-2 | dall-e-3 | gpt-image-1 | gpt-image-2 |
|----------------|---------|---------|------------|------------|
| Generate | ✅ | ✅ | ✅ | ✅ |
| Edit | ✅ (1 img) | ❌ | ✅ (up to 10) | ✅ (up to 10) |
| Variation | ✅ | ❌ | ❌ | ❌ |
| Streaming | ❌ | ❌ | ✅ | ❌ |
| Max images (N) | 10 | 1 | 10 | **8** |
| webp/jpeg format | ❌ | ❌ | ✅ | ✅ |
| Transparent background | ❌ | ❌ | ✅ | ❌ |
| Opaque background | ❌ | ❌ | ✅ | ✅ |
| response_format | ✅ | ✅ | ❌ | ❌ |
| input_fidelity (Edit) | ❌ | ❌ | ✅ | ❌ (auto) |
| Moderation | ❌ | ❌ | ✅ | ✅ |
| isAuto (size) | ❌ | ❌ | ✅ | ✅ |
| is3840x2160 (4K) | ❌ | ❌ | ❌ | ✅ (exp.) |
| Deprecated May 2026 | ✅ | ✅ | ❌ | ❌ |

---

## 7. API Key

`TAiDalle` supports two ways to configure the API key:

```pascal
// Literal (not recommended in source code)
Dalle.ApiKey := 'sk-proj-XXXXXXXXXXXXXXXX';

// Environment variable (recommended)
Dalle.ApiKey := '@OPENAI_API_KEY';
// Resolves GetEnvironmentVariable('OPENAI_API_KEY') at runtime
```

The resolution occurs in the `ApiKey` getter, transparent to the caller.

---

## 8. Complete examples

### Example 1: Simple generation with gpt-image-2

```pascal
procedure TForm1.ButtonGenerateClick(Sender: TObject);
var
  Dalle: TAiDalle;
  Img  : TAiDalleImage;
begin
  Dalle := TAiDalle.Create(nil);
  try
    Dalle.ApiKey  := '@OPENAI_API_KEY';
    Dalle.Model   := imGptImage2;
    Dalle.Quality := iqHigh;

    Img := Dalle.Generate(
      'A serene Japanese garden with cherry blossoms and a koi pond at golden hour',
      '',
      is1536x1024
    );

    if Assigned(Img) and (Img.Image.Size > 0) then
    begin
      Image1.Bitmap.LoadFromStream(Img.Image);
      Img.Image.SaveToFile(TPath.GetTempPath + 'garden.png');
    end;
  except
    on E: Exception do
      ShowMessage('Error: ' + E.Message);
  end;
  Dalle.Free;
end;
```

### Example 2: Editing with mask (inpainting)

```pascal
procedure EditWithMask(const ASourceFile, AMaskFile: string; const APrompt: string);
var
  Dalle    : TAiDalle;
  Files    : TAiMediaFiles;
  Source   : TAiMediaFile;
  Mask     : TAiMediaFile;
  Result   : TAiDalleImage;
begin
  Dalle  := TAiDalle.Create(nil);
  Files  := TAiMediaFiles.Create;
  Source := TAiMediaFile.Create;
  Mask   := TAiMediaFile.Create;
  try
    Dalle.ApiKey := '@OPENAI_API_KEY';
    Dalle.Model  := imGptImage2;

    Source.LoadFromFile(ASourceFile);
    Files.Add(Source);
    Mask.LoadFromFile(AMaskFile);  // PNG with alpha: transparent = edit

    Result := Dalle.Edit(Files, Mask, APrompt, is1024x1024);

    if Assigned(Result) then
      Result.Image.SaveToFile('edited_result.png');
  finally
    Files.Free;  // frees Source internally
    Mask.Free;
    Dalle.Free;
  end;
end;
```

### Example 3: Streaming with gpt-image-1

```pascal
procedure TForm1.GenerateWithStreaming;
var
  Dalle: TAiDalle;
begin
  Dalle := TAiDalle.Create(nil);

  Dalle.ApiKey      := '@OPENAI_API_KEY';
  Dalle.Model       := imGptImage1;
  Dalle.Stream      := True;
  Dalle.PartialImages := 2;

  Dalle.OnPartialImageReceived :=
    procedure(Sender: TObject; const Img: TAiDalleImage; Idx: Integer)
    begin
      TThread.Queue(nil, procedure
      begin
        StatusBar1.SimpleText := Format('Partial image %d received...', [Idx + 1]);
        ImagePreview.Bitmap.LoadFromStream(Img.Image);
        Img.Free;
      end);
    end;

  Dalle.OnStreamCompleted :=
    procedure(Sender: TObject; const Img: TAiDalleImage)
    begin
      TThread.Queue(nil, procedure
      begin
        ImageFinal.Bitmap.LoadFromStream(Img.Image);
        Img.Image.SaveToFile('streaming_result.png');
        StatusBar1.SimpleText := 'Generation complete.';
        Img.Free;
      end);
    end;

  // Run in a separate thread because Generate is blocking
  TTask.Run(procedure
  begin
    try
      Dalle.Generate('A cyberpunk city at night with neon lights', '', is1024x1024);
    finally
      TThread.Queue(nil, procedure begin Dalle.Free; end);
    end;
  end);
end;
```

### Example 4: Complete integration with TAiChatConnection

```pascal
procedure TForm1.SetupImageChat;
var
  Tool: TAiDalleImageTool;
begin
  // Tool: configure once, reuse
  Tool := TAiDalleImageTool.Create(Self);  // Self as owner for automatic management
  Tool.ApiKey    := '@OPENAI_API_KEY';
  Tool.Model     := imGptImage2;
  Tool.Quality   := iqHigh;
  Tool.ImageSize := is1024x1024;

  // Chat: configure
  AiConn.DriverName   := 'OpenAi';
  AiConn.Model        := 'gpt-image-2';
  AiConn.Params.Values['ApiKey'] := '@OPENAI_API_KEY';
  AiConn.ChatTools.ImageTool := Tool;
  AiConn.Params.Values['Asynchronous'] := 'True';  // REQUIRED for image generation

  AiConn.OnReceiveDataEnd :=
    procedure(Sender: TObject; ResMsg: TAiChatMessage; const Data: string)
    begin
      // If there is a generated image, it is in ResMsg.MediaFiles[0]
      if ResMsg.MediaFiles.Count > 0 then
      begin
        var MediaFile := ResMsg.MediaFiles[0];
        Image1.Bitmap.LoadFromStream(MediaFile.Content);
        Caption1.Text := ResMsg.Prompt;  // revised prompt or the original
      end;
    end;

  // The user writes naturally; the LLM decides whether to generate an image
  AiConn.Run('Generate an image of an astronaut playing guitar on the Moon');
end;
```

### Example 5: Variation with dall-e-2

```pascal
procedure TForm1.ButtonVariationClick(Sender: TObject);
var
  Dalle   : TAiDalle;
  Original: TAiMediaFile;
  Variant : TAiDalleImage;
begin
  Dalle    := TAiDalle.Create(nil);
  Original := TAiMediaFile.Create;
  try
    Dalle.ApiKey := '@OPENAI_API_KEY';
    Dalle.Model  := imDallE2;

    Original.LoadFromFile('original.png');  // Square PNG required

    Variant := Dalle.Variation(Original, is1024x1024);

    if Assigned(Variant) then
      Variant.Image.SaveToFile('variation.png');
  finally
    Original.Free;
    Dalle.Free;
  end;
end;
```

---

## Unit dependencies

To use `TAiDalle` or `TAiDalleImageTool`, add to `uses`:

```pascal
uses
  uMakerAi.OpenAi.Dalle,   // TAiDalle, TAiDalleImageTool, and all types/enums
  uMakerAi.Core,            // TAiMediaFile, TAiMediaFiles (for Edit/Variation)
  uMakerAi.Chat.Messages;   // TAiChatMessage (only if extending TAiImageToolBase)
```

For use with `TAiChatConnection`:
```pascal
uses
  uMakerAi.Chat.AiConnection,      // TAiChatConnection
  uMakerAi.Chat.Initializations,   // Driver registration (loads gpt-image-2)
  uMakerAi.OpenAi.Dalle;           // TAiDalleImageTool
```

---

*Documentation generated for MakerAI v3.4 — uMakerAi.OpenAi.Dalle.pas*  
*Author: Gustavo Enríquez — gustavoeenriquez@gmail.com*