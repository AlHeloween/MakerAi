

Chapter 1: Introduction to MakerAI Architecture

Welcome to the MakerAI framework for Delphi. If you are reading this, you probably want to integrate the incredible power of Generative Artificial Intelligence into your VCL and FMX applications. This manual will guide you through the TAiChatConnection component, the central piece designed to make that integration flexible, robust, and, above all, simple.
1.1 The Problem: Fragmentation of AI APIs

The AI ecosystem is in full swing. Every day, tech giants and the open source community offer us more powerful and specialized models.
OpenAI leads with its GPT models.
Google competes fiercely with its Gemini model family.
xAI enters the scene with Grok, seeking compatibility and performance.
Anthropic offers Claude, focused on security and more natural conversations.
The Open Source community, through platforms like Ollama, gives us access to hundreds of models we can run locally, guaranteeing privacy and reducing costs.
This diversity is fantastic, but for a developer, it presents an immediate challenge: fragmentation. Although many RESTful APIs share similarities, each has its own subtleties:
Different endpoints: api.openai.com vs. generativelanguage.googleapis.com.
Different parameter names: max_tokens in OpenAI vs. maxOutputTokens in Gemini.
Unique request structures: The way to send a system message or handle "function calling" can vary.
Variable capabilities: Some models are purely textual, others are multimodal (accept images, audio), and others are specialized in Text-to-Speech (TTS).
Writing code coupled directly to one of these APIs is a risky decision. If you want to change providers to leverage a faster or cheaper model, or simply offer options to your users, you would face a costly and error-prone rewrite.

1.2 The Solution: A Layer-Based Architecture

The MakerAI framework addresses this problem with a clean, decoupled architecture, inspired by proven software design principles. Instead of connecting your application directly to an external API, we introduce an abstraction layer.
Look at the following conceptual diagram:



As you can see, your application only needs to know one component: TAiChatConnection. Everything else happens "under the hood".
1.3 The Central Role of TAiChatConnection

TAiChatConnection is the heart of this architecture. It fulfills two fundamental roles based on classic software design patterns:
It is a Facade:
Concept: A facade is an object that provides a simplified and unified interface to a more complex subsystem. It is like your TV remote control: it gives you simple buttons (change channel, raise volume) without you needing to know anything about the internal circuitry.
In MakerAI: TAiChatConnection exposes simple methods like Run, AddMessageAndRun and events like OnError and OnReceiveDataEnd. When you call AiConn.Run(...), you do not need to know if a JSON is being built for OpenAI or for Grok. The component handles that complexity, presenting a friendly and consistent face.
It uses a Factory Pattern:
Concept: A factory is responsible for creating objects without exposing the creation logic to the client. You ask for a "car" and it gives you one, without you having to know how it is assembled.
In MakerAI: The DriverName property is the instruction you give to the internal factory (TAiChatFactory). When you set DriverName := 'Gemini', TAiChatConnection asks the factory: "Give me an object capable of talking to Gemini". The factory returns an instance of TAiGeminiChat. If you then change to 'Ollama', it will return an instance of TAiOllamaChat. This "engine" change is dynamic and occurs at runtime.
The Key Principle: Write your code once, run it with any AI.
The combination of these patterns results in the most important benefit of this framework: the ability to write your application code once and have it work transparently with multiple AI providers.
// This code works the same regardless of whether DriverName is 'OpenAI', 'Grok' or 'Ollama'.
procedure TMyForm.ButtonSendClick(Sender: TObject);
var
  Response: string;
begin
  Response := AiChatConnection1.AddMessageAndRun(MemoPrompt.Text, 'user', []);
  MemoResponse.Lines.Add('AI: ' + Response);
end;

This abstraction not only saves you countless hours of development and maintenance, but also prepares your applications for the future, allowing you to adopt new and better AI models as soon as they are available, with minimal effort.


Chapter 2: Getting Started with TAiChatConnection
In this chapter, we will leave theory behind and build our first AI application in Delphi. By the end, you will have a simple window where you can write a prompt, select an AI provider, and see the response in real time.
2.1 Component Installation and Configuration
Before starting, make sure MakerAI components are correctly installed in your Delphi IDE.
Open Delphi and create a new project, either VCL Application or Multi-Device Application (FMX). The MakerAI framework is compatible with both platforms.
Go to the Component Palette. Look for the "MakerAI" tab. If you do not find it, make sure you have installed the corresponding design packages (.dpk).
Drag and drop a TAiChatConnection component from the palette onto your form. You will see a new non-visual icon on your TForm. We will call it AiConn from now on.
Make sure to add the corresponding unit in the uses clause, if you want to use Ollama you must add uMakerAi.Chat.Ollama in the uses, for OpenAi you must add uMakerAi.Chat.OpenAi and the same for each driver you wish to use.
We also recommend adding uMakerAi.Chat and uMakerAi.Core which are the units where general definitions and some types and classes commonly used in programs are found.

