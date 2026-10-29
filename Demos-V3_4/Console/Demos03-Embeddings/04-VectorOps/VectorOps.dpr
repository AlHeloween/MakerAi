program VectorOps;

{$APPTYPE CONSOLE}
{$R *.res}

// =============================================================================
// MakerAI — 03-Embeddings / 04-VectorOps
// =============================================================================
// Demonstrates algebraic operations with embedding vectors:
// dot product, cosine similarity, L2 distance, addition, subtraction,
// averaging, interpolation and normalization, with the classic analogy
// king - man + woman approx queen.
//
// Concepts covered (sections 21.3 to 21.6 of the book):
//   - DotProduct, CosineSimilarity, EuclideanDistance
//   - Averaging embeddings (AverageEmbedding)
//   - Adding and subtracting (VectorAdd, VectorSubtract)
//   - Classic analogy: king - man + woman approx queen
//   - Manual interpolation between two concepts
//   - Normalization (Normalize)
//
// Provider: local Ollama (no cost, no API key)
//   Main model: mxbai-embed-large:latest
//   Alternatives:     snowflake-arctic-embed:latest
//                     embeddinggemma:latest
// =============================================================================

uses
  System.SysUtils,
  System.Math,
  uMakerAi.Embeddings.core,
  uMakerAi.Embeddings.Connection,
  uMakerAi.Embeddings.Ollama;

const
  DRIVER = 'Ollama';
  MODEL  = 'mxbai-embed-large:latest';
  URL    = 'http://localhost:11434/api/';

// -----------------------------------------------------------------------------
//  Presentation helpers
// -----------------------------------------------------------------------------
procedure Titulo(const S: String);
begin
  Writeln;
  Writeln(StringOfChar('-', 62));
  Writeln(S);
  Writeln(StringOfChar('-', 62));
end;

function NivelSim(Sim: Double): String;
begin
  if Sim >= 0.90 then Result := 'very high'
  else if Sim >= 0.70 then Result := 'high'
  else if Sim >= 0.50 then Result := 'medium'
  else if Sim >= 0.30 then Result := 'low'
  else Result := 'very low';
end;

var GDimsLog: Boolean = False;

function E(Conn: TAiEmbeddingConnection; const Texto: String): TAiEmbeddingData;
begin
  Result := Conn.CreateEmbedding(Texto, 'user');
  if not GDimsLog and (Length(Result) > 0) then
  begin
    Writeln(Format('  [model: %s  dims: %d]', [MODEL, Length(Result)]));
    GDimsLog := True;
  end;
end;

// =============================================================================
//  Section 1 — Dot product and basic metrics (book sec. 21.3-21.5)
// =============================================================================
procedure SeccionMetricas(Conn: TAiEmbeddingConnection);
var
  VFr, VDr, VAv: TAiEmbeddingData;
begin
  Titulo('Sec. 21.3-21.5  Dot product, cosine similarity and L2 distance');

  Writeln('  Vectorizing: "medico", "doctor", "avion" ...');
  VFr := E(Conn, 'medico');
  VDr := E(Conn, 'doctor');
  VAv := E(Conn, 'avion');
  Writeln;

  Writeln(Format('  DotProduct(medico, doctor) = %.4f', [TAiEmbeddingsCore.DotProduct(VFr, VDr)]));
  Writeln(Format('  DotProduct(medico, avion)  = %.4f', [TAiEmbeddingsCore.DotProduct(VFr, VAv)]));
  Writeln;

  var SimMD := TAiEmbeddingsCore.CosineSimilarity(VFr, VDr);
  var SimMA := TAiEmbeddingsCore.CosineSimilarity(VFr, VAv);

  Writeln(Format('  CosineSimilarity(medico, doctor) = %.4f  [%s]', [SimMD, NivelSim(SimMD)]));
  Writeln(Format('  CosineSimilarity(medico, avion)  = %.4f  [%s]', [SimMA, NivelSim(SimMA)]));
  Writeln;

  Writeln(Format('  EuclideanDistance(medico, doctor) = %.4f  (smaller = closer)', [TAiEmbeddingsCore.EuclideanDistance(VFr, VDr)]));
  Writeln(Format('  EuclideanDistance(medico, avion)  = %.4f', [TAiEmbeddingsCore.EuclideanDistance(VFr, VAv)]));
