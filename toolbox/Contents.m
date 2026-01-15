% Claude Code for MATLAB
% Version 1.0.0 (R2025b)
%
% Integrates Claude Code AI assistant into MATLAB and Simulink for
% mechanical engineers and developers.
%
% GETTING STARTED
%   claudecode.launch     - Open Claude Code assistant panel
%
% MAIN CLASSES
%   claudecode.ClaudeCodeApp           - Main application class
%   claudecode.ChatUIController        - Chat interface controller
%   claudecode.ClaudeProcessManager    - Claude CLI communication
%   claudecode.CodeExecutor            - Safe code execution
%   claudecode.SimulinkBridge          - Simulink model integration
%   claudecode.WorkspaceContextProvider - Workspace context extraction
%
% CONFIGURATION
%   claudecode.config.Settings         - Application settings
%   claudecode.config.ExecutionPolicy  - Code execution policy
%
% FEATURES
%   - Chat interface with Claude in a side panel
%   - Execute MATLAB code from Claude's responses
%   - Automatic workspace context inclusion
%   - Simulink model introspection and modification
%   - GitHub integration via Claude Code CLI
%
% REQUIREMENTS
%   - MATLAB R2025b or later
%   - Claude Code CLI installed and in PATH
%     Install from: https://claude.ai/code
%
% EXAMPLES
%   % Launch the assistant
%   claudecode.launch()
%
%   % Programmatic access
%   app = claudecode.ClaudeCodeApp();
%   app.launch();
%
% See also: claudecode.launch, claudecode.ClaudeCodeApp

% Copyright 2025
% License: MIT
