// MIT License
//
// Copyright (c) <year> <copyright holders>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// Name: Gustavo Enr?quez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/



unit uMakerAi.Chat.Initializations;

interface

uses
  System.SysUtils, uMakerAi.ParamsRegistry, uMakerAi.Embeddings;

implementation

// These imports activate the initialization of each Chat driver,
// which register both TAiChatFactory (chat) and TAiEmbeddingFactory (embeddings).
// Centralized here so that any app using uMakerAi.Chat.Initializations
// has all drivers available automatically.
uses
  uMakerAi.Chat.OpenAi,
  uMakerAi.Chat.Claude,
  uMakerAi.Chat.Gemini,
  uMakerAi.Chat.Ollama,
  uMakerAi.Chat.Groq,
  uMakerAi.Chat.DeepSeek,
  uMakerAi.Chat.GLM,
  uMakerAi.Chat.Qwen,
  uMakerAi.Chat.Kimi,
  uMakerAi.Chat.Grok,
  uMakerAi.Chat.Mistral,
  uMakerAi.Chat.Cohere,
  uMakerAi.Chat.LMStudio,
  uMakerAi.Chat.GenericLLM,
  uMakerAi.Chat.MakerAi,
  // uMakerAi.Chat.Llamacpp,      // Demos only — requires makerai.gen.dll (Windows)
  uMakerAi.Embeddings.OpenAi,
  uMakerAi.Embeddings.Gemini,
  uMakerAi.Embeddings.Ollama,
  uMakerAi.Embeddings.Mistral,
  uMakerAi.Embeddings.Qwen,
  uMakerAi.Embeddings.Cohere,
  uMakerAi.Embeddings.LMStudio,
  uMakerAi.Embeddings.Generic;
  // uMakerAi.Embeddings.Llamacpp; // Demos only — requires makerai.gen.dll (Windows)

Procedure InitChatModels;
Var
  Model: String;
