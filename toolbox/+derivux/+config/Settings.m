classdef Settings < handle
    %SETTINGS Configuration settings for Derivux MATLAB integration
    %
    %   This class manages persistent settings for the Derivux add-on.
    %
    %   Example:
    %       settings = derivux.config.Settings.load();
    %       settings.theme = 'light';
    %       settings.save();

    properties
        % UI Settings
        theme = 'dark'                      % 'dark' or 'light'
        fontSize = 14                        % Chat font size

        % Context Settings
        maxWorkspaceVariables = 50          % Max variables to include

        % Execution Settings
        codeExecutionMode = 'prompt'        % 'auto', 'prompt', 'disabled'
        executionTimeout = 30               % Timeout in seconds
        allowSystemCommands = false         % Allow system(), !, etc.
        allowDestructiveOps = false         % Allow delete, rmdir, etc.

        % Claude Settings
        model = 'claude-sonnet-4-5-20250514'  % Claude model ID
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

        % Display Settings
        headlessMode = true                 % Suppress figure/model pop-up windows

        % Timeout Settings
        maxPollingDuration = 600            % Max total polling duration in seconds (10 min ceiling)

        % Authentication Settings
        authMethod = 'subscription'         % 'subscription' or 'api_key'

        % Safety Settings
        allowBypassModeCycling = false      % Allow cycling to bypass mode via status bar/keyboard
    end

    properties (Constant, Access = private)
        SETTINGS_FILE = 'derivux_settings.json'
        VALID_MODELS = {...
            'claude-sonnet-4-5-20250514', ...
            'claude-opus-4-5-20250514', ...
            'claude-haiku-4-5-20250514'}
    end

    methods
        function set.model(obj, value)
            %SET.MODEL Validate and set model property
            if ~ismember(value, obj.VALID_MODELS)
                error('Settings:InvalidModel', ...
                    'Invalid model: %s. Valid models are: %s', ...
                    value, strjoin(obj.VALID_MODELS, ', '));
            end
            obj.model = value;
        end

        function set.authMethod(obj, value)
            %SET.AUTHMETHOD Validate and set authentication method
            validMethods = {'subscription', 'api_key'};
            if ~ismember(value, validMethods)
                error('Settings:InvalidAuthMethod', ...
                    'Invalid auth method: %s. Valid methods are: %s', ...
                    value, strjoin(validMethods, ', '));
            end
            obj.authMethod = value;
        end

        function set.codeExecutionMode(obj, value)
            %SET.CODEEXECUTIONMODE Validate and set code execution mode
            %
            %   Valid modes:
            %   - 'plan': Interview/planning mode - no code execution
            %   - 'prompt': Normal mode - prompts before each code execution
            %   - 'auto': Auto mode - executes code automatically (security blocks active)
            %   - 'bypass': DANGEROUS - removes all restrictions including blocked functions
            %
            %   Legacy mode 'disabled' is mapped to 'plan' for backwards compatibility
            validModes = {'plan', 'prompt', 'auto', 'bypass'};

            % Handle legacy 'disabled' mode by mapping to 'plan'
            if strcmp(value, 'disabled')
                value = 'plan';
            end

            if ~ismember(value, validModes)
                error('Settings:InvalidExecutionMode', ...
                    'Invalid execution mode: %s. Valid modes are: %s', ...
                    value, strjoin(validModes, ', '));
            end
            obj.codeExecutionMode = value;
        end

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

            defaultSettings = derivux.config.Settings();
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

            settings = derivux.config.Settings();
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
            path = fullfile(prefDir, 'Derivux', 'derivux_settings.json');
        end
    end
end
