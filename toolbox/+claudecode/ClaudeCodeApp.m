classdef ClaudeCodeApp < handle
    %CLAUDECODEAPP Main entry point for Claude Code MATLAB integration
    %
    %   This class creates and manages the Claude Code assistant interface
    %   with an embedded HTML chat interface. Uses MATLAB's ToolGroup API
    %   for professional desktop integration with a toolstrip ribbon.
    %
    %   Example:
    %       app = claudecode.ClaudeCodeApp();
    %       app.launch();
    %
    %   Or use the convenience function:
    %       claudecode.launch()
    %
    %   The app integrates with the MATLAB desktop via ToolGroup, providing
    %   a toolstrip ribbon with chat controls, context toggles, and settings.

    properties (SetAccess = private)
        Settings            % Configuration settings
    end

    properties (Access = private)
        Figure              % Chat figure
        ChatController      % ChatUIController instance
        PythonBridge        % Python MatlabBridge instance
        SimulinkBridge      % SimulinkBridge instance
        IsOpen = false      % Whether the app is open
        UsingToolGroup = false  % Whether toolbar mode is being used

        % Toolbar controls (when using toolbar mode)
        StopButton          % Stop button reference
        WorkspaceCheckbox   % Include Workspace checkbox
        SimulinkCheckbox    % Include Simulink checkbox
    end

    properties (Constant, Access = private)
        APP_TITLE = 'Claude Code'
        DEFAULT_WIDTH = 450
        DEFAULT_HEIGHT = 700
    end

    methods
        function obj = ClaudeCodeApp()
            %CLAUDECODEAPP Constructor

            obj.Settings = claudecode.config.Settings.load();
            obj.initialize();
        end

        function delete(obj)
            %DELETE Destructor

            obj.close();
        end

        function launch(obj)
            %LAUNCH Create and show the application window

            if obj.IsOpen && ~isempty(obj.Figure) && isvalid(obj.Figure)
                % Already open, bring to front
                figure(obj.Figure);
                return;
            end

            % Verify Claude CLI is available via Python
            if ~obj.PythonBridge.is_claude_available()
                obj.showSetupInstructions();
                return;
            end

            % Decide which UI mode to use
            % useToolGroup now means "use toolbar mode" (docked uifigure with toolbar)
            if obj.Settings.useToolGroup
                obj.createToolGroupWindow();
            else
                obj.createDockedWindow();
            end

            obj.IsOpen = true;
        end

        function close(obj)
            %CLOSE Close the application

            % Stop Python process
            if ~isempty(obj.PythonBridge)
                try
                    obj.PythonBridge.stop_process();
                catch
                    % Python may not be available
                end
            end

            % Close figure
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                delete(obj.Figure);
            end

            % Clear toolbar controls
            obj.StopButton = [];
            obj.WorkspaceCheckbox = [];
            obj.SimulinkCheckbox = [];

            obj.IsOpen = false;
            obj.UsingToolGroup = false;
        end

        function show(obj)
            %SHOW Show the application window

            if obj.IsOpen && ~isempty(obj.Figure) && isvalid(obj.Figure)
                obj.Figure.Visible = 'on';
                figure(obj.Figure);
            else
                obj.launch();
            end
        end

        function hide(obj)
            %HIDE Hide the application window

            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                obj.Figure.Visible = 'off';
            end
        end

        function bridge = getPythonBridge(obj)
            %GETPYTHONBRIDGE Get the Python bridge for custom agent registration

            bridge = obj.PythonBridge;
        end
    end

    methods (Access = private)
        function initialize(obj)
            %INITIALIZE Initialize components

            % Add Python package to path
            obj.setupPythonPath();

            % Create Python bridge
            obj.PythonBridge = py.claudecode.MatlabBridge();

            % Create Simulink bridge (MATLAB-side)
            obj.SimulinkBridge = claudecode.SimulinkBridge();
        end

        function setupPythonPath(~)
            %SETUPPYTHONPATH Add Python package to Python path

            % Get path to python folder
            thisFile = mfilename('fullpath');
            toolboxDir = fileparts(fileparts(thisFile));
            projectDir = fileparts(toolboxDir);
            pythonDir = fullfile(projectDir, 'python');

            % Add to Python path if not already there
            P = py.sys.path;
            pathList = string(P);

            if ~any(pathList == pythonDir)
                insert(P, int64(0), pythonDir);
            end
        end

        function available = isToolGroupAvailable(~)
            %ISTOOLGROUPAVAILABLE Check if ToolGroup API is available

            try
                available = exist('matlab.ui.internal.desktop.ToolGroup', 'class') == 8;
            catch
                available = false;
            end
        end

        function createToolGroupWindow(obj)
            %CREATETOOLGROUPWINDOW Create docked uifigure with toolbar
            %
            %   Note: ToolGroup has compatibility issues with uihtml, so we use
            %   a docked uifigure with a custom toolbar panel instead.

            % Create docked uifigure
            obj.Figure = uifigure(...
                'Name', obj.APP_TITLE, ...
                'Resize', 'on', ...
                'CloseRequestFcn', @(~,~) obj.onCloseRequest());
            obj.Figure.WindowStyle = 'docked';

            % Create toolbar panel at top
            toolbarHeight = 36;
            obj.Figure.AutoResizeChildren = 'off';

            toolbarPanel = uipanel(obj.Figure, ...
                'Units', 'pixels', ...
                'Position', [0, obj.Figure.Position(4) - toolbarHeight, obj.Figure.Position(3), toolbarHeight], ...
                'BorderType', 'none', ...
                'BackgroundColor', [0.94 0.94 0.94]);

            % Create toolbar buttons using helper
            obj.createToolbarButtons(toolbarPanel);

            % Create chat panel below toolbar
            chatPanel = uipanel(obj.Figure, ...
                'Units', 'pixels', ...
                'Position', [0, 0, obj.Figure.Position(3), obj.Figure.Position(4) - toolbarHeight], ...
                'BorderType', 'none');

            % Create chat controller in the chat panel
            obj.ChatController = claudecode.ChatUIController(...
                chatPanel, obj.PythonBridge);

            % Connect Simulink bridge
            obj.ChatController.SimulinkBridge = obj.SimulinkBridge;

            % Set up streaming state callback
            obj.ChatController.StreamingStateChangedFcn = @(isStreaming) obj.onStreamingStateChanged(isStreaming);

            % Store toolbar panel for resize handling
            obj.Figure.UserData = struct('toolbarPanel', toolbarPanel, 'chatPanel', chatPanel, 'toolbarHeight', toolbarHeight);

            % Set up resize callback
            obj.Figure.SizeChangedFcn = @(src,~) obj.onToolbarFigureResize(src);

            obj.UsingToolGroup = true;
        end

        function createToolbarButtons(obj, parent)
            %CREATETOOLBARBUTTONS Create toolbar buttons in the panel

            btnWidth = 80;
            btnHeight = 26;
            spacing = 5;
            x = spacing;
            y = (parent.Position(4) - btnHeight) / 2;

            % Clear Chat button
            clearBtn = uibutton(parent, ...
                'Text', 'Clear', ...
                'Position', [x, y, btnWidth, btnHeight], ...
                'ButtonPushedFcn', @(~,~) obj.onClearChat());
            x = x + btnWidth + spacing;

            % New button
            newBtn = uibutton(parent, ...
                'Text', 'New', ...
                'Position', [x, y, btnWidth, btnHeight], ...
                'ButtonPushedFcn', @(~,~) obj.onNewConversation());
            x = x + btnWidth + spacing;

            % Stop button
            obj.StopButton = uibutton(parent, ...
                'Text', 'Stop', ...
                'Position', [x, y, btnWidth, btnHeight], ...
                'Enable', 'off', ...
                'ButtonPushedFcn', @(~,~) obj.onStop());
            x = x + btnWidth + spacing * 3;

            % Separator
            x = x + 10;

            % Include Workspace checkbox
            obj.WorkspaceCheckbox = uicheckbox(parent, ...
                'Text', 'Workspace', ...
                'Position', [x, y, 90, btnHeight], ...
                'Value', obj.Settings.autoIncludeWorkspace, ...
                'ValueChangedFcn', @(src,~) obj.onToggleWorkspace(src.Value));
            x = x + 95;

            % Include Simulink checkbox
            obj.SimulinkCheckbox = uicheckbox(parent, ...
                'Text', 'Simulink', ...
                'Position', [x, y, 80, btnHeight], ...
                'Value', obj.Settings.autoIncludeSimulink, ...
                'ValueChangedFcn', @(src,~) obj.onToggleSimulink(src.Value));
        end

        function onToolbarFigureResize(obj, fig)
            %ONTOOLBARFIGURERESIZE Handle figure resize with toolbar

            if isempty(fig.UserData)
                return;
            end

            toolbarPanel = fig.UserData.toolbarPanel;
            chatPanel = fig.UserData.chatPanel;
            toolbarHeight = fig.UserData.toolbarHeight;

            figPos = fig.Position;

            % Resize toolbar panel (stays at top)
            toolbarPanel.Position = [0, figPos(4) - toolbarHeight, figPos(3), toolbarHeight];

            % Resize chat panel (fills rest)
            chatPanel.Position = [0, 0, figPos(3), figPos(4) - toolbarHeight];
        end

        function createDockedWindow(obj)
            %CREATEDOCKEDWINDOW Create fallback docked uifigure window

            if obj.Settings.dockWindow
                % Create docked figure
                obj.Figure = uifigure(...
                    'Name', obj.APP_TITLE, ...
                    'Resize', 'on', ...
                    'CloseRequestFcn', @(~,~) obj.onCloseRequest());
                obj.Figure.WindowStyle = 'docked';
            else
                % Create floating window (right side of screen)
                screenSize = get(0, 'ScreenSize');
                xPos = screenSize(3) - obj.DEFAULT_WIDTH - 50;
                yPos = (screenSize(4) - obj.DEFAULT_HEIGHT) / 2;

                obj.Figure = uifigure(...
                    'Name', obj.APP_TITLE, ...
                    'Position', [xPos, yPos, obj.DEFAULT_WIDTH, obj.DEFAULT_HEIGHT], ...
                    'Resize', 'on', ...
                    'CloseRequestFcn', @(~,~) obj.onCloseRequest());
            end

            % Create chat controller with Python bridge
            obj.ChatController = claudecode.ChatUIController(...
                obj.Figure, obj.PythonBridge);

            % Connect Simulink bridge
            obj.ChatController.SimulinkBridge = obj.SimulinkBridge;

            obj.UsingToolGroup = false;
        end

        function onCloseRequest(obj)
            %ONCLOSEREQUEST Handle window close

            obj.close();
        end

        % Toolstrip callback handlers
        function onClearChat(obj)
            %ONCLEARCHAT Clear chat history

            if ~isempty(obj.ChatController)
                obj.ChatController.clearHistory();
            end
        end

        function onNewConversation(obj)
            %ONNEWCONVERSATION Start a new conversation

            if ~isempty(obj.ChatController)
                obj.ChatController.clearHistory();
            end

            % Reset Python conversation state
            if ~isempty(obj.PythonBridge)
                try
                    obj.PythonBridge.reset_conversation();
                catch
                    % Method may not exist
                end
            end
        end

        function onStop(obj)
            %ONSTOP Stop the current request

            if ~isempty(obj.ChatController)
                obj.ChatController.stopCurrentRequest();
            end

            % Stop Python async operation
            if ~isempty(obj.PythonBridge)
                try
                    obj.PythonBridge.stop_async();
                catch
                    % Method may not exist
                end
            end
        end

        function onToggleWorkspace(obj, value)
            %ONTOGGLEWORKSPACE Handle workspace toggle change

            obj.Settings.autoIncludeWorkspace = value;

            % Notify ChatController if needed
            if ~isempty(obj.ChatController)
                obj.ChatController.setIncludeWorkspace(value);
            end
        end

        function onToggleSimulink(obj, value)
            %ONTOGGLESSIMULINK Handle Simulink toggle change

            obj.Settings.autoIncludeSimulink = value;

            % Notify ChatController if needed
            if ~isempty(obj.ChatController)
                obj.ChatController.setIncludeSimulink(value);
            end
        end

        function onChangeTheme(obj, theme)
            %ONCHANGETHEME Handle theme change

            obj.Settings.theme = theme;

            % Notify ChatController
            if ~isempty(obj.ChatController)
                obj.ChatController.setTheme(theme);
            end
        end

        function onOpenDocs(~)
            %ONOPENDOCS Open documentation

            web('https://github.com/anthropics/claude-code', '-browser');
        end

        function onReportIssue(~)
            %ONREPORTISSUE Open issue reporter

            web('https://github.com/anthropics/claude-code/issues', '-browser');
        end

        function onStreamingStateChanged(obj, isStreaming)
            %ONSTREAMINGSTATECHANGED Handle streaming state changes

            if ~isempty(obj.StopButton) && isvalid(obj.StopButton)
                if isStreaming
                    obj.StopButton.Enable = 'on';
                else
                    obj.StopButton.Enable = 'off';
                end
            end
        end

        function showSetupInstructions(~)
            %SHOWSETUPINSTRUCTIONS Show instructions for installing Claude CLI

            % Create a temporary visible figure for the dialog
            tempFig = uifigure('Visible', 'on', 'Position', [100 100 1 1]);

            msg = sprintf(['Claude Code CLI not found.\n\n' ...
                'Please install Claude Code from:\n' ...
                'https://claude.ai/code\n\n' ...
                'After installation, ensure ''claude'' is in your PATH\n' ...
                'and restart MATLAB.\n\n' ...
                'If Claude is installed but MATLAB cannot find it,\n' ...
                'you may need to set the full path in Settings.']);

            uialert(tempFig, msg, 'Claude Code Not Found', 'Icon', 'warning', ...
                'CloseFcn', @(~,~) delete(tempFig));
        end
    end

    methods (Static)
        function app = getInstance()
            %GETINSTANCE Get or create singleton instance

            persistent instance;

            if isempty(instance) || ~isvalid(instance)
                instance = claudecode.ClaudeCodeApp();
            end

            app = instance;
        end
    end
end
