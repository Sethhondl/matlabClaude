# CLAUDE.md - Project Context for Claude Code

## Overview

**Claude Code for MATLAB** - A MATLAB toolbox integrating Claude AI into MATLAB and Simulink.

**Target users:** Mechanical engineers and MATLAB developers working on control systems and simulation.

## Quick Start

```matlab
claudecode.launch()
```

## Project Structure

```
matlabClaude/
├── toolbox/+claudecode/    # MATLAB classes (ClaudeCodeApp, CodeExecutor, SimulinkBridge)
├── python/claudecode/      # Python backend (agent.py, matlab_tools.py, simulink_tools.py)
├── scripts/                # Helper scripts (worktree.sh)
├── tests/                  # MATLAB unit tests
└── logs/                   # Runtime logs
```

## Development

### Requirements

- MATLAB R2025b+
- Python 3.10+
- Claude Code CLI (`claude --version`)

### Running Tests

```matlab
results = runAllTests();
results = runAllTests('Verbose', true);
```

### Security

The CodeExecutor blocks: `system`, `eval`, `evalin`, `delete`, `rmdir`, and Java/Python escape hatches.

---

## Git Workflow (Worktrees)

This project uses **git worktrees** for parallel feature development. Each feature gets its own directory—no stashing or WIP commits needed when switching tasks.

### Helper Script (Recommended)

```bash
./scripts/worktree.sh new feature/voice-input     # Create new feature
./scripts/worktree.sh list                         # List all worktrees
./scripts/worktree.sh remove feature/voice-input  # Remove after merge
./scripts/worktree.sh prune                        # Clean stale refs
```

### Manual Commands

```bash
# Create worktree with new branch
git worktree add ../matlabClaude-worktrees/feature-name -b feature/name origin/main

# Remove worktree after merge
git worktree remove ../matlabClaude-worktrees/feature-name
git branch -d feature/name
```

### Branch Prefixes

| Prefix | Purpose |
|--------|---------|
| `feature/` | New functionality |
| `bugfix/` | Bug fixes |
| `experiment/` | Exploratory work |
| `refactor/` | Code improvements |

### Commit Messages

Format: `<Type>: <short description>`

Types: `Add`, `Fix`, `Update`, `Refactor`, `Remove`, `Test`, `Docs`
