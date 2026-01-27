# Invention Disclosure Document

## Derivux for MATLAB: AI-Integrated Engineering Assistant

---

## 1. Administrative Information

| Field | Value |
|-------|-------|
| **Invention Title** | Derivux for MATLAB: Workspace-Aware AI Integration with Secure Code Execution for MATLAB and Simulink |
| **Inventor(s)** | Sebastian Hondl |
| **Date of Conception** | January 15, 2026 |
| **Filing Type** | Personal/Individual |
| **Development Status** | Working Prototype |
| **Repository Status** | Private (GitHub) |
| **Prior Public Disclosure** | None |

---

## 1B. University Affiliation & Independent Development Declaration

### Inventor Status

| Field | Value |
|-------|-------|
| **University Affiliation** | University of Minnesota (Student) |
| **Department** | Mechanical Engineering |
| **Relevant Coursework** | ME 5281 and related courses |

### Declaration of Independent Development

**I hereby declare that this invention:**

1. **Was developed independently** as a personal project, not as part of any university research program, grant-funded work, or faculty-directed research

2. **Did not utilize university research resources**, including:
   - No university research lab facilities
   - No university research funding or grants
   - No research staff or faculty collaboration on core IP development
   - No specialized research equipment or computing clusters

   *Note: Development did utilize the university-provided MATLAB license available to all students as a standard educational resource. See "Note on University-Provided MATLAB License" below for why this does not constitute a research resource.*

3. **Arose from personal initiative and coursework**, specifically:
   - Personal interest in AI-assisted engineering tools
   - Skills developed through standard coursework (not research assistantships)
   - Development performed on personal time using personal computing resources

4. **Does not incorporate** any university-owned intellectual property, including:
   - No code from university research projects
   - No algorithms developed under faculty supervision for research
   - No data collected as part of university research

### Resources Used (For Transparency)

| Resource | Source | Category |
|----------|--------|----------|
| MATLAB license | University-provided student license | Standard Educational Resource |
| Development hardware | Personal computer | Personal |
| Claude API / SDK | Personal account | Personal |
| GitHub repository | Personal account | Personal |
| Development time | Personal time outside coursework | Personal |

### Note on University-Provided MATLAB License

The MATLAB software license used during development was provided by the University of Minnesota as a **standard educational resource available to all enrolled students**. This is analogous to other broadly-available university resources such as:

- Library access and digital subscriptions
- Campus WiFi and network access
- General-purpose computer labs
- Microsoft Office / Google Workspace licenses

**This type of standard educational resource is distinct from research-specific resources** such as:
- Research grant funding
- Specialized laboratory equipment
- Research computing clusters allocated for specific projects
- Software licenses purchased for specific research programs

The use of standard student software licenses for personal projects is common and expected — students routinely use university-provided MATLAB, Microsoft Office, and similar tools for personal work, class projects, and independent learning without triggering university IP claims.

**Key distinction:** The university provides MATLAB licenses to support student education broadly, not as a quid pro quo for IP rights on student personal projects.

### Why This Matters

Under most university IP policies, including the University of Minnesota's, inventions created:
- Using significant university resources, OR
- As part of sponsored research, OR
- Within scope of employment duties

...may be claimed by the university. This invention falls **outside** these categories as it represents independent student work arising from personal initiative.

