📘 User Guide: TAiClaudeChat Component (Delphi)
This component allows Delphi applications to connect with the Anthropic API (Claude 3.5 and 3.7), supporting the most advanced features such as Extended Thinking, Code Execution, Web Search, and Context Caching.

1. Basic Configuration
Initialization
Place the component on your form or create it at runtime.
codeDelphi
uses uMakerAi.Chat.Claude;

procedure TForm1.FormCreate(Sender: TObject);
begin
  AiClaudeChat1.ApiKey := 'sk-ant-api03-...'; // Your Anthropic API Key
  
  // Select Model (Recommended: Claude 3.7 Sonnet)
  AiClaudeChat1.Model := 'claude-3-7-sonnet-20250219';
  
  // Configure base instructions (Personality)
  AiClaudeChat1.InitialInstructions.Text := 'You are a Delphi and Pascal expert.';
end;

2. "Thinking" Mode (Extended Thinking) 🧠
Allows Claude to "reason" step by step before responding, ideal for complex logic, math, or programming problems.
Manual Configuration
codeDelphi
procedure EnableThinking;
begin
  // 1. Enable the feature
  AiClaudeChat1.EnableThinking := True;
  
  // 2. Define token budget for thinking (Min 1024)
  AiClaudeChat1.ThinkingBudget := 4096; 
  
  // 3. IMPORTANT: Increase total limit
  // Max_tokens must be greater than ThinkingBudget (e.g., 4096 + 4000 for response)
  AiClaudeChat1.Max_tokens := 10000;
  
  // 4. Temperature (Claude forces 1.0 in this mode)
  AiClaudeChat1.Temperature := 1.0;
end;
Quick Configuration (OpenAI Style)
You can use the compatibility property:
codeDelphi
// Automatically adjusts Budget and MaxTokens
AiClaudeChat1.ReasoningEffort := 'high'; // Options: 'low', 'medium', 'high'
View Thinking
Thinking is not mixed with the final response. Access it like this:
codeDelphi
procedure TForm1.AiClaudeChat1ReceiveDataEnd(Sender: TObject; aMsg: TAiChatMessage; ...);
begin
  // Final response for the user
  MemoChat.Lines.Add(aMsg.Content);
  
  // Thinking process (Optional: show in a collapsible panel)
  if aMsg.ThinkingContent <> '' then
    MemoThinking.Lines.Text := aMsg.ThinkingContent;
end;

3. Streaming with Tools (Function Calling) ⚡
The component supports function execution while writing the response in real time.
codeDelphi
procedure StartChatStream;
begin
  AiClaudeChat1.Asynchronous := True; // Enable Streaming
  AiClaudeChat1.Tool_Active := True;  // Enable user-defined Tools
  
  // Send message
  AiClaudeChat1.AddMessageAndRun('What time is it and how is the weather?', 'user', []);
end;

// Event to see text arriving letter by letter
procedure TForm1.AiClaudeChat1ReceiveData(Sender: TObject; ... aText: String);
begin
  MemoChat.Text := MemoChat.Text + aText;
end;

4. Native Tools (Native Tools) 🛠️
Claude has built-in tools that don't require you to write function code. They are activated via the ChatMediaSupports property.
A. Web Search and Code Execution
codeDelphi
// Enable capabilities
AiClaudeChat1.ChatMediaSupports := [
   tcm_WebSearch,          // Claude can search the internet
   tcm_code_interpreter    // Claude can execute Python/Bash
];

// Usage example:
AiClaudeChat1.AddMessageAndRun('Search the current price of Bitcoin and graph it with Python', 'user', []);
B. Text Editor (File Editing)
Allows Claude to read, create, and modify local files (useful for programming agents).
codeDelphi
// 1. Enable support
AiClaudeChat1.ChatMediaSupports := [tcm_TextEditor];

// 2. (Optional) Register a safe class to limit disk access
initialization
  TAiClaudeChat.RegisterTextEditorClass(TSecureEditor); // Your inherited class
C. Memory (Knowledge Base)
Allows Claude to remember data between sessions if the API supports it.
codeDelphi
AiClaudeChat1.EnableMemory := True;

