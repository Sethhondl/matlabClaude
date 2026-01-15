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
    end
end