That is all! You already have the AI engine ready to be configured.
2.2 Essential Properties: DriverName and Model
Select the AiConn component on your form and look at the Object Inspector. You will see a series of properties. For now, we will focus on the two most important ones:
DriverName: This is the "master switch". Click the dropdown arrow of this property. You will see a list of all AI providers ("Drivers") that the framework has registered, such as OpenAI, Gemini, Grok, Ollama, etc.
Action: Select the driver you want to use, for example, OpenAI.
Model: Once you have selected a DriverName, this property allows you to specify which model from that provider you want to use.
Action: Type the model name. For OpenAI, a good starting point is gpt-4o-mini.
Important Note about API Keys: Most drivers require an API Key to function. TAiChatConnection will automatically load the API Key from the parameters registered for the driver. The most common way to configure this is through the factory parameter system, which we will see in detail later. For now, make sure you have a valid API Key for the provider you have chosen. The ApiKey parameter will be configured automatically when you select the DriverName, you can also configure your ApiKey as an operating system environment variable in Windows and Linux and the configuration in the ApiKey parameter must begin with the @ symbol indicating to the system to look for it in the environment variable 
E.g. ApiKey = @OPENAI_APIKEY While defining that environment variable in the operating system environment




2.3 Your First Conversation: AddMessageAndRun
Now that we have the component configured, let us make it work.
Design the User Interface (UI):
Add two TMemo components to your form. Name the first MemoPrompt and the second MemoResponse.
Add a TButton and name its Text (or Caption in VCL) property as "Send".
Write the Code:
Double-click the TButton to create its OnClick event.
Inside the event, write the following code:
procedure TForm1.Button1Click(Sender: TObject);
var
  Response: string;
begin
  // We disable the button to prevent multiple sends
  Button1.Enabled := False;
  MemoResponse.Lines.Add('You: ' + MemoPrompt.Text);
  MemoResponse.Lines.Add('AI: ...writing...');
  try
    // This is the magic line. Sends the prompt and waits for the response.
    Response := AiConn.AddMessageAndRun(MemoPrompt.Text, 'user', []);

    // We update the response in the memo
    MemoResponse.Lines[MemoResponse.Lines.Count - 1] := 'AI: ' + Response;
  finally
    // We reactivate the button
    Button1.Enabled := True;
  end;
end;

Code Analysis:
AiConn.AddMessageAndRun(...): This is the "all-in-one" method.
The first parameter (MemoPrompt.Text) is the text you want to send.
The second ('user') is the message role. 'user' is for user questions.
The third ([]) is a multimedia file array, which for now we leave empty.
The method is synchronous: your code execution will stop until the API returns a complete response. (We will see asynchronous mode later).
Run the Application:
Press F9 to compile and run your project.
Type a question in MemoPrompt, such as "What is the capital of France?".
Click "Send".
Congratulations! After a few seconds, you should see the AI response appear in MemoResponse. You have built your first AI chat application in Delphi.
2.4 Error Handling: The OnError Event
What happens if your API Key is incorrect, you have no internet connection, or the provider's API is down? Your application will crash with an unhandled exception. This is not professional.
The OnError event of TAiChatConnection is your safety net.
Assign the Event:
Return to the form designer.
Select the AiConn component.
In the Object Inspector, go to the Events tab.
Double-click the OnError event. Delphi will create an empty procedure.
Implement Error Handling:
Write the following code in the event. It is crucial to use TThread.Synchronize or TThread.Queue because network errors occur in secondary threads.

procedure TForm1.AiConnError(Sender: TObject; const ErrorMsg: string;
  Exception: Exception; const AResponse: IHTTPResponse);
begin
  // We use Queue to safely send the UI update to the main thread.
  TThread.Queue(nil,
    procedure
    begin
      MemoResponse.Lines.Add('--- ERROR ---');
      MemoResponse.Lines.Add(ErrorMsg);
      MemoResponse.Lines.Add('---------------');
      ShowMessage('An error occurred: ' + ErrorMsg);

      // If the button got stuck disabled, we reactivate it.
      Button1.Enabled := True;
    end);
end;

Test the Error: To force an error, go to the Object Inspector and modify the ApiKey property in AiConn.Params by adding an "x" at the end to invalidate it. Run the application again and send a question. Now, instead of a crash, you will see the error message handled gracefully in your TMemo and in a ShowMessage.
Chapter 3: Advanced Conversation Management
In the previous chapter, we created a basic interaction. However, the true power of large language models (LLMs) lies in their ability to maintain contextual conversations. The AI must "remember" what was said before. This chapter focuses on how TAiChatConnection and its underlying architecture manage this history.
3.1 Chat History: The Messages Property
Every time you interact with TAiChatConnection, you are not sending just your last question. Internally, the component maintains a complete history of the conversation. This history is accessible through the Messages property.
TAiChatConnection.Messages: This property is of type TAiChatMessages, which is essentially a list (TList<TAiChatMessage>) of objects.
TAiChatMessage: Each object in the list represents a single turn in the conversation and contains vital information:
Role: Who said the message ('user', 'assistant'/'model', 'system', 'tool').
Prompt / Content: The content of the message.
MediaFiles: A list of multimedia files (images, etc.) attached to that message.
And other metadata such as usage tokens, tool call ID, etc.
You can use this property to inspect the conversation at any time.
Practical Example: Visualize History
Add a new TButton to your form and a TMemo called MemoHistory.
In the OnClick event of the button, add the following code:

procedure TForm1.ButtonShowHistoryClick(Sender: TObject);
var
  Msg: TAiChatMessage;
  i: Integer;
begin
  MemoHistory.Lines.Clear;
  MemoHistory.Lines.Add('--- START OF CHAT HISTORY ---');
  for i := 0 to AiConn.Messages.Count - 1 do
  begin
    Msg := AiConn.Messages[i];
    MemoHistory.Lines.Add(Format('[%d] ROLE: %s', [i, Msg.Role]));
    MemoHistory.Lines.Add(Msg.Prompt); 
    MemoHistory.Lines.Add('--------------------');
  end;
end;

or you can use the following instruction

