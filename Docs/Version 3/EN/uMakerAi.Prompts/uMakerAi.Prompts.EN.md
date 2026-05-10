User Manual: uMakerAi.Prompts
Introduction
The uMakerAi.Prompts unit provides a Delphi component for managing and using prompt templates (instructions) to interact with Artificial Intelligence (AI) models. It facilitates the creation, storage, and customization of reusable prompts, simplifying the development of AI-powered applications.
Main Components
The uMakerAi.Prompts unit consists of two main classes:
TAiPromptItem: Represents an individual prompt.
TAiPrompts: Represents a collection of prompts.

Using the TAiPrompts Component
Add the Component to the Form:
Drag and drop the TAiPrompts component (from the component palette) onto your Delphi form. This will create an instance of the component, for example, AiPrompts1.
Manage Prompts at Design Time:
Double-click the AiPrompts1 component on the form. This will open the Delphi collection editor for the Items property.
Click the Add button to create a new prompt (TAiPromptItem).
Name: Set the Nombre property of the prompt. This name will be used to identify the prompt in your code.
Strings: Click the ellipsis (...) next to the Strings property. This will open the TStringList editor. Here you can type the prompt text, line by line. The TStringList editor allows editing prompts that span multiple lines.

Alternative: Create Prompts by Code:
You can also create and add prompts to the Items collection by code:
var
  PromptItem: TAiPromptItem;
begin
  PromptItem := AiPrompts1.AddString('Greeting', 'Hello!');
  PromptItem := AiPrompts1.AddString('PersonalizedGreeting', 'Hello <#Name>, welcome to <#City>!');
end;

Main Methods of the TAiPrompts Component
GetString(Name: String): String
Description: Retrieves the text of a prompt by name.
Parameters:
Name: The name of the prompt to retrieve.
Return Value: The prompt text (as a single string, combining the TStringList lines).
Example:

var
  Greeting: string;
begin
  Greeting := AiPrompts1.GetString('Greeting');
  ShowMessage(Greeting); // Shows "Hello!"
end;

GetTemplate(Name: String; Params: Array of String): String; Overload
Description: Retrieves the text of a prompt and replaces placeholders with values provided in a string array.
Parameters:
Name: The name of the prompt.
Params: A string array in the format 'Name=Value'.
Return Value: The prompt text with placeholders replaced.
Example:

var
  PersonalizedGreeting: string;
begin
  PersonalizedGreeting := AiPrompts1.GetTemplate('PersonalizedGreeting', ['Name=John', 'City=Buenos Aires']);
  ShowMessage(PersonalizedGreeting); // Shows "Hello John, welcome to Buenos Aires!"
end;

GetTemplate(Name: String; Params: TStringList): String; Overload
Description: Retrieves the text of a prompt and replaces placeholders with values provided in a TStringList.
Parameters:
Name: The name of the prompt.
Params: A TStringList where property names are placeholder names, and property values are replacement values.
Return Value: The prompt text with placeholders replaced.
Example:

var
  PersonalizedGreeting: string;
  Params: TStringList;
begin
  Params := TStringList.Create;
  try
    Params.Values['Name'] := 'John';
    Params.Values['City'] := 'Buenos Aires';
    PersonalizedGreeting := AiPrompts1.GetTemplate('PersonalizedGreeting', Params);
    ShowMessage(PersonalizedGreeting); // Shows "Hello John, welcome to Buenos Aires!"
  finally
    Params.Free;
  end;
end;



GetTemplate(Name: String; Params: TJSONObject): String; Overload
Description: Retrieves the text of a prompt and replaces placeholders with values provided in a TJSONObject.
Parameters:
Name: The name of the prompt.
Params: A TJSONObject where keys are placeholder names, and values are replacement values.
Return Value: The prompt text with placeholders replaced.
Example:
uses
  System.JSON;

var
  PersonalizedGreeting: string;
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  try
    Params.AddPair('Name', 'John');
    Params.AddPair('City', 'Buenos Aires');
    PersonalizedGreeting := AiPrompts1.GetTemplate('PersonalizedGreeting', Params);
    ShowMessage(PersonalizedGreeting); // Shows "Hello John, welcome to Buenos Aires!"
  finally
    Params.Free;
  end;
