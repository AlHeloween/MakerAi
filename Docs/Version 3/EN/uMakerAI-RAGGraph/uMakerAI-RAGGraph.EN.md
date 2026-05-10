

MakerAI Graph-RAG Manual: General Index
Part I: Fundamentals and Concepts
This section establishes the theoretical basis and purpose of the system.
Chapter 1: Introduction and Contextualization
1.1. The Evolution of RAG: From Vector to Graph.
1.2. The problem of "flat" Vector RAG (lack of relational context).
1.3. The Hybrid solution: Why MakerAI is a complement, not a replacement.
1.4. Comparative table: Vector vs. Graph vs. Hybrid.
Chapter 2: Operations and Analysis in Knowledge Graphs
2.1. Beyond connecting dots: The value of structural analysis.
2.2. Key Topological Concepts:
Degree (In/Out): Influence and Popularity.
Islands and Components: Information silos.
Paths: Traceability and causality.
2.3. Advanced Analysis Algorithms:
Closeness Centrality: The neural center.
Betweenness: Bridges and bottlenecks.
Community Detection (Louvain): Thematic clusters.
2.4. MakerAI Capabilities Matrix: What the component implements today (✅) and what is future (❌).
Chapter 3: MakerAI Component Architecture
3.1. The orchestrator: TAiRagGraph.
3.2. Intelligent anatomy: Nodes (TAiRagGraphNode) and Edges (TAiRagGraphEdge).
3.3. Memory integrity: The "Identity Map" pattern.
3.4. The power of dual Embeddings: Vector Search + Structural Navigation.
Part II: Construction and Query (The Magic in Action)
How to create the graph and extract value from it.
Chapter 4: AI Data Ingestion
4.1. From Text to Graph: The role of LLM and Prompt Engineering.
4.2. The TAiRagGraphBuilder component.
4.3. Fusion Strategies: How to handle evolving data.
Chapter 5: Querying Knowledge
5.1. Search: Vector Search (the anchor).
5.2. Match: Pattern Search (Cypher style).
5.3. Query: The Hybrid Planner (TQueryPlan).
Chapter 6: Practical In-Memory Tutorial
6.1. Creating a graph from scratch (step-by-step code).
6.2. Visualization: Exporting to GraphML/Gephi.
Part III: Scalability and Production
Taking the system to the real world with databases.
Chapter 7: Driver System and Persistence
7.1. Abstraction: TAiRagGraphDriverBase.
7.2. Postgres as Graph + Vector engine (pgvector).
7.3. Optimization: Recursive CTEs and SQL delegation.
Chapter 8: Best Practices and Optimization

Now we have a solid narrative structure:
Why (Cap 1)
What (Cap 2)
How (Architecture) (Cap 3)
How (Use) (Part II)
Scaling (Part III)


MakerAI Graph-RAG Manual
Chapter 1: Contextualization and Fundamentals
1.1. Introduction: The Evolution of RAG
Retrieval-Augmented Generation (RAG) has become the standard for equipping Language Models (LLMs) with long-term memory and private knowledge. Until now, the dominant implementation has been Vector-RAG.
Vector RAG works by fragmenting documents into chunks, converting them into numerical vectors (embeddings), and retrieving the ones most similar to the user's question. While revolutionary, it has a critical blind spot: it treats information as isolated islands.
MakerAI Graph-RAG is born to cover that blind spot. It is a set of components for Delphi that allows building, managing, and querying Knowledge Graphs enriched with AI, allowing your applications to "reason" about the relationships between data, not just about their textual similarity.
1.2. The Problem of "Flat" Vector RAG
To understand why you need Graphs, we must first understand where traditional RAG fails:
Loss of Relational Context: When dividing a document into chunks, connections are broken. If chunk A mentions "Juan" and chunk B (ten pages later) mentions that "The Director approved the budget", vector RAG will hardly know that Juan is the Director if they are not in the same fragment.
Inability for "Multi-hop" (Multi-hop Reasoning): If you ask "Who is the boss of the creator of Project X?", a vector RAG will search for documents about "Project X". But the answer requires connecting: Project X -> Creator -> Boss. Vector RAG fails here because the answer is not explicitly written in a single paragraph.
Difficulty with Global Questions: Questions like "What are the recurring themes in all 2023 contracts?" are difficult for a vector system, since it is designed to search for needles in a haystack (specific data), not to understand the structure of the entire haystack.
1.3. The Solution: Graph-RAG
MakerAI Graph-RAG introduces structure where before there was only text. It transforms your unstructured data into a network of Nodes (entities) and Edges (relationships).
When using this component, your system stops seeing data as a flat list of texts and starts seeing them as an interconnected map. This allows:
Structural Retrieval: Finding information by following relationships (e.g., searching for all nodes connected by the WORKS_IN relationship).
Persistence of Logic: Logical relationships (cause-effect, hierarchy, belonging) are "engraved" in the database and do not depend on the LLM's context window.
1.4. Why is it a Complement and not a Replacement?
It is vital to understand that MakerAI Graph-RAG does not come to eliminate your vector database; it comes to enhance it. We are talking about a Hybrid architecture.
Purely graph-based systems (like old SPARQL queries or pure Cypher) are rigid: they require knowing exactly what nodes are called to find them. This is where AI and vectors are still kings.
MakerAI Synergy (The Hybrid approach):
The component implements the best of both worlds through a two-step process:
The Anchor (Vector Work): We use vector search to find the entry point.
User: "Search for problems in the technology department".
Vector: Finds the semantically closest node, perhaps called "Systems Management" (even if it does not explicitly say "technology").
The Journey (Graph Work): Once anchored in "Systems Management", we use the graph to explore.
Graph: Expands the HAS_INCIDENCE or REPORTS_TO relationships to find the real problems, even if they do not have words similar to the original question.
1.5. Comparative Table: Vector vs. Graph vs. MakerAI Hybrid
 
