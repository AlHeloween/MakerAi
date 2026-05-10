User Manual: uMakerAi.ToolFunctions
Introduction
The uMakerAi.ToolFunctions unit provides a Delphi component designed to manage and expose functions (or "tools") that can be used by an Artificial Intelligence (AI) model. This component allows defining, configuring, and executing functions, enabling the AI model to interact with the outside world, access information, or perform specific tasks.
Main Components
The uMakerAi.ToolFunctions unit consists of the following main components:
TAiFunctions: This is the main component, which manages a collection of functions.
TFunctionActionItem: Represents an individual function that can be called by the AI model.
TFunctionParamsItem: Represents an individual parameter of a function.
TFunctionEvent: Defines the type of event that fires when a function is executed.
Data Types and Enumerations
TToolstype = (tt_function, ttNone);:
Defines the types of "tools" supported. Currently only tt_function is implemented.
TToolsParamType = (ptString, ptInteger, ptBoolean, ptFloat, ptDate, ptTime, ptDateTime, ptBase64);:
Defines the data types allowed for function parameters.
Using the TAiFunctions Component
Add the Component to the Form:
Drag and drop the TAiFunctions component from the component palette onto your Delphi form. This will create an instance of the component, for example, AiFunctions1.
Define Functions:
Double-click the AiFunctions1 component on the form. This will open the component's property editor.
Click the ellipsis (...) next to the Functions property. This will open the Delphi collection editor.
Click the Add button to create a new function (TFunctionActionItem).
Configure the function properties:
FunctionName: The function name (e.g., getCurrentWeather). This is the name the AI model will use to refer to the function.
Enabled: Indicates whether the function is enabled. If disabled, it will not be exposed to the AI model.
Description: A description of the function (e.g., "Gets the current weather for a given city").
Default: Indicates whether this function is the default function to be executed if the AI model does not specify a function name.
Parameters: Click the ellipsis (...) next to the Parameters property. This will open the collection editor for the function's parameters.
Click the Add button to create a new parameter (TFunctionParamsItem).
Configure the parameter properties:
Name: The parameter name (e.g., city).
ParamType: The data type of the parameter (e.g., ptString).
Required: Indicates whether the parameter is mandatory.
Description: A description of the parameter (e.g., "The city for which to get the weather").
Enum: A list of allowed values for the parameter (optional, comma-separated). Used to restrict the values the parameter can take. For example, if ParamType is String, you could restrict it to "London,New York,Paris".
OnAction: Select the OnAction event and click the ellipsis (...). This will open the code editor for the event. This is where you write the Delphi code that will execute when the function is called.
Code for the OnAction Event:
Inside the OnAction event, you must:
Get the parameter values from the ToolCall object (which is an instance of TAiToolsFunction).
Perform the function logic.
Set the Handled property to True if the function executed successfully, or False if an error occurred.
(Optional) Assign a result to the ToolCall.Result property to return it to the AI model.
Example:

procedure TForm1.GetCurrentWeatherAction(Sender: TObject; FunctionAction: TFunctionActionItem; FunctionName: String; ToolCall: TAiToolsFunction; var Handled: Boolean);
var
  City: string;
  WeatherInfo: string;
begin
  try
    City := ToolCall.Parameters.Values['city'];  // Get the "city" parameter value

    // Validate if value exists and is not empty
    If Trim(City) = '' then
    Begin
      ShowMessage('Error: The "city" parameter is required');
      Handled := False;
      Exit;
    End;

    // Code to get current weather for the city (e.g., calling an API)
    WeatherInfo := GetWeatherFromAPI(City);

    // Assign the result (if needed)
    ToolCall.Result := WeatherInfo;

    Handled := True;  // Indicate function executed successfully
  except
    on E: Exception do
    begin
      ShowMessage('Error in GetCurrentWeatherAction: ' + E.Message);
      Handled := False;
    end;
  end;
end;

Execute a Function:
When the AI model decides to use a function, it will send a request to your Delphi application, specifying the function name and parameter values. Your application creates a TAiToolsFunction object with this information and calls the DoCallFunction method of the TAiFunctions component so the application executes it and returns the requested value.

Main Methods of the TAiFunctions Component
Constructor Create(AOwner: TComponent):
Creates an instance of the TAiFunctions component.
Destructor Destroy:
Destroys the component instance.

Function SetFunctionEnable(FunctionName : String; Enabled : Boolean) : Boolean:
Enables or disables a function by name.
Parameters:
FunctionName: The name of the function to enable or disable.
Enabled: True to enable the function, False to disable it.
Return Value: True if the function was found and its state could be updated, False if the function was not found.