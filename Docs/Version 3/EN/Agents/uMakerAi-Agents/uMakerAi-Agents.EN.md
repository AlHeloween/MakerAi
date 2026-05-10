


Module 1: Why do we need to orchestrate AI? Beyond simple question and answer.
The Silent Revolution in your IDE
As a Delphi developer, you are accustomed to building robust, fast, and reliable applications. For decades, we have mastered the creation of complex systems, from ERPs and point-of-sale systems to industrial software. Today, a new revolution is knocking at our door: Generative Artificial Intelligence and Large Language Models (LLMs) like GPT, Gemini, or Llama.
Integrating an API call to an LLM in a Delphi application is relatively simple. With components like TRESTClient, we can send a question and receive an answer. This is useful, but it is only the tip of the iceberg. Soon we encounter more complex questions:
"How can I make the LLM query my customer database to answer a question?"
"What if I need it to automatically send a report by email after generating it?"
"How can I maintain a coherent conversation with a user, remembering what was said before?"
"What if a task requires multiple reasoning steps and access to different tools?"
This is where a simple API call falls short.
The Problem: The LLM is a Brain without Hands
Imagine an LLM as an incredibly intelligent and eloquent brain, but one that is isolated in a room without doors or windows. It can reason, write, and generate ideas, but it cannot interact with the outside world. It cannot search the internet, read a file on your hard drive, query your SQL database, or execute an action in your application.
When we try to solve real-world problems that require more than just generating text, we face these limitations:
Lack of Updated Context: LLMs are trained with data that has a cutoff date. They do not know what happened yesterday, nor what the current stock of your best-selling product is.
Inability to Act: They cannot execute actions. They cannot click a button, call an external API (by themselves), or modify a record in a database.
Multi-Step Complexity: Tasks like "Research the latest market trends for product X, draft an email for the marketing team, and save it in the drafts folder" are impossible to perform in a single step.
Trying to manage this logic manually in your Delphi code can quickly become "spaghetti" code with if-then-else statements, nested API calls, and fragile, hard-to-maintain state management.
The Solution: Agents and AI Graphs
The solution is not to ask the LLM to do everything, but to treat it as just another component (albeit a very special one) within a larger workflow. This is where orchestration comes in.
MakerAI Agents allows you to build these intelligent workflows in a structured, visual, and powerful way. The central idea is simple: decompose a complex problem into a series of interconnected steps, forming what we call an "AI Graph".
To understand how it works, let us introduce some key concepts:
Agent: An agent is not just an LLM. It is a system that uses an LLM as its "reasoning engine" to make decisions and act. The agent observes an input (for example, a user question), thinks about what steps it must follow to solve it, and uses the tools at its disposal to execute those steps.
Tool: A tool is the "hand" we give to our AI brain. It is a well-defined Delphi function or procedure that the agent can execute to interact with the outside world.
TDatabaseTool: A tool to execute SQL queries.
TFileTool: A tool to read or write files.
TWebApiTool: A tool to consume data from an external API (for example, weather, stock prices, etc.).
Chains vs. Graphs:
A Chain is the simplest form of orchestration: a linear flow where the output of step A becomes the input of step B, B's output becomes C's input, and so on. Example: Translate a text -> Summarize the translated text -> Analyze the sentiment of the summary.
A Graph is a much more powerful and flexible structure, necessary for most real-world problems. It allows:
Branches: Take different paths based on a condition (e.g., if sentiment is positive, do X; if negative, do Y).
Parallelization (Fan-out): Execute multiple steps at the same time to improve efficiency.
Joins: Wait for multiple parallel branches to finish before continuing.
Cycles: Repeat a set of steps until a condition is met (e.g., the agent tries to use a tool, if it fails, it reasons again and tries another way).
State and the Blackboard: For different steps of a graph to communicate with each other, they need a shared place where they can read and write information. This is the role of the Blackboard (TAIBlackboard). It is a persistent memory for a single graph execution. A node can write a result to the blackboard (e.g., Blackboard.SetString('CustomerID', '123')), and another node, later in the flow, can read that value to perform its task.

Module 2: Anatomy of an AI Graph with MakerAI Agents
The Metaphor: An Intelligent Flowchart
If you have ever designed a flowchart to represent a business process or an algorithm, you are already halfway to understanding how MakerAI Agents works.
Imagine each box in your flowchart as a unit of work (TAIAgentsNode) and each arrow connecting them as a flow route (TAIAgentsLink). Now, imagine that inside some of those boxes there is an AI "brain" capable of making decisions, and that the arrows can change direction dynamically according to results. That is, in essence, an AI Graph.
MakerAI Agents allows you to build these intelligent flowcharts directly in the Delphi form designer or create them dynamically by code. Each piece of the puzzle is a Delphi component, with properties you can configure in the Object Inspector and events you can implement in the Code Editor.
Let us break down the fundamental pieces that make up any graph you build.

