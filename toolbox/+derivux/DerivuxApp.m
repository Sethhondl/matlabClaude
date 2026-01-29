classdef DerivuxApp < handle
    %DERIVUXAPP Main entry point for Derivux MATLAB integration
    %
    %   This class creates and manages the Derivux assistant interface
    %   with an embedded HTML chat interface. By default, the window docks
    %   into the MATLAB desktop as a side panel that can be tiled alongside
    %   the Editor and other tools.
    %
    %   Example:
    %       app = derivux.DerivuxApp();
    %       app.launch();
    %
    %   Or use the convenience function:
    %       derivux.launch()
    %
    %   Docking controls:
    %       app.dock()      - Dock into MATLAB desktop
    %       app.undock()    - Undock to floating window
    %       app.isDocked()  - Check current dock state
    %
    %   Tip: After launching, right-click the "Derivux" tab and select
    %   "Tile Right" to position it as a persistent side panel.

    properties (SetAccess = private)
        Settings            % Configuration settings
        Logger              % Logging instance
        SessionId           % Session identifier for log correlation
    end

    properties (Access = private)
        Figure              % Main uifigure window
        ChatController      % ChatUIController instance
        PythonBridge        % Python MatlabBridge instance
        SimulinkBridge      % SimulinkBridge instance
        IsOpen = false      % Whether the app is open
        StartTime           % App start time for session duration
    end

    properties (Constant, Access = private)
        APP_TITLE = 'Derivux'
        DEFAULT_WIDTH = 450
        DEFAULT_HEIGHT = 700
    end

    properties (Access = private)
        IsDocked = true     % Whether to dock into MATLAB desktop
    end

    methods
        function obj = DerivuxApp()
            %DERIVUXAPP Constructor

            obj.StartTime = datetime('now');
            obj.Settings = obj.loadSettings();
            obj.IsDocked = obj.Settings.dockWindow;

            % Initialize logging system
            obj.initializeLogging();

            obj.initialize();

            % Log app initialization
            obj.Logger.info('DerivuxApp', 'app_initialized', struct(...
                'version', obj.getVersion(), ...
                'settings', obj.getLoggableSettings(), ...
                'matlab_version', version));
        end

        function delete(obj)
            %DELETE Destructor

            obj.close();
        end

        function launch(obj)
            %LAUNCH Create and show the application window

            if obj.IsOpen && ~isempty(obj.Figure) && isvalid(obj.Figure)
                % Already open, bring to front
                obj.Logger.debug('DerivuxApp', 'launch_already_open');
                figure(obj.Figure);
                return;
            end

            obj.Logger.info('DerivuxApp', 'launch_started');

            % Verify Claude CLI is available via Python
            if ~obj.PythonBridge.is_claude_available()
                obj.Logger.warn('DerivuxApp', 'claude_cli_not_found');
                obj.showSetupInstructions();
                return;
            end

            obj.createWindow();
            obj.IsOpen = true;

            obj.Logger.info('DerivuxApp', 'launch_complete', struct(...
                'is_docked', obj.IsDocked));
        end

        function close(obj)
            %CLOSE Close the application

            % Calculate session duration
            sessionDurationSec = 0;
            if ~isempty(obj.StartTime)
                sessionDurationSec = seconds(datetime('now') - obj.StartTime);
            end

            % Log app closure
            if ~isempty(obj.Logger) && isvalid(obj.Logger)
                obj.Logger.info('DerivuxApp', 'app_closed', struct(...
                    'session_duration_sec', sessionDurationSec));
                obj.Logger.close();
            end

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

            % Create Python bridge and configure logging
            obj.PythonBridge = py.derivux.MatlabBridge();

            % Pass session ID and logging config to Python for correlation
            try
                loggingConfig = py.dict(pyargs(...
                    'session_id', obj.SessionId, ...
                    'enabled', obj.Settings.loggingEnabled, ...
                    'level', obj.Settings.logLevel, ...
                    'log_directory', obj.Settings.logDirectory, ...
                    'log_sensitive_data', obj.Settings.logSensitiveData));
                obj.PythonBridge.configure_logging(loggingConfig);
            catch ME
                obj.Logger.warn('DerivuxApp', 'python_logging_config_failed', struct(...
                    'error', ME.message));
            end

            % Sync agent-based settings from MATLAB to Python
            % This ensures the correct agent and global settings are active from startup
            try
                % Switch to the saved agent
                if strcmp(obj.Settings.agent, 'plan')
                    obj.PythonBridge.toggle_primary_agent();  % Assuming default is build
                end
                % Apply global settings
                obj.PythonBridge.set_auto_execute(logical(obj.Settings.autoExecute));
                obj.PythonBridge.set_bypass_mode(logical(obj.Settings.bypassMode));
            catch ME
                obj.Logger.warn('DerivuxApp', 'python_settings_sync_failed', struct(...
                    'error', ME.message));
            end

            % Create Simulink bridge (MATLAB-side)
            obj.SimulinkBridge = derivux.SimulinkBridge();
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
                % Color is omitted to let HTML content handle theming
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
            obj.ChatController = derivux.ChatUIController(...
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

            % Load full settings if available
            try
                fullSettings = derivux.config.Settings.load();
                settings.loggingEnabled = fullSettings.loggingEnabled;
                settings.logLevel = fullSettings.logLevel;
                settings.logDirectory = fullSettings.logDirectory;
                settings.logSensitiveData = fullSettings.logSensitiveData;
                settings.logMaxFileSize = fullSettings.logMaxFileSize;
                settings.logMaxFiles = fullSettings.logMaxFiles;
            catch
                % Use defaults if settings unavailable
                settings.loggingEnabled = true;
                settings.logLevel = 'INFO';
                settings.logDirectory = '';
                settings.logSensitiveData = true;
                settings.logMaxFileSize = 10485760;
                settings.logMaxFiles = 10;
            end
        end

        function initializeLogging(obj)
            %INITIALIZELOGGING Initialize the logging system

            % Get the singleton logger
            obj.Logger = derivux.logging.Logger.getInstance();

            % Configure from settings
            obj.Logger.setLevel(obj.Settings.logLevel);

            if obj.Settings.loggingEnabled
                obj.Logger.enable();
            else
                obj.Logger.disable();
            end

            % Apply other settings via config
            config = obj.Logger.getConfig();
            config.LogSensitiveData = obj.Settings.logSensitiveData;
            config.MaxFileSize = obj.Settings.logMaxFileSize;
            config.MaxFiles = obj.Settings.logMaxFiles;

            if ~isempty(obj.Settings.logDirectory) && obj.Settings.logDirectory ~= ""
                config.LogDirectory = obj.Settings.logDirectory;
            end

            % Store session ID for correlation
            obj.SessionId = config.SessionId;
        end

        function ver = getVersion(~)
            %GETVERSION Get application version string

            ver = '1.0.0';  % TODO: Read from version file or constant
        end

        function s = getLoggableSettings(obj)
            %GETLOGGABLESETTINGS Get settings safe for logging

            s = struct(...
                'theme', obj.Settings.theme, ...
                'autoIncludeWorkspace', obj.Settings.autoIncludeWorkspace, ...
                'autoIncludeSimulink', obj.Settings.autoIncludeSimulink, ...
                'loggingEnabled', obj.Settings.loggingEnabled, ...
                'logLevel', obj.Settings.logLevel);
        end
    end

    methods (Static)
        function app = getInstance()
            %GETINSTANCE Get or create singleton instance

            persistent instance;

            if isempty(instance) || ~isvalid(instance)
                instance = derivux.DerivuxApp();
            end

            app = instance;
        end
    end
end
