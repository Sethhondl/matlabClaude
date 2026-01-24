classdef Logger < handle
    %LOGGER Singleton logger for structured JSON-lines logging
    %   Provides application-wide logging with configurable verbosity,
    %   automatic file rotation, and session correlation support.
    %
    %   Usage:
    %       % Get the singleton instance
    %       logger = derivux.logging.Logger.getInstance();
    %
    %       % Log at different levels
    %       logger.info('ComponentName', 'event_name', struct('key', 'value'));
    %       logger.error('ComponentName', 'error_occurred', struct('error', err));
    %       logger.debug('ComponentName', 'debug_info');
    %       logger.trace('ComponentName', 'fine_grained_detail');
    %       logger.warn('ComponentName', 'warning_condition');
    %
    %       % Timed operations
    %       tic;
    %       % ... do work ...
    %       logger.infoTimed('Component', 'operation_complete', data, toc*1000);
    %
    %       % Configure logging
    %       logger.setLevel(derivux.logging.LogLevel.DEBUG);
    %       logger.enable();
    %       logger.disable();
    %
    %   See also: LogLevel, LogConfig, LogFormatter

    properties (Access = private)
        Config derivux.logging.LogConfig
        FileHandle = -1
        CurrentFilePath (1,1) string = ""
        WriteCount (1,1) double = 0
        LastRotationCheck (1,1) datetime = datetime('now')
    end

    properties (Constant, Access = private)
        % Check rotation every N writes
        ROTATION_CHECK_INTERVAL = 100
    end

    methods (Access = private)
        function obj = Logger()
            %LOGGER Private constructor for singleton pattern
            obj.Config = derivux.logging.LogConfig();
        end
    end

    methods (Static)
        function logger = getInstance()
            %GETINSTANCE Get or create the singleton Logger instance
            %
            %   Example:
            %       logger = derivux.logging.Logger.getInstance();

            persistent instance
            if isempty(instance) || ~isvalid(instance)
                instance = derivux.logging.Logger();
            end
            logger = instance;
        end

        function resetInstance()
            %RESETINSTANCE Reset the singleton instance (for testing)
            %   Forces creation of a new Logger on next getInstance() call.

            logger = derivux.logging.Logger.getInstance();
            logger.close();
            clear derivux.logging.Logger.getInstance;
        end
    end

    methods
        function delete(obj)
            %DELETE Destructor - close file handle
            obj.close();
        end

        %% Configuration Methods

        function configure(obj, settings)
            %CONFIGURE Apply settings from Settings object
            %   logger.configure(derivux.config.Settings.load())

            arguments
                obj
                settings
            end

            obj.Config.applySettings(settings);
        end

        function setLevel(obj, level)
            %SETLEVEL Set the minimum logging level
            %   logger.setLevel(derivux.logging.LogLevel.DEBUG)
            %   logger.setLevel('DEBUG')

            arguments
                obj
                level
            end

            if ischar(level) || isstring(level)
                level = derivux.logging.LogLevel.fromString(level);
            end
            obj.Config.Level = level;
        end

        function level = getLevel(obj)
            %GETLEVEL Get current logging level
            level = obj.Config.Level;
        end

        function setSessionId(obj, sessionId)
            %SETSESSIONID Set session ID for cross-component correlation
            %   logger.setSessionId('abc123')

            arguments
                obj
                sessionId (1,1) string
            end

            obj.Config.SessionId = sessionId;
            % Reset file path to regenerate with new session ID
            obj.Config.CachedLogFilePath = "";
            obj.close();  % Close old file, will open new one on next write
        end

        function sessionId = getSessionId(obj)
            %GETSESSIONID Get current session ID
            sessionId = obj.Config.SessionId;
        end

        function enable(obj)
            %ENABLE Enable logging
            obj.Config.Enabled = true;
        end

        function disable(obj)
            %DISABLE Disable logging
            obj.Config.Enabled = false;
        end

        function tf = isEnabled(obj)
            %ISENABLED Check if logging is enabled
            tf = obj.Config.Enabled;
        end

        function config = getConfig(obj)
            %GETCONFIG Get the current configuration object
            config = obj.Config;
        end

        function path = getLogFilePath(obj)
            %GETLOGFILEPATH Get the path to the current log file
            path = obj.Config.LogFilePath;
        end

        %% Logging Methods - Level-specific

        function error(obj, component, event, data, options)
            %ERROR Log an error-level message
            %   logger.error('Component', 'event_name')
            %   logger.error('Component', 'event_name', struct('key', 'value'))
            %   logger.error('Component', 'event_name', data, 'TraceId', 'abc')

            arguments
                obj
                component (1,1) string
                event (1,1) string
                data = struct()
                options.TraceId (1,1) string = ""
                options.StackTrace (1,1) string = ""
            end

            obj.log(derivux.logging.LogLevel.ERROR, component, event, data, ...
                'TraceId', options.TraceId, 'StackTrace', options.StackTrace);
        end

        function warn(obj, component, event, data, options)
            %WARN Log a warning-level message
            %   logger.warn('Component', 'event_name')

            arguments
                obj
                component (1,1) string
                event (1,1) string
                data = struct()
                options.TraceId (1,1) string = ""
            end

            obj.log(derivux.logging.LogLevel.WARN, component, event, data, ...
                'TraceId', options.TraceId);
        end

        function info(obj, component, event, data, options)
            %INFO Log an info-level message
            %   logger.info('Component', 'event_name')
            %   logger.info('Component', 'event_name', struct('count', 10))

            arguments
                obj
                component (1,1) string
                event (1,1) string
                data = struct()
                options.TraceId (1,1) string = ""
            end

            obj.log(derivux.logging.LogLevel.INFO, component, event, data, ...
                'TraceId', options.TraceId);
        end

        function debug(obj, component, event, data, options)
            %DEBUG Log a debug-level message
            %   logger.debug('Component', 'debug_info')

            arguments
                obj
                component (1,1) string
                event (1,1) string
                data = struct()
                options.TraceId (1,1) string = ""
            end

            obj.log(derivux.logging.LogLevel.DEBUG, component, event, data, ...
                'TraceId', options.TraceId);
        end

        function trace(obj, component, event, data, options)
            %TRACE Log a trace-level message (finest granularity)
            %   logger.trace('Component', 'stream_chunk')

            arguments
                obj
                component (1,1) string
                event (1,1) string
                data = struct()
                options.TraceId (1,1) string = ""
            end

            obj.log(derivux.logging.LogLevel.TRACE, component, event, data, ...
                'TraceId', options.TraceId);
        end

        %% Timed Logging Methods

        function errorTimed(obj, component, event, data, durationMs, options)
            %ERRORTIMED Log error with duration
            arguments
                obj
                component (1,1) string
                event (1,1) string
                data
                durationMs (1,1) double
                options.TraceId (1,1) string = ""
            end

            obj.log(derivux.logging.LogLevel.ERROR, component, event, data, ...
                'DurationMs', durationMs, 'TraceId', options.TraceId);
        end

        function warnTimed(obj, component, event, data, durationMs, options)
            %WARNTIMED Log warning with duration
            arguments
                obj
                component (1,1) string
                event (1,1) string
                data
                durationMs (1,1) double
                options.TraceId (1,1) string = ""
            end

            obj.log(derivux.logging.LogLevel.WARN, component, event, data, ...
                'DurationMs', durationMs, 'TraceId', options.TraceId);
        end

        function infoTimed(obj, component, event, data, durationMs, options)
            %INFOTIMED Log info with duration
            %   tic; doWork(); logger.infoTimed('Comp', 'done', data, toc*1000)
            arguments
                obj
                component (1,1) string
                event (1,1) string
                data
                durationMs (1,1) double
                options.TraceId (1,1) string = ""
            end

            obj.log(derivux.logging.LogLevel.INFO, component, event, data, ...
                'DurationMs', durationMs, 'TraceId', options.TraceId);
        end

        function debugTimed(obj, component, event, data, durationMs, options)
            %DEBUGTIMED Log debug with duration
            arguments
                obj
                component (1,1) string
                event (1,1) string
                data
                durationMs (1,1) double
                options.TraceId (1,1) string = ""
            end

            obj.log(derivux.logging.LogLevel.DEBUG, component, event, data, ...
                'DurationMs', durationMs, 'TraceId', options.TraceId);
        end

        function traceTimed(obj, component, event, data, durationMs, options)
            %TRACETIMED Log trace with duration
            arguments
                obj
                component (1,1) string
                event (1,1) string
                data
                durationMs (1,1) double
                options.TraceId (1,1) string = ""
            end

            obj.log(derivux.logging.LogLevel.TRACE, component, event, data, ...
                'DurationMs', durationMs, 'TraceId', options.TraceId);
        end

        %% Utility Methods

        function close(obj)
            %CLOSE Close the log file handle
            if obj.FileHandle ~= -1
                try
                    fclose(obj.FileHandle);
                catch
                    % Ignore errors on close
                end
                obj.FileHandle = -1;
            end
        end

        function flush(obj)
            %FLUSH Flush buffered writes to disk
            if obj.FileHandle ~= -1
                try
                    % MATLAB fwrite is typically unbuffered, but this ensures it
                    fclose(obj.FileHandle);
                    obj.FileHandle = -1;
                catch
                    % Ignore errors
                end
            end
        end
    end

    methods (Access = private)
        function log(obj, level, component, event, data, options)
            %LOG Core logging method

            arguments
                obj
                level derivux.logging.LogLevel
                component (1,1) string
                event (1,1) string
                data = struct()
                options.DurationMs double = []
                options.TraceId (1,1) string = ""
                options.StackTrace (1,1) string = ""
            end

            % Skip if disabled or below threshold
            if ~obj.Config.Enabled || level < obj.Config.Level
                return;
            end

            try
                % Build log entry
                entry = derivux.logging.LogFormatter.createEntry(level, component, event, data, ...
                    'SessionId', obj.Config.SessionId, ...
                    'DurationMs', options.DurationMs, ...
                    'TraceId', options.TraceId, ...
                    'StackTrace', options.StackTrace);

                % Convert to JSON
                jsonStr = derivux.logging.LogFormatter.toJson(entry);

                % Console output if enabled
                if obj.Config.ConsoleOutput
                    fprintf('[%s] %s.%s: %s\n', string(level), component, event, jsonStr);
                end

                % Write to file
                obj.writeToFile(jsonStr);

            catch ME
                % Log failures shouldn't crash the application
                if obj.Config.ConsoleOutput
                    fprintf(2, 'Logger error: %s\n', ME.message);
                end
            end
        end

        function writeToFile(obj, jsonStr)
            %WRITETOFILE Write JSON string to log file

            % Ensure file is open
            if obj.FileHandle == -1
                obj.openFile();
            end

            if obj.FileHandle == -1
                return;  % Failed to open file
            end

            % Write line
            fprintf(obj.FileHandle, '%s\n', jsonStr);

            % Flush if configured
            if obj.Config.FlushImmediately
                % Force write to disk
            end

            % Periodic rotation check
            obj.WriteCount = obj.WriteCount + 1;
            if mod(obj.WriteCount, obj.ROTATION_CHECK_INTERVAL) == 0
                obj.checkRotation();
            end
        end

        function openFile(obj)
            %OPENFILE Open log file for writing

            filePath = obj.Config.LogFilePath;

            % Ensure directory exists
            [dirPath, ~, ~] = fileparts(filePath);
            if ~isfolder(dirPath)
                try
                    mkdir(dirPath);
                catch ME
                    warning('Logger:DirectoryCreateFailed', ...
                        'Failed to create log directory: %s', ME.message);
                    return;
                end
            end

            % Open file in append mode
            try
                obj.FileHandle = fopen(filePath, 'a', 'n', 'UTF-8');
                if obj.FileHandle == -1
                    warning('Logger:FileOpenFailed', ...
                        'Failed to open log file: %s', filePath);
                else
                    obj.CurrentFilePath = filePath;
                end
            catch ME
                warning('Logger:FileOpenFailed', ...
                    'Failed to open log file: %s', ME.message);
            end
        end

        function checkRotation(obj)
            %CHECKROTATION Check if log rotation is needed

            if obj.CurrentFilePath == "" || ~isfile(obj.CurrentFilePath)
                return;
            end

            try
                fileInfo = dir(obj.CurrentFilePath);
                if ~isempty(fileInfo) && fileInfo.bytes > obj.Config.MaxFileSize
                    obj.rotateFiles();
                end
            catch
                % Ignore rotation check errors
            end
        end

        function rotateFiles(obj)
            %ROTATEFILES Rotate log files

            % Close current file
            obj.close();

            [dirPath, name, ext] = fileparts(obj.CurrentFilePath);

            % Delete oldest files beyond limit
            pattern = fullfile(dirPath, sprintf('%s.*%s', name, ext));
            existingFiles = dir(pattern);

            if numel(existingFiles) >= obj.Config.MaxFiles
                % Sort by date and delete oldest
                [~, sortIdx] = sort([existingFiles.datenum]);
                for i = 1:(numel(existingFiles) - obj.Config.MaxFiles + 1)
                    oldFile = fullfile(dirPath, existingFiles(sortIdx(i)).name);
                    try
                        delete(oldFile);
                    catch
                        % Ignore deletion errors
                    end
                end
            end

            % Rename current file with rotation number
            rotationNum = numel(existingFiles) + 1;
            rotatedPath = fullfile(dirPath, sprintf('%s.%d%s', name, rotationNum, ext));
            try
                movefile(obj.CurrentFilePath, rotatedPath);
            catch
                % If rename fails, just continue with current file
            end

            % Generate new session ID for new file
            obj.Config.SessionId = obj.Config.generateSessionId();
            obj.Config.CachedLogFilePath = "";

            % Open new file
            obj.openFile();
        end
    end
end