Begin


  // ===================================================================
  // GLOBAL CONFIGURATION FOR OLLAMA
  // https://ollama.com/library
  // Ultima actualizacion: May 2026
  // ===================================================================
  // Default: plain text, no native tools (conservative)
  TAiChatFactory.Instance.RegisterUserParam('Ollama', 'Max_Tokens',   '8000');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', 'Temperature',  '0.7');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', 'Asynchronous', 'True');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', 'Tool_Active',  'False');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', 'ModelCaps',    '[]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', 'SessionCaps',  '[]');

  // ------- Llama 3.3 (text + tools, 128K ctx) ------
  Model := 'llama3.3:latest';
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'Tool_Active', 'True');

  // ------- Qwen 2.5 (text + tools, 128K ctx) ------
  Model := 'qwen2.5:latest';
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'Tool_Active', 'True');

  // ------- Qwen3 (text + tools + reasoning, 128K ctx) ------
  Model := 'qwen3:latest';
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'Tool_Active',   'True');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'ThinkingLevel', 'tlMedium');

  // ------- DeepSeek R1 (reasoning via <think>, without tools) ------
  Model := 'deepseek-r1:latest';
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'ThinkingLevel', 'tlMedium');

  // ------- Llama 3.2 Vision (vision, 11B, 128K ctx) ------
  Model := 'llama3.2-vision:latest';
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'SessionCaps', '[cap_Image]');

  // ------- Qwen 2.5 VL (advanced vision + tools, 128K ctx) ------
  Model := 'qwen2.5vl:latest';
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'Tool_Active', 'True');

  // ------- Gemma 3 (vision + tools, sizes: 1b/4b/12b/27b) ------
  // All sizes share the same capabilities
  Model := 'gemma3:1b';  // = gemma3:4b
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'Tool_Active', 'False');

  Model := 'gemma3:4b';  // = gemma3:4b
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'Tool_Active', 'False');

  Model := 'gemma3:12b';
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'Tool_Active', 'False');

  Model := 'gemma3:27b';
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'Tool_Active', 'False');

  // ------- Gemma 4 (vision + audio + native reasoning, sizes: e4b / 4b / 12b / 27b) ------
  // gemma4 supports image, audio and reasoning natively.
  for Model in ['gemma4', 'gemma4:latest',
                'gemma4:e2b', 'gemma4:e4b',
                'gemma4:4b',  'gemma4:12b', 'gemma4:27b'] do
  begin
    TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'ModelCaps',    '[cap_Image, cap_Audio, cap_Reasoning]');
    TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'SessionCaps',  '[cap_Image, cap_Audio, cap_Reasoning]');
    TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'ThinkingLevel', 'tlMedium');
    TAiChatFactory.Instance.RegisterUserParam('Ollama', Model, 'Tool_Active',  'True');
  end;


  // ------------------------- OPENAI ----------------------------------
  // https://platform.openai.com/docs/models
  // Ultima actualizacion: May 2026
  // ------------------------- OPENAI ----------------------------------

  // --- Default global values for all OpenAI models ---
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'Max_Tokens', '16000');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'Tool_Active', 'True');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'Temperature', '1');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'SessionCaps', '[cap_Image]');

  // deprecated Feb 2026 — kept for backward compatibility
  // ------- GPT-4.1 (Apr 2025) -- 1M ctx, 32K output, vision + tools ------
  // https://platform.openai.com/docs/models/gpt-4.1
  Model := 'gpt-4.1';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',   '32768');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Image]');

  Model := 'gpt-4.1-mini';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',   '32768');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Image]');

  Model := 'gpt-4.1-nano';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',   '32768');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Image]');

  // ------- GPT-4o -- 128K ctx, 16K output, vision + tools ------
  // https://platform.openai.com/docs/models/gpt-4o
  Model := 'gpt-4o';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',   '16384');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Image]');

  Model := 'gpt-4o-mini';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',   '16384');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Image]');

  // ------- Reasoning: o3 / o4-mini -- 200K ctx, 100K output ------
  // https://platform.openai.com/docs/models/o3
  Model := 'o3';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',    '100000');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',    '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',  '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ThinkingLevel', 'tlMedium');

  Model := 'o3-pro';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',    '100000');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',    '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',  '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ThinkingLevel', 'tlHigh');

  // https://platform.openai.com/docs/models/o4-mini
  Model := 'o4-mini';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',    '100000');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',    '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',  '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ThinkingLevel', 'tlMedium');

  // ------- Deep Research -- extended response time ------
  Model := 'o3-deep-research';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',    '100000');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',    '[cap_Reasoning, cap_WebSearch, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',  '[cap_Reasoning, cap_WebSearch, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ResponseTimeOut', '120000');

  Model := 'o4-mini-deep-research';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',    '100000');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',    '[cap_Reasoning, cap_WebSearch, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',  '[cap_Reasoning, cap_WebSearch, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ResponseTimeOut', '120000');

  // ------- Native web search via Responses API ------
  // Note: gpt-4o-search-preview only works via Chat Completions API (not Responses API)
  // For Responses API use gpt-4.1 + tool web_search (recommended)
  TAiChatFactory.Instance.RegisterCustomModel('OpenAi', 'aa_gpt-4.1-web-search', 'gpt-4.1');
  Model := 'aa_gpt-4.1-web-search';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',   '32768');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Image, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Image, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active', 'False');

  // Legacy Chat Completions search models (may not work via Responses API)
  Model := 'gpt-4o-search-preview';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active', 'False');

  Model := 'gpt-4o-mini-search-preview';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active', 'False');

  // ------- GPT-5 family (2026) ------
  // https://platform.openai.com/docs/models/gpt-5

  // --- GPT-5.4 (May 2026) -- 1M ctx, vision + tools, standard production ---
  Model := 'gpt-5.4';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',   '32768');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active', 'True');

  Model := 'gpt-5.4-mini';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',   '32768');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active', 'True');

  // --- GPT-5.5 (Apr 2026) -- 1M ctx, reasoning + vision + tools + computer use ---
  // https://platform.openai.com/docs/models/gpt-5.5
  // reasoning.effort mapped from ThinkingLevel via Responses API
  Model := 'gpt-5.5';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',    '32768');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',    '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',  '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active',  'True');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ThinkingLevel', 'tlMedium');

  Model := 'gpt-5.5-pro';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',    '32768');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',    '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',  '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active',  'True');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ThinkingLevel', 'tlHigh');

  // --- GPT-5.6 Sol/Terra/Luna (Jul 2026) -- 1.05M ctx, 128K out ---
  // The whole family: vision + reasoning + tools + prompt caching.
  // Sol = flagship; Terra = cost/capability balance; Luna = economical tier.
  // The alias 'gpt-5.6' routes to Sol in the API.
  for Model in ['gpt-5.6', 'gpt-5.6-sol'] do
  begin
    TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',    '32768');
    TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',    '[cap_Image, cap_Reasoning]');
    TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',  '[cap_Image, cap_Reasoning]');
    TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active',  'True');
    TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ThinkingLevel', 'tlHigh');
  end;

  Model := 'gpt-5.6-terra';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',    '32768');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',    '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',  '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active',  'True');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ThinkingLevel', 'tlMedium');

  Model := 'gpt-5.6-luna';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',    '32768');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',    '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',  '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active',  'True');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ThinkingLevel', 'tlLow');

  // --- GPT-6 Astra (Aug 27/2026) -- 1.05M ctx (272K without surcharge), 128K out ---
  // https://developers.openai.com/api/docs/models/gpt-6-astra
  // Vision + reasoning + tools. $10/$50 per 1M ($1 cached). Above 272K
  // input tokens are charged 2x and output 1.5x.
  //
  // COMPUTER USE: astra brings the native 'computer' tool (replaces the
  // dedicated computer-use-preview, shut down on 23-Jul-2026). It is NOT enabled by
  // default: cap_ComputerUse gives the model the mouse and keyboard of the
  // machine, so it is explicit opt-in (same criterion as Claude and as
  // gemini-3.5-flash). To enable it, override in the app:
  //   TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'gpt-6-astra',
  //     'ModelCaps',   '[cap_Image, cap_Reasoning, cap_ComputerUse]');
  //   TAiChatFactory.Instance.RegisterUserParam('OpenAi', 'gpt-6-astra',
  //     'SessionCaps', '[cap_Image, cap_Reasoning, cap_ComputerUse]');
  //
  // Effort: the GPT-6 family accepts none/low/medium/high/xhigh/max; starting
  // v3.8 TAiThinkingLevel expresses them all (tlXHigh/tlMax).
  Model := 'gpt-6-astra';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',    '32768');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',    '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',  '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active',  'True');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ThinkingLevel', 'tlHigh');

  // --- GPT-6 Sol / Luna (Sep 2026) -- 1.05M ctx, 128K out, text + image ---
  // https://developers.openai.com/api/docs/models/gpt-6-sol (y gpt-6-luna)
  // Reviewed Sep 29/2026 against the official docs. Both: reasoning.effort
  // none..max (default medium), function calling, web/file search, code
  // interpreter, computer use, structured outputs and prompt caching. For
  // above 272K input: input 2x and output 1.5x.
  // Sol: code and agents, $2/$10 ($0.2 cached) -- DRIVER DEFAULT since
  //      v3.8 (natural successor to gpt-5.1 in the same price band).
  Model := 'gpt-6-sol';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',    '32768');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',    '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',  '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active',  'True');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ThinkingLevel', 'tlMedium');

  // Luna: high volume and bounded tasks, $0.10/$0.50 ($0.01 cached). WARNING: via
  // Chat Completions only accepts function calling with reasoning_effort=none
  // (the driver uses Responses API, where there is no such restriction).
  Model := 'gpt-6-luna';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Max_Tokens',    '32768');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',    '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',  '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active',  'True');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ThinkingLevel', 'tlLow');

  // ------- Generacion de imagenes ------
  // https://platform.openai.com/docs/guides/images
  // ModelCaps=[]: usa endpoint dedicado; Gap=[cap_GenImage] activa InternalRunImageGeneration
  // gpt-image-2.5 family (Sep 2026): flare = fast and high quality,
  // sunburst = premium for fine editing. Both with real transparent background
  // and xhigh/max quality. Endpoints: /images/generations and /images/edits.
  for Model in ['gpt-image-2.5-flare', 'gpt-image-2.5-flare-2026-09-08',
                'gpt-image-2.5-sunburst', 'gpt-image-2.5-sunburst-2026-09-08'] do
  begin
    TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',       '[]');
    TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',     '[cap_GenImage]');
    TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active',     'False');
    TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ResponseTimeOut', '36000');
  end;

  Model := 'gpt-image-2';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',       '[]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',     '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active',     'False');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ResponseTimeOut', '36000');

  Model := 'gpt-image-1';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',      '[]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',    '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active',    'False');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ResponseTimeOut', '36000');

  // DEPRECATED by OpenAI (May 2026): they remain registered while the
  // API accepts them, but for new projects use gpt-image-1/1.5/2
  Model := 'dall-e-3';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active', 'False');

  Model := 'dall-e-2';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active', 'False');

  Model := 'gpt-image-1.5';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',       '[]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',     '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active',     'False');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ResponseTimeOut', '36000');

  // Rest of the gpt-image family visible in /v1/models (Jul 2026). Without these
  // entries they inherit the driver defaults (ModelCaps=[cap_Image]) -> gap
  // empty -> the request goes through /responses -> "model was not found".
  for Model in ['chatgpt-image-latest', 'gpt-image-1-mini', 'gpt-image-2-2026-04-21'] do
  begin
    TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',       '[]');
    TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',     '[cap_GenImage]');
    TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active',     'False');
    TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ResponseTimeOut', '36000');
  end;

  // ------- Audio TTS -- ModelCaps=[]: usa endpoint TTS dedicado ------
  // Gap=[cap_GenAudio] activa InternalRunSpeechGeneration
  // https://platform.openai.com/docs/guides/audio
  // DEPRECATED by OpenAI on 2026-10-01 (along with tts-1 / tts-1-hd), shut down
  // on 2027-01-06. OpenAI recommends gpt-realtime-2.1-mini (realtime).
  Model := 'gpt-4o-mini-tts';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',    '[]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps',  '[cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active',  'False');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Voice',        'alloy');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Voice_Format', 'mp3');

  // ------- Transcription (STT) -- cap_Audio: processes native audio ------
  // Use with ChatMode = cmTranscription
  // gpt-transcribe: recommended for files/batch (WER 8.98% vs 15.21% whisper)
  Model := 'gpt-transcribe';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active', 'False');

  // gpt-live-transcribe: low-latency live transcription (Realtime)
  Model := 'gpt-live-transcribe';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active', 'False');

  // gpt-4o-transcribe, gpt-4o-mini-transcribe, gpt-4o-transcribe-diarize and
  // whisper-1: DEPRECATED by OpenAI on 2026-08-26, shut down on 2027-02-26.
  // They remain registered while they work; migrate to the two above.
  Model := 'gpt-4o-transcribe';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active', 'False');

  Model := 'gpt-4o-mini-transcribe';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active', 'False');

  Model := 'gpt-4o-transcribe-diarize';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active', 'False');

  // whisper-1 -- STT legacy via /v1/audio/transcriptions
  Model := 'whisper-1';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active', 'False');

  // ------- Audio multimodal (audio I/O in completions) ------
  // cap_Audio + cap_GenAudio in ModelCaps: processes and generates audio via completions
  Model := 'gpt-4o-audio-preview';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Audio, cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Audio, cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active', 'False');

  Model := 'gpt-4o-mini-audio-preview';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Audio, cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Audio, cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'Tool_Active', 'False');

  // ------- Perfiles personalizados (aa_*) ------
  // GPT-4.1 with native PDF support (OpenAI file API)
  TAiChatFactory.Instance.RegisterCustomModel('OpenAi', 'aa_gpt-4.1-pdf', 'gpt-4.1');
  Model := 'aa_gpt-4.1-pdf';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ModelCaps',   '[cap_Image, cap_Pdf]');
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'SessionCaps', '[cap_Image, cap_Pdf]');

  // o3 with high reasoning level
  TAiChatFactory.Instance.RegisterCustomModel('OpenAi', 'aa_o3-high', 'o3');
  Model := 'aa_o3-high';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ThinkingLevel', 'tlHigh');

  // o4-mini -- high and low reasoning levels
  TAiChatFactory.Instance.RegisterCustomModel('OpenAi', 'aa_o4-mini-high', 'o4-mini');
  Model := 'aa_o4-mini-high';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ThinkingLevel', 'tlHigh');

  TAiChatFactory.Instance.RegisterCustomModel('OpenAi', 'aa_o4-mini-low', 'o4-mini');
  Model := 'aa_o4-mini-low';
  TAiChatFactory.Instance.RegisterUserParam('OpenAi', Model, 'ThinkingLevel', 'tlLow');

  // ------------------------- GEMINI ----------------------------------
  // https://ai.google.dev/gemini-api/docs/models
  // Last updated: Sep 29 2026 (against the official docs, WITHOUT testing
  // runtime: there was no API key). Driver default: gemini-3.8-flash.
  // The 2.5 family remains registered but Google limits it to accounts that already
  // used it; for a new user it fails.
  // ------------------------- GEMINI ----------------------------------

  // --- Default global values for all Gemini models ---
  TAiChatFactory.Instance.RegisterUserParam('Gemini', 'Max_Tokens',  '32768');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', 'Tool_Active', 'True');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', 'SessionCaps', '[cap_Image]');

  // ------- Gemini 3.x family (2026) ------

  // ------- Gemini 3.1 Pro Preview -- flagship, 2M ctx, full multimodal + reasoning ------
  Model := 'gemini-3.1-pro-preview';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Max_Tokens',   '65536');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ThinkingLevel', 'tlHigh');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',   'True');

  // ------- Gemini 3 Flash Preview -- speed/quality balance, multimodal + reasoning ------
  Model := 'gemini-3-flash-preview';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Max_Tokens',   '65536');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ThinkingLevel', 'tlMedium');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',   'True');

  // ------- Gemini 3.1 Flash Lite -- economical, multimodal + reasoning ------
  Model := 'gemini-3.1-flash-lite';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Max_Tokens',   '65536');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ThinkingLevel', 'tlLow');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',   'True');

  // ------- Gemini 3.5/3.6 family (May-Jul 2026, GA) ------
  // Sampling params (temperature/topP/topK) deprecated in this family:
  // the driver omits them automatically.

  // gemini-3.5-flash -- flash flagship GA (may 19/2026); alias gemini-flash-latest.
  // Computer Use tool in public preview for this model (cap_ComputerUse
  // user opt-in, not by default)
  Model := 'gemini-3.5-flash';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Max_Tokens',   '65536');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ThinkingLevel', 'tlMedium');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',   'True');

  // gemini-flash-latest -- moving alias that points to the most recent GA flash
  Model := 'gemini-flash-latest';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Max_Tokens',   '65536');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ThinkingLevel', 'tlMedium');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',   'True');

  // gemini-3.6-flash -- GA (Jul 21/2026): better token efficiency and
  // agentic planning, cheaper than 3.5 Flash
  Model := 'gemini-3.6-flash';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Max_Tokens',   '65536');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ThinkingLevel', 'tlMedium');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',   'True');

  // gemini-3.5-flash-lite -- GA (Jul 21/2026): low latency, subagents
  Model := 'gemini-3.5-flash-lite';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Max_Tokens',   '65536');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ThinkingLevel', 'tlLow');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',   'True');

  // ------- Gemini 3.7/3.8 family (Aug-Sep 2026, stable) ------
  // 1M ctx, 65K output; input text/image/video/audio/PDF; function calling,
  // Google Search, code execution, url context, structured output and computer
  // use (preview). Thinking only low/medium/high: 'minimal' errors and cannot
  // be turned off (the driver maps tlMinimal/tlNone to LOW). Sampling omitted
  // (3.5+ family). Without runtime testing.

  // gemini-3.8-flash -- stable (Sep 2026): DRIVER DEFAULT
  Model := 'gemini-3.8-flash';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Max_Tokens',   '65536');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ThinkingLevel', 'tlMedium');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',   'True');

  // gemini-3.7-flash -- stable (Aug 2026), code-oriented
  Model := 'gemini-3.7-flash';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Max_Tokens',   '65536');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ThinkingLevel', 'tlMedium');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',   'True');

  // ------- Gemini 3.8 TTS (stable, Sep 22 2026) ------
  // Official replacement for gemini-2.5-flash-preview-tts. Same schema in both.
  // The docs present the new /interactions API, but the migration guide
  // still covers generateContent, which is what the driver uses.
  Model := 'gemini-3.8-flash-tts';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',       '[]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',     '[cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',     'False');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Voice',           'Sol=Kore,Gustavo=Puck');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ResponseTimeOut', '36000');

  Model := 'gemini-3.8-flash-lite-tts';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',       '[]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',     '[cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',     'False');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Voice',           'Sol=Kore,Gustavo=Puck');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ResponseTimeOut', '36000');

  // ------- Gemini 3.1 Flash TTS Preview -- new generation TTS ------
  // Since Jun 17/2026 it supports streaming via streamGenerateContent
  Model := 'gemini-3.1-flash-tts-preview';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',       '[]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',     '[cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',     'False');

  // ------- Gemini 3.1 Flash Image Preview -- image + chat ------
  Model := 'gemini-3.1-flash-image-preview';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',   '[cap_Image, cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps', '[cap_Image, cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active', 'False');

  // ------- Nano Banana GA family (May-Jun 2026) ------
  // WARNING: Imagen 4.0 models (imagen-4.0-*-generate-001) SHUT DOWN on 17 Aug 2026.
  // Nano Banana 2 (GA of flash-image, May 28/2026); supports video-to-image
  Model := 'gemini-3.1-flash-image';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',   '[cap_Image, cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps', '[cap_Image, cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active', 'False');

  // Nano Banana Pro (GA may 28/2026)
  Model := 'gemini-3-pro-image';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',   '[cap_Image, cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps', '[cap_Image, cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active', 'False');

  // Nano Banana 2 Lite (GA Jun 30/2026): ultra-fast and economical image
  Model := 'gemini-3.1-flash-lite-image';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',   '[cap_Image, cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps', '[cap_Image, cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active', 'False');

  // ------- Veo 3.1 -- new generation video ------
  // WARNING: veo-2.0 and veo-3.0 were SHUT DOWN on 30 Jun 2026 — use only 3.1
  Model := 'veo-3.1-generate-preview';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active', 'False');

  // ------- Gemini Omni Flash (preview jun 30/2026) -- video 3-10s 720p ------
  Model := 'gemini-omni-flash-preview';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active', 'False');

  // ------- Gemini 2.5 Computer Use -- browser automation ------
  // https://ai.google.dev/gemini-api/docs/computer-use
  // Dedicated model: native computerUse tool (environment=ENVIRONMENT_BROWSER).
  // cap_ComputerUse enables the tool declaration and delegation to TAiComputerUseTool.
  Model := 'gemini-2.5-computer-use-preview-10-2025';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Max_Tokens',   '65536');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',    '[cap_Image, cap_ComputerUse]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',  '[cap_Image, cap_ComputerUse]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',  'True');

  // ------- 2.5 family: LIMITED access (Google only serves it to accounts that
  // already used it; no shutdown date). It is kept for those accounts; for
  // new projects use gemini-3.8-flash.
  // ------- Gemini 2.5 Flash -- 1M ctx, 65K output, full multimodal ------
  // https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash
  // Input: Audio, Video, PDF, Images; WebSearch+CodeInterpreter+Thinking native
  Model := 'gemini-2.5-flash';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Max_Tokens',   '65536');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active', 'True');

  // ------- Gemini 2.5 Flash Lite -- budget/fast, multimodal ------
  Model := 'gemini-2.5-flash-lite';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Max_Tokens',   '32768');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf]');

  // ------- Gemini 2.5 Pro -- 1M ctx, high capability ------
  // https://ai.google.dev/gemini-api/docs/models/gemini-2.5-pro
  Model := 'gemini-2.5-pro';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Max_Tokens',   '65536');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active', 'True');

  // ------- Gemini 3 Pro Preview -- SHUT DOWN by Google ------
  // Remains as an alias of gemini-3.1-pro-preview (its successor) to avoid breaking
  // existing configurations: the driver sends the base model.
  TAiChatFactory.Instance.RegisterCustomModel('Gemini', 'gemini-3-pro-preview', 'gemini-3.1-pro-preview');
  Model := 'gemini-3-pro-preview';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Max_Tokens',   '65536');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch, cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ThinkingLevel', 'tlHigh');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',   'True');

  // ------- TTS -- ModelCaps=[]: uses dedicated TTS endpoint ------
  // Gap=[cap_GenAudio] activa InternalRunSpeechGeneration
  // https://ai.google.dev/gemini-api/docs/speech-generation
  Model := 'gemini-2.5-flash-preview-tts';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',       '[]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',     '[cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',     'False');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Voice',           'Sol=Kore,Gustavo=Puck');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ResponseTimeOut', '36000');

  Model := 'gemini-2.5-pro-preview-tts';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',       '[]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',     '[cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',     'False');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Voice',           'Sol=Kore,Gustavo=Puck');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ResponseTimeOut', '36000');

  // ------- Image generation via completions ------
  // cap_GenImage in ModelCaps and SessionCaps: InternalRunCompletions + responseModalities=[IMAGE]
  // https://ai.google.dev/gemini-api/docs/image-generation
  // Note: 'gemini-2.5-flash-image-preview' (previous name, returns 404 in v1beta)
  Model := 'gemini-2.5-flash-image';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',   '[cap_Image, cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps', '[cap_Image, cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active', 'False');

  // WARNING: gemini-2.5-flash-image SHUTS DOWN on 2 Oct 2026 (official replacement:
  // gemini-3.1-flash-image). After that date convert it into an alias.

  // ------- Gemini 3 Pro Image (Nano Banana Pro) -- advanced image generation ------
  // https://ai.google.dev/gemini-api/docs/image-generation
  // Note: does not support ThinkingLevel (INVALID_ARGUMENT if sent)
  Model := 'gemini-3-pro-image-preview';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',   '[cap_Image, cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps', '[cap_Image, cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active', 'False');

  // ------- Imagen 4 (via Gemini API :predict endpoint) ------
  // ModelCaps=[]: uses :predict endpoint; Gap=[cap_GenImage] enables InternalRunNativeImageGeneration
  // https://ai.google.dev/gemini-api/docs/imagen
  // Params via ImageParams.Params: aspectRatio (1:1 3:4 4:3 9:16 16:9), imageSize (1K 2K), personGeneration
  // SHUT DOWN on 17 Aug 2026. The three names remain as aliases of Nano
  // Banana 2 (gemini-3.1-flash-image) with their capabilities: generation moves
  // from the :predict endpoint to completions with responseModalities=[IMAGE], and the
  // existing code keeps working. ImageParams.aspectRatio is still
  // sent (imageConfig); personGeneration may not apply.
  TAiChatFactory.Instance.RegisterCustomModel('Gemini', 'imagen-4.0-generate-001',       'gemini-3.1-flash-image');
  TAiChatFactory.Instance.RegisterCustomModel('Gemini', 'imagen-4.0-fast-generate-001',  'gemini-3.1-flash-image');
  TAiChatFactory.Instance.RegisterCustomModel('Gemini', 'imagen-4.0-ultra-generate-001', 'gemini-3.1-flash-image');
  for Model in ['imagen-4.0-generate-001', 'imagen-4.0-fast-generate-001', 'imagen-4.0-ultra-generate-001'] do
  begin
    TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',       '[cap_Image, cap_GenImage]');
    TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',     '[cap_Image, cap_GenImage]');
    TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',     'False');
    TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ResponseTimeOut', '120000');
  end;

  // ------- Video generation (Veo) ------
  // ModelCaps=[cap_Image]: accepts input image
  // SessionCaps adds cap_GenVideo: Gap enables InternalRunImageVideoGeneration
  // https://ai.google.dev/gemini-api/docs/video
  // RETIRED: veo-2.0-generate-001 and veo-3.0-generate-preview were SHUT DOWN
  // by Google on 30 Jun 2026 — the aa_veo-2.0/aa_veo-3.0 profiles are removed
  // from the registry; use aa_veo-3.1-generate-preview.

  TAiChatFactory.Instance.RegisterCustomModel('Gemini', 'aa_veo-3.1-generate-preview', 'veo-3.1-generate-preview');
  Model := 'aa_veo-3.1-generate-preview';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',    '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',  '[cap_Image, cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Tool_Active',  'False');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'Asynchronous', 'False');

  // ------- Perfiles personalizados (aa_*) ------
  TAiChatFactory.Instance.RegisterCustomModel('Gemini', 'aa_gemini-2.5-pro-pdf', 'gemini-2.5-pro');
  Model := 'aa_gemini-2.5-pro-pdf';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',   '[cap_Image, cap_Pdf]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps', '[cap_Image, cap_Pdf]');

  TAiChatFactory.Instance.RegisterCustomModel('Gemini', 'aa_gemini-2.5-flash-pdf', 'gemini-2.5-flash');
  Model := 'aa_gemini-2.5-flash-pdf';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',   '[cap_Image, cap_Pdf]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps', '[cap_Image, cap_Pdf]');

  TAiChatFactory.Instance.RegisterCustomModel('Gemini', 'aa_gemini-2.5-flash-code-interpreter', 'gemini-2.5-flash');
  Model := 'aa_gemini-2.5-flash-code-interpreter';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Pdf, cap_CodeInterpreter, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Pdf, cap_CodeInterpreter, cap_WebSearch]');

  TAiChatFactory.Instance.RegisterCustomModel('Gemini', 'aa_gemini-2.5-flash-web-search', 'gemini-2.5-flash');
  Model := 'aa_gemini-2.5-flash-web-search';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',   '[cap_Image, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps', '[cap_Image, cap_WebSearch]');

  // The same profiles on gemini-3.8-flash (the 2.5 ones only work for
  // accounts that already used that family)
  TAiChatFactory.Instance.RegisterCustomModel('Gemini', 'aa_gemini-3.8-flash-pdf', 'gemini-3.8-flash');
  Model := 'aa_gemini-3.8-flash-pdf';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',   '[cap_Image, cap_Pdf]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps', '[cap_Image, cap_Pdf]');

  TAiChatFactory.Instance.RegisterCustomModel('Gemini', 'aa_gemini-3.8-flash-code-interpreter', 'gemini-3.8-flash');
  Model := 'aa_gemini-3.8-flash-code-interpreter';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Pdf, cap_CodeInterpreter, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Pdf, cap_CodeInterpreter, cap_WebSearch]');

  TAiChatFactory.Instance.RegisterCustomModel('Gemini', 'aa_gemini-3.8-flash-web-search', 'gemini-3.8-flash');
  Model := 'aa_gemini-3.8-flash-web-search';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',   '[cap_Image, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps', '[cap_Image, cap_WebSearch]');

  // Gemini 3 Pro: low thinking (fast response, low reasoning token cost)
  // gemini-3-pro-preview was shut down: the profile points to its successor (the
  // alias does not chain, GetBaseModel resolves only one level)
  TAiChatFactory.Instance.RegisterCustomModel('Gemini', 'aa_gemini-3-pro-fast', 'gemini-3.1-pro-preview');
  Model := 'aa_gemini-3-pro-fast';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ThinkingLevel', 'tlLow');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch]');

  // Gemini 3.1 Pro: low thinking (fast response)
  TAiChatFactory.Instance.RegisterCustomModel('Gemini', 'aa_gemini-3.1-pro-fast', 'gemini-3.1-pro-preview');
  Model := 'aa_gemini-3.1-pro-fast';
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ThinkingLevel', 'tlLow');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'ModelCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Gemini', Model, 'SessionCaps',
    '[cap_Image, cap_Audio, cap_Video, cap_Pdf, cap_WebSearch]');

  // ------------------------- GROQ ----------------------------------
  // https://console.groq.com/docs/models
  // Last updated: Sep 28 2026 — verified against GET /models and with
  // real calls. Groq retired llama-3.x (model_not_found): aliases remain
  // toward gpt-oss so previous code keeps working.
  // ------------------------- GROQ ----------------------------------

  // --- Default global values for all Groq models ---
  TAiChatFactory.Instance.RegisterUserParam('Groq', 'Max_Tokens',    '8192');
  TAiChatFactory.Instance.RegisterUserParam('Groq', 'Tool_Active',   'True');
  TAiChatFactory.Instance.RegisterUserParam('Groq', 'ModelCaps',     '[]');
  TAiChatFactory.Instance.RegisterUserParam('Groq', 'SessionCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Groq', 'ThinkingLevel', 'tlDefault'); // Reset when changing model
  TAiChatFactory.Instance.RegisterUserParam('Groq', 'Format',        '');          // Reset reasoning_format when changing model

  // ------- Production models -- text/chat ------
  // RETIRED Sep 2026 (model_not_found, not in /models): llama-3.1-8b-instant
  // and llama-3.3-70b-versatile. Aliases to the closest replacement: the fast one and the
  // quality one. The aliases inherit only Groq's global params.
  TAiChatFactory.Instance.RegisterCustomModel('Groq', 'llama-3.1-8b-instant',    'openai/gpt-oss-20b');
  TAiChatFactory.Instance.RegisterCustomModel('Groq', 'llama-3.3-70b-versatile', 'openai/gpt-oss-120b');

  // gpt-oss-20b (driver default since Sep 2026): 131K ctx, 65K output, ~1000 t/s, reasoning + code_interpreter (include_reasoning API)
  Model := 'openai/gpt-oss-20b';
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'Max_Tokens',    '65536');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'ModelCaps',    '[cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'SessionCaps',  '[cap_Reasoning, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'ThinkingLevel', 'tlMedium');

  // gpt-oss-120b: 131K ctx, 65K output, ~500 t/s, reasoning (include_reasoning API)
  // WARNING Aug 2026: does NOT accept images ("content must be a string") — verified
  // at runtime; cap_Image removed. With llama-4-scout retired, Groq does NOT have
  // a chat model with vision currently.
  Model := 'openai/gpt-oss-120b';
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'Max_Tokens',    '65536');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'ThinkingLevel', 'tlMedium');

  // gpt-oss-safeguard-20b: 131K ctx, 65K output, ~1000 t/s, moderation/safety
  // Tool calling: yes (no parallel). No built-in tools. No reasoning or vision.
  Model := 'openai/gpt-oss-safeguard-20b';
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'Max_Tokens', '65536');

  // ------- Reasoning models ------
  // qwen3.6-27b (Aug 2026): 131K ctx, native reasoning (reasoning_format API).
  // Same contract as the retired qwen3-32b (verified at runtime): without params it leaves
  // <think> raw in content; 'parsed' -> message.reasoning field; effort 'none' turns it off.
  // reasoning_format: 'parsed' (message.reasoning), 'raw' (<think> tags), 'hidden' (response only)
  // reasoning_effort: 'default' (thinking active), 'none' (non-thinking)
  // Max_Tokens: the API rejects max_completion_tokens > 16384 (400; verified
  // Sep 28 2026 — before it was 40960 and the model did not respond)
  Model := 'qwen/qwen3.6-27b';
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'Max_Tokens',    '16384');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'ThinkingLevel', 'tlMedium');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'Format',        'parsed');

  // qwen3.8-27b (Sep 2026): 131K ctx. Verified at runtime: it responds without
  // visible reasoning (neither message.reasoning with 'parsed' nor raw <think>),
  // so it is registered as a chat model, without cap_Reasoning. The API rejects
  // max_completion_tokens > 16384 (400 invalid_request_error).
  Model := 'qwen/qwen3.8-27b';
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'Max_Tokens', '16384');

  // RETIRED Aug 2026: qwen/qwen3-32b — alias to qwen3.6-27b for previous code
  TAiChatFactory.Instance.RegisterCustomModel('Groq', 'qwen/qwen3-32b', 'qwen/qwen3.6-27b');

  // DEPRECATED 10/02/25 — use llama-3.3-70b-versatile
  // deepseek-r1-distill-llama-70b removed
  // DEPRECATED 07/14/25 — replaced by qwen (now qwen3.6-27b)
  // qwen-qwq-32b removed

  // ------- Vision ------
  // RETIRED: llama-4-scout (Aug 2026) and llama-4-maverick (03/09/26).
  // Groq does NOT have a chat model with vision currently (gpt-oss-120b is text only).

  // RETIRED 04/15/26: moonshotai/kimi-k2-instruct and kimi-k2-instruct-0905
  // (use openai/gpt-oss-120b, or the native Kimi driver with kimi-k3)

  // ------- Arabic ------
  // allam-2-7b: 4K ctx, bilingual Arabic/English (SDAIA), without tools
  Model := 'allam-2-7b';
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'Max_Tokens',  '4000');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'Tool_Active', 'False');

  // meta-llama/llama-prompt-guard-2-22m/-86m: prompt safety classifiers for
  // prompts (512 ctx) — they are not chat models, they are not registered

  // ------- Agent systems with built-in tools ------
  // NOT AVAILABLE Sep 2026: groq/compound and groq/compound-mini (web search +
  // server-side code execution) return model_not_found and do not appear in
  // GET /models. No alias on purpose: there is no replacement with web search, and
  // redirecting them would silently change behavior. To execute code
  // openai/gpt-oss-20b remains (cap_CodeInterpreter).

  // ------- Audio STT -- cap_Audio: processes native audio ------
  // Use with ChatMode = cmTranscription
  // https://console.groq.com/docs/speech-text
  Model := 'whisper-large-v3';
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'ModelCaps',   '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'SessionCaps', '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'Tool_Active', 'False');

  Model := 'whisper-large-v3-turbo';
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'ModelCaps',   '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'SessionCaps', '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'Tool_Active', 'False');

  // ------- Audio TTS -- ModelCaps=[]: usa endpoint TTS dedicado ------
  // Gap=[cap_GenAudio] activa InternalRunSpeechGeneration
  // https://console.groq.com/docs/text-to-speech
  // Orpheus TTS (Canopy Labs) -- only TTS available in Groq (playai-tts decommissioned 12/31/25)
  // https://console.groq.com/docs/text-to-speech/orpheus
  // English voices: autumn, diana, hannah, austin, daniel, troy
  Model := 'canopylabs/orpheus-v1-english';
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'SessionCaps', '[cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'Tool_Active', 'False');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'Voice',       'austin');

  // Arabic voices: fahad, sultan, lulwa, noura
  Model := 'canopylabs/orpheus-arabic-saudi';
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'SessionCaps', '[cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'Tool_Active', 'False');
  TAiChatFactory.Instance.RegisterUserParam('Groq', Model, 'Voice',       'lulwa');

  // playai-tts and playai-tts-arabic: REMOVED (decommissioned 12/31/25)

  // ===========================================================================
  // CLAUDE — GLOBAL CONFIGURATION
  // Source: https://platform.claude.com/docs/en/about-claude/models/overview
  // All current models natively support:
  //   - Vision (images + PDF)
  //   - Extended Thinking (CoT reasoning)
  //   - Web Search (via native Anthropic tool)
  //   - Tool calling
  // Standard context: 200K tokens
  // Extended context (1M, beta): Opus 4.6, Sonnet 4.6, Sonnet 4.5, Sonnet 4
  //   Requires header: context-1m-2025-08-07
  //
  // ModelCaps  = native model capabilities (SetModelCaps synchronizes NativeInputFiles + ChatMediaSupports)
  // SessionCaps = desired session capabilities (SetSessionCaps synchronizes NativeOutputFiles + EnabledFeatures)
  //   Gap = SessionCaps - ModelCaps -> determines which bridges/tools are enabled in RunNew
  //   No gap (SessionCaps = ModelCaps) -> direct call to InternalRunCompletions
  // ===========================================================================
  TAiChatFactory.Instance.RegisterUserParam('Claude', 'Max_Tokens', '16000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', 'Tool_Active', 'False');
  TAiChatFactory.Instance.RegisterUserParam('Claude', 'Asynchronous', 'False');

  // ===========================================================================
  // CLAUDE HAIKU 4.5  |  Alias: claude-haiku-4-5
  // The fastest, near-frontier intelligence
  // Contexto:     200K tokens
  // Max output:   64K tokens
  // Thinking:     Extended thinking (WITHOUT Adaptive thinking)
  // Price:        $1 / $5 MTok (input / output)
  // Data cutoff: Jul 2025 (reliable knowledge: Feb 2025)
  // ===========================================================================
  Model := 'claude-haiku-4-5-20251001';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '16000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // ===========================================================================
  // CLAUDE SONNET 4  |  Alias: claude-sonnet-4-0  [Legacy]
  // First Sonnet of the Claude 4 family
  // Contexto:     200K tokens (1M tokens beta disponible)
  // Max output:   64K tokens
  // Thinking:     Extended thinking + Adaptive thinking
  // Precio:       $3 / $15 MTok
  // Data cutoff: Mar 2025 (reliable knowledge: Jan 2025)
  // ===========================================================================
  Model := 'claude-sonnet-4-20250514';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '16000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // ===========================================================================
  // CLAUDE OPUS 4  |  Alias: claude-opus-4-0  [Legacy]
  // First Opus of the Claude 4 family — highly capable in agents and code
  // Contexto:     200K tokens
  // Max output:   32K tokens
  // Thinking:     Extended thinking + Adaptive thinking
  // Price:        $15 / $75 MTok
  // Data cutoff: Mar 2025 (reliable knowledge: Jan 2025)
  // ===========================================================================
  Model := 'claude-opus-4-20250514';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '16000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // ===========================================================================
  // CLAUDE OPUS 4.1  |  RETIRED on 5 Aug 2026: alias of claude-opus-5-5
  // (see the Sep 2026 generation block, below). These params are
  // applied to the old name and are those of the model that now serves it.
  // ===========================================================================
  Model := 'claude-opus-4-1-20250805';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '32000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // ===========================================================================
  // CLAUDE SONNET 4.5  |  Alias: claude-sonnet-4-5  [Legacy]
  // Speed / intelligence balance — 4.5 generation
  // Contexto:     200K tokens (1M tokens beta disponible)
  // Max output:   64K tokens
  // Thinking:     Extended thinking + Adaptive thinking
  // Precio:       $3 / $15 MTok
  // Data cutoff: Jul 2025 (reliable knowledge: Jan 2025)
  // ===========================================================================
  Model := 'claude-sonnet-4-5-20250929';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '16000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // ===========================================================================
  // CLAUDE OPUS 4.5  |  Alias: claude-opus-4-5  [Legacy]
  // Best in coding and complex agent tasks — 4.5 generation
  // Contexto:     200K tokens
  // Max output:   64K tokens
  // Thinking:     Extended thinking + Adaptive thinking
  // Precio:       $5 / $25 MTok
  // Data cutoff: Aug 2025 (reliable knowledge: May 2025)
  // ===========================================================================
  Model := 'claude-opus-4-5-20251101';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '16000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // ===========================================================================
  // CLAUDE SONNET 4.6  |  Alias: claude-sonnet-4-6  [CURRENT MODEL]
  // Best speed / intelligence balance of the 4.6 family
  // Contexto:     200K tokens (1M tokens beta disponible)
  // Max output:   64K tokens
  // Thinking:     Extended thinking + Adaptive thinking
  // Precio:       $3 / $15 MTok
  // Data cutoff: Jan 2026 (reliable knowledge: Aug 2025)  <- most recent cutoff
  // ===========================================================================
  Model := 'claude-sonnet-4-6';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '32000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // ===========================================================================
  // CLAUDE OPUS 4.6  |  Alias: claude-opus-4-6  [previous generation]
  // The most intelligent Anthropic model for complex agents and code
  // Contexto:     200K tokens (1M tokens beta disponible)
  // Max output:   128K tokens  <- only model with 128K output
  // Thinking:     Extended thinking + Adaptive thinking
  // Precio:       $5 / $25 MTok
  // Data cutoff: Aug 2025 (reliable knowledge: May 2025)
  // ===========================================================================
  Model := 'claude-opus-4-6';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '32000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // ===========================================================================
  // FAMILY 4.7/4.8/5 (Jul-Aug 2026) — MANDATORY ADAPTIVE thinking
  // budget_tokens and temperature/top_p/top_k return 400 on these models;
  // the driver handles them automatically (thinking adaptive + effort).
  // All: 1M context, 128K max output, vision + PDF + reasoning + web search.
  // ===========================================================================

  // CLAUDE OPUS 4.7 — previous Opus generation (high autonomy)
  Model := 'claude-opus-4-7';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '32000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // CLAUDE OPUS 4.8 — the most capable Opus 4.x (long-horizon, knowledge work)
  Model := 'claude-opus-4-8';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '32000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // ------- Computer Use (Claude) ------
  // https://docs.claude.com/en/docs/agents-and-tools/tool-use/computer-use-tool
  // Current tool: computer_toolset_20260801 (Aug 2026). Replaces computer_20251124,
  // which the API now rejects for ALL models; those prior to opus-4-8 were
  // left without computer use (their supported tools list no longer includes it).
  // Verified against the API Sep 10/2026 — only these accept it:
  //   claude-opus-4-8, claude-opus-5, claude-sonnet-5, claude-fable-5
  // It is NOT enabled by default: cap_ComputerUse lets the model move the mouse and
  // the machine keyboard, so it is explicit user opt-in (same
  // criterion as gemini-3.5-flash). To enable it, override in the app:
  //   TAiChatFactory.Instance.RegisterUserParam('Claude', 'claude-opus-5',
  //     'ModelCaps',   '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch, cap_ComputerUse]');
  //   TAiChatFactory.Instance.RegisterUserParam('Claude', 'claude-opus-5',
  //     'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch, cap_ComputerUse]');
  // (see Demos/066-ComputerUseTest)

  // CLAUDE OPUS 5  [CURRENT MODEL — RECOMMENDED]
  // Successor to Opus 4.8 at the same price ($5/$25). Thinking active by default.
  // Classifiers may decline with stop_reason:"refusal" (the driver
  // reports it via OnError).
  Model := 'claude-opus-5';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '32000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // CLAUDE SONNET 5  [CURRENT MODEL — BEST PRICE/QUALITY]
  // Near-Opus quality in code/agents. $3/$15 (intro $2/$10 until Aug 31/2026).
  // New tokenizer: ~30% more tokens than sonnet-4-6 for the same text.
  Model := 'claude-sonnet-5';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '32000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // CLAUDE FABLE 5 — top capability ($10/$50)
  // WARNING: requires 30-day data retention in the organization (orgs with
  // ZDR receive 400 on EVERY request); thinking always active.
  Model := 'claude-fable-5';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '32000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // ===========================================================================
  // SEP 2026 GENERATION: OPUS 5.5 / SONNET 5.5 / FABLE 5.1
  // 1M context, 128K output, same tokenizer as the 5 family. Changes that
  // break versus the 5 family (the driver handles them):
  //  - thinking CANNOT be turned off ({type:"disabled"} = 400); the
  //    depth goes through output_config.effort. The driver never sends disabled.
  //  - forcing a tool (tool_choice any/tool) = 400: the driver downgrades it to auto.
  //  - thinking blocks tied to the model and to the conversation.
  // Reviewed Sep 29/2026 against the official model reference.
  // ===========================================================================

  // CLAUDE OPUS 5.5 — successor to Opus 5, CHEAPER ($4/$20). Effort by
  // default MEDIUM (Opus 5 was high): set ThinkingLevel if more is needed.
  Model := 'claude-opus-5-5';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '32000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // CLAUDE SONNET 5.5 — successor to Sonnet 5, same price ($2/$10). Accepts
  // system messages mid-conversation (Sonnet 5 does not).
  Model := 'claude-sonnet-5-5';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '32000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // CLAUDE FABLE 5.1 — successor to Fable 5, same price ($10/$50). Same as
  // Fable 5: mandatory 30-day retention (ZDR = 400) and thinking always
  // active.
  Model := 'claude-fable-5-1';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '32000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // CLAUDE OPUS 4.1 — RETIRED on 5 Aug 2026. Its names remain as aliases
  // of the official replacement (claude-opus-5-5) to avoid breaking configurations.
  TAiChatFactory.Instance.RegisterCustomModel('Claude', 'claude-opus-4-1-20250805', 'claude-opus-5-5');
  TAiChatFactory.Instance.RegisterCustomModel('Claude', 'claude-opus-4-1',          'claude-opus-5-5');
  Model := 'claude-opus-4-1';
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'Max_Tokens', '32000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // ===========================================================================
  // CUSTOM CLAUDE PROFILES (aa_*)
  // Based on current models of the 4.6 family
  //
  // ModelCaps  = what the profile declares as native to the model
  // SessionCaps = what is wanted in the session (gap enables automatic bridges)
  // ===========================================================================
  var BaseName: string;

  // 1. Sonnet 4.6 — Deep thinking (cost/reasoning balance)
  //    Gap = [] -> InternalRunCompletions with ThinkingLevel=tlHigh active
  BaseName := 'aa_claude-sonnet-4-6-thinking';
  TAiChatFactory.Instance.RegisterCustomModel('Claude', BaseName, 'claude-sonnet-4-6');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'ThinkingLevel', 'tlHigh');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'Max_Tokens', '32000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // 2. Opus 4.6 — Deep thinking (maximum reasoning capability)
  //    Gap = [] -> InternalRunCompletions with ThinkingLevel=tlHigh active
  BaseName := 'aa_claude-opus-4-6-thinking';
  TAiChatFactory.Instance.RegisterCustomModel('Claude', BaseName, 'claude-opus-4-6');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'ThinkingLevel', 'tlHigh');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'Max_Tokens', '64000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // 3. Opus 4.6 — Agents (tool calling + TextEditor + Shell enabled)
  //    Gap = [] -> InternalRunCompletions with Tool_Active=True
  //    cap_TextEditor and cap_Shell in ModelCaps enable those tools via ChatMediaSupports
  BaseName := 'aa_claude-opus-4-6-agent';
  TAiChatFactory.Instance.RegisterCustomModel('Claude', BaseName, 'claude-opus-4-6');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'Tool_Active', 'True');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'Max_Tokens', '32000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch, cap_TextEditor, cap_Shell]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch, cap_TextEditor, cap_Shell]');

  // 4. Haiku 4.5 — Fast for classification and simple tools (low cost)
  //    Gap = [] -> InternalRunCompletions with Tool_Active=True
  BaseName := 'aa_claude-haiku-4-5-tools';
  TAiChatFactory.Instance.RegisterCustomModel('Claude', BaseName, 'claude-haiku-4-5-20251001');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'Tool_Active', 'True');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'Max_Tokens', '8000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // 5. Sonnet 5 — Deep thinking (best price/quality of the 5 family)
  //    The driver sends thinking adaptive + output_config.effort=high
  BaseName := 'aa_claude-sonnet-5-thinking';
  TAiChatFactory.Instance.RegisterCustomModel('Claude', BaseName, 'claude-sonnet-5');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'ThinkingLevel', 'tlHigh');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'Max_Tokens', '32000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // 6. Opus 5 — Deep thinking (maximum capability of the Opus line)
  BaseName := 'aa_claude-opus-5-thinking';
  TAiChatFactory.Instance.RegisterCustomModel('Claude', BaseName, 'claude-opus-5');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'ThinkingLevel', 'tlHigh');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'Max_Tokens', '64000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch]');

  // 7. Opus 5 — Agents (tool calling + TextEditor + Shell enabled)
  BaseName := 'aa_claude-opus-5-agent';
  TAiChatFactory.Instance.RegisterCustomModel('Claude', BaseName, 'claude-opus-5');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'Tool_Active', 'True');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'Max_Tokens', '32000');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'ModelCaps',  '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch, cap_TextEditor, cap_Shell]');
  TAiChatFactory.Instance.RegisterUserParam('Claude', BaseName, 'SessionCaps', '[cap_Image, cap_Pdf, cap_Reasoning, cap_WebSearch, cap_TextEditor, cap_Shell]');


  // ------------------------- MISTRAL ----------------------------------
  // https://docs.mistral.ai/getting-started/models
  // Last updated: Jun 2026
  // ------------------------- MISTRAL ----------------------------------

  // --- Default global values for all Mistral models ---
  // Most support native vision -> ModelCaps=[cap_Image] by default
  TAiChatFactory.Instance.RegisterUserParam('Mistral', 'Max_Tokens',  '16000');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', 'Tool_Active', 'True');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', 'SessionCaps', '[cap_Image]');

  // ------- Frontier/generalist models (vision + reasoning_effort) ------
  // https://docs.mistral.ai/getting-started/models/overview
  // mistral-large-latest -> Mistral Large 3 (v25.12), 256K ctx, vision + tools
  // Hereda defaults: ModelCaps=[cap_Image], Tool_Active=True

  // mistral-medium-latest -> Mistral Medium 3.5 (v26.04), 256K ctx, vision + reasoning_effort + tools
  // Razonamiento configurable via reasoning_effort (low/medium/high); ver driver
  Model := 'mistral-medium-latest';
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ModelCaps',    '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'SessionCaps',  '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ThinkingLevel', 'tlMedium');

  // mistral-small-latest -> Mistral Small 4 (v26.03), 256K ctx, vision + reasoning_effort + tools
  // Razonamiento configurable via reasoning_effort (low/medium/high); ver driver
  Model := 'mistral-small-latest';
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ModelCaps',    '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'SessionCaps',  '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ThinkingLevel', 'tlMedium');

  // ------- Ministral (edge models) (vision + tools) ------
  // ministral-14b-latest -> 262K ctx, vision + tools
  // ministral-8b-latest  -> 262K ctx, vision + tools
  // ministral-3b-latest  -> 262K ctx, vision + tools
  // All inherit defaults: ModelCaps=[cap_Image], Tool_Active=True

  // ------- Reasoning: Magistral (NO vision) ------
  // https://docs.mistral.ai/getting-started/models/reasoning
  Model := 'magistral-medium-latest';
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ThinkingLevel', 'tlMedium');

  TAiChatFactory.Instance.RegisterCustomModel('Mistral', 'aa_magistral-medium-high', 'magistral-medium-latest');
  Model := 'aa_magistral-medium-high';
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ThinkingLevel', 'tlHigh');

  Model := 'magistral-small-latest';
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ThinkingLevel', 'tlMedium');

  // ------- Code: Devstral + Codestral ------
  // devstral-latest -> Devstral 2 (v25.12), 256K ctx, code agent, tools
  Model := 'devstral-latest';
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'SessionCaps', '[]');

  // devstral-small-latest -> Devstral Small 2, 24B, 256K ctx
  Model := 'devstral-small-latest';
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'SessionCaps', '[]');

  // codestral-latest -> 256K ctx, code completion, without tools
  Model := 'codestral-latest';
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'SessionCaps', '[]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'Tool_Active', 'False');

  // ------- Dedicated vision: Pixtral ------
  // pixtral-12b-latest -> 128K ctx, vision + tools
  // Hereda defaults: ModelCaps=[cap_Image], Tool_Active=True

  // pixtral-large-latest -> 131K ctx, vision + tools (frontier multimodal)
  // Inherits defaults

  // ------- Audio STT: Voxtral ------
  // cap_Audio: processes native audio; use with ChatMode=cmTranscription
  // https://docs.mistral.ai/capabilities/audio
  Model := 'voxtral-mini-latest';
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ModelCaps',   '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'SessionCaps', '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'Tool_Active', 'False');

  // voxtral-small-latest -> available Jun 2026, same caps as voxtral-mini
  Model := 'voxtral-small-latest';
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ModelCaps',   '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'SessionCaps', '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'Tool_Active', 'False');

  // ------- Voxtral TTS (Mar 23/2026) -- text-to-speech with zero-shot cloning ------
  // Gap [cap_GenAudio] enables the driver's InternalRunNativeSpeechGeneration
  // (POST /v1/audio/speech). Formats: mp3/wav/pcm/flac/opus (TtsFormat)
  Model := 'voxtral-mini-tts-2603';
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'SessionCaps', '[cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'Tool_Active', 'False');

  // ------- OCR: mistral-ocr ------
  // OCR 4 (mistral-ocr-4-0) since Jun 23/2026: mistral-ocr-latest points to it.
  // New: OcrIncludeBlocks (structural blocks with bounding boxes) and the
  // pages parameter accepts ranges ("0-5", "0,2-4")
  // ModelCaps=[] intentionally: creates Gap=[cap_Pdf] so RunNew enables Phase 1
  // (InternalRunPDFDescription → endpoint /v1/ocr). TAiMistralChat.InternalRunCompletions
  // detects the OCR-only model and skips Phase 3 (chat completions not supported).
  // https://docs.mistral.ai/capabilities/document
  Model := 'mistral-ocr-latest';
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'SessionCaps', '[cap_Pdf]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'Tool_Active', 'False');

  TAiChatFactory.Instance.RegisterCustomModel('Mistral', 'aa_mistral-ocr-pdf', 'mistral-ocr-latest');
  Model := 'aa_mistral-ocr-pdf';
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'SessionCaps', '[cap_Pdf]');
  TAiChatFactory.Instance.RegisterUserParam('Mistral', Model, 'Tool_Active', 'False');

  // ------------------------- GROK ----------------------------------
  // https://docs.x.ai/developers/models
  // Ultima actualizacion: Ago 2026 (probado runtime)
  // Current family: grok-4.5 / grok-4.3 / grok-4.20 / grok-build + grok-imagine.
  // Current text models ALWAYS REASON (reasoning_content in the
  // response) and do NOT accept frequency/presence/stop or reasoning_effort.
  // logprobs/top_logprobs NOT supported in grok-4.20 and later.
  // RETIRED Aug 2026: complete grok-3 family, grok-4-0709, grok-4-fast-*,
  // grok-4-1*, grok-code-fast-1, grok-2-vision-1212, grok-2-image-1212.
  // ------------------------- GROK ----------------------------------

  // --- Default global values for all Grok models ---
  TAiChatFactory.Instance.RegisterUserParam('Grok', 'Max_Tokens',  '16000');
  TAiChatFactory.Instance.RegisterUserParam('Grok', 'Tool_Active', 'True');
  TAiChatFactory.Instance.RegisterUserParam('Grok', 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', 'SessionCaps', '[]');

  // ------- Grok 4.3 [driver default] ------
  // 1M ctx, vision + reasoning always active (tested). $1.25/M in, $2.50/M out (<200K)
  Model := 'grok-4.3';
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'ModelCaps',   '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'SessionCaps', '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'Max_Tokens',  '32000');

  // ------- Grok 4.5 [premium, recommended for code and chat] ------
  // 500K ctx, vision + reasoning always active (tested). $2/M in, $6/M out (<200K)
  Model := 'grok-4.5';
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'ModelCaps',   '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'SessionCaps', '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'Max_Tokens',  '32000');

  // ------- Grok Build (coding, 256K ctx, reasoning always active) ------
  // $1/M in, $2/M out (<200K). No confirmed vision.
  Model := 'grok-build-0.1';
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'ModelCaps',   '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'SessionCaps', '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'Max_Tokens',  '32000');

  // Aliases of retired models to current equivalents
  TAiChatFactory.Instance.RegisterCustomModel('Grok', 'grok-3',           'grok-4.3');
  TAiChatFactory.Instance.RegisterCustomModel('Grok', 'grok-4',           'grok-4.3');
  TAiChatFactory.Instance.RegisterCustomModel('Grok', 'grok-4-0709',      'grok-4.3');
  TAiChatFactory.Instance.RegisterCustomModel('Grok', 'grok-code-fast-1', 'grok-build-0.1');

  // ------- Grok 4.20 (Mar 2026, 1M ctx, vision + tools) ------
  Model := 'grok-4.20-0309-non-reasoning';
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'Max_Tokens',  '32000');

  Model := 'grok-4.20-0309-reasoning';
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'ModelCaps',   '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'SessionCaps', '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'Max_Tokens',  '32000');

  Model := 'grok-4.20-multi-agent-0309';
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'ModelCaps',   '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'SessionCaps', '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'Max_Tokens',  '32000');

  // ------- Generacion de imagenes ------
  // ModelCaps=[]: usa endpoint dedicado; Gap=[cap_GenImage] activa InternalRunImageGeneration
  // grok-imagine-image $0.02/img; grok-imagine-image-quality $0.05/img
  Model := 'grok-imagine-image';
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'SessionCaps', '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'Tool_Active', 'False');

  Model := 'grok-imagine-image-quality';
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'SessionCaps', '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'Tool_Active', 'False');

  // Aliases of retired image models
  TAiChatFactory.Instance.RegisterCustomModel('Grok', 'grok-2-image-1212',      'grok-imagine-image');
  TAiChatFactory.Instance.RegisterCustomModel('Grok', 'grok-2-image',           'grok-imagine-image');
  TAiChatFactory.Instance.RegisterCustomModel('Grok', 'grok-imagine-image-pro', 'grok-imagine-image-quality');

  // ------- Video generation ------
  // Gap=[cap_GenVideo] enables InternalRunImageVideoGeneration
  // grok-imagine-video $0.05/sec; grok-imagine-video-1.5 $0.08/sec
  Model := 'grok-imagine-video';
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'Tool_Active', 'False');

  Model := 'grok-imagine-video-1.5';
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'Tool_Active', 'False');

  // ------- Perfiles personalizados (aa_*) ------
  // Grok with native web search (Agent Tools API - grok-4+)
  TAiChatFactory.Instance.RegisterCustomModel('Grok', 'aa_grok-3-search', 'grok-4.3');
  Model := 'aa_grok-3-search';
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'ModelCaps',   '[cap_WebSearch]');
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'SessionCaps', '[cap_WebSearch]');

  // Fast profile with reasoning (retarget: grok-4-fast-reasoning was retired)
  TAiChatFactory.Instance.RegisterCustomModel('Grok', 'aa_grok-4-fast-high', 'grok-4.20-0309-reasoning');
  Model := 'aa_grok-4-fast-high';
  TAiChatFactory.Instance.RegisterUserParam('Grok', Model, 'ThinkingLevel', 'tlHigh');

  // ------------------------- COHERE ----------------------------------
  // https://docs.cohere.com/docs/models
  // Ultima actualizacion: Ago 2026 (probado runtime)
  // ------------------------- COHERE ----------------------------------

  // --- Default global values for all Cohere models ---
  TAiChatFactory.Instance.RegisterUserParam('Cohere', 'Max_Tokens',  '8000');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', 'Tool_Active', 'True');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', 'Asynchronous', 'False');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', 'SessionCaps', '[]');

  // ------- Command A+ (may 2026) [FLAGSHIP] ------
  // command-a-plus-05-2026: MoE 218B (25B active), Apache 2.0, 436K ctx.
  // Vision + reasoning ALWAYS active (content brings a 'thinking' block before the
  // 'text'; sending thinking disabled fails with INVALID_TOOL_GENERATION).
  // $2.5/M input, $10/M output.
  Model := 'command-a-plus-05-2026';
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'ModelCaps',   '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'SessionCaps', '[cap_Image, cap_Reasoning]');

  // ------- North Mini Code (436K ctx, coding + tools) ------
  // north-mini-code-1-0: reasons by default; without cap_Reasoning the driver sends
  // thinking disabled (fast mode); add cap_Reasoning to reason.
  // north-mini-code-1-0: inherits global defaults

  // ------- Command A (288K ctx, text + tools) ------
  // command-a-03-2025: inherits global defaults (driver default)

  // ------- Command A Reasoning (256K ctx, text + tools + reasoning) ------
  Model := 'command-a-reasoning-08-2025';
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'ThinkingLevel', 'tlMedium');

  // ------- Command A Vision (128K ctx, vision, without tools) ------
  Model := 'command-a-vision-07-2025';
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'Tool_Active', 'False');

  // ------- Command A Translate (16K ctx, specialized translation, without tools) ------
  Model := 'command-a-translate-08-2025';
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'Tool_Active', 'False');

  // ------- Command R7B (128K ctx, text + tools, lightweight) ------
  // command-r7b-12-2024: inherits global defaults

  // ------- Aya Expanse (multilingual text, without tools) ------
  // The 8b (aya-expanse-8b / aya-vision-8b) are NO LONGER in /v1/models (Aug 2026)
  Model := 'c4ai-aya-expanse-32b';
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'Tool_Active', 'False');

  // ------- Aya Vision (multilingual vision, without tools, 16K ctx) ------
  Model := 'c4ai-aya-vision-32b';
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'Tool_Active', 'False');

  // ------- Tiny Aya (8K ctx, lightweight multilingual, without tools) ------
  Model := 'tiny-aya-global';
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'Max_Tokens',  '4000');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'Tool_Active', 'False');
  // tiny-aya-earth / tiny-aya-fire / tiny-aya-water: regional variants, same config
  Model := 'tiny-aya-earth';
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'Max_Tokens',  '4000');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'Tool_Active', 'False');
  Model := 'tiny-aya-fire';
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'Max_Tokens',  '4000');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'Tool_Active', 'False');
  Model := 'tiny-aya-water';
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'Max_Tokens',  '4000');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'Tool_Active', 'False');

  // ------- Rerank v4.0 (Aug 2026) ------
  // rerank-v4.0-fast / rerank-v4.0-pro: 32K ctx (vs 4K in v3.x). They are used via
  // TCohereChat.RerankModel + Rerank() method; rerank-english-v3.0 remains active.

  // ------- Audio STT: cohere-transcribe (Mar 2026) ------
  // cap_Audio: processes native audio; use with ChatMode=cmTranscription
  // https://docs.cohere.com/docs/cohere-transcribe
  Model := 'cohere-transcribe-03-2026';
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'ModelCaps',   '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'SessionCaps', '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('Cohere', Model, 'Tool_Active', 'False');

  // ------------------------- DEEPSEEK ----------------------------------
  // https://api-docs.deepseek.com/quick_start/pricing
  // ------------------------- DEEPSEEK ----------------------------------
  // https://api-docs.deepseek.com/ — updated Sep 2026, tested at runtime
  // V4 (Apr 2026): only models in /v1/models. 1M ctx / 384K output both.
  // Sep 2026: RENAME. The canonical ones are 'deepseek-flash' and 'deepseek-v4-pro'.
  // 'deepseek-v4-flash' and 'deepseek-v4-flash-vision-exp' are still accepted as
  // aliases, but those models were retired (they route to the new flash).
  // v4-pro CONTINUES after 14 Sep 2026 (official notice), billing unchanged.
  // The API enables thinking by default (effort=high); the driver controls it:
  // cap_Reasoning => thinking enabled + reasoning_effort (tlLow=low, tlMedium=high,
  // tlHigh=max); without cap_Reasoning the driver sends thinking disabled (fast mode).
  // WARNING pricing: peak/off-peak rates are ALREADY IN EFFECT. Off-peak you pay
  // half; peak hours 01:00-04:00 and 06:00-10:00 UTC Monday through Friday.

  // --- Default global values for all DeepSeek models ---
  TAiChatFactory.Instance.RegisterUserParam('DeepSeek', 'Max_Tokens',  '8192');
  TAiChatFactory.Instance.RegisterUserParam('DeepSeek', 'Tool_Active', 'True');
  TAiChatFactory.Instance.RegisterUserParam('DeepSeek', 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('DeepSeek', 'SessionCaps', '[]');

  // ------- DeepSeek Flash [CURRENT MODEL - driver default] ------
  // Peak price: $0.30/M in (miss) / $0.003/M (hit) / $1.20/M out.
  // Off-peak it is HALF. Peak hours 01:00-04:00 and 06:00-10:00 UTC (Mon-Fri).
  // Without cap_Reasoning by default = fast mode; to reason add
  // ModelCaps [cap_Reasoning] + ThinkingLevel
  Model := 'deepseek-flash';
  TAiChatFactory.Instance.RegisterUserParam('DeepSeek', Model, 'Max_Tokens', '65536');

  // Legacy alias: the original model was retired, the name still routes
  // to the new deepseek-flash. It remains registered for old configurations.
  Model := 'deepseek-v4-flash';
  TAiChatFactory.Instance.RegisterUserParam('DeepSeek', Model, 'Max_Tokens', '65536');

  // ------- DeepSeek V4 Pro (reasoning by default) ------
  // 1.6T params (49B active). Peak price: $1.32/M in (miss) / $0.022/M (hit)
  // / $3.96/M out; off-peak half ($1.98/M out)
  // Note: in v4-pro the API maps effort low->high (minimum supported, Aug 2026)
  Model := 'deepseek-v4-pro';
  TAiChatFactory.Instance.RegisterUserParam('DeepSeek', Model, 'Max_Tokens', '65536');
  TAiChatFactory.Instance.RegisterUserParam('DeepSeek', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('DeepSeek', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('DeepSeek', Model, 'ThinkingLevel', 'tlMedium');

  // ------- Aliases OFFICIALLY RETIRED on 24 Jul 2026 ------
  // deepseek-chat and deepseek-reasoner still route to v4-flash (no-thinking/thinking)
  // in a grace period, but do NOT depend on them. deepseek-reasoner keeps
  // its entry so existing configurations keep reasoning.
  Model := 'deepseek-reasoner';
  TAiChatFactory.Instance.RegisterUserParam('DeepSeek', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('DeepSeek', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('DeepSeek', Model, 'ThinkingLevel', 'tlMedium');

  // ------------------------- GLM (Zhipu AI / Z.ai) -----------------
  // https://docs.z.ai/api-reference/llm/chat-completion
  // Last updated: Aug 2026 (capabilities verified vs official docs;
  // registered WITHOUT runtime testing)
  // ------------------------- GLM (Zhipu AI / Z.ai) -----------------
  // The API has thinking ENABLED by default in glm-4.7/5.x; the driver
  // controls it explicitly based on cap_Reasoning (DeepSeek V4 pattern).
  // glm-5.3 uses FORCED thinking (does not accept disabled - the driver handles it).
  // reasoning_effort (low/high/max, default max) only glm-5.2/5.3.
  // tool_choice: the API only supports 'auto'. Maximum output 128K (16K in 4.5v).
  // International endpoint api.z.ai; for mainland China change URL to
  // https://open.bigmodel.cn/api/paas/v4/. Bounded sampling: temperature [0,1],
  // top_p [0.01,1], max_tokens up to 131072 (clamp in the driver).

  // --- Default global values for all GLM models ---
  TAiChatFactory.Instance.RegisterUserParam('GLM', 'Max_Tokens',  '8192');
  TAiChatFactory.Instance.RegisterUserParam('GLM', 'Tool_Active', 'True');
  TAiChatFactory.Instance.RegisterUserParam('GLM', 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('GLM', 'SessionCaps', '[]');

  // ------- GLM-4.7 [driver default] ------
  // 200K ctx / 128K out. Cost/capability balance: $0.60/M in / $2.20/M out.
  // Without cap_Reasoning by default = fast mode (the driver sends disabled);
  // to reason add ModelCaps [cap_Reasoning]
  Model := 'glm-4.7';
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'Max_Tokens', '16384');

  // ------- GLM-4.7-Flash (FREE) ------
  // No cost for registered accounts (includes input cache); prototypes
  Model := 'glm-4.7-flash';
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'Max_Tokens', '16384');

  // ------- GLM-4.7-FlashX (lightweight fast, $0.07/M in / $0.40/M out) ------
  Model := 'glm-4.7-flashx';
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'Max_Tokens', '16384');

  // ------- GLM-5.3 (Aug 14/2026) -- flagship coding open-weights ------
  // 1M ctx / 128K out. MoE ~744B (40B active). $1.40/M in / $4.40/M out.
  // FORCED thinking: cannot be disabled (the driver always sends enabled);
  // reasoning_effort low/high/max (default max) via ThinkingLevel
  Model := 'glm-5.3';
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'Max_Tokens',    '32768');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'ThinkingLevel', 'tlMedium');

  // ------- GLM-5.2 (Jun 2026) -- 1M ctx / 128K out, reasoning_effort ------
  // $1.40/M in / $4.40/M out
  Model := 'glm-5.2';
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'Max_Tokens',    '32768');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'ThinkingLevel', 'tlMedium');

  // ------- GLM-5.1 (long-running agents) ------
  // $1.40/M in / $4.40/M out; autonomous sessions up to 8h
  Model := 'glm-5.1';
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'Max_Tokens',    '32768');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'ThinkingLevel', 'tlMedium');

  // ------- GLM-5 (200K ctx / 128K out, deep reasoning) ------
  // $1.00/M in / $3.20/M out
  Model := 'glm-5';
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'Max_Tokens',    '32768');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'ThinkingLevel', 'tlMedium');

  // ------- GLM-5-Turbo (high-throughput agents) ------
  // 200K ctx / 128K out. $1.20/M in / $4.00/M out. Without cap_Reasoning by
  // default = the driver sends thinking disabled (fast response)
  Model := 'glm-5-turbo';
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'Max_Tokens', '16384');

  // ------- GLM-5V-Turbo (vision + tools + agents) ------
  // 200K ctx / 128K out. $1.20/M in / $4.00/M out. Image/video/file input
  Model := 'glm-5v-turbo';
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'SessionCaps', '[cap_Image]');

  // ------- GLM-4.6V (vision, 128K ctx) ------
  // $0.30/M in / $0.90/M out. First V family with NATIVE function calling
  // (images as tool parameters)
  Model := 'glm-4.6v';
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'SessionCaps', '[cap_Image]');

  // ------- GLM-4.6V-Flash (FREE vision, 128K ctx) ------
  Model := 'glm-4.6v-flash';
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'SessionCaps', '[cap_Image]');

  // ------- GLM-4.6V-FlashX (lightweight vision, $0.04/M in / $0.40/M out) ------
  Model := 'glm-4.6v-flashx';
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'SessionCaps', '[cap_Image]');

  // ------- GLM-4.5V (vision open-source ~100B) ------
  // $0.60/M in / $1.80/M out. Maximum output 16K. WITHOUT function calling
  // (native FC in vision arrived with 4.6V)
  Model := 'glm-4.5v';
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'Tool_Active', 'False');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'Max_Tokens',  '8192');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('GLM', Model, 'SessionCaps', '[cap_Image]');

  // ------------------------- QWEN (Alibaba Model Studio) ----------
  // https://www.alibabacloud.com/help/en/model-studio/models
  // Registered Sep 28 2026. Everything marked 'tested' was verified at runtime against
  // dashscope-intl (Singapore). Key: @DASHSCOPE_API_KEY (tied to its region).
  // The account exposes ~170 models (also DeepSeek, GLM and Kimi served by
  // Alibaba); here the tested ones are registered. Any other id works with the
  // global params by assigning it in Model.
  // Reasoning: the driver sends enable_thinking=true only with cap_Reasoning in
  // ModelCaps; hybrids are registered WITHOUT the cap (fast) and it is enabled
  // by adding it. ThinkingLevel -> thinking_budget (tlLow 1024, tlMedium 4096,
  // tlHigh 16384, tlDefault no limit).
  // ------------------------- QWEN (Alibaba Model Studio) ----------

  // --- Default global values for all Qwen models ---
  TAiChatFactory.Instance.RegisterUserParam('Qwen', 'Max_Tokens',  '8192');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', 'Tool_Active', 'True');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', 'SessionCaps', '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', 'ThinkingLevel', 'tlDefault');

  // ------- Flagship multimodal (text + image) -- tested ------
  // qwen3.8-flash: driver default; fast, vision, hybrid reasoning, tools+stream
  Model := 'qwen3.8-flash';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_Image]');

  // qwen3.8-max: the most capable; vision, hybrid reasoning
  Model := 'qwen3.8-max';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_Image]');

  // qwen3.7-plus: vision, hybrid reasoning
  Model := 'qwen3.7-plus';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_Image]');

  // qwen3-vl-flash: dedicated vision
  Model := 'qwen3-vl-flash';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_Image]');

  // qwen3.8-omni-flash: omnimodal; tested with image and with input audio
  // (sync and stream; the driver converts audio to a data URI). Video untested
  Model := 'qwen3.8-omni-flash';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[cap_Image, cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_Image, cap_Audio]');

  // ------- Text -- tested (hybrid reasoning, WITHOUT vision) ------
  // qwen3-max, qwen-plus, qwen-flash, qwen-turbo: use the globals ([] = fast)
  TAiChatFactory.Instance.RegisterUserParam('Qwen', 'qwen3-max',  'Max_Tokens', '8192');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', 'qwen-plus',  'Max_Tokens', '8192');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', 'qwen-flash', 'Max_Tokens', '8192');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', 'qwen-turbo', 'Max_Tokens', '8192');

  // ------- Code -- tested (they do not reason: enable_thinking is ignored) ------
  TAiChatFactory.Instance.RegisterUserParam('Qwen', 'qwen3-coder-plus',  'Max_Tokens', '8192');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', 'qwen3-coder-flash', 'Max_Tokens', '8192');

  // ------- Reasoning only -- tested ------
  // qwq-plus: ONLY responds in streaming (without stream it returns empty and without error)
  Model := 'qwq-plus';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Asynchronous', 'True');

  // qwen3-235b-a22b-thinking-2507: open weights, reasons with and without stream
  Model := 'qwen3-235b-a22b-thinking-2507';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_Reasoning]');

  // ------- Phase 2: image generation [cap_GenImage] -- tested ------
  // Gap [cap_GenImage] -> InternalRunNativeImageGeneration (native API, synchronous).
  // Size: ImageParams.Params.Values['size'] (default 1024*1024; qwen-image-plus
  // only accepts 1328*1328, 1664*928, 928*1664, 1472*1104, 1104*1472)
  Model := 'qwen-image-3.0';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'qwen-image-3.0-pro';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'qwen-image-2.0';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'qwen-image-2.0-pro';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'qwen-image-max';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'z-image-turbo';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'wan2.7-image';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'wan2.7-image-pro';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');

  // ------- Image editing [cap_GenImage] -- tested ------
  // Images attached to the prompt (1 to 3) are the input. Without 'size' the
  // original aspect ratio is preserved. qwen-image-2.0/3.0 and wan2.7-image
  // also edit; z-image-turbo does not. Times: plus ~9 s, edit ~17 s, max ~40 s
  Model := 'qwen-image-edit-plus';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'qwen-image-edit';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'qwen-image-edit-max';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenImage]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');

  // ------- Video (wan) [cap_GenVideo] ------
  // Asynchronous task (5 s of video: wan2.6 ~45 s, wan2.7 ~95 s). Attached images:
  // 0 = text to video, 1 = image to video (a -t2v switches to its -i2v), 2 = first and
  // last frame (kf2v). Default 720P; VideoParams.Params passes to the API
  // (duration 2-15 in wan2.6/2.7; wan2.1/2.2 do not accept duration). wan2.5+ includes audio.
  Model := 'wan2.6-t2v';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'wan2.7-t2v';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'wan2.5-t2v-preview';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'wan2.2-t2v-plus';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'wan2.1-t2v-turbo';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'wan2.1-t2v-plus';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'wan2.6-i2v-flash';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'wan2.6-i2v';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'wan2.7-i2v';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'wan2.5-i2v-preview';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'wan2.2-i2v-flash';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'wan2.2-i2v-plus';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'wan2.1-i2v-turbo';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'wan2.2-kf2v-flash';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'wan2.1-kf2v-plus';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenVideo]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');

  // ------- Text translation (qwen-mt) -- tested ------
  // The driver sends only the last user message + translation_options (the API
  // rejects system, history and tools). Languages in TranslateTo / TranslateFrom
  // (Params), glossary in TranslateTerms, domain in TranslateDomain.
  // qwen-mt-plus translates domain terms better ("caja menor" -> petty cash);
  // flash/turbo/lite get them right with TranslateTerms or TranslateDomain
  Model := 'qwen-mt-plus';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'qwen-mt-flash';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'qwen-mt-turbo';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'qwen-mt-lite';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');

  // ------- Phase 2: voice (TTS) [cap_GenAudio] -- tested ------
  // Voice in TtsParams.Voice (default Cherry; also Ethan...), language in
  // TtsParams.Language ('es' or 'Spanish'; empty = Auto). Returns a WAV.
  Model := 'qwen3-tts-flash';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'qwen3-tts-instruct-flash';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');

  // ------- Custom voices (TAiQwenVoices) -- tested ------
  // A cloned voice (qwen-tts-vc-*) or designed voice (qwen-tts-vd-*) only works with
  // its model; the driver chooses it by the prefix of TtsParams.Voice
  Model := 'qwen3-tts-vc-2026-01-22';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');
  Model := 'qwen3-tts-vd-2026-01-26';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_GenAudio]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');

  // ------- Phase 2: transcription (ASR) -- tested ------
  // Use with ChatMode = cmTranscription: the Prompt travels as context for the
  // recognizer (proper nouns). A text model with SessionCaps [cap_Audio]
  // also transcribes with this model before responding (Phase 1 bridge).
  Model := 'qwen3-asr-flash';
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'ModelCaps',   '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'SessionCaps', '[cap_Audio]');
  TAiChatFactory.Instance.RegisterUserParam('Qwen', Model, 'Tool_Active', 'False');

  // ------------------------- KIMI ----------------------------------
  // https://platform.moonshot.ai/docs/api/chat
  // Ultima actualizacion: May 2026
  // ------------------------- KIMI ----------------------------------

  // --- Default global values for all Kimi models ---
  TAiChatFactory.Instance.RegisterUserParam('Kimi', 'Max_Tokens',  '16000');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', 'Tool_Active', 'True');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', 'Temperature', '1');
  // top_p REMOVED from defaults: the new family (k3/k2.6/k2.7) returns
  // 400 if top_p is sent (only accepts temperature) — verified at runtime Aug 2026
  TAiChatFactory.Instance.RegisterUserParam('Kimi', 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', 'SessionCaps', '[]');

  // ------- Kimi K3 (Jul 16/2026) -- flagship, 1M ctx  [CURRENT MODEL] ------
  // Successor to the K2 family (~2.8T MoE). Flat price across the entire context:
  // $3/M input (cache-miss), $0.30/M cache-hit, $15/M output.
  Model := 'kimi-k3';
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'Max_Tokens',   '16000');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'ModelCaps',    '[cap_Image, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'SessionCaps',  '[cap_Image, cap_Reasoning]');

  // ------- Kimi K2.7 Code (Jul 2026) -- coding multimodal ------
  Model := 'kimi-k2.7-code';
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'ModelCaps',    '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'SessionCaps',  '[cap_Image]');

  Model := 'kimi-k2.7-code-highspeed';
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'ModelCaps',    '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'SessionCaps',  '[cap_Image]');

  // ------- Kimi K2.6 (256K ctx, vision + text + tools) ------
  Model := 'kimi-k2.6';
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'ModelCaps',    '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'SessionCaps',  '[cap_Image]');

  // kimi-latest: moving alias to the most recent model (inherits defaults)

  // ------- Kimi K2.5 -- RETIRES on 31 Aug 2026 (migrate to kimi-k3) ------
  Model := 'kimi-k2.5';
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'ModelCaps',    '[cap_Image, cap_Pdf, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'SessionCaps',  '[cap_Image, cap_Pdf, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'ThinkingLevel', 'tlMedium');

  // RETIRED from the API (Jul 2026): kimi-k2 and kimi-k2-thinking no longer exist
  // in /v1/models — entries removed from the registry.

  // ------- Moonshot V1 Legacy -- FULL SUNSET on 31 Aug 2026 ------
  Model := 'moonshot-v1-8k';
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'Max_Tokens',  '4096');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'Tool_Active', 'False');

  Model := 'moonshot-v1-32k';
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'Max_Tokens',  '16000');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'Tool_Active', 'False');

  Model := 'moonshot-v1-128k';
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'Max_Tokens',  '65536');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'Tool_Active', 'False');

  // ------- Moonshot V1 Vision Preview (vision, without tools) ------
  Model := 'moonshot-v1-8k-vision-preview';
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'Max_Tokens',  '4096');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'Tool_Active', 'False');

  Model := 'moonshot-v1-32k-vision-preview';
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'Max_Tokens',  '16000');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'Tool_Active', 'False');

  Model := 'moonshot-v1-128k-vision-preview';
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'Max_Tokens',  '65536');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('Kimi', Model, 'Tool_Active', 'False');

  // ------------------------- LMSTUDIO ----------------------------------
  // https://lmstudio.ai
  // Ultima actualizacion: May 2026
  // Local inference OpenAI-compatible (http://127.0.0.1:1234/v1/)
  // ------------------------- LMSTUDIO ----------------------------------

  // --- Global values (conservative: text, without tools) ---
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', 'Max_Tokens',  '4096');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', 'Tool_Active', 'False');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', 'SessionCaps', '[]');

  // ------- Llama 3.3 70B (text + tools) ------
  Model := 'llama-3.3-70b-instruct';
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'Tool_Active', 'True');

  // ------- Qwen 2.5 7B (text + tools) ------
  Model := 'qwen2.5-7b-instruct';
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'Tool_Active', 'True');

  // ------- DeepSeek R1 7B (reasoning) ------
  Model := 'deepseek-r1-7b';
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'ThinkingLevel', 'tlMedium');

  // ------- Llama 3.2 11B Vision (vision) ------
  Model := 'llama-3.2-11b-vision-instruct';
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'SessionCaps', '[cap_Image]');

  // ------- Mistral 7B (text + tools) ------
  Model := 'mistral-7b-instruct-v0.3';
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'Tool_Active', 'True');

  // ------- Gemma 3 (vision + tools, sizes: 4b/12b/27b) ------
  // In LM Studio the ID is the model name or alias configured in the app
  Model := 'gemma-3-4b-it';
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'Tool_Active', 'True');

  Model := 'gemma-3-12b-it';
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'Tool_Active', 'True');

  Model := 'gemma-3-27b-it';
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'Tool_Active', 'True');

  // ------- Gemma 4 (vision + audio + reasoning + tools) ------
  // In LM Studio the ID is the name/alias configured in the app
  Model := 'gemma-4-4b-it';
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'ModelCaps',    '[cap_Image, cap_Audio, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'SessionCaps',  '[cap_Image, cap_Audio, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'ThinkingLevel', 'tlMedium');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'Tool_Active',  'True');

  Model := 'gemma-4-12b-it';
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'ModelCaps',    '[cap_Image, cap_Audio, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'SessionCaps',  '[cap_Image, cap_Audio, cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'ThinkingLevel', 'tlMedium');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'Tool_Active',  'True');

  // ------- Qwen3 (reasoning + tools) ------
  Model := 'qwen3-8b';
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'ThinkingLevel', 'tlMedium');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'Tool_Active',  'True');

  Model := 'qwen3-14b';
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'ModelCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'SessionCaps',  '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'ThinkingLevel', 'tlMedium');
  TAiChatFactory.Instance.RegisterUserParam('LMStudio', Model, 'Tool_Active',  'True');

  // ------------------------- GENERICLLM ----------------------------------
  // Driver for any OpenAI-compatible API
  // Ultima actualizacion: May 2026
  // Configure: DriverName='GenericLLM', URL='http://host/v1/', Model='model-name'
  // ------------------------- GENERICLLM ----------------------------------

  // --- Conservative global values (the user configures everything manually) ---
  TAiChatFactory.Instance.RegisterUserParam('GenericLLM', 'Max_Tokens',  '4096');
  TAiChatFactory.Instance.RegisterUserParam('GenericLLM', 'Tool_Active', 'False');
  TAiChatFactory.Instance.RegisterUserParam('GenericLLM', 'ModelCaps',   '[]');
  TAiChatFactory.Instance.RegisterUserParam('GenericLLM', 'SessionCaps', '[]');

  // ------------------------- MAKERAI -------------------------------------
  // Driver for MakerAI API (https://api.cimamaker.com/v1/).
  // Phase 1: compatible with OpenAI Chat Completions API.
  // Phase 2: own endpoints via overrides of InternalRunCompletions/ParseChat.
  // API Key: environment variable MAKERAI_API_KEY
  // Ultima actualizacion: May 2026
  // ------------------------- MAKERAI -------------------------------------

  // --- Default global values ---
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', 'Max_Tokens',   '16000');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', 'Temperature',  '1');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', 'Tool_Active',  'True');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', 'Asynchronous', 'True');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', 'ModelCaps',    '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', 'SessionCaps',  '[cap_Image]');

  // --- Chat models ---
  // mk-pro: advanced model (OpenAI-backed), vision + web_search + code_execution + file_reader
  Model := 'mk-pro';
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'ModelCaps',   '[cap_Image, cap_Pdf, cap_WebSearch, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'SessionCaps', '[cap_Image, cap_Pdf, cap_WebSearch, cap_CodeInterpreter]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'Tool_Active', 'True');

  // mk-claude-sonnet: Claude Sonnet via MKAI — vision + all Claude mk_tools
  // (web_search, code_execution, computer_use, text_editor, bash, memory, file_reader)
  Model := 'mk-claude-sonnet';
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'ModelCaps',
    '[cap_Image, cap_Pdf, cap_WebSearch, cap_CodeInterpreter, cap_ComputerUse, cap_TextEditor, cap_Shell, cap_Memory]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'SessionCaps',
    '[cap_Image, cap_Pdf, cap_WebSearch, cap_CodeInterpreter, cap_ComputerUse, cap_TextEditor, cap_Shell, cap_Memory]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'Tool_Active', 'True');

  // mk-gpt-oss-20b: main chat model, reasoning + vision + file_reader
  Model := 'mk-gpt-oss-20b';
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'ModelCaps',    '[cap_Reasoning, cap_Image, cap_Pdf]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'SessionCaps',  '[cap_Reasoning, cap_Image, cap_Pdf]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'ThinkingLevel', 'tlMedium');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'Tool_Active',  'True');

  // mk-think: specialized reasoning + vision (confirmed May 2026)
  Model := 'mk-think';
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'ModelCaps',    '[cap_Reasoning, cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'SessionCaps',  '[cap_Reasoning, cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'ThinkingLevel', 'tlMedium');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'Tool_Active',  'True');

  // mk-basic-8b: lightweight model, without vision, without tools, with file_reader
  Model := 'mk-basic-8b';
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'ModelCaps',   '[cap_Pdf]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'SessionCaps', '[cap_Pdf]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'Tool_Active', 'False');

  // mk-scout: server-side multi-provider routing (Llama-4-scout via Groq / Gemini / Mistral fallback).
  // Routes 1 and 2 have vision; all have file_reader.
  Model := 'mk-scout';
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'ModelCaps',   '[cap_Image, cap_Pdf]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'SessionCaps', '[cap_Image, cap_Pdf]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'Tool_Active', 'True');

  // mk-local-fast, mk-local-coder: local models without vision (Mistral-small-latest)
  for Model in ['mk-local-fast', 'mk-local-coder'] do
  begin
    TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'ModelCaps',   '[]');
    TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'SessionCaps', '[]');
    TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'Tool_Active', 'True');
  end;

  Model := 'mk-local-smart';
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'ModelCaps',   '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'SessionCaps', '[cap_Image]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'Tool_Active', 'True');

  // mk-nanobanana family
  for Model in ['mk-nanobanana', 'mk-nanobanana-2', 'mk-nanobanana-pro'] do
  begin
    TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'ModelCaps',   '[cap_Image]');
    TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'SessionCaps', '[cap_Image]');
    TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'Tool_Active', 'False');
  end;

  // --- DeepSeek via broker (text only) ---
  // These entries were missing: without them the models inherited the global default
  // ModelCaps=[cap_Image] and declared a vision that DeepSeek does not have in its
  // public API. 'mk-deepseek-flash' follows the Sep 2026 rename;
  // 'mk-deepseek-v4-flash' is the name the broker used in production and is
  // kept as an alias. Without cap_Reasoning = fast mode, as in the
  // direct DeepSeek driver.
  for Model in ['mk-deepseek-flash', 'mk-deepseek-v4-flash'] do
  begin
    TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'ModelCaps',   '[]');
    TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'SessionCaps', '[]');
    TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'Tool_Active', 'True');
  end;

  // mk-deepseek-v4-pro: reasoning by default (direct driver pattern)
  Model := 'mk-deepseek-v4-pro';
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'ModelCaps',      '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'SessionCaps',    '[cap_Reasoning]');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'ThinkingLevel',  'tlMedium');
  TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'Tool_Active',    'True');

  // --- Image generation ---
  // The 2.5 family (flare/sunburst, Sep 2026) accepts quality xhigh/max and
  // real transparent background with real alpha; the broker translates the mk- name to OpenAi's.
  for Model in ['mk-gpt-image-1', 'mk-gpt-image-1.5', 'mk-gpt-image-1-mini', 'mk-gpt-image-2',
                'mk-gpt-image-2.5-flare', 'mk-gpt-image-2.5-sunburst'] do
  begin
    TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'ModelCaps',   '[]');
    TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'SessionCaps', '[cap_GenImage]');
    TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'Tool_Active', 'False');
  end;

  // --- STT (Transcription) ---
  for Model in ['mk-whisper-large', 'mk-whisper-medium', 'mk-whisper-turbo'] do
  begin
    TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'ModelCaps',   '[cap_Audio]');
    TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'SessionCaps', '[cap_Audio]');
    TAiChatFactory.Instance.RegisterUserParam('MakerAi', Model, 'Tool_Active', 'False');
  end;