2.1 The Orchestrator (TAIAgents): The Operational Brain
The TAIAgents component is the heart and brain of the entire system. It does not perform any business task by itself, but is responsible for managing and executing the entire graph. Think of it as the conductor of an orchestra: it does not play any instrument, but ensures all musicians (the nodes) enter on time, follow the score (the flow), and work in harmony.
You will place a TAIAgents component on your form or DataModule as the main entry point for your AI logic.
Key Responsibilities:
Graph Container: It is the "owner" of all nodes (TAIAgentsNode) and links (TAIAgentsLink) that are part of the graph. When you place a node on the form, it is automatically associated with the main orchestrator.
Entry and Exit Point: Through its StartNode and EndNode properties, you tell the orchestrator where the execution flow should begin and end.
StartNode: The first node that will be executed when you call the Run method.
EndNode: A special node that marks the successful completion of the graph.
Execution Engine: The Run(Input: string): ITask method is what starts everything. It initiates graph execution in a secondary thread (TTask) to not block your application's user interface, and returns a task (ITask) you can use to wait for completion if necessary.
Centralized State Management: The orchestrator owns the Blackboard, which is the shared state for the entire graph execution. We will see the blackboard in detail later, but it is crucial to understand that TAIAgents manages it.
Global Event Handling: It provides graph-level events to manage communication and errors in a centralized way.
OnPrint: A useful event for logging and debugging. Any node or link in the graph can call its Print method, and this event will fire.
OnError: A global "try-catch" for your graph. If any node or link throws an exception during execution, this event captures it, allowing you to log the error, notify the user, or decide whether to abort execution.
OnEnd: Fires when the graph finishes execution (either reaching the EndNode or being aborted). This is where you will normally collect the final result from the Output of the last node or from the Blackboard.
OnConfirm: Facilitates interaction with the user. Allows a node to stop the flow and ask the user a question (through the main UI), waiting for an answer to continue.
In Practice:
On your form, you will have a single TAIAgents. You will configure it by assigning the start and end nodes, and you will probably implement the OnEnd and OnError events to know when the work has finished and if something went wrong. All the complex and specific logic of each step will reside in the individual nodes, keeping your code clean and organized.
2.2 The Node (TAIAgentsNode): The Unit of Work
If TAIAgents is the orchestra conductor, TAIAgentsNode is the musician. Each node represents a discrete and specific step within your workflow. It is a box in our "intelligent flowchart" that receives an input, performs an action, and produces an output.
The beauty of this approach is that you can create nodes for any type of task, from simple text manipulation to a complex call to an AI model, a database query, or the execution of a specialized tool.
Key Properties and Concepts:
Input and Output (String):
Input: The data the node receives to work with. By default, a node's Input is automatically filled with the Output of the node that preceded it in the flow.
Output: The result of the work done by the node. This value will be passed as Input to the next connected node. If not modified, the Output equals the Input, allowing data to flow through nodes that do not need to alter it.
OnExecute (Event):
This is the logical heart of the node. It is an event of type procedure(Node, BeforeNode: TAIAgentsNode; Link: TAIAgentsLink; Input: String; var Output: String) where you write the code that defines what this node does.
You receive the Input.
You perform your logic (call a function, an API, process text...).
You assign the result to the var Output parameter.
Next (TAIAgentsLink):
This property connects the node to the next step in the flow. From a node, only one link can exit. However, as we will see in the next section, that single link can have multiple destinations, allowing parallel execution.
Tool (TAiToolBase):
A powerful alternative to the OnExecute event. Instead of writing code directly in the form event, you can associate a predefined "Tool" (a TAiToolBase component) to the node. When the node executes, if it has a Tool assigned, it will call the Execute method of that tool. This promotes code reuse and separation of responsibilities. For example, you can have a single TDatabaseQueryTool and use it in multiple nodes across different graphs. The node that has the highest priority is OnExecute over Tool.
JoinMode and Synchronization:
A node can be the arrival point of multiple links (for example, after parallel execution). The JoinMode property controls how the node behaves in this situation:
jmAny (default): The node will execute every time one of the input branches arrives at it. This is ideal for graphs containing cycles or loops.
jmAll: The node will wait for all input branches to complete their execution and arrive at it before executing once. This is essential for synchronizing parallel tasks before proceeding to the next step (such as unifying results in a final report).
The Role of the Node in the Graph:
You can have different types of nodes according to their function:
Processing Nodes: Perform a specific task, such as calling an LLM, formatting text, performing a calculation, etc.
Routing Nodes: Nodes whose main function is to analyze the current state (often reading from the Blackboard) to make a decision that will influence the path the flow will take.
Tool Nodes: Nodes that act as executors of actions in the real world, using the Tool component.
Wait/Join Nodes: Nodes configured with JoinMode = jmAll that serve as synchronization points in the graph.
When designing your graph, think of each task as an independent node. This makes your workflow modular, easier to understand, debug, and maintain.

