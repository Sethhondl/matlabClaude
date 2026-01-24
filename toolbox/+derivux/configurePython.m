function configured = configurePython()
%CONFIGUREPYTHON Configure Python environment for Claude Code
%
%   CONFIGUREPYTHON() ensures Python 3.10+ is configured for MATLAB.
%   Automatically finds and configures the best available Python version.
%
%   configured = CONFIGUREPYTHON() returns true if successfully configured.
%
%   The function searches for Python in this order:
%   1. Homebrew Python 3.13, 3.12, 3.11, 3.10
%   2. System Python 3.10+
%
%   See also: pyenv, claudecode.launch

    configured = false;

    % Check current Python environment
    pe = pyenv;

    % If Python is already loaded, check version
    if pe.Status == "Loaded"
        ver = str2double(pe.Version);
        if ver >= 3.10
            configured = true;
            return
        else
            warning('claudecode:pythonVersion', ...
                ['Python %s is loaded but Claude Agent SDK requires 3.10+.\n' ...
                 'Restart MATLAB and run claudecode.launch() again to auto-configure.'], ...
                pe.Version);
            return
        end
    end

    % Python not loaded yet - find best version
    % Prefer 3.12 (fully supported by MATLAB R2025b) over 3.13
    pythonPaths = {
        '/usr/local/opt/python@3.12/bin/python3.12'
        '/opt/homebrew/opt/python@3.12/bin/python3.12'
        '/usr/local/bin/python3.12'
        '/usr/local/opt/python@3.11/bin/python3.11'
        '/opt/homebrew/opt/python@3.11/bin/python3.11'
        '/usr/local/bin/python3.11'
        '/usr/local/opt/python@3.10/bin/python3.10'
        '/opt/homebrew/opt/python@3.10/bin/python3.10'
        '/usr/local/bin/python3.10'
    };

    for i = 1:length(pythonPaths)
        pythonPath = pythonPaths{i};
        if isfile(pythonPath)
            try
                pyenv('Version', pythonPath);
                pe = pyenv;
                fprintf('Configured Python %s: %s\n', pe.Version, pe.Executable);
                configured = true;
                return
            catch ME
                % Try next path
                continue
            end
        end
    end

    % No suitable Python found
    warning('claudecode:noPython', ...
        ['Could not find Python 3.10+.\n' ...
         'Install with: brew install python@3.13\n' ...
         'Then install SDK: /usr/local/opt/python@3.13/bin/python3.13 -m pip install claude-agent-sdk']);
end