End;

Procedure InitEmbeddingModels;
Begin
  // OpenAI - additional models with specific dimensions
  TAiEmbeddingFactory.Instance.RegisterUserParam('OpenAi', 'text-embedding-3-large', 'Dimensions', '3072');
  TAiEmbeddingFactory.Instance.RegisterUserParam('OpenAi', 'text-embedding-ada-002', 'Dimensions', '1536');

  // Ollama - common embedding models
  TAiEmbeddingFactory.Instance.RegisterUserParam('Ollama', 'nomic-embed-text', 'Dimensions', '768');
  TAiEmbeddingFactory.Instance.RegisterUserParam('Ollama', 'mxbai-embed-large', 'Dimensions', '1024');

  // Gemini - text-embedding-004 deprecated (shutdown Jan 2026); use text-embedding-005
  TAiEmbeddingFactory.Instance.RegisterUserParam('Gemini', 'text-embedding-004', 'Dimensions', '768');
  TAiEmbeddingFactory.Instance.RegisterUserParam('Gemini', 'text-embedding-005', 'Dimensions', '768');
  // gemini-embedding-2 (GA Apr 22/2026): multimodal (text + image via File
  // Search); 3072 dims by default (MRL allows truncating). WITHOUT runtime testing
  TAiEmbeddingFactory.Instance.RegisterUserParam('Gemini', 'gemini-embedding-2', 'Dimensions', '3072');

  // Cohere - embedding models
  TAiEmbeddingFactory.Instance.RegisterUserParam('Cohere', 'embed-multilingual-v3.0', 'Dimensions', '1024');
  TAiEmbeddingFactory.Instance.RegisterUserParam('Cohere', 'embed-v4.0',              'Dimensions', '1536');
End;

Initialization

InitChatModels;
InitEmbeddingModels;

end.
