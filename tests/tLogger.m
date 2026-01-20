classdef tLogger < matlab.unittest.TestCase
    %TLOGGER Unit tests for the logging system
    %
    %   These tests verify the functionality of the structured JSON-lines
    %   logging system including Logger, LogLevel, LogConfig, and LogFormatter.
    %
    %   Run with:
    %       results = runtests('tLogger');

    properties (TestParameter)
        LogLevelStr = {'ERROR', 'WARN', 'INFO', 'DEBUG', 'TRACE'}
    end

    properties
        TestLogDir
        Logger
        OriginalLogFilePath
    end

    methods (TestClassSetup)
        function setupTestEnvironment(testCase)
            % Create a temporary directory for test logs
            testCase.TestLogDir = fullfile(tempdir, sprintf('claudecode_test_logs_%s', datestr(now, 'yyyymmdd_HHMMSS')));
            mkdir(testCase.TestLogDir);
        end
    end

    methods (TestClassTeardown)
        function teardownTestEnvironment(testCase)
            % Clean up test log directory
            if isfolder(testCase.TestLogDir)
                rmdir(testCase.TestLogDir, 's');
            end
        end
    end

    methods (TestMethodSetup)
        function setupTest(testCase)
            % Reset the logger singleton for each test
            claudecode.logging.Logger.resetInstance();
            testCase.Logger = claudecode.logging.Logger.getInstance();

            % Configure to use test directory
            config = testCase.Logger.getConfig();
            config.LogDirectory = testCase.TestLogDir;
            config.FlushImmediately = true;
            testCase.Logger.enable();
            testCase.Logger.setLevel('TRACE');  % Enable all levels for testing
        end
    end

    methods (TestMethodTeardown)
        function teardownTest(testCase)
            % Close logger to release file handles
            if ~isempty(testCase.Logger) && isvalid(testCase.Logger)
                testCase.Logger.close();
            end
        end
    end

    %% LogLevel Tests

    methods (Test)
        function testLogLevelValues(testCase)
            % Verify log level numeric values
            testCase.verifyEqual(uint8(claudecode.logging.LogLevel.TRACE), uint8(5));
            testCase.verifyEqual(uint8(claudecode.logging.LogLevel.DEBUG), uint8(10));
            testCase.verifyEqual(uint8(claudecode.logging.LogLevel.INFO), uint8(20));
            testCase.verifyEqual(uint8(claudecode.logging.LogLevel.WARN), uint8(30));
            testCase.verifyEqual(uint8(claudecode.logging.LogLevel.ERROR), uint8(40));
        end

        function testLogLevelFromString(testCase, LogLevelStr)
            % Test parsing log levels from strings
            level = claudecode.logging.LogLevel.fromString(LogLevelStr);
            testCase.verifyClass(level, 'claudecode.logging.LogLevel');
        end

        function testLogLevelFromStringCaseInsensitive(testCase)
            % Test case-insensitive parsing
            level1 = claudecode.logging.LogLevel.fromString('info');
            level2 = claudecode.logging.LogLevel.fromString('INFO');
            level3 = claudecode.logging.LogLevel.fromString('Info');

            testCase.verifyEqual(level1, level2);
            testCase.verifyEqual(level2, level3);
        end

        function testLogLevelFromStringInvalid(testCase)
            % Test invalid log level defaults to INFO
            level = claudecode.logging.LogLevel.fromString('INVALID');
            testCase.verifyEqual(level, claudecode.logging.LogLevel.INFO);
        end

        function testLogLevelIsValidLevel(testCase)
            testCase.verifyTrue(claudecode.logging.LogLevel.isValidLevel('INFO'));
            testCase.verifyTrue(claudecode.logging.LogLevel.isValidLevel('error'));
            testCase.verifyFalse(claudecode.logging.LogLevel.isValidLevel('INVALID'));
        end
    end

    %% LogConfig Tests

    methods (Test)
        function testLogConfigDefaults(testCase)
            config = claudecode.logging.LogConfig();

            testCase.verifyTrue(config.Enabled);
            testCase.verifyEqual(config.Level, claudecode.logging.LogLevel.INFO);
            testCase.verifyTrue(config.LogSensitiveData);
            testCase.verifyEqual(config.MaxFileSize, 10485760);
            testCase.verifyEqual(config.MaxFiles, 10);
        end

        function testLogConfigSessionIdGenerated(testCase)
            config = claudecode.logging.LogConfig();

            % Session ID should be non-empty and match expected format
            testCase.verifyNotEmpty(config.SessionId);
            testCase.verifyTrue(strlength(config.SessionId) > 10);
        end

        function testLogConfigReset(testCase)
            config = claudecode.logging.LogConfig();

            % Modify settings
            config.Enabled = false;
            config.Level = claudecode.logging.LogLevel.ERROR;
            config.MaxFileSize = 1000;

            % Reset
            config.reset();

            % Verify defaults restored
            testCase.verifyTrue(config.Enabled);
            testCase.verifyEqual(config.Level, claudecode.logging.LogLevel.INFO);
            testCase.verifyEqual(config.MaxFileSize, 10485760);
        end
    end

    %% LogFormatter Tests

    methods (Test)
        function testLogFormatterToJson(testCase)
            data = struct('key', 'value', 'number', 42);
            jsonStr = claudecode.logging.LogFormatter.toJson(data);

            testCase.verifyTrue(contains(jsonStr, '"key"'));
            testCase.verifyTrue(contains(jsonStr, '"value"'));
            testCase.verifyTrue(contains(jsonStr, '42'));
        end

        function testLogFormatterIsoTimestamp(testCase)
            ts = claudecode.logging.LogFormatter.isoTimestamp();

            % Should match ISO 8601 format with microseconds
            testCase.verifyTrue(contains(ts, 'T'));
            testCase.verifyTrue(endsWith(ts, 'Z'));
            testCase.verifyGreaterThan(strlength(ts), 20);
        end

        function testLogFormatterCreateEntry(testCase)
            entry = claudecode.logging.LogFormatter.createEntry(...
                claudecode.logging.LogLevel.INFO, ...
                'TestComponent', ...
                'test_event', ...
                struct('data_key', 'data_value'), ...
                'SessionId', 'test_session', ...
                'DurationMs', 123.45, ...
                'TraceId', 'trace_001');

            testCase.verifyEqual(entry.level, 'INFO');
            testCase.verifyEqual(entry.component, 'TestComponent');
            testCase.verifyEqual(entry.event, 'test_event');
            testCase.verifyEqual(entry.session_id, 'test_session');
            testCase.verifyEqual(entry.duration_ms, 123.45);
            testCase.verifyEqual(entry.trace_id, 'trace_001');
            testCase.verifyTrue(isfield(entry, 'ts'));
            testCase.verifyTrue(isfield(entry.data, 'data_key'));
        end

        function testLogFormatterSanitizeData(testCase)
            % Test sanitization of various types
            data = struct(...
                'str', 'hello', ...
                'num', 42, ...
                'nan_val', NaN, ...
                'inf_val', Inf, ...
                'bool', true);

            sanitized = claudecode.logging.LogFormatter.sanitizeData(data);

            testCase.verifyEqual(sanitized.str, "hello");
            testCase.verifyEqual(sanitized.num, 42);
            testCase.verifyEqual(sanitized.nan_val, "NaN");
            testCase.verifyEqual(sanitized.inf_val, "Inf");
            testCase.verifyTrue(sanitized.bool);
        end

        function testLogFormatterTruncateString(testCase)
            longStr = repmat('a', 1, 20000);
            truncated = claudecode.logging.LogFormatter.truncateString(longStr, 100);

            testCase.verifyLessThanOrEqual(strlength(truncated), 100);
            testCase.verifyTrue(endsWith(truncated, '...[truncated]'));
        end
    end

    %% Logger Singleton Tests

    methods (Test)
        function testLoggerIsSingleton(testCase)
            logger1 = claudecode.logging.Logger.getInstance();
            logger2 = claudecode.logging.Logger.getInstance();

            testCase.verifySameHandle(logger1, logger2);
        end

        function testLoggerConfiguration(testCase)
            testCase.Logger.setLevel('DEBUG');
            testCase.verifyEqual(testCase.Logger.getLevel(), claudecode.logging.LogLevel.DEBUG);

            testCase.Logger.disable();
            testCase.verifyFalse(testCase.Logger.isEnabled());

            testCase.Logger.enable();
            testCase.verifyTrue(testCase.Logger.isEnabled());
        end

        function testLoggerSessionId(testCase)
            originalId = testCase.Logger.getSessionId();
            testCase.verifyNotEmpty(originalId);

            testCase.Logger.setSessionId('custom_session_123');
            testCase.verifyEqual(testCase.Logger.getSessionId(), "custom_session_123");
        end
    end

    %% Logger Output Tests

    methods (Test)
        function testLoggerWritesFile(testCase)
            % Log a message
            testCase.Logger.info('TestComponent', 'test_event', struct('key', 'value'));

            % Get the log file path and verify it exists
            logPath = testCase.Logger.getLogFilePath();
            testCase.Logger.close();  % Flush and close

            testCase.verifyTrue(isfile(logPath), 'Log file should exist');
        end

        function testLoggerJsonLinesFormat(testCase)
            % Log multiple messages
            testCase.Logger.info('Component1', 'event1');
            testCase.Logger.warn('Component2', 'event2');
            testCase.Logger.error('Component3', 'event3');

            logPath = testCase.Logger.getLogFilePath();
            testCase.Logger.close();

            % Read and verify JSON-lines format
            content = fileread(logPath);
            lines = strsplit(content, newline);

            % Remove empty lines
            lines = lines(~cellfun('isempty', lines));

            testCase.verifyGreaterThanOrEqual(numel(lines), 3);

            % Verify each line is valid JSON
            for i = 1:numel(lines)
                try
                    entry = jsondecode(lines{i});
                    testCase.verifyTrue(isfield(entry, 'ts'));
                    testCase.verifyTrue(isfield(entry, 'level'));
                    testCase.verifyTrue(isfield(entry, 'component'));
                    testCase.verifyTrue(isfield(entry, 'event'));
                catch ME
                    testCase.verifyFail(sprintf('Line %d is not valid JSON: %s', i, ME.message));
                end
            end
        end

        function testLoggerLevelFiltering(testCase)
            % Set level to WARN (should filter out INFO, DEBUG, TRACE)
            testCase.Logger.setLevel('WARN');

            testCase.Logger.trace('Test', 'trace_event');
            testCase.Logger.debug('Test', 'debug_event');
            testCase.Logger.info('Test', 'info_event');
            testCase.Logger.warn('Test', 'warn_event');
            testCase.Logger.error('Test', 'error_event');

            logPath = testCase.Logger.getLogFilePath();
            testCase.Logger.close();

            content = fileread(logPath);

            % Should contain WARN and ERROR, but not INFO, DEBUG, TRACE
            testCase.verifyTrue(contains(content, 'warn_event'));
            testCase.verifyTrue(contains(content, 'error_event'));
            testCase.verifyFalse(contains(content, 'info_event'));
            testCase.verifyFalse(contains(content, 'debug_event'));
            testCase.verifyFalse(contains(content, 'trace_event'));
        end

        function testLoggerDisabled(testCase)
            testCase.Logger.disable();

            testCase.Logger.info('Test', 'should_not_appear');

            logPath = testCase.Logger.getLogFilePath();
            testCase.Logger.close();

            % File may or may not exist, but should not contain the event
            if isfile(logPath)
                content = fileread(logPath);
                testCase.verifyFalse(contains(content, 'should_not_appear'));
            end
        end

        function testLoggerTimedMethods(testCase)
            testCase.Logger.infoTimed('Test', 'timed_event', struct('key', 'value'), 123.456);

            logPath = testCase.Logger.getLogFilePath();
            testCase.Logger.close();

            content = fileread(logPath);
            entry = jsondecode(content);

            testCase.verifyEqual(entry.duration_ms, 123.456);
        end

        function testLoggerTraceId(testCase)
            testCase.Logger.info('Test', 'event_with_trace', struct(), 'TraceId', 'my_trace_id');

            logPath = testCase.Logger.getLogFilePath();
            testCase.Logger.close();

            content = fileread(logPath);
            entry = jsondecode(content);

            testCase.verifyEqual(entry.trace_id, 'my_trace_id');
        end
    end

    %% Integration Tests

    methods (Test)
        function testLoggerSessionCorrelation(testCase)
            % Simulate what happens during app initialization
            sessionId = testCase.Logger.getSessionId();

            % Log several events with the same session
            testCase.Logger.info('ClaudeCodeApp', 'app_initialized');
            testCase.Logger.info('ChatUIController', 'message_received');
            testCase.Logger.info('CodeExecutor', 'execution_started');

            logPath = testCase.Logger.getLogFilePath();
            testCase.Logger.close();

            content = fileread(logPath);
            lines = strsplit(content, newline);
            lines = lines(~cellfun('isempty', lines));

            % Verify all entries have the same session_id
            for i = 1:numel(lines)
                entry = jsondecode(lines{i});
                testCase.verifyEqual(entry.session_id, char(sessionId));
            end
        end
    end
end
