classdef ClaudeCodeApp < handle
    %CLAUDECODEAPP Main entry point for Claude Code MATLAB integration
    %
    %   This class creates and manages the Claude Code assistant interface,
    %   providing a chat panel for interacting with Claude about MATLAB
    %   and Simulink development.
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
        Figure              % Main uifigure
        MainPanel           % Panel for main content (future use)
        ChatPanel           % Panel for chat UI
        ChatController      % ChatUIController instance
        ProcessManager      % ClaudeProcessManager instance
        SimulinkBridge      % SimulinkBridge instance
        GitProvider         % GitContextProvider (future)
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
            %LAUNCH Create and show the application window

            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                % Already open, bring to front
                figure(obj.Figure);
                return;
            end

            % Verify Claude CLI is available
            if ~obj.ProcessManager.isClaudeAvailable()
                obj.showSetupInstructions();
                return;
            end

            obj.createUI();
            obj.Figure.Visible = 'on';
        end

        function close(obj)
            %CLOSE Close the application

            % Stop process manager
            if ~isempty(obj.ProcessManager)
                obj.ProcessManager.stopProcess();
            end

            % Delete figure
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                delete(obj.Figure);
            end
        end

        function show(obj)
            %SHOW Show the application window

            if ~isempty(obj.Figure) && isvalid(obj.Figure)
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
    end

    methods (Access = private)
        function initialize(obj)
            %INITIALIZE Initialize components

            obj.ProcessManager = claudecode.ClaudeProcessManager();
            obj.SimulinkBridge = claudecode.SimulinkBridge();
        end

        function createUI(obj)
            %CREATEUI Create the user interface

            % Get screen size for positioning
            screenSize = get(0, 'ScreenSize');
            figWidth = 500;
            figHeight = 700;
            figX = screenSize(3) - figWidth - 50;  % Right side of screen
            figY = (screenSize(4) - figHeight) / 2;

            % Create main figure
            obj.Figure = uifigure(...
                'Name', 'Claude Code', ...
                'Position', [figX, figY, figWidth, figHeight], ...
                'Visible', 'off', ...
                'CloseRequestFcn', @(~,~) obj.onCloseRequest(), ...
                'Color', [0.12 0.12 0.12], ...
                'Resize', 'on');

            % For now, the entire figure is the chat panel
            % Future: Add split layout with workspace view

            obj.ChatPanel = uipanel(obj.Figure, ...
                'Position', [0, 0, figWidth, figHeight], ...
                'BorderType', 'none', ...
                'BackgroundColor', [0.12 0.12 0.12]);

            % Create chat controller
            obj.ChatController = claudecode.ChatUIController(...
                obj.ChatPanel, obj.ProcessManager);

            % Connect Simulink bridge
            obj.ChatController.SimulinkBridge = obj.SimulinkBridge;

            % Handle figure resize
            obj.Figure.SizeChangedFcn = @(~,~) obj.onResize();
        end

        function onResize(obj)
            %ONRESIZE Handle figure resize

            if isvalid(obj.Figure) && isvalid(obj.ChatPanel)
                figPos = obj.Figure.Position;
                obj.ChatPanel.Position = [0, 0, figPos(3), figPos(4)];
            end
        end

        function onCloseRequest(obj)
            %ONCLOSEREQUEST Handle close button

            obj.close();
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

            fig = uifigure('Name', 'Setup Required', ...
                'Position', [500, 400, 450, 200]);
            uialert(fig, msg, 'Claude Code Not Found', ...
                'Icon', 'warning', ...
                'CloseFcn', @(~, ~) delete(fig));
        end

        function settings = loadSettings(~)
            %LOADSETTINGS Load saved settings or defaults

            settings = struct();
            settings.theme = 'dark';
            settings.autoIncludeWorkspace = false;
            settings.autoIncludeSimulink = false;
            settings.maxHistoryLength = 100;

            % TODO: Load from preferences file
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