end;

// =============================================================================
//  Section 2 — Averaging embeddings (book sec. 21.6 op. 1)
// =============================================================================
procedure SeccionPromediar(Conn: TAiEmbeddingConnection);
var
  Palabras: TArray<String>;
  Vectores: TAiEmbeddingList;
  Promedio: TAiEmbeddingData;
  I: Integer;
begin
  Titulo('Sec. 21.6  Operation 1 — Averaging (general topic of a group)');

  Palabras := ['perro', 'gato', 'caballo', 'conejo', 'pajaro'];
  Writeln(Format('  Averaging %d animals: %s', [Length(Palabras), String.Join(', ', Palabras)]));

  SetLength(Vectores, Length(Palabras));
  for I := 0 to High(Palabras) do
    Vectores[I] := E(Conn, Palabras[I]);

  Promedio := TAiEmbeddingsCore.AverageEmbedding(Vectores);

  Writeln;
  Writeln('  Similarity of the average vector with each animal:');
  for I := 0 to High(Palabras) do
    Writeln(Format('    %s: %.4f', [Palabras[I], TAiEmbeddingsCore.CosineSimilarity(Promedio, Vectores[I])]));

  Writeln;
  var VAnimal := E(Conn, 'animal domestico');
  var VCoche  := E(Conn, 'automovil');
  Writeln('  Comparison with external words:');
  Writeln(Format('    "animal domestico": %.4f  (expected: high)', [TAiEmbeddingsCore.CosineSimilarity(Promedio, VAnimal)]));
  Writeln(Format('    "automovil":        %.4f  (expected: low)', [TAiEmbeddingsCore.CosineSimilarity(Promedio, VCoche)]));
end;

// =============================================================================
//  Section 3 — Adding embeddings: search A AND B (book sec. 21.6 op. 2)
// =============================================================================
procedure SeccionSuma(Conn: TAiEmbeddingConnection);
var
  VGato, VRojo, VCombinado: TAiEmbeddingData;
  Candidatos: TArray<String>;
  Vectores: TAiEmbeddingList;
  I: Integer;
begin
  Titulo('Sec. 21.6  Operation 2 — Addition: cat + red (semantic AND)');

  Writeln('  We look for documents that talk about BOTH concepts: cat AND red');
  Candidatos := ['gato rojo', 'gato azul', 'perro rojo', 'auto rojo', 'gato negro', 'flor roja'];

  VGato      := E(Conn, 'gato');
  VRojo      := E(Conn, 'rojo');
  VCombinado := TAiEmbeddingsCore.VectorAdd(VGato, VRojo);

  SetLength(Vectores, Length(Candidatos));
  for I := 0 to High(Candidatos) do
    Vectores[I] := E(Conn, Candidatos[I]);

  var Res := TAiEmbeddingsCore.FindTopK(VCombinado, Vectores, 3);

  Writeln;
  Writeln('  Top 3 closest to the vector (cat + red):');
  for I := 0 to High(Res) do
    Writeln(Format('    [%d] %.4f — %s', [I+1, Res[I].Score, Candidatos[Res[I].Index]]));
end;

// =============================================================================
//  Section 4 — Analogy: king - man + woman approx queen (book sec. 21.6 op. 3)
// =============================================================================
procedure SeccionAnalogia(Conn: TAiEmbeddingConnection);
var
  VRey, VHombre, VMujer, VAnalogy: TAiEmbeddingData;
  Candidatos: TArray<String>;
  Vectores: TAiEmbeddingList;
  I: Integer;
