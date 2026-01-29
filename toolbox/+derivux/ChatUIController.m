classdef ChatUIController < handle
    %CHATUICONTROLLER Manages the chat UI and bridges JavaScript/MATLAB communication
    %
    %   This class creates and manages the chat interface using an embedded
    %   HTML webview, handling bidirectional communication between the UI and MATLAB.
    %   Core logic (Claude communication, agents) is handled by Python.
    %
    %   Example:
    %       controller = derivux.ChatUIController(parentFigure, bridge);

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
        InitiatingTabId = '' % Tab that initiated current async request (for session isolation)

        % Polling timeout
        PollingStartTime        % Time when polling started (for max ceiling)
        LastActivityTime        % Time of last content received (for activity timeout)
        MaxPollingDuration = 86400    % Max total polling duration (24 hours) - no timeout
        ActivityTimeout = 86400       % Timeout after no activity (24 hours) - no timeout

        % Interrupt state
        IsInterrupting = false  % Whether an interrupt is in progress
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
            obj.CodeExecutor = derivux.CodeExecutor();
            obj.WorkspaceProvider = derivux.WorkspaceContextProvider();
            obj.Logger = derivux.logging.Logger.getInstance();

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

            % Update streaming state in Python (source of truth)
            if ~isempty(obj.PythonBridge) && ~isempty(obj.InitiatingTabId)
                try
                    obj.PythonBridge.update_streaming_state(obj.InitiatingTabId, true, '');
                catch ME
                    obj.Logger.warn('ChatUIController', 'update_streaming_state_error', struct(...
                        'error', ME.message));
                end
            end

            obj.Logger.info('ChatUIController', 'stream_started', struct(), ...
                'TraceId', obj.CurrentTraceId);
        end

        function sendStreamChunk(obj, chunk)
            %SENDSTREAMCHUNK Append a streaming text chunk

            obj.CurrentStreamText = [obj.CurrentStreamText, chunk];
            obj.StreamChunkCount = obj.StreamChunkCount + 1;
            obj.sendToJS('streamChunk', struct('text', chunk));

            % Periodically sync stream text to Python (every 10 chunks)
            % This allows recovery if JS context is lost mid-stream
            if mod(obj.StreamChunkCount, 10) == 0
                if ~isempty(obj.PythonBridge) && ~isempty(obj.InitiatingTabId)
                    try
                        obj.PythonBridge.update_streaming_state(...
                            obj.InitiatingTabId, true, obj.CurrentStreamText);
                    catch
                        % Ignore sync errors - not critical
                    end
                end
            end

            % Log at TRACE level to avoid log bloat
            obj.Logger.trace('ChatUIController', 'stream_chunk', struct(...
                'chunk_size', strlength(chunk), ...
                'chunk_number', obj.StreamChunkCount), ...
                'TraceId', obj.CurrentTraceId);
        end

        function endStreaming(obj)
            %ENDSTREAMING Signal end of streaming response

            responseLength = strlength(obj.CurrentStreamText);
            tabIdForPersist = obj.InitiatingTabId;  % Capture before clearing

            if ~isempty(obj.CurrentStreamText)
                % Store in history without sending to UI (JS finalizeStreamingMessage handles UI)
                msg = struct('role', 'assistant', 'content', obj.CurrentStreamText, 'timestamp', now);
                obj.Messages{end+1} = msg;

                % Persist assistant message to Python state (source of truth)
                if ~isempty(obj.PythonBridge) && ~isempty(tabIdForPersist)
                    try
                        obj.PythonBridge.add_message(tabIdForPersist, 'assistant', obj.CurrentStreamText, py.list({}));
                        % Also update streaming state to false
                        obj.PythonBridge.update_streaming_state(tabIdForPersist, false, '');
                    catch ME
                        obj.Logger.warn('ChatUIController', 'persist_assistant_message_error', struct(...
                            'error', ME.message));
                    end
                end
            end
            obj.IsStreaming = false;
            obj.CurrentStreamText = '';
            obj.updateStatus('ready', 'Ready');
            obj.sendToJS('endStreaming', struct());

            obj.Logger.info('ChatUIController', 'stream_complete', struct(...
                'response_length', responseLength, ...
                'total_chunks', obj.StreamChunkCount, ...
                'initiating_tab', obj.InitiatingTabId), ...
                'TraceId', obj.CurrentTraceId);

            % Clear initiating tab ID after completion
            obj.InitiatingTabId = '';

            % Check for pending interventions (e.g., execution intent in Plan mode)
            obj.checkForPendingIntervention();
        end

        function sendError(obj, message)
            %SENDERROR Display an error message

            obj.addMessage('error', message);
            obj.IsStreaming = false;
            obj.InitiatingTabId = '';  % Clear initiating tab on error
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
                        obj.onClearChat(eventData);

                    case 'requestSettings'
                        obj.sendCurrentSettings();

                    case 'saveSettings'
                        obj.handleSaveSettings(eventData);

                    case 'setAuthMethod'
                        obj.handleSetAuthMethod(eventData);

                    case 'validateApiKey'
                        obj.handleValidateApiKey(eventData);

                    case 'clearApiKey'
                        obj.handleClearApiKey();

                    case 'cliLogin'
                        obj.handleCliLogin();

                    case 'requestAuthStatus'
                        obj.sendAuthStatus();

                    case 'setExecutionMode'
                        obj.handleSetExecutionMode(eventData);

                    % Multi-session tab events
                    case 'createSession'
                        obj.handleCreateSession(eventData);

                    case 'closeSession'
                        obj.handleCloseSession(eventData);

                    case 'switchSession'
                        obj.handleSwitchSession(eventData);

                    case 'interruptRequest'
                        obj.handleInterruptRequest(eventData);

                    % Tab state persistence events (Python as source of truth)
                    case 'requestFullState'
                        obj.handleRequestFullState(eventData);

                    case 'saveScrollPosition'
                        obj.handleSaveScrollPosition(eventData);

                    case 'addMessageToState'
                        obj.handleAddMessageToState(eventData);

                    case 'updateStreamingState'
                        obj.handleUpdateStreamingState(eventData);

                    case 'dismissIntervention'
                        obj.handleDismissIntervention(eventData);

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

            % Capture initiating tab ID for session isolation
            % This ensures streaming responses go to the correct tab even if user switches
            if isfield(data, 'tabId')
                obj.InitiatingTabId = char(data.tabId);
            else
                obj.InitiatingTabId = '';
            end

            % Generate trace ID for this message flow
            obj.CurrentTraceId = sprintf('msg_%s', datestr(now, 'HHMMSS_FFF'));

            % Log message received with initiating tab for session tracing
            obj.Logger.info('ChatUIController', 'message_received', struct(...
                'message_length', strlength(message), ...
                'initiating_tab', obj.InitiatingTabId), ...
                'TraceId', obj.CurrentTraceId);

            % Check for /context command
            [processedMessage, hasContext] = obj.processContextCommand(message);
            message = processedMessage;

            % Add user message to history
            obj.addMessage('user', message);

            % Persist user message to Python state (source of truth)
            if ~isempty(obj.PythonBridge) && ~isempty(obj.InitiatingTabId)
                try
                    obj.PythonBridge.add_message(obj.InitiatingTabId, 'user', message, py.list({}));
                catch ME
                    obj.Logger.warn('ChatUIController', 'add_message_to_state_error', struct(...
                        'error', ME.message));
                end
            end

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

            % Load timeout setting (allows mid-session changes)
            try
                settings = derivux.config.Settings.load();
                obj.MaxPollingDuration = settings.maxPollingDuration;
            catch
                % Keep default if settings fail to load
            end

            % Record start time for timeout detection
            obj.PollingStartTime = tic;
            obj.LastActivityTime = tic;  % Initialize activity timer

            obj.PollingTimer = timer(...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', 0.05, ...  % 50ms polling
                'TimerFcn', @(~,~) obj.pollAsyncResponse());
            start(obj.PollingTimer);
        end

        function pollAsyncResponse(obj)
            %POLLASYNCRESPONSE Poll Python for async response content

            try
                % Check for activity-based timeout (no content received recently)
                if ~isempty(obj.LastActivityTime)
                    inactiveTime = toc(obj.LastActivityTime);
                    totalTime = toc(obj.PollingStartTime);

                    % Timeout if no activity for ActivityTimeout seconds
                    % Also enforce MaxPollingDuration as an absolute safety ceiling
                    if inactiveTime > obj.ActivityTimeout || totalTime > obj.MaxPollingDuration
                        % Timeout occurred - stop polling and show error
                        timeoutReason = 'inactivity';
                        if totalTime > obj.MaxPollingDuration
                            timeoutReason = 'max_duration';
                        end

                        obj.Logger.warn('ChatUIController', 'polling_timeout', struct(...
                            'inactive_seconds', inactiveTime, ...
                            'total_seconds', totalTime, ...
                            'timeout_reason', timeoutReason, ...
                            'activity_timeout', obj.ActivityTimeout, ...
                            'max_duration', obj.MaxPollingDuration), ...
                            'TraceId', obj.CurrentTraceId);

                        if ~isempty(obj.PollingTimer) && isvalid(obj.PollingTimer)
                            stop(obj.PollingTimer);
                            delete(obj.PollingTimer);
                            obj.PollingTimer = [];
                        end
                        obj.endStreaming();

                        if strcmp(timeoutReason, 'inactivity')
                            obj.sendError(sprintf(...
                                'Request timed out after %.0f seconds of inactivity. The AI may be unavailable. Please try again.', ...
                                inactiveTime));
                        else
                            obj.sendError(sprintf(...
                                'Request exceeded maximum duration of %.0f seconds. Please try a simpler request.', ...
                                totalTime));
                        end
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

                        % Reset activity timeout on any content received
                        obj.LastActivityTime = tic;
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
            %
            %   Execution behavior depends on the current execution mode:
            %   - 'plan': No execution (blocked at UI level, but safety check here)
            %   - 'prompt': Always prompts for approval before execution
            %   - 'auto': Smart auto-execute - safe code runs, dangerous prompts
            %   - 'bypass': No restrictions - all code executes without checks

            code = data.code;
            startTime = tic;

            obj.Logger.info('ChatUIController', 'code_execution_requested', struct(...
                'code_length', strlength(code), ...
                'block_id', data.blockId));

            % Load current execution mode from Settings
            try
                settings = derivux.config.Settings.load();
                mode = char(settings.codeExecutionMode);
            catch
                mode = 'prompt';  % Default to safest mode
            end

            % Configure CodeExecutor based on execution mode
            switch mode
                case 'plan'
                    % Plan mode: shouldn't reach here, but block if it does
                    obj.Logger.warn('ChatUIController', 'code_execution_blocked_plan_mode');
                    obj.sendToJS('codeResult', struct(...
                        'success', false, ...
                        'output', 'Code execution is disabled in Plan mode. Switch to Normal, Auto, or Bypass mode to execute code.', ...
                        'blockId', data.blockId));
                    return;

                case 'prompt'
                    % Prompt mode: always require approval
                    obj.CodeExecutor.RequireApproval = true;
                    obj.CodeExecutor.BypassMode = false;
                    obj.CodeExecutor.AllowSystemCommands = false;
                    obj.CodeExecutor.AllowDestructiveOps = false;

                case 'auto'
                    % Auto mode: smart execution - only prompt for dangerous code
                    isDangerous = obj.CodeExecutor.preValidateCode(code);
                    obj.CodeExecutor.RequireApproval = isDangerous;
                    obj.CodeExecutor.BypassMode = false;
                    obj.CodeExecutor.AllowSystemCommands = false;
                    obj.CodeExecutor.AllowDestructiveOps = false;

                    if isDangerous
                        obj.Logger.info('ChatUIController', 'auto_mode_dangerous_code', struct(...
                            'block_id', data.blockId, ...
                            'prompting', true));
                    end

                case 'bypass'
                    % Bypass mode: DANGEROUS - no restrictions
                    obj.CodeExecutor.RequireApproval = false;
                    obj.CodeExecutor.BypassMode = true;
                    obj.CodeExecutor.AllowSystemCommands = true;
                    obj.CodeExecutor.AllowDestructiveOps = true;

                    obj.Logger.warn('ChatUIController', 'bypass_mode_execution', struct(...
                        'block_id', data.blockId, ...
                        'code_length', strlength(code)));

                otherwise
                    % Unknown mode - default to safest behavior
                    obj.CodeExecutor.RequireApproval = true;
                    obj.CodeExecutor.BypassMode = false;
            end

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

        function onClearChat(obj, eventData)
            %ONCLEARCHAT Handle clear chat request
            %
            %   eventData may contain tabId for session-specific clearing

            % Get tabId if provided
            tabId = '';
            if nargin > 1 && isstruct(eventData) && isfield(eventData, 'tabId')
                tabId = char(eventData.tabId);
            end

            % Clear local message history
            obj.Messages = {};
            obj.CurrentStreamText = '';
            obj.IsStreaming = false;

            % Clear Python conversation state (this resets the agent)
            if ~isempty(obj.PythonBridge)
                try
                    obj.PythonBridge.clear_conversation();

                    % Also clear tab state in Python (source of truth)
                    if ~isempty(tabId)
                        obj.PythonBridge.clear_tab(tabId);
                    end
                catch ME
                    warning('ChatUIController:ClearError', ...
                        'Error clearing Python conversation: %s', ME.message);
                end
            end

            % Update status
            obj.updateStatus('ready', 'Ready');

            % Log with tabId if available
            if ~isempty(tabId)
                obj.Logger.debug('ChatUIController', 'chat_cleared', struct('tabId', tabId));
            end
        end

        function sendCurrentSettings(obj)
            %SENDCURRENTSETTINGS Send current settings to JavaScript

            try
                settings = derivux.config.Settings.load();

                % Get auth info from CredentialStore
                authInfo = derivux.config.CredentialStore.getAuthInfo();

                % Ensure all values are the correct type for JavaScript
                settingsStruct = struct(...
                    'model', char(settings.model), ...
                    'theme', char(settings.theme), ...
                    'codeExecutionMode', char(settings.codeExecutionMode), ...
                    'loggingEnabled', logical(settings.loggingEnabled), ...
                    'logLevel', char(settings.logLevel), ...
                    'logSensitiveData', logical(settings.logSensitiveData), ...
                    'headlessMode', logical(settings.headlessMode), ...
                    'maxPollingDuration', double(settings.maxPollingDuration), ...
                    'allowBypassModeCycling', logical(settings.allowBypassModeCycling), ...
                    'authMethod', authInfo.authMethod, ...
                    'hasApiKey', authInfo.hasApiKey, ...
                    'apiKeyMasked', authInfo.apiKeyMasked);
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
                    'headlessMode', true, ...
                    'maxPollingDuration', 86400, ...
                    'allowBypassModeCycling', false, ...
                    'authMethod', 'subscription', ...
                    'hasApiKey', false, ...
                    'apiKeyMasked', '');
                obj.sendToJS('loadSettings', defaultSettings);
            end
        end

        function handleSaveSettings(obj, data)
            %HANDLESAVESETTINGS Save settings from JavaScript

            try
                settings = derivux.config.Settings.load();

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
                if isfield(data, 'maxPollingDuration')
                    settings.maxPollingDuration = data.maxPollingDuration;
                end
                if isfield(data, 'allowBypassModeCycling')
                    settings.allowBypassModeCycling = data.allowBypassModeCycling;
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
                        logger = derivux.logging.Logger.getInstance();
                        config = logger.getConfig();
                        if isfield(data, 'loggingEnabled')
                            config.Enabled = data.loggingEnabled;
                        end
                        if isfield(data, 'logLevel')
                            config.Level = derivux.logging.LogLevel.fromString(data.logLevel);
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

        function handleSetAuthMethod(obj, data)
            %HANDLESETAUTHMETHOD Save authentication method preference

            try
                if isfield(data, 'method')
                    method = char(data.method);

                    % Save to settings
                    settings = derivux.config.Settings.load();
                    settings.authMethod = method;
                    settings.save();

                    % Also save to CredentialStore for persistence
                    derivux.config.CredentialStore.setAuthMethod(method);

                    % Update Python bridge
                    if ~isempty(obj.PythonBridge)
                        try
                            obj.PythonBridge.set_auth_method(method);
                        catch ME
                            warning('ChatUIController:AuthMethodError', ...
                                'Error updating auth method in Python: %s', ME.message);
                        end
                    end

                    % Update status bar
                    obj.updateStatusBar();

                    obj.Logger.info('ChatUIController', 'auth_method_changed', struct(...
                        'method', method));
                end
            catch ME
                warning('ChatUIController:SetAuthMethodError', ...
                    'Error setting auth method: %s', ME.message);
            end
        end

        function handleValidateApiKey(obj, data)
            %HANDLEVALIDATEAPIKEY Validate API key and store if valid

            try
                if ~isfield(data, 'apiKey')
                    obj.sendToJS('apiKeyValidationResult', struct(...
                        'valid', false, ...
                        'message', 'No API key provided'));
                    return;
                end

                apiKey = char(data.apiKey);

                % Use CredentialStore to validate format
                isValid = derivux.config.CredentialStore.validateApiKey(apiKey);

                if isValid
                    % Store the API key
                    derivux.config.CredentialStore.setApiKey(apiKey);

                    % Set in Python bridge environment
                    if ~isempty(obj.PythonBridge)
                        try
                            obj.PythonBridge.set_api_key(apiKey);
                        catch ME
                            warning('ChatUIController:ApiKeyEnvError', ...
                                'Error setting API key in Python: %s', ME.message);
                        end
                    end

                    % Get masked version for display
                    authInfo = derivux.config.CredentialStore.getAuthInfo();

                    obj.sendToJS('apiKeyValidationResult', struct(...
                        'valid', true, ...
                        'message', ['API key validated and stored: ', authInfo.apiKeyMasked]));

                    obj.Logger.info('ChatUIController', 'api_key_validated_and_stored');
                else
                    obj.sendToJS('apiKeyValidationResult', struct(...
                        'valid', false, ...
                        'message', 'Invalid API key format. Keys should start with "sk-ant-" and be 100+ characters.'));
                end
            catch ME
                obj.sendToJS('apiKeyValidationResult', struct(...
                    'valid', false, ...
                    'message', ['Validation error: ', ME.message]));
                warning('ChatUIController:ValidateApiKeyError', ...
                    'Error validating API key: %s', ME.message);
            end
        end

        function handleClearApiKey(obj)
            %HANDLECLEARAPIKEY Clear stored API key

            try
                % Clear from CredentialStore
                derivux.config.CredentialStore.clearApiKey();

                % Clear from Python bridge environment
                if ~isempty(obj.PythonBridge)
                    try
                        obj.PythonBridge.clear_api_key();
                    catch ME
                        warning('ChatUIController:ClearApiKeyEnvError', ...
                            'Error clearing API key in Python: %s', ME.message);
                    end
                end

                % Send updated status to UI
                obj.sendAuthStatus();

                obj.Logger.info('ChatUIController', 'api_key_cleared');
            catch ME
                warning('ChatUIController:ClearApiKeyError', ...
                    'Error clearing API key: %s', ME.message);
            end
        end

        function handleCliLogin(obj)
            %HANDLECLILOGIN Start Claude CLI login process
            %
            %   This will automatically install the Claude CLI if it's not
            %   already installed, then open the browser for authentication.

            try
                if ~isempty(obj.PythonBridge)
                    % Update status to show we're working
                    obj.sendToJS('cliLoginResult', struct(...
                        'started', false, ...
                        'installing', true, ...
                        'message', 'Checking Claude CLI installation...'));

                    result = obj.PythonBridge.start_cli_login();
                    result = obj.pyDictToStruct(result);

                    % Check for installing flag (CLI was just installed)
                    installing = false;
                    if isfield(result, 'installing')
                        installing = logical(result.installing);
                    end

                    obj.sendToJS('cliLoginResult', struct(...
                        'started', logical(result.started), ...
                        'installing', installing, ...
                        'message', char(result.message)));

                    obj.Logger.info('ChatUIController', 'cli_login_started', struct(...
                        'started', result.started, ...
                        'installing', installing));
                else
                    obj.sendToJS('cliLoginResult', struct(...
                        'started', false, ...
                        'installing', false, ...
                        'message', 'Python bridge not available'));
                end
            catch ME
                obj.sendToJS('cliLoginResult', struct(...
                    'started', false, ...
                    'installing', false, ...
                    'message', ['Login error: ', ME.message]));
                warning('ChatUIController:CliLoginError', ...
                    'Error starting CLI login: %s', ME.message);
            end
        end

        function sendAuthStatus(obj)
            %SENDAUTHSTATUS Send current authentication status to UI

            try
                % Get auth info from CredentialStore
                authInfo = derivux.config.CredentialStore.getAuthInfo();

                statusData = struct();
                statusData.authMethod = authInfo.authMethod;
                statusData.hasApiKey = authInfo.hasApiKey;
                statusData.apiKeyMasked = authInfo.apiKeyMasked;

                % Get CLI auth status from Python
                if ~isempty(obj.PythonBridge)
                    try
                        cliStatus = obj.PythonBridge.check_cli_auth_status();
                        cliStatus = obj.pyDictToStruct(cliStatus);
                        statusData.cliAuthenticated = logical(cliStatus.authenticated);
                        statusData.cliEmail = char(cliStatus.email);
                        statusData.cliMessage = char(cliStatus.message);
                    catch ME
                        statusData.cliAuthenticated = false;
                        statusData.cliEmail = '';
                        statusData.cliMessage = ['Error checking CLI status: ', ME.message];
                    end
                else
                    statusData.cliAuthenticated = false;
                    statusData.cliEmail = '';
                    statusData.cliMessage = 'Python bridge not available';
                end

                obj.sendToJS('authStatusUpdate', statusData);

            catch ME
                warning('ChatUIController:SendAuthStatusError', ...
                    'Error sending auth status: %s', ME.message);
            end
        end

        function handleSetExecutionMode(obj, data)
            %HANDLESETEXECUTIONMODE Handle execution mode change from UI
            %
            %   This handles the setExecutionMode event from JavaScript when
            %   the user clicks the status bar indicator or changes the dropdown.
            %
            %   Modes:
            %   - 'plan': Interview/planning mode - no code execution
            %   - 'prompt': Normal mode - prompts before each code execution
            %   - 'auto': Auto mode - executes automatically (security blocks active)
            %   - 'bypass': DANGEROUS - removes all restrictions

            try
                if ~isfield(data, 'mode')
                    return;
                end

                mode = char(data.mode);

                % Save to settings
                settings = derivux.config.Settings.load();
                settings.codeExecutionMode = mode;
                settings.save();

                % Log warning for dangerous modes
                if strcmp(mode, 'bypass')
                    obj.Logger.warn('ChatUIController', 'bypass_mode_enabled', struct(...
                        'warning', 'ALL SAFETY RESTRICTIONS DISABLED'));
                elseif strcmp(mode, 'auto')
                    obj.Logger.info('ChatUIController', 'auto_mode_enabled', struct(...
                        'note', 'Auto-execution enabled, security blocks still active'));
                else
                    obj.Logger.info('ChatUIController', 'execution_mode_changed', struct(...
                        'mode', mode));
                end

                % Update Python bridge with new mode (if method exists)
                if ~isempty(obj.PythonBridge)
                    try
                        obj.PythonBridge.set_execution_mode(mode);
                    catch
                        % Method may not exist yet - that's OK
                    end
                end

                % Update status bar
                obj.updateStatusBar();

            catch ME
                warning('ChatUIController:SetExecutionModeError', ...
                    'Error setting execution mode: %s', ME.message);
            end
        end

        function handleCreateSession(obj, eventData)
            %HANDLECREATESESSION Handle create session event from JavaScript
            %
            %   Called when user creates a new tab in the UI.
            %   Creates tab in Python (source of truth for tab state).

            try
                if ~isfield(eventData, 'tabId')
                    return;
                end

                tabId = char(eventData.tabId);
                label = '';
                if isfield(eventData, 'label')
                    label = char(eventData.label);
                end

                % Create in Python (source of truth)
                if ~isempty(obj.PythonBridge)
                    obj.PythonBridge.create_tab(tabId, label);
                end

                obj.Logger.info('ChatUIController', 'session_created', struct(...
                    'tabId', tabId, 'label', label));
            catch ME
                obj.Logger.warn('ChatUIController', 'create_session_error', struct(...
                    'error', ME.message));
            end
        end

        function handleCloseSession(obj, eventData)
            %HANDLECLOSESESSION Handle close session event from JavaScript
            %
            %   Called when user closes a tab in the UI.
            %   Closes tab in Python (source of truth for tab state).

            try
                if ~isfield(eventData, 'tabId')
                    return;
                end

                tabId = char(eventData.tabId);

                % Close in Python (source of truth)
                if ~isempty(obj.PythonBridge)
                    obj.PythonBridge.close_tab(tabId);
                end

                obj.Logger.info('ChatUIController', 'session_closed', struct(...
                    'tabId', tabId));
            catch ME
                obj.Logger.warn('ChatUIController', 'close_session_error', struct(...
                    'error', ME.message));
            end
        end

        function handleSwitchSession(obj, eventData)
            %HANDLESWITCHSESSION Handle switch session event from JavaScript
            %
            %   Called when user switches between tabs in the UI.
            %   Switches tab in Python (source of truth for tab state).

            try
                if ~isfield(eventData, 'tabId')
                    return;
                end

                tabId = char(eventData.tabId);
                fromTabId = '';
                scrollPos = 0;

                if isfield(eventData, 'fromTabId')
                    fromTabId = char(eventData.fromTabId);
                end
                if isfield(eventData, 'scrollPosition')
                    scrollPos = double(eventData.scrollPosition);
                end

                % Switch in Python (source of truth) with scroll position
                if ~isempty(obj.PythonBridge)
                    obj.PythonBridge.switch_tab(fromTabId, tabId, scrollPos);
                end

                obj.Logger.debug('ChatUIController', 'session_switched', struct(...
                    'tabId', tabId, 'fromTabId', fromTabId));
            catch ME
                obj.Logger.warn('ChatUIController', 'switch_session_error', struct(...
                    'error', ME.message));
            end
        end

        function handleInterruptRequest(obj, ~)
            %HANDLEINTERRUPTREQUEST Handle interrupt request from JavaScript
            %
            %   Called when user presses ESC twice (double-ESC) to interrupt
            %   the current Claude request. Similar to Claude Code's behavior.

            try
                % Check if we're actually streaming
                if ~obj.IsStreaming
                    obj.Logger.debug('ChatUIController', 'interrupt_ignored_not_streaming');
                    return;
                end

                % Prevent multiple interrupts
                if obj.IsInterrupting
                    obj.Logger.debug('ChatUIController', 'interrupt_ignored_already_interrupting');
                    return;
                end

                obj.IsInterrupting = true;

                obj.Logger.info('ChatUIController', 'interrupt_requested', struct(...
                    'trace_id', obj.CurrentTraceId, ...
                    'initiating_tab', obj.InitiatingTabId));

                % Stop polling immediately
                obj.stopPolling();

                % Interrupt the Python process
                if ~isempty(obj.PythonBridge)
                    try
                        obj.PythonBridge.interrupt_process();
                    catch ME
                        obj.Logger.warn('ChatUIController', 'interrupt_python_error', struct(...
                            'error', ME.message));
                    end
                end

                % Append interrupted message to stream
                if ~isempty(obj.CurrentStreamText)
                    obj.sendStreamChunk(newline + newline + '_[Response interrupted by user]_');
                end

                % End streaming
                obj.endStreaming();

                % Send interrupt complete event to JavaScript
                obj.sendToJS('interruptComplete', struct('timestamp', now));

                % Reset interrupt state
                obj.IsInterrupting = false;

                obj.Logger.info('ChatUIController', 'interrupt_complete', struct(...
                    'trace_id', obj.CurrentTraceId));

            catch ME
                obj.IsInterrupting = false;
                obj.Logger.error('ChatUIController', 'interrupt_error', struct(...
                    'error', ME.message));
                warning('ChatUIController:InterruptError', ...
                    'Error handling interrupt: %s', ME.message);
            end
        end

        function handleRequestFullState(obj, ~)
            %HANDLEREQUESTFULLSTATE Return complete tab state to JavaScript
            %
            %   Called by JavaScript on initialization to restore state after
            %   uihtml component regeneration (resize, dock/undock).
            %   Python is the source of truth for all tab state.

            try
                if isempty(obj.PythonBridge)
                    obj.sendToJS('fullStateResponse', struct('tabs', {{}}, ...
                        'activeTabId', '', 'nextTabNumber', 1));
                    return;
                end

                % Get complete state from Python
                pyState = obj.PythonBridge.get_all_tab_state();
                matlabState = obj.pyDictToStruct(pyState);

                % Convert Python list to MATLAB cell array
                tabsList = {};
                if isfield(matlabState, 'tabs')
                    pyTabs = matlabState.tabs;
                    if isa(pyTabs, 'py.list')
                        tabsList = cell(pyTabs);
                        % Convert each tab dict to struct
                        for i = 1:length(tabsList)
                            if isa(tabsList{i}, 'py.dict')
                                tabsList{i} = obj.pyDictToStruct(tabsList{i});
                            end
                        end
                    end
                end

                % Send to JavaScript
                responseData = struct(...
                    'tabs', {tabsList}, ...
                    'activeTabId', char(matlabState.activeTabId), ...
                    'nextTabNumber', double(matlabState.nextTabNumber));

                obj.sendToJS('fullStateResponse', responseData);

                obj.Logger.info('ChatUIController', 'full_state_sent', struct(...
                    'tab_count', length(tabsList)));

            catch ME
                obj.Logger.error('ChatUIController', 'request_full_state_error', struct(...
                    'error', ME.message));
                % Send empty state on error (JS will create initial tab)
                obj.sendToJS('fullStateResponse', struct('tabs', {{}}, ...
                    'activeTabId', '', 'nextTabNumber', 1));
            end
        end

        function handleSaveScrollPosition(obj, eventData)
            %HANDLESAVESCROLLPOSITION Save scroll position for a tab
            %
            %   Called by JavaScript when user scrolls or switches tabs

            try
                if ~isfield(eventData, 'tabId') || ~isfield(eventData, 'scrollPosition')
                    return;
                end

                tabId = char(eventData.tabId);
                scrollPos = double(eventData.scrollPosition);

                if ~isempty(obj.PythonBridge)
                    obj.PythonBridge.save_scroll_position(tabId, scrollPos);
                end
            catch ME
                obj.Logger.warn('ChatUIController', 'save_scroll_error', struct(...
                    'error', ME.message));
            end
        end

        function handleAddMessageToState(obj, eventData)
            %HANDLEADDMESSAGETOSTATE Add a message to tab state in Python
            %
            %   Called by JavaScript when user sends a message or assistant responds

            try
                if ~isfield(eventData, 'tabId') || ~isfield(eventData, 'role') || ~isfield(eventData, 'content')
                    return;
                end

                tabId = char(eventData.tabId);
                role = char(eventData.role);
                content = char(eventData.content);

                % Get images if present
                images = {};
                if isfield(eventData, 'images')
                    images = eventData.images;
                end

                if ~isempty(obj.PythonBridge)
                    obj.PythonBridge.add_message(tabId, role, content, py.list(images));
                end

                obj.Logger.debug('ChatUIController', 'message_added_to_state', struct(...
                    'tabId', tabId, 'role', role));

            catch ME
                obj.Logger.warn('ChatUIController', 'add_message_error', struct(...
                    'error', ME.message));
            end
        end

        function handleUpdateStreamingState(obj, eventData)
            %HANDLEUPDATESTREAMINGSTATE Update streaming state in Python
            %
            %   Called by JavaScript during streaming to keep Python in sync

            try
                if ~isfield(eventData, 'tabId')
                    return;
                end

                tabId = char(eventData.tabId);
                isStreaming = false;
                currentText = '';

                if isfield(eventData, 'isStreaming')
                    isStreaming = logical(eventData.isStreaming);
                end
                if isfield(eventData, 'currentText')
                    currentText = char(eventData.currentText);
                end

                if ~isempty(obj.PythonBridge)
                    obj.PythonBridge.update_streaming_state(tabId, isStreaming, currentText);
                end

            catch ME
                obj.Logger.warn('ChatUIController', 'update_streaming_error', struct(...
                    'error', ME.message));
            end
        end

        function handleDismissIntervention(obj, ~)
            %HANDLEDISMISSINTERVENTION Dismiss pending intervention in Python
            %
            %   Called by JavaScript when user cancels or dismisses the
            %   execution intent modal without selecting a mode.

            try
                if ~isempty(obj.PythonBridge)
                    obj.PythonBridge.dismiss_intervention();
                    obj.Logger.debug('ChatUIController', 'intervention_dismissed');
                end
            catch ME
                obj.Logger.warn('ChatUIController', 'dismiss_intervention_error', struct(...
                    'error', ME.message));
            end
        end

        function checkForPendingIntervention(obj)
            %CHECKFORPENDINGINTERVENTION Check if there's an execution intent intervention
            %
            %   Called after streaming completes to check for pending
            %   interventions (specifically execution_intent in Plan mode).

            try
                if isempty(obj.PythonBridge)
                    return;
                end

                % Get pending intervention from Python
                intervention = obj.PythonBridge.get_pending_intervention();

                if ~isempty(intervention)
                    intervention = obj.pyDictToStruct(intervention);

                    % Only handle execution_intent type
                    if isfield(intervention, 'type') && strcmp(char(intervention.type), 'execution_intent')
                        obj.Logger.info('ChatUIController', 'execution_intent_detected', struct(...
                            'confidence', intervention.confidence));

                        % Send prompt to JavaScript
                        obj.sendToJS('executionIntentPrompt', struct(...
                            'type', char(intervention.type), ...
                            'message', char(intervention.message), ...
                            'confidence', intervention.confidence, ...
                            'suggested_mode', char(intervention.suggested_mode)));
                    end
                end

            catch ME
                obj.Logger.warn('ChatUIController', 'check_intervention_error', struct(...
                    'error', ME.message));
            end
        end

        function updateTabStatus(obj, tabId, status)
            %UPDATETABSTATUS Send tab status update to JavaScript
            %
            %   updateTabStatus(obj, tabId, status)
            %
            %   tabId: The tab/session ID
            %   status: Status string ('ready', 'working', 'attention', 'unread')

            obj.sendToJS('tabStatusUpdate', struct(...
                'tabId', tabId, ...
                'status', status));
        end

        function onUIReady(obj)
            %ONUIREADY Handle UI ready signal

            obj.IsReady = true;

            % Detect and send theme to UI
            currentTheme = obj.detectMatlabTheme();
            obj.sendToJS('setTheme', struct('theme', currentTheme));

            % Update status bar with model, project, git info
            obj.updateStatusBar();

            % Note: Welcome message is now shown by JavaScript TabManager
            % when creating the initial tab
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
                settings = derivux.config.Settings.load();
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
            %   Sends model name, project name, git branch, diff stats, auth method,
            %   and execution mode

            try
                % Get model short name
                modelName = obj.getModelShortName();

                % Get project name from current directory
                [~, projectName] = fileparts(pwd);

                % Get git information
                gitInfo = obj.getGitInfo();

                % Get auth method
                authMethod = derivux.config.CredentialStore.getAuthMethod();

                % Get execution mode
                settings = derivux.config.Settings.load();
                executionMode = char(settings.codeExecutionMode);

                % Send to UI
                obj.sendToJS('statusBarUpdate', struct(...
                    'model', char(modelName), ...
                    'project', char(projectName), ...
                    'branch', char(gitInfo.branch), ...
                    'additions', gitInfo.additions, ...
                    'deletions', gitInfo.deletions, ...
                    'authMethod', authMethod, ...
                    'executionMode', executionMode));

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
