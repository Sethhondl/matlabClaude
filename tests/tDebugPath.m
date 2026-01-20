classdef tDebugPath < matlab.unittest.TestCase
    %TDEBUGPATH Unit tests for debugPath diagnostic function
    %
    %   Run tests with:
    %       results = runtests('tDebugPath');

    properties
        OriginalHome
    end

    methods (TestMethodSetup)
        function saveHomeEnv(testCase)
            testCase.OriginalHome = getenv('HOME');
        end
    end

    methods (TestMethodTeardown)
        function restoreHomeEnv(testCase)
            if ~isempty(testCase.OriginalHome)
                setenv('HOME', testCase.OriginalHome);
            end
        end
    end

    methods (Test)
        %% Basic Execution Tests
        function testRunsWithoutError(testCase)
            %TESTRUNSWITHOUTRERROR Verify function runs without throwing

            try
                claudecode.debugPath();
            catch ME
                testCase.verifyFail(['debugPath should not error: ', ME.message]);
            end
        end

        function testReturnsNothing(testCase)
            %TESTRETURNSNOTHING Verify function has no output

            nOut = nargout('claudecode.debugPath');
            testCase.verifyEqual(nOut, 0, ...
                'debugPath should be a void function with no outputs');
        end

        function testFunctionExists(testCase)
            %TESTFUNCTIONEXISTS Verify function is accessible

            testCase.verifyTrue(exist('claudecode.debugPath', 'file') > 0, ...
                'debugPath should exist in claudecode package');
        end

        %% Output Format Tests
        function testOutputContainsHeader(testCase)
            %TESTOUTPUTCONTAINSHEADER Verify output has expected header

            output = evalc('claudecode.debugPath()');

            testCase.verifySubstring(output, '=== Claude CLI Path Debugging ===', ...
                'Output should contain header');
        end

        function testOutputContainsHomeInfo(testCase)
            %TESTOUTPUTCONTAINSHOMEINFO Verify output shows HOME variable

            output = evalc('claudecode.debugPath()');

            testCase.verifySubstring(output, 'HOME', ...
                'Output should reference HOME variable');
        end

        function testOutputContainsEndMarker(testCase)
            %TESTOUTPUTCONTAINSENDMARKER Verify output has end marker

            output = evalc('claudecode.debugPath()');

            testCase.verifySubstring(output, '=== End Debug ===', ...
                'Output should contain end marker');
        end

        function testOutputHasNumberedSteps(testCase)
            %TESTOUTPUTHASNUMBEREDSTEPS Verify output has numbered steps

            output = evalc('claudecode.debugPath()');

            testCase.verifySubstring(output, '1.', ...
                'Output should have numbered steps');
        end

        %% Edge Case Tests
        function testHandlesEmptyHome(testCase)
            %TESTHANDLESEMPTYHOME Verify handling when HOME is empty

            % Save and clear HOME
            setenv('HOME', '');

            try
                output = evalc('claudecode.debugPath()');
                testCase.verifySubstring(output, 'ERROR', ...
                    'Should report error when HOME is empty');
            catch ME
                testCase.verifyFail(['Should handle empty HOME: ', ME.message]);
            end

            % Restore HOME (done in teardown)
        end

        function testHandlesNonExistentNvmDir(testCase)
            %TESTHANDLESNONEXISTENTNVMDIR Verify handling when NVM dir missing

            % This test just verifies no error is thrown
            output = evalc('claudecode.debugPath()');

            % Should complete without error
            testCase.verifySubstring(output, '=== End Debug ===', ...
                'Should complete even if NVM dir does not exist');
        end

        %% Multiple Calls Test
        function testMultipleCallsConsistent(testCase)
            %TESTMULTIPLECALLSCONSISTENT Verify multiple calls give same output

            output1 = evalc('claudecode.debugPath()');
            output2 = evalc('claudecode.debugPath()');

            % Outputs should be identical (no side effects)
            testCase.verifyEqual(output1, output2, ...
                'Multiple calls should produce identical output');
        end
    end
end
