classdef ClaudeCodeApp < handle
    %CLAUDECODEAPP Main entry point for Claude Code MATLAB integration
    %
    %   This class creates and manages the Claude Code assistant interface
    %   with an embedded HTML chat interface. By default, the window docks
    %   into the MATLAB desktop as a side panel that can be tiled alongside
    %   the Editor and other tools.
    %
    %   Example:
    %       app = claudecode.ClaudeCodeApp();
    %       app.launch();
    %
    %   Or use the convenience function:
    %       claudecode.launch()
    %
    %   Docking controls:
    %       app.dock()      - Dock into MATLAB desktop
    %       app.undock()    - Undock to floating window
    %       app.isDocked()  - Check current dock state
    %
    %   Tip: After launching, right-click the "Claude Code" tab and select
    %   "Tile Right" to position it as a persistent side panel.

    properties (SetAccess = private)
        Settings            % Configuration settings
    end

    properties (Access = private)
        Figure              % Main uifigure window
        ChatController      % ChatUIController instance
        PythonBridge        % Python MatlabBridge instance
        SimulinkBridge      % SimulinkBridge instance
        IsOpen = false      % Whether the app is open
    end

    properties (Constant, Access = private)
        APP_TITLE = 'Claude Code'
        DEFAULT_WIDTH = 450
        DEFAULT_HEIGHT = 700
    end

    properties (Access = private)
        IsDocked = true     % Whether to dock into MATLAB desktop
    end

    methods
        function obj = ClaudeCodeApp()
            %CLAUDECODEAPP Constructor

            obj.Settings = obj.loadSettings();
            obj.IsDocked = obj.Settings.dockWindow;
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

            obj.createWindow();
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

            obj.IsOpen = false;
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

        function dock(obj)
            %DOCK Dock the window into the MATLAB desktop
            %   After docking, you can tile the panel to the side by:
            %   1. Right-click the tab title
            %   2. Select "Tile Right" or drag to desired position

            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                obj.Figure.WindowStyle = 'docked';
                obj.IsDocked = true;
            end
        end

        function undock(obj)
            %UNDOCK Undock the window to a floating window

            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                obj.Figure.WindowStyle = 'normal';
                obj.IsDocked = false;

                % Reposition to right side of screen
                screenSize = get(0, 'ScreenSize');
                xPos = screenSize(3) - obj.DEFAULT_WIDTH - 50;
                yPos = (screenSize(4) - obj.DEFAULT_HEIGHT) / 2;
                obj.Figure.Position = [xPos, yPos, obj.DEFAULT_WIDTH, obj.DEFAULT_HEIGHT];
            end
        end

        function tf = isDocked(obj)
            %ISDOCKED Returns true if window is currently docked

            tf = obj.IsDocked;
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

        function createWindow(obj)
            %CREATEWINDOW Create the main application window

            if obj.IsDocked
                % Create docked figure - WindowStyle must be set first
                obj.Figure = uifigure(...
                    'Name', obj.APP_TITLE, ...
                    'Color', [0.12 0.12 0.12], ...
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
                    'Color', [0.12 0.12 0.12], ...
                    'Resize', 'on', ...
                    'CloseRequestFcn', @(~,~) obj.onCloseRequest());
            end

            % Create chat controller with Python bridge
            obj.ChatController = claudecode.ChatUIController(...
                obj.Figure, obj.PythonBridge);

            % Connect Simulink bridge
            obj.ChatController.SimulinkBridge = obj.SimulinkBridge;
        end

        function onCloseRequest(obj)
            %ONCLOSEREQUEST Handle window close

            obj.close();
        end

        function showSetupInstructions(obj)
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

        function settings = loadSettings(~)
            %LOADSETTINGS Load saved settings or defaults

            settings = struct();
            settings.theme = 'dark';
            settings.autoIncludeWorkspace = false;
            settings.autoIncludeSimulink = false;
            settings.maxHistoryLength = 100;
            settings.dockWindow = true;  % Dock into MATLAB desktop by default
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
