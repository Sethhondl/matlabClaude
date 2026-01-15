classdef ClaudeProcessManager < handle
    %CLAUDEPROCESSMANAGER Manages Claude Code CLI subprocess communication
    %
    %   This class spawns Claude Code as a subprocess using Java ProcessBuilder
    %   and handles bidirectional communication with streaming JSON output.
    %
    %   Example:
    %       pm = claudecode.ClaudeProcessManager();
    %       response = pm.sendMessage('Hello Claude');

    properties (Access = private)
        Process             % Java Process object
        InputStream         % BufferedReader for stdout
        ErrorStream         % BufferedReader for stderr
        OutputStream        % Writer for stdin
        SessionId           % Current session ID for conversation continuity
        IsRunning           % Boolean flag
        StreamTimer         % Timer for async stream reading
    end

    properties (Constant)
        DEFAULT_TIMEOUT = 300000  % 5 minutes in milliseconds
    end

    properties (Access = private)
        ClaudePath = ''  % Resolved path to Claude CLI
    end

    properties (SetAccess = private)
        LastError = ''      % Last error message
    end

    events
        StreamChunk         % Fired when a new chunk is received
        ResponseComplete    % Fired when response is complete
        ErrorOccurred       % Fired on errors
    end

    methods
        function obj = ClaudeProcessManager()
            %CLAUDEPROCESSMANAGER Constructor
            obj.IsRunning = false;
            obj.SessionId = '';
            obj.ClaudePath = obj.findClaudeCLI();
        end

        function delete(obj)
            %DELETE Destructor - ensure process is stopped
            obj.stopProcess();
        end

        function available = isClaudeAvailable(obj)
            %ISCLAUDEAVAILABLE Check if Claude CLI is installed and accessible
            if isempty(obj.ClaudePath)
                available = false;
                return;
            end

            try
                [status, ~] = system(['"', obj.ClaudePath, '" --version']);
                available = (status == 0);
            catch
                available = false;
            end
        end

        function path = getClaudePath(obj)
            %GETCLAUDEPATH Get the resolved path to Claude CLI
            path = obj.ClaudePath;
        end

        function setClaudePath(obj, path)
            %SETCLAUDEPATH Manually set the Claude CLI path
            obj.ClaudePath = path;
        end

        function response = sendMessage(obj, prompt, options)
            %SENDMESSAGE Send a message to Claude and get response
            %
            %   response = pm.sendMessage(prompt) sends prompt and returns response
            %   response = pm.sendMessage(prompt, options) with additional options
            %
            %   Options struct fields:
            %       allowedTools - cell array of allowed tool names
            %       timeout - timeout in milliseconds
            %       includeContext - additional context string

            arguments
                obj
                prompt (1,:) char
                options.allowedTools = {'Edit', 'Write', 'Read', 'Bash', 'Glob', 'Grep'}
                options.timeout = obj.DEFAULT_TIMEOUT
                options.context = ''
                options.resumeSession = true
            end

            % Build the full prompt with context if provided
            fullPrompt = prompt;
            if ~isempty(options.context)
                fullPrompt = sprintf('%s\n\n%s', options.context, prompt);
            end

            % Build command arguments
            args = obj.buildCommandArgs(fullPrompt, options);

            % Start process and collect response
            response = obj.executeCommand(args, options.timeout);
        end

        function sendMessageAsync(obj, prompt, chunkCallback, completeCallback, options)
            %SENDMESSAGEASYNC Send message asynchronously with callbacks
            %
            %   pm.sendMessageAsync(prompt, @onChunk, @onComplete)
            %
            %   chunkCallback: function(chunkText) called for each streamed chunk
            %   completeCallback: function(fullResponse) called when complete

            arguments
                obj
                prompt (1,:) char
                chunkCallback function_handle
                completeCallback function_handle
                options.allowedTools = {'Edit', 'Write', 'Read', 'Bash', 'Glob', 'Grep'}
                options.context = ''
            end

            % Build full prompt
            fullPrompt = prompt;
            if ~isempty(options.context)
                fullPrompt = sprintf('%s\n\n%s', options.context, prompt);
            end

            % Build command
            args = obj.buildCommandArgs(fullPrompt, options);

            % Start process
            obj.startProcess(args);

            % Set up async reading with a timer
            fullResponse = '';
            obj.StreamTimer = timer(...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', 0.05, ...  % 50ms polling
                'TimerFcn', @(~,~) obj.pollStream(chunkCallback, completeCallback, fullResponse));
            start(obj.StreamTimer);
        end

        function stopProcess(obj)
            %STOPPROCESS Gracefully terminate the subprocess
            if obj.IsRunning && ~isempty(obj.Process)
                try
                    obj.Process.destroy();
                catch
                    % Process may already be terminated
                end
                obj.IsRunning = false;
            end

            % Stop timer if running
            if ~isempty(obj.StreamTimer) && isvalid(obj.StreamTimer)
                stop(obj.StreamTimer);
                delete(obj.StreamTimer);
            end
        end
    end

    methods (Access = private)
        function args = buildCommandArgs(obj, prompt, options)
            %BUILDCOMMANDARGS Build CLI argument cell array

            args = {'-p', '--output-format', 'stream-json'};

            % Add allowed tools
            if ~isempty(options.allowedTools)
                toolStr = strjoin(options.allowedTools, ',');
                args = [args, {'--allowedTools', toolStr}];
            end

            % Add session resume if we have a session
            if options.resumeSession && ~isempty(obj.SessionId)
                args = [args, {'--resume', obj.SessionId}];
            end

            % Add the prompt (must be last)
            args = [args, {prompt}];
        end

        function startProcess(obj, args)
            %STARTPROCESS Start Claude CLI as subprocess using Java ProcessBuilder

            import java.lang.ProcessBuilder
            import java.io.BufferedReader
            import java.io.InputStreamReader
            import java.io.OutputStreamWriter

            % Build command array for Java
            numArgs = length(args) + 1;
            cmdArray = javaArray('java.lang.String', numArgs);
            cmdArray(1) = java.lang.String(obj.ClaudePath);
            for i = 1:length(args)
                cmdArray(i+1) = java.lang.String(args{i});
            end

            % Create and configure ProcessBuilder
            pb = ProcessBuilder(cmdArray);
            pb.redirectErrorStream(false);  % Keep stderr separate

            % Set working directory to current MATLAB directory
            pb.directory(java.io.File(pwd));

            % Start the process
            obj.Process = pb.start();

            % Set up stream readers
            obj.InputStream = BufferedReader(InputStreamReader(...
                obj.Process.getInputStream(), 'UTF-8'));
            obj.ErrorStream = BufferedReader(InputStreamReader(...
                obj.Process.getErrorStream(), 'UTF-8'));
            obj.OutputStream = OutputStreamWriter(...
                obj.Process.getOutputStream(), 'UTF-8');

            obj.IsRunning = true;
        end

        function response = executeCommand(obj, args, timeout)
            %EXECUTECOMMAND Execute command and collect full response

            obj.startProcess(args);

            response = struct();
            response.text = '';
            response.toolUses = {};
            response.sessionId = '';
            response.success = true;
            response.error = '';

            startTime = tic;

            try
                while obj.IsRunning
                    % Check timeout
                    if toc(startTime) * 1000 > timeout
                        obj.stopProcess();
                        response.success = false;
                        response.error = 'Timeout waiting for Claude response';
                        break;
                    end

                    % Check if process has exited
                    try
                        exitValue = obj.Process.exitValue();
                        obj.IsRunning = false;
                        if exitValue ~= 0
                            response.success = false;
                            response.error = obj.readAllErrors();
                        end
                    catch
                        % Process still running, continue
                    end

                    % Read available output
                    while obj.InputStream.ready()
                        line = char(obj.InputStream.readLine());
                        if ~isempty(line)
                            parsed = obj.parseStreamLine(line);
                            if ~isempty(parsed)
                                response = obj.mergeResponse(response, parsed);
                            end
                        end
                    end

                    pause(0.01);  % Small pause to prevent CPU spinning
                end

                % Read any remaining output
                while obj.InputStream.ready()
                    line = char(obj.InputStream.readLine());
                    if ~isempty(line)
                        parsed = obj.parseStreamLine(line);
                        if ~isempty(parsed)
                            response = obj.mergeResponse(response, parsed);
                        end
                    end
                end

                % Update session ID if we got one
                if ~isempty(response.sessionId)
                    obj.SessionId = response.sessionId;
                end

            catch ME
                response.success = false;
                response.error = ME.message;
                obj.stopProcess();
            end
        end

        function parsed = parseStreamLine(~, line)
            %PARSESTREAMLINE Parse a single line of NDJSON stream output

            parsed = struct();

            try
                json = jsondecode(line);

                % Handle different message types from Claude Code stream
                if isfield(json, 'type')
                    switch json.type
                        case 'assistant'
                            % Assistant message content
                            if isfield(json, 'message') && isfield(json.message, 'content')
                                content = json.message.content;
                                if iscell(content)
                                    for i = 1:length(content)
                                        block = content{i};
                                        if isfield(block, 'type') && strcmp(block.type, 'text')
                                            parsed.text = block.text;
                                        end
                                    end
                                end
                            end

                        case 'content_block_delta'
                            % Streaming text delta
                            if isfield(json, 'delta') && isfield(json.delta, 'text')
                                parsed.textDelta = json.delta.text;
                            end

                        case 'result'
                            % Final result with session info
                            if isfield(json, 'session_id')
                                parsed.sessionId = json.session_id;
                            end
                            if isfield(json, 'result')
                                parsed.finalText = json.result;
                            end

                        case 'tool_use'
                            % Tool usage
                            parsed.toolUse = json;

                        case 'error'
                            % Error message
                            if isfield(json, 'error')
                                parsed.error = json.error;
                            end
                    end
                end

            catch
                % Not valid JSON or unrecognized format, skip
            end
        end

        function response = mergeResponse(~, response, parsed)
            %MERGERESPONSE Merge parsed data into response struct

            if isfield(parsed, 'text')
                response.text = [response.text, parsed.text];
            end

            if isfield(parsed, 'textDelta')
                response.text = [response.text, parsed.textDelta];
            end

            if isfield(parsed, 'finalText')
                response.text = parsed.finalText;
            end

            if isfield(parsed, 'sessionId')
                response.sessionId = parsed.sessionId;
            end

            if isfield(parsed, 'toolUse')
                response.toolUses{end+1} = parsed.toolUse;
            end

            if isfield(parsed, 'error')
                response.success = false;
                response.error = parsed.error;
            end
        end

        function errText = readAllErrors(obj)
            %READALLERRORS Read all available error stream content

            errText = '';
            try
                while obj.ErrorStream.ready()
                    line = char(obj.ErrorStream.readLine());
                    errText = [errText, line, newline]; %#ok<AGROW>
                end
            catch
                % Stream may be closed
            end
        end

        function pollStream(obj, chunkCallback, completeCallback, fullResponse)
            %POLLSTREAM Poll stream for async reading

            persistent accumText
            if isempty(accumText)
                accumText = '';
            end

            try
                % Check if process has exited
                processExited = false;
                try
                    obj.Process.exitValue();
                    processExited = true;
                catch
                    % Still running
                end

                % Read available lines
                while obj.InputStream.ready()
                    line = char(obj.InputStream.readLine());
                    if ~isempty(line)
                        parsed = obj.parseStreamLine(line);

                        % Handle text chunks
                        if isfield(parsed, 'textDelta')
                            accumText = [accumText, parsed.textDelta];
                            chunkCallback(parsed.textDelta);
                        elseif isfield(parsed, 'text')
                            accumText = [accumText, parsed.text];
                            chunkCallback(parsed.text);
                        end

                        % Capture session ID
                        if isfield(parsed, 'sessionId')
                            obj.SessionId = parsed.sessionId;
                        end
                    end
                end

                % If process exited, complete
                if processExited
                    obj.IsRunning = false;
                    stop(obj.StreamTimer);
                    delete(obj.StreamTimer);

                    response = struct();
                    response.text = accumText;
                    response.sessionId = obj.SessionId;
                    response.success = true;

                    accumText = '';  % Reset for next message
                    completeCallback(response);
                end

            catch ME
                obj.LastError = ME.message;
                obj.stopProcess();

                response = struct();
                response.text = accumText;
                response.success = false;
                response.error = ME.message;

                accumText = '';
                completeCallback(response);
            end
        end

        function claudePath = findClaudeCLI(~)
            %FINDCLAUDECLI Search for Claude CLI in common locations

            % Common installation paths to check
            homeDir = getenv('HOME');
            possiblePaths = {};

            % NVM-based Node.js installations (common for npm global packages)
            possiblePaths{end+1} = fullfile(homeDir, '.nvm', 'versions', 'node', '*', 'bin', 'claude');
            % Standard npm global installations
            possiblePaths{end+1} = '/usr/local/bin/claude';
            possiblePaths{end+1} = '/usr/bin/claude';
            possiblePaths{end+1} = '/opt/homebrew/bin/claude';
            possiblePaths{end+1} = fullfile(homeDir, '.local', 'bin', 'claude');
            possiblePaths{end+1} = fullfile(homeDir, 'bin', 'claude');
            % npm prefix locations
            possiblePaths{end+1} = fullfile(homeDir, '.npm-global', 'bin', 'claude');
            % Yarn global
            possiblePaths{end+1} = fullfile(homeDir, '.yarn', 'bin', 'claude');

            claudePath = '';

            % Check each possible path
            for i = 1:length(possiblePaths)
                pathPattern = possiblePaths{i};

                if contains(pathPattern, '*')
                    % Handle glob pattern (for NVM)
                    matches = dir(pathPattern);
                    for j = 1:length(matches)
                        if matches(j).isdir == false
                            candidatePath = fullfile(matches(j).folder, matches(j).name);
                            if isfile(candidatePath)
                                claudePath = candidatePath;
                                return;
                            end
                        end
                    end
                else
                    if isfile(pathPattern)
                        claudePath = pathPattern;
                        return;
                    end
                end
            end

            % Last resort: try 'which claude' via system
            try
                [status, result] = system('which claude 2>/dev/null');
                if status == 0
                    claudePath = strtrim(result);
                    return;
                end
            catch
                % Ignore errors
            end

            % If nothing found, leave empty (will fail gracefully)
        end
    end
end
