classdef tSettings < matlab.unittest.TestCase
    %TSETTINGS Unit tests for Settings
    %
    %   Run tests with:
    %       results = runtests('tSettings');

    properties
        Settings
    end

    methods (TestMethodSetup)
        function createSettings(testCase)
            testCase.Settings = claudecode.config.Settings();
        end
    end

    methods (Test)
        %% Constructor Tests
        function testConstructor(testCase)
            %TESTCONSTRUCTOR Verify constructor creates valid object

            settings = claudecode.config.Settings();
            testCase.verifyClass(settings, 'claudecode.config.Settings');
        end

        %% Default Values Tests
        function testDefaultTheme(testCase)
            %TESTDEFAULTTHEME Verify default theme

            testCase.verifyEqual(testCase.Settings.theme, 'dark');
        end

        function testDefaultFontSize(testCase)
            %TESTDEFAULTFONTSIZE Verify default font size

            testCase.verifyEqual(testCase.Settings.fontSize, 14);
        end

        function testDefaultAutoIncludeWorkspace(testCase)
            %TESTDEFAULTAUTOINCLUDEWORKSPACE Verify default

            testCase.verifyFalse(testCase.Settings.autoIncludeWorkspace);
        end

        function testDefaultAutoIncludeSimulink(testCase)
            %TESTDEFAULTAUTOINCLUDESIMULINK Verify default

            testCase.verifyFalse(testCase.Settings.autoIncludeSimulink);
        end

        function testDefaultCodeExecutionMode(testCase)
            %TESTDEFAULTCODEEXECUTIONMODE Verify default

            testCase.verifyEqual(testCase.Settings.codeExecutionMode, 'prompt');
        end

        function testDefaultExecutionTimeout(testCase)
            %TESTDEFAULTEXECUTIONTIMEOUT Verify default

            testCase.verifyEqual(testCase.Settings.executionTimeout, 30);
        end

        function testDefaultAllowSystemCommands(testCase)
            %TESTDEFAULTALLOWSYSTEMCOMMANDS Verify default

            testCase.verifyFalse(testCase.Settings.allowSystemCommands);
        end

        function testDefaultAllowDestructiveOps(testCase)
            %TESTDEFAULTALLOWDESTRUCTIVEOPS Verify default

            testCase.verifyFalse(testCase.Settings.allowDestructiveOps);
        end

        function testDefaultClaudePath(testCase)
            %TESTDEFAULTCLAUDEPATH Verify default

            testCase.verifyEqual(testCase.Settings.claudePath, 'claude');
        end

        function testDefaultAllowedTools(testCase)
            %TESTDEFAULTALLOWEDTOOLS Verify default tools

            expectedTools = {'Edit', 'Write', 'Read', 'Bash', 'Glob', 'Grep'};
            testCase.verifyEqual(testCase.Settings.defaultAllowedTools, expectedTools);
        end

        %% Property Modification Tests
        function testModifyTheme(testCase)
            %TESTMODIFYTHEME Verify theme can be changed

            testCase.Settings.theme = 'light';
            testCase.verifyEqual(testCase.Settings.theme, 'light');
        end

        function testModifyTimeout(testCase)
            %TESTMODIFYTIMEOUT Verify timeout can be changed

            testCase.Settings.executionTimeout = 60;
            testCase.verifyEqual(testCase.Settings.executionTimeout, 60);
        end

        %% Reset Tests
        function testReset(testCase)
            %TESTRESET Verify reset restores defaults

            % Modify some settings
            testCase.Settings.theme = 'light';
            testCase.Settings.fontSize = 18;
            testCase.Settings.executionTimeout = 120;

            % Reset
            testCase.Settings.reset();

            % Verify defaults restored
            testCase.verifyEqual(testCase.Settings.theme, 'dark');
            testCase.verifyEqual(testCase.Settings.fontSize, 14);
            testCase.verifyEqual(testCase.Settings.executionTimeout, 30);
        end

        %% Load Tests
        function testLoadReturnsSettings(testCase)
            %TESTLOADRETURNSSETTINGS Verify load returns settings object

            settings = claudecode.config.Settings.load();
            testCase.verifyClass(settings, 'claudecode.config.Settings');
        end

        %% Save Tests
        function testSaveDoesNotError(testCase)
            %TESTSAVEDOESNOTERROR Verify save doesn't throw

            try
                testCase.Settings.save();
            catch ME
                testCase.verifyFail(['save errored: ', ME.message]);
            end
        end

        function testSaveAndLoad(testCase)
            %TESTSAVEANDLOAD Verify round-trip

            % Modify and save
            testCase.Settings.theme = 'light';
            testCase.Settings.fontSize = 16;
            testCase.Settings.save();

            % Load and verify
            loaded = claudecode.config.Settings.load();
            testCase.verifyEqual(loaded.theme, 'light');
            testCase.verifyEqual(loaded.fontSize, 16);

            % Reset for other tests
            testCase.Settings.reset();
            testCase.Settings.save();
        end

        %% Boundary Value Tests
        function testFontSizePositive(testCase)
            %TESTFONTSIZEPOSITIVE Verify font size must be positive

            testCase.Settings.fontSize = 8;
            testCase.verifyEqual(testCase.Settings.fontSize, 8);

            testCase.Settings.fontSize = 72;
            testCase.verifyEqual(testCase.Settings.fontSize, 72);
        end

        function testExecutionTimeoutPositive(testCase)
            %TESTEXECUTIONTIMEOUTPOSITIVE Verify timeout is positive

            testCase.Settings.executionTimeout = 1;
            testCase.verifyEqual(testCase.Settings.executionTimeout, 1);

            testCase.Settings.executionTimeout = 300;
            testCase.verifyEqual(testCase.Settings.executionTimeout, 300);
        end

        function testMaxWorkspaceVariablesPositive(testCase)
            %TESTMAXWORKSPACEVARIABLESPOSITIVE Verify max variables limit

            testCase.Settings.maxWorkspaceVariables = 10;
            testCase.verifyEqual(testCase.Settings.maxWorkspaceVariables, 10);

            testCase.Settings.maxWorkspaceVariables = 100;
            testCase.verifyEqual(testCase.Settings.maxWorkspaceVariables, 100);
        end

        function testMaxHistoryLengthPositive(testCase)
            %TESTMAXHISTORYLENGTHPOSITIVE Verify max history limit

            testCase.Settings.maxHistoryLength = 50;
            testCase.verifyEqual(testCase.Settings.maxHistoryLength, 50);

            testCase.Settings.maxHistoryLength = 500;
            testCase.verifyEqual(testCase.Settings.maxHistoryLength, 500);
        end

        %% All Properties Have Defaults Tests
        function testAllPropertiesHaveDefaults(testCase)
            %TESTALLPROPERTIESHAVEDEFAULTS Verify all properties initialized

            props = properties(testCase.Settings);

            for i = 1:length(props)
                propName = props{i};
                value = testCase.Settings.(propName);

                % Verify property is not undefined/empty (except for valid empty strings)
                if ~ischar(value) && ~isstring(value)
                    testCase.verifyFalse(isempty(value), ...
                        sprintf('Property %s should have a default value', propName));
                end
            end
        end

        %% Additional Property Tests
        function testDefaultMaxWorkspaceVariables(testCase)
            %TESTDEFAULTMAXWORKSPACEVARIABLES Verify default value

            testCase.verifyEqual(testCase.Settings.maxWorkspaceVariables, 50);
        end

        function testDefaultMaxHistoryLength(testCase)
            %TESTDEFAULTMAXHISTORYLENGTH Verify default value

            testCase.verifyEqual(testCase.Settings.maxHistoryLength, 100);
        end

        function testDefaultSaveHistory(testCase)
            %TESTDEFAULTSAVEHISTORY Verify default value

            testCase.verifyTrue(testCase.Settings.saveHistory);
        end

        function testModifySaveHistory(testCase)
            %TESTMODIFYSAVEHISTORY Verify can change save history

            testCase.Settings.saveHistory = false;
            testCase.verifyFalse(testCase.Settings.saveHistory);
        end

        %% Corrupted JSON Handling Test
        function testCorruptedJsonReturnsDefaults(testCase)
            %TESTCORRUPTEDJSONRETURNSDEFAULTS Verify corrupted file handling

            % Get settings path
            prefDir = prefdir;
            settingsPath = fullfile(prefDir, 'ClaudeCode', 'claude_code_settings.json');

            % Backup original if exists
            hasBackup = false;
            if exist(settingsPath, 'file')
                backupPath = [settingsPath, '.backup'];
                copyfile(settingsPath, backupPath);
                hasBackup = true;
            end

            try
                % Write corrupted JSON
                settingsDir = fileparts(settingsPath);
                if ~exist(settingsDir, 'dir')
                    mkdir(settingsDir);
                end

                fid = fopen(settingsPath, 'w');
                fprintf(fid, '{ invalid json content !!!');
                fclose(fid);

                % Load should return defaults and warn
                loadedSettings = claudecode.config.Settings.load();

                % Should have default values
                testCase.verifyEqual(loadedSettings.theme, 'dark');
                testCase.verifyEqual(loadedSettings.fontSize, 14);

            catch ME
                % Restore and rethrow
                if hasBackup
                    movefile(backupPath, settingsPath);
                end
                rethrow(ME);
            end

            % Restore original
            if hasBackup
                movefile(backupPath, settingsPath);
            else
                delete(settingsPath);
            end
        end

        %% Theme Validation Tests
        function testThemeValues(testCase)
            %TESTTHEMEVALUES Verify theme accepts valid values

            testCase.Settings.theme = 'dark';
            testCase.verifyEqual(testCase.Settings.theme, 'dark');

            testCase.Settings.theme = 'light';
            testCase.verifyEqual(testCase.Settings.theme, 'light');
        end

        %% Code Execution Mode Tests
        function testCodeExecutionModeValues(testCase)
            %TESTCODEEXECUTIONMODEVALUES Verify valid mode values

            validModes = {'auto', 'prompt', 'disabled'};

            for i = 1:length(validModes)
                testCase.Settings.codeExecutionMode = validModes{i};
                testCase.verifyEqual(testCase.Settings.codeExecutionMode, validModes{i});
            end
        end

        %% Boolean Properties Tests
        function testAllowSystemCommandsBoolean(testCase)
            %TESTALLOWSYSTEMCOMMANDSBOOLEAN Verify boolean behavior

            testCase.Settings.allowSystemCommands = true;
            testCase.verifyTrue(testCase.Settings.allowSystemCommands);

            testCase.Settings.allowSystemCommands = false;
            testCase.verifyFalse(testCase.Settings.allowSystemCommands);
        end

        function testAllowDestructiveOpsBoolean(testCase)
            %TESTALLOWDESTRUCTIVEOPSBOOLEAN Verify boolean behavior

            testCase.Settings.allowDestructiveOps = true;
            testCase.verifyTrue(testCase.Settings.allowDestructiveOps);

            testCase.Settings.allowDestructiveOps = false;
            testCase.verifyFalse(testCase.Settings.allowDestructiveOps);
        end

        function testAutoIncludeWorkspaceBoolean(testCase)
            %TESTAUTOINCLUDEWORKSPACEBOOLEAN Verify boolean behavior

            testCase.Settings.autoIncludeWorkspace = true;
            testCase.verifyTrue(testCase.Settings.autoIncludeWorkspace);

            testCase.Settings.autoIncludeWorkspace = false;
            testCase.verifyFalse(testCase.Settings.autoIncludeWorkspace);
        end

        function testAutoIncludeSimulinkBoolean(testCase)
            %TESTAUTOINCLUDESIMUMLINKBOOLEAN Verify boolean behavior

            testCase.Settings.autoIncludeSimulink = true;
            testCase.verifyTrue(testCase.Settings.autoIncludeSimulink);

            testCase.Settings.autoIncludeSimulink = false;
            testCase.verifyFalse(testCase.Settings.autoIncludeSimulink);
        end

        %% Multiple Save/Load Cycles
        function testMultipleSaveLoadCycles(testCase)
            %TESTMULTIPLESAVELOADCYCLES Verify persistence stability

            originalTheme = testCase.Settings.theme;

            for i = 1:3
                testCase.Settings.theme = 'light';
                testCase.Settings.save();

                loaded = claudecode.config.Settings.load();
                testCase.verifyEqual(loaded.theme, 'light');

                testCase.Settings.theme = 'dark';
                testCase.Settings.save();

                loaded = claudecode.config.Settings.load();
                testCase.verifyEqual(loaded.theme, 'dark');
            end

            % Restore original
            testCase.Settings.theme = originalTheme;
            testCase.Settings.save();
        end

        %% Reset Restores All Properties
        function testResetRestoresAllProperties(testCase)
            %TESTRESETRESTORESALLPROPERTIES Verify complete reset

            % Get default settings
            defaultSettings = claudecode.config.Settings();

            % Modify multiple settings
            testCase.Settings.theme = 'light';
            testCase.Settings.fontSize = 20;
            testCase.Settings.executionTimeout = 120;
            testCase.Settings.allowSystemCommands = true;
            testCase.Settings.maxHistoryLength = 200;

            % Reset
            testCase.Settings.reset();

            % Verify all are restored
            testCase.verifyEqual(testCase.Settings.theme, defaultSettings.theme);
            testCase.verifyEqual(testCase.Settings.fontSize, defaultSettings.fontSize);
            testCase.verifyEqual(testCase.Settings.executionTimeout, defaultSettings.executionTimeout);
            testCase.verifyEqual(testCase.Settings.allowSystemCommands, defaultSettings.allowSystemCommands);
            testCase.verifyEqual(testCase.Settings.maxHistoryLength, defaultSettings.maxHistoryLength);
        end
    end
end
