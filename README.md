# Derivux for MATLAB

A MATLAB toolbox that integrates Claude AI assistant into MATLAB and Simulink, designed for mechanical engineers and developers.

## Features

- **Chat Interface**: Side panel with embedded web-based chat UI
- **Code Execution**: Run MATLAB code directly from Claude's responses
- **Workspace Context**: Automatically include MATLAB workspace variables in prompts
- **Simulink Integration**: Read and modify Simulink models programmatically
- **GitHub Integration**: Leverage Claude CLI's built-in git capabilities

## Requirements

- MATLAB R2025b or later
- Claude CLI installed and in PATH
  - Install from: https://claude.ai/code

## Installation

1. Clone this repository or download the toolbox
2. Add the toolbox to your MATLAB path:
   ```matlab
   addpath('/path/to/derivux/toolbox')
   ```
3. Verify Claude CLI is installed:
   ```bash
   claude --version
   ```

## Quick Start

```matlab
% Launch the Derivux assistant
derivux.launch()
```

## Usage

### Basic Chat
1. Launch the assistant with `derivux.launch()`
2. Type your question in the input box
3. Press Ctrl+Enter or click Send

### Including Context
- Check "Include workspace" to send workspace variable information to Claude
- Check "Include Simulink model" to send currently open model structure to Claude

### Code Execution
- MATLAB code blocks in Claude's responses have "Run" and "Insert" buttons
- Click "Run" to execute the code immediately
- Click "Insert" to insert the code into the MATLAB editor
- Click "Copy" to copy the code to clipboard

### Simulink Integration
When a Simulink model is open:
- Claude can read block structures and connections
- Claude can suggest modifications using Simulink APIs
- Block additions and parameter changes can be executed

## Project Structure

```
derivux/
├── toolbox/
│   ├── +derivux/              # Main package
│   │   ├── DerivuxApp.m       # Main entry point
│   │   ├── ClaudeProcessManager.m  # CLI communication
│   │   ├── ChatUIController.m      # UI controller
│   │   ├── CodeExecutor.m          # Safe code execution
│   │   ├── SimulinkBridge.m        # Simulink integration
│   │   ├── WorkspaceContextProvider.m
│   │   └── +config/
│   │       └── Settings.m
│   ├── chat_ui/               # Web UI files
│   │   ├── index.html
│   │   ├── css/
│   │   └── js/
│   ├── Contents.m
│   └── functionSignatures.json
├── tests/                     # Unit tests
│   ├── tClaudeProcessManager.m
│   ├── tCodeExecutor.m
│   ├── tSimulinkBridge.m
│   └── runAllTests.m
└── README.md
```

## Running Tests

```matlab
% Run all tests
cd tests
results = runAllTests();

% Run with verbose output
results = runAllTests('Verbose', true);

% Generate HTML report
results = runAllTests('GenerateReport', true);
```

## Security

The CodeExecutor class validates all code before execution, blocking:
- System commands (`system`, `dos`, `unix`, `!`)
- Eval variants (`eval`, `evalin`, `evalc`, `feval`)
- Destructive operations (`delete`, `rmdir`)
- Java/Python escape hatches
- Clear/exit/quit commands

## Configuration

Settings are stored in MATLAB preferences and can be modified:

```matlab
settings = derivux.config.Settings.load();
settings.theme = 'light';
settings.executionTimeout = 60;
settings.save();
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                 MATLAB Desktop                       │
│  ┌─────────────────────────────────────────────────┐│
│  │  uifigure with Grid Layout                      ││
│  │  ┌──────────────┐  ┌──────────────────────────┐ ││
│  │  │  Main Panel  │  │  Chat Panel (uihtml)     │ ││
│  │  │              │  │  - HTML/CSS/JS UI        │ ││
│  │  │              │  │  - Message history       │ ││
│  │  │              │  │  - Code blocks + Run btn │ ││
│  │  └──────────────┘  └──────────────────────────┘ ││
│  └─────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────┘
          │                           │
          ▼                           ▼
┌──────────────────┐      ┌──────────────────────┐
│ClaudeProcessManager│    │ SimulinkBridge       │
│(Java ProcessBuilder)│   │ (get_param/add_block)│
└──────────────────┘      └──────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────┐
│  Claude CLI: claude -p --output-format stream-json  │
└─────────────────────────────────────────────────────┘
```

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
