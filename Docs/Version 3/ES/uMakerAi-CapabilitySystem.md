# Sistema de Capacidades: ModelCaps y SessionCaps

**MakerAI v3.3 â€” DocumentaciÃ³n tÃ©cnica**
Ãšltima actualizaciÃ³n: marzo 2026

---

## Ãndice

1. [IntroducciÃ³n](#1-introducciÃ³n)
2. [El enum TAiCapability](#2-el-enum-taicapability)
3. [ModelCaps vs SessionCaps](#3-modelcaps-vs-sessioncaps)
4. [Gap Analysis: el motor central](#4-gap-analysis-el-motor-central)
5. [ConfiguraciÃ³n via TAiChatFactory](#5-configuraciÃ³n-via-taichatfactory)
6. [ConfiguraciÃ³n en tiempo de ejecuciÃ³n](#6-configuraciÃ³n-en-tiempo-de-ejecuciÃ³n)
7. [Compatibilidad con el sistema legacy](#7-compatibilidad-con-el-sistema-legacy)
8. [Patrones de configuraciÃ³n frecuentes](#8-patrones-de-configuraciÃ³n-frecuentes)
9. [Referencia de capacidades por provider](#9-referencia-de-capacidades-por-provider)
10. [AÃ±adir un nuevo provider](#10-aÃ±adir-un-nuevo-provider)
11. [Referencia de archivos fuente](#11-referencia-de-archivos-fuente)

---

## 1. IntroducciÃ³n

MakerAI v3.3 introduce el **sistema unificado de capacidades** (`TAiCapabilities`), que reemplaza los cuatro parÃ¡metros legacy dispersos (`NativeInputFiles`, `NativeOutputFiles`, `ChatMediaSupports`, `EnabledFeatures`) por dos propiedades ortogonales y simples:

| Propiedad | Significado |
|-----------|-------------|
| `ModelCaps` | Lo que el modelo sabe hacer **de forma nativa** vÃ­a completions |
| `SessionCaps` | Lo que la sesiÃ³n **necesita** (puede superar las capacidades nativas) |

La diferencia entre ambas (`Gap = SessionCaps - ModelCaps`) determina quÃ© bridges y herramientas activa el orquestador automÃ¡ticamente antes de llamar a la API.

**Ventajas sobre el sistema anterior:**
- Una sola lÃ­nea describe completamente un modelo
- El bridge correcto se activa solo, sin cÃ³digo adicional
- Compatible hacia atrÃ¡s: los modelos configurados con el sistema legacy siguen funcionando sin cambios

---

## 2. El enum TAiCapability

Definido en `Source/Core/uMakerAi.Core.pas`:

```pascal
TAiCapability = (
  // ---- Entrada / ComprensiÃ³n (completions nativo) ----
  cap_Image,            // el modelo entiende imÃ¡genes entrantes
  cap_Audio,            // el modelo entiende/transcribe audio entrante
  cap_Video,            // el modelo entiende video entrante
  cap_Pdf,              // el modelo entiende PDFs entrantes
  cap_WebSearch,        // el modelo puede buscar en la web
  cap_Reasoning,        // el modelo tiene razonamiento extendido (CoT/thinking)
  cap_CodeInterpreter,  // el modelo puede ejecutar cÃ³digo
  cap_Memory,           // el modelo tiene memoria persistente
  cap_TextEditor,       // el modelo puede editar archivos de texto
  cap_ComputerUse,      // el modelo puede controlar el ordenador
  cap_Shell,            // el modelo puede ejecutar comandos shell

  // ---- Salida / GeneraciÃ³n (gap -> activa bridge automÃ¡tico) ----
  cap_GenImage,         // producir una imagen como output
  cap_GenAudio,         // producir audio como output (TTS)
  cap_GenVideo,         // producir video como output
  cap_GenReport,        // producir un reporte (PDF, HTML, XLSX)
  cap_ExtractCode       // post-procesar: extraer bloques de cÃ³digo de la respuesta
);

TAiCapabilities = set of TAiCapability;
```

### ClasificaciÃ³n conceptual

**Capacidades de entrada** (`cap_Image` .. `cap_Shell`): describen quÃ© tipos de contenido entiende el modelo de forma nativa en el endpoint de completions. Si el modelo no tiene una capacidad de entrada pero la sesiÃ³n la necesita, el orquestador ejecuta un **bridge de entrada** (transcripciÃ³n, descripciÃ³n de imagen, extracciÃ³n de texto de PDF) antes de enviar el prompt.

**Capacidades de generaciÃ³n** (`cap_GenImage` .. `cap_ExtractCode`): describen quÃ© tipo de contenido produce la sesiÃ³n como salida. Cuando hay gap en estas capacidades, el orquestador redirige la llamada al endpoint especializado (TTS, generaciÃ³n de imÃ¡genes, etc.) en lugar de completions.

---

## 3. ModelCaps vs SessionCaps

### ModelCaps â€” capacidades nativas del modelo

Representa exactamente lo que el modelo puede hacer a travÃ©s del endpoint de completions **sin intervenciÃ³n externa**. Es un hecho fijo del modelo: no cambia segÃºn las necesidades del usuario.

Ejemplos:
- `GPT-4.1`: puede procesar imÃ¡genes â†’ `ModelCaps = [cap_Image]`
- `dall-e-3`: solo genera imÃ¡genes, no hace completions â†’ `ModelCaps = []`
- `gemini-2.5-flash`: multimodal completo â†’ `ModelCaps = [cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]`

### SessionCaps â€” capacidades deseadas en la sesiÃ³n

Representa lo que el **usuario quiere** que la sesiÃ³n sea capaz de hacer. Puede coincidir con `ModelCaps` (sin gap, llamada directa) o superarla (con gap, se activan bridges).

Ejemplos:
- Quiero usar GPT-4o para generar audio TTS: `SessionCaps = [cap_Image, cap_GenAudio]` â†’ Gap = `[cap_GenAudio]` â†’ usa endpoint TTS de OpenAI
- Quiero usar Ollama (sin visiÃ³n) con imÃ¡genes: `SessionCaps = [cap_Image]` + `ModelCaps = []` â†’ Gap = `[cap_Image]` â†’ bridge de descripciÃ³n visual antes de completions

### RelaciÃ³n con los parÃ¡metros legacy

Al asignar `ModelCaps` y `SessionCaps`, el sistema sincroniza automÃ¡ticamente los parÃ¡metros legacy:

| Propiedad nueva | Sincroniza (legacy) |
|-----------------|---------------------|
| `ModelCaps` | `NativeInputFiles` + `ChatMediaSupports` |
| `SessionCaps` | `NativeOutputFiles` + `EnabledFeatures` |

Esta sincronizaciÃ³n ocurre en los setters `SetModelCaps` y `SetSessionCaps` (llamados tanto desde cÃ³digo como via RTTI al aplicar params de factory).

---

## 4. Gap Analysis: el motor central

El mÃ©todo `TAiChat.RunNew` calcula el gap en su primera lÃ­nea:

```pascal
Gap := FSessionCaps - FModelCaps;  // resta de conjuntos
```

Luego ejecuta tres fases:

### Fase 1: Bridge de entrada (solo en `cmConversation`)

Para cada archivo adjunto al mensaje que el modelo no soporta nativamente:

| Gap contiene | Tipo de archivo | Bridge activado |
|---|---|---|
| `cap_Audio` | `.mp3`, `.wav`, etc. | `InternalRunTranscription` â†’ convierte a texto |
| `cap_Image` | `.png`, `.jpg`, etc. | `InternalRunImageDescription` â†’ describe la imagen |
| `cap_Pdf` | `.pdf` | `InternalRunPDFDescription` â†’ extrae/describe el PDF |

Los archivos ya procesados (`MF.Procesado = True`) se saltan. TambiÃ©n hay prioridad 1: si el evento `OnProcessMediaFile` estÃ¡ asignado, se usa antes del bridge automÃ¡tico.

### Fase 2: Grounding (siempre, sin guarda de modo)

| Gap contiene | AcciÃ³n |
|---|---|
| `cap_WebSearch` | `InternalRunWebSearch` â€” busca en la web e inyecta resultados en el contexto |

### Fase 3: OrquestaciÃ³n de salida (en `cmConversation`)

El gap determina quÃ© endpoint se usa. Se evalÃºa en orden de prioridad:

| Gap contiene | MÃ©todo invocado |
|---|---|
| `cap_GenVideo` | `InternalRunImageVideoGeneration` |
| `cap_GenImage` | `InternalRunImageGeneration` |
| `cap_GenAudio` | `InternalRunSpeechGeneration` |
| `cap_GenReport` | `InternalRunReport` |
| (vacÃ­o) | `InternalRunCompletions` (conversaciÃ³n normal) |

`cap_ExtractCode` no redirige el endpoint: lo gestiona internamente `InternalRunCompletions` mediante el parÃ¡metro legacy `Tfc_ExtractTextFile in NativeOutputFiles` (sincronizado por `SyncLegacyFromSessionCaps`).

### Modos forzados

Si `ChatMode` es distinto de `cmConversation`, el Gap se ignora en Fase 1 y Fase 3, y se llama al mÃ©todo correspondiente directamente:

```pascal
cmImageGeneration  â†’ InternalRunImageGeneration  (siempre)
cmVideoGeneration  â†’ InternalRunImageVideoGeneration
cmSpeechGeneration â†’ InternalRunSpeechGeneration
cmWebSearch        â†’ InternalRunWebSearch
cmReportGeneration â†’ InternalRunReport
cmTranscription    â†’ InternalRunTranscription (primer audio del mensaje)
```

---

## 5. ConfiguraciÃ³n via TAiChatFactory

La forma estÃ¡ndar de configurar capacidades es en `Source/Chat/uMakerAi.Chat.Initializations.pas`, usando `TAiChatFactory.Instance.RegisterUserParam`.

### Niveles de configuraciÃ³n

Los parÃ¡metros tienen tres niveles (de menor a mayor prioridad):

1. **Defaults del driver** â€” `RegisterDefaultParams` en la clase del driver
2. **Defaults globales del provider** â€” `RegisterUserParam(Driver, Param, Value)`
3. **Override por modelo** â€” `RegisterUserParam(Driver, Model, Param, Value)`

Un override de modelo siempre gana sobre el global del driver.

### Sintaxis

```pascal
// Default global para todo el provider
TAiChatFactory.Instance.RegisterUserParam('DriverName', 'ModelCaps',   '[cap_Image]');
TAiChatFactory.Instance.RegisterUserParam('DriverName', 'SessionCaps', '[cap_Image]');

// Override para un modelo especÃ­fico
TAiChatFactory.Instance.RegisterUserParam('DriverName', 'nombre-del-modelo', 'ModelCaps',   '[cap_Image, cap_Reasoning]');
TAiChatFactory.Instance.RegisterUserParam('DriverName', 'nombre-del-modelo', 'SessionCaps', '[cap_Image, cap_Reasoning]');
TAiChatFactory.Instance.RegisterUserParam('DriverName', 'nombre-del-modelo', 'ThinkingLevel', 'tlMedium');
```

### Formato de la string de capacidades

La string sigue el formato de un set de Pascal, usando los nombres exactos del enum `TAiCapability`:

```
'[]'                                        // conjunto vacÃ­o
'[cap_Image]'                               // una capacidad
'[cap_Image, cap_Reasoning]'                // varias capacidades
'[cap_Image, cap_Audio, cap_Video, cap_Pdf]'  // multimedia completo
```

El parser (en `ApplyParamsToChat`, vÃ­a RTTI `tkSet`) es sensible a mayÃºsculas/minÃºsculas: los nombres deben coincidir exactamente con los valores del enum.

### ParÃ¡metro ThinkingLevel

Para modelos con razonamiento extendido, se configura el nivel con `ThinkingLevel`:

| Valor | DescripciÃ³n |
|-------|-------------|
| `tlDefault` | Deja al provider elegir (generalmente Medium) |
| `tlLow` | Razonamiento mÃ­nimo â€” respuesta rÃ¡pida, bajo costo |
| `tlMedium` | Balance calidad/velocidad â€” valor recomendado |
| `tlHigh` | Razonamiento mÃ¡ximo â€” mayor calidad, mÃ¡s lento y costoso |

`ThinkingLevel` solo tiene efecto si `cap_Reasoning` estÃ¡ en `ModelCaps`. Si el modelo no tiene `cap_Reasoning`, el parÃ¡metro se ignora.

### Perfiles personalizados (aa_*)

Para crear variantes de un modelo con configuraciÃ³n diferente (ej. nivel de thinking distinto, caps reducidas), usar `RegisterCustomModel` + override:

```pascal
// Crea 'aa_o3-high' que usa internamente el modelo 'o3'
TAiChatFactory.Instance.RegisterCustomModel('OpenAi', 'aa_o3-high', 'o3');
TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'aa_o3-high', 'ThinkingLevel', 'tlHigh');

// Crea 'aa_gemini-3-pro-fast' con thinking reducido para respuestas rÃ¡pidas
TAiChatFactory.Instance.RegisterCustomModel('Gemini', 'aa_gemini-3-pro-fast', 'gemini-3-pro-preview');
TAiChatFactory.Instance.RegisterUserParam('Gemini', 'aa_gemini-3-pro-fast', 'ThinkingLevel', 'tlLow');
TAiChatFactory.Instance.RegisterUserParam('Gemini', 'aa_gemini-3-pro-fast', 'ModelCaps',
  '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch]');  // sin cap_Reasoning
TAiChatFactory.Instance.RegisterUserParam('Gemini', 'aa_gemini-3-pro-fast', 'SessionCaps',
  '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch]');
```

El prefijo `aa_` es una convenciÃ³n del proyecto para perfiles personalizados; no es obligatorio pero ayuda a distinguirlos de los modelos oficiales en listas desplegables.

---

## 6. ConfiguraciÃ³n en tiempo de ejecuciÃ³n

AdemÃ¡s de la factory, se pueden asignar `ModelCaps` y `SessionCaps` directamente sobre la instancia en cÃ³digo:

### Sobre TAiChatConnection

```pascal
// En tiempo de diseÃ±o (Inspector de Objetos) o en cÃ³digo
AiConnection.DriverName := 'OpenAi';
AiConnection.Model := 'gpt-4.1';

// Sobreescribir caps para esta sesiÃ³n especÃ­fica
AiConnection.ModelCaps   := [cap_Image, cap_Pdf];
AiConnection.SessionCaps := [cap_Image, cap_Pdf, cap_GenAudio];
// Gap = [cap_GenAudio] -> prÃ³ximo Run() usarÃ¡ endpoint TTS
```

### Sobre TAiChat directamente

```pascal
var Chat: TAiOpenChat;
Chat := TAiOpenChat.Create(nil);
Chat.ApiKey := '@OPENAI_API_KEY';
Chat.Model  := 'gpt-image-1';
Chat.ModelCaps   := [];
Chat.SessionCaps := [cap_GenImage];
// Gap = [cap_GenImage] -> Run() llamarÃ¡ a InternalRunImageGeneration
```

**Importante:** Al asignar `ModelCaps` o `SessionCaps` directamente, se activa `FNewSystemConfigured = True`, lo que impide que `EnsureNewSystemConfig` sobreescriba estos valores con la traducciÃ³n automÃ¡tica desde parÃ¡metros legacy.

### Consultar las caps actuales

```pascal
// Leer caps efectivas (despuÃ©s de aplicar params de factory)
var Gap: TAiCapabilities;
Gap := AiConnection.SessionCaps - AiConnection.ModelCaps;

if cap_GenAudio in Gap then
  ShowMessage('Esta sesiÃ³n generarÃ¡ audio via TTS');

if cap_Reasoning in AiConnection.ModelCaps then
  ShowMessage('Este modelo tiene razonamiento nativo');
```

---

## 7. Compatibilidad con el sistema legacy

### ParÃ¡metros legacy

El sistema anterior configuraba las capacidades mediante cuatro parÃ¡metros:

| ParÃ¡metro legacy | Tipo | DescripciÃ³n |
|---|---|---|
| `NativeInputFiles` | `TAiFileCategories` | Tipos de archivo que el modelo acepta nativamente |
| `NativeOutputFiles` | `TAiFileCategories` | Tipos de archivo que el modelo genera |
| `ChatMediaSupports` | `TAiChatMediaSupports` | Capacidades lÃ³gicas nativas del modelo |
| `EnabledFeatures` | `TAiChatMediaSupports` | Capacidades deseadas en la sesiÃ³n |

### TraducciÃ³n automÃ¡tica

Si un modelo fue configurado con el sistema legacy y **no** se asignaron `ModelCaps`/`SessionCaps` explÃ­citamente (`FNewSystemConfigured = False`), el mÃ©todo `EnsureNewSystemConfig` (llamado al inicio de cada `Run`) traduce automÃ¡ticamente:

```
ChatMediaSupports + NativeInputFiles/OutputFiles  â†’  ModelCaps
EnabledFeatures   + NativeOutputFiles             â†’  SessionCaps
```

Esta traducciÃ³n ocurre una sola vez por sesiÃ³n y es invisible para el usuario. El sistema legacy sigue funcionando sin ningÃºn cambio de cÃ³digo.

### Prioridad de configuraciÃ³n

```
1. ModelCaps/SessionCaps asignados explÃ­citamente  (FNewSystemConfigured=True)  â† Mayor prioridad
2. TraducciÃ³n automÃ¡tica desde legacy params         (FNewSystemConfigured=False)
3. Defaults del driver (RegisterDefaultParams)                                   â† Menor prioridad
```

### GuÃ­a de migraciÃ³n

Para migrar un driver existente al nuevo sistema:

```pascal
// Antes (legacy)
TAiChatFactory.Instance.RegisterUserParam('MiDriver', 'ChatMediaSupports', 'Tcm_Image,Tcm_Pdf');
TAiChatFactory.Instance.RegisterUserParam('MiDriver', 'EnabledFeatures',   'Tcm_Image,Tcm_Pdf');
TAiChatFactory.Instance.RegisterUserParam('MiDriver', 'NativeInputFiles',  'Tfc_Image,Tfc_Pdf');

// DespuÃ©s (nuevo sistema v3.3)
TAiChatFactory.Instance.RegisterUserParam('MiDriver', 'ModelCaps',   '[cap_Image, cap_Pdf]');
TAiChatFactory.Instance.RegisterUserParam('MiDriver', 'SessionCaps', '[cap_Image, cap_Pdf]');
```

No es necesario eliminar los parÃ¡metros legacy existentes si ya se configuran los nuevos: cuando `ModelCaps`/`SessionCaps` estÃ¡n presentes en los params de factory, el RTTI los aplica vÃ­a los setters que activan `FNewSystemConfigured = True`, ignorando la traducciÃ³n automÃ¡tica.

---

## 8. Patrones de configuraciÃ³n frecuentes

### PatrÃ³n 1: Modelo de texto puro (sin capacidades especiales)

```pascal
// Solo texto, sin tools
RegisterUserParam('Driver', 'ModelCaps',   '[]');
RegisterUserParam('Driver', 'SessionCaps', '[]');
RegisterUserParam('Driver', 'Tool_Active', 'False');
```

Resultado: `Gap = []` â†’ `InternalRunCompletions` directo.

### PatrÃ³n 2: Modelo con visiÃ³n nativa

```pascal
// El modelo puede ver imÃ¡genes directamente en completions
RegisterUserParam('Driver', 'ModelCaps',   '[cap_Image]');
RegisterUserParam('Driver', 'SessionCaps', '[cap_Image]');
RegisterUserParam('Driver', 'Tool_Active', 'True');
```

Resultado: `Gap = []` â†’ las imÃ¡genes van directas al API de completions.

### PatrÃ³n 3: Modelo multimodal completo (Gemini 2.5 Flash)

```pascal
RegisterUserParam('Gemini', 'gemini-2.5-flash', 'ModelCaps',
  '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
RegisterUserParam('Gemini', 'gemini-2.5-flash', 'SessionCaps',
  '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
```

Resultado: `Gap = []` â†’ todo va directo al completions nativo de Gemini.

### PatrÃ³n 4: Modelo con razonamiento (CoT/thinking)

```pascal
RegisterUserParam('Driver', 'modelo-reasoning', 'ModelCaps',    '[cap_Image, cap_Reasoning]');
RegisterUserParam('Driver', 'modelo-reasoning', 'SessionCaps',  '[cap_Image, cap_Reasoning]');
RegisterUserParam('Driver', 'modelo-reasoning', 'ThinkingLevel', 'tlMedium');
```

Resultado: el driver activa el modo de razonamiento extendido segÃºn el nivel configurado.

### PatrÃ³n 5: TTS via endpoint dedicado

```pascal
// ModelCaps vacÃ­o = no hace completions / no entiende inputs
// Gap = [cap_GenAudio] â†’ InternalRunSpeechGeneration
RegisterUserParam('Driver', 'modelo-tts', 'ModelCaps',    '[]');
RegisterUserParam('Driver', 'modelo-tts', 'SessionCaps',  '[cap_GenAudio]');
RegisterUserParam('Driver', 'modelo-tts', 'Tool_Active',  'False');
RegisterUserParam('Driver', 'modelo-tts', 'Voice',        'alloy');
```

### PatrÃ³n 6: GeneraciÃ³n de imagen via endpoint dedicado

```pascal
// ModelCaps vacÃ­o = usa endpoint de imagen, no completions
// Gap = [cap_GenImage] â†’ InternalRunImageGeneration
RegisterUserParam('Driver', 'modelo-imagen', 'ModelCaps',   '[]');
RegisterUserParam('Driver', 'modelo-imagen', 'SessionCaps', '[cap_GenImage]');
RegisterUserParam('Driver', 'modelo-imagen', 'Tool_Active', 'False');
```

### PatrÃ³n 7: GeneraciÃ³n de imagen NATIVA via completions (Gemini)

```pascal
// cap_GenImage en ModelCaps Y SessionCaps = el modelo devuelve imagen en la respuesta de completions
// Gap = [] â†’ InternalRunCompletions (el modelo genera imagen inline en la respuesta)
RegisterUserParam('Gemini', 'gemini-2.5-flash-image', 'ModelCaps',   '[cap_Image, cap_GenImage]');
RegisterUserParam('Gemini', 'gemini-2.5-flash-image', 'SessionCaps', '[cap_Image, cap_GenImage]');
RegisterUserParam('Gemini', 'gemini-2.5-flash-image', 'Tool_Active', 'False');
```

La diferencia con el PatrÃ³n 6: aquÃ­ `cap_GenImage` estÃ¡ en **ambos** `ModelCaps` y `SessionCaps`, por lo que no hay gap. El propio completions devuelve la imagen inline. En el PatrÃ³n 6, `cap_GenImage` solo estÃ¡ en `SessionCaps`, creando el gap que redirige al endpoint de imagen dedicado.

### PatrÃ³n 8: STT (transcripciÃ³n) via endpoint dedicado

```pascal
// cap_Audio en ModelCaps (soporta audio) + Tool_Active=False (sin tools)
// Usar con ChatMode = cmTranscription
RegisterUserParam('Driver', 'whisper', 'ModelCaps',   '[cap_Audio]');
RegisterUserParam('Driver', 'whisper', 'SessionCaps', '[cap_Audio]');
RegisterUserParam('Driver', 'whisper', 'Tool_Active', 'False');
```

### PatrÃ³n 9: Modelo con bridge de visiÃ³n para texto puro

```pascal
// El modelo (ej. Ollama texto puro) no tiene visiÃ³n nativa
// El usuario quiere enviar imÃ¡genes â†’ bridge automÃ¡tico las describe antes del prompt
RegisterUserParam('Ollama', 'ModelCaps',   '[]');          // no ve imÃ¡genes
RegisterUserParam('Ollama', 'SessionCaps', '[cap_Image]'); // sesiÃ³n requiere imÃ¡genes
// Gap = [cap_Image] â†’ en Fase 1, InternalRunImageDescription se ejecuta automÃ¡ticamente
// La imagen se describe en texto y se adjunta al prompt
```

### PatrÃ³n 10: GeneraciÃ³n de video

```pascal
// ModelCaps=[cap_Image]: acepta imagen como input (text-to-video o image-to-video)
// SessionCaps agrega cap_GenVideo: Gap=[cap_GenVideo] â†’ InternalRunImageVideoGeneration
RegisterUserParam('Gemini', 'aa_veo-3.0-generate-preview', 'ModelCaps',   '[cap_Image]');
RegisterUserParam('Gemini', 'aa_veo-3.0-generate-preview', 'SessionCaps', '[cap_Image, cap_GenVideo]');
RegisterUserParam('Gemini', 'aa_veo-3.0-generate-preview', 'Tool_Active', 'False');
```

---

## 9. Referencia de capacidades por provider

### OpenAI

| Modelo | ModelCaps | SessionCaps | Tool_Active | Notas |
|--------|-----------|-------------|-------------|-------|
| gpt-4.1 / 4.1-mini / 4.1-nano | `[cap_Image]` | `[cap_Image]` | True | 1M ctx, 32K output |
| gpt-4o / gpt-4o-mini | `[cap_Image]` | `[cap_Image]` | True | |
| o3 | `[cap_Image, cap_Reasoning]` | `[cap_Image, cap_Reasoning]` | True | ThinkingLevel=tlMedium |
| o3-pro | `[cap_Image, cap_Reasoning]` | `[cap_Image, cap_Reasoning]` | True | ThinkingLevel=tlHigh |
| o4-mini | `[cap_Image, cap_Reasoning]` | `[cap_Image, cap_Reasoning]` | True | ThinkingLevel=tlMedium |
| o3/o4-mini-deep-research | `[cap_Reasoning, cap_WebSearch, cap_CodeInterpreter]` | idem | True | |
| gpt-4o-search-preview | `[cap_WebSearch]` | `[cap_WebSearch]` | False | |
| gpt-image-1 / dall-e-3 / dall-e-2 | `[]` | `[cap_GenImage]` | False | Gap â†’ endpoint imagen |
| gpt-4o-mini-tts | `[]` | `[cap_GenAudio]` | False | Gap â†’ endpoint TTS |
| gpt-4o-audio-preview | `[cap_Audio, cap_GenAudio]` | `[cap_Audio, cap_GenAudio]` | False | Audio I/O nativo en completions |
| gpt-4o-transcribe / mini-transcribe | `[cap_Audio]` | `[cap_Audio]` | False | STT nativo |
| aa_gpt-4.1-pdf | `[cap_Image, cap_Pdf]` | `[cap_Image, cap_Pdf]` | True | Perfil con PDF nativo |

### Gemini (Google)

| Modelo | ModelCaps | SessionCaps | Tool_Active | Notas |
|--------|-----------|-------------|-------------|-------|
| gemini-2.5-flash | `[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]` | idem | True | 1M ctx, 65K output |
| gemini-2.5-flash-lite | `[cap_Image, cap_Audio, cap_Video, cap_Pdf]` | idem | True | Budget/rÃ¡pido |
| gemini-2.5-pro | `[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]` | idem | True | |
| gemini-3-pro-preview | idem que 2.5-pro | idem | True | ThinkingLevel=tlHigh |
| gemini-3.1-pro-preview | idem | idem | True | ThinkingLevel=tlHigh |
| gemini-2.5-flash-image | `[cap_Image, cap_GenImage]` | idem | False | Gen imagen nativa en completions |
| gemini-3-pro-image-preview | `[cap_Image, cap_GenImage]` | idem | False | Sin ThinkingLevel |
| gemini-2.5-flash-preview-tts | `[]` | `[cap_GenAudio]` | False | Gap â†’ TTS |
| gemini-2.5-pro-preview-tts | `[]` | `[cap_GenAudio]` | False | Gap â†’ TTS |
| aa_veo-2.0/3.0/3.1 | `[cap_Image]` | `[cap_Image, cap_GenVideo]` | False | Gap=[cap_GenVideo] â†’ video |

### Claude (Anthropic)

| ConfiguraciÃ³n | ModelCaps | SessionCaps | Tool_Active |
|---|---|---|---|
| Global (todos los modelos) | `[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]` | idem | False |

Todos los modelos Claude actuales (Opus 4.6, Sonnet 4.6/4.5, Haiku 4.5) comparten las mismas capacidades nativas: visiÃ³n, PDF, reasoning y web search.

### Groq

| Modelo | ModelCaps | SessionCaps | Tool_Active |
|--------|-----------|-------------|-------------|
| Global (default) | `[]` | `[]` | True |
| llama-3.1/3.3 | `[]` (hereda global) | `[]` | True |
| qwen/qwen-3-32b | `[cap_Reasoning]` | `[cap_Reasoning]` | True | ThinkingLevel=tlMedium |
| deepseek-r1-distill-llama-70b | `[cap_Reasoning]` | `[cap_Reasoning]` | True | ThinkingLevel=tlMedium |
| llama-4-scout / llama-4-maverick | `[cap_Image]` | `[cap_Image]` | True | |
| compound-beta / mini | `[cap_WebSearch, cap_CodeInterpreter]` | idem | False | Nativo, no tool calls |
| whisper-large-v3 / turbo | `[cap_Audio]` | `[cap_Audio]` | False | STT |
| canopylabs/orpheus-v1-english | `[]` | `[cap_GenAudio]` | False | Gap â†’ TTS |

### DeepSeek

| Modelo | ModelCaps | SessionCaps | Tool_Active | Notas |
|--------|-----------|-------------|-------------|-------|
| deepseek-chat | `[]` | `[]` | True | Texto + tools, 128K ctx |
| deepseek-reasoner | `[cap_Reasoning]` | `[cap_Reasoning]` | True | ThinkingLevel=tlMedium |

### Kimi (Moonshot AI)

| Modelo | ModelCaps | SessionCaps | Tool_Active |
|--------|-----------|-------------|-------------|
| kimi-k2 | `[]` | `[]` | True |
| kimi-k2.5 | `[cap_Image, cap_Pdf, cap_Reasoning]` | idem | True |
| kimi-k2-thinking | `[cap_Reasoning]` | `[cap_Reasoning]` | True |
| moonshot-v1-* | `[]` | `[]` | False |
| moonshot-v1-*-vision | `[cap_Image]` | `[cap_Image]` | False |

### xAI Grok

| Modelo | ModelCaps | SessionCaps | Tool_Active |
|--------|-----------|-------------|-------------|
| grok-3 | `[]` | `[]` | True |
| grok-3-mini | `[cap_Reasoning]` | `[cap_Reasoning]` | True | ThinkingLevel=tlLow |
| grok-4-fast-reasoning | `[cap_Image, cap_Reasoning]` | idem | True | 2M ctx |
| grok-2-image-1212 / grok-imagine-* | `[]` | `[cap_GenImage]` | False | Gap â†’ imagen |
| grok-imagine-video | `[]` | `[cap_GenVideo]` | False | Gap â†’ video |

### Mistral

| ConfiguraciÃ³n | ModelCaps | SessionCaps | Tool_Active |
|---|---|---|---|
| Global (default) | `[cap_Image]` | `[cap_Image]` | True |
| magistral-medium/small | `[cap_Reasoning]` | `[cap_Reasoning]` | True | ThinkingLevel=tlMedium |
| devstral-latest | `[]` | `[cap_Pdf, cap_Image]` | True | Sin visiÃ³n propia |
| voxtral-mini/small | `[cap_Audio]` | `[cap_Audio]` | False | STT vÃ­a completions |
| mistral-ocr-latest | `[cap_Pdf]` | `[cap_Pdf]` | False | OCR vÃ­a /v1/ocr |

### Cohere

| Modelo | ModelCaps | SessionCaps | Tool_Active |
|--------|-----------|-------------|-------------|
| command-a-03-2025 | `[]` | `[]` | True |
| command-a-reasoning-08-2025 | `[cap_Reasoning]` | `[cap_Reasoning]` | True |
| command-a-vision-07-2025 | `[cap_Image]` | `[cap_Image]` | False |
| c4ai-aya-vision-8b/32b | `[cap_Image]` | `[cap_Image]` | False |

### Ollama (modelos locales)

| ConfiguraciÃ³n | ModelCaps | SessionCaps | Tool_Active |
|---|---|---|---|
| Global (default) | `[]` | `[]` | False |
| llama3.3 / qwen2.5 | `[]` | `[]` | True |
| qwen3:latest | `[cap_Reasoning]` | `[cap_Reasoning]` | True | ThinkingLevel=tlMedium |
| deepseek-r1:latest | `[cap_Reasoning]` | `[cap_Reasoning]` | False | ThinkingLevel=tlMedium |
| llama3.2-vision | `[cap_Image]` | `[cap_Image]` | False | |
| qwen2.5vl | `[cap_Image]` | `[cap_Image]` | True | |
| gemma3:1b/4b/12b/27b | `[cap_Image]` | `[cap_Image]` | True | |

---

## 10. AÃ±adir un nuevo provider

Al crear un nuevo driver (`TAi[Provider]Chat` heredando de `TAiChat`), configurar las capacidades en `uMakerAi.Chat.Initializations.pas`:

```pascal
// 1. Configurar defaults globales del provider
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'Max_Tokens',  '16000');
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'Tool_Active', 'True');
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'ModelCaps',   '[cap_Image]');
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'SessionCaps', '[cap_Image]');

// 2. Overrides por modelo
// Modelo bÃ¡sico (solo texto)
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'mi-model-basic', 'ModelCaps',   '[]');
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'mi-model-basic', 'SessionCaps', '[]');

// Modelo con reasoning
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'mi-model-think', 'ModelCaps',    '[cap_Image, cap_Reasoning]');
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'mi-model-think', 'SessionCaps',  '[cap_Image, cap_Reasoning]');
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'mi-model-think', 'ThinkingLevel', 'tlMedium');

// Modelo TTS
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'mi-model-tts', 'ModelCaps',   '[]');
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'mi-model-tts', 'SessionCaps', '[cap_GenAudio]');
TAiChatFactory.Instance.RegisterUserParam('MiProvider', 'mi-model-tts', 'Tool_Active', 'False');
```

### Preguntas de diseÃ±o al configurar un nuevo modelo

1. **Â¿QuÃ© tipos de entrada acepta el endpoint de completions?**
   â†’ Esas son las `ModelCaps` de entrada (`cap_Image`, `cap_Audio`, etc.)

2. **Â¿El endpoint de completions puede generar imÃ¡genes/audio/video inline?**
   â†’ AÃ±adir la `cap_Gen*` correspondiente a `ModelCaps` (y `SessionCaps`). Gap = 0, va directo.

3. **Â¿El modelo tiene endpoint separado de TTS/imagen/video?**
   â†’ `ModelCaps = []`, `SessionCaps = [cap_Gen*]`. Gap activa el bridge.

4. **Â¿El modelo tiene razonamiento extendido?**
   â†’ `cap_Reasoning` en `ModelCaps` y `SessionCaps`, mÃ¡s `ThinkingLevel`.

5. **Â¿El modelo soporta tool calling?**
   â†’ `Tool_Active = True`.

---

## 11. Referencia de archivos fuente

| PropÃ³sito | Archivo |
|-----------|---------|
| DefiniciÃ³n de `TAiCapability` y `TAiCapabilities` | `Source/Core/uMakerAi.Core.pas` (lÃ­nea 65) |
| DeclaraciÃ³n de `ModelCaps`/`SessionCaps` en `TAiChat` | `Source/Core/uMakerAi.Chat.pas` (lÃ­nea 430) |
| ImplementaciÃ³n de setters y sync con legacy | `Source/Core/uMakerAi.Chat.pas` (lÃ­nea 2886) |
| Gap analysis y fases de orquestaciÃ³n (`RunNew`) | `Source/Core/uMakerAi.Chat.pas` (lÃ­nea 3004) |
| AplicaciÃ³n de params via RTTI (`ApplyParamsToChat`) | `Source/Chat/uMakerAi.Chat.AiConnection.pas` (lÃ­nea 509) |
| ConfiguraciÃ³n de modelos por provider | `Source/Chat/uMakerAi.Chat.Initializations.pas` |

---

*DocumentaciÃ³n generada para MakerAI v3.3 â€” marzo 2026*
*Fuente oficial del proyecto: https://makerai.cimamaker.com*
