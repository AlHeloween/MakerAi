unit uMakerAi.Utils.Python;


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
// Name: Gustavo Enriquez
// Social Networks:
// - Email: gustavoeenriquez@gmail.com

// - Telegram: https://t.me/MakerAi_Suite_Delphi
// - Telegram: https://t.me/MakerAi_Delphi_Suite_English

// - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
// - Youtube: https://www.youtube.com/@cimamaker3945
// - GitHub: https://github.com/gustavoeenriquez/


{
  ===============================================================================
  uMakerAi.Utils.Python - Utility to execute Python scripts from Delphi
  ===============================================================================

  This library provides a simple and efficient interface to execute
  Python scripts from Delphi applications, allowing you to take advantage of the
  power of Python for complex calculations, data analysis, artificial
  intelligence and more.

  MAIN FEATURES:
  - Execution of Python scripts with and without parameters
  - Automatic conversion of Delphi types to Python
  - Safe memory and reference handling
  - Support for multiple data types (String, Integer, Float, Boolean, DateTime)
  - Reusable global Python engine for better performance

  REQUIREMENTS:
  - Python 3.10 or higher installed on the system
  - Python4Delphi (P4D) component
  - Accessible Python DLL (python310.dll by default)

  BASIC USAGE:

  1. Without parameters:
  Result := TUtilsPython.ExecuteScript('result = "Hello from Python!"');

  2. With parameters:
  Result := TUtilsPython.ExecuteScript('result = param1 + param2', [10, 20]);

  PRACTICAL EXAMPLE - Prime Number Calculation:

  var
  ScriptPrimos: String;
  Resultado: String;
  begin
  ScriptPrimos :=
  'def primos(n):' + sLineBreak +
  '    primos_list = []' + sLineBreak +
  '    num = 2' + sLineBreak +
  '    while len(primos_list) < n:' + sLineBreak +
  '        es_primo = True' + sLineBreak +
  '        for i in range(2, int(num ** 0.5) + 1):' + sLineBreak +
  '            if num % i == 0:' + sLineBreak +
  '                es_primo = False' + sLineBreak +
  '                break' + sLineBreak +
  '        if es_primo:' + sLineBreak +
  '            primos_list.append(num)' + sLineBreak +
  '        num += 1' + sLineBreak +
  '    return primos_list' + sLineBreak + sLineBreak +
  'result = primos(param1)';

  // Calculate the first 10 prime numbers
  Resultado := TUtilsPython.ExecuteScript(ScriptPrimos, [10]);
  ShowMessage(Resultado); // Result: [2, 3, 5, 7, 11, 13, 17, 19, 23, 29]
  end;

  OTHER EXAMPLES:

  - Mathematical operations:
  Result := TUtilsPython.ExecuteScript('result = param1 ** param2', [2, 8]); // 256

  - String manipulation:
  Result := TUtilsPython.ExecuteScript(
  'result = param1.upper() + " " + param2.lower()',
  ['Hello', 'WORLD']
  ); // "HELLO world"

  - Date handling:
  Result := TUtilsPython.ExecuteScript(
  'result = param1.strftime("%Y-%m-%d %H:%M:%S")',
  [Now]
  );


  IMPORTANT NOTES:
  - All scripts must assign their result to the variable 'result'
  - Parameters are passed as param1, param2, param3, etc.
  - The Python engine is initialized automatically
  - It is recommended to handle exceptions when executing complex scripts

  AUTHOR: Gustavo Enriquez
  VERSION: 1.1 - Support for dynamic parameters
  DATE: 2024

  ===============================================================================

  WARNING! Make sure the application is 64-bit if you have Python installed in 64-bit architecture.

}

interface

uses
  PythonEngine, System.SysUtils, System.Variants;

Type

  EPythonArchitectureError = class(Exception);

  TUtilsPython = Class
  Private
    class function VariantToPythonValue(const Value: Variant): String;
    class procedure CheckArchitecture;
    class function Is64BitApplication: Boolean;
    class function GetApplicationArchitecture: String;
  Protected
  Public
    class function ExecuteScript(Script: String): String; overload;
    class function ExecuteScript(Script: String; const Params: array of Variant): String; overload;
  End;

var
  GlPythonEngine: TPythonEngine;

procedure InitializePythonEngine;
Function GetPythonEngine(DllName: String = 'python310.dll'): TPythonEngine;

implementation

Function GetPythonEngine(DllName: String): TPythonEngine;
Begin
  if not Assigned(GlPythonEngine) then
  begin
    GlPythonEngine := TPythonEngine.Create(nil);
  end;

  // Check architecture before initializing
  TUtilsPython.CheckArchitecture;

  GlPythonEngine.DllName := DllName; // make sure to use the correct Python version

  If Not GlPythonEngine.Initialized then
    GlPythonEngine.LoadDll;

  Result := GlPythonEngine;
End;

procedure InitializePythonEngine;
begin
  if not Assigned(GlPythonEngine) then
  begin
    GlPythonEngine := TPythonEngine.Create(nil);
  end;
end;

{ TPythonUtils }

class function TUtilsPython.Is64BitApplication: Boolean;
begin
{$IFDEF WIN64}
  Result := True;
{$ELSE}
  Result := False;
{$ENDIF}
end;

class function TUtilsPython.GetApplicationArchitecture: String;
begin
  if Is64BitApplication then
    Result := '64 bits'
  else
    Result := '32 bits';