MakerAI Graph-RAG Manual
Chapter 2: Operations and Analysis in Knowledge Graphs
Storing data in a graph is not just for visualizing them attractively. The real power lies in the ability to perform mathematical analyses on the structure of information.
While a vector database tells you "what resembles what", a graph allows you to answer questions about "how information flows", "who is important", and "where the gaps are". This chapter explores the theoretical concepts that turn simple data storage into a reasoning engine.
2.1. Beyond connecting dots: The value of structural analysis
Imagine you have a corporate email database.
Vector Approach: You can search for emails that talk about "2024 Budgets".
Graph Approach: You can identify who is the person connecting the Finance department with Engineering, even if that person never uses the word "Budget" in their emails.
Structural analysis assumes that the position of data in the network is as important as the data itself.
In the context of a RAG (Retrieval-Augmented Generation) system, understanding the structure allows:
Prioritize Context: If the LLM retrieves 50 possible nodes, which ones do we send to the prompt? Structural analysis tells us which are the "central" or "authority" nodes to prioritize them.
Detect Silos: Identify areas of knowledge that are not connected with the rest of the company.
Explainability: Not just give an answer, but trace the logical path of how it was reached (A caused B, which affected C).
2.2. Key Topological Concepts
To operate a graph, we must familiarize ourselves with network topology. Below, we describe the most important concepts and their practical application in MakerAI.
A. Degree: Popularity and Influence
"Degree" is the simplest metric and at the same time one of the most powerful. It measures the number of direct connections a node has. A node with high degree is a Hub.
There are three variants that tell us different stories:
In-Degree:
Definition: Number of arrows pointing to the node.
Interpretation: Represents Prestige, Authority, or Dependence.
RAG Example: In a law graph, the Constitution would have a very high In-Degree because many laws cite it. If you search for legal information, nodes with high In-Degree are the "parent" documents you should not ignore.
Out-Degree:
Definition: Number of arrows born from the node.
Interpretation: Represents Influence, Generosity, or Dispersion.
RAG Example: A user who sends emails to many different people. Or an index document that summarizes many other topics.
Total Degree: The sum of both. Indicates general activity in the network.
In MakerAI: These operations are computationally cheap and very fast. They serve as an excellent first filter to find the most relevant entities of a domain.
B. Islands (Connected Components)
An "Island" (technically, a Connected Component) is a subset of nodes that are connected to each other, but have no path to reach the rest of the main graph.
What does an Island mean in your data?
Information Silos: If you load HR manuals and IT manuals, and there is no link between them, you will have two islands.
Orphan Data: A node with Degree 0 is an island of one inhabitant. It is data that exists but has no context.
Impact on RAG:
If the LLM tries to reason or navigate from a concept in Island A to a concept in Island B, it will fail because there is no logical bridge. Detecting islands helps you know where integrative information is missing in your knowledge base.
C. Paths and Distance
A path is the sequence of edges you must traverse to travel from Node A to Node B.
Path length: Measured in "hops".
Shortest Path: The most efficient route between two points.
Practical Application:
Imagine you ask: "What relationship does Supplier X have with Manager Y?".
There may be no direct relationship. Path analysis reveals:
Supplier X --(signed)--> Contract 123 --(approved by)--> Manager Y.
This ability to "connect the dots" through intermediaries is the definitive advantage over vector search, which would only see two separate entities.


2.3. Advanced Analysis Algorithms
Beyond counting simple connections, there are algorithms that analyze the network globally to discover hidden roles and emerging structures.
A. Closeness Centrality
This algorithm answers the question: "Who can access everyone else in the fastest way?".
It measures the average distance from a node to all other nodes in the network.
Interpretation: Identifies the neural center or the best diffusion point.
RAG Example:
In an employee network, the person with the highest closeness is not necessarily the boss (who may be isolated at the top), but perhaps a secretary or project manager who interacts with many departments.
If the RAG system needs to diffuse an alert or find a node from which to explore the entire graph with the lowest cost, it will choose the one with the highest closeness.
B. Betweenness Centrality
This algorithm answers: "Who controls the flow of information?".
It measures how many times a node acts as a "bridge" on the shortest path between any other two nodes.
Interpretation: Identifies bottlenecks and critical vulnerability points.
RAG Example:
Imagine a knowledge graph where the "Sales" theme and the "Engineering" theme are two large dense groups, connected only by a node called "Product Manager".
That "Product Manager" will have very high Betweenness. If you eliminate that node, the graph splits into two unconnected islands.
For RAG, these nodes are vital for cross-domain reasoning.
C. Community Detection (Louvain Algorithm)
This is one of the most powerful concepts in graph AI. Community algorithms do not look for individual nodes, but groups.
They look for sets of nodes that are densely connected to each other, but poorly connected to the outside.
Interpretation: Identifies natural themes, clusters, or departments without anyone explicitly labeling them.
RAG Example (Thematic Summary):
When ingesting thousands of news items, the Louvain algorithm could automatically group all news about "Football", "Tennis", and "Basketball" into one community (Sports), and those about "Stock Market" and "Inflation" into another (Economy).
This allows the RAG system to answer high-level questions like: "Summarize the main topics discussed in yesterday's documents", simply by listing the detected communities.