2.3 The Link (TAIAgentsLink): Defining Flow and Logic
If nodes are cities on our map, links (TAIAgentsLink) are the roads that connect them. A link defines the route that data and control follow from one node to another. However, in MakerAI Agents, a link is much more than a simple arrow; it can contain its own logic to create dynamic and complex workflows.
Each TAIAgentsNode has a single output property, Next, where a TAIAgentsLink is assigned. It is this link that determines what happens next.
Key Capabilities of a Link:
Simple Connection (Single Destination):
In its most basic form, a link connects one node to another. This is done by assigning the destination node to the link's NextA property. This is the pillar for building linear chains (A -> B -> C).
Parallel Execution (Fan-out):
This is where the power begins to manifest. A single link can have multiple destinations. The NextA, NextB, NextC, and NextD properties can each point to a different node. When the flow reaches this link, all destination nodes execute simultaneously, each in its own thread. This is ideal for tasks that do not depend on each other and can be performed at the same time to save time.
Example: A node receives a product request. Its output link splits so that three nodes execute in parallel: one queries stock, another searches for customer reviews, and a third searches for competing products.
Failure Routes (Fallback):
The NextNo property defines an alternative route. It is used in conjunction with the link's own conditional logic to handle "failure" cases or when a condition is not met.
MaxCicles: This property sets a maximum number of times this link can be passed in a loop before considering it a failure and taking the NextNo route. This is a crucial safety mechanism to avoid infinite loops.
Conditional Routing (Intelligent Decision):
This is one of the most advanced and powerful features, elevating your graph from a simple script to a reasoning system. A link can function as a "switch" or a "router".
How it works: Instead of using NextA, NextB, etc., a dictionary of conditional destinations is defined. The link, when executed, will consult a specific key in the Blackboard (for example, Blackboard.GetString('next_route')). The value of that key will determine which destination node the flow will be routed to.
Example: A node (ClassifierNode) analyzes an email and writes to the Blackboard whether it is "SALES", "SUPPORT", or "SPAM". The output link of this node is configured with three conditional routes. If 'next_route' is "SALES", the flow goes to SalesTeamNode; if it is "SUPPORT", it goes to SupportTeamNode, and so on.
Custom Logic in Transition (OnExecute):
Like a node, a link also has an OnExecute event. This event gives you precise control over the transition.
procedure(Node: TAIAgentsNode; Link: TAIAgentsLink; var IsOk: Boolean; var Handled: Boolean)
You can perform validations before passing to the next node.
By modifying IsOk := False, you can force the transition to be considered a "failure", which may redirect the flow to NextNo if configured.
By setting Handled := True, you can completely stop the flow at this point, without the link continuing to any of its destinations.

In essence, TAIAgentsLink allows you to decide not only where the flow goes, but also how and why it goes there. The combination of parallelism, failure routes, and conditional routing is what allows you to build graphs that can adapt, react, and make complex decisions.
2.4 The Blackboard (TAIBlackboard): The Shared Memory of the Graph
If nodes are company offices and links are hallways, the blackboard (TAIBlackboard) is the central bulletin board where everyone can read important messages and leave notes for others.
In a graph, nodes often execute independently and, in cases of parallelism, even in different threads. The Blackboard is the mechanism that allows them to communicate and share information in a secure and centralized way. It is, in effect, the short-term memory of a single graph execution.
The Blackboard is a property of the TAIAgents orchestrator, meaning there is only one instance per graph and it is accessible from any node, link, or tool within that graph.
What is it and how does it work?
Technically, TAIBlackboard is a thread-safe dictionary that stores key-value pairs. The key is always a string, and the value can be of various types (TValue), including:
String
Integer
Boolean
Double
And other types supported by TValue.
Main Methods:
To facilitate its use, the Blackboard offers direct and typed methods:
SetString(const AKey, AValue: string): Writes or updates a text value.
GetString(const AKey: string; const ADefault: string = ''): string: Reads a text value. If the key does not exist, it returns the default value.
SetInteger(...), GetInteger(...)
SetBoolean(...), GetBoolean(...)
And generic methods to work with TValue:
SetValue(const AKey: string; const AValue: TValue)
TryGetValue(const AKey: string; out AValue: TValue): Boolean
Crucial Use Cases:
Passing Complex Information between Nodes:
While the Input/Output of a node is ideal for passing the main result of one step to the next, you often need to pass multiple pieces of information.
Example: A GetUserNode gets the ID, name, and subscription level of a user. Instead of concatenating everything into a single output string, it can write each piece of data to the Blackboard:
Graph.Blackboard.SetInteger('UserID', 123);
Graph.Blackboard.SetString('UserName', 'John Doe');
Graph.Blackboard.SetString('Subscription', 'Premium');

Later nodes can now read this information directly, without needing to parse a complex string.

Enabling Conditional Routing:
This is the most important use case. As we saw in the links section, conditional routing depends on a node writing a "decision" to the Blackboard.
Example:
// Inside the OnExecute of a classification node
var Classification: string;
Classification := MyLLM.Classify(Input); // Returns 'support' or 'sales'
Graph.Blackboard.SetString('next_route', Classification);

The next link in the graph will read the value of 'next_route' to decide which node to direct the flow to.

Aggregating Results from Parallel Branches:
When you have multiple nodes running in parallel, each can do its work and write its result to the Blackboard using a unique key. The join node (JoinNode) that comes after can then read all results from the blackboard to consolidate them.
Example:
// In SummarizeNode
Graph.Blackboard.SetString('summary_result', SummaryText);
// In KeywordsNode
Graph.Blackboard.SetString('keywords_result', KeywordsList);
// In ReportNode (the join node)
var FinalReport: TStringBuilder;
FinalReport.AppendLine(Graph.Blackboard.GetString('summary_result'));
FinalReport.AppendLine(Graph.Blackboard.GetString('keywords_result'));

Keeping Counters or State Flags:
You can use the Blackboard to track execution state, such as the number of retries, whether a critical action has already been performed, etc.

