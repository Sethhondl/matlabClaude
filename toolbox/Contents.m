% Derivux for MATLAB
% Version 1.0.0 (R2025b)
%
% Integrates Claude AI assistant into MATLAB and Simulink for
% mechanical engineers and developers.
%
% GETTING STARTED
%   derivux.launch     - Open Derivux assistant panel
%
% MAIN CLASSES
%   derivux.DerivuxApp             - Main application class
%   derivux.ChatUIController       - Chat interface controller
%   derivux.ClaudeProcessManager   - Claude CLI communication
%   derivux.CodeExecutor           - Safe code execution
%   derivux.SimulinkBridge         - Simulink model integration
%   derivux.WorkspaceContextProvider - Workspace context extraction
%
% CONFIGURATION
%   derivux.config.Settings         - Application settings
%   derivux.config.ExecutionPolicy  - Code execution policy
%
% FEATURES
%   - Chat interface with Claude in a side panel
%   - Execute MATLAB code from Claude's responses
%   - Automatic workspace context inclusion
%   - Simulink model introspection and modification
%   - GitHub integration via Claude CLI
%
% REQUIREMENTS
%   - MATLAB R2025b or later
%   - Claude CLI installed and in PATH
%     Install from: https://claude.ai/code
%
% EXAMPLES
%   % Launch the assistant
%   derivux.launch()
%
%   % Programmatic access
%   app = derivux.DerivuxApp();
%   app.launch();
%
% See also: derivux.launch, derivux.DerivuxApp

% Copyright 2025
% License: MIT
