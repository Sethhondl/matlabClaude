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

        % State
        Messages = {}       % Cell array of message structs
        IsStreaming = false % Whether currently streaming
        CurrentStreamText = '' % Accumulated text during streaming
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

            obj.createUI();
        end

        function delete(obj)
            %DELETE Destructor

            % Stop polling timer
            if ~isempty(obj.PollingTimer) && isvalid(obj.PollingTimer)
                stop(obj.PollingTimer);
                delete(obj.PollingTimer);
            end
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
            obj.updateStatus('streaming', 'Claude is thinking...');
            obj.sendToJS('startStreaming', struct());
        end

        function sendStreamChunk(obj, chunk)
            %SENDSTREAMCHUNK Append a streaming text chunk

            obj.CurrentStreamText = [obj.CurrentStreamText, chunk];
            obj.sendToJS('streamChunk', struct('text', chunk));
        end

        function endStreaming(obj)
            %ENDSTREAMING Signal end of streaming response

            if ~isempty(obj.CurrentStreamText)
                % Store in history without sending to UI (JS finalizeStreamingMessage handles UI)
                msg = struct('role', 'assistant', 'content', obj.CurrentStreamText, 'timestamp', now);
                obj.Messages{end+1} = msg;
            end
            obj.IsStreaming = false;
            obj.CurrentStreamText = '';
            obj.updateStatus('ready', 'Ready');
            obj.sendToJS('endStreaming', struct());
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
                return;
            end

            message = data.content;
            if isempty(strtrim(message))
                return;
            end

            % Add user message to history
            obj.addMessage('user', message);

            % Notify via event
            notify(obj, 'MessageSent');

            % Build context for agents
            context = py.dict();
            if isfield(data, 'includeWorkspace') && data.includeWorkspace
                workspaceCtx = obj.WorkspaceProvider.getWorkspaceContext();
                context{'workspace'} = workspaceCtx;
            end
            if isfield(data, 'includeSimulink') && data.includeSimulink && ~isempty(obj.SimulinkBridge)
                simulinkCtx = obj.SimulinkBridge.buildSimulinkContext();
                context{'simulink'} = simulinkCtx;
            end

            % Check if any Python agent can handle this message
            agentResult = obj.PythonBridge.dispatch_to_agent(message, context);
            agentResult = obj.pyDictToStruct(agentResult);

            if agentResult.handled
                % Agent handled it - show response directly
                obj.sendAssistantMessage(char(agentResult.response));
                return;
            end

            % No agent handled it - send to Claude via Python
            % Always include directory and editor context
            contextStr = obj.WorkspaceProvider.getCurrentDirectoryContext();
            contextStr = [contextStr, newline, newline, obj.WorkspaceProvider.getEditorContext()];

            % Optionally include workspace context
            if isfield(data, 'includeWorkspace') && data.includeWorkspace
                contextStr = [contextStr, newline, newline, obj.WorkspaceProvider.getWorkspaceContext()];
            end
            % Optionally include Simulink context
            if isfield(data, 'includeSimulink') && data.includeSimulink && ~isempty(obj.SimulinkBridge)
                contextStr = [contextStr, newline, newline, obj.SimulinkBridge.buildSimulinkContext()];
            end

            obj.startStreaming();

            % Start async message via Python
            obj.PythonBridge.start_async_message(message, contextStr);

            % Start polling for responses
            obj.startPolling();
        end

        function startPolling(obj)
            %STARTPOLLING Start polling for async response chunks

            obj.PollingTimer = timer(...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', 0.05, ...  % 50ms polling
                'TimerFcn', @(~,~) obj.pollAsyncResponse());
            start(obj.PollingTimer);
        end

        function pollAsyncResponse(obj)
            %POLLASYNCRESPONSE Poll Python for async response content

            try
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

            % Execute the code (stays in MATLAB)
            [result, isError] = obj.CodeExecutor.execute(code);

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

        function onUIReady(obj)
            %ONUIREADY Handle UI ready signal

            obj.IsReady = true;

            % Detect and send theme to UI
            currentTheme = obj.detectMatlabTheme();
            obj.sendToJS('setTheme', struct('theme', currentTheme));

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