procedure TForm1.ButtonShowHistoryClick(Sender: TObject);
begin
   MemoHistory.Lines.Text := AiConn.Messages.ToJSon.Format;
end;


When you run and click this button after a conversation, you will see how the history has been built turn by turn.
3.2 Detailed Conversation Flow
The framework offers several methods to precisely control how the conversation is built. Understanding the difference is key to creating advanced applications.
AddMessageAndRun(prompt, role, mediaFiles): The "all-in-one".
What it does: 1. Creates a TAiChatMessage. 2. Adds it to history (Messages). 3. Executes the API request with the entire history.
When to use it: For simple and direct interactions, like in our first example. It is the most common method.
NewMessage(prompt, role): The "builder".
What it does: 1. Creates a TAiChatMessage object and returns it to you. 2. Does NOT add it to history.
When to use it: When you need to prepare a message, perhaps add multimedia files or modify it, before deciding whether to send it or not.
Run(message): The "executor".
What it does: 1. If you pass a message (message), it first adds it to history. 2. Executes the API request with the current complete history.
When to use it: It is the perfect complement to NewMessage. It allows you to send a message you have prepared previously.
Combined Example:
procedure TForm1.ButtonComplexInteractionClick(Sender: TObject);
var
  Msg: TAiChatMessage;
  Response: string;
begin
  // 1. We create a new message but do not add it to history yet.
  Msg := AiConn.NewMessage('Describe this image and then tell me a joke about programmers.', 'user');

  // 2. We add an image file (assuming OpenDialog1 is configured).
  if OpenDialog1.Execute then
  begin
    Msg.LoadMediaFromFile(OpenDialog1.FileName);

    // 3. Now that the message is complete, we send it using Run.
    // Run will take care of adding it to history before executing.
    Response := AiConn.Run(Msg);
    MemoResponse.Lines.Add('AI: ' + Response);
  end
  else
  begin
    // If the user cancels, the message was never added to history.
    // We simply free it (since NewMessage does not transfer ownership).
    Msg.Free;
  end;
end;

3.3 Customizing Assistant Behavior
You can guide the behavior and knowledge of the AI using two key properties on TAiChatConnection.
InitialInstructions: TStrings
What it is: A set of instructions that are sent at the beginning of the conversation to establish the "system role". It defines the personality, tone, rules, and general context of the assistant.
How to use it: In the Object Inspector, click the ellipsis (...) of the InitialInstructions property and write your directives, one per line.
Example:
You are a Delphi expert assistant named "Maker".
Always respond in Spanish.
Your responses should be technical, precise, and with code examples when appropriate.
You must never refuse to answer a programming question.
When starting a new conversation, these instructions will be injected as the first message in history, guiding all subsequent AI responses.

Memory: TStrings
What it is: A list of Key=Value pairs that is added to the initial instructions. It serves to provide data or factual context that the AI must know.
How to use it: Similar to InitialInstructions, you can edit it in the Object Inspector or by code.
Example:
Generated code
UserName=Gustavo
UserLevel=Expert
Project=MakerAI Framework
CurrentDate=2024-10-27
Difference with InitialInstructions: While instructions define behavior, memory defines base knowledge. It is ideal for personalizing the user experience without saturating the main prompt.
3.4 Saving and Loading Conversations
An essential feature of any chat application is the ability to save a conversation and resume it later. The Messages object makes this trivial.
Add a TSaveDialog and a TOpenDialog to your form.
Implement saving:
Generated delphi
procedure TForm1.ButtonSaveChatClick(Sender: TObject);
begin
  if SaveDialog1.Execute then
  begin
    try
      AiConn.Messages.SaveToFile(SaveDialog1.FileName);
      ShowMessage('Conversation saved successfully.');
    except
      on E: Exception do
        ShowMessage('Error saving: ' + E.Message);
    end;
  end;
end;
Implement loading:
procedure TForm1.ButtonLoadChatClick(Sender: TObject);
begin
  if OpenDialog1.Execute then
  begin
    try
      // Before loading, it is a good idea to clear the current conversation.
      AiConn.NewChat; // NewChat clears history in the active driver.
      AiConn.Messages.LoadFromFile(OpenDialog1.FileName);
      ShowMessage('Conversation loaded. You can continue chatting.');
      // Optional: Show the loaded history again in the memo.
      ButtonShowHistoryClick(Sender);
    except
      on E: Exception do
        ShowMessage('Error loading: ' + E.Message);
    end;
  end;
end;


