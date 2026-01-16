function app = launch()
%LAUNCH Launch the Claude Code assistant
%
%   CLAUDECODE.LAUNCH() opens the Claude Code assistant panel.
%
%   app = CLAUDECODE.LAUNCH() returns the app instance.
%
%   Example:
%       claudecode.launch()
%
%   See also: claudecode.ClaudeCodeApp, claudecode.configurePython

    % Auto-configure Python 3.10+ for Claude Agent SDK
    claudecode.configurePython();

    app = claudecode.ClaudeCodeApp.getInstance();
    app.launch();

    if nargout == 0
        clear app
    end
end
