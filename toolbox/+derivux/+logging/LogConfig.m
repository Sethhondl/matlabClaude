classdef LogConfig < handle
    %LOGCONFIG Configuration settings for the logging system
    %   Holds all configuration options for Logger instances including
    %   output paths, verbosity levels, rotation settings, and formatting.
    %
    %   Example:
    %       config = derivux.logging.LogConfig();
    %       config.Level = derivux.logging.LogLevel.DEBUG;
    %       config.LogDirectory = '/custom/logs';
    %
    %   See also: Logger, LogLevel

    properties
        % Logging enabled/disabled
        Enabled (1,1) logical = true

        % Minimum level to log (messages below this are ignored)
        Level (1,1) derivux.logging.LogLevel = derivux.logging.LogLevel.INFO

        % Directory for log files (empty = default logs/ in project)
        LogDirectory (1,1) string = ""

        % Whether to include sensitive data (full messages, code) for reconstruction
        LogSensitiveData (1,1) logical = true

        % Maximum file size before rotation (bytes)
        MaxFileSize (1,1) double = 10485760  % 10 MB

        % Maximum number of rotated files to keep
        MaxFiles (1,1) double = 10

        % Session ID for correlation across components
        SessionId (1,1) string = ""

        % Include stack trace in log entries
        IncludeStackTrace (1,1) logical = false

        % Console output (for debugging the logger itself)
        ConsoleOutput (1,1) logical = false

        % Flush after each write
        FlushImmediately (1,1) logical = true
    end

    properties (Dependent)
        % Full path to log file
        LogFilePath
    end

    properties (Access = private)
        CachedLogFilePath (1,1) string = ""
    end

    methods
        function obj = LogConfig()
            %LOGCONFIG Create a new logging configuration
            obj.SessionId = obj.generateSessionId();
        end

        function path = get.LogFilePath(obj)
            %GET.LOGFILEPATH Get the full path to the log file

            if obj.CachedLogFilePath ~= ""
                path = obj.CachedLogFilePath;
                return;
            end

            % Determine log directory
            if obj.LogDirectory == ""
                % Default to logs/ in project root
                logDir = obj.getDefaultLogDirectory();
            else
                logDir = obj.LogDirectory;
            end

            % Ensure directory exists
            if ~isfolder(logDir)
                mkdir(logDir);
            end

            % Create filename with session ID
            filename = sprintf('matlab_%s.jsonl', obj.SessionId);
            path = fullfile(logDir, filename);
            obj.CachedLogFilePath = path;
        end

        function reset(obj)
            %RESET Reset configuration to defaults
            obj.Enabled = true;
            obj.Level = derivux.logging.LogLevel.INFO;
            obj.LogDirectory = "";
            obj.LogSensitiveData = true;
            obj.MaxFileSize = 10485760;
            obj.MaxFiles = 10;
            obj.SessionId = obj.generateSessionId();
            obj.IncludeStackTrace = false;
            obj.ConsoleOutput = false;
            obj.FlushImmediately = true;
            obj.CachedLogFilePath = "";
        end

        function applySettings(obj, settings)
            %APPLYSETTINGS Apply settings from Settings object
            %   config.applySettings(derivux.config.Settings.load())

            arguments
                obj
                settings
            end

            if isprop(settings, 'loggingEnabled')
                obj.Enabled = settings.loggingEnabled;
            end

            if isprop(settings, 'logLevel')
                obj.Level = derivux.logging.LogLevel.fromString(settings.logLevel);
            end

            if isprop(settings, 'logDirectory') && settings.logDirectory ~= ""
                obj.LogDirectory = settings.logDirectory;
            end

            if isprop(settings, 'logSensitiveData')
                obj.LogSensitiveData = settings.logSensitiveData;
            end

            if isprop(settings, 'logMaxFileSize')
                obj.MaxFileSize = settings.logMaxFileSize;
            end

            if isprop(settings, 'logMaxFiles')
                obj.MaxFiles = settings.logMaxFiles;
            end

            % Clear cached path to regenerate
            obj.CachedLogFilePath = "";
        end
    end

    methods (Access = private)
        function sessionId = generateSessionId(~)
            %GENERATESESSIONID Generate a unique session identifier
            %   Format: YYYYMMDD_HHMMSS_XXXX where XXXX is random hex

            timestamp = datetime('now', 'Format', 'yyyyMMdd_HHmmss');
            randomPart = dec2hex(randi([0, 65535]), 4);
            sessionId = sprintf('%s_%s', char(timestamp), randomPart);
        end

        function logDir = getDefaultLogDirectory(~)
            %GETDEFAULTLOGDIRECTORY Get default log directory

            % Try to find project root by looking for CLAUDE.md
            currentDir = fileparts(mfilename('fullpath'));

            % Navigate up from +logging to project root
            % +logging -> +derivux -> toolbox -> project root
            projectRoot = fullfile(currentDir, '..', '..', '..', '..');
            projectRoot = char(java.io.File(projectRoot).getCanonicalPath());

            % Check if CLAUDE.md exists to verify we found project root
            if isfile(fullfile(projectRoot, 'CLAUDE.md'))
                logDir = fullfile(projectRoot, 'logs');
            else
                % Fallback to temp directory
                logDir = fullfile(tempdir, 'derivux_logs');
            end
        end
    end
end