Chapter 4: Multimodal Capabilities (Images, Audio and Video)
Modern Artificial Intelligence is no longer limited to text. Current models can "see" images, "hear" audio, and "create" new multimedia content. The MakerAI framework is designed from its core to handle these complex interactions in a surprisingly simple way. In this chapter, you will learn to build applications that interact with the world through sight and hearing.
4.1 The TAiMediaFile Object: Your Swiss Army Knife for Media
The heart of all multimodal functionality is the TAiMediaFile class. Think of this object as a universal container for any type of file you want to send to or receive from the AI.
TAiMediaFile abstracts the complexity of handling different data sources. A single object can represent:
An image file on your hard drive.
A photo hosted on an internet URL.
An audio file you just recorded.
Video data in Base64 format.
Key Load Methods:
LoadFromFile(const aFileName: string): The most common. Loads a file directly from a disk path.
var MediaFile := TAiMediaFile.Create;
MediaFile.LoadFromFile('C:\Photos\my_dog.jpg');
LoadFromUrl(const aUrl: string): Downloads and loads the content of an online resource.
var MediaFile := TAiMediaFile.Create;
MediaFile.LoadFromUrl('https://.../cat_image.png');
LoadFromStream(const aFileName: string; Stream: TMemoryStream): Loads from an existing TMemoryStream. Useful for in-memory generated data.
LoadFromBase64(const aFileName, aBase64: string): Loads from a text string in Base64 format.
Once loaded, TAiMediaFile automatically exposes useful properties like MimeType, FileCategory, and Base64, which the framework uses to build the correct API request.
4.2 "Seeing" with AI: Sending Images to Vision Models
Let us give "eyes" to our application.
Select a Model with Vision Capability:
Make sure the DriverName and Model in your TAiChatConnection correspond to a multimodal model. Examples:
OpenAI: gpt-4o or gpt-4o-mini
Gemini: gemini-1.5-pro-latest
Ollama: llava:latest
Enable Image Processing:
The framework needs to know that the driver you have chosen can handle images natively. This is controlled with the ChatMediaSupports property of the driver (which is configured through the Params of TAiChatConnection). For the most powerful drivers, this comes preconfigured.
Build the Multimodal Message:
The AddMessageAndRun method is overloaded to accept an array of TAiMediaFile.
Practical Example: Describe an Image
Add a TOpenDialog to the form.

procedure TForm1.ButtonDescribeImageClick(Sender: TObject);
var
  MediaFile: TAiMediaFile;
  Response: string;
begin
  // Configure the dialog to only accept image files.
  OpenDialog1.Filter := 'Image Files|*.jpg;*.jpeg;*.png;*.bmp';
  if OpenDialog1.Execute then
  begin
    // 1. Create an instance of TAiMediaFile.
    MediaFile := TAiMediaFile.Create;
    try
      // 2. Load the image selected by the user.
      MediaFile.LoadFromFile(OpenDialog1.FileName);

      // 3. Send the text prompt TOGETHER with the image file.
      MemoPrompt.Text := 'Describe what you see in this image in detail.';
      Response := AiConn.AddMessageAndRun(MemoPrompt.Text, 'user', [MediaFile]);

      MemoResponse.Lines.Add('AI: ' + Response);
    finally
      // 4. Free the MediaFile object.
      MediaFile.Free;
    end;
  end;
end;

And that is all! TAiChatConnection and the Gemini/OpenAI driver will take care of converting the image to Base64, building the complex multimodal JSON, and sending it to the API. You will receive a textual description of the image as if it were a normal conversation.
4.3 "Speaking" with AI: Generating Audio (Text-to-Speech - TTS)
Now, let us make the AI talk to us.
Configure Audio Output:
Audio generation is activated by indicating to the framework that you expect an audio file as output. This is done through the NativeOutputFiles property.
// Before calling Run, configure the output.
AiConn.Params.Values['NativeOutputFiles'] := '[Tfc_Audio]';

Select a Voice with TAiSpeechConfig:
The TAiSpeechConfig object, accessible through AiConn.AiChat.SpeechConfig, allows you to control voices.

Single Voice:
AiConn.Params.Values['Voice'] := 'echo'; // OpenAI 'echo' voice
AiConn.Params.Values['Voice'] := 'Kore'; // Gemini 'Kore' voice
Multiple Voices (for dialogues):
AiConn.Params.Values['Voice'] := 'Narrator=onyx, Interviewee=nova';

Receive Audio in OnReceiveDataEnd:
When the AI response is a multimedia file, the text parameter (aText) of the OnReceiveDataEnd event will be empty. Instead, the TAiChatMessage object (aMsg) will contain a TAiMediaFile with the generated audio.
Practical Example: Read the Response
Add a TMediaPlayer to your form.

// Implement the OnReceiveDataEnd event of your AiConn.
procedure TForm1.AiConnReceiveDataEnd(const Sender: TObject; aMsg: TAiChatMessage,
  AResponse: TJSONObject; aRole, aText: string);
var
  AudioFile: TAiMediaFile;
  SavePath: string;
begin
  // We check if the response message contains files.
  if Assigned(aMsg) and (aMsg.MediaFiles.Count > 0) then
  begin
    // We keep the first file (assuming it is the audio).
    AudioFile := aMsg.MediaFiles[0];
    
    // We check if it is an audio file.
    if AudioFile.FileCategory = Tfc_Audio then
    begin
      TThread.Queue(nil, procedure
      begin
        SavePath := TPath.Combine(TPath.GetTempPath, 'response.wav');
        AudioFile.SaveToFile(SavePath);
        MediaPlayer1.FileName := SavePath;
        MediaPlayer1.Play;
        MemoResponse.Lines.Add('AI: [Audio generated, playing...]');
      end);
    end;
  end
  else if not aText.IsEmpty then
  begin
    // If there is no media, it is a normal text response.
    TThread.Queue(nil, procedure
    begin
      MemoResponse.Lines.Add('AI: ' + aText);
    end);
  end;
end;

Now, when executing a request with audio output configured, the response will play automatically.
4.4 Creating with AI: Generating Video
Video generation, supported by cutting-edge models like Google's Veo, follows a pattern similar to audio, but often involves long-duration operations that are handled asynchronously.
Configure Video Output:

AiConn.Params.Values['NativeOutputFiles'] := '[Tfc_Video]';
AiConn.Params.Values['ChatMediaSupports'] := '[]';


Asynchronous Handling:
Video generation can take several minutes. If Asynchronous handling is checked, the framework handles this in the background. The call to AddMessageAndRun will return immediately. The application will remain responsive, and when the video is ready, it will be notified through the OnReceiveDataEnd event, where you can process the video TAiMediaFile similarly to how you did with audio.