end;

AddString(Name, Data: String): TAiPromptItem
Description: Adds a new prompt to the collection.
Parameters:
Name: The name of the new prompt.
Data: The text of the new prompt.
Return Value: A reference to the created TAiPromptItem.
Example:
var
  NewPrompt: TAiPromptItem;
begin
  NewPrompt := AiPrompts1.AddString('Farewell', 'Goodbye!');
end;

Placeholder Syntax
Placeholders in prompts must follow the format <#Name>, where Name is the parameter name to be replaced.
Complete Example
unit Unit1;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, uMakerAi.Prompts, Vcl.StdCtrls;

type
  TForm1 = class(TForm)
    AiPrompts1: TAiPrompts;
    Button1: TButton;
    Memo1: TMemo;
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

procedure TForm1.Button1Click(Sender: TObject);
var
  Prompt: string;
  Params: TStringList;
begin
  // Get a prompt and replace parameters using TStringList
  Params := TStringList.Create;
  try
    Params.Values['Name'] := 'John';
    Params.Values['City'] := 'Buenos Aires';
    Prompt := AiPrompts1.GetTemplate('PersonalizedGreeting', Params);
    Memo1.Text := Prompt;
  finally
    Params.Free;
  end;
end;

end.

Form (Unit1.dfm):
Create a new Delphi form.
Drag and drop a TAiPrompts component from the component palette. Name it AiPrompts1.
Drag and drop a TButton and a TMemo component.
TAiPrompts Configuration (at design time):
Double-click AiPrompts1.
Add a new TAiPromptItem.
Name: PersonalizedGreeting
Strings:
Hello <#Name>, welcome to <#City>!


Examples:

Example 1: Video (Veo2)
Objective: Generate a prompt for Veo2 that describes a realistic scene in a coffee shop.
1.1. Create the Prompt at Design Time:
Double-click AiPrompts1.
Click "Add" to create a new TAiPromptItem.
Name: CoffeeShopVideo
Strings: (Click the ellipsis to open the TStringList editor)
Generate a realistic video of:

Subject: <#Subject>
Context: <#Context>
Action: <#Action>
Style: Realistic, with natural lighting and vibrant colors.

Camera movement: Medium shot, following the subject while performing the action. Slight camera movements to maintain visual interest.
Composition: Classic framing, with the subject in the center of the shot and the background slightly blurred.
Ambiance: Warm and cozy, with natural light coming through the windows and the ambient sound of the coffee shop.

1.2. Use the Prompt in Delphi (Using TStringList):
uses
  System.SysUtils, System.Classes;

procedure TForm1.ButtonVideoClick(Sender: TObject);
var
  PromptFinal: string;
  Params: TStringList;
begin
  Params := TStringList.Create;
  try
    Params.Values['Subject'] := 'A young woman about 25 years old, with brown hair and a floral summer dress.';
    Params.Values['Context'] := 'A busy coffee shop in the city center during lunch hour, on a sunny day.';
    Params.Values['Action'] := 'Working on her laptop and occasionally looking around.';

    PromptFinal := AiPrompts1.GetTemplate('CoffeeShopVideo', Params);

    // Now PromptFinal contains the complete prompt ready to send to Veo2.
    MemoResultado.Text := PromptFinal; // Show the prompt in a memo (optional)
    // (Here would be the code to send PromptFinal to the Veo2 API)

  finally
    Params.Free;
  end;
end;
1.3. Use the Prompt in Delphi (Using TJSONObject):
uses
  System.SysUtils, System.Classes, System.JSON;