end;

class procedure TUtilsPython.CheckArchitecture;
begin
  if not Is64BitApplication then
  begin
    raise EPythonArchitectureError.CreateFmt('ARCHITECTURE ERROR: The application is compiled in %s but Python is generally installed in 64 bits.' + sLineBreak + 'SOLUTIONS:' + sLineBreak +
      '1. Recompile the application for 64 bits (Recommended)' + sLineBreak + '2. Install Python 32 bits from https://www.python.org/downloads/' + sLineBreak + '3. Use the Python 32-bit DLL (python310-32.dll)' + sLineBreak + sLineBreak +
      'To compile for 64 bits:' + sLineBreak + '- In Delphi: Project > Options > Building > Delphi Compiler > Target platforms > Win64' + sLineBreak + '- Select "Win64" as target platform', [GetApplicationArchitecture]);
  end;
end;

class function TUtilsPython.ExecuteScript(Script: String): String;
// In this function the script must return the result in a variable called result
var
  PyEngine: TPythonEngine;
  PyModule: TPythonModule;
  PyResult: PPyObject;
  FullScript: String;
  UTF8Script: UTF8String;
begin

// Check architecture before executing
  CheckArchitecture;

  PyEngine := GetPythonEngine; // Gets the global engine

  try
    // Create the Python module
    PyModule := TPythonModule.Create(nil);
    PyModule.Engine := PyEngine;
    PyModule.ModuleName := 'mymodule';

    FullScript := '# -*- coding: utf-8 -*-' + sLineBreak + Script;

    // Convert to UTF-8
    UTF8Script := UTF8Encode(FullScript);

    // Execute the full Python script
    PyEngine.ExecString(AnsiString(UTF8Script));

    // Get the result of the execution
    PyResult := PyEngine.EvalString('result');

    // Convert the result to a string
    Result := PyEngine.PyObjectAsString(PyResult);

    // Decrement the reference of the Python object
    PyEngine.Py_DecRef(PyResult);
  Except
    On E: Exception do
    Begin
      Result := E.Message + sLineBreak + 'Remember that all scripts must return a value in a variable called result';
      Raise;
    End;
  end;
end;

class function TUtilsPython.ExecuteScript(Script: String; const Params: array of Variant): String;
var
  PyEngine: TPythonEngine;
  PyModule: TPythonModule;
  PyResult: PPyObject;
  ParameterScript: String;
  i: Integer;
  FullScript: String;
  UTF8Script: UTF8String;
begin

// Check architecture before executing
  CheckArchitecture;

  PyEngine := GetPythonEngine;
  try
    // Create the Python module
    PyModule := TPythonModule.Create(nil);
    try
      PyModule.Engine := PyEngine;
      PyModule.ModuleName := 'mymodule';

      // Build the parameter script
      ParameterScript := '';
      for i := 0 to High(Params) do
      begin
        ParameterScript := ParameterScript + Format('param%d = %s', [i + 1, VariantToPythonValue(Params[i])]) + sLineBreak;
      end;

      // If there are date parameters, add datetime import
      for i := 0 to High(Params) do
      begin
        if VarType(Params[i]) = varDate then
        begin
          ParameterScript := 'import datetime' + sLineBreak + ParameterScript;
          Break;
        end;
      end;

      // Add UTF-8 encoding at the beginning of the script
      FullScript := '# -*- coding: utf-8 -*-' + sLineBreak + ParameterScript + sLineBreak + Script;

      // Convert to UTF-8
      UTF8Script := UTF8Encode(FullScript);

      // Execute the full Python script
      PyEngine.ExecString(AnsiString(UTF8Script));

      // Get the result of the execution
      PyResult := PyEngine.EvalString('result');
      try
        // Convert the result to a string
        Result := PyEngine.PyObjectAsString(PyResult);
      finally
        // Decrement the reference of the Python object
        PyEngine.Py_DecRef(PyResult);
      end;
    finally
      PyModule.Free;
    end;
  Except
    On E: Exception do
    Begin
      Result := E.Message + sLineBreak + 'Remember that all scripts must return a value in a variable called result';
      Raise;
    End;
  end;
end;

class function TUtilsPython.VariantToPythonValue(const Value: Variant): String;
begin
  case VarType(Value) of
    varEmpty, varNull:
      Result := 'None';
    varBoolean:
      if Value then
        Result := 'True'
      else
        Result := 'False';
    varByte, varSmallint, varInteger, varWord, varLongWord, varInt64, varUInt64:
      Result := VarToStr(Value);
    varSingle, varDouble, varCurrency:
      Result := StringReplace(VarToStr(Value), ',', '.', [rfReplaceAll]); // Decimal format for Python
    varDate:
      Result := Format('datetime.datetime(%s)', [FormatDateTime('yyyy,m,d,h,n,s', Value)]);
    varString, varUString, varOleStr:
      Result := QuotedStr(VarToStr(Value));
  else
    Result := QuotedStr(VarToStr(Value)); // By default as string
  end;
end;

initialization

InitializePythonEngine;

finalization

FreeAndNil(GlPythonEngine);

end.



 def primos(n):
     primos_list = []
     num = 2
     while len(primos_list) < n:
         es_primo = True
         for i in range(2, int(num ** 0.5) + 1):
             if num % i == 0:
                 es_primo = False
                 break
         if es_primo:
             primos_list.append(num)
         num += 1
     return primos_list
 result = primos(param1)