Chapter 5: Function Calling and Tools
So far, we have treated AI as a black box that receives information (text, images) and returns a response. But what if the AI needed real-world data that only your application knows? Or if it needed to perform an action within your system, such as saving a file to a database or turning on a device?

This is where Function Calling (or "Tool Use") comes in. It is one of the most transformative capabilities of modern LLMs.
5.1 What is Function Calling?
Function Calling is the mechanism that allows an AI model, in the middle of a conversation, to pause, ask your application to execute one of its own Delphi functions, and then use the result of that function to formulate its final response.
In essence, you give the AI a "tool catalog" (your Delphi functions) and the intelligence to know when and how to use them.

The Basic Flow:
User: "Hello, AI. What is the weather like in Madrid and what is the current price of Microsoft stock?"
AI (analyzing): "The user is asking me two things. I do not have access to the internet or real-time financial data. But wait! The developer gave me a tool called GetWeather and another called GetStockPrice."
AI -> Your App (Tool Request): "Please execute these two functions:
GetWeather with argument {'location': 'Madrid'}.
GetStockPrice with argument {'ticker': 'MSFT'}."
Your App (Execution): Your Delphi code receives this request. Calls a weather API to get the weather and a financial API for the stock price.
Your App -> AI (Tool Response): "Here are the results:
Result of GetWeather: {'temperature': '25C', 'condition': 'sunny'}.
Result of GetStockPrice: {'price': 350.75, 'currency': 'USD'}."
AI (Formulating final response): "OK, I have the data now."
AI -> User (Final response): "The weather in Madrid is sunny with 25C, and the price of Microsoft stock (MSFT) is 350.75 USD."
5.2 Defining Tools with TAiFunctions
For the AI to know what tools are available, you need to describe them. This is where the TAiFunctions component comes in.
Add the Component: Drag a TAiFunctions component from the "MakerAI" palette onto your form. We will call it AiFunctions1.
Define a Function:
Select AiFunctions1 and go to the Functions property in the Object Inspector. Click the ellipsis (...) to open the collection editor.
Click "Add new". A TFunctionActionItem will be created.
Configure its properties. The most important is FunctionBody, which is a JSON format description of the function.
Example: Defining a GetFechaActual tool
Select the new TFunctionActionItem and in the FunctionBody property, paste the following JSON:

{
  "type": "function",
  "function": {
    "name": "GetFechaActual",
    "description": "Gets the current date and time of the system where the application is running.",
    "parameters": {
      "type": "object",
      "properties": {},
      "required": []
    }
  }
}

JSON Analysis:
name: The function name the AI will use to call it.
description: Crucial! This is the natural language description the AI uses to understand what the tool is for. Be clear and descriptive.
parameters: Describes the arguments your function accepts. In this case, there are none ("properties": {}).
Link Tools to the Connection:
Select your AiConn component.
In the Object Inspector, look for the AiFunctions property.
In the dropdown, select AiFunctions1.
Now TAiChatConnection knows that when it talks to the AI, it must inform it that the GetFechaActual tool is available.
5.3 Execution Flow in Code
When the AI decides to use one of your tools, the framework manages it through events. You have two ways to implement the code that executes.
Method 1: Using the OnAction event of TFunctionActionItem (Recommended)
Return to the AiFunctions1 collection editor.
Select your TFunctionActionItem (GetFechaActual).
Go to the Events tab of the Object Inspector.
Double-click the OnAction event. Delphi will create the event handler.
Implement the tool code:

procedure TForm1.AiFunctions1Functions0GetFechaActualAction(Sender: TObject;
  FunctionAction: TFunctionActionItem; FunctionName: string;
  ToolCall: TAiToolsFunction; var Handled: Boolean);
begin
  // 1. Execute your Delphi logic.
  // In this case, we simply get the current date and time.

  // 2. Assign the result to the 'Response' property of the ToolCall object.
  // The result must be a string. If your function returns complex data,
  // serialize it to JSON.
  ToolCall.Response := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);

  // 3. Inform the framework that you have handled this call.
  Handled := True;
end;

Method 2: Using the OnCallToolFunction event of TAiChatConnection (General)
This event fires for any function call. It is useful if you prefer to have all logic in one place.

procedure TForm1.AiConnCallToolFunction(Sender: TObject;
  AiToolCall: TAiToolsFunction);
begin
  if AiToolCall.name = 'GetFechaActual' then
  begin
    AiToolCall.Response := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
  end
  else if AiToolCall.name = 'OtraFuncion' then
  begin
    // ...logic for another function...
  end;
end;

Note: If you implement both, the OnAction event of TFunctionActionItem has priority. If you set Handled := True there, the OnCallToolFunction event of TAiChatConnection will not fire for that call.
5.4 Putting it all together
Activate tools: Before sending your prompt, make sure the Tool_Active parameter is True.
AiConn.Params.Values['Tool_Active'] := 'True';
Send a prompt that encourages tool use:
// Send a prompt that references the tool.
Response := AiConn.AddMessageAndRun('Can you give me the exact date and time right now?', 'user', []);

// Show the final AI response.
MemoResponse.Lines.Add('AI: ' + Response);

When you run this code, TAiChatConnection will automatically perform the complete 2-step cycle described at the beginning. You do not need to do anything else. The history (Messages) will clearly show the AI's tool request and the response you provided, all managed transparently.


