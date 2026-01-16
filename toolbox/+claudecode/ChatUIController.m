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
                obj.addMessage('assistant', obj.CurrentStreamText);
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

            % Create uihtml component filling the figure
            obj.HTMLComponent = uihtml(obj.ParentFigure, ...
                'HTMLSource', htmlPath, ...
                'Position', [0 0 obj.ParentFigure.Position(3) obj.ParentFigure.Position(4)], ...
                'HTMLEventReceivedFcn', @(src, evt) obj.handleJSEvent(evt));

            % Set up resize callback to keep HTML component filling figure
            obj.ParentFigure.SizeChangedFcn = @(~,~) obj.onFigureResize();

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
            contextStr = '';
            if isfield(data, 'includeWorkspace') && data.includeWorkspace
                contextStr = [contextStr, obj.WorkspaceProvider.getWorkspaceContext(), newline, newline];
            end
            if isfield(data, 'includeSimulink') && data.includeSimulink && ~isempty(obj.SimulinkBridge)
                contextStr = [contextStr, obj.SimulinkBridge.buildSimulinkContext(), newline, newline];
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
            %POLLASYNCRESPONSE Poll Python for async response chunks

            try
                % Get any new chunks
                chunks = obj.PythonBridge.poll_async_chunks();
                chunksList = cell(chunks);

                for i = 1:length(chunksList)
                    chunk = char(chunksList{i});
                    if ~isempty(chunk)
                        obj.sendStreamChunk(chunk);
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

            % Send welcome message
            obj.sendToJS('showMessage', struct(...
                'role', 'assistant', ...
                'content', 'Welcome to Claude Code! Ask questions about your MATLAB code, get help with Simulink models, or request code changes.'));
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
