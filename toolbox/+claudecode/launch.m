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
%   See also: claudecode.ClaudeCodeApp

    app = claudecode.ClaudeCodeApp.getInstance();
    app.launch();

    if nargout == 0
        clear app
    end
end
