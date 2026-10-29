// MIT License
//
// Copyright (c) 2024 Gustavo Enríquez - CimaMaker
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
// Nombre: Gustavo Enríquez
// - Email: gustavoeenriquez@gmail.com
// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - GitHub: https://github.com/gustavoeenriquez/

unit uMakerAi.Memory.Decay;

// Exponential decay engine for TAiMemory.
//
// Model inspired by Ebbinghaus forgetting curve:
//   decay = exp(-base_rate * importance_factor * access_factor * hours_elapsed)
//
// Factors:
//   importance_factor  = 1.0 / importance      -> importance 10 = slow decay, 1 = fast
//   access_factor      = 1.0 / log1p(accesses) -> more accesses = slower decay
//   hours_elapsed      = hours since last access
//
// Result: Double in [0.0, 1.0] where 1.0 = fresh, 0.0 = completely decayed

interface

uses
  System.SysUtils, System.Math, System.DateUtils;

type
  TAiMemoryDecay = class
  private
    const BASE_RATE = 0.005; // base rate - 0.005 ≈ half-life ~200h for imp=5
  public
    // Calculates the decay score based on importance, accesses and time
    class function Compute(
      AImportance:  Integer;
      AAccessCount: Integer;
      ALastAccess:  TDateTime
    ): Double;

    // Returns True if the entry should be considered "active" (decay > threshold)
    class function IsAlive(
      AImportance:  Integer;
      AAccessCount: Integer;
      ALastAccess:  TDateTime;
      AThreshold:   Double = 0.1
    ): Boolean;
  end;

implementation

class function TAiMemoryDecay.Compute(
  AImportance:  Integer;
  AAccessCount: Integer;
  ALastAccess:  TDateTime
): Double;
var
  HoursElapsed:     Double;
  ImportanceFactor: Double;
  AccessFactor:     Double;
  EffectiveRate:    Double;
begin
  // Importance guaranteed in range 1-10
  AImportance  := Max(1, Min(10, AImportance));
  AAccessCount := Max(0, AAccessCount);

  HoursElapsed := Max(0.0, HourSpan(Now, ALastAccess));

  // importance 10 -> factor 0.1 (very slow decay)
  // importance  1 -> factor 1.0 (maximum decay)
  ImportanceFactor := 1.0 / AImportance;

  // More accesses -> larger denominator -> slower decay (log1p = Ln(1+x) in Delphi)
  AccessFactor := 1.0 / (1.0 + Ln(1.0 + AAccessCount));

  EffectiveRate := BASE_RATE * ImportanceFactor * AccessFactor;

  Result := Exp(-EffectiveRate * HoursElapsed);
  Result := Max(0.0, Min(1.0, Result));
end;

class function TAiMemoryDecay.IsAlive(
  AImportance:  Integer;
  AAccessCount: Integer;
  ALastAccess:  TDateTime;
  AThreshold:   Double
): Boolean;
begin
  Result := Compute(AImportance, AAccessCount, ALastAccess) >= AThreshold;
end;

end.