The Blackboard is automatically cleared at the start of each execution (Run), ensuring each graph operation starts with a clean state. It is the tool that transforms a collection of isolated steps into a coherent, stateful process.



2.5 The Tool (TAiToolBase): Giving Capabilities to the Agent
So far, we have seen how to build internal workflows. But the real power of an AI agent lies in its ability to interact with external systems: query a database, read a file, call a web API, or execute any other action in your application.
This is where the Tool (TAiToolBase) comes in.
A tool is a reusable Delphi component that encapsulates a specific capability. Instead of writing data access or API logic directly in the OnExecute event of a node, you encapsulate it within a class that inherits from TAiToolBase.
Why use Tools?
Reuse: You can create a tool once (for example, TExecuteSQLQueryTool) and use it in countless nodes across many different graphs. If you need to update how you connect to the database, you do it in one place: the tool class.
Separation of Responsibilities (SoC): Keeps your graph "clean". The graph handles orchestration (the "what" and "when"), while tools handle execution (the "how"). This makes your logic much easier to read, test, and maintain.
Abstraction: A node does not need to know the details of how a tool works. It simply knows it has a tool that, for example, "gets the price of a product". The complexity of the API call, error handling, and response parsing is hidden inside the tool.
Preparation for Autonomous Agents: This is the most important point for the future. Advanced agent systems (like those using Function Calling or ReAct) work by presenting an LLM with a list of available tools. The LLM, based on the user's question, decides which tool to use and with what parameters. By structuring your capabilities as TAiToolBase, you are already building the system the right way to be able, in the future, to allow the LLM to make these decisions autonomously.

Anatomy of a Tool:
Creating a tool is very simple. You must create a new class that inherits from TAiToolBase and override a single method:

type
  TMyCustomTool = class(TAiToolBase)
  protected
    procedure Execute(ANode: TAIAgentsNode; const AInput: string; var AOutput: string); override;
  published
    property Description; // Inherited and very important
  end;

procedure TMyCustomTool.Execute(ANode: TAIAgentsNode; const AInput: string; var AOutput: string);
begin
  // Your logic goes here.
  // AInput: Contains the input from the node using it.
  // ANode: Gives you access to the node executing you, in case you need
  //        to call Print() or access the Blackboard (ANode.Graph.Blackboard).

  // Example:
  ANode.Print(Format('My tool is executing with input: %s', [AInput]));
  AOutput := 'Result of my tool processing ' + AInput;
end;

Execute (Method): It is the heart of the tool. Here you implement what the tool should do.
Description (Property): It is fundamental to document what the tool does here. This description is not just for other developers; it is the text an LLM would use to understand the tool's capability and decide whether to use it. A good description would be: "Searches the current price of a product in the inventory database. The input must be the product SKU."
How is it used?
You create an instance of your tool (you can do it in the form designer if you register it as a component, or by code).
In the TAIAgentsNode you want to use this tool, instead of implementing OnExecute, you assign your tool instance to the node's Tool property.

When the graph executes that node, it will automatically call the Execute method of the assigned tool, passing it the node's Input and expecting the tool to fill the Output.
With this last pillar, you now have a complete view of all the pieces that make up MakerAI Agents. You have learned about the orchestrator, the nodes that do the work, the links that define the flow, the blackboard that shares state, and the tools that connect your graph to the real world.


Module 3: Hello, World! - Your First Graph
In this module, we will leave theory aside to build our first functional AI graph. The objective is simple, but it will allow us to become familiar with the basic workflow of MakerAI Agents: placing components, connecting them, and executing the graph.
Objective:
We will create a simple graph that receives a name as input (for example, "World") and produces a personalized greeting as output ("Hello, World").
Components we will use:
1 x TAIAgents: The main orchestrator.
2 x TAIAgentsNode: One for the start (StartNode) and one for the end (EndNode).
1 x TAIAgentsLink: To connect our two nodes.
Standard VCL/FMX components: TEdit for input, TButton to execute, and TMemo to view OnPrint logs.

Step 1: Preparing the Stage on the Form
Open a new VCL or FMX project in Delphi.
From the Component Palette, in the "MakerAI" tab, drag and drop the following components onto your form:
TAIAgents
TAIAgentsNode
TAIAgentsNode
TAIAgentsLink
Add user interface components: TEdit, TButton, and TMemo.
Rename the components for clarity. This is a good practice that will help you enormously in more complex graphs. Select each component and, in the Object Inspector, change its Name property:
TAIAgents1 -> AgentManager
TAIAgentsNode1 -> nodeStart
TAIAgentsNode2 -> nodeEnd
TAIAgentsLink1 -> linkStartToEnd
TMemo1 -> memoLog
TEdit1 -> editInput (and clear its Text property)
TButton1 -> btnRun (and change its Caption/Text to "Execute")

Your form should look more or less like this (non-visual components will appear at the bottom or as icons):

Step 2: Configuring the Graph
Now we will "wire" our components to define the graph structure. All this is done through the Object Inspector.
Configure the Orchestrator (AgentManager):
Select the AgentManager component.
Find the StartNode property. Click the dropdown and select nodeStart.
Find the EndNode property. Click the dropdown and select nodeEnd.
Connect the Nodes with the Link:
Select nodeStart.
Find its Next property. In the dropdown, select linkStartToEnd. This tells the start node that when it finishes, it must pass control to the link.
Select linkStartToEnd.
Find its NextA property. In the dropdown, select nodeEnd. This tells the link that its only destination is the end node.
That is all! You have just visually defined a flow: nodeStart -> linkStartToEnd -> nodeEnd.