Chapter 6: Customization and Extension of the Framework
You have mastered the fundamentals, multimodal conversations, and tool use. Now it is time to take full control. This chapter will teach you to modify the framework's behavior, adjust low-level parameters, and, most excitingly, add support for new AI providers by creating your own drivers.
6.1 The Parameter System: The True Power of TAiChatConnection
We have mentioned parameters in passing, but now we will delve into them. The Params property of TAiChatConnection is much more than a simple configuration list; it is a real-time window into the state of the active AI "driver".
What is the Params property?
It is a TStrings that contains all configurable parameters for the currently selected driver (DriverName) and model (Model). When you change drivers, this list automatically updates with the corresponding parameters.
Reading and Modifying at Runtime:
You can read and write to this property to alter the behavior of the next API request. This is incredibly useful for giving control to the end user.
Practical Example: A TTrackBar to control "Temperature"
Add a TTrackBar to your form. Configure its Min to 0 and Max to 20.
Add a TLabel to display the current value.
In the OnChange event of the TTrackBar, write the following code:

procedure TForm1.TrackBarTempChange(Sender: TObject);
var
  TempValue: Double;
begin
  // We convert the TrackBar value (0-20) to a temperature range (0.0 - 2.0)
  TempValue := TrackBarTemp.Value / 10.0;
  LabelTemp.Text := Format('Temperature: %.1f', [TempValue]);

  // Here is the key! We modify the parameter in AiConn.
  // We use FormatFloat to ensure the correct decimal point format.
  AiConn.Params.Values['Temperature'] := FormatFloat('0.0', TempValue);
end;

Now, when the user moves the TTrackBar, the Temperature property of the active driver will update instantly, affecting the "creativity" of the next AI response. You can apply this same principle to Max_Tokens, Tool_Active, Asynchronous, etc.
Registering Custom Parameters with TAiChatFactory:
The framework comes with default values for each driver, but you can override them or add new profiles. This is done (usually in the initialization section of a unit) using TAiChatFactory.Instance.RegisterUserParam.

initialization
  // Sets a default value for ANY model of the 'Ollama' driver
  TAiChatFactory.Instance.RegisterUserParam('Ollama', 'Url', 'http://localhost:11434/v1/');

  // Creates a specific profile for the 'llava' model within the 'Ollama' driver
  TAiChatFactory.Instance.RegisterUserParam('Ollama', 'llava', 'InitialInstructions', 'You are an expert in describing images.');
  TAiChatFactory.Instance.RegisterUserParam('Ollama', 'llava', 'Temperature', '0.2');
end.

When the user selects the Ollama driver and the llava model, TAiChatConnection will automatically load these custom configurations into its Params property.
6.2 Creating Your Own Driver (E.g., for Anthropic Claude)
This is the ultimate expression of framework extensibility. Suppose Anthropic releases a new version of its API for the Claude model and you want to integrate it.
Step-by-Step Guide:
Create the New Unit and Class:
Create a new unit, for example, uMakerAi.Chat.Claude.pas. Inside, define a new class that inherits from TAiChat.

unit uMakerAi.Chat.Claude;

interface
uses
  ..., uMakerAi.Chat, uMakerAi.Core; // And other dependencies

type
  TAiClaudeChat = class(TAiChat)
  protected
    // Methods we are going to override
    function InitChatCompletions: String; override;
    class function GetDriverName: string; override;
    class procedure RegisterDefaultParams(Params: TStrings); override;
    class function CreateInstance(Sender: TComponent): TAiChat; override;
  public
    // Specific methods or properties of Claude, if any
  end;

procedure Register;

implementation

procedure Register;
begin
  // This procedure may not be necessary if we use initialization
end;

Implement the "Factory" Methods:
These four methods are the contract your class must fulfill for TAiChatFactory to recognize it.

class function TAiClaudeChat.GetDriverName: string;
begin
  Result := 'Claude'; // The name that will appear in the ComboBox
end;

class function TAiClaudeChat.CreateInstance(Sender: TComponent): TAiChat;
begin
  Result := TAiClaudeChat.Create(Sender); // Creates an instance of itself
end;

class procedure TAiClaudeChat.RegisterDefaultParams(Params: TStrings);
begin
  Params.Clear;
  Params.Add('ApiKey=@CLAUDE_API_KEY');
  Params.Add('Model=claude-3-opus-20240229');
  Params.Add('MaxTokens=4096');
  Params.Add('BaseURL=https://api.anthropic.com/v1/');
end;

Override the Main Logic (InitChatCompletions):
This is the most important step. Here you will adapt the JSON request construction to Claude API specifications. For example, Claude might use max_tokens_to_sample instead of max_tokens, or have a different message structure.

function TAiClaudeChat.InitChatCompletions: String;
var
  LRequest: TJSonObject;
begin
  // Here you would build the JSON request body specific to the Claude API.
  // For example:
  LRequest := TJSonObject.Create;
  try
    LRequest.AddPair('model', Self.Model);
    LRequest.AddPair('messages', Self.GetMessages); // You might need to override GetMessages too
    LRequest.AddPair('max_tokens_to_sample', Self.Max_tokens); // Claude-specific parameter!
    Result := LRequest.ToJSON;
  finally
    LRequest.Free;
  end;
end;

Register the Driver:
Finally, in the initialization section of your new unit, you tell the factory that a new driver is available.
initialization
  TAiChatFactory.Instance.RegisterDriver(TAiClaudeChat);
end.

