# CLAUDE.md - Project Context for Claude Code

## Project Overview

**Claude Code for MATLAB** - A MATLAB toolbox that integrates Claude Code AI assistant into MATLAB and Simulink, designed for mechanical engineers and developers.

### Goals

1. Provide a seamless chat interface within MATLAB for AI assistance
2. Enable safe code execution from Claude's responses
3. Integrate with Simulink for model reading/modification
4. Leverage Claude Code's built-in git capabilities
5. Support workspace context awareness for better assistance

### Target Users

- Mechanical engineers using MATLAB/Simulink
- MATLAB developers wanting AI-assisted coding
- Teams working on control systems and simulation

## Project Structure

```
matlabClaude/
├── toolbox/              # MATLAB package (+claudecode namespace)
│   ├── +claudecode/      # Main MATLAB classes
│   └── chat_ui/          # Web UI (HTML/CSS/JS)
├── python/               # Python backend (Claude Agent SDK)
│   └── claudecode/       # Python package
│       ├── agents/       # Custom agent implementations
│       ├── matlab_tools.py
│       ├── simulink_tools.py
│       └── bridge.py
├── tests/                # MATLAB unit tests
└── logs/                 # Runtime logs
```

## Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| ClaudeCodeApp.m | toolbox/+claudecode/ | Main entry point |
| ClaudeProcessManager.m | toolbox/+claudecode/ | CLI communication |
| CodeExecutor.m | toolbox/+claudecode/ | Safe code execution |
| SimulinkBridge.m | toolbox/+claudecode/ | Simulink integration |
| agent.py | python/claudecode/ | Claude Agent SDK integration |
| matlab_tools.py | python/claudecode/ | MATLAB tool definitions |

## Development Guidelines

### Requirements

- MATLAB R2025b or later
- Python 3.10+
- Claude Code CLI installed (`claude --version`)

### Running the Application

```matlab
claudecode.launch()
```

### Running Tests

```matlab
cd tests
results = runAllTests();
results = runAllTests('Verbose', true);  % verbose output
```

### Security Considerations

The CodeExecutor blocks dangerous operations:
- System commands (`system`, `dos`, `unix`, `!`)
- Eval variants (`eval`, `evalin`, `evalc`, `feval`)
- Destructive operations (`delete`, `rmdir`)
- Java/Python escape hatches

---

## Git Workflow

### Branch Naming Convention

| Prefix | Purpose | Example |
|--------|---------|---------|
| `feature/` | New functionality | `feature/voice-input` |
| `bugfix/` | Bug fixes | `bugfix/simulink-crash` |
| `experiment/` | Exploratory work | `experiment/new-ui` |
| `refactor/` | Code improvements | `refactor/process-manager` |

### Feature Branch Workflow

**Starting a new feature:**
```bash
git checkout main
git pull origin main
git checkout -b feature/your-feature-name
```

**Working on the feature:**
```bash
# Make changes, commit often
git add .
git commit -m "Add feature component X"

# Keep feature branch updated with main
git fetch origin
git rebase origin/main
```

**Switching between features:**
```bash
# Save current work
git add .
git commit -m "WIP: description"

# Switch to another feature
git checkout feature/other-feature

# Or create a new one
git checkout main && git checkout -b feature/new-thing
```

**Completing a feature:**
```bash
git checkout main
git pull origin main
git merge feature/your-feature-name
git push origin main
git branch -d feature/your-feature-name
```

### Quick Reference

```bash
# List all branches
git branch -a

# See what's different from main
git diff main..HEAD

# Stash work temporarily
git stash
git stash pop

# Discard local changes
git checkout -- .
```

### Commit Message Format

```
<type>: <short description>

<optional body with more detail>
```

Types: `Add`, `Fix`, `Update`, `Refactor`, `Remove`, `Test`, `Docs`

Examples:
- `Add voice input support for chat interface`
- `Fix Simulink model parsing for nested subsystems`
- `Update Python bridge for R2025b compatibility`

---

## Current State

- Main branch: stable, production-ready
- Remote: origin (GitHub)
- Architecture: MATLAB frontend + Python backend via Claude Agent SDK