2.4. MakerAI Capabilities Matrix
As of today, the TAiRagGraph component is designed to be lightweight and efficient, implementing the most critical operations for information retrieval (Retrieval), leaving heavy statistical analyses for future versions or for external tools (like Gephi).
Below, the operations available natively in the current code are detailed:
Note: Although MakerAI does not calculate Betweenness or Louvain internally yet, its ability to export to standard formats (GraphML, DOT) allows you to load your graph into tools like Gephi or Neo4j to perform these advanced analyses and then reimport the results as node properties.




MakerAI Graph-RAG Manual
Chapter 3: MakerAI Component Architecture
Now that we understand the theory and potential of graphs, it is time to lift the hood and see how MakerAI implements these concepts in Delphi. This chapter dissects the internal structure of the library, explaining the main classes, how they manage memory, and how they integrate Artificial Intelligence.
The architecture has been designed following principles of decoupling and efficiency, separating graph logic (memory), persistence (database), and vector intelligence (embeddings).
3.1. The Orchestrator: TAiRagGraph
The root component of the entire system is TAiRagGraph.
This component is not a simple list of objects; it acts as an embedded DBMS (Database Management System) in memory.
Its critical responsibilities are:
Lifecycle Management: It is the "owner" of all nodes and edges. When the graph is freed, it takes care of cleaning all associated memory.
Fast Access Indices: To guarantee optimal performance, it maintains internal dictionaries that allow:
Search by ID in constant time O(1).
Search by Label instantly.
Search by Name quickly.
Vector Coordination: It contains two instances of TAiRAGVector (one for nodes, one for edges). This is what allows performing semantic searches ("find me something like...") on the graph structure.
Interface with Drivers: It defines how the graph "talks" to the outside world (databases like Postgres) through the Driver property.
In your code:
RAG := TAiRagGraph.Create(Self);
RAG.Embeddings := AiOpenAiEmbeddings1; // Connects the brain (AI)
RAG.Driver := RAGPgDriver;             // Connects storage (DB)

3.2. Intelligent Anatomy: Nodes and Edges
MakerAI elevates traditional graph concepts by enriching them with AI capabilities.
A. The Node (TAiRagGraphNode)
The node represents an Entity (a noun in a sentence).
It inherits from TAiEmbeddingNode, which gives it a unique duality: it is a structured object and, at the same time, a mathematical vector.
Internal structure:
ID (string): Universal unique identifier (generally a UUID).
NodeLabel (string): The category or type (e.g., 'CUSTOMER', 'PRODUCT').
Name (string): The human-readable name.
Properties (TDictionary<string, Variant>): A flexible NoSQL-type store to save any extra data (dates, numbers, strings).
Data (TAiEmbeddingData): The vector of numbers (embedding) that represents the semantic meaning of the node.
Adjacency Lists: Each node knows its connections. It maintains two internal lists:
OutgoingEdges: Relationships born here.
IncomingEdges: Relationships arriving here.

B. The Edge (TAiRagGraphEdge)
The edge represents a Relationship (a verb in a sentence).
Unlike many simple graph libraries, in MakerAI edges are first-class citizens.
Distinctive features:
Vector Semantics: Like nodes, edges have Embeddings.
Why is this revolutionary? It allows searching relationships by their "intention". You can search for causality relationships and the system will find edges labeled as CAUSE, PROVOKES, GENERATES, or DERIVES_IN, because semantically they are similar, without needing to program a giant OR.
Directionality: Always goes from a FromNode to a ToNode.
Weight: A Double value indicating connection strength. By default it is 1.0, but can be used to represent:
Interaction frequency (how many emails were sent).
Confidence in the relationship (probability of certainty).
Physical distance.

3.3. Memory Integrity: The "Identity Map" Pattern
When working with complex graphs, one of the most common and dangerous errors is object duplication.
Imagine this scenario:
You load an invoice referencing customer "Juan Perez".
Later, you load a support ticket from the same customer "Juan Perez".
If your system creates two different TNode objects for "Juan Perez", you have just broken the graph. The invoice connections will go to one object and the ticket ones to another. Structural analysis will fail because it will seem like they are two different people.
The MakerAI Solution:
TAiRagGraph strictly implements the Identity Map pattern.
Centralized Registry: It maintains an internal dictionary FNodeRegistry (key=ID, value=Object).
Intelligent Hydration: Every time you try to load a node (whether manually with AddNode or from the database with FindNodeByID), the system intercepts the request:
Verifies if the ID already exists in FNodeRegistry.
If it exists: Returns the pointer to the object already in memory. Ignores or merges new data, but never creates a second object.
If it does not exist: Creates the object, registers it, and returns it.
This guarantees Referential Uniqueness: No matter how many times you mention a node, in memory there will always be only one instance of it, correctly accumulating all its connections.
3.4. The Power of Dual Embeddings: Vector Search + Structural Navigation
MakerAI architecture does not choose between Vectors or Graphs; it fuses them. This is the basis of Hybrid RAG.
To understand the power of this architecture, let us analyze how it solves a complex question:
User Question: "What technological risks affect the Finance Department?"
Phase 1: The Vector (The Anchor)
The system first uses the AI engine (TAiEmbeddingsCore) to convert the question into numbers.
Searches in the vector index of Nodes.
Perhaps there is no node called "Finance Department", but the vector finds one called "Administrative Management" because semantically they are very similar.
Result: We have found the entry point (the Anchor) without needing an exact text match.