Step 3: Implementing the Logic
Now we need to tell our nodeStart what to do. This is where we will write our first piece of AI code.
Implement the logic of nodeStart:
Select nodeStart on the form.
Go to the Object Inspector, to the Events tab.
Double-click the OnExecute event. The IDE will generate the procedure skeleton.
Write the following code:

procedure TForm1.nodeStartExecute(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: String; var Output: String);
begin
  // 1. We print a log message to see we are here.
  //    Any call to Print() in a node is redirected to the OnPrint event of the orchestrator.
  Node.Print(Format('Start Node: Received input "%s"', [Input]));

  // 2. The main logic: create the greeting.
  //    The 'Input' parameter contains what was passed to the Run() method.
  Output := 'Hello, ' + Input;

  // 3. We print the result we are going to pass to the next node.
  Node.Print(Format('Start Node: Generated output "%s"', [Output]));
end;

Connect the Orchestrator Events:
We need to tell the AgentManager what to do with Print messages and what to do when the graph ends.
Select AgentManager.
In the Events tab, double-click OnPrint. Write this code to show logs in our TMemo:

procedure TForm1.AgentManagerPrint(Sender: TObject; Value: String);
begin
  // We show the message in TMemo, making sure it is thread-safe.
  TThread.Synchronize(nil,
    procedure
    begin
      memoLog.Lines.Add(Format('[%s] %s', [TObject(Sender).ClassName], Value));
    end);
end;

Now, double-click the OnEnd event. This is where we will receive the final result of the entire process.

procedure TForm1.AgentManagerEnd(Node: TAIAgentsNode; Value: string);
begin
  // 'Node' is the last node that executed (in our case, nodeEnd).
  // 'Value' is the final Output of that last node.
  TThread.Synchronize(nil,
    procedure
    begin
      ShowMessage('The graph has finished. Final result: ' + Value);
      btnRun.Enabled := True; // We reactivate the button
    end);
end;

Important: Note the use of TThread.Synchronize. Agent events execute in a secondary thread. Any interaction with the user interface (UI) must be done inside TThread.Synchronize to avoid concurrent access errors.

Step 4: Execute!
The only thing left is to call the Run method of the agent from our button.
Double-click btnRun in the form designer.
Write the following code in the OnClick event:

procedure TForm1.btnRunClick(Sender: TObject);
begin
  memoLog.Clear;
  btnRun.Enabled := False; // We disable the button while executing.
  AgentManager.Run(editInput.Text);
end;

Let us Test It!
Run your application (F9).
Type "World" in the TEdit.
Click the "Execute" button.
What you will see:
The button will deactivate.
In TMemo, logs will appear almost instantly:

[TAIAgentsNode] Start Node: Received input "World"
[TAIAgentsNode] Start Node: Generated output "Hello, World"

A ShowMessage will appear with the text: "The graph has finished. Final result: Hello, World".
The "Execute" button will reactivate.
Congratulations! You have just built and executed your first AI Graph. You have learned to:
Configure the orchestrator and define the graph flow.
Implement the logic of a node.
Handle log and completion events.
Execute the graph asynchronously.
Although this example is simple, the principles you have applied are the foundation for building incredibly complex agents and workflows.

Module 4: Making Decisions - Conditional Routing
In the real world, processes are rarely linear. Often, we need to take one path or another based on certain information. In this module, we will build a graph that simulates sentiment analysis of a text. If the text is considered "positive", it will follow one route; if it is "negative", it will follow another.
Objective:
Create a graph that receives a text. A central node will "analyze" whether the text contains the word "good" (simulating a positive analysis) or "bad" (simulating a negative one). Depending on the result, the flow will go to a positive response node or a negative response node.
Components we will use:
1 x TAIAgents (we can reuse the one from the previous module)
4 x TAIAgentsNode
3 x TAIAgentsLink

Step 1: Graph Design on the Form
We will modify the form from the previous module or create a new one.
Place and rename the components:
AgentManager (TAIAgents)
nodeStart (TAIAgentsNode)
nodeAnalyze (TAIAgentsNode): This will be our decision node.
nodePositiveResponse (TAIAgentsNode): Will execute if sentiment is positive.
nodeNegativeResponse (TAIAgentsNode): Will execute if sentiment is negative.
nodeEnd (TAIAgentsNode): Will be the common endpoint.

Configure the Orchestrator (AgentManager):
StartNode: nodeStart
EndNode: nodeEnd
Graph Wiring (the crucial part):
This graph has a fork, so pay attention to the connections.
From nodeStart to nodeAnalyze:
Create a link linkStartToAnalyze.
nodeStart.Next -> linkStartToAnalyze
linkStartToAnalyze.NextA -> nodeAnalyze
The fork from nodeAnalyze:
This is the most important step. nodeAnalyze will have a single output link, but this link will be conditional.
Create a link and call it linkConditionalRouter.
nodeAnalyze.Next -> linkConditionalRouter
Do NOT configure NextA on linkConditionalRouter! We will do it by code to define conditional routes.
From branches to nodeEnd:
Create a link linkPositiveToEnd.
nodePositiveResponse.Next -> linkPositiveToEnd
linkPositiveToEnd.NextA -> nodeEnd
Create a link linkNegativeToEnd.
nodeNegativeResponse.Next -> linkNegativeToEnd
linkNegativeToEnd.NextA -> nodeEnd
Visually, your flow will look like this:




Step 2: Implementing Decision Logic
The magic of conditional routing resides in two parts:
A node writes a "decision" to the Blackboard.
A subsequent link reads that decision and routes the flow based on it.
Logic of nodeStart:
This node will simply pass the input. Double-click its OnExecute event.
procedure TForm1.nodeStartExecute(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: String; var Output: String);
begin
  Node.Print('Step 1: Starting analysis with text: ' + Input);
  // We simply pass the input to the next node
  Output := Input;
end;

Logic of nodeAnalyze (The Brain):
This is the node that makes the decision.

procedure TForm1.nodeAnalyzeExecute(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: String; var Output: String);
var
  Decision: string;
begin
  // We simulate sentiment analysis
  if Pos('good', Input.ToLower) > 0 then
    Decision := 'positive'
  else if Pos('bad', Input.ToLower) > 0 then
    Decision := 'negative'
  else
    Decision := 'neutral'; // A default route

  Node.Print('Step 2: Analysis completed. Decision: ' + Decision);

  // Here is the key! We write the decision to the Blackboard.
  // The conditional link will use this key to route.
  Node.Graph.Blackboard.SetString('next_route', Decision);

  // We pass the decision as output so the following nodes can use it.
  Output := 'The detected sentiment was: ' + Decision;
end;

Node.Graph.Blackboard: This is how we access the Blackboard from a node.
'next_route': This is the key name the system uses by default for conditional routing.
Logic of Response Nodes:
These nodes simply generate a final message based on the route taken.
procedure TForm1.nodePositiveResponseExecute(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: String; var Output: String);
begin
  Node.Print('Positive Route: Generating optimistic response.');
  Output := 'Thank you for your positive feedback!';
end;

procedure TForm1.nodeNegativeResponseExecute(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: String; var Output: String);
begin
  Node.Print('Negative Route: Generating apology response.');
  Output := 'We are sorry your experience was not good.';
end;

Step 3: Configuring the Conditional Link by Code
The Delphi designer is great for simple connections, but conditional routes are more easily defined by code, usually in the form's OnCreate event.
Go to the OnCreate event of your form.
Add the following code to "teach" linkConditionalRouter its possible destinations:

procedure TForm1.FormCreate(Sender: TObject);
begin
  // We add routes to the conditional link
  linkConditionalRouter.AddConditionalTarget('positive', nodePositiveResponse);
  linkConditionalRouter.AddConditionalTarget('negative', nodeNegativeResponse);

  // Optional: What happens if the decision is neither 'positive' nor 'negative'?
  // We can define a default destination. In this case, if it is 'neutral' or
  // anything else, it will go directly to the end.
  linkConditionalRouter.NextNo := nodeEnd;
end;

AddConditionalTarget(Key, Node): This method tells the link: "When the 'next_route' key of the Blackboard contains the value Key, direct the flow to the specified Node".
NextNo: If the value in the Blackboard does not match any of the conditional keys, the flow will take this alternative route. If we do not define it and there is no match, the graph will stop with an error.

Step 4: Let us Test It!
Use the same UI from the previous module (TEdit, TButton, TMemo) and the same code for OnPrint, OnEnd, and OnClick events of the button.
Test 1: Positive Sentiment
Type in TEdit: "The service was very good".
Click "Execute".
Expected log:

[TAIAgentsNode] Step 1: Starting analysis...
[TAIAgentsNode] Step 2: Analysis completed. Decision: positive
[TAIAgentsNode] Positive Route: Generating optimistic response.

Final message: "The graph has finished. Final result: Thank you for your positive feedback!"
Test 2: Negative Sentiment
Type in TEdit: "What a bad time I had".
Click "Execute".
Expected log:

[TAIAgentsNode] Step 1: Starting analysis...
[TAIAgentsNode] Step 2: Analysis completed. Decision: negative
[TAIAgentsNode] Negative Route: Generating apology response.

Final message: "The graph has finished. Final result: We are sorry your experience was not good."
Test 3: Neutral Sentiment
Type in TEdit: "The day is cloudy".
Click "Execute".
Expected log:

[TAIAgentsNode] Step 1: Starting analysis...
[TAIAgentsNode] Step 2: Analysis completed. Decision: neutral

Final message: "The graph has finished. Final result: The detected sentiment was: neutral". (The flow went directly to nodeEnd through the NextNo route).
You have just built a graph that reacts dynamically to its input data. This pattern is the basis for creating agents that can choose which tool to use, decide if they need more information from the user, or handle different types of requests intelligently.

Module 5: Divide and Conquer - Parallel Execution (Fan-out)
Often, a problem requires performing several independent tasks that do not depend on each other. For example, to create a comprehensive report on a topic, we might want to generate a summary, extract keywords, and translate it to another language. Executing these tasks one after another would be inefficient.