5. Prompt Caching (Cost Savings) 💰
Ideal when you repeatedly send long documents or complex system instructions.
Cache the System Prompt
If you have a 50-page manual in InitialInstructions:
codeDelphi
AiClaudeChat1.CacheSystemPrompt := True;
Effect: The first call costs normal. Subsequent calls (within 5 min) cost ~10% of the price.
Cache Specific Files or Messages
codeDelphi
var
  Msg: TAiChatMessage;
  PDF: TAiMediaFile;
begin
  Msg := AiClaudeChat1.NewMessage('Analyze this book', 'user');
  
  PDF := TAiMediaFile.Create;
  PDF.LoadFromFile('BigBook.pdf');
  
  // Mark for caching
  PDF.CacheControl := True; 
  
  Msg.AddMediaFile(PDF);
  AiClaudeChat1.InternalAddMessage(Msg);
  AiClaudeChat1.Run(nil, nil);
end;

6. Context Management (Auto-Cleanup) 🧹
For very long chats, avoid filling the context window by automatically clearing old tool data.
codeDelphi
// Configure at startup
procedure ConfigureCleanup;
begin
  // If history exceeds 20k tokens, clear old tool usage,
  // but keep the last 3 interactions to not lose the thread.
  AiClaudeChat1.ConfigureAutoContextClearing(20000, 3);
end;

Summary of Key Properties

Complete Initialization Example
codeDelphi
procedure TForm1.InitAgent;
begin
  with AiClaudeChat1 do
  begin
    // 1. Powerful Model
    Model := 'claude-3-7-sonnet-20250219';
    
    // 2. Streaming and Tools
    Asynchronous := True;
    Tool_Active := True;
    
    // 3. Native Capabilities
    ChatMediaSupports := [tcm_WebSearch, tcm_code_interpreter, tcm_TextEditor];
    
    // 4. Thinking Configuration
    ReasoningEffort := 'high'; // Configures auto thinking and budget
    
    // 5. Cost Optimization
    InitialInstructions.LoadFromFile('Rules.txt');
    CacheSystemPrompt := True;
    
    // 6. Automatic cleanup
    ConfigureAutoContextClearing(30000, 5);
  end;
end;


📂 File Management (Files API)
These functions allow direct interaction with Anthropic's cloud storage. They are useful when you need to upload PDF documents, images, or text files to manage them by ID instead of sending Base64 content every time (though the component handles Base64 automatically in normal chat).
Note: These functions use the beta header files-api-2025-04-14 internally.

1. Upload Files (UploadFile)
Uploads a physical file or stream to Claude's servers and returns a File ID.
codeDelphi
Function UploadFile(aMediaFile: TAiMediaFile): String; Override;
Parameter aMediaFile: A TAiMediaFile object previously loaded with data (from file, stream, or URL).
Return: The File ID generated by Anthropic (e.g., file_xyz...).
Usage:
codeDelphi
var
  MyFile: TAiMediaFile;
  FileID: string;
begin
  MyFile := TAiMediaFile.Create;
  try
    MyFile.LoadFromFile('C:\Docs\Contract.pdf');
    
    // Upload to cloud
    FileID := AiClaudeChat1.UploadFile(MyFile);
    
    ShowMessage('File uploaded with ID: ' + FileID);
    // Now the MyFile object has its .IdFile property updated
  finally
    MyFile.Free;
  end;
end;

2. List Files (RetrieveFileList)
Gets a list of all files you have previously uploaded that are still available in your organization.
codeDelphi
function RetrieveFileList: TAiMediaFiles; Override;
Return: A TAiMediaFiles object (a list of TAiMediaFile) with each file's metadata (ID, name, size, creation date).
Usage:
codeDelphi
var
  List: TAiMediaFiles;
  File: TAiMediaFile;
begin
  List := AiClaudeChat1.RetrieveFileList;
  try
    for File in List do
    begin
      Memo1.Lines.Add('ID: ' + File.IdFile + ' - Name: ' + File.FileName);
    end;
  finally
    List.Free;
  end;
end;

3. Get Metadata (RetrieveFile)
Retrieves information about a specific file using its ID. Useful for verifying if a file exists or its size.
codeDelphi
function RetrieveFile(aFileId: string): TAiMediaFile; Override;
Parameter aFileId: The ID of the file you want to query (e.g., file_xyz...).
Return: A TAiMediaFile object with file information. Returns nil if it fails.
Note: Does not download binary content, only descriptive data.

