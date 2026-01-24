classdef ChatUIController < handle
    %CHATUICONTROLLER Manages the chat UI and bridges JavaScript/MATLAB communication
    %
    %   This class creates and manages the chat interface using an embedded
    %   HTML webview, handling bidirectional communication between the UI and MATLAB.
    %   Core logic (Claude communication, agents) is handled by Python.
    %
    %   Example:
    %       controller = claudecode.ChatUIController(parentFigure, bridge);

    properties (Access = public)
        SimulinkBridge      % Reference to SimulinkBridge for model context
        GitProvider         % Reference to GitContextProvider
    end

    properties (Access = private)
        ParentFigure        % uifigure containing the UI
        PythonBridge        % Python MatlabBridge instance
        CodeExecutor        % Reference to CodeExecutor (MATLAB-side)
        WorkspaceProvider   % Reference to WorkspaceContextProvider
        HTMLComponent       % uihtml component
        IsReady = false     % Whether UI has initialized
        PollingTimer        % Timer for polling async responses
        Logger              % Logging instance

        % State
        Messages = {}       % Cell array of message structs
        IsStreaming = false % Whether currently streaming
        CurrentStreamText = '' % Accumulated text during streaming
        CurrentTraceId = '' % Trace ID for correlating streaming events
        StreamChunkCount = 0 % Count of stream chunks for current message

        % Polling timeout
        PollingStartTime    % Time when polling started
        MaxPollingDuration = 300 % Maximum polling duration in seconds (5 minutes)
    end

    events
        MessageSent         % Fired when user sends a message
        CodeExecuted        % Fired when code is executed
    end

    methods
        function obj = ChatUIController(parent, pythonBridge)
            %CHATUICONTROLLER Constructor
            %
            %   controller = ChatUIController(parent, pythonBridge)
            %
            %   parent: uifigure to contain the chat UI
            %   pythonBridge: Python MatlabBridge instance

            obj.ParentFigure = parent;
            obj.PythonBridge = pythonBridge;
            obj.CodeExecutor = claudecode.CodeExecutor();
            obj.WorkspaceProvider = claudecode.WorkspaceContextProvider();
            obj.Logger = claudecode.logging.Logger.getInstance();

            obj.createUI();

            obj.Logger.info('ChatUIController', 'controller_initialized');
        end

        function delete(obj)
            %DELETE Destructor

            obj.stopPolling();
        end

        function stopPolling(obj)
            %STOPPOLLING Stop the polling timer safely
            %
            %   This method can be called externally before shutdown to prevent
            %   race conditions between polling callbacks and cleanup.

            if ~isempty(obj.PollingTimer) && isvalid(obj.PollingTimer)
                try
                    stop(obj.PollingTimer);
                    delete(obj.PollingTimer);
                catch
                    % Ignore errors during cleanup
                end
                obj.PollingTimer = [];
            end
            obj.IsStreaming = false;
        end

        function sendAssistantMessage(obj, content)
            %SENDASSISTANTMESSAGE Display a complete assistant message

            obj.addMessage('assistant', content);
            obj.IsStreaming = false;
            obj.updateStatus('ready', 'Ready');
        end

        function startStreaming(obj)
            %STARTSTREAMING Signal start of streaming response

            obj.IsStreaming = true;
            obj.CurrentStreamText = '';
            obj.StreamChunkCount = 0;
            obj.updateStatus('streaming', 'Claude is thinking...');
            obj.sendToJS('startStreaming', struct());

            obj.Logger.info('ChatUIController', 'stream_started', struct(), ...
                'TraceId', obj.CurrentTraceId);
        end

        function sendStreamChunk(obj, chunk)
            %SENDSTREAMCHUNK Append a streaming text chunk

            obj.CurrentStreamText = [obj.CurrentStreamText, chunk];
            obj.StreamChunkCount = obj.StreamChunkCount + 1;
            obj.sendToJS('streamChunk', struct('text', chunk));

            % Log at TRACE level to avoid log bloat
            obj.Logger.trace('ChatUIController', 'stream_chunk', struct(...
                'chunk_size', strlength(chunk), ...
                'chunk_number', obj.StreamChunkCount), ...
                'TraceId', obj.CurrentTraceId);
        end

        function endStreaming(obj)
            %ENDSTREAMING Signal end of streaming response

            responseLength = strlength(obj.CurrentStreamText);

            if ~isempty(obj.CurrentStreamText)
                % Store in history without sending to UI (JS finalizeStreamingMessage handles UI)
                msg = struct('role', 'assistant', 'content', obj.CurrentStreamText, 'timestamp', now);
                obj.Messages{end+1} = msg;
            end
            obj.IsStreaming = false;
            obj.CurrentStreamText = '';
            obj.updateStatus('ready', 'Ready');
            obj.sendToJS('endStreaming', struct());

            obj.Logger.info('ChatUIController', 'stream_complete', struct(...
                'response_length', responseLength, ...
                'total_chunks', obj.StreamChunkCount), ...
                'TraceId', obj.CurrentTraceId);
        end

        function sendError(obj, message)
            %SENDERROR Display an error message

            obj.addMessage('error', message);
            obj.IsStreaming = false;
            obj.updateStatus('error', 'Error occurred');
            obj.sendToJS('showError', struct('message', message));
        end

        function updateStatus(obj, status, message)
            %UPDATESTATUS Update the status indicator

            obj.sendToJS('updateStatus', struct('status', status, 'message', message));
        end
    end

    methods (Access = private)
        function createUI(obj)
            %CREATEUI Create the uihtml component

            % Get path to HTML file
            thisFile = mfilename('fullpath');
            toolboxDir = fileparts(fileparts(thisFile));
            htmlPath = fullfile(toolboxDir, 'chat_ui', 'index.html');

            % Use a grid layout to handle auto-resizing (uihtml doesn't support Units)
            grid = uigridlayout(obj.ParentFigure, [1 1], ...
                'Padding', [0 0 0 0], ...
                'RowHeight', {'1x'}, ...
                'ColumnWidth', {'1x'});

            % Create uihtml component inside the grid - it will auto-fill
            obj.HTMLComponent = uihtml(grid, ...
                'HTMLSource', htmlPath, ...
                'HTMLEventReceivedFcn', @(src, evt) obj.handleJSEvent(evt));

            % Set IsReady immediately - the HTML component can receive events
            % even before JS calls setup(). This avoids race conditions.
            obj.IsReady = true;
        end

        function onFigureResize(obj)
            %ONFIGURERESIZE Handle figure resize

            if ~isempty(obj.HTMLComponent) && isvalid(obj.HTMLComponent)
                obj.HTMLComponent.Position = [0 0 obj.ParentFigure.Position(3) obj.ParentFigure.Position(4)];
            end
        end

        function handleJSEvent(obj, evt)
            %HANDLEJSEVENT Handle events from JavaScript

            try
                eventName = evt.HTMLEventName;
                eventData = evt.HTMLEventData;

                switch eventName
                    case 'userMessage'
                        obj.onUserMessage(eventData);

                    case 'runCode'
                        obj.onRunCode(eventData);

                    case 'copyCode'
                        obj.onCopyCode(eventData);

                    case 'insertCode'
                        obj.onInsertCode(eventData);

                    case 'uiReady'
                        obj.onUIReady();

                    case 'clearChat'
                        obj.onClearChat();

                    case 'requestSettings'
                        obj.sendCurrentSettings();

                    case 'saveSettings'
                        obj.handleSaveSettings(eventData);

                    otherwise
                        warning('ChatUIController:UnknownEvent', ...
                            'Unknown JS event: %s', eventName);
                end

            catch ME
                warning('ChatUIController:EventError', ...
                    'Error handling JS event: %s', ME.message);
            end
        end

        function onUserMessage(obj, data)
            %ONUSERMESSAGE Handle user message from UI

            if obj.IsStreaming
                obj.Logger.debug('ChatUIController', 'message_ignored_streaming');
                return;
            end

            message = data.content;
            if isempty(strtrim(message))
                return;
            end

            % Generate trace ID for this message flow
            obj.CurrentTraceId = sprintf('msg_%s', datestr(now, 'HHMMSS_FFF'));

            % Log message received
            obj.Logger.info('ChatUIController', 'message_received', struct(...
                'message_length', strlength(message)), ...
                'TraceId', obj.CurrentTraceId);

            % Check for /context command
            [processedMessage, hasContext] = obj.processContextCommand(message);
            message = processedMessage;

            % Add user message to history
            obj.addMessage('user', message);

            % Notify via event
            notify(obj, 'MessageSent');

            % Build context for agents (empty - Claude will fetch on-demand)
            context = py.dict();

            % Check if any Python agent can handle this message
            agentResult = obj.PythonBridge.dispatch_to_agent(message, context);
            agentResult = obj.pyDictToStruct(agentResult);

            if agentResult.handled
                % Agent handled it - show response directly
                obj.Logger.info('ChatUIController', 'agent_handled', struct(...
                    'agent_name', char(agentResult.agent_name)), ...
                    'TraceId', obj.CurrentTraceId);
                obj.sendAssistantMessage(char(agentResult.response));
                return;
            end

            % No agent handled it - send to Claude via Python
            % Always include directory and editor context
            contextStr = obj.WorkspaceProvider.getCurrentDirectoryContext();
            contextStr = [contextStr, newline, newline, obj.WorkspaceProvider.getEditorContext()];

            % If /context command was used, prepend workspace and Simulink context
            if hasContext
                contextStr = [contextStr, newline, newline, obj.buildFullContext()];
            end

            obj.startStreaming();

            % Start async message via Python
            obj.PythonBridge.start_async_message(message, contextStr);

            % Start polling for responses
            obj.startPolling();
        end

        function startPolling(obj)
            %STARTPOLLING Start polling for async response chunks

            % Record start time for timeout detection
            obj.PollingStartTime = tic;

            obj.PollingTimer = timer(...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', 0.05, ...  % 50ms polling
                'TimerFcn', @(~,~) obj.pollAsyncResponse());
            start(obj.PollingTimer);
        end

        function pollAsyncResponse(obj)
            %POLLASYNCRESPONSE Poll Python for async response content

            try
                % Check for polling timeout
                if ~isempty(obj.PollingStartTime)
                    elapsedTime = toc(obj.PollingStartTime);
                    if elapsedTime > obj.MaxPollingDuration
                        % Timeout occurred - stop polling and show error
                        obj.Logger.warn('ChatUIController', 'polling_timeout', struct(...
                            'elapsed_seconds', elapsedTime, ...
                            'max_duration', obj.MaxPollingDuration), ...
                            'TraceId', obj.CurrentTraceId);

                        if ~isempty(obj.PollingTimer) && isvalid(obj.PollingTimer)
                            stop(obj.PollingTimer);
                            delete(obj.PollingTimer);
                            obj.PollingTimer = [];
                        end
                        obj.endStreaming();
                        obj.sendError(sprintf(...
                            'Request timed out after %.0f seconds. The AI may be unavailable or processing a complex request. Please try again.', ...
                            elapsedTime));
                        return;
                    end
                end

                % Get any new content (text, images, tool use)
                content = obj.PythonBridge.poll_async_content();
                contentList = cell(content);

                for i = 1:length(contentList)
                    item = contentList{i};
                    if isa(item, 'py.dict')
                        item = obj.pyDictToStruct(item);
                    end

                    if isfield(item, 'type')
                        itemType = char(item.type);
                        switch itemType
                            case 'text'
                                text = char(item.text);
                                if ~isempty(text)
                                    obj.sendStreamChunk(text);
                                end
                            case 'image'
                                obj.sendImage(item.source);
                            case 'tool_use'
                                % Show tool use indicator
                                toolName = char(item.name);
                                obj.sendStreamChunk(sprintf('\n[Using tool: %s]\n', toolName));
                        end
                    end
                end

                % Check if complete
                if obj.PythonBridge.is_async_complete()
                    % Stop polling
                    stop(obj.PollingTimer);
                    delete(obj.PollingTimer);
                    obj.PollingTimer = [];

                    % Get final response
                    response = obj.PythonBridge.get_async_response();
                    if ~isempty(response)
                        response = obj.pyDictToStruct(response);
                        obj.endStreaming();

                        if ~response.success && ~isempty(response.error)
                            obj.sendError(char(response.error));
                        end
                    else
                        obj.endStreaming();
                    end
                end

            catch ME
                % Stop polling on error
                if ~isempty(obj.PollingTimer) && isvalid(obj.PollingTimer)
                    stop(obj.PollingTimer);
                    delete(obj.PollingTimer);
                    obj.PollingTimer = [];
                end
                obj.endStreaming();
                obj.sendError(ME.message);
            end
        end

        function sendImage(obj, source)
            %SENDIMAGE Send an image to the UI
            %
            %   source: struct with 'type', 'media_type', 'data' fields

            if isa(source, 'py.dict')
                source = obj.pyDictToStruct(source);
            end

            % Extract image data
            imageData = struct();
            if isfield(source, 'type')
                imageData.type = char(source.type);
            else
                imageData.type = 'base64';
            end
            if isfield(source, 'media_type')
                imageData.media_type = char(source.media_type);
            else
                imageData.media_type = 'image/png';
            end
            if isfield(source, 'data')
                imageData.data = char(source.data);
            else
                return;  % No image data, skip
            end

            obj.sendToJS('showImage', imageData);
        end

        function onRunCode(obj, data)
            %ONRUNCODE Handle code execution request

            code = data.code;
            startTime = tic;

            obj.Logger.info('ChatUIController', 'code_execution_requested', struct(...
                'code_length', strlength(code), ...
                'block_id', data.blockId));

            % Execute the code (stays in MATLAB)
            [result, isError] = obj.CodeExecutor.execute(code);

            elapsedMs = toc(startTime) * 1000;

            % Log result
            if isError
                obj.Logger.warn('ChatUIController', 'code_execution_error', struct(...
                    'block_id', data.blockId, ...
                    'error_message', result), ...
                    'DurationMs', elapsedMs);
            else
                obj.Logger.info('ChatUIController', 'code_execution_complete', struct(...
                    'block_id', data.blockId, ...
                    'result_length', strlength(result)), ...
                    'DurationMs', elapsedMs);
            end

            % Send result back to UI
            obj.sendToJS('codeResult', struct(...
                'success', ~isError, ...
                'output', result, ...
                'blockId', data.blockId));

            % Notify
            notify(obj, 'CodeExecuted');
        end

        function onCopyCode(~, data)
            %ONCOPYCODE Handle code copy request

            clipboard('copy', data.code);
        end

        function onInsertCode(~, data)
            %ONINSERTCODE Handle code insert to editor

            % Insert code at cursor in MATLAB editor
            try
                editorObj = matlab.desktop.editor.getActive();
                if ~isempty(editorObj)
                    editorObj.insertTextAtPositionInLine(data.code, ...
                        editorObj.Selection(1), editorObj.Selection(2));
                end
            catch
                % Editor may not be available
            end
        end

        function onClearChat(obj)
            %ONCLEARCHAT Handle clear chat request

            % Clear local message history
            obj.Messages = {};
            obj.CurrentStreamText = '';
            obj.IsStreaming = false;

            % Clear Python conversation state (this resets the agent)
            if ~isempty(obj.PythonBridge)
                try
                    obj.PythonBridge.clear_conversation();
                catch ME
                    warning('ChatUIController:ClearError', ...
                        'Error clearing Python conversation: %s', ME.message);
                end
            end

            % Update status
            obj.updateStatus('ready', 'Ready');
        end

        function sendCurrentSettings(obj)
            %SENDCURRENTSETTINGS Send current settings to JavaScript

            try
                settings = claudecode.config.Settings.load();

                % Ensure all values are the correct type for JavaScript
                settingsStruct = struct(...
                    'model', char(settings.model), ...
                    'theme', char(settings.theme), ...
                    'codeExecutionMode', char(settings.codeExecutionMode), ...
                    'loggingEnabled', logical(settings.loggingEnabled), ...
                    'logLevel', char(settings.logLevel), ...
                    'logSensitiveData', logical(settings.logSensitiveData), ...
                    'headlessMode', logical(settings.headlessMode));
                obj.sendToJS('loadSettings', settingsStruct);
            catch ME
                % Send default settings if loading fails
                obj.Logger.warn('ChatUIController', 'settings_load_failed', struct(...
                    'error', ME.message));
                defaultSettings = struct(...
                    'model', 'claude-sonnet-4-5-20250514', ...
                    'theme', 'dark', ...
                    'codeExecutionMode', 'prompt', ...
                    'loggingEnabled', true, ...
                    'logLevel', 'INFO', ...
                    'logSensitiveData', true, ...
                    'headlessMode', true);
                obj.sendToJS('loadSettings', defaultSettings);
            end
        end

        function handleSaveSettings(obj, data)
            %HANDLESAVESETTINGS Save settings from JavaScript

            try
                settings = claudecode.config.Settings.load();

                % Update settings from data
                if isfield(data, 'model')
                    settings.model = data.model;
                end
                if isfield(data, 'theme')
                    settings.theme = data.theme;
                end
                if isfield(data, 'codeExecutionMode')
                    settings.codeExecutionMode = data.codeExecutionMode;
                end
                if isfield(data, 'loggingEnabled')
                    settings.loggingEnabled = data.loggingEnabled;
                end
                if isfield(data, 'logLevel')
                    settings.logLevel = data.logLevel;
                end
                if isfield(data, 'logSensitiveData')
                    settings.logSensitiveData = data.logSensitiveData;
                end
                if isfield(data, 'headlessMode')
                    settings.headlessMode = data.headlessMode;
                end

                settings.save();

                % Update Python bridge with new model
                if ~isempty(obj.PythonBridge) && isfield(data, 'model')
                    try
                        obj.PythonBridge.update_model(data.model);
                    catch ME
                        warning('ChatUIController:ModelUpdateError', ...
                            'Error updating model in Python: %s', ME.message);
                    end
                end

                % Update status bar to reflect new model (independent of Python bridge)
                if isfield(data, 'model')
                    obj.updateStatusBar();
                end

                % Update Logger with new settings
                if isfield(data, 'loggingEnabled') || isfield(data, 'logLevel') || isfield(data, 'logSensitiveData')
                    try
                        logger = claudecode.logging.Logger.getInstance();
                        config = logger.getConfig();
                        if isfield(data, 'loggingEnabled')
                            config.Enabled = data.loggingEnabled;
                        end
                        if isfield(data, 'logLevel')
                            config.Level = claudecode.logging.LogLevel.fromString(data.logLevel);
                        end
                        if isfield(data, 'logSensitiveData')
                            config.LogSensitiveData = data.logSensitiveData;
                        end
                    catch ME
                        warning('ChatUIController:LoggerUpdateError', ...
                            'Error updating logger settings: %s', ME.message);
                    end
                end

                % Update Python bridge with headless mode setting
                if ~isempty(obj.PythonBridge) && isfield(data, 'headlessMode')
                    try
                        obj.PythonBridge.set_headless_mode(data.headlessMode);
                    catch ME
                        warning('ChatUIController:HeadlessModeError', ...
                            'Error updating headless mode in Python: %s', ME.message);
                    end
                end

            catch ME
                warning('ChatUIController:SettingsSaveError', ...
                    'Error saving settings: %s', ME.message);
            end
        end

        function onUIReady(obj)
            %ONUIREADY Handle UI ready signal

            obj.IsReady = true;

            % Detect and send theme to UI
            currentTheme = obj.detectMatlabTheme();
            obj.sendToJS('setTheme', struct('theme', currentTheme));

            % Update status bar with model, project, git info
            obj.updateStatusBar();

            % Send welcome message
            obj.sendToJS('showMessage', struct(...
                'role', 'assistant', ...
                'content', 'Welcome to Claude Code! Ask questions about your MATLAB code, get help with Simulink models, or request code changes.'));
        end

        function themeStr = detectMatlabTheme(obj)
            %DETECTMATLABTHEME Detect current MATLAB theme (light or dark)

            themeStr = 'light';  % Default to light

            try
                % Try to get theme from settings (R2025a+)
                s = settings;
                if isprop(s.matlab, 'appearance') && ...
                   isprop(s.matlab.appearance, 'MATLABTheme')
                    themeValue = s.matlab.appearance.MATLABTheme.ActiveValue;
                    if contains(lower(char(themeValue)), 'dark')
                        themeStr = 'dark';
                    end
                end
            catch
                % Fallback: check figure theme if available
                try
                    if ~isempty(obj.ParentFigure) && isvalid(obj.ParentFigure)
                        figTheme = obj.ParentFigure.Theme;
                        if ~isempty(figTheme)
                            baseStyle = figTheme.BaseColorStyle;
                            if strcmpi(baseStyle, 'dark')
                                themeStr = 'dark';
                            end
                        end
                    end
                catch
                    % Keep default light theme
                end
            end
        end

        function addMessage(obj, role, content)
            %ADDMESSAGE Add a message to the history

            msg = struct('role', role, 'content', content, 'timestamp', now);
            obj.Messages{end+1} = msg;

            % Send to UI
            obj.sendToJS('showMessage', struct('role', role, 'content', content));
        end

        function sendToJS(obj, eventName, data)
            %SENDTOJS Send data to JavaScript

            if obj.IsReady && ~isempty(obj.HTMLComponent) && isvalid(obj.HTMLComponent)
                sendEventToHTMLSource(obj.HTMLComponent, eventName, data);
            end
        end

        function [processedMessage, hasContext] = processContextCommand(obj, message)
            %PROCESSCONTEXTCOMMAND Check for /context command and process it
            %
            %   Returns:
            %       processedMessage: Message with /context stripped if present
            %       hasContext: true if /context command was used

            hasContext = false;
            processedMessage = message;

            % Check if message starts with /context
            trimmedMsg = strtrim(message);
            if startsWith(trimmedMsg, '/context', 'IgnoreCase', true)
                hasContext = true;

                % Remove /context from the message
                remainder = strtrim(trimmedMsg(9:end));  % Length of '/context' is 8

                if isempty(remainder)
                    % Just /context alone - add a prompt for Claude
                    processedMessage = 'Please analyze my current MATLAB workspace and Simulink model (if open).';
                else
                    % /context followed by a question
                    processedMessage = remainder;
                end

                obj.Logger.info('ChatUIController', 'context_command_used', struct(...
                    'has_followup', ~isempty(remainder)));
            end
        end

        function contextStr = buildFullContext(obj)
            %BUILDFULLCONTEXT Build full workspace + Simulink context string
            %
            %   Returns combined context from workspace and open Simulink model

            contextStr = '';

            % Add workspace context
            workspaceCtx = obj.WorkspaceProvider.getWorkspaceContext();
            if ~isempty(workspaceCtx)
                contextStr = ['## MATLAB Workspace Context', newline, workspaceCtx];
            end

            % Add Simulink context if available
            if ~isempty(obj.SimulinkBridge)
                simulinkCtx = obj.SimulinkBridge.buildSimulinkContext();
                if ~isempty(simulinkCtx)
                    if ~isempty(contextStr)
                        contextStr = [contextStr, newline, newline];
                    end
                    contextStr = [contextStr, '## Simulink Model Context', newline, simulinkCtx];
                end
            end
        end

        function gitInfo = getGitInfo(~)
            %GETGITINFO Get git branch and diff statistics
            %
            %   Returns struct with fields:
            %       branch: Current branch name (empty if not in a repo)
            %       additions: Total lines added (uncommitted)
            %       deletions: Total lines deleted (uncommitted)

            gitInfo = struct('branch', '', 'additions', 0, 'deletions', 0);

            try
                % Get current branch name (2 second timeout to prevent UI hang)
                if isunix
                    [status, branch] = system('timeout 2 git rev-parse --abbrev-ref HEAD 2>/dev/null');
                else
                    % Windows: no timeout utility, but less common for MATLAB users
                    [status, branch] = system('git rev-parse --abbrev-ref HEAD 2>nul');
                end
                if status == 0 && ~isempty(strtrim(branch))
                    gitInfo.branch = strtrim(branch);
                end

                % Get diff statistics (3 second timeout - this command can be slow on large repos)
                if isunix
                    [status, diffstat] = system('timeout 3 git diff --numstat HEAD 2>/dev/null');
                else
                    [status, diffstat] = system('git diff --numstat HEAD 2>nul');
                end
                if status == 0 && ~isempty(strtrim(diffstat))
                    lines = strsplit(strtrim(diffstat), newline);
                    for i = 1:numel(lines)
                        if isempty(strtrim(lines{i}))
                            continue;
                        end
                        parts = strsplit(lines{i});
                        if numel(parts) >= 2
                            % First column is additions, second is deletions
                            addVal = str2double(parts{1});
                            delVal = str2double(parts{2});
                            if ~isnan(addVal)
                                gitInfo.additions = gitInfo.additions + addVal;
                            end
                            if ~isnan(delVal)
                                gitInfo.deletions = gitInfo.deletions + delVal;
                            end
                        end
                    end
                end
            catch
                % Git not available or not in a repo - return defaults
            end
        end

        function shortName = getModelShortName(obj)
            %GETMODELSHORTNAME Get a short display name for the current model

            shortName = 'Claude';  % Default fallback

            try
                settings = claudecode.config.Settings.load();
                modelId = char(settings.model);

                % Map model IDs to short display names
                if contains(modelId, 'opus')
                    shortName = 'Opus 4.5';
                elseif contains(modelId, 'sonnet')
                    shortName = 'Sonnet 4.5';
                elseif contains(modelId, 'haiku')
                    shortName = 'Haiku 4.5';
                else
                    % Use last part of model ID if unrecognized
                    parts = strsplit(modelId, '-');
                    if numel(parts) >= 2
                        shortName = [upper(parts{2}(1)), parts{2}(2:end)];
                    end
                end
            catch
                % Use default if settings can't be loaded
            end
        end

        function updateStatusBar(obj)
            %UPDATESTATUSBAR Send current status bar data to JavaScript UI
            %
            %   Sends model name, project name, git branch, and diff stats

            try
                % Get model short name
                modelName = obj.getModelShortName();

                % Get project name from current directory
                [~, projectName] = fileparts(pwd);

                % Get git information
                gitInfo = obj.getGitInfo();

                % Send to UI
                obj.sendToJS('statusBarUpdate', struct(...
                    'model', char(modelName), ...
                    'project', char(projectName), ...
                    'branch', char(gitInfo.branch), ...
                    'additions', gitInfo.additions, ...
                    'deletions', gitInfo.deletions));

            catch ME
                obj.Logger.warn('ChatUIController', 'status_bar_update_failed', struct(...
                    'error', ME.message));
            end
        end

        function s = pyDictToStruct(obj, pyDict)
            %PYDICTTOSTRUCT Convert Python dict to MATLAB struct (recursively)

            if ~isa(pyDict, 'py.dict')
                s = pyDict;
                return;
            end

            s = struct(pyDict);

            % Recursively convert nested py.dict fields
            fields = fieldnames(s);
            for i = 1:length(fields)
                fieldVal = s.(fields{i});
                if isa(fieldVal, 'py.dict')
                    s.(fields{i}) = obj.pyDictToStruct(fieldVal);
                elseif isa(fieldVal, 'py.str')
                    s.(fields{i}) = char(fieldVal);
                end
            end
        end
    end
end
