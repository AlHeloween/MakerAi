14-Dec-2024
Implementation of TAiChat component in Delphi

Change History
14-Dec-2024
Grok Chat support added with TAIGrokChat component.
Grok Embeddings support added with TAiGrokEmbeddings component.
NativeInputFiles property added to filter files that pass directly to the model
NativeOutputFiles property added to tell the model in what format we want the response
Introduction
In the current digital era, artificial intelligence (AI) has become an essential tool for developing advanced applications. The ability to understand and process natural language has opened new frontiers in human-machine interaction. With this in mind, developing a framework that simplifies connectivity with different AI models is crucial. TAiChat and its associated components aim to provide developers with a simple but powerful way to integrate this functionality into their Delphi applications.
A well-designed framework lowers entry barriers, allowing developers to focus on implementing innovative solutions without worrying about the underlying complexities of each AI model's proprietary API. By offering compatibility with multiple industry-leading models, such as OpenAI, Anthropic, Gemini, among others, the flexibility needed to adapt to the changing needs of software development is guaranteed.
Possible Uses of AI Models in Delphi
With AI models available in a programming environment like Delphi, developers can create smarter and more responsive applications in a variety of sectors. Some examples of applications that can be developed include:
1. Virtual Assistants: Implementation of assistants that can manage complex queries, answer frequently asked questions, and provide personalized recommendations, thereby improving the user experience.
2. Sentiment Analysis: Integration of modules that analyze and understand the sentiment behind text, useful for monitoring social media, opinion surveys, and customer satisfaction.
3. Content Generation: Automation of content creation through text, such as summaries, reports, and articles, optimizing time and human resources.
4. Automatic Translation: Development of applications that offer real-time text translation, facilitating multilingual communication.
5. Intelligent Chatbots: Design of chatbots that can learn and adapt their responses with each interaction, providing continuous and more contextual support to users.
6. Speech-to-Text Recognition: Implementation of functionalities that convert voice to text, allowing more natural and fluid data entry.
7. Creative Motivation: Assist in generating ideas for creative writing, game design, among others, allowing area professionals to explore new possibilities.
What is TAiChat?
General Purpose
The TAiChat Delphi component aims to simplify access and interaction with artificial intelligence language models (LLM) through different APIs, providing a unified interface for Delphi developers. This allows programmers to focus on integrating AI capabilities into their applications efficiently, without having to handle the specific complexities of each API.
Interaction with AI Models
TAiChat acts as a base component, encapsulating the complexity of interacting with LLM APIs. This component is the foundation for other inherited components like TAiOllamaChat, TAiGeminiChat, TAiClaudeChat, TAiMistralChat, and TAiOpenChat. All these components encapsulate and adapt the particularities of each API, facilitating integration with current and future AI models.
Main Functions
- Communication with LLMs: Sends text messages to models to get responses.
- Tools Functions: Facilitates callback execution and handling of functions defined by AI.
- Memory Management: Allows the model to remember both current conversation data and data stored in memory.
- Parameter Configuration: Customization of features like temperature, max_tokens, and other execution parameters.
- Attachment Handling: Processes multimedia files (images, voice, PDFs) to perform preprocessing such as converting or interpreting files before reaching the LLM.
Configuration and Customization
TAiChat allows configuration of all parameters necessary for optimal AI model operation. Properties like temperature, max_tokens, and other features can be adjusted according to specific application needs, and are applied according to the particularities of each model's API.
Error and Exception Handling
TAiChat includes mechanisms to handle connection and processing errors, ensuring robust interaction with APIs. Errors are managed in each procedure, and in asynchronous modes, they are properly captured to allow handling from the Delphi environment.
Examples and Demonstrations

1. Basic Example:
   var
     Chat: TAiChat;
   begin
     Chat := TAiChat.Create(nil);
     try
       Chat.ApiKey := 'your-api-key';
       Chat.Model := 'gpt-4';
       Chat.AddMessage('What is the capital of France?', 'user');
       ShowMessage(Chat.Run);
     finally
       Chat.Free;
     end;
   end;
2. Example with Process and MediaFiles (images):
   var
     Res: String;
     MediaFile: TAiMediaFile;
   begin
     MediaFile := TAiMediaFile.Create;
     MediaFile.LoadFromFile('path/to/file.jpg');
     Res := Chat.AddMessageAndRun('Describe this image', 'user', [MediaFile]);
     ShowMessage(Res);
     MediaFile.Free;
   end;
3. Example with Process and MediaFiles (Voice) with direct call: (only for OpenAi)
Var
  Res: String;
  MediaFile: TAiMediaFile;
  Msg: TAiChatMessage;
  FileName: String;
begin

  MediaFile := TAiMediaFile.Create;
  MediaFile.LoadFromFile('c:\temp\prompt.wav');

  Try
    Msg := AiOpenChat1.AddMessageAndRunMsg(MemoPrompt.Lines.Text, 'user', [MediaFile]);
  Finally
    FreeAndNil(MediaFile);
  End;

  MemoResponse.Lines.Text := Msg.Content;

  If (Msg.MediaFiles.Count > 0) and (Assigned(Msg.MediaFiles[0].Content)) then
  Begin
    FileName := 'c:\temp\response3' + Cons.ToString + '.wav';
    Msg.MediaFiles[0].Content.Position := 0;
    Msg.MediaFiles[0].Content.SaveToFile(FileName);

    Try
      MediaPlayer1.FileName := FileName;
      MediaPlayer1.Play;
    Finally
    End;
  End;