4. Delete File (DeleteFile)
Deletes a file from Anthropic's servers. It's good practice to delete files no longer needed to maintain privacy and order.
codeDelphi
Function DeleteFile(aMediaFile: TAiMediaFile): String; Override;
Parameter aMediaFile: Must have at least the IdFile property assigned.
Return: The ID of the deleted file as confirmation.

5. Check State (CheckFileState)
A utility function that verifies if a file is still accessible on the server.
codeDelphi
Function CheckFileState(aMediaFile: TAiMediaFile): String; Override;
Return: Returns the IdFile if the file exists and is accessible. Returns an empty string '' if the file is not found or there was an error.

6. Upload to Cache (UploadFileToCache)
In Anthropic's ecosystem, there is no strict "File Cache" distinction as in other providers. This function acts as an alias for UploadFile to maintain compatibility with generic TAiChat code.
codeDelphi
Function UploadFileToCache(aMediaFile: TAiMediaFile; aTTL_Seconds: Integer = 3600): String; Override;
Behavior: Internally calls UploadFile. The aTTL_Seconds parameter is ignored in Claude, as persistence depends on Anthropic's retention policies.

7. Download Content (DownLoadFile)
⚠️ Important: Due to security policies and API design, Anthropic does not allow downloading binary content of files uploaded via the API (unlike OpenAI).
codeDelphi
Function DownLoadFile(aMediaFile: TAiMediaFile): String; Override;
Current behavior: This function returns an empty string or throws an exception indicating download is not supported by the provider.
Usage: Should not be used to retrieve files. You must maintain your own local copy of uploaded files.

Summary of Operations

📂 Practical Cases: File Management (Files API)
Although the TAiClaudeChat component automatically handles sending images and documents in chat (converting them to Base64 in real time), dedicated file management functions (UploadFile, DeleteFile, etc.) have a different strategic purpose in the Anthropic ecosystem.
These functions interact with the /v1/files endpoint and are fundamental for asynchronous processes and cost optimization.

Case 1: Preparation for Batch Processing (Batch API) 📉
The problem: Your company needs to classify 10,000 emails or analyze 5,000 database records. Doing this message by message in chat is slow, blocks the application, and you pay full price per token.
The solution: The Files API is the first step to using the Message Batches API.
You generate a local file (.jsonl) containing the 10,000 requests.
You use UploadFile to send this file to Anthropic's servers.
(Note: The file ID would then be sent to the Batches endpoint).
Benefit: This method offers a 50% discount on token costs compared to standard chat.
codeDelphi
// Example: Upload a work batch for overnight processing
var
  WorkBatch: TAiMediaFile;
  FileID: string;
begin
  WorkBatch := TAiMediaFile.Create;
  try
    // JSONL file with thousands of prepared requests
    WorkBatch.LoadFromFile('C:\Data\Analysis_Batch_2025.jsonl');
    
    // Upload to Anthropic cloud
    FileID := AiClaudeChat1.UploadFile(WorkBatch);
    
    Log('Batch uploaded successfully. ID for Batch: ' + FileID);
  finally
    WorkBatch.Free;
  end;
end;

Case 2: Privacy and Compliance Management (GDPR) 🛡️
The problem: You have uploaded confidential data for analysis, but due to security policies (like GDPR or ISO 27001), that data cannot remain on third-party servers indefinitely.
The solution: Use listing and deletion functions to maintain strict data hygiene.
codeDelphi
// Example: End of day cleanup
procedure TForm1.CleanRemoteData;
var
  Files: TAiMediaFiles;
  File: TAiMediaFile;
begin
  // 1. Get everything we have in the cloud
  Files := AiClaudeChat1.RetrieveFileList;
  try
    for File in Files do
    begin
      // 2. Delete old or already processed files
      AiClaudeChat1.DeleteFile(File);
      MemoLog.Lines.Add('File deleted from server: ' + File.FileName);
    end;
  finally
    Files.Free;
  end;
end;