MakerAI Agents greatly simplifies parallel task execution (known as "Fan-out"). In this module, we will build a graph that takes a topic and launches three "workers" simultaneously to process it in different ways.

Objective:
Create a graph that receives an input topic (e.g., "Artificial Intelligence"). A link will split the flow so that three nodes execute at the same time:
A node that simulates creating a summary.
A node that simulates keyword extraction.
A node that simulates text translation.
Important: In this module we will focus only on the "split" part (Fan-out). In the next module, we will see how to "join" the results (Join).
Components we will use:
1 x TAIAgents
5 x TAIAgentsNode
4 x TAIAgentsLink

Step 1: Parallel Graph Design
Place and rename the components:
AgentManager (TAIAgents)
nodeStart (TAIAgentsNode): Receives the topic.
nodeSummarize (TAIAgentsNode): Summary task.
nodeKeywords (TAIAgentsNode): Keyword task.
nodeTranslate (TAIAgentsNode): Translation task.
nodeEnd (TAIAgentsNode): Our endpoint.
Configure the Orchestrator (AgentManager):
StartNode: nodeStart
EndNode: nodeEnd
Graph Wiring (Fan-out):
From nodeStart to the "splitter" link:
Create a link linkFanOut.
nodeStart.Next -> linkFanOut
The Magic of Fan-out! Connect linkFanOut to the three worker nodes:
Select linkFanOut.
NextA -> nodeSummarize
NextB -> nodeKeywords
NextC -> nodeTranslate
Connect each branch to the end:
To simplify, for now we will make each branch end independently (although they do not join, the graph will continue waiting for all to finish).
Create linkSummarizeToEnd, linkKeywordsToEnd, linkTranslateToEnd.
nodeSummarize.Next -> linkSummarizeToEnd -> linkSummarizeToEnd.NextA -> nodeEnd
nodeKeywords.Next -> linkKeywordsToEnd -> linkKeywordsToEnd.NextA -> nodeEnd
nodeTranslate.Next -> linkTranslateToEnd -> linkTranslateToEnd.NextA -> nodeEnd

The flow will look like this:




Note: The nodeEnd in this design is a bit conceptual. As it has multiple inputs, it will execute as soon as the first branch arrives (due to its default JoinMode jmAny). The real power of this pattern will be revealed in the next module when we introduce a join node (Join) before the end.

Step 2: Implementing Parallel Logic
To demonstrate that nodes execute in parallel, we will introduce an artificial delay (Sleep) in each one. If the flow were sequential, the total time would be the sum of all delays. In a parallel flow, the total time will be approximately that of the longest delay.
Logic of nodeStart:
Simply passes the topic to linkFanOut.

procedure TForm1.nodeStartExecute(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: String; var Output: String);
begin
  Node.Print('Starting topic processing: ' + Input);
  Output := Input;
end;

Logic of Worker Nodes:
Each node will perform its "task", simulate work with a Sleep, and save its result to the Blackboard.

procedure TForm1.nodeSummarizeExecute(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: String; var Output: String);
begin
  Node.Print('>> [Thread ' + TThread.Current.ThreadID.ToString + '] Starting summary...');
  Sleep(2000); // Simulates 2 seconds of work
  Output := 'This is a summary about ' + Input + '.';
  Node.Graph.Blackboard.SetString('summary_result', Output);
  Node.Print('<< [Thread ' + TThread.Current.ThreadID.ToString + '] Summary finished.');
end;

procedure TForm1.nodeKeywordsExecute(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: String; var Output: String);
begin
  Node.Print('>> [Thread ' + TThread.Current.ThreadID.ToString + '] Starting keyword extraction...');
  Sleep(3000); // Simulates 3 seconds of work
  Output := 'AI, Delphi, Parallel';
  Node.Graph.Blackboard.SetString('keywords_result', Output);
  Node.Print('<< [Thread ' + TThread.Current.ThreadID.ToString + '] Keywords finished.');
end;

procedure TForm1.nodeTranslateExecute(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: String; var Output: String);
begin
  Node.Print('>> [Thread ' + TThread.Current.ThreadID.ToString + '] Starting translation...');
  Sleep(1500); // Simulates 1.5 seconds of work
  Output := 'This is a text about ' + Input + '.';
  Node.Graph.Blackboard.SetString('translate_result', Output);
  Node.Print('<< [Thread ' + TThread.Current.ThreadID.ToString + '] Translation finished.');
end;

We have added the ThreadID to the log. If parallelism works, you should see different IDs for each node (or at least, not always the same as the main thread).

Step 3: Let us Test It!

Use the same UI and the same OnPrint, OnEnd, and OnClick events from previous modules.
Type in TEdit: "AI and Delphi".
Click "Execute" and observe the memoLog carefully.
Expected Log:
Most likely you will see the "Starting..." messages appear almost all at once. Then, the "finished" messages will appear in the order their Sleep ends, not in the order they are defined (Translation -> Summary -> Keywords).

[TAIAgentsNode] Starting topic processing: AI and Delphi
[TAIAgentsNode] >> [Thread 1234] Starting summary...
[TAIAgentsNode] >> [Thread 5678] Starting keyword extraction...
[TAIAgentsNode] >> [Thread 9012] Starting translation...
// ... 1.5 seconds later ...
[TAIAgentsNode] << [Thread 9012] Translation finished.
// ... 0.5 seconds later (2s total) ...
[TAIAgentsNode] << [Thread 1234] Summary finished.
// ... 1 second later (3s total) ...
[TAIAgentsNode] << [Thread 5678] Keywords finished.