Phase 2: The Graph (Navigation)
Once we have the TAiRagGraphNode object of "Administrative Management", the system switches mode. It leaves vector mathematics and uses the graph's pointer structure.
Explores outgoing edges (OutgoingEdges).
Filters relationships that semantically resemble "Risk" or "Affectation" (using the edge embedding or relationship type).
Finds connected nodes like: Legacy Server --(relationship: CRITICAL_FOR)--> Administrative Management.

The Final Result
The system returns: "The Legacy Server represents a risk".
Observe the magic:
The text "Finance Department" never existed in the data.
The word "Risk" perhaps was not in the relationship (which said "CRITICAL_FOR").
However, the system connected both worlds.
This ability to Anchor with Vectors and Navigate with Pointers is what makes MakerAI architecture much more robust than traditional RAG, allowing "multi-hop reasoning" transparently for the developer.

Part II: Construction and Query (The Magic in Action)
In this part of the manual, we will stop talking about the engine's internal structure to focus on how to use it. You will learn to transform disordered documents into an elegant graph and, subsequently, interrogate that graph to obtain intelligent responses.

4.1. Manual Insertion of Relationships
Although the ultimate goal is to use AI, there will be times when you need to create explicit connections by code: fixed business rules, master hierarchies, or specific corrections. MakerAI offers a fluent API for this. Very useful for performing a dump (ETL) between a relational database and a knowledge graph.
Step 1: Create Nodes
First, we define entities. Remember that each node needs a unique ID, a Label (category), and a Name.
var
  NodeElon, NodeSpaceX: TAiRagGraphNode;
begin
  // AddNode(ID, Label, Name)
  NodeElon := RAG.AddNode('id_elon', 'PERSON', 'Elon Musk');
  
  // We can enrich the node with extra properties
  NodeElon.Properties.Add('age', 52);
  NodeElon.Properties.Add('nationality', 'South African');

  NodeSpaceX := RAG.AddNode('id_spacex', 'COMPANY', 'SpaceX');
end;


Step 2: Create the Relationship (Edge)
Once nodes exist, we connect them. Direction matters: the relationship is born in the first and arrives at the second.

var
  Edge: TAiRagGraphEdge;
begin
  // AddEdge(Origin, Destination, Edge_ID, Label, Relationship_Name)
  Edge := RAG.AddEdge(NodeElon, NodeSpaceX, 'id_rel_01', 'FOUNDED', 'founded the company');
  
  // Edges can also have data
  Edge.Properties.Add('year', 2002);
  Edge.Weight := 0.9; // High importance
end;