Case 3: Stability on Slow Connections 🌐
The problem: Trying to send a chat with a gigantic context (e.g., an entire PDF book) in a single HTTP request can cause timeouts or network errors if the client connection is unstable.
The solution:
Upload the file first using UploadFile (which is a dedicated and robust multipart/form-data operation).
Verify the file is safely on the server with CheckFileState.
Reference the file in future processes (as API availability allows) without having to retransmit megabytes of data.

Decision Table: Which method to use?


🚀 Batch Processing (Message Batches API)
The TAiClaudeChat component allows access to Anthropic's powerful Batches API. This functionality is designed to process large volumes of requests asynchronously, offering a 50% cost discount and avoiding network congestion in your application.
Key Difference: Unlike other providers, files you upload to Claude are not for "chatting with a PDF" in real time. They are data containers (work packages) sent to the Batches API.

Complete Workflow
The process consists of 4 steps:
Prepare: Create a local .jsonl file with the requests.
Upload: Send the file to the cloud (UploadFile).
Execute: Order Claude to process the file (CreateMessageBatch).
Retrieve: Download results when ready.

Step 1: Prepare the Batch File (.jsonl)
You must generate a text file where each line is a JSON object representing a complete chat request.
Example content of trabajo.jsonl:
codeJSON
{"custom_id": "ticket-101", "params": {"model": "claude-3-5-haiku-20241022", "max_tokens": 100, "messages": [{"role": "user", "content": "Classify this ticket: Login error"}]}}
{"custom_id": "ticket-102", "params": {"model": "claude-3-5-haiku-20241022", "max_tokens": 100, "messages": [{"role": "user", "content": "Classify this ticket: Blue screen"}]}}

Step 2: Upload the File
Use the file management function to upload your .jsonl.
codeDelphi
var
  BatchFile: TAiMediaFile;
  InputFileId: string;
begin
  BatchFile := TAiMediaFile.Create;
  try
    BatchFile.LoadFromFile('C:\Batches\work.jsonl');
    InputFileId := AiClaudeChat1.UploadFile(BatchFile);
    // Returns e.g.: "file_xyz123..."
  finally
    BatchFile.Free;
  end;
end;

Step 3: Create the Batch (Execute Process)
Once the file is uploaded, you use its ID to start processing on Anthropic's servers.
codeDelphi
var
  BatchId: string;
begin
  // Start the process
  BatchId := AiClaudeChat1.CreateMessageBatch(InputFileId);
  
  MemoLog.Lines.Add('Batch started with ID: ' + BatchId);
  MemoLog.Lines.Add('The process can take up to 24 hours (usually much less).');
end;