4. Example with Process and MediaFiles (Voice) with response in event: (only for OpenAi)
Var
  Res: String;
  MediaFile: TAiMediaFile;
begin
  MediaFile := TAiMediaFile.Create;
  MediaFile.LoadFromFile('c:\temp\prompt.wav');

  Try
    Res := AiOpenChat1.AddMessageAndRun(MemoPrompt.Lines.Text, 'user', [MediaFile]);
    MemoResponse.Lines.Text := Res;
  Finally
    FreeAndNil(MediaFile);
  End;
End;
In the OnReceiveDataEnd event, receive the parameter aMsg: TAiChatMessage from which we would obtain the result.
procedure TForm75.AiOpenChat1ReceiveDataEnd(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
Var
  FileName: String;
begin

  If (aMsg.MediaFiles.Count > 0) and (Assigned(aMsg.MediaFiles[0].Content)) then
  Begin
    Inc(Cons);
    FileName := 'c:\temp\response' + Cons.ToString + '.wav';
    aMsg.MediaFiles[0].Content.Position := 0;
    aMsg.MediaFiles[0].Content.SaveToFile(FileName);
    Try
      MediaPlayer1.FileName := FileName;
      MediaPlayer1.Play;
    Finally
    End;
  End;
end;
Public Properties:
Messages: TAiChatMessages
Collection of messages managed by the component.
LastError: String
Stores the last error that occurred during component execution.
Published Properties:
ApiKey: String
Key for the AI model API.
Model: String
Specifies the model that will be used for chat interactions (e.g., GPT-3.5, GPT-4, etc.).
Frequency_penalty: Double
Penalty for frequent words in the generated response (-2 to 2).
Logit_bias: String
Optional parameter to adjust logit biases of certain words. May be an empty string or contain values between -100 and 100.
Logprobs: Boolean
Enables or disables capture of logarithmic probabilities.
Top_logprobs: String
Specifies how many top logarithmic probabilities will be returned (values between 0 and 5).
Max_tokens: integer
Limit of tokens allowed in a response. If 0, the maximum value allowed by the model is taken.
N: integer
Number of responses generated per input message (default 1).
Presence_penalty: Double
Penalty to avoid repeating similar concepts in responses (-2.0 to 2.0).
Response_format: TAiOpenChatResponseFormat
Format of the response generated by the model, compatible with certain models like GPT-4.
Seed: integer
Seed used to generate variations in responses. If 0, it is not used.
Stop: string
Keywords to stop response generation. Several words can be defined separated by commas.
Asynchronous: Boolean
Determines whether responses are processed asynchronously.
Temperature: Double
Controls the randomness level in response generation (values between 0 and 2).
Top_p: Double
Adjusts cumulative probability for response generation (values between 0 and 1).
Tools: TStrings
List of available tools the model can use to process interactions.
Tool_choice: string
Name of the selected tool for chat processing.
Tool_Active: Boolean
Indicates whether the selected tool is active.
User: String
User associated with chat interactions.
InitialInstructions: TStrings
Initial instructions that will be sent to the model when starting the conversation.
Prompt_tokens: integer
Number of tokens used in the conversation "prompt".
Completion_tokens: integer
Number of tokens generated in the response.
Total_tokens: integer
Sum of tokens used in the "prompt" and in the response.
LastContent: String
Last content sent in the conversation.
LastPrompt: String
Last "prompt" sent to the model.
Busy: Boolean
Indicates whether the component is busy processing a request.
OnReceiveData: TAiOpenChatDataEvent
Event that fires when receiving data from the model.
OnReceiveDataEnd: TAiOpenChatDataEvent
Event that fires when data reception has finished.
OnAddMessage: TAiOpenChatDataEvent
Event that fires when a message is added to the conversation.
OnCallToolFunction: TOnCallToolFunction
Event that fires when a tool function is invoked.
OnBeforeSendMessage: TAiOpenChatBeforeSendEvent
Event that allows intercepting and modifying a message before sending it.
OnInitChat: TAiOpenChatInitChat
Event that fires when starting a new conversation.
Url: String
URL of the AI model service.
AIChatConfig: TAiChatConfig
Configuration used for interactions with the model.
ResponseTimeOut: integer
Maximum wait time to receive a response from the model.
Memory: TStrings
Persistent memory used to store data relevant to the conversation.
Functions: TFunctionActionItems
List of functions that can be executed within the conversation flow.
AiFunctions: TAiFunctions
Collection of specific AI functions to execute tasks.
OnProcessMediaFile: TAiOpenChatOnMediaFile
Event that fires when a media file is processed.
JsonSchema: TStrings
JSON schema used to validate or structure model responses.
NativeInputFiles: TAiFileCategories
Allows filtering attached files that will pass directly to the model, currently depending on the model may include Audio or Images, in addition to text that goes by default.
NativeOutputFiles: TAiFileCategories
Allows telling the model in what format the response is desired, currently only OpenAI has response formats in Text and Audio and they are only available with audio models in particular, will mark error in other models.

TAiChat Component Events
TAiOpenChatDataEvent: This event fires when any data is received during interaction with the AI model. It is useful for processing each fragment of information coming from the model, particularly in asynchronous operations.
TAiOpenChatDataEvent = procedure(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSonObject; aRole, aText: String) of object;
Common Use:
- Capture partial responses while they are being processed in asynchronous mode.
- Update user interfaces while receiving data.

TAiOpenChatBeforeSendEvent: Fires just before sending a message to the AI model. Allows the developer to modify or validate the message before it is sent.
TAiOpenChatBeforeSendEvent = procedure(const Sender: TObject; var aMsg: TAiChatMessage) of object;
- Validate and finally adjust the message before sending it to the model.
- Modify message content based on custom logic.

TAiOpenChatInitChat: This event is called when starting a new chat. Allows configuring and modifying initial instructions or adjusting chat memory.
TAiOpenChatInitChat = procedure(const Sender: TObject; aRole: String; Var aText: String; Var aMemory: TJSonObject) of object;
- Establish the initial context of a conversation.
- Customize chat memory with specific data for the session that is starting.

TAiOpenChatOnMediaFile: Manages media file processing before they reach the LLM model. It can be used to manipulate or convert files to other formats.
TAiOpenChatOnMediaFile = procedure(const Sender: TObject; Prompt: String; MediaFile: TAiMediaFile; Var Respuesta: String; Var aProcesado: Boolean) of object;
- Convert images to text using OCR before sending them to the model.
- Perform preliminary analysis of audio files.

TAiOpenChatDataEnd: This event activates when reception of data from the AI model is complete, useful for finalizing operations based on complete reception.
TAiOpenChatDataEnd = procedure(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSonObject; aRole, aText: String) of object;
- Execute final actions once the entire model response has been received.
- Status updates or cleanup after interaction.

OnCallToolFunction: Called when a specific tool function defined by the AI model needs to be executed. This allows implementing callbacks that are invoked by the model.
TOnCallToolFunction = procedure(Sender: TObject; AiToolCall: TAiToolsFunction) of object;
- Execute specific functions that have been requested by the model.
- Integrate business logic or process specific commands.
How to start?
We will start with the most basic, which is creating a request and getting the response, however, the components have different ways to achieve the same objective, let us see:
Example 1: AddMessage and Run Functions
In this first example, a message of type "user" is added to the chat and then executed obtaining a response, we use the AddMessage(aPrompt, aRole : String) : TAiChatMesage method, which only adds a message to the chat memory, to then be executed with the Run function, thus obtaining the model response.
   var
     Chat: TAiChat;
   begin
     Chat := TAiChat.Create(nil);
     try
       Chat.ApiKey := 'your-api-key';
       Chat.Model := 'gpt-4o';
       Chat.AddMessage('What is the capital of France?', 'user');
       ShowMessage(Chat.Run);
     finally
       Chat.Free;
     end;
   end;


Example 2: NewMessage and Run Functions
In this example, a message of type "user" is created, it is not added to the chat but executed directly, we use the NewMessage(aPrompt, aRole : String) : TAiChatMesage method, which is passed to the Run function, thus obtaining the model response, when using the "Run" function the system adds the message to the chat before executing it.
var
  Chat: TAiChat;
  Msg : TAiChatMessage;
begin
  Chat := TAiOpenChat.Create(nil);
  try
    Chat.ApiKey := 'api key';
    Chat.Model := 'gpt-4o';
    Msg := Chat.NewMessage('What is the capital of France?', 'user');

    //...here you can handle the msg before sending it to the model...
    Msg.LoadMediaFromFile('path/to/file1.jpg');
    Msg.LoadMediaFromFile('path/to/file2.jpg');

    ShowMessage(Chat.Run(Msg));
  finally
    Chat.Free;
  end;

Example 3: AddMessageAndRun Function
In this example, the message is created and executed in a single step, directly returning the result, the message is added to the chat automatically.
var
  Chat: TAiChat;
  Res : String;
begin
  Chat := TAiOpenChat.Create(nil);
  try
    Chat.ApiKey := 'api key';
    Chat.Model := 'gpt-4o';

    Res := Chat.AddMessageAndRun('what is the capital of France?','user',[]);
    ShowMessage(Res);

  finally
    Chat.Free;
  end;

Example 4: Directing the chat conversation
The chat can take different directions since its response has a certain freedom conditioned by statistical and random themes, for this, for example, the Seed property and the Temperature property are handled.
However, it is possible to direct chat responses by simulating a previous conversation, that is, "making it believe" that the chat has already responded to some questions just as we expect it to have done.
var
  Chat: TAiChat;
  Prompt, Res : String;
begin
  Chat := TAiOpenChat.Create(nil);
  try
    Chat.ApiKey := 'api key';
    Chat.Model := 'gpt-4o';

    Prompt := 'Let us assume we live in another universe where mathematics '+
        'have mutated, all constants have one more point, for example Square '+
        'root of 2 is not 1.4242... but 2.4141..., human temperature '+
        'is no longer 37 degrees but 38 degrees, and so on with all data.   '+
        'also mathematical operations have one more point, for example 2+2 =5. '+
        'Please do not give explanations about this new universe, simply '+
        'answer what you are asked, nor make reference to this new universe.';

    Chat.AddMessage(Prompt, 'user');

    //here we manually add the model response we want,
Chat.AddMessage('I understand, now we will be in this new universe and will not make reference to this', 'assistant');

    Res := Chat.AddMessageAndRun('what is the value of PI?','user',[]);
    ShowMessage(Res);

  finally
    Chat.Free;
  end;

This option will return as a result: The value of pi is 4.1416..;
Asynchronous Mode
So far the call mode has been synchronous, which means we call the LLM and wait until the model responds completely, which in some cases is not convenient given that it can take several seconds to perform the task.
We have two ways to face the problem, the first is to make the call inside a thread and wait to receive the complete response, the advantage of this method is that the application does not block waiting for the response and the interface can remain active, the second option consists of the model instead of waiting to have the complete response sending portions of the response as it generates them, so the user experience will be more satisfactory even though the final response time will be approximately equal.
Thread Calls
If you wish to make a call within the first model (By Threads) the recommendation is to use one of the thread mechanisms, in our case we will work with the TTask class.
  TTask.Run(
    Procedure
    Begin
      // code to execute inside the thread goes here

      TThread.Synchronize(nil,
        procedure
        begin
           // Code to execute with graphical interface goes here
        end);

      // code to execute inside the thread after the graphical interface goes here

    End);

An implementation of this first model would be something like the following code, however it is not what we are looking for, since what we do is not what asynchronous chat mode really refers to, which we will explain later.
  TTask.Run(
    Procedure
    var
      Chat: TAiChat;
      Prompt, Res: String;
      Msg: TAiChatMessage;
    Begin
      Chat := TAiOpenChat.Create(nil);
      try
        Chat.ApiKey := 'My api key';
        Chat.Model := 'gpt-4o';
        Chat.InitialInstructions.Text := 'You are an expert in the latest version of Delphi language';
        Chat.AddToMemory('UserName', 'Gustavo');
        Chat.AddToMemory('Virtual Assistant name', 'SofIA');
        Chat.AddToMemory('Hobbies', 'Programming, watching TV');

        Prompt := 'Hello, what is your name and what is my name?';

        Res := Chat.AddMessageAndRun(Prompt, 'user', []);

      TThread.Synchronize(nil,
        procedure
        begin
           MemoResponse.Lines.Text := Res;
        end);

      finally
        Chat.Free;
      end;
    End);

Asynchronous Chat Mode
The asynchronous chat mode consists of the LLM sending tokens as it generates them, so the user has feedback of what is happening in real time. This mode in many LLMs is not compatible with the execution of model functions (Tools), therefore, it is important to take into account the documentation of each model when executing asynchronous mode.
In this model we must mark the property Chat.Asynchronous := True; and from there the result will be sent to the OnReceiveData and OnReceiveDataEnd events.
The OnReceiveData event executes for each token received and it is the client application's responsibility to build the complete message, while the OnReceiveDataEnd event executes once the entire process is finished and at this point it already receives the complete message. Let us detail the process a bit more.

Var
  Prompt, Res: String;
  Msg: TAiChatMessage;
Begin

  If Not Assigned(Chat) then
    Chat := TAiOpenChat.Create(nil);

  try
    Chat.ApiKey := 'My api key;
    Chat.Model := 'gpt-4o';
    Chat.InitialInstructions.Text := 'You are an expert in the latest version of Delphi language';
    Chat.Asynchronous := True;
    Chat.OnReceiveData := AiConnReceiveData;

    Prompt := 'Tell me why I should use Delphi and in what cases is it better than other languages?';

    MemoResponse.Lines.Add('user: ' + Prompt);
    MemoResponse.Lines.Add('');
    MemoResponse.Lines.Add('assistant: ');

    If Chat.Asynchronous = False then
    Begin
      Res := Chat.AddMessageAndRun(Prompt, 'user', []);
      MemoResponse.Lines.Text := MemoResponse.Lines.Text + Res;
    End
    Else
    Begin
      Chat.AddMessageAndRun(Prompt, 'user', []);
    End;

  finally
    // Chat.Free;
  end;

In the event we add the text of each token to a memo
procedure TForm75.AiConnReceiveData(const Sender: TObject; aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
begin
  TThread.Synchronize(nil,
    procedure
    begin
      MemoResponse.BeginUpdate;
      Try
        MemoResponse.Lines.Text := MemoResponse.Lines.Text + aText;
        MemoResponse.SelStart := Length(MemoResponse.Text);
      Finally
        MemoResponse.EndUpdate;
      End;
    end);
end;

If you do not want to add each token, it is possible to use the OnReceiveDataEnd event, which executes only once at the end of the query and returns the complete text. It is also possible to use these events to modify the graphical interface by enabling or disabling objects like buttons, memos, etc. The component has the Chat.Busy property, which will always be true while executing and false when available.
. . .  
    Chat.Model := 'gpt-4o';
    Chat.InitialInstructions.Text := 'You are an expert in the latest version of Delphi language';
    Chat.Asynchronous := True;
    //Chat.OnReceiveData := AiConnReceiveData;
    Chat.OnReceiveDataEnd := AiOpenChat1ReceiveDataEnd;
. . . 

procedure TForm75.AiOpenChat1ReceiveDataEnd(const Sender: TObject;
  aMsg: TAiChatMessage; aResponse: TJSONObject; aRole, aText: string);
begin
  TThread.Synchronize(nil,
    procedure
    begin
      MemoResponse.BeginUpdate;
      Try
        MemoResponse.Lines.Text := MemoResponse.Lines.Text + aText;
        MemoResponse.SelStart := Length(MemoResponse.Text);
      Finally
        MemoResponse.EndUpdate;
      End;
    end);
end;

Memory Handling
Components handle 3 types of memory that affect response behavior according to the context created with this data. The first of all is the initial message which defines its initial behavior, the second corresponds to information stored in a property called Memory in which Key=Value data pairs are stored and finally the message list which corresponds to the conversation directly.
Initial Message
In most LLMs there is a first message that tells the model how to behave, by default a similar message is assumed to "you are a helpful and servile assistant", however, in many cases it is necessary to direct it better like "You are an expert in Delphi application development latest version", etc.
Property InitialInstructions: TStrings read FInitialInstructions write SetInitialInstructions;

var
  Chat: TAiChat;
  Prompt, Res : String;
begin
  Chat := TAiOpenChat.Create(nil);
  try
    Chat.ApiKey := 'Api Key';
    Chat.Model := 'gpt-4o';
    Chat.InitialInstructions.Text := 'You are an expert in the latest Delphi';

    Prompt := 'make a function that calculates the fibonacci series';

    Res := Chat.AddMessageAndRun(Prompt,'user',[]);
    ShowMessage(Res);

  finally
    Chat.Free;
  end;

Memory Property
The Memory property allows storing key information that can affect LLM behavior, this memory is permanent between different chat sessions, that is, it remains despite starting a new chat, which does not happen with messages.
var
  Chat: TAiChat;
  Prompt, Res : String;
begin
  Chat := TAiOpenChat.Create(nil);
  try
    Chat.ApiKey := 'Api Key';
    Chat.Model := 'gpt-4o';
    Chat.InitialInstructions.Text := 'You are an expert in the latest version of Delphi language';
    Chat.AddToMemory('UserName','Gustavo');
    Chat.AddToMemory('Virtual Assistant name','SofIA');
    Chat.AddToMemory('Hobbies','Programming, watching TV');

    Prompt := 'Hello, what is your name and what is my name?';

    Res := Chat.AddMessageAndRun(Prompt,'user',[]);
    ShowMessage(Res);

  finally
    Chat.Free;
  end;

To remove an entry from memory it is possible to execute the Procedure RemoveFromMemory(Key: String) and to remove all memory entries you can use: Chat.Memory.Clear;

Chat Messages
The third memory handled are the conversation messages, each message both from the user and the assistant is added to a list and for each request the total messages must be sent, including the initial message, memory messages, and chat messages.
To add a message to the message list there are several ways, in this section we will see how this list can be administered.
Adding a message without executing it: Chat.AddMessage(Prompt, Role);
This option allows adding messages both as "user" or as "Assistant", it must be remembered that so far a chat is performed by interleaving messages between these two roles.

Another option consists of creating the message and then adding it to the list, it is possible to create and add as many messages as necessary, always simulating the conversation between "user" and "assistant" and at the end it is possible to execute the Chat1.Run function; 

The TAiChat.Run(Msg : TAiChatMessage = Nil); function has an optional parameter, so if the parameter is Nil or no parameter is passed it executes with the messages already in the list, otherwise it adds the passed message as parameter and then executes the command.

Var Msg : TAiChatMessage;
  Msg := Chat.NewMessage('What is the capital of France?', 'user');
  Msg.LoadMediaFromFile('path/to/file1.jpg');
  Chat1.Run(Msg)

As a third option is the "AddMessageAndRun" function which performs the two steps in a single function, creates the message, adds it to the list and then executes the "Run" function
var
  Chat: TAiChat;
  Res : String;
begin
  Chat := TAiOpenChat.Create(nil);
  try
    Chat.ApiKey := 'api key';
    Chat.Model := 'gpt-4o';

    Res := Chat.AddMessageAndRun('what is the capital of France?','user',[]);
    ShowMessage(Res);

  finally
    Chat.Free;
  end;

Operations with Messages
NewChat: Delete all messages: To delete all messages and start a new chat just execute the Chat1.NewChat; function with this option all messages are deleted, but does not delete the initial message or the content of the "Memory" property. 

GetLastMessage: This function returns an object of type TAiChatMessage that is at the end of the message list, This message can be deleted using either the object itself or the message Id.

    Msg := Chat.GetLastMessage;
    Chat.RemoveMesage(Msg);
    Or this way
    Chat.RemoveMesage(Msg.Id);


Memory Optimization Techniques
Now knowing how memory works we can see that each message increases the message list and soon it can exceed the model's context window, plus each call increases the number of tokens consumed, so it can be a good technique to summarize messages.
The message list sent to the model would have a form similar to this Json.
[
    {
        "role": "system",
        "content": "You are an expert in the latest version of Delphi language\r\n\r\n\r\nTo Remember= {\r\n    \"UserName\": \"Gustavo\",\r\n    \"Virtual Assistant name\": \"SofIA\",\r\n    \"Hobbies\": \"Programming, watching TV\"\r\n}"
    },
    {
        "role": "user",
        "content": "Hello, what is your name and what is my name?"
    },
    {
        "role": "assistant",
        "content": "Hello! I am SofIA and your name is Gustavo. How can I help you today?"
    }
]

There are several techniques to summarize message content, the one we will work here consists of summarizing the most relevant ideas and eliminating what does not add value to the conversation.
To implement this solution a second component is used that will take care of performing the text conversion.
Var
  Messages, Res: String;
begin
  Messages := Chat1.Messages.ToJson.Format;
  Chat2.Messages.Clear;

  Res := Chat2.AddMessageAndRun('Summarize the following json, eliminate what is not relevant and what is repeated. Message: ' + Messages, 'user', []);

  Chat1.Messages.Clear;

  Chat1.AddMessage('keep this information in mind: ' + Res, 'user');
  Chat1.AddMessage('Understood, I will keep it in mind for future queries', 'assistant');

Multimedia File Handling
There are many LLM models, some specialized in code, others in text exclusively and even multimodal, but in some cases it is required to mix these models obtaining the best of each one. Although it is increasingly common to find multimodal models, the synchronized use of different models is still necessary.
Multimedia - Images
If the model is multimodal it is not necessary to do anything different from what we have seen so far. Keep in mind that some models like Llama 3.2 only accept one message in the chat and with only one image.
In Dec-2024 the filter was added that allows selecting the types of files that pass directly to the model with the NativeInputFiles property, If you want to pass image files directly to the model you would mark tfc_image and the system adds the image in base64 to the request, but if it is not marked, the system makes a call to preprocess images to the OnProcessMediaFile method, which allows the programmer to process that file and return to the request the equivalent of that file, E.g. If it is audio it can be converted to text and pass the text to the model.

               

Similarly some models already allow returning different file formats, the particular case of OpenAI allows returning both Text and Audio, so if you want to use this feature it would be necessary to mark in the NativeOutputFiles property the Audio and Text section. It should be clarified that this filter currently only works with OpenAI's audio model. For other models it still has no effect.



var
  Chat: TAiChat;
  Msg : TAiChatMessage;
begin
  Chat := TAiOpenChat.Create(nil);
  try
    Chat.ApiKey := 'api key';
    Chat.Model := 'gpt-4o';
    Msg := Chat.NewMessage('What can you see in this image?', 'user');

    //...here you can handle the msg before sending it to the model...
    Msg.LoadMediaFromFile('path/to/file1.jpg');
    Msg.LoadMediaFromFile('path/to/file2.jpg');

    ShowMessage(Chat.Run(Msg));
  finally
    Chat.Free;
  end;

When the main model is not multimodal, a second model can be used that is multimodal to complement the main model and for this the OnProcessMediaFile event is used, in which the binary file content can be obtained to preprocess it and pass to the request the equivalent text.
procedure TForm75.AiOpenChat1ProcessMediaFile(const Sender: TObject; Prompt: string; MediaFile: TAiMediaFile;
    var Respuesta: string; var aProcesado: Boolean);
var
  Chat: TAiChat;
  Res : String;
begin
  Chat := TAiOpenChat.Create(nil);
  try
    Chat.ApiKey := 'api key';
    Chat.Model := 'gpt-4o';
    Res := Chat.AddMessageAndRun('What can you see in this image?', 'user', [MediaFile]);

    Respuesta := Res; //Returns the image description
    aProcesado := True; //Tells the model that it has been processed

  finally
    Chat.Free;
  end;
end;




Multimedia - Audios
We can also preprocess audios, for this we will use the TAiAudio component that uses the Whisper model also from OpenAi, but that is free on other platforms and can even be downloaded locally since it is Open Source.
First, the audio file is attached the same way as if it were an image, Remember that there are several ways to attach files, see the corresponding section.
var
  Chat: TAiChat;
  Msg : TAiChatMessage;
begin
  Chat := TAiOpenChat.Create(nil);
  try
    Chat.ApiKey := 'api key';
    Chat.Model := 'gpt-4o';
    Msg := Chat.NewMessage('Can you summarize this audio?', 'user');

    Msg.LoadMediaFromFile('path/to/myaudio.wav');

    ShowMessage(Chat.Run(Msg));
  finally
    Chat.Free;
  end;

Using the OnProcessMediaFile event, we will convert the Audio to Text as follows
var
  Res: String;
begin

  Case MediaFile.FileCategory of

    TAiFileCategory.Tfc_Image:
      Begin
        Var
          Chat: TAiChat;
        Chat := TAiOpenChat.Create(nil);
        try
          Chat.ApiKey := 'api key';
          Chat.Model := 'gpt-4o';
          Res := Chat.AddMessageAndRun('What can you see in this image?', 'user', [MediaFile]);
          Respuesta := Res;
          aProcesado := True;
        finally
          Chat.Free;
        end;
      End;

    TAiFileCategory.Tfc_Audio:
      Begin
        var
          Audio: TAiAudio;
        Audio := TAiAudio.Create(nil);
        try
          Audio.ApiKey := 'your-api-key';
          Audio.Model := 'whisper-1';
          Res := Audio.Transcription(MediaFile.Content, MediaFile.FileName, 'Transcribe the audio');
          Respuesta := Res;
          aProcesado := True;

        finally
          Audio.Free;
        end;
      End;
  End;

In the same way Videos, PDFs, etc. can be processed. As long as you have a tool that allows converting from the file type to Text. It is worth noting that this process does not implement a RAG model and for that we invite you to see the corresponding RAG manual for which there are also components for implementation.

Function Execution (Tools)
One of the most valuable functionalities that LLMs have developed is function execution, it is the way we can connect AI to the real world, with this tool it is possible to interact with applications, interact with IoT (The Internet of Things) and in general give arms to the artificial brain.
It should be clarified that not all models are enabled for this work, so we invite you to read the documentation of each platform to find the appropriate model.
In the case of OpenAI, this type of functionality is available through what they call API Tools. With the integration of external functions, an LLM can do things like:
Search for information in real time: The model can make queries to external sources, such as databases or search engines.
Manipulate data: For example, process images, files, or perform complex mathematical calculations.
Software interaction: It can make HTTP requests, integrate with external systems, invoke APIs, etc.
This capability is especially useful when an LLM needs to perform tasks beyond generating text. For example, it can invoke functions to obtain specific data, such as executing system commands, generating reports, interacting with third-party services, or consulting complex systems.
Preparation
The most important thing for function execution as part of LLM Tools is that the model can understand clearly when to execute one function or another, so unlike what many think, detailing each function well and in natural language is important, not assuming anything and giving all necessary instructions to the model so it does not make mistakes both in the functionality of a procedure and in each of the parameters it requires for its execution.

Function Example
To describe a function in the context of function calling in LLM models, it is essential to provide a clear structure that specifies what the function does, what parameters it receives, and what result it returns. Next, we will see how to define a function, in our case a function that returns the current date and time of the system.
First, the function name must be clear and not mnemonic and preferably not abbreviated. For example, the function name can be called Get_Fecha_Actual, as a parameter it could be the location about which we need to obtain the date.
Function Name: Get_Fecha_Actual
Function Description: The Get_Fecha_Actual function returns the current date and time in a specific geographic location. It is used to obtain the localized date and time according to the time zone of the provided city or country.
Parameter: Location corresponds to the city, country or time zone location, it is optional and if it does not exist it will take the city of Colombia by default.
It should be noted that the name is clear and understandable for a human and therefore for artificial intelligence.

Implementation
There are 2 ways to implement functions, the first is with the TAiChat.Function property, which allows defining the function specifically for that component, and we also have a separate component called TAIFunctions, which can be associated through the TAiChat.AiFunctions property, both ways work similarly, however, the advantage of the second method is that the TAiFunctions component can be shared between different objects, thus sharing the same function between different TAiChat components.
The logic is that if it has the AiFunctions property assigned, the component will execute the functions that are in the TAiFunctions component, while if that property is Nil, it will execute the functions that are in the TAiChat.Functions property, that is, the local ones.

For this example we will use the TAiFunctions component and associate it to the TChat.AiFunctions property, so we can share it with different components.  
First, we will define the function in the TAiFunctions component in the Functions property, as it is a collection we will do it from the visual environment.

In the property we add a new function and change the Name property to the clear name of the function, in this example it would be Get_FechayHoraActual, it must be accompanied by a Description that is clear and concise. 
Subsequently we define the parameters, in this example it would be Location, it must also be accompanied by a clear description and if the parameter is required or is of enumerated type, for which a comma-separated list can be created.
Finally, the function will have an event that will execute when the LLM considers it should use it.  
procedure TForm75.AiFunctions1Functions0Get_FechayHoraAction(Sender: TObject;
              FunctionAction: TFunctionActionItem; FunctionName: string;
              ToolCall: TAiToolsFunction; var Handled: Boolean);
Var
  Locacion : String;
begin
  Locacion := ToolCall.Params.Values['Localizacion'];
  //here the time should be calculated depending on the location
  ToolCall.Response := FormatDateTime('YYYY-MM-DD hh:nn:ss', Now);
  Handled := True;
end;

As a response in this example we will simply return the system date and time, but really here it is possible to perform quite complex procedures and this is the basis of the famous GPTs of OpenAi.
It should be taken into account that some models like those of OpenAi can execute functions in parallel handling threads, therefore, it is necessary to program these functions taking into account Multithread execution. 
IMPORTANT NOTE: None of the events are protected to be executed in the background or with thread concurrency protection, therefore, it is necessary for the user to handle these situations.
Example:  
If you are accessing databases you must create a connection component each time the function is called, since for example TFDConnection does not allow concurrent handling and can cause execution blockages.

Visual interface handling must always be done within a protected function like TThread.Synchronize or TThread.Queue, since it can interfere with the main thread flow and cause application blockages.

If several functions or even the same function access global variables, it will be necessary to use semaphores to avoid concurrency and errors for this reason.

TAiChat Component Events
In this section we will make a small tour of each of the events that we have not yet mentioned in this manual and how to use them.
OnInitchat
This event is used to intercept LLM initialization, it only executes once automatically before adding the first message to the message list, it is the moment where both the initial message and the TAiChat.Memory property can be modified.

    Chat.InitialInstructions.Text := 'You are an expert in Delphi language';
    Chat.AddToMemory('My_Name','Gustavo');
    Chat.AddToMemory('Your_Name_Assistant','SofIA');

The aText parameter in the function would correspond to Chat.InitialInstructions.Text and the aMemory parameter would be
{
    "MyName": "Gustavo",
    "Your_Name_Assistant": "SofIA"
}

In this event it is possible to modify the parameters completely. This case allows personalizing the model behavior based on some parameter like the user.

procedure TForm75.AiOpenChat1InitChat(const Sender: TObject; aRole: string;
  var aText: string; var aMemory: TJSONObject);
begin
   aText := 'You are an expert Delphi programmer and also in Sql databases';
   aMemory.AddPair('Remember1','You are obsessive with details');
end;

OnAddMessage
This event executes whenever a new message is added to the message list, this includes the initial "System" and "User" messages, it does not include "Assistant" messages. It is possible to modify some of the aMsg message parameters directly in the parameter.

procedure TForm75.AiConnAddMessage(const Sender: TObject; aMsg: TAiChatMessage;
  aResponse: TJSONObject; aRole, aText: string);
begin
    ShowMessage(aRole+' : '+aMsg.Prompt)
end;

OnBeforeSendMessage
This event allows capturing messages just before being sent to the LLM, very similar to OnAddMessage it allows intercepting the message and modifying it, only this event only includes "User" messages.
procedure TForm75.AiOpenChat1BeforeSendMessage(const Sender: TObject;
  var aMsg: TAiChatMessage);
begin
   aMsg.LoadMediaFromFile('/my/file.png');
end;


OnCallToolFunctions
As we saw in the previous section about LLM function execution, each function has an event destined to execute automatically when it finds the need, however, if the function defined in the TAiChat.Functions property or in the TAiFunctions.Functions Component does not have an associated event or the Handled variable = false, the system assumes it was not executed and proceeds to execute the OnCallToolFunction event of the component.

procedure TForm75.AiOpenChat1CallToolFunction(Sender: TObject;
  AiToolCall: TAiToolsFunction);
Var
  MiParam : String;
begin
  If AiToolCall.&Function = 'MiFuncion' then
  Begin
    MiParam := AiToolCall.Params.Values['MiParam'];
    //here executes the corresponding function
  End;
end;


TAiChatConn Component
One of the premises of the MakerAi component Suite consists of use transparency between different LLM models, that is, with the same code it is possible to interact with the models and services that exist on the market, so one of the characteristics that have been sought is to allow changing LLM in a simple way.
For this the TAiChatConn component has been created, which allows "Connecting" our program transparently with any model, changing only the TAiChatConn.Chat property, likewise this component has the basic parameters common to all components, thus allowing having a single connector to the different available LLMs.
Note: This component is still in development, so some functionalities are not available.


This way it is possible to interact simply with AiConn without dealing with other models. For example, for the execution of a request it would be something like this.

Var
  Res: String;
  MediaFile: TAiMediaFile;
  Msg: TAiChatMessage;
begin

  If FileExists(OpenDialog1.FileName) then
  Begin
    MediaFile := TAiMediaFile.Create;
    MediaFile.LoadFromFile(OpenDialog1.FileName);
    // MediaFile.LoadFromUrl(Url);  //Url with the identifiable file name
    // MediaFile.LoadFromBase64(FileName, Base64Data); //The filename is used to obtain the image type
    // MediaFile.LoadFromStream(FileName, Stream); //The filename is used to obtain the image type
  End;

  If ChIncludeImage.IsChecked then
    Res := AiConn.AddMessageAndRun(MemoPrompt.Lines.Text, 'user', [MediaFile])
  Else
    Res := AiConn.AddMessageAndRun(MemoPrompt.Lines.Text, 'user', []);

  MemoResponse.Lines.Text := Res;
  FreeAndNil(MediaFile);


Delphi MVP - Gustavo Enriquez
 Social Networks:
 - Email: gustavoeenriquez@gmail.com
 - Telegram: +57 3128441700
 - LinkedIn: https://www.linkedin.com/in/gustavo-enriquez-3937654a/
 - Youtube: https://www.youtube.com/@cimamaker3945
 - GitHub: https://github.com/gustavoeenriquez/
