classdef CodeExecutor < handle
    %CODEEXECUTOR Safely executes MATLAB code with security validation
    %
    %   This class provides a secure way to execute MATLAB code from Claude's
    %   responses, with validation to block potentially dangerous operations.
    %
    %   Example:
    %       executor = claudecode.CodeExecutor();
    %       [result, isError] = executor.execute('x = 1 + 1');

    properties
        AllowSystemCommands = false     % Allow system(), !, etc.
        AllowFileOperations = true      % Allow file read/write
        AllowDestructiveOps = false     % Allow delete, rmdir, etc.
        Timeout = 30                    % Execution timeout in seconds
        ExecutionWorkspace = 'base'     % Workspace to execute in
        RequireApproval = false         % Require user approval for all code
        LogExecutions = true            % Log all executions
    end

    properties (Constant, Access = private)
        % Functions that are always blocked
        BLOCKED_FUNCTIONS = {
            % System commands
            'system', 'dos', 'unix', 'perl', 'python', '!', ...
            % Dangerous eval variants
            'eval', 'evalin', 'evalc', 'feval', 'builtin', ...
            % Destructive file operations
            'delete', 'rmdir', 'movefile', 'copyfile', ...
            % Java/Python escape hatches
            'java.lang.Runtime', 'py.os', 'py.subprocess', ...
            % Network operations
            'urlread', 'urlwrite', 'webread', 'webwrite', 'websave', ...
            'ftp', 'sendmail', ...
            % Other dangerous operations
            'clear', 'clearvars', 'exit', 'quit', 'restart'
        }

        % Patterns that indicate dangerous code
        BLOCKED_PATTERNS = {
            '^\s*!',           % Shell escape at line start
            'java\.lang\.',    % Java access
            'py\.',            % Python access
            'NET\.',           % .NET access
            'COM\.'            % COM access
        }
    end

    properties (Access = private)
        ExecutionLog = {}   % Log of executed code and results
    end

    methods
        function obj = CodeExecutor()
            %CODEEXECUTOR Constructor
        end

        function [result, isError] = execute(obj, code)
            %EXECUTE Execute MATLAB code safely
            %
            %   [result, isError] = executor.execute(code)
            %
            %   Returns:
            %       result: Output text or error message
            %       isError: true if execution failed or was blocked

            % Validate code before execution
            [isValid, reason] = obj.validateCode(code);

            if ~isValid
                result = sprintf('Code blocked: %s', reason);
                isError = true;
                obj.logExecution(code, result, true, 'blocked');
                return;
            end

            % Check if approval is required
            if obj.RequireApproval
                approved = obj.requestApproval(code, 'Code execution requested');
                if ~approved
                    result = 'Code execution cancelled by user';
                    isError = true;
                    obj.logExecution(code, result, true, 'cancelled');
                    return;
                end
            end

            % Execute with timeout protection
            try
                result = obj.executeWithTimeout(code);
                isError = false;
                obj.logExecution(code, result, false, 'success');

            catch ME
                result = obj.formatError(ME);
                isError = true;
                obj.logExecution(code, result, true, 'error');
            end
        end

        function [isValid, reason] = validateCode(obj, code)
            %VALIDATECODE Check if code is safe to execute
            %
            %   [isValid, reason] = executor.validateCode(code)

            isValid = true;
            reason = '';

            % Check for blocked functions
            for i = 1:length(obj.BLOCKED_FUNCTIONS)
                funcName = obj.BLOCKED_FUNCTIONS{i};

                % Handle special case for '!' operator
                if strcmp(funcName, '!')
                    if contains(code, '!') && ~contains(code, '~=') && ~contains(code, '!=')
                        isValid = false;
                        reason = 'Shell escape operator (!) is not allowed';
                        return;
                    end
                    continue;
                end

                % Build pattern to match function call or reference
                pattern = sprintf('\\b%s\\s*[\\(\\.]?', regexptranslate('escape', funcName));

                if ~isempty(regexp(code, pattern, 'once'))
                    isValid = false;
                    reason = sprintf('Blocked function detected: %s', funcName);
                    return;
                end
            end

            % Check for blocked patterns
            for i = 1:length(obj.BLOCKED_PATTERNS)
                pattern = obj.BLOCKED_PATTERNS{i};

                if ~isempty(regexp(code, pattern, 'once'))
                    isValid = false;
                    reason = sprintf('Blocked pattern detected: %s', pattern);
                    return;
                end
            end

            % Check for system commands if not allowed
            if ~obj.AllowSystemCommands
                if contains(code, 'system(') || contains(code, 'dos(') || ...
                   contains(code, 'unix(')
                    isValid = false;
                    reason = 'System commands are not allowed';
                    return;
                end
            end

            % Check for destructive operations if not allowed
            if ~obj.AllowDestructiveOps
                destructiveOps = {'delete(', 'rmdir(', 'recycle('};
                for i = 1:length(destructiveOps)
                    if contains(code, destructiveOps{i})
                        isValid = false;
                        reason = sprintf('Destructive operation not allowed: %s', destructiveOps{i});
                        return;
                    end
                end
            end
        end

        function log = getExecutionLog(obj)
            %GETEXECUTIONLOG Get the execution log

            log = obj.ExecutionLog;
        end

        function clearLog(obj)
            %CLEARLOG Clear the execution log

            obj.ExecutionLog = {};
        end
    end

    methods (Access = private)
        function result = executeWithTimeout(obj, code)
            %EXECUTEWITHTIMEOUT Execute code with timeout protection

            % For R2025b+, we can use futures/parfeval for timeout
            % For now, use direct execution with try-catch
            % TODO: Implement proper timeout using parfeval if PCT available

            % Capture output
            result = evalc(sprintf('evalin(''%s'', code)', obj.ExecutionWorkspace));

            % Clean up result
            result = strtrim(result);
        end

        function approved = requestApproval(~, code, reason)
            %REQUESTAPPROVAL Request user approval for code execution

            % Format code for display (truncate if too long)
            displayCode = code;
            if length(displayCode) > 500
                displayCode = [displayCode(1:500), '... (truncated)'];
            end

            msg = sprintf(['%s\n\n' ...
                          '--- Code ---\n%s\n--- End ---\n\n' ...
                          'Do you want to execute this code?'], reason, displayCode);

            answer = questdlg(msg, 'Code Execution Approval', ...
                'Execute', 'Cancel', 'Cancel');

            approved = strcmp(answer, 'Execute');
        end

        function errStr = formatError(~, ME)
            %FORMATERROR Format error message for display

            errStr = sprintf('Error: %s', ME.message);

            if ~isempty(ME.stack)
                errStr = sprintf('%s\n  at line %d', errStr, ME.stack(1).line);
            end
        end

        function logExecution(obj, code, result, isError, status)
            %LOGEXECUTION Log an execution attempt

            if ~obj.LogExecutions
                return;
            end

            entry = struct();
            entry.timestamp = datetime('now');
            entry.code = code;
            entry.result = result;
            entry.isError = isError;
            entry.status = status;

            obj.ExecutionLog{end+1} = entry;

            % Keep log size reasonable (last 100 entries)
            if length(obj.ExecutionLog) > 100
                obj.ExecutionLog = obj.ExecutionLog(end-99:end);
            end
        end
    end
end