And that is it! When you compile your project, the "Claude" driver will appear as an option in TAiChatConnection, and all the configuration and execution machinery will work for it.
6.3 Hooks and Advanced Events
For finer customization cases, TAiChatConnection offers "hooks" in the form of events that allow you to intercept the data flow.
OnBeforeSendMessage(Sender: TObject; var aMsg: TAiChatMessage):
Fires just before the message history is converted to JSON and sent. The aMsg parameter is var, meaning you can modify the last user message on the fly.
Use case: Automatically add contextual information to the user prompt, such as current date and time, or sign all requests with an identifier.
OnProcessResponse(Sender: TObject; LastMsg, ResMsg: TAiChatMessage; var Response: string):
Fires after the AI has returned a text response, but before it is assigned to the final ResMsg and notified through OnReceiveDataEnd. It allows you to modify the raw AI response.
Use case: Censor words, translate the response to another language, or format the response by adding line breaks or Markdown before displaying it in a TMemo.
OnChatModelChange(Sender: TObject; const OldChat, NewChat: TAiChat):
Fires exactly when the user changes the DriverName. It gives you access to the old driver instance (about to be destroyed) and the new one.
Use case: Implement "history translation". You could take the history from OldChat, use an AI to summarize it, and then inject that summary as the first message in NewChat, providing a smoother context transition between different providers.

Appendices:
Appendix A: Driver Reference Guide
This section provides a quick reference of supported drivers and their most notable parameters and capabilities. Use this table to decide which driver is most suitable for your task.

Appendix B: Troubleshooting Common Problems (FAQ)
Q: I receive a 401 Unauthorized error or similar.
A: This is almost always an API Key problem.
Verify that you have assigned the correct ApiKey in the driver parameters. You can do this through TAiChatFactory.Instance.RegisterUserParam('DriverName', 'ApiKey', 'YOUR_KEY_HERE').
Make sure the key has not expired or been revoked in the provider's control panel.
Confirm that your account has credit or an active payment plan.
Q: My application freezes when sending a prompt.
A: You are making a synchronous call, which blocks the main thread.
Quick Solution: Launch the request in a separate thread using TTask.Run.
Recommended Solution: Activate asynchronous mode. Set the Asynchronous parameter to True (AiConn.Params.Values['Asynchronous'] := 'True'). You will need to handle the response in the OnReceiveData (for text streaming) and OnReceiveDataEnd (for final response) events.
Q: I send an image but the AI responds "I do not see any image".
A: The driver or model is not configured correctly for vision.
Verify the Model: Make sure the selected Model is multimodal (e.g., gpt-4o, gemini-1.5-pro, llava).
Verify Driver Supports: The driver's ChatMediaSupports parameter must include Tcm_Image. This is usually preconfigured, but if you use a custom driver, it is a point to check.
Check the Message Object: Make sure the TAiMediaFile is being added correctly to the TAiChatMessage before calling Run.
Q: Audio or video generation does not work.
A: Similar to the vision problem, it is a configuration issue.
Activate the Correct Output: Before the call, you must set AiConn.Params.Values['NativeOutputFiles'] := '[Tfc_Audio]' (or [Tfc_Video]).
Check the Model: Not all models support these outputs. For Gemini TTS, you need a -tts model. For video, you need a specific model like veo-2.0.
Check the OnReceiveDataEnd Code: The response will not come as text. You must inspect aMsg.MediaFiles to find the generated file and process it.
Q: The AI does not use my tools (Function Calling).
A: Several points to verify in order:
Is it Active?: The Tool_Active parameter must be True.
Are they Linked?: The AiFunctions property of your TAiChatConnection must be linked to your TAiFunctions component.
Clear Description?: The description property in your tool's JSON is the most important part. The AI decides whether to use the tool based on that description. It must be clear, detailed, and in natural language. If the description is "Gets data", it is too vague. If it is "Gets the current temperature and weather conditions for a specific city", it is much better.
Adequate Prompt?: Your question to the AI must naturally encourage tool use.

Appendix C: Code Recipes (Code Snippets)
Recipe 1: Chatbot that Summarizes Conversation When Changing Driver
Use the OnChatModelChange event to maintain context when the user changes from, for example, OpenAI to a local Ollama model.

procedure TForm1.AiConnChatModelChange(Sender: TObject; const OldChat,
  NewChat: TAiChat);
var
  SummaryTask: ITask;
  Summary: string;
begin
  // Only if there is previous history and we are changing to a new valid driver.
  if not Assigned(OldChat) or not Assigned(NewChat) or (OldChat.Messages.Count < 3) then
    Exit;

  MemoResponse.Lines.Add('Changing driver... Summarizing history...');

  // We use a TTask to not block the UI while summarizing.
  SummaryTask := TTask.Run(
    function: string
    var
      Summarizer: TAiChat;
      History: string;
    begin
      // We use a temporary instance of a fast model to summarize.
      Summarizer := AiConn.CreateChatForDriver('OpenAI', 'gpt-4o-mini');
      try
        History := OldChat.Messages.ExportChatHistory.Format;
        Result := Summarizer.AddMessageAndRun('Summarize the following chat history in 3 key phrases: ' + History, 'user', []);
      finally
        Summarizer.Free;
      end;
    end);

  // When the summary task finishes, we inject the summary into the new chat.
  TTask.ContinueWith(SummaryTask,
    procedure(const Task: ITask)
    begin
      TThread.Queue(nil,
        procedure
        begin
          Summary := (Task as ITask<string>).Result;
          NewChat.AddMessage('This is a summary of our conversation so far: ' + Summary, 'system');
          MemoResponse.Lines.Add('Ready! You can continue the conversation with the new model.');
        end);
    end);
