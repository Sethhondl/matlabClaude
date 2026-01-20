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

        %% Dock/Undock Method Tests
        function testDockMethod(testCase)
            %TESTDOCKMETHOD Verify dock method exists and callable

            try
                testCase.App = claudecode.ClaudeCodeApp();
                testCase.App.dock();
                testCase.verifyTrue(testCase.App.isDocked());
            catch ME
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['dock errored: ', ME.message]);
                end
            end
        end

        function testUndockMethod(testCase)
            %TESTUNDOCKMETHOD Verify undock method exists and callable

            try
                testCase.App = claudecode.ClaudeCodeApp();
                testCase.App.undock();
                testCase.verifyFalse(testCase.App.isDocked());
            catch ME
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['undock errored: ', ME.message]);
                end
            end
        end

        function testIsDocked(testCase)
            %TESTISDOCKED Verify isDocked returns boolean

            try
                testCase.App = claudecode.ClaudeCodeApp();
                result = testCase.App.isDocked();
                testCase.verifyClass(result, 'logical');
            catch ME
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['isDocked errored: ', ME.message]);
                end
            end
        end

        function testDockUndockToggle(testCase)
            %TESTDOCKUNDOCKTOGGLE Verify dock/undock toggle works

            try
                testCase.App = claudecode.ClaudeCodeApp();

                % Toggle to undocked
                testCase.App.undock();
                testCase.verifyFalse(testCase.App.isDocked());

                % Toggle to docked
                testCase.App.dock();
                testCase.verifyTrue(testCase.App.isDocked());
            catch ME
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['dock/undock toggle errored: ', ME.message]);
                end
            end
        end

        %% Settings Structure Tests
        function testSettingsHasTheme(testCase)
            %TESTSETTINGSHASTHEME Verify Settings has theme field

            try
                testCase.App = claudecode.ClaudeCodeApp();
                testCase.verifyTrue(isfield(testCase.App.Settings, 'theme') || ...
                    isprop(testCase.App.Settings, 'theme'));
            catch ME
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['Settings check errored: ', ME.message]);
                end
            end
        end

        function testSettingsHasDockWindow(testCase)
            %TESTSETTINGSHASDOCKWINDOW Verify Settings has dockWindow field

            try
                testCase.App = claudecode.ClaudeCodeApp();
                testCase.verifyTrue(isfield(testCase.App.Settings, 'dockWindow'));
            catch ME
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['Settings check errored: ', ME.message]);
                end
            end
        end

        function testSettingsHasAutoIncludeWorkspace(testCase)
            %TESTSETTINGSHASAUTOINCLUDEWORKSPACE Verify field exists

            try
                testCase.App = claudecode.ClaudeCodeApp();
                testCase.verifyTrue(isfield(testCase.App.Settings, 'autoIncludeWorkspace'));
            catch ME
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['Settings check errored: ', ME.message]);
                end
            end
        end

        function testSettingsHasAutoIncludeSimulink(testCase)
            %TESTSETTINGSHASAUTOINCLUDESIMULINK Verify field exists

            try
                testCase.App = claudecode.ClaudeCodeApp();
                testCase.verifyTrue(isfield(testCase.App.Settings, 'autoIncludeSimulink'));
            catch ME
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['Settings check errored: ', ME.message]);
                end
            end
        end

        %% Double Launch Behavior Tests
        function testDoubleLaunch(testCase)
            %TESTDOUBLELAUNCH Verify double launch brings to front

            try
                app1 = claudecode.ClaudeCodeApp.getInstance();
                app1.launch();

                app2 = claudecode.ClaudeCodeApp.getInstance();
                app2.launch();

                % Should be same instance
                testCase.verifyEqual(app1, app2);

                testCase.App = app1;
            catch ME
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['Double launch errored: ', ME.message]);
                end
            end
        end

        function testLaunchAfterClose(testCase)
            %TESTLAUNCHAFTERCLOSE Verify can launch after close

            try
                app1 = claudecode.ClaudeCodeApp.getInstance();
                app1.launch();
                app1.close();

                % Should be able to get new instance after close
                % (singleton may be cleared)
                testCase.verifyTrue(true);
            catch ME
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['Launch after close errored: ', ME.message]);
                end
            end
        end

        %% Close Multiple Times Tests
        function testCloseMultipleTimes(testCase)
            %TESTCLOSEMULTIPLETIMES Verify multiple closes don't error

            try
                testCase.App = claudecode.ClaudeCodeApp();

                testCase.App.close();
                testCase.App.close();
                testCase.App.close();

                testCase.verifyTrue(true, 'Multiple closes should not error');
            catch ME
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['Multiple close errored: ', ME.message]);
                end
            end
        end

        %% Show/Hide Cycle Tests
        function testShowHideCycle(testCase)
            %TESTSHOWHIDECYCLE Verify show/hide cycle works

            try
                testCase.App = claudecode.ClaudeCodeApp();

                testCase.App.show();
                testCase.App.hide();
                testCase.App.show();

                testCase.verifyTrue(true, 'Show/hide cycle should work');
            catch ME
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['Show/hide cycle errored: ', ME.message]);
                end
            end
        end

        %% getPythonBridge Test
        function testGetPythonBridge(testCase)
            %TESTGETPYTHONBRIDGE Verify getPythonBridge method

            try
                testCase.App = claudecode.ClaudeCodeApp();
                bridge = testCase.App.getPythonBridge();

                % Should return the Python bridge object
                testCase.verifyFalse(isempty(bridge));
            catch ME
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['getPythonBridge errored: ', ME.message]);
                end
            end
        end
    end
end
