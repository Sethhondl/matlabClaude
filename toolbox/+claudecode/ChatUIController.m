classdef ChatUIController < handle
    %CHATUICONTROLLER Manages the chat UI and bridges JavaScript/MATLAB communication
    %
    %   This class creates and manages the chat interface using an embedded
    %   HTML webview, handling bidirectional communication between the UI and MATLAB.
    %   Core logic (Claude communication, agents) is handled by Python.
    %
    %   Supports both uifigure (App Designer) and standard figure (ToolGroup) parents.
    %
    %   Example:
    %       controller = claudecode.ChatUIController(parentFigure, bridge);

    properties (Access = public)
        SimulinkBridge      % Reference to SimulinkBridge for model context
        GitProvider         % Reference to GitContextProvider
        StreamingStateChangedFcn  % Callback for streaming state changes
    end

    properties (Access = private)
        ParentFigure        % Figure containing the UI (uifigure or standard figure)
        ParentPanel         % uipanel container (for standard figure)
        PythonBridge        % Python MatlabBridge instance
        CodeExecutor        % Reference to CodeExecutor (MATLAB-side)
        WorkspaceProvider   % Reference to WorkspaceContextProvider
        HTMLComponent       % uihtml component
        IsReady = false     % Whether UI has initialized
        PollingTimer        % Timer for polling async responses
        IsUIFigure = true   % Whether parent is a uifigure

        % State
        Messages = {}       % Cell array of message structs
        IsStreaming = false % Whether currently streaming
        CurrentStreamText = '' % Accumulated text during streaming

        % Context toggles (can be set from toolstrip)
        IncludeWorkspace = false
        IncludeSimulink = false
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
            %   parent: uifigure or standard figure to contain the chat UI
            %   pythonBridge: Python MatlabBridge instance

            obj.ParentFigure = parent;
            obj.PythonBridge = pythonBridge;
            obj.CodeExecutor = claudecode.CodeExecutor();
            obj.WorkspaceProvider = claudecode.WorkspaceContextProvider();

            % Detect figure type
            obj.IsUIFigure = obj.detectFigureType(parent);

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

        function clearHistory(obj)
            %CLEARHISTORY Clear the chat message history

            obj.Messages = {};
            obj.sendToJS('clearHistory', struct());
        end

        function stopCurrentRequest(obj)
            %STOPCURRENTREQUEST Stop the current streaming request

            if obj.IsStreaming
                % Stop polling timer
                if ~isempty(obj.PollingTimer) && isvalid(obj.PollingTimer)
                    stop(obj.PollingTimer);
                    delete(obj.PollingTimer);
                    obj.PollingTimer = [];
                end

                obj.endStreaming();
                obj.sendToJS('showMessage', struct('role', 'system', 'content', 'Request stopped by user.'));
            end
        end

        function setIncludeWorkspace(obj, value)
            %SETINCLUDEWORKSPACE Set the include workspace toggle

            obj.IncludeWorkspace = value;
        end

        function setIncludeSimulink(obj, value)
            %SETINCLUDESIMULINK Set the include Simulink toggle

            obj.IncludeSimulink = value;
        end

        function setTheme(obj, theme)
            %SETTHEME Set the chat UI theme

            if strcmpi(theme, 'auto')
                theme = obj.detectMatlabTheme();
            end
            obj.sendToJS('setTheme', struct('theme', theme));
        end

        function sendAssistantMessage(obj, content)
            %SENDASSISTANTMESSAGE Display a complete assistant message

            obj.addMessage('assistant', content);
            obj.setStreamingState(false);
            obj.updateStatus('ready', 'Ready');
        end

        function startStreaming(obj)
            %STARTSTREAMING Signal start of streaming response

            obj.setStreamingState(true);
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
            obj.setStreamingState(false);
            obj.CurrentStreamText = '';
            obj.updateStatus('ready', 'Ready');
            obj.sendToJS('endStreaming', struct());
        end

        function sendError(obj, message)
            %SENDERROR Display an error message

            obj.addMessage('error', message);
            obj.setStreamingState(false);
            obj.updateStatus('error', 'Error occurred');
            obj.sendToJS('showError', struct('message', message));
        end

        function updateStatus(obj, status, message)
            %UPDATESTATUS Update the status indicator

            obj.sendToJS('updateStatus', struct('status', status, 'message', message));
        end
    end

    methods (Access = private)
        function isUIFig = detectFigureType(~, parent)
            %DETECTFIGURETYPE Detect if parent is a uifigure, uipanel, or standard figure

            try
                % Check if it's a uipanel (common when using toolbar mode)
                if isa(parent, 'matlab.ui.container.Panel')
                    isUIFig = true;  % uipanel in uifigure context
                    return;
                end

                % uifigure has 'AutoResizeChildren' property
                isUIFig = isprop(parent, 'AutoResizeChildren');
            catch
                isUIFig = false;
            end
        end

        function createUI(obj)
            %CREATEUI Create the uihtml component

            % Get path to HTML file
            thisFile = mfilename('fullpath');
            toolboxDir = fileparts(fileparts(thisFile));
            htmlPath = fullfile(toolboxDir, 'chat_ui', 'index.html');

            if obj.IsUIFigure
                % UIFigure or uipanel context
                parent = obj.ParentFigure;

                % Get parent size
                parentPos = parent.Position;

                % For uipanel, position is in normalized units by default
                % Convert to pixels if needed
                if isa(parent, 'matlab.ui.container.Panel')
                    % Get pixel position of panel
                    parentPos = getpixelposition(parent);
                else
                    % Disable AutoResizeChildren to allow SizeChangedFcn to work
                    if isprop(parent, 'AutoResizeChildren')
                        parent.AutoResizeChildren = 'off';
                    end
                end

                obj.HTMLComponent = uihtml(parent, ...
                    'HTMLSource', htmlPath, ...
                    'Position', [0 0 parentPos(3) parentPos(4)], ...
                    'HTMLEventReceivedFcn', @(src, evt) obj.handleJSEvent(evt));

                % Set up resize callback on the parent
                if isprop(parent, 'SizeChangedFcn')
                    parent.SizeChangedFcn = @(~,~) obj.onFigureResize();
                end
            else
                % Standard figure: Create uipanel first, then uihtml inside it
                obj.ParentPanel = uipanel(obj.ParentFigure, ...
                    'Units', 'normalized', ...
                    'Position', [0 0 1 1], ...
                    'BorderType', 'none');

                obj.HTMLComponent = uihtml(obj.ParentPanel, ...
                    'HTMLSource', htmlPath, ...
                    'Position', [0 0 obj.ParentPanel.Position(3) obj.ParentPanel.Position(4)], ...
                    'HTMLEventReceivedFcn', @(src, evt) obj.handleJSEvent(evt));

                % Set up resize callback for standard figure
                obj.ParentFigure.SizeChangedFcn = @(~,~) obj.onFigureResize();
            end

            obj.IsReady = true;
        end

        function onFigureResize(obj)
            %ONFIGURERESIZE Handle figure/panel resize

            if ~isempty(obj.HTMLComponent) && isvalid(obj.HTMLComponent)
                if obj.IsUIFigure
                    % Get parent size (works for both uifigure and uipanel)
                    parent = obj.ParentFigure;
                    if isa(parent, 'matlab.ui.container.Panel')
                        parentPos = getpixelposition(parent);
                    else
                        parentPos = parent.Position;
                    end
                    obj.HTMLComponent.Position = [0 0 parentPos(3) parentPos(4)];
                else
                    % For standard figure with panel, get panel pixel size
                    if ~isempty(obj.ParentPanel) && isvalid(obj.ParentPanel)
                        figPos = getpixelposition(obj.ParentFigure);
                        obj.HTMLComponent.Position = [0 0 figPos(3) figPos(4)];
                    end
                end
            end
        end

        function setStreamingState(obj, isStreaming)
            %SETSTREAMINGSTATE Update streaming state and notify

            obj.IsStreaming = isStreaming;

            % Notify via callback if set
            if ~isempty(obj.StreamingStateChangedFcn)
                try
                    obj.StreamingStateChangedFcn(isStreaming);
                catch
                    % Callback may have been deleted
                end
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

            % Determine context inclusion (prefer toolstrip settings, fallback to UI data)
            includeWorkspace = obj.IncludeWorkspace;
            includeSimulink = obj.IncludeSimulink;

            if isfield(data, 'includeWorkspace')
                includeWorkspace = includeWorkspace || data.includeWorkspace;
            end
            if isfield(data, 'includeSimulink')
                includeSimulink = includeSimulink || data.includeSimulink;
            end

            % Build context for agents
            context = py.dict();
            if includeWorkspace
                workspaceCtx = obj.WorkspaceProvider.getWorkspaceContext();
                context{'workspace'} = workspaceCtx;
            end
            if includeSimulink && ~isempty(obj.SimulinkBridge)
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
            if includeWorkspace
                contextStr = [contextStr, newline, newline, obj.WorkspaceProvider.getWorkspaceContext()];
            end
            % Optionally include Simulink context
            if includeSimulink && ~isempty(obj.SimulinkBridge)
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

        function s = pyDictToStruct(~, pyDict)
            %PYDICTTOSTRUCT Convert Python dict to MATLAB struct

            s = struct(pyDict);
        end
    end
end