Step 4: Check Status and Results
Although the component doesn't have automatic polling (to not block the UI), you can check the Batch status using its ID.
(Note: It's recommended to implement a CheckBatchStatus(BatchId) function that calls the GET /v1/messages/batches/{id} endpoint).
When the status is "ended", the response JSON will give you a results_file_id.
You use RetrieveFile(results_file_id) to get metadata.
Download the content (using a standard HTTP client with authentication headers, since DownLoadFile is not implemented in the component due to chat API security restrictions, but the Batches API does allow downloading results).

Summary of New Functions
When to use Batches?
Advantage: 50% token cost savings and higher rate limits than standard chat.

Delphi Code: Create and Execute a Batch
codeDelphi
uses
  System.IOUtils, System.Classes, uMakerAi.Core, uMakerAi.Chat.Claude;

procedure TForm1.btnExecuteBatchClick(Sender: TObject);
var
  BatchFile: TAiMediaFile;
  JsonLContent: TStringList;
  InputFileId, BatchId: string;
  FileName: string;
begin
  // ---------------------------------------------------------
  // STEP 1: PREPARATION (Generate the .jsonl file)
  // ---------------------------------------------------------
  // In a real app, you would generate this by iterating over your database.
  // Each line is a complete, independent JSON request.
  
  FileName := TPath.Combine(TPath.GetDocumentsPath, 'test_batch.jsonl');
  JsonLContent := TStringList.Create;
  try
    // Request 1: Translate text
    JsonLContent.Add('{"custom_id": "req-001", "params": {"model": "claude-3-5-haiku-20241022", "max_tokens": 100, "messages": [{"role": "user", "content": "Translate to English: Hello world"}]}}');
    
    // Request 2: Summarize text
    JsonLContent.Add('{"custom_id": "req-002", "params": {"model": "claude-3-5-haiku-20241022", "max_tokens": 100, "messages": [{"role": "user", "content": "Summarize in 5 words: Artificial intelligence is changing the world."}]}}');

    JsonLContent.SaveToFile(FileName, TEncoding.UTF8);
    MemoLog.Lines.Add('Local file generated: ' + FileName);
  finally
    JsonLContent.Free;
  end;

  // ---------------------------------------------------------
  // STEP 2: UPLOAD (UploadFile)
  // ---------------------------------------------------------
  BatchFile := TAiMediaFile.Create;
  try
    BatchFile.LoadFromFile(FileName);

    MemoLog.Lines.Add('Uploading file to Anthropic...');
    
    // This function returns the file ID in the cloud (e.g.: "file_abc123...")
    InputFileId := AiClaudeChat1.UploadFile(BatchFile);
    
    MemoLog.Lines.Add('File uploaded successfully.');
    MemoLog.Lines.Add('File ID: ' + InputFileId);

    // ---------------------------------------------------------
    // STEP 3: EXECUTION (CreateMessageBatch)
    // ---------------------------------------------------------
    if InputFileId <> '' then
    begin
      MemoLog.Lines.Add('Requesting Batch creation...');
      
      // This function returns the batch process ID (e.g.: "msgbatch_xyz789...")
      BatchId := AiClaudeChat1.CreateMessageBatch(InputFileId);

      MemoLog.Lines.Add('Batch started successfully!');
      MemoLog.Lines.Add('Batch ID: ' + BatchId);
      MemoLog.Lines.Add('------------------------------------------------');
      MemoLog.Lines.Add('NOTE: The process is asynchronous. Claude will process requests');
      MemoLog.Lines.Add('in the background. It will cost 50% less than normal chat.');
    end;

  except
    on E: Exception do
      MemoLog.Lines.Add('Error: ' + E.Message);
  finally
    BatchFile.Free;
  end;
end;
What happens next?
Once you have the Batch ID, the component's work is done for now (you don't block the screen waiting).
In a real production scenario, you would save that BatchId in a database and have a timer or scheduled process that checks the batch status periodically (every 15 minutes, for example) to see if it has finished and download the results.

Property | Description | Recommendation
Model | Model version | claude-3-7-sonnet-20250219
Asynchronous | Streaming | True for better UX
EnableThinking | Activates reasoning | True for complex tasks
ThinkingBudget | Tokens for thinking | 4096 (Adjust by difficulty)
ChatMediaSupports | Activates Web/Code/Edit | [tcm_WebSearch, tcm_code_interpreter]
CacheSystemPrompt | Save money | True if Prompt > 1000 tokens
EnableMemory | Persistent memory | True for agents

Function | Description | API Endpoint
UploadFile | Uploads a file for future use. | POST /v1/files
RetrieveFileList | Shows all your uploaded files. | GET /v1/files
RetrieveFile | Gets file details. | GET /v1/files/{id}
DeleteFile | Deletes a file. | DELETE /v1/files/{id}
DownLoadFile | ❌ Not supported by API. | N/A

Need | Recommended Method | Why?
Interactive Chat (User expects response) | AddMessage + TAiMediaFile | It's immediate. The component handles Base64 conversion automatically.
Analyze 1 Image | AddMessage + TAiMediaFile | Simple and fast.
Process 1,000+ Records | UploadFile (Batch) | You save 50% money and don't block the UI.
Data Audit | RetrieveFileList | Allows knowing what data Anthropic has from you.
Secure Deletion | DeleteFile | Ensures data is deleted from the cloud.

Function | Description | Beta Header
CreateMessageBatch(FileId) | Creates a processing batch from an uploaded JSONL file. | message-batches-2024-09-24

Scenario | Recommended Method
User asks something in chat | Normal Chat (AddMessage)
Analyze 1 PDF document | Normal Chat (AddMessage + MediaFile)
Classify 10,000 old emails | Batch API (UploadFile + CreateMessageBatch)
Generate descriptions for 5,000 products | Batch API (UploadFile + CreateMessageBatch)