begin
  Titulo('Sec. 21.6  Operation 3 — Analogy: king - man + woman approx queen');

  Writeln('  Formula:  VAnalogy = VectorAdd(VectorSubtract(rey, hombre), mujer)');
  Writeln('  Expected result: queen (or semantically equivalent terms)');
  Writeln;

  VRey    := E(Conn, 'rey');
  VHombre := E(Conn, 'hombre');
  VMujer  := E(Conn, 'mujer');

  // rey - hombre + mujer
  VAnalogy := TAiEmbeddingsCore.VectorAdd(
    TAiEmbeddingsCore.VectorSubtract(VRey, VHombre),
    VMujer
  );

  Candidatos := ['reina', 'princesa', 'principe', 'rey', 'senora', 'jefa', 'mujer', 'dama'];
  SetLength(Vectores, Length(Candidatos));
  for I := 0 to High(Candidatos) do
    Vectores[I] := E(Conn, Candidatos[I]);

  var Res := TAiEmbeddingsCore.FindTopK(VAnalogy, Vectores, 5);

  Writeln('  Top 5 candidates closest to the analogy vector:');
  for I := 0 to High(Res) do
    Writeln(Format('    [%d] %.4f — %s', [I+1, Res[I].Score, Candidatos[Res[I].Index]]));
  Writeln;
  Writeln('  Note: the result varies by model. Models with larger');
  Writeln('  semantic vocabulary place "reina" in the top 1 or 2.');
end;

// =============================================================================
//  Section 5 — Interpolation (book sec. 21.6 op. 4)
// =============================================================================
procedure SeccionInterpolacion(Conn: TAiEmbeddingConnection);
var
  VGato, VPerro, VMezcla: TAiEmbeddingData;
  I, J: Integer;
  Alpha, Beta: Double;
begin
  Titulo('Sec. 21.6  Operation 4 — Interpolation: transition from cat to dog');

  VGato  := E(Conn, 'gato');
  VPerro := E(Conn, 'perro');

  Writeln(Format('  %-6s  %-14s  %-14s', ['Alpha', 'Sim(gato)', 'Sim(perro)']));
  Writeln('  ' + StringOfChar('-', 38));

  for I := 0 to 5 do
  begin
    Alpha := I / 5.0;
    Beta  := 1.0 - Alpha;

    // alpha * gato + (1-alpha) * perro
    SetLength(VMezcla, Length(VGato));
    for J := 0 to High(VGato) do
      VMezcla[J] := Alpha * VGato[J] + Beta * VPerro[J];

    var SG := TAiEmbeddingsCore.CosineSimilarity(VMezcla, VGato);
    var SP := TAiEmbeddingsCore.CosineSimilarity(VMezcla, VPerro);
    Writeln(Format('  %-6.1f  %-14.4f  %-14.4f', [Alpha, SG, SP]));
  end;

  Writeln;
  Writeln('  alpha=0.0 -> 100% dog | alpha=1.0 -> 100% cat');
end;

// =============================================================================
//  Section 6 — Normalization (book sec. 21.6 op. 5)
// =============================================================================
procedure SeccionNormalizacion(Conn: TAiEmbeddingConnection);
var
  V: TAiEmbeddingData;
begin
  Titulo('Sec. 21.6  Operation 5 — Normalization');

  V := E(Conn, 'inteligencia artificial');
  Writeln(Format('  Magnitude before normalization : %.6f', [TAiEmbeddingsCore.Magnitude(V)]));

  TAiEmbeddingsCore.Normalize(V);
  Writeln(Format('  Magnitude after normalization : %.6f  (should be ~1.0)', [TAiEmbeddingsCore.Magnitude(V)]));
  Writeln;
  Writeln('  OpenAI returns already normalized vectors (magnitude ~1.0).');
  Writeln('  Ollama and others may have different magnitudes.');
end;

// =============================================================================
//  PROGRAMA PRINCIPAL
// =============================================================================
procedure RunDemo;
var
  Conn: TAiEmbeddingConnection;
begin
  Writeln('=== VectorOps — Algebraic operations with embeddings ===');
  Writeln('Driver: ', DRIVER, ' | Model: ', MODEL);

  Conn := TAiEmbeddingConnection.Create(nil);
  try
    Conn.DriverName := DRIVER;
    Conn.Model      := MODEL;
    Conn.Url        := URL;

    SeccionMetricas(Conn);
    SeccionPromediar(Conn);
    SeccionSuma(Conn);
    SeccionAnalogia(Conn);
    SeccionInterpolacion(Conn);
    SeccionNormalizacion(Conn);

    Writeln;
    Writeln('=== Demo completed ===');
  finally
    Conn.Free;
  end;
end;

begin
  try
    RunDemo;
  except
    on E: Exception do
      Writeln('ERROR: ', E.ClassName, ' — ', E.Message);
  end;
  Writeln;
  Writeln('Press Enter to exit...');
  Readln;
end.