end;

Recipe 2: Use AI to Analyze Text Sentiment
A powerful application of "Function Calling" where the tool does not access external data, but performs a structured action.
Define the Tool in TAiFunctions:
{
  "type": "function",
  "function": {
    "name": "AnalyzeSentiment",
    "description": "Analyzes the sentiment of a text and classifies it as 'positive', 'negative' or 'neutral'.",
    "parameters": {
      "type": "object",
      "properties": {
        "sentiment": {
          "type": "string",
          "description": "The sentiment classification.",
          "enum": ["positive", "negative", "neutral"]
        }
      },
      "required": ["sentiment"]
    }
  }
}

Implement the OnAction:

procedure TForm1.AiFunctions1Functions0AnalyzeSentimentAction(Sender: TObject;
  ...; ToolCall: TAiToolsFunction; var Handled: Boolean);
var
  Sentiment: string;
begin
  // The AI already did the work. We just capture the result.
  Sentiment := ToolCall.Params.Values['sentiment'];
  ShowMessage('The sentiment detected by the AI is: ' + Sentiment);

  // We tell the AI that the action is completed.
  ToolCall.Response := '{"status": "ok", "sentiment_logged": "' + Sentiment + '"}';
  Handled := True;
end;

Execute the Prompt:

AiConn.Params.Values['Tool_Active'] := 'True';
// We force the AI to use the tool with 'tool_choice'
AiConn.Params.Values['Tool_choice'] := '{"type": "function", "function": {"name": "AnalyzeSentiment"}}';

AiConn.AddMessageAndRun('Today is a fantastic day! I love programming in Delphi.', 'user', []);

In this case, the AI does not respond with text, but directly calls your function with the result of its analysis, allowing you to act on that structured data in your Delphi code.
Appendix D: Driver parameter guide
In this section the most common parameters that can be handled within the Params property of TAIChatConnection are presented.


Feature | OpenAI | Gemini | Grok | Ollama
DriverName | OpenAI | Gemini | Grok | Ollama
Popular Models | gpt-4o, gpt-4o-mini, gpt-3.5-turbo | gemini-1.5-pro, gemini-1.5-flash | grok-2, grok-2-vision | llama3.2, llava, phi3
Vision Support | ✅ (Native) | ✅ (Native) | ✅ (Native) | ✅ (Depends on model, e.g., llava)
TTS Support | ✅ (Dedicated endpoint) | ✅ (Native in -tts models) | ❌ (Not available) | ❌ (Not available)
Video Support | ❌ (Sora not available on API) | ✅ (Veo, with predictLongRunning) | ❌ (Not available) | ❌ (Not available)
Function Calling | ✅ (Excellent support) | ✅ (Excellent support) | ✅ (Compatible support) | ✅ (Depends on model, e.g., llama3.2)
ApiKey Parameter | ✅ Required | ✅ Required | ✅ Required | ❌ Not required
BaseURL Parameter | https://api.openai.com/v1/ | https://generativelanguage.googleapis.com/v1beta/ | https://api.x.ai/v1/ | http://localhost:11434/v1/ (configurable)
Model Parameter | ✅ | ✅ | ✅ | ✅
Temperature Parameter | ✅ (0.0 - 2.0) | ✅ (0.0 - 1.0) | ✅ (0.0 - 2.0) | ✅ (Numeric)
Max_Tokens Parameter | ✅ | ✅ (maxOutputTokens) | ✅ | ✅ (num_predict)
Top_p Parameter | ✅ | ✅ | ✅ | ✅
Asynchronous Parameter | ✅ (Streaming) | ✅ (Streaming) | ✅ (Streaming) | ✅ (Streaming)
Specific Parameters | Logit_bias, Seed, Response_format | TopK, SpeechConfig, VideoParams | Reasoning_content (in response) | num_ctx (context size)
Ideal For... | General use, powerful tools, latest technology. | Advanced multimodality (long context, video), Google ecosystem. | Speed and direct responses, OpenAI API compatibility. | Total privacy, zero cost, customization, offline operation.

Property | Type | Description | Common Use/Values
ApiKey | String | API key for authentication with the AI service. If it starts with @, it is interpreted as the name of an environment variable. | Necessary to use the API. Example: "sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxx" or "@OPENAI_API_KEY"
Model | String | Identifier of the AI model to use (e.g., "gpt-4o", "gpt-3.5-turbo"). | Specifies the language model. List of available models is obtained with TAiChat.GetModels.
Frequency_penalty | Double | Frequency penalty. Values between -2.0 and 2.0. Reduces the probability of the model repeating tokens it has already used. | Controls repetition in responses. Positive values encourage more diverse responses.
Logit_bias | String | Modifies the probability of certain tokens appearing. Must be an empty string or a value between -100 and 100. | Allows influencing the vocabulary used. Useful for directing responses toward specific topics or words. Requires advanced knowledge of tokens.
Logprobs | Boolean | Whether to include the logarithmic probability of tokens in the response. | Useful for advanced analysis of the model response.
Top_logprobs | String | Number of top log probabilities to return. Must be an empty string or a value between 0 and 5. | Returns the most probable tokens and their logarithmic probabilities in the response.
Max_tokens | Integer | Maximum number of tokens to be generated in the response. If 0, the maximum allowed by the model is used. | Limits response length. Helps control costs and response times.
N | Integer | Number of chat completion choices to generate for each input message. You will be charged based on the number of tokens generated in all choices. Keep n as 1 to minimize costs. The default value is 1. | Generates multiple responses for the same question.

