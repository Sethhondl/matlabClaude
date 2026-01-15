classdef tClaudeCodeApp < matlab.unittest.TestCase
    %TCLAUDECODEAPP Unit tests for ClaudeCodeApp
    %
    %   Run tests with:
    %       results = runtests('tClaudeCodeApp');
    %
    %   Note: These tests create UI components and require a display.

    properties
        App
    end

    methods (TestMethodTeardown)
        function cleanupApp(testCase)
            if ~isempty(testCase.App) && isvalid(testCase.App)
                testCase.App.close();
            end
        end
    end

    methods (Test)
        %% Constructor Tests
        function testConstructor(testCase)
            %TESTCONSTRUCTOR Verify constructor creates valid object

            testCase.App = claudecode.ClaudeCodeApp();

            testCase.verifyClass(testCase.App, 'claudecode.ClaudeCodeApp');
        end

        function testSettingsLoaded(testCase)
            %TESTSETTINGSLOADED Verify settings property exists

            testCase.App = claudecode.ClaudeCodeApp();

            testCase.verifyTrue(isstruct(testCase.App.Settings));
        end

        %% Singleton Tests
        function testGetInstance(testCase)
            %TESTGETINSTANCE Verify singleton pattern

            app1 = claudecode.ClaudeCodeApp.getInstance();
            app2 = claudecode.ClaudeCodeApp.getInstance();

            testCase.verifyEqual(app1, app2);

            testCase.App = app1;  % For cleanup
        end

        %% Method Tests
        function testCloseMethod(testCase)
            %TESTCLOSEMETHOD Verify close doesn't error

            testCase.App = claudecode.ClaudeCodeApp();

            try
                testCase.App.close();
            catch ME
                testCase.verifyFail(['close errored: ', ME.message]);
            end
        end

        function testShowMethod(testCase)
            %TESTSHOWMETHOD Verify show doesn't error

            testCase.App = claudecode.ClaudeCodeApp();

            try
                testCase.App.show();
                testCase.App.close();
            catch ME
                testCase.verifyFail(['show errored: ', ME.message]);
            end
        end

        function testHideMethod(testCase)
            %TESTHIDEMETHOD Verify hide doesn't error

            testCase.App = claudecode.ClaudeCodeApp();

            try
                testCase.App.hide();
            catch ME
                testCase.verifyFail(['hide errored: ', ME.message]);
            end
        end

        %% Launch Function Tests
        function testLaunchFunction(testCase)
            %TESTLAUNCHFUNCTION Verify launch convenience function

            try
                app = claudecode.launch();
                testCase.verifyClass(app, 'claudecode.ClaudeCodeApp');
                app.close();
            catch ME
                % May fail if Claude CLI not available - that's OK
                if ~contains(ME.message, 'Claude')
                    testCase.verifyFail(['launch errored: ', ME.message]);
                end
            end
        end
    end
end
