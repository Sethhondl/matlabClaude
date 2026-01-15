classdef ChatUIController < handle
    %CHATUICONTROLLER Manages the chat UI and bridges JavaScript/MATLAB communication
    %
    %   This class creates and manages the uihtml component that displays
    %   the chat interface, handling bidirectional communication between
    %   the JavaScript UI and MATLAB.
    %
    %   Example:
    %       controller = claudecode.ChatUIController(parentPanel, processManager);

    properties (Access = public)
        SimulinkBridge      % Reference to SimulinkBridge for model context
        GitProvider         % Reference to GitContextProvider
    end

    properties (Access = private)
        HTMLComponent       % uihtml object
        ParentContainer     % Panel or figure containing the uihtml
        ProcessManager      % Reference to ClaudeProcessManager
        CodeExecutor        % Reference to CodeExecutor
        WorkspaceProvider   % Reference to WorkspaceContextProvider
        IsReady = false     % Whether UI has initialized
    end

    events
        MessageSent         % Fired when user sends a message
        CodeExecuted        % Fired when code is executed
    end

    methods
        function obj = ChatUIController(parent, processManager)
            %CHATUICONTROLLER Constructor
            %
            %   controller = ChatUIController(parent, processManager)
            %
            %   parent: uipanel or uifigure to contain the chat UI
            %   processManager: ClaudeProcessManager instance

            obj.ParentContainer = parent;
            obj.ProcessManager = processManager;
            obj.CodeExecutor = claudecode.CodeExecutor();
            obj.WorkspaceProvider = claudecode.WorkspaceContextProvider();

            obj.createUI();
        end

        function delete(obj)
            %DELETE Destructor
            if ~isempty(obj.HTMLComponent) && isvalid(obj.HTMLComponent)
                delete(obj.HTMLComponent);
            end
        end

        function sendToJS(obj, type, data)
            %SENDTOJS Send data to JavaScript UI
            %
            %   controller.sendToJS('assistantMessage', struct('content', 'Hello'))

            if ~obj.IsReady
                warning('ChatUIController:NotReady', 'UI not ready yet');
                return;
            end

            payload = data;
            payload.type = type;

            try
                sendEventToHTMLSource(obj.HTMLComponent, 'matlabEvent', payload);
            catch ME
                warning('ChatUIController:SendError', 'Failed to send to JS: %s', ME.message);
            end
        end

        function sendAssistantMessage(obj, content)
            %SENDASSISTANTMESSAGE Send a complete assistant message to the UI

            obj.sendToJS('assistantMessage', struct('content', content));
        end

        function startStreaming(obj)
            %STARTSTREAMING Signal start of streaming response

            obj.sendToJS('streamStart', struct());
        end

        function sendStreamChunk(obj, chunk)
            %SENDSTREAMCHUNK Send a streaming text chunk

            obj.sendToJS('streamChunk', struct('content', chunk));
        end

        function endStreaming(obj)
            %ENDSTREAMING Signal end of streaming response

            obj.sendToJS('streamEnd', struct());
        end

        function sendError(obj, message)
            %SENDERROR Send an error message to the UI

            obj.sendToJS('error', struct('message', message));
        end

        function updateStatus(obj, status, message)
            %UPDATESTATUS Update the status indicator

            obj.sendToJS('status', struct('status', status, 'message', message));
        end
    end

    methods (Access = private)
        function createUI(obj)
            %CREATEUI Create the uihtml component

            % Get path to HTML file
            thisDir = fileparts(mfilename('fullpath'));
            htmlPath = fullfile(thisDir, '..', 'chat_ui', 'index.html');

            % Create uihtml component filling the parent container
            obj.HTMLComponent = uihtml(obj.ParentContainer, ...
                'HTMLSource', htmlPath, ...
                'HTMLEventReceivedFcn', @(src, event) obj.handleJSEvent(event));

            % Position to fill parent
            obj.HTMLComponent.Position = [0 0 obj.ParentContainer.Position(3:4)];

            % Handle parent resize
            if isprop(obj.ParentContainer, 'SizeChangedFcn')
                obj.ParentContainer.SizeChangedFcn = @(~,~) obj.handleResize();
            end
        end

        function handleResize(obj)
            %HANDLERESIZE Handle parent container resize

            if isvalid(obj.HTMLComponent)
                obj.HTMLComponent.Position = [0 0 obj.ParentContainer.Position(3:4)];
            end
        end

        function handleJSEvent(obj, event)
            %HANDLEJSEVENT Handle events from JavaScript

            eventName = event.HTMLEventName;
            eventData = event.HTMLEventData;

            switch eventName
                case 'uiReady'
                    obj.onUIReady(eventData);

                case 'userMessage'
                    obj.onUserMessage(eventData);

                case 'executeCode'
                    obj.onExecuteCode(eventData);

                case 'insertCode'
                    obj.onInsertCode(eventData);

                otherwise
                    warning('ChatUIController:UnknownEvent', ...
                        'Unknown event from JS: %s', eventName);
            end
        end

        function onUIReady(obj, ~)
            %ONUIREADY Handle UI ready notification

            obj.IsReady = true;
            obj.updateStatus('ready', 'Ready');
        end

        function onUserMessage(obj, data)
            %ONUSERMESSAGE Handle user message from UI

            prompt = data.content;

            % Build context if requested
            context = '';

            if isfield(data, 'includeWorkspace') && data.includeWorkspace
                workspaceContext = obj.WorkspaceProvider.getWorkspaceContext();
                context = [context, workspaceContext, newline, newline];
            end

            if isfield(data, 'includeSimulink') && data.includeSimulink
                if ~isempty(obj.SimulinkBridge)
                    simulinkContext = obj.SimulinkBridge.buildSimulinkContext();
                    context = [context, simulinkContext, newline, newline];
                end
            end

            % Notify via event
            notify(obj, 'MessageSent');

            % Send to Claude asynchronously
            obj.startStreaming();

            obj.ProcessManager.sendMessageAsync(prompt, ...
                @(chunk) obj.onStreamChunk(chunk), ...
                @(result) obj.onMessageComplete(result), ...
                'context', context);
        end

        function onStreamChunk(obj, chunk)
            %ONSTREAMCHUNK Handle streaming chunk from Claude

            obj.sendStreamChunk(chunk);
        end

        function onMessageComplete(obj, result)
            %ONMESSAGECOMPLETE Handle complete response from Claude

            obj.endStreaming();

            if ~result.success
                obj.sendError(result.error);
            end

            % Update session ID
            if isfield(result, 'sessionId') && ~isempty(result.sessionId)
                obj.sendToJS('sessionId', struct('sessionId', result.sessionId));
            end
        end

        function onExecuteCode(obj, data)
            %ONEXECUTECODE Handle code execution request

            blockId = data.blockId;
            code = data.code;

            % Execute code safely
            [result, isError] = obj.CodeExecutor.execute(code);

            % Send result back to UI
            obj.sendToJS('codeResult', struct(...
                'blockId', blockId, ...
                'result', result, ...
                'isError', isError));

            % Notify via event
            notify(obj, 'CodeExecuted');
        end

        function onInsertCode(obj, data)
            %ONINSERTCODE Handle code insertion request

            code = data.code;

            try
                % Try to insert into current editor
                % This uses MATLAB's desktop API
                editorService = com.mathworks.mlservices.MLEditorServices;

                if editorService.hasOpenEditor()
                    % Insert at cursor position
                    editor = editorService.getEditorApplication();
                    activeEditor = editor.getActiveEditor();

                    if ~isempty(activeEditor)
                        activeEditor.insertTextAtCaret(code);
                    else
                        % No active editor, open new document
                        matlab.desktop.editor.newDocument(code);
                    end
                else
                    % No editor open, create new document
                    matlab.desktop.editor.newDocument(code);
                end

            catch ME
                % Fallback: create new script file
                try
                    matlab.desktop.editor.newDocument(code);
                catch
                    warning('ChatUIController:InsertError', ...
                        'Failed to insert code: %s', ME.message);
                end
            end
        end
    end
end