Step 3: Generate Vectors (Optional but Recommended)
If you create nodes manually and want them to be "searchable" by AI, you must explicitly generate their embeddings. If you do not, they will only be findable by exact name search.
// We connect descriptive text to the AI engine
NodeElon.Data := RAG.Embeddings.CreateEmbedding('Elon Musk, technological magnate and CEO of Tesla and SpaceX.');
This manual form gives you total control and is ideal for defining the "backbone" of your graph (e.g., your company's department structure) before letting AI fill in the details.

4.2. From Text to Graph: The Role of LLM and Prompt Engineering
Now that you know how to create a node and an edge manually, imagine having to do it for a 500-page manual. It would be impossible. This is where automation with AI comes in.
The ingestion challenge is not technical, but linguistic: How do we convert a paragraph of fluent and ambiguous text into the rigid structure (Node A -> Relationship -> Node B) we just saw?
The answer is to use a Large Language Model (LLM) as a "translator". We do not ask the LLM to summarize the text, but to act as a database extraction engine.
The Concept of "Semantic Triplet"
We teach AI to see the world in Triplets:
Subject (Node A) -> Predicate (Edge) -> Object (Node B)
For example, from the text "The iPhone was presented by Steve Jobs in 2007", we want to extract:
Subject: iPhone (Type: Product)
Predicate: PRESENTED_BY (Property: year 2007)
Object: Steve Jobs (Type: Person)
Prompt Engineering for Graphs
The success of your Graph-RAG depends on the quality of your Prompt. A mediocre prompt will generate a dirty graph. An excellent prompt will generate a crystalline knowledge base.
For MakerAI, the prompt must demand three critical things from the LLM:
Relationship Normalization:
You must instruct the model to use consistent verbs. If one text says "is employed by" and another "works at", the model should normalize both to WORKS_AT. This facilitates subsequent queries.
Contextualization (The text field):
This is the key to Hybrid RAG. It is not enough to extract {"name": "Apollo 11"}. We need AI to generate a brief semantic description: {"text": "NASA space mission that took man to the Moon in 1969"}.
Why? Because this text is what we will convert into a vector. Thanks to this, if a user searches for "moon landing", the system will find the "Apollo 11" node even if the name does not match.
Strict JSON Format:
The LLM must return exclusively a JSON array with the structure our TAiRagGraphBuilder component expects.
The Master Prompt:
In the demo project source code, you will find an optimized prompt designed specifically for this. It instructs the model to detect metadata, infer entity types, and generate rich descriptions for embeddings.

4.3. The TAiRagGraphBuilder Component
Once the LLM has returned a clean JSON with entities and relationships, we need to inject it into our graph. Doing this manually (parse JSON, check if node exists, create if not, etc.) is tedious and error-prone.
For that exists TAiRagGraphBuilder. It is a utility component designed to act as a bridge between raw JSON and the TAiRagGraph object structure.
Builder Responsibilities
Automatic Parsing: Reads the JSON triplet array.
Real-Time Vector Management:
Detects if the node brings a text field (the description generated by AI).
If it has it, automatically calls the Embeddings engine connected to generate the numerical vector.
Assigns that vector to the node. This means the node is born already being "intelligent" and searchable.
Creation Abstraction: You just pass it the JSON string, and it takes care of calling AddNode and AddEdge for you.
Basic Usage
codeDelphi
// Initial configuration
RAGBuilder1.Graph := RAG;                 // Where do I save the data?
RAGBuilder1.Embeddings := AiOpenAiEmbeddings1; // Who calculates vectors?

// Execution
JsonString := '... [{ "subject": {...}, "predicate": {...}, "object": {...} }] ...';
RAGBuilder1.Process(JsonString, msAddNewOnly);
4.4. Fusion Strategies: How to handle evolving data
One of the biggest problems in knowledge databases is what to do when you receive new information about something you already know.
Scenario:
Day 1: You load a document that says: "Juan Perez is Manager".
Day 2: You load another document that says: "Juan Perez is 45 years old".
You do not want to create two "Juan Perez". You want the existing node to evolve. MakerAI Builder handles this through the TMergeStrategy parameter.
The 3 Fusion Strategies (TMergeStrategy)
msAddNewOnly (Only Add New):
Behavior: If the node already exists, respects its current data. Only adds new properties if they did not exist before.
Ideal use: When you trust your old data more than new ones, or want to preserve the first version of truth.
In the example: The final node will have Position: Manager and Age: 45. If day 2 said Position: Director, it would be ignored and Manager would be maintained.
msOverwrite (Overwrite):
Behavior: New information commands. If a property already exists, it is updated with the new value.
Ideal use: When you are processing updates or more recent data that corrects previous ones.
In the example: If day 2 says Position: Director, the node updates to Director.
msKeepExisting (Keep Existing):
Behavior: Strict conservative. If the node already exists, nothing of its properties is touched, not even new ones are added. Only new relationships (edges) are created.
Ideal use: Massive loads where speed is priority and you do not want to spend time merging fine details.
Design Note: This fusion logic applies to both Nodes and Edges. This allows your graph to be a living entity that enriches with each document you process, instead of being a static photo.



MakerAI Graph-RAG Manual
Chapter 5: Querying Knowledge
You have built a rich, interconnected graph full of semantic vectors. Now comes the crucial moment: asking it questions.
In a traditional RAG system, your only tool is "Similarity Search". In MakerAI Graph-RAG, you have an arsenal of three complementary tools, designed to solve different types of questions:
Search (Semantic Search): "Find me things similar to this..."
Match (Structural Search): "Find me this specific connection pattern..."
Query (Hybrid Search): "Find something similar to this, and then tell me what it connects to..."
In this chapter we will master each one of them.
5.1. Search: Semantic Search (The Anchor)
This is the most basic and fundamental operation. It is identical to what you would do in a classic vector RAG, but applied to your graph nodes.
Its objective is to find the Entry Point (the anchor) within the immense sea of data.
How it works?
The user enters text in natural language (e.g., "liquidity problems").
The system converts that text into a numerical vector.
Compares that vector against vectors stored in all graph nodes.
Returns the mathematically closest nodes (cosine similarity).
When to use it?
When you do not know the exact name of what you are looking for.
When the question is vague or exploratory.
To initiate any complex reasoning process (it is step 1 of almost everything).

Example Code
var
  Results: TArray<TAiRagGraphNode>;
  Prompt: string;
begin
  Prompt := 'server security incidents';
  
  // Search(Prompt, Depth, Limit, MinimumPrecision)
  Results := RAG.Search(Prompt, 0, 5, 0.75);
  
  // 'Results' will contain nodes like "Main Firewall", "Access Log",
  // even if none has the word "incident" in its name, 
  // thanks to the semantic similarity of their descriptions.
end;

The "Depth" parameter (ADepth)
Observe the 0 parameter in the previous example. TAiRagGraph.Search has a hidden superpower: Context Expansion.
If ADepth = 0: Returns only found nodes (standard behavior).
If ADepth > 0: Finds nodes and also brings their neighbors.
If you find the "Server X" node, with ADepth=1 you will automatically bring "Server Admin" and "Installed Software".
This saves additional queries and gives the LLM immediate context about what surrounds the found concept.
Pro Tip: For a RAG Chatbot, it is usually a good idea to use ADepth=1. This gives AI not only the direct response, but the immediate context to respond in a more complete and nuanced way.

5.2. Match: Structural Search (Pattern Matching)
While Search is fuzzy and flexible ("find something similar"), Match is surgical and precise ("find exactly this shape").
This operation is inspired by Neo4j's Cypher language. It allows defining a Visual Pattern of nodes and relationships and asking the graph to find all sub-structures that fit that mold.
When to use it?
When you know the structure of the information you are looking for.
For specific business questions: "Which customers bought product X?"
To filter data based on exact properties: "Find me people over 30 who live in Madrid".
Anatomy of a Match Query
A Match query is built by chaining "Clauses". A typical clause looks like this:
(Person) -[WORKS_IN]-> (Company)
In MakerAI, this is modeled through objects:
TMatchNodePattern: Defines what to look for in a node (Label, Properties).
TMatchEdgePattern: Defines what to look for in the relationship (Label, Direction).
TMatchClause: Joins two nodes through an edge.
Practical Example
Suppose we want to answer: "Which employees work in the Sales Department?".

var
  Query: TGraphMatchQuery;
  PatronEmployee, PatronDepto: TMatchNodePattern;
  PatronRelation: TMatchEdgePattern;
  Results: TArray<TDictionary<string, TObject>>;
begin
  Query := TGraphMatchQuery.Create;
  try
    // 1. We define the origin node: Any node with label 'EMPLOYEE'
    PatronEmployee := TMatchNodePattern.Create;
    PatronEmployee.Variable := 'e'; // Alias to refer to it
    PatronEmployee.NodeLabel := 'EMPLOYEE';
    Query.AddNodePattern(PatronEmployee);

    // 2. We define the destination node: 'DEPARTMENT' node named 'Sales'
    PatronDepto := TMatchNodePattern.Create;
    PatronDepto.Variable := 'd';
    PatronDepto.NodeLabel := 'DEPARTMENT';
    PatronDepto.Properties.Add('name', 'Sales'); // Exact filter
    Query.AddNodePattern(PatronDepto);

    // 3. We define the relationship: Must be 'BELONGS_TO'
    PatronRelation := TMatchEdgePattern.Create;
    PatronRelation.EdgeLabel := 'BELONGS_TO';
    PatronRelation.Direction := gdOutgoing; // Employee -> Dept

    // 4. We join everything in a clause: (e)-[r]->(d)
    Query.AddMatchClause(TMatchClause.Create('e', PatronRelation, 'd'));

    // 5. We execute
    Results := RAG.Match(Query);
    
    // 'Results' will be a list of dictionaries. 
    // Each dictionary will have a key 'e' with the found employee node.
  finally
    Query.Free;
  end;
end;

Hidden Power: Subgraphs
Like Search, the Match method also accepts an ADepth parameter.
If you execute RAG.Match(Query, 1), you will not only get the employees, but the system will return the complete subgraph formed by those employees and their immediate connections. This is ideal for visualizing on screen "who is who" in the sales department.

5.3. Query: The Hybrid Planner (The Crown Jewel)
So far we have seen two extremes:
Search: Finds similar things (but ignores structure).
Match: Finds exact structures (but requires knowing exact names).
The Query function combines both worlds. It allows solving complex "multi-hop" questions starting from imprecise natural language.
The Problem:
User asks: "What risks affect billing systems?"
In normal RAG: It would search for texts saying "risk" and "billing".
Reality: Perhaps the node is called "ERP Server" (not "billing system") and the relationship is called "HAS_VULNERABILITY" (not "risk").
Conclusion: No traditional method would work well.
The Solution: TQueryPlan
MakerAI introduces the concept of Query Plan. Instead of executing a direct search, we ask the LLM to "think" the steps necessary to find the answer and give us a map.
A TQueryPlan has two phases:
Anchoring Phase (Semantic): "Find node X using vectors, no matter what it is called exactly".
Navigation Phase (Structural): "From there, move along relationship Y to find objective Z".
Plan Structure
The plan is defined through a JSON or Delphi record:
type
  TQueryPlan = record
    AnchorPrompt: string;       // Text to search the entry point (Vector)
    AnchorVariable: string;     // Temporary name for the anchor (e.g., 'initial_node')
    Steps: TArray<TQueryStep>;  // Steps to follow from the anchor
    ResultVariable: string;     // Which of the found nodes we return
  end;

Execution Example: "Risks in Billing"
1. The Plan (Generated by LLM):
The LLM receives the question and generates this logical plan:
Anchor: Search for something semantically similar to "Billing System".
(The system finds the node "Financial ERP Server v2" thanks to vectors).
Step 1: From the anchor, follow incoming relationships (INCOMING) labeled AFFECTS.
(The system navigates backward and finds a node "CVE-2024-001").
Result: Returns nodes found in Step 1.
2. The Code:
var
  Plan: TQueryPlan;
  Results: TArray<TAiRagGraphNode>;
begin
  // Plan configuration (normally this comes from an LLM JSON)
  Plan.AnchorPrompt := 'Billing infrastructure system';
  Plan.AnchorVariable := 'system';
  
  SetLength(Plan.Steps, 1);
  Plan.Steps[0].SourceVariable := 'system';
  Plan.Steps[0].EdgeLabel := 'AFFECTS'; // Risk relationship
  Plan.Steps[0].IsReversed := True;      // We look for WHO affects the system (Incoming)
  Plan.Steps[0].TargetVariable := 'risk';
  
  Plan.ResultVariable := 'risk';

  // Execution
  // Query(Plan, Depth, Limit, Precision)
  Results := RAG.Query(Plan, 0, 5, 0.70);
end;

Why is it revolutionary?
The Query function allows the user to ask questions about the causal structure of data without knowing the technical names of servers, error codes, or the exact terminology of the database.
The Vector bridges the language gap ("Billing" -> "ERP").
The Graph bridges the logical gap ("Affects" -> Find the source of the problem).
This is the true power of Graph-RAG: Structured Reasoning from Natural Language.

5.3.1. Practical Case: Automating Query with LLM
In the previous example we defined TQueryPlan manually by code. However, in a real chat application, we do not want to program each possible question. We want the LLM to translate user intention into a dynamically executable plan.
Below, we show how to implement the complete flow using the TAiChatConnection component (as seen in the Demo application).
The "Planner" Prompt
First, we need a prompt that teaches the LLM to act as a query architect.
(This prompt is simplified for the example):
System: You are an expert in translating user questions into query plans for a knowledge graph.
Your output must be a JSON following this structure:

{
  "anchorPrompt": "Text for vector search of the initial node",
  "anchorVariable": "start",
  "steps": [
    {
      "sourceVariable": "start",
      "edgeLabel": "RELATION_NAME",
      "targetVariable": "destination",
      "isReversed": false
    }
  ],
  "resultVariable": "destination"
}
User: "What risks affect billing systems?"

Delphi Implementation
This code takes the user's question, gets the JSON plan from the LLM, converts it into a TQueryPlan object, and executes the search.


procedure TMainForm.ExecuteIntelligentQuery(const UserQuestion: string);
var
  Prompt, JsonResponse: string;
  Plan: TQueryPlan;
  FoundNodes: TArray<TAiRagGraphNode>;
  Node: TAiRagGraphNode;
begin
  // 1. Build the prompt for the LLM
  Prompt := AiPrompts1.GetTemplate('CreateJsonQueryPlan', ['text=' + UserQuestion]);

  // 2. Query the LLM (GPT-4, Claude, etc.)
  // We force JSON output to ensure parsing works
  AiConn.Params.Values['response_format'] := '{"type": "json_object"}'; 
  JsonResponse := AiConn.AddMessageAndRun(Prompt, 'user', []);

  // 3. Convert JSON to TQueryPlan (using our helper)
  Plan := ParseJsonToQueryPlan(JsonResponse);

  // 4. Validate and Execute
  if (Plan.AnchorPrompt <> '') then
  begin
    // We execute the hybrid query
    // Depth 0, Limit 5, Precision 0.7
    FoundNodes := RAG.Query(Plan, 0, 5, 0.7);

    // 5. Show Results
    if Length(FoundNodes) > 0 then
    begin
      MemoLog.Lines.Add('Graph Response:');
      for Node in FoundNodes do
        MemoLog.Lines.Add('- ' + Node.Name + ' (' + Node.NodeLabel + ')');
    end
    else
      MemoLog.Lines.Add('No relevant information found in the graph.');
  end;
end;

What just happened
The user asked in natural language.
The LLM understood that to answer it needs to search "Systems" and look at incoming "Risk" relationships.
The LLM generated the technical JSON.
Delphi executed that plan against the real graph.
This pattern allows your application to answer questions you never explicitly programmed, as long as the information and relationships exist in the graph.

Chapter 6: Practical Tutorial - Your First In-Memory Graph
So far we have seen a lot of theory and architecture. In this chapter, we will build a functional application in less than 10 minutes.
We will create a small knowledge graph about "Historical Characters and their Inventions", query it through AI, and visualize the results. All this will happen in your PC's RAM, without needing to install databases.
6.1. Project Configuration
Create a new VCL or FMX project in Delphi.
Drag the following components to the form:
TAiRagGraph (rename it to RAG).
TAiOpenAiEmbeddings (or the embeddings provider you prefer).
TAiRagGraphBuilder.
Connect the components:
In RAG, assign Embeddings -> AiOpenAiEmbeddings1.
In RAGBuilder, assign Graph -> RAG and Embeddings -> AiOpenAiEmbeddings1.
Add your API Key to the Embeddings component.

6.2. Data Ingestion (The "Hello World")
We will simulate that an LLM has already processed a text and given us this JSON. We will use the Builder to load it.
Place a btnLoad button and add this code:

procedure TMainForm.btnLoadClick(Sender: TObject);
var
  JsonData: string;
begin
  // We simulate a JSON that would come from an LLM
  JsonData := '[' +
    '{' +
    '  "subject": {' +
    '    "name": "Nikola Tesla", "nodeLabel": "PERSON", ' +
    '    "text": "Serbian-American inventor, electrical and mechanical engineer."' +
    '  },' +
    '  "predicate": {' +
    '    "edgeLabel": "INVENTED", "name": "created the device"' +
    '  },' +
    '  "object": {' +
    '    "name": "Induction Motor", "nodeLabel": "INVENTION", ' +
    '    "text": "Electric motor that works with alternating current."' +
    '  }' +
    '},' +
    '{' +
    '  "subject": {' +
    '    "name": "Thomas Edison", "nodeLabel": "PERSON", ' +
    '    "text": "American inventor and businessman."' +
    '  },' +
    '  "predicate": {' +
    '    "edgeLabel": "RIVALED_WITH", "name": "had conflict with"' +
    '  },' +
    '  "object": {' +
    '    "name": "Nikola Tesla", "nodeLabel": "PERSON", ' +
    '    "text": ""' + // Note: When repeating the node, Builder will merge data
    '  }' +
    '}]';

  // We process the JSON
  RAGBuilder.Process(JsonData, msAddNewOnly);
  
  ShowMessage('Graph loaded. Nodes: ' + IntToStr(RAG.NodeCount));
end;

6.3. Querying the "Genius"
Now we will test the power of vector search. We will ask a vague question that does not exactly match names.
Place a TEdit (edtQuestion), a TMemo (memoResults), and a btnSearch button.

procedure TMainForm.btnSearchClick(Sender: TObject);
var
  Results: TArray<TAiRagGraphNode>;
  Node: TAiRagGraphNode;
begin
  // User question: "alternating current expert"
  // (Note that the name "Nikola Tesla" does not have those words, but his description does)
  
  // We search with depth 1 to see what he invented
  Results := RAG.Search(edtQuestion.Text, 1, 3, 0.75);

  memoResults.Lines.Clear;
  if Length(Results) = 0 then
    memoResults.Lines.Add('Nothing found.')
  else
  begin
    for Node in Results do
    begin
      memoResults.Lines.Add('FOUND: ' + Node.Name + ' (' + Node.NodeLabel + ')');
      
      // Show relationships (thanks to ADepth=1)
      if Node.OutgoingEdges.Count > 0 then
      begin
        memoResults.Lines.Add('  -> Relationships:');
        for var Edge in Node.OutgoingEdges do
          memoResults.Lines.Add('     - ' + Edge.EdgeLabel + ' -> ' + Edge.ToNode.Name);
      end;
      memoResults.Lines.Add('-------------------');
    end;
  end;
end;
Expected Result: If you search for "Edison's enemy" or "electricity expert", the system should return Nikola Tesla and show that he invented the Induction Motor. You have created your first reasoning system!
6.4. Visualization: Seeing is Believing
In-memory graphs are abstract. Let us export it to see it in a visual tool.
procedure TMainForm.btnExportClick(Sender: TObject);
begin
  // Export to GraphML format (compatible with Gephi and yEd)
  RAG.SaveToFile('MyHistoricalGraph.graphml', gefGraphML);
  
  // Export to DOT format (for Graphviz)
  RAG.SaveToFile('MyHistoricalGraph.dot', gefDOT);
  
  ShowMessage('Files exported. Open them to see your network!');
end;
Extra steps:
Download and install Gephi (free).
Open the generated .graphml file.
You will see Tesla, Edison, and Motor nodes connected visually.
Part III: Scalability and Production
An in-memory graph is incredibly fast, but has a limit: your server's RAM. What if you have millions of documents? Or if you need data persistence after a restart?
In this part, you will learn to connect MakerAI with industrial-level databases, transforming your application into a robust, concurrent, and persistent system.

Chapter 7: Driver System and Persistence
MakerAI has been designed with a storage-agnostic architecture. The TAiRagGraph component does not know about SQL, files, or connections. It only knows about Nodes and Edges.
To talk to the outside world, it uses a Driver.
7.1. Abstraction: TAiRagGraphDriverBase
Every driver in MakerAI must inherit from this base class. It is a contract that defines the operations the database must support.
The graph delegates to the driver operations like:
AddNode / AddEdge: Save new elements.
FindNodeByID: Retrieve a specific node.
SearchNodes: Perform vector searches (delegating heavy math to the DB).
Query: Execute complex query plans.
Thanks to this abstraction, today you can use Postgres, and tomorrow you could write a driver for Neo4j, Redis, or SQLite without changing a single line of your business logic.
7.2. Postgres as Graph Engine (TAiRagGraphPostgresDriver)
PostgreSQL has become the "Swiss army knife" of modern databases. With the pgvector extension, it transforms into a high-performance vector database, capable of competing with dedicated solutions like Pinecone or Milvus.
Why Postgres?
All in one: You have your relational data (users, invoices) and your vector graph in the same place.
ACID: Safe transactions. If edge insertion fails, you are not left with corrupt data.
HNSW: Supports Hierarchical Navigable Small World indices, the gold standard for fast vector searches in millions of records.
Recursive SQL: Allows traversing deep graphs with surprising efficiency.

Driver Configuration
To use it, you need:
A PostgreSQL server (v12+).
The vector extension installed.
The TAiRagGraphPostgresDriver component on your form.

// Connection
RAGPgDriver.Connection := FDConnection1; // Your normal FireDAC connection
RAGPgDriver.TableName := 'knowledge_v1_'; // Prefix for tables

// Linking
RAG.Driver := RAGPgDriver; 

// Initialization (Only the first time)
// Creates tables 'knowledge_v1_nodes' and 'knowledge_v1_edges'
RAGPgDriver.CreateSchema('knowledge_v1_', 1536); // 1536 is OpenAI dimension

7.3. Optimization: The Magic of Delegation
The Postgres driver is not a simple store. It is intelligent.
When you execute a complex search like Search(..., ADepth=2), the driver does NOT download thousands of records to Delphi to filter them.
Instead:
It builds a complex SQL query using Recursive CTEs (WITH RECURSIVE).
Sends the query to Postgres.
Postgres performs vector search (using HNSW index) and navigates relationships internally.
The driver receives only the final filtered and clean subgraph.
This drastically reduces network traffic and memory load on your application server, allowing the system to scale massively.
Note on Integrity:
The driver configures foreign keys with ON DELETE CASCADE. If you delete a node in the database (even manually via SQL), Postgres will automatically delete all connected edges. Your graph always stays consistent.


MakerAI Graph-RAG Manual
Chapter 8: Best Practices and Optimization
Implementing a Graph-RAG system is as much an art as a science. Here we compile a series of tips and strategies to ensure your system is fast, accurate, and economical.
8.1. Data Modeling Strategy
The most common error is wanting to "graph everything".
Not everything is a node:
Bad: Create a node for date "2023-10-01" and connect it to 500 documents. You will create a "Supernode" that will dirty all searches.
Good: Save the date as a property inside the Document node or relationship.
Granularity:
Prefer conceptual nodes ("Contract") over purely textual nodes ("Paragraph 1").
Let the embedding text field carry the semantic weight of content, and use the graph for high-level structure.
8.2. Vector and Index Optimization
Vector Dimension:
Make sure the dimension configured in CreateSchema matches your AI model (OpenAI=1536, Llama2=4096). If they do not match, Postgres will throw errors.
Distance Operator:
The driver uses <-> (Euclidean/L2 Distance) by default. This works well with normalized vectors (like OpenAI's).
If you use non-normalized models, consider adjusting the index in the database to use cosine similarity (<=>).
8.3. Context Management (Tokens)
In RAG, each retrieved node consumes "tokens" in the LLM's context window.
Limit Depth (ADepth):
ADepth=1 is usually the sweet spot. Brings the node and its direct neighbors.
ADepth=2 can bring exponentially more nodes (hundreds), which could saturate the prompt or slow the response. Use with caution.
Limit Quantity (ALimit):