procedure TForm1.ButtonVideoClick(Sender: TObject);
var
  PromptFinal: string;
  Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  try
    Params.AddPair('Subject', 'A young woman about 25 years old, with brown hair and a floral summer dress.');
    Params.AddPair('Context', 'A busy coffee shop in the city center during lunch hour, on a sunny day.');
    Params.AddPair('Action', 'Working on her laptop and occasionally looking around.');

    PromptFinal := AiPrompts1.GetTemplate('CoffeeShopVideo', Params);

    // Now PromptFinal contains the complete prompt ready to send to Veo2.
    MemoResultado.Text := PromptFinal; // Show the prompt in a memo (optional)
    // (Here would be the code to send PromptFinal to the Veo2 API)

  finally
    Params.Free;
  end;
end;

1.4. Create the Prompt by Code:
uses
  System.SysUtils, System.Classes;

procedure TForm1.FormCreate(Sender: TObject);
var
  PromptItem: TAiPromptItem;
begin
  PromptItem := AiPrompts1.AddString('CoffeeShopVideoCode',
  'Generate a realistic video of:#13' +
  '#13' +
  'Subject: <#Subject>#13' +
  'Context: <#Context>#13' +
  'Action: <#Action>#13' +
  'Style: Realistic, with natural lighting and vibrant colors.#13' +
  '#13' +
  'Camera movement: Medium shot, following the subject while performing the action. Slight camera movements to maintain visual interest.#13' +
  'Composition: Classic framing, with the subject in the center of the shot and the background slightly blurred.#13' +
  'Ambiance: Warm and cozy, with natural light coming through the windows and the ambient sound of the coffee shop.'
  );
end;

and you use the previous examples of 1.2. Use the Prompt in Delphi (Using TStringList): or 1.3. Use the Prompt in Delphi (Using TJSONObject): changing the name to CoffeeShopVideoCode.

Example 2: Image (Image Generation)
Objective: Generate a prompt for an image generation model (e.g., DALL-E, Midjourney, Stable Diffusion) that creates an image of a cat in a garden.
2.1. Create the Prompt at Design Time:
Double-click AiPrompts1.
Click "Add" to create a new TAiPromptItem.
Name: CatGardenImage
Strings:
A photograph of a <#Breed> cat sleeping in a garden full of <#Flowers>, with <#Light> light and an <#ArtisticStyle> style.

2.2. Use the Prompt in Delphi (Using Array of String):
procedure TForm1.ButtonImageClick(Sender: TObject);
var
  PromptFinal: string;
begin
  PromptFinal := AiPrompts1.GetTemplate('CatGardenImage',
    ['Breed=Persian', 'Flowers=Red roses', 'Light=Warm', 'ArtisticStyle=Impressionist']);

  // Now PromptFinal contains the complete prompt ready to send to the image generation API.
  MemoResultado.Text := PromptFinal; // Show the prompt in a memo (optional)
  // (Here would be the code to send PromptFinal to the image generation API)
end;

Example 3: Voice (Voice/Text-to-Speech Generation)
Objective: Generate a prompt for a voice generation or text-to-speech model that creates a welcome voice message.
3.1. Create the Prompt at Design Time:
Double-click AiPrompts1.
Click "Add" to create a new TAiPromptItem.
Name: WelcomeVoice
Strings:
Generate a welcome voice message for a new user on the <#PlatformName> platform, with a <#Tone> tone and an approximate duration of <#Duration> seconds.
3.2. Use the Prompt in Delphi (Using TStringList):
procedure TForm1.ButtonVoiceClick(Sender: TObject);
var
  PromptFinal: string;
  Params: TStringList;
begin
  Params := TStringList.Create;
  try
    Params.Values['PlatformName'] := 'MakerAI Suite';
    Params.Values['Tone'] := 'Friendly and enthusiastic';
    Params.Values['Duration'] := '15';

    PromptFinal := AiPrompts1.GetTemplate('WelcomeVoice', Params);

    // Now PromptFinal contains the complete prompt ready to send to the voice generation API.
    MemoResultado.Text := PromptFinal; // Show the prompt in a memo (optional)
    // (Here would be the code to send PromptFinal to the voice generation API)

  finally
    Params.Free;
  end;
end;
These examples show how you can use the TAiPrompts component to manage and customize prompts for different types of AI models (video, image, and voice). Remember these are just basic examples, and you can adapt and expand them to meet your specific needs.