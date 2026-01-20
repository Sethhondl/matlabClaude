classdef Settings < handle
    %SETTINGS Configuration settings for Claude Code MATLAB integration
    %
    %   This class manages persistent settings for the Claude Code add-on.
    %
    %   Example:
    %       settings = claudecode.config.Settings.load();
    %       settings.theme = 'light';
    %       settings.save();

    properties
        % UI Settings
        theme = 'dark'                      % 'dark' or 'light'
        fontSize = 14                        % Chat font size

        % Context Settings
        autoIncludeWorkspace = false        % Auto-include workspace in prompts
        autoIncludeSimulink = false         % Auto-include Simulink model
        maxWorkspaceVariables = 50          % Max variables to include

        % Execution Settings
        codeExecutionMode = 'prompt'        % 'auto', 'prompt', 'disabled'
        executionTimeout = 30               % Timeout in seconds
        allowSystemCommands = false         % Allow system(), !, etc.
        allowDestructiveOps = false         % Allow delete, rmdir, etc.

        % Claude Settings
        claudePath = 'claude'               % Path to Claude CLI
        defaultAllowedTools = {'Edit', 'Write', 'Read', 'Bash', 'Glob', 'Grep'}

        % History Settings
        maxHistoryLength = 100              % Max messages to keep
        saveHistory = true                  % Persist chat history

        % Logging Settings
        loggingEnabled = true               % Master switch for logging
        logLevel = 'INFO'                   % ERROR, WARN, INFO, DEBUG, TRACE
        logDirectory = ''                   % Empty = default logs/ in project
        logSensitiveData = true             % Include full messages/code for reconstruction
        logMaxFileSize = 10485760           % 10 MB rotation threshold
        logMaxFiles = 10                    % Keep last N log files
    end

    properties (Constant, Access = private)
        SETTINGS_FILE = 'claude_code_settings.json'
    end

    methods
        function save(obj)
            %SAVE Save settings to file

            settingsPath = obj.getSettingsPath();

            % Convert to struct for JSON
            s = struct();
            props = properties(obj);
            for i = 1:length(props)
                propName = props{i};
                s.(propName) = obj.(propName);
            end

            % Ensure directory exists
            settingsDir = fileparts(settingsPath);
            if ~exist(settingsDir, 'dir')
                mkdir(settingsDir);
            end

            % Write JSON
            jsonStr = jsonencode(s, 'PrettyPrint', true);
            fid = fopen(settingsPath, 'w');
            if fid ~= -1
                fprintf(fid, '%s', jsonStr);
                fclose(fid);
            end
        end

        function reset(obj)
            %RESET Reset to default settings

            defaultSettings = claudecode.config.Settings();
            props = properties(obj);

            for i = 1:length(props)
                propName = props{i};
                obj.(propName) = defaultSettings.(propName);
            end
        end
    end

    methods (Static)
        function settings = load()
            %LOAD Load settings from file or create defaults

            settings = claudecode.config.Settings();
            settingsPath = settings.getSettingsPath();

            if exist(settingsPath, 'file')
                try
                    jsonStr = fileread(settingsPath);
                    s = jsondecode(jsonStr);

                    % Apply loaded values
                    props = properties(settings);
                    fields = fieldnames(s);

                    for i = 1:length(fields)
                        fieldName = fields{i};
                        if ismember(fieldName, props)
                            settings.(fieldName) = s.(fieldName);
                        end
                    end

                catch ME
                    warning('Settings:LoadError', ...
                        'Could not load settings: %s', ME.message);
                end
            end
        end
    end

    methods (Access = private)
        function path = getSettingsPath(~)
            %GETSETTINGSPATH Get path to settings file

            % Use MATLAB preferences directory
            prefDir = prefdir;
            path = fullfile(prefDir, 'ClaudeCode', 'claude_code_settings.json');
        end
    end
end