**Recommended Action:** Submit this disclosure to the UMN Office of Technology Commercialization (https://research.umn.edu/units/techcomm) to:
1. Formally document independent ownership
2. Obtain a case ID for reference in external agreements
3. Confirm the university does not claim ownership rights

---

## 2. Technical Field

This invention relates to:

- **AI-assisted software development tools** for domain-specific engineering environments
- **Human-AI collaborative engineering** in control systems and simulation development
- **Secure execution environments** for AI-generated code
- **Real-time context integration** between AI language models and specialized technical software
- **Model-Context Protocol (MCP)** tool integration for autonomous AI agents

---

## 3. Background and Problem Statement

### Current Limitations

Engineers working with MATLAB and Simulink face significant friction when using AI assistants:

1. **Context Switching Costs**: Users must manually copy-paste data, describe workspace contents, and translate between AI recommendations and MATLAB syntax

2. **Lack of Workspace Awareness**: Existing AI tools cannot see the user's current variables, model structure, or execution context, leading to generic or incorrect suggestions

3. **Security Risks**: AI-generated code may contain dangerous operations (file deletion, system commands, network access) that could harm the user's system if executed blindly

4. **Simulink Complexity**: Block diagram manipulation requires understanding spatial relationships, port connections, and library paths—information difficult to convey through text

5. **Session Isolation**: Multi-tab or multi-project workflows require context separation that existing tools don't provide

### Need in the Art

There exists a need for an AI integration that:
- Understands the user's live workspace state
- Executes code securely with appropriate safeguards
- Manipulates Simulink models programmatically
- Maintains conversation context across extended sessions
- Routes specialized requests to purpose-built agents

---

## 4. Summary of the Invention

**Derivux for MATLAB** is a toolbox that deeply integrates Claude AI into the MATLAB and Simulink environment, enabling engineers to interact with an AI assistant that has real-time awareness of their workspace, can execute code safely, and can programmatically create and modify Simulink models.

### Key Capabilities

1. **Workspace-Aware AI**: Claude can see all variables, their types, sizes, and values in the MATLAB workspace
2. **Secure Code Execution**: A sandbox validates AI-generated code before execution, blocking dangerous operations
3. **Simulink Manipulation**: Claude can query, create, modify, and optimize Simulink block diagrams
4. **Visual Output Capture**: Plots and diagrams are captured and displayed inline in the chat interface
5. **Multi-Session Isolation**: Multiple chat tabs maintain separate conversation contexts
6. **Specialized Agent Routing**: Pattern-based routing directs requests to purpose-built agents

---

## 5. Detailed Technical Description

### 5.1 Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    MATLAB LAYER (MATLAB/MEX)                    │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐  │
│  │   DerivuxApp     │  │  SimulinkBridge  │  │ CodeExecutor  │  │
│  │   (Orchestrator) │  │  (Model Access)  │  │ (Security)    │  │
│  └────────┬─────────┘  └────────┬─────────┘  └───────┬───────┘  │
│           │                     │                    │          │
│  ┌────────┴─────────────────────┴────────────────────┴────────┐ │
│  │              WorkspaceContextProvider                       │ │
│  │              (Real-time Introspection)                      │ │
│  └─────────────────────────────┬──────────────────────────────┘ │
└────────────────────────────────┼────────────────────────────────┘
                                 │ py.derivux.MatlabBridge()
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                   BRIDGE LAYER (Python)                         │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐  │
│  │   MatlabBridge   │  │ SpecializedAgent │  │ SessionContext│  │
│  │   (Orchestrator) │  │   Manager        │  │ (Isolation)   │  │
│  └────────┬─────────┘  └────────┬─────────┘  └───────────────┘  │
│           │                     │                               │
│  ┌────────┴─────────────────────┴──────────────────────────────┐│
│  │           Persistent Async Event Loop                       ││
│  │           (Maintains SDK Client State)                      ││
│  └─────────────────────────────┬───────────────────────────────┘│
└────────────────────────────────┼────────────────────────────────┘
                                 │ Claude Agent SDK
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                     AI LAYER (Claude SDK)                       │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐  │
│  │   MatlabAgent    │  │   MCP Server     │  │ Tool Registry │  │
│  │   (SDK Client)   │  │   (In-Process)   │  │ (matlab/*)    │  │
│  └────────┬─────────┘  └────────┬─────────┘  └───────────────┘  │
│           │                     │                               │
│  ┌────────┴─────────────────────┴──────────────────────────────┐│
│  │                    Claude API                                ││
│  └──────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Component Descriptions

#### 5.2.1 MATLAB Layer

**DerivuxApp** (`toolbox/+derivux/DerivuxApp.m:1-385`)
- Main entry point and orchestrator for the toolbox
- Creates dockable UI figure that integrates with MATLAB desktop
- Manages lifecycle of Python bridge and Simulink bridge
- Handles session logging with correlation IDs across MATLAB and Python

**CodeExecutor** (`toolbox/+derivux/CodeExecutor.m:1-256`)
- Security sandbox for AI-generated code execution
- Implements blocklist of dangerous functions (lines 23):
  ```matlab
  BLOCKED_FUNCTIONS = {'system', 'dos', 'unix', 'perl', 'python', '!',
                       'eval', 'evalin', 'evalc', 'feval', 'builtin',
                       'delete', 'rmdir', 'movefile', 'copyfile',
                       'java.lang.Runtime', 'py.os', 'py.subprocess', ...}
  ```
- Pattern-based detection blocks shell escapes and foreign runtime access (lines 26):
  ```matlab
  BLOCKED_PATTERNS = {'^\s*!', 'java\.lang\.', 'py\.', 'NET\.', 'COM\.'}
  ```
- Supports three execution modes: prompt (ask user), auto (execute with blocks), bypass (expert mode)

**SimulinkBridge** (`toolbox/+derivux/SimulinkBridge.m:1-537`)
- Provides programmatic access to Simulink model structure
- Extracts block lists, connections, parameters, and subsystem hierarchies
- Enables model modification: add blocks, connect signals, set parameters
- Integrates with custom layout engine for diagram optimization

**SimulinkLayoutEngine** (`toolbox/+derivux/SimulinkLayoutEngine.m:1-807`)
- Custom graph layout algorithm optimized for control system diagrams
- Implements five-phase layout pipeline:
  1. **Graph Extraction**: Build adjacency representation from Simulink model
  2. **Layer Assignment**: Longest-path algorithm for left-to-right flow (lines 235-310)
  3. **Crossing Minimization**: Barycenter heuristic with bidirectional sweeps (lines 314-354)
  4. **Coordinate Assignment**: Calculate pixel positions with proper spacing (lines 385-442)
  5. **Wire Routing**: Orthogonal routes with 90-degree angles (lines 446-476)
- Produces clean, readable diagrams superior to Simulink's built-in auto-arrange

**WorkspaceContextProvider** (`toolbox/+derivux/WorkspaceContextProvider.m:1-380`)
- Extracts real-time workspace state for AI context
- Formats variables by type with appropriate detail:
  - Scalars: show value
  - Vectors: show contents up to 10 elements
  - Matrices: show min/max/mean for large arrays
  - Structs: list field names
  - Tables: show dimensions and column names
- Also provides editor context (current file, cursor position, selection)

#### 5.2.2 Python Bridge Layer

**MatlabBridge** (`python/derivux/bridge.py:1-1516`)
- Central orchestrator for Python-side functionality
- Maintains persistent async event loop for SDK client state (lines 124-143)
- Implements graceful shutdown with timeout protection (lines 632-744)
- Provides multi-session context isolation (lines 1414-1516):
  ```python
  @dataclass
  class SessionContext:
      tab_id: str
      messages: List[Dict[str, Any]] = field(default_factory=list)
      created_at: float = field(default_factory=time.time)
      last_active_at: float = field(default_factory=time.time)
  ```
- Supports both Claude Agent SDK and CLI fallback modes

**SpecializedAgentManager** (via `specialized_agent.py`)
- Pattern-based routing framework for directing requests to specialized agents
- Routes based on explicit commands (`/git`, `/review`) or auto-detection
- Confidence scoring algorithm (lines 61-96):
  ```python
  # First match is a strong signal (0.5), each additional adds 0.15
  score = 0.5 + (matches - 1) * 0.15
  return min(1.0, score)
  ```

#### 5.2.3 AI Layer

**MatlabAgent** (`python/derivux/agent.py:1-590`)
- Wraps Claude Agent SDK with MATLAB-specific configuration
- Registers MCP tools for MATLAB and Simulink interaction
- Implements conversation compaction for long sessions (lines 498-547):
  - After 50 turns, requests Claude to summarize conversation
  - Restarts agent with summary in system prompt
  - Preserves context while reducing token usage

**MCP Tool Implementation**

MATLAB Tools (`python/derivux/matlab_tools.py:1-451`):
- `matlab_execute`: Run MATLAB code with figure capture
- `matlab_workspace`: List/read/write workspace variables
- `matlab_plot`: Generate and capture plots as base64 images

Simulink Tools (`python/derivux/simulink_tools.py:1-469`):
- `simulink_query`: Query model structure (blocks, connections, parameters)
- `simulink_modify`: Add/delete blocks, connect signals, set parameters
- `simulink_layout`: Optimize diagram layout using custom engine
- `simulink_capture`: Capture model diagram as image for chat display

### 5.3 Data Flow

```
User Message
    │
    ▼
┌──────────────────┐
│ Chat UI (JS/HTML)│ ◄─── Embedded in MATLAB uifigure
└────────┬─────────┘
         │ webwindow postMessage
         ▼
┌──────────────────┐
│ ChatUIController │ ◄─── Routes to Python bridge
└────────┬─────────┘
         │ py.derivux.MatlabBridge.start_async_message()
         ▼
┌──────────────────┐
│ MatlabBridge     │ ◄─── Routes to specialized agent
└────────┬─────────┘
         │ asyncio.run_coroutine_threadsafe()
         ▼
┌──────────────────┐
│ MatlabAgent      │ ◄─── Claude SDK client
└────────┬─────────┘
         │ MCP tool calls
         ▼
┌──────────────────┐
│ MCP Tools        │ ◄─── Execute MATLAB commands
└────────┬─────────┘
         │ MATLAB Engine API
         ▼
┌──────────────────┐
│ MATLAB Workspace │ ◄─── Code execution, figure capture
└──────────────────┘
```

### 5.4 Communication Protocol

The system uses a bidirectional asynchronous communication pattern:

1. **MATLAB → Python**: Direct Python calls via `py.derivux.MatlabBridge()`
2. **Python → MATLAB**: MATLAB Engine API (`matlab.engine`) for workspace access
3. **Async Streaming**: Python background thread with polling from MATLAB:
   ```python
   # Python side - stores chunks
   def poll_async_chunks(self) -> List[str]:
       with self._async_lock:
           chunks = self._async_chunks.copy()
           self._async_chunks = []
           return chunks
   ```
   ```matlab
   % MATLAB side - polls for updates
   while ~obj.PythonBridge.is_async_complete()
       chunks = obj.PythonBridge.poll_async_chunks();
       for i = 1:length(chunks)
           obj.appendToResponse(string(chunks{i}));
       end
       pause(0.05);
   end
   ```

---

## 6. Novel Aspects / Claims

### Claim 1: Bidirectional Asynchronous Communication Bridge for AI-MATLAB Integration

**The invention provides** a method and system for bidirectional asynchronous communication between an AI language model and a domain-specific technical computing environment (MATLAB), comprising:

- A persistent event loop in Python maintaining AI client state across multiple interactions
- Thread-safe chunk-based streaming from Python to MATLAB for real-time response display
- Graceful shutdown coordination with timeout protection to prevent MATLAB freezing
- Session ID correlation across language boundaries for unified logging

**Key Implementation** (`bridge.py:124-186`):
```python
def _start_persistent_loop(self) -> None:
    """Start a persistent event loop in a background thread.
    This keeps the SDK client alive between messages for conversation memory.
    """
    def run_loop():
        self._loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self._loop)
        self._loop.run_forever()

    self._loop_thread = threading.Thread(target=run_loop, daemon=True)
    self._loop_thread.start()
```

**Novelty**: Unlike existing approaches that spawn new processes per request, this maintains a persistent connection enabling conversation memory while preserving MATLAB's synchronous execution model.

---

### Claim 2: Real-Time Workspace Introspection for AI Context Enrichment

**The invention provides** a method for automatically extracting and formatting technical computing environment state for AI context, comprising:

- Type-aware formatting that presents variables appropriately for each MATLAB data type
- Size-aware truncation preventing context overflow while preserving essential information
- Priority ordering that surfaces smaller, more readable variables first
- Editor integration providing cursor position and selected text as additional context

**Key Implementation** (`WorkspaceContextProvider.m:31-85`):
```matlab
function context = getWorkspaceContext(obj)
    vars = evalin('base', 'whos');
    [~, idx] = sort([vars.bytes]);  % Prioritize smaller variables
    vars = vars(idx);

    for i = 1:length(vars)
        if count >= obj.MaxVariables, break; end
        if v.bytes > 1e7, continue; end  % Skip very large variables
        varStr = obj.formatVariable(v);
        % ... type-specific formatting
    end
end
```

**Novelty**: Existing AI assistants require manual context copying; this system automatically extracts relevant workspace state formatted specifically for AI consumption.

---

### Claim 3: Security-Sandboxed Code Execution with Pre-Validation

**The invention provides** a secure execution environment for AI-generated code, comprising:

- Function-level blocklist preventing dangerous operations (system calls, file deletion, eval chains)
- Pattern-based detection blocking shell escapes and foreign runtime access
- Multi-level execution modes (prompt, auto, bypass) balancing security with workflow speed
- Execution logging for audit trail and debugging

**Key Implementation** (`CodeExecutor.m:111-175`):
```matlab
function [isValid, reason] = validateCode(obj, code)
    % Check for blocked functions
    for i = 1:length(obj.BLOCKED_FUNCTIONS)
        pattern = sprintf('\\b%s\\s*[\\(\\.]?', regexptranslate('escape', funcName));
        if ~isempty(regexp(code, pattern, 'once'))
            isValid = false;
            reason = sprintf('Blocked function detected: %s', funcName);
            return;
        end
    end

    % Check for blocked patterns (shell escapes, foreign runtimes)
    for i = 1:length(obj.BLOCKED_PATTERNS)
        if ~isempty(regexp(code, obj.BLOCKED_PATTERNS{i}, 'once'))
            isValid = false;
            reason = sprintf('Blocked pattern detected');
            return;
        end
    end
end
```

**Novelty**: Rather than sandboxing at the OS level (which would prevent legitimate MATLAB operations), this uses domain-specific knowledge to block only dangerous patterns while allowing full MATLAB functionality.

---

### Claim 4: Automatic Simulink Diagram Layout Algorithm

**The invention provides** a specialized graph layout algorithm optimized for control system block diagrams, comprising:

- Five-phase pipeline: graph extraction, layer assignment, crossing minimization, coordinate assignment, wire routing
- Layer assignment using longest-path algorithm ensuring left-to-right signal flow
- Barycenter heuristic for crossing minimization with bidirectional sweeps
- Orthogonal wire routing producing 90-degree angles for professional appearance

**Key Implementation** (`SimulinkLayoutEngine.m:235-310` for layer assignment):
```matlab
function assignLayers(obj)
    % BFS-based longest path from sources
    sources = obj.findSourceBlocks();
    queue = sources;

    while ~isempty(queue)
        current = queue(1); queue(1) = [];
        currentLayer = obj.LayerAssignment(current);

        for succ = obj.AdjacencyList{current}
            newLayer = currentLayer + 1;
            if newLayer > obj.LayerAssignment(succ)
                obj.LayerAssignment(succ) = newLayer;
                queue(end+1) = succ;
            end
        end
    end
end
```

**Novelty**: Simulink's built-in auto-arrange often produces cluttered diagrams; this algorithm produces publication-quality layouts by applying graph drawing algorithms specifically tuned for control system conventions.

---

### Claim 5: Multi-Session Context Isolation in Single Process

**The invention provides** a method for maintaining multiple isolated conversation contexts within a single process, comprising:

- Per-tab session context storage with independent message histories
- Session switching that preserves conversation state across context changes
- Timestamp tracking for session activity and cleanup
- Specialized agent routing scoped to session context

**Key Implementation** (`bridge.py:1414-1516`):
```python
@dataclass
class SessionContext:
    tab_id: str
    messages: List[Dict[str, Any]] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)
    last_active_at: float = field(default_factory=time.time)

def switch_session_context(self, tab_id: str) -> None:
    if old_session_id and old_session_id in self._session_contexts:
        old_context = self._session_contexts[old_session_id]
        old_context.last_active_at = time.time()

    self._active_session_id = tab_id
    new_context = self._session_contexts[tab_id]
    new_context.last_active_at = time.time()
```

**Novelty**: Existing tools either share context across tabs (causing cross-contamination) or spawn separate processes (high resource usage). This provides isolation within a single, efficient process.

---

### Claim 6: Pattern-Based Specialized Agent Routing Framework

**The invention provides** a framework for routing user requests to purpose-built AI agents, comprising:

- Explicit command prefix matching (e.g., `/git`, `/review`)
- Confidence-based auto-detection using keyword patterns
- Scoring algorithm that weights first match strongly while accumulating evidence
- Agent configuration via declarative data structures

**Key Implementation** (`specialized_agent.py:61-96`):
```python
def calculate_confidence(self, message: str) -> float:
    message_lower = message.lower()
    matches = 0

    for pattern in self.auto_detect_patterns:
        if re.search(pattern, message_lower, re.IGNORECASE):
            matches += 1

    if matches == 0:
        return 0.0

    # First match is a strong signal (0.5), each additional adds 0.15
    score = 0.5 + (matches - 1) * 0.15
    return min(1.0, score)
```

**Novelty**: Rather than using a single general-purpose prompt, this routes requests to specialized agents with focused capabilities and restricted tool access, improving both accuracy and security.

---

## 7. Advantages Over Prior Art

### 7.1 Comparison with MATLAB Copilot

| Feature | MATLAB Copilot | Derivux |
|---------|---------------|---------|
| Workspace awareness | Limited | Full real-time introspection |
| Code execution | User must copy-paste | Direct secure execution |
| Simulink support | Text suggestions only | Programmatic model manipulation |
| Figure capture | Manual export | Automatic inline display |
| Security model | N/A (no execution) | Multi-layer validation |

### 7.2 Comparison with General AI Assistants (ChatGPT, Claude.ai)

| Feature | General AI | Derivux |
|---------|-----------|---------|
| MATLAB syntax accuracy | General knowledge | Domain-specific tools |
| Workspace context | None | Real-time introspection |
| Execution capability | None | Secure sandbox |
| Simulink manipulation | Describe only | Programmatic access |
| Session persistence | Web-based | MATLAB-integrated |

### 7.3 Unique Benefits

1. **Zero Context Switching**: Engineers stay in MATLAB while accessing AI capabilities
2. **Live Workspace Awareness**: AI understands current state without manual description
3. **Secure Execution**: AI-generated code runs with appropriate safeguards
4. **Visual Feedback**: Plots and diagrams appear inline in conversation
5. **Domain Expertise**: Specialized agents for git, code review, Simulink, etc.

---

## 8. Potential Applications

### 8.1 Control Systems Engineering
- Rapid prototyping of control algorithms
- Automated transfer function analysis and Bode plot generation
- PID tuning assistance with immediate simulation feedback

### 8.2 Simulation Development
- Accelerated Simulink model creation through natural language
- Automated layout optimization for publication-ready diagrams
- Parameter sweep automation with result visualization

### 8.3 Educational Uses
- Interactive MATLAB tutorial with immediate execution feedback
- Step-by-step debugging assistance with workspace visibility
- Concept explanation with live examples

### 8.4 Enterprise Deployment
- Standardized AI assistance across engineering teams
- Audit logging for compliance requirements
- Customizable security policies per deployment

---

## 9. Development Status and Evidence

### 9.1 Working Prototype

The invention exists as a fully functional MATLAB toolbox with:

- **~3,500 lines of MATLAB code** across 12 class files
- **~4,000 lines of Python code** across 15 modules
- **~1,500 lines of JavaScript/HTML** for the chat UI

### 9.2 Key Implementation Files

| Component | File | Lines |
|-----------|------|-------|
| Main Orchestrator | `toolbox/+derivux/DerivuxApp.m` | 385 |
| Security Model | `toolbox/+derivux/CodeExecutor.m` | 256 |
| Simulink Bridge | `toolbox/+derivux/SimulinkBridge.m` | 537 |
| Layout Engine | `toolbox/+derivux/SimulinkLayoutEngine.m` | 807 |
| Workspace Context | `toolbox/+derivux/WorkspaceContextProvider.m` | 380 |
| Python Bridge | `python/derivux/bridge.py` | 1516 |
| AI Agent | `python/derivux/agent.py` | 590 |
| Agent Routing | `python/derivux/agents/specialized_agent.py` | 265 |
| MATLAB Tools | `python/derivux/matlab_tools.py` | 451 |
| Simulink Tools | `python/derivux/simulink_tools.py` | 469 |

### 9.3 Development Timeline

| Date | Milestone |
|------|-----------|
| January 15, 2026 | Initial commit - basic architecture |
| January 16-20, 2026 | Core MATLAB/Python bridge implementation |
| January 21-24, 2026 | Simulink integration and layout engine |
| January 25-27, 2026 | Security hardening and multi-session support |

---

## 10. Prior Art Considerations

### 10.1 Known Related Technologies

1. **MATLAB Copilot** (MathWorks)
   - Provides code suggestions but no execution capability
   - Limited workspace awareness
   - No Simulink manipulation

2. **GitHub Copilot**
   - General code completion, not MATLAB-specific
   - No workspace integration
   - No execution environment

3. **Claude Agent SDK** (Anthropic)
   - Provides the underlying AI capability
   - Generic framework, not MATLAB-specific
   - No domain-specific tools

4. **Model Context Protocol (MCP)**
   - Standard for tool integration
   - Generic protocol, no MATLAB implementation
   - This invention implements MCP tools for MATLAB/Simulink

### 10.2 Differentiation Points

1. **Deep Integration**: Unlike browser-based AI tools, Derivux runs inside MATLAB with direct workspace access

2. **Security-First Design**: Unlike general code execution, the security sandbox is specifically designed for MATLAB operations

3. **Simulink-Native**: Unlike text-based AI assistants, Derivux can programmatically manipulate Simulink models

4. **Custom Layout Algorithm**: The diagram layout engine is purpose-built for control system conventions

---

## 11. Disclosure History

### 11.1 Prior Publications
None. The repository has been private since creation.

### 11.2 Prior Demonstrations
None. Development has occurred in a private setting.

### 11.3 Third-Party Access
None. No external parties have had access to the code or documentation.

---

## 12. Verification Checklist

### For Patent Attorney Review

- [ ] **Claim 1 (Async Communication)**: Review `bridge.py` lines 124-186, 582-612
- [ ] **Claim 2 (Workspace Introspection)**: Review `WorkspaceContextProvider.m` lines 31-85
- [ ] **Claim 3 (Security Sandbox)**: Review `CodeExecutor.m` lines 21-27, 111-175
- [ ] **Claim 4 (Layout Algorithm)**: Review `SimulinkLayoutEngine.m` full file
- [ ] **Claim 5 (Session Isolation)**: Review `bridge.py` lines 1414-1516
- [ ] **Claim 6 (Agent Routing)**: Review `specialized_agent.py` lines 61-96

### Technical Accuracy
- [ ] All file references verified against repository
- [ ] Code snippets accurately represent implementation
- [ ] Architecture diagram matches actual data flow

### Completeness
- [ ] All six novel claims clearly articulated
- [ ] Prior art adequately distinguished
- [ ] Development timeline documented

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| **MCP** | Model Context Protocol - standard for AI tool integration |
| **Claude Agent SDK** | Anthropic's Python SDK for building AI agents |
| **MATLAB Engine API** | MathWorks API for controlling MATLAB from Python |
| **Simulink** | MATLAB's block diagram simulation environment |
| **Barycenter Heuristic** | Graph layout algorithm for minimizing edge crossings |

---

## Appendix B: Figure Captions

1. **Figure 1**: Three-layer architecture showing MATLAB, Bridge, and AI layers
2. **Figure 2**: Data flow diagram from user message to MATLAB execution
3. **Figure 3**: Simulink layout engine pipeline phases

---

## Appendix C: Template Language for Company Agreements

### Background IP Carve-Out

When entering agreements with companies (internships, consulting, projects), use language similar to:

> **Pre-Existing Intellectual Property.** [Your Name] enters this agreement with pre-existing intellectual property protected under University of Minnesota invention disclosure [CASE ID - to be assigned], titled "Derivux for MATLAB: Workspace-Aware AI Integration with Secure Code Execution for MATLAB and Simulink" (the "Background IP"). This Background IP is expressly excluded from any intellectual property assignment or license provisions of this Agreement. The Background IP includes, without limitation:
>
> - Source code, architecture, and design specifications for AI-MATLAB integration systems
> - Security sandboxing methods for AI-generated code execution
> - Algorithms for Simulink diagram layout optimization
> - Methods for real-time workspace introspection and context formatting
> - Multi-session context isolation techniques
> - Pattern-based agent routing frameworks

### Limited Output License (If Demonstrating Capabilities)

If you want to demonstrate the tool's capabilities to a company without exposing the IP:

> **Demonstration Outputs.** During the Project, [Your Name] may utilize personal tools to generate [outputs/analyses/solutions] for the benefit of the Project ("Tool Outputs"). Company shall have a non-exclusive, non-transferable, limited license to use such Tool Outputs solely within the field of [DEFINE NARROWLY - e.g., "internal analysis of Widget X performance data"]. This license:
>
> (a) Does not include any rights to the underlying tools, methods, source code, designs, specifications, or intellectual property used to generate the Tool Outputs;
>
> (b) Does not permit reverse engineering, decompilation, or analysis of the Tool Outputs to derive information about the generating methods;
>
> (c) Is limited to [SPECIFIC PROJECT NAME] and does not extend to other projects or uses;
>
> (d) Terminates upon completion of the Project unless otherwise agreed in writing.

### Key Definitions to Include

| Term | Suggested Definition |
|------|---------------------|
| **Field of Use** | Define as narrowly as possible (e.g., "thermal analysis of consumer electronics housings" not "engineering analysis") |
| **Background IP** | Reference the invention disclosure title and case ID |
| **Tool Outputs** | Results generated by your tools, not the tools themselves |
| **Project** | Specific, named engagement with defined scope |

### What to Avoid

❌ Do NOT agree to:
- Broad IP assignment clauses without carve-outs
- "All work product created during employment" language without exceptions
- Obligations to disclose your personal IP to the company
- Non-compete clauses that would prevent using your own tools elsewhere

✅ DO insist on:
- Written acknowledgment of your pre-existing IP
- Specific carve-out language referencing your disclosure
- Narrow field-of-use limitations on any output licenses
- No access to source code, specifications, or designs

---

## Appendix D: Next Steps Checklist

### Immediate (Before Any Company Engagement)

- [ ] Submit this disclosure to UMN Tech Commercialization
- [ ] Obtain case ID / reference number
- [ ] Meet with Tech Commercialization to confirm independent ownership
- [ ] Review any existing employment/internship agreements for IP clauses

### Before Going Public

- [ ] Decide on patent strategy with Tech Commercialization
- [ ] If pursuing patent: file provisional application
- [ ] If not: document trade secret protections

### When Engaging with Companies

- [ ] Reference disclosure case ID in all agreements
- [ ] Include Background IP carve-out language
- [ ] Define field of use as narrowly as possible
- [ ] Never share source code without written agreement

---

*Document prepared: January 27, 2026*
*Version: 1.1*
*Updated to include university affiliation documentation and company agreement templates*
