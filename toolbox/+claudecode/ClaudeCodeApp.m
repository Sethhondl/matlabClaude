classdef ClaudeCodeApp < handle
    %CLAUDECODEAPP Main entry point for Claude Code MATLAB integration
    %
    %   This class creates and manages the Claude Code assistant interface
    %   as a docked panel in the MATLAB desktop using the ToolGroup API.
    %
    %   Example:
    %       app = claudecode.ClaudeCodeApp();
    %       app.launch();
    %
    %   Or use the convenience function:
    %       claudecode.launch()

    properties (SetAccess = private)
        Settings            % Configuration settings
    end

    properties (Access = private)
        ToolGroup           % matlab.ui.internal.desktop.ToolGroup
        ChatFigure          % Figure containing chat UI
        ChatPanel           % Panel for chat UI
        ChatController      % ChatUIController instance
        ProcessManager      % ClaudeProcessManager instance
        SimulinkBridge      % SimulinkBridge instance
        IsOpen = false      % Whether the tool is open
    end

    properties (Constant, Access = private)
        TOOL_NAME = 'ClaudeCode'
        TOOL_TITLE = 'Claude Code'
    end

    methods
        function obj = ClaudeCodeApp()
            %CLAUDECODEAPP Constructor

            obj.Settings = obj.loadSettings();
            obj.initialize();
        end

        function delete(obj)
            %DELETE Destructor

            obj.close();
        end

        function launch(obj)
            %LAUNCH Create and show the application as a docked panel

            if obj.IsOpen
                % Already open, bring to front
                obj.show();
                return;
            end

            % Verify Claude CLI is available
            if ~obj.ProcessManager.isClaudeAvailable()
                obj.showSetupInstructions();
                return;
            end

            obj.createToolGroup();
            obj.IsOpen = true;
        end

        function close(obj)
            %CLOSE Close the application

            % Stop process manager
            if ~isempty(obj.ProcessManager)
                obj.ProcessManager.stopProcess();
            end

            % Close ToolGroup
            if ~isempty(obj.ToolGroup) && isvalid(obj.ToolGroup)
                try
                    obj.ToolGroup.close();
                catch
                    % May already be closed
                end
            end

            obj.IsOpen = false;
        end

        function show(obj)
            %SHOW Show the application

            if obj.IsOpen && ~isempty(obj.ToolGroup) && isvalid(obj.ToolGroup)
                obj.ToolGroup.open();
            else
                obj.launch();
            end
        end

        function hide(obj)
            %HIDE Hide the application (minimize)

            if ~isempty(obj.ToolGroup) && isvalid(obj.ToolGroup)
                obj.ToolGroup.minimize();
            end
        end
    end

    methods (Access = private)
        function initialize(obj)
            %INITIALIZE Initialize components

            obj.ProcessManager = claudecode.ClaudeProcessManager();
            obj.SimulinkBridge = claudecode.SimulinkBridge();
        end

        function createToolGroup(obj)
            %CREATETOOLGROUP Create the ToolGroup and docked figure

            import matlab.ui.internal.desktop.*

            % Create ToolGroup
            obj.ToolGroup = ToolGroup(obj.TOOL_NAME, obj.TOOL_TITLE);

            % Configure ToolGroup behavior
            obj.ToolGroup.disableDataBrowser();

            % Set close callback
            addlistener(obj.ToolGroup, 'GroupAction', @(src, evt) obj.onToolGroupAction(evt));

            % Create the chat figure
            obj.createChatFigure();

            % Add figure to ToolGroup
            obj.ToolGroup.addFigure(obj.ChatFigure);

            % Open the ToolGroup
            obj.ToolGroup.open();

            % Set default layout - dock to right side
            drawnow;  % Ensure UI is rendered
            obj.setDefaultLayout();
        end

        function createChatFigure(obj)
            %CREATECHATFIGURE Create the figure containing the chat UI

            % Create figure for the chat panel
            obj.ChatFigure = figure(...
                'Name', 'Chat', ...
                'NumberTitle', 'off', ...
                'MenuBar', 'none', ...
                'ToolBar', 'none', ...
                'Color', [0.12 0.12 0.12], ...
                'Visible', 'off', ...
                'HandleVisibility', 'off');

            % Create panel to hold chat UI
            obj.ChatPanel = uipanel(obj.ChatFigure, ...
                'Units', 'normalized', ...
                'Position', [0 0 1 1], ...
                'BorderType', 'none', ...
                'BackgroundColor', [0.12 0.12 0.12]);

            % Create chat controller
            obj.ChatController = claudecode.ChatUIController(...
                obj.ChatPanel, obj.ProcessManager);

            % Connect Simulink bridge
            obj.ChatController.SimulinkBridge = obj.SimulinkBridge;
        end

        function setDefaultLayout(obj)
            %SETDEFAULTLAYOUT Set the default docked layout

            try
                % Get the ToolGroup's peer (Java object)
                group = obj.ToolGroup;

                % Try to set preferred width for side docking
                % This uses internal APIs and may vary by MATLAB version
                pause(0.2);  % Allow UI to settle

                % The figure will dock automatically
                % User can then drag it to desired position

            catch
                % Layout customization is optional
            end
        end

        function onToolGroupAction(obj, evt)
            %ONTOOLGROUPACTION Handle ToolGroup events

            if strcmp(evt.EventData.EventType, 'CLOSING')
                obj.close();
            end
        end

        function showSetupInstructions(~)
            %SHOWSETUPINSTRUCTIONS Show instructions for installing Claude CLI

            msg = sprintf(['Claude Code CLI not found.\n\n' ...
                'Please install Claude Code from:\n' ...
                'https://claude.ai/code\n\n' ...
                'After installation, ensure ''claude'' is in your PATH\n' ...
                'and restart MATLAB.\n\n' ...
                'If Claude is installed but MATLAB cannot find it,\n' ...
                'you may need to set the full path in Settings.']);

            msgbox(msg, 'Claude Code Not Found', 'warn');
        end

        function settings = loadSettings(~)
            %LOADSETTINGS Load saved settings or defaults

            settings = struct();
            settings.theme = 'dark';
            settings.autoIncludeWorkspace = false;
            settings.autoIncludeSimulink = false;
            settings.maxHistoryLength = 100;
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
