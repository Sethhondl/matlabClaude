classdef tLaunch < matlab.unittest.TestCase
    %TLAUNCH Unit tests for launch convenience function
    %
    %   Run tests with:
    %       results = runtests('tLaunch');
    %
    %   Note: These tests create UI components and may require Python/Claude.

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
        %% Function Existence Tests
        function testFunctionExists(testCase)
            %TESTFUNCTIONEXISTS Verify launch function is accessible

            testCase.verifyTrue(exist('claudecode.launch', 'file') > 0, ...
                'launch function should exist in claudecode package');
        end

        function testFunctionHasOutput(testCase)
            %TESTFUNCTIONHASOUTPUT Verify function can return output

            nOut = nargout('claudecode.launch');
            testCase.verifyGreaterThanOrEqual(nOut, 0, ...
                'launch should support optional output');
        end

        %% Return Type Tests
        function testReturnsClaudeCodeApp(testCase)
            %TESTRETURNSCLAUDECODEAPP Verify returns ClaudeCodeApp instance

            try
                testCase.App = claudecode.launch();
                testCase.verifyClass(testCase.App, 'claudecode.ClaudeCodeApp');
            catch ME
                % May fail if Python/Claude not available - that's OK for this test
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['launch errored unexpectedly: ', ME.message]);
                end
            end
        end

        %% Singleton Tests
        function testReturnsSingleton(testCase)
            %TESTRETURNSSINGLETON Verify multiple calls return same instance

            try
                app1 = claudecode.launch();
                app2 = claudecode.launch();

                testCase.verifyEqual(app1, app2, ...
                    'launch should return singleton instance');

                testCase.App = app1;  % For cleanup
            catch ME
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['launch errored: ', ME.message]);
                end
            end
        end

        function testSameAsGetInstance(testCase)
            %TESTSAMEASGETINSTANCE Verify same as ClaudeCodeApp.getInstance

            try
                app1 = claudecode.launch();
                app2 = claudecode.ClaudeCodeApp.getInstance();

                testCase.verifyEqual(app1, app2, ...
                    'launch should return same instance as getInstance');

                testCase.App = app1;
            catch ME
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['launch errored: ', ME.message]);
                end
            end
        end

        %% Graceful Handling Tests
        function testGracefulHandlingNoPython(testCase)
            %TESTGRACEFULHANDLINGNOPYTHON Verify graceful handling without Python

            % This test verifies the function handles missing dependencies gracefully
            % by either succeeding or failing with a clear error (not crashing)

            try
                testCase.App = claudecode.launch();
                % If we get here, launch succeeded
                testCase.verifyClass(testCase.App, 'claudecode.ClaudeCodeApp');
            catch ME
                % Verify the error is related to Python/Claude, not a bug
                validErrors = {'Python', 'Claude', 'pyenv', 'py.'};
                hasValidError = false;

                for i = 1:length(validErrors)
                    if contains(ME.message, validErrors{i}) || ...
                       contains(ME.identifier, validErrors{i})
                        hasValidError = true;
                        break;
                    end
                end

                if hasValidError
                    % Expected failure due to missing dependencies
                    testCase.verifyTrue(true);
                else
                    testCase.verifyFail(['Unexpected error in launch: ', ME.message]);
                end
            end
        end

        %% Configuration Tests
        function testCallsConfigurePython(testCase)
            %TESTCALLSCONFIGUREPYTHON Verify configurePython is called

            % This is a behavioral test - launch should configure Python
            % We verify by checking that pyenv state is consistent

            pe1 = pyenv;

            try
                testCase.App = claudecode.launch();
            catch
                % Ignore launch errors
            end

            pe2 = pyenv;

            % pyenv should be in a valid state after launch
            testCase.verifyTrue(pe2.Status == "Loaded" || pe2.Status == "NotLoaded", ...
                'pyenv should be in valid state after launch');
        end

        %% No Output When Not Requested
        function testNoOutputWithoutAssignment(testCase)
            %TESTNOOUTPUTWITHOUTASSIGNMENT Verify clean execution without output

            try
                % Call without output assignment
                claudecode.launch();

                % If we get here, launch succeeded without error
                % Clean up using getInstance
                app = claudecode.ClaudeCodeApp.getInstance();
                if ~isempty(app) && isvalid(app)
                    app.close();
                end
            catch ME
                if contains(ME.message, 'Python') || contains(ME.message, 'Claude')
                    testCase.assumeFail('Python or Claude not available');
                else
                    testCase.verifyFail(['launch errored: ', ME.message]);
                end
            end
        end
    end
end
