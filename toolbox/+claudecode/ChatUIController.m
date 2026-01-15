classdef ChatUIController < handle
    %CHATUICONTROLLER Manages the chat UI and bridges JavaScript/MATLAB communication
    %
    %   This class creates and manages the chat interface, handling
    %   bidirectional communication between the UI and MATLAB.
    %
    %   Example:
    %       controller = claudecode.ChatUIController(parentPanel, processManager);

    properties (Access = public)
        SimulinkBridge      % Reference to SimulinkBridge for model context
        GitProvider         % Reference to GitContextProvider
    end

    properties (Access = private)
        ParentContainer     % Panel or figure containing the UI
        ProcessManager      % Reference to ClaudeProcessManager
        CodeExecutor        % Reference to CodeExecutor
        WorkspaceProvider   % Reference to WorkspaceContextProvider
        IsReady = false     % Whether UI has initialized

        % UI Components (for figure-based UI)
        WebWindow           % Internal web window for HTML content
        MessageHistory      % Listbox or text area for messages
        InputField          % Edit field for user input
        SendButton          % Button to send message
        ContextPanel        % Panel for context options
        WorkspaceCheckbox   % Checkbox for workspace context
        SimulinkCheckbox    % Checkbox for Simulink context

        % State
        Messages = {}       % Cell array of message structs
        IsStreaming = false % Whether currently streaming
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
            %   parent: uipanel or figure to contain the chat UI
            %   processManager: ClaudeProcessManager instance

            obj.ParentContainer = parent;
            obj.ProcessManager = processManager;
            obj.CodeExecutor = claudecode.CodeExecutor();
            obj.WorkspaceProvider = claudecode.WorkspaceContextProvider();

            obj.createUI();
        end

        function delete(obj)
            %DELETE Destructor
            % Clean up UI components if needed
        end

        function sendAssistantMessage(obj, content)
            %SENDASSISTANTMESSAGE Display a complete assistant message

            obj.addMessage('assistant', content);
            obj.IsStreaming = false;
            obj.updateSendButton();
        end

        function startStreaming(obj)
            %STARTSTREAMING Signal start of streaming response

            obj.IsStreaming = true;
            obj.updateSendButton();
            obj.addMessage('assistant', '');  % Add empty message to append to
        end

        function sendStreamChunk(obj, chunk)
            %SENDSTREAMCHUNK Append a streaming text chunk

            if ~isempty(obj.Messages)
                lastIdx = length(obj.Messages);
                obj.Messages{lastIdx}.content = [obj.Messages{lastIdx}.content, chunk];
                obj.updateMessageDisplay();
            end
        end

        function endStreaming(obj)
            %ENDSTREAMING Signal end of streaming response

            obj.IsStreaming = false;
            obj.updateSendButton();
        end

        function sendError(obj, message)
            %SENDERROR Display an error message

            obj.addMessage('error', message);
            obj.IsStreaming = false;
            obj.updateSendButton();
        end

        function updateStatus(obj, status, message)
            %UPDATESTATUS Update the status indicator
            % For now, just update the send button text
            if obj.IsStreaming
                obj.SendButton.String = 'Thinking...';
            else
                obj.SendButton.String = 'Send';
            end
        end
    end

    methods (Access = private)
        function createUI(obj)
            %CREATEUI Create the UI components

            parent = obj.ParentContainer;

            % Get parent position for sizing
            if isprop(parent, 'Position')
                pos = parent.Position;
                if strcmp(get(parent, 'Units'), 'normalized')
                    pos = [0 0 1 1];
                end
            else
                pos = [0 0 400 600];
            end

            % Create main layout panels using normalized units
            % Header panel (top 5%)
            obj.createHeader(parent);

            % Message history (middle 75%)
            obj.createMessageArea(parent);

            % Context options (5%)
            obj.createContextPanel(parent);

            % Input area (bottom 15%)
            obj.createInputArea(parent);

            obj.IsReady = true;
        end

        function createHeader(obj, parent)
            %CREATEHEADER Create the header panel

            uicontrol(parent, ...
                'Style', 'text', ...
                'String', 'Claude Code', ...
                'Units', 'normalized', ...
                'Position', [0.02 0.94 0.96 0.05], ...
                'FontSize', 14, ...
                'FontWeight', 'bold', ...
                'ForegroundColor', [0.8 0.8 0.8], ...
                'BackgroundColor', [0.15 0.15 0.15], ...
                'HorizontalAlignment', 'left');
        end

        function createMessageArea(obj, parent)
            %CREATEMESSAGEAREA Create the message display area

            obj.MessageHistory = uicontrol(parent, ...
                'Style', 'listbox', ...
                'String', {'Welcome to Claude Code!', '', 'Ask questions about your MATLAB code,',...
                          'get help with Simulink models,', 'or request code changes.'}, ...
                'Units', 'normalized', ...
                'Position', [0.02 0.22 0.96 0.71], ...
                'FontSize', 11, ...
                'FontName', 'Consolas', ...
                'ForegroundColor', [0.8 0.8 0.8], ...
                'BackgroundColor', [0.12 0.12 0.12], ...
                'Max', 2, ...  % Enable multi-select for scrolling
                'HorizontalAlignment', 'left');
        end

        function createContextPanel(obj, parent)
            %CREATECONTEXTPANEL Create context options panel

            obj.WorkspaceCheckbox = uicontrol(parent, ...
                'Style', 'checkbox', ...
                'String', 'Include workspace', ...
                'Units', 'normalized', ...
                'Position', [0.02 0.16 0.35 0.05], ...
                'FontSize', 10, ...
                'ForegroundColor', [0.7 0.7 0.7], ...
                'BackgroundColor', [0.12 0.12 0.12], ...
                'Value', 0);

            obj.SimulinkCheckbox = uicontrol(parent, ...
                'Style', 'checkbox', ...
                'String', 'Include Simulink model', ...
                'Units', 'normalized', ...
                'Position', [0.40 0.16 0.40 0.05], ...
                'FontSize', 10, ...
                'ForegroundColor', [0.7 0.7 0.7], ...
                'BackgroundColor', [0.12 0.12 0.12], ...
                'Value', 0);
        end

        function createInputArea(obj, parent)
            %CREATEINPUTAREA Create the input area

            % Input text field
            obj.InputField = uicontrol(parent, ...
                'Style', 'edit', ...
                'String', '', ...
                'Units', 'normalized', ...
                'Position', [0.02 0.02 0.78 0.12], ...
                'FontSize', 11, ...
                'ForegroundColor', [0.9 0.9 0.9], ...
                'BackgroundColor', [0.18 0.18 0.18], ...
                'HorizontalAlignment', 'left', ...
                'Max', 3, ...  % Multi-line
                'KeyPressFcn', @(src, evt) obj.onKeyPress(evt));

            % Send button
            obj.SendButton = uicontrol(parent, ...
                'Style', 'pushbutton', ...
                'String', 'Send', ...
                'Units', 'normalized', ...
                'Position', [0.82 0.02 0.16 0.12], ...
                'FontSize', 11, ...
                'FontWeight', 'bold', ...
                'ForegroundColor', [1 1 1], ...
                'BackgroundColor', [0.85 0.47 0.34], ...
                'Callback', @(~,~) obj.onSendClick());
        end

        function onKeyPress(obj, evt)
            %ONKEYPRESS Handle key press in input field

            % Check for Ctrl+Enter or Cmd+Enter
            if strcmp(evt.Key, 'return') && ...
               (any(strcmp(evt.Modifier, 'control')) || any(strcmp(evt.Modifier, 'command')))
                obj.onSendClick();
            end
        end

        function onSendClick(obj)
            %ONSENDCLICK Handle send button click

            if obj.IsStreaming
                return;
            end

            message = strtrim(obj.InputField.String);
            if isempty(message)
                return;
            end

            % Handle multi-line input (cell array from edit box)
            if iscell(message)
                message = strjoin(message, newline);
            end

            % Clear input
            obj.InputField.String = '';

            % Add user message to display
            obj.addMessage('user', message);

            % Build context
            context = '';

            if obj.WorkspaceCheckbox.Value
                workspaceContext = obj.WorkspaceProvider.getWorkspaceContext();
                context = [context, workspaceContext, newline, newline];
            end

            if obj.SimulinkCheckbox.Value && ~isempty(obj.SimulinkBridge)
                simulinkContext = obj.SimulinkBridge.buildSimulinkContext();
                context = [context, simulinkContext, newline, newline];
            end

            % Notify via event
            notify(obj, 'MessageSent');

            % Send to Claude asynchronously
            obj.startStreaming();

            obj.ProcessManager.sendMessageAsync(message, ...
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

            if ~result.success && ~isempty(result.error)
                obj.sendError(result.error);
            end
        end

        function addMessage(obj, role, content)
            %ADDMESSAGE Add a message to the history

            msg = struct('role', role, 'content', content, 'timestamp', now);
            obj.Messages{end+1} = msg;
            obj.updateMessageDisplay();
        end

        function updateMessageDisplay(obj)
            %UPDATEMESSAGEDISPLAY Update the message listbox

            lines = {};

            for i = 1:length(obj.Messages)
                msg = obj.Messages{i};

                % Add role prefix
                switch msg.role
                    case 'user'
                        prefix = '>> YOU: ';
                    case 'assistant'
                        prefix = '   CLAUDE: ';
                    case 'error'
                        prefix = '!! ERROR: ';
                    otherwise
                        prefix = '   ';
                end

                % Split content into lines and add prefix to first line
                contentLines = strsplit(msg.content, newline);
                for j = 1:length(contentLines)
                    if j == 1
                        lines{end+1} = [prefix, contentLines{j}];
                    else
                        lines{end+1} = ['           ', contentLines{j}];
                    end
                end

                % Add blank line between messages
                lines{end+1} = '';
            end

            obj.MessageHistory.String = lines;

            % Scroll to bottom
            if ~isempty(lines)
                obj.MessageHistory.Value = length(lines);
            end
        end

        function updateSendButton(obj)
            %UPDATESENDBUTTON Update send button state

            if obj.IsStreaming
                obj.SendButton.String = 'Thinking...';
                obj.SendButton.Enable = 'off';
            else
                obj.SendButton.String = 'Send';
                obj.SendButton.Enable = 'on';
            end
        end
    end
end