Key Observations:
Execution Time: The total execution time of the graph will be approximately 3 seconds (the duration of the longest task), not 6.5 seconds (2 + 3 + 1.5). This demonstrates the gained efficiency.
Thread IDs: You will notice that thread IDs are different, confirming that TAIAgents has used the TTask thread pool to execute branches in parallel.
OnEnd: The OnEnd event will fire as soon as the first branch (translation) reaches nodeEnd. The main graph, however, will internally wait for all launched tasks to finish before considering itself completely finished.

You have successfully implemented a Fan-out pattern, an essential technique for optimizing AI workflows involving multiple independent tasks.


Module 6: Putting the Pieces Together - Branch Synchronization (Join)
This module is the natural counterpart of the previous one. After having divided our flow into multiple parallel branches (Fan-out), we will now learn to synchronize them at a single junction point (Join). This allows us to ensure that all parallel tasks have finished before proceeding with the next step, such as compiling a final report.
Objective:
We will modify the graph from Module 5. Instead of each branch going directly to the end node, we will make them converge on a new "join node". This node will be configured to wait for all three tasks (summary, keywords, translation) to finish. Once they have all completed, it will execute to compile a final report from the results stored in the Blackboard.
Key Concept: JoinMode = jmAll
The magic of synchronization resides in the JoinMode property of TAIAgentsNode.
jmAny (default): The node executes as soon as the first input signal arrives.
jmAll: The node counts how many input routes it has. Then, it waits patiently until it has received a signal from each of those routes before executing once.
Components we will use:
We will reuse most of the graph from Module 5, but with an additional node and re-wiring.
1 x TAIAgents
6 x TAIAgentsNode
5 x TAIAgentsLink (we need fewer links because we no longer go directly to the end from each branch)

Step 1: Redesigning the Graph for Join
Add the Join Node:
Starting from the Module 5 design, add a new TAIAgentsNode to the form.
Rename it to nodeReport.
Configure JoinMode:
Select nodeReport.
In the Object Inspector, find the JoinMode property and change it from jmAny to jmAll. This is the most important step!
Re-wiring the Graph:
We will redirect the output of the three worker nodes (nodeSummarize, nodeKeywords, nodeTranslate) to point to the new nodeReport.
Disconnect from nodeEnd: Remove the links linkSummarizeToEnd, linkKeywordsToEnd, and linkTranslateToEnd. Or, easier, simply change their properties.
Create the new links to nodeReport:
Create a link linkSummarizeToReport.
nodeSummarize.Next -> linkSummarizeToReport
linkSummarizeToReport.NextA -> nodeReport
Create a link linkKeywordsToReport.
nodeKeywords.Next -> linkKeywordsToReport
linkKeywordsToReport.NextA -> nodeReport
Create a link linkTranslateToReport.
nodeTranslate.Next -> linkTranslateToReport
linkTranslateToReport.NextA -> nodeReport
Connect the Join Node to the End:
Create a link linkReportToEnd.
nodeReport.Next -> linkReportToEnd
linkReportToEnd.NextA -> nodeEnd
The new flow will look like this:


Step 2: Implementing Join Logic
The logic of the worker nodes (nodeSummarize, etc.) from the previous module is already perfect, as they save their results to the Blackboard. Now we only need to implement the logic of nodeReport to read those results and combine them.
Logic of nodeReport:
Select nodeReport and double-click its OnExecute event.
Write the following code:

procedure TForm1.nodeReportExecute(Node, BeforeNode: TAIAgentsNode;
  Link: TAIAgentsLink; Input: String; var Output: String);
var
  ReportBuilder: TStringBuilder;
  Summary, Keywords, Translation: string;
begin
  Node.Print('>>> All branches have finished! Compiling final report...');

  // We read the results that previous nodes left in the Blackboard.
  Summary := Node.Graph.Blackboard.GetString('summary_result', '[Summary not available]');
  Keywords := Node.Graph.Blackboard.GetString('keywords_result', '[Keywords not available]');
  Translation := Node.Graph.Blackboard.GetString('translate_result', '[Translation not available]');

  // We build the final report.
  ReportBuilder := TStringBuilder.Create;
  try
    ReportBuilder.AppendLine('--- COMPLETE REPORT ---');
    ReportBuilder.AppendLine('');
    ReportBuilder.AppendLine('Summary:');
    ReportBuilder.AppendLine(Summary);
    ReportBuilder.AppendLine('');
    ReportBuilder.AppendLine('Keywords:');
    ReportBuilder.AppendLine(Keywords);
    ReportBuilder.AppendLine('');
    ReportBuilder.AppendLine('Translation (English):');
    ReportBuilder.AppendLine(Translation);
    ReportBuilder.AppendLine('------------------------');

    // We assign the complete report as the final output of the graph.
    Output := ReportBuilder.ToString;
  finally
    ReportBuilder.Free;
  end;

  Node.Print('<<< Final report compiled.');
end;

Step 3: Let us Test It!

