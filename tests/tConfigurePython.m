classdef tConfigurePython < matlab.unittest.TestCase
    %TCONFIGUREPYTHON Unit tests for configurePython function
    %
    %   Run tests with:
    %       results = runtests('tConfigurePython');
    %
    %   Note: These tests verify the function behavior without actually
    %   changing the Python configuration (which requires MATLAB restart).

    methods (Test)
        %% Return Type Tests
        function testReturnsLogical(testCase)
            %TESTRETURNSLOGICAL Verify function returns logical

            result = derivux.configurePython();
            testCase.verifyClass(result, 'logical');
        end

        %% Idempotency Tests
        function testIdempotency(testCase)
            %TESTIDEMPOTENCY Verify calling twice returns same result

            result1 = derivux.configurePython();
            result2 = derivux.configurePython();

            testCase.verifyEqual(result1, result2, ...
                'Calling configurePython twice should return same result');
        end

        %% Current Environment Tests
        function testRespectsLoadedPython(testCase)
            %TESTRESPECTSLOADEDPYTHON Verify does not change loaded Python

            % Get current Python status
            pe = pyenv;

            % Call configurePython
            derivux.configurePython();

            % Verify pyenv is unchanged (or still valid)
            peAfter = pyenv;

            % Status should be same or both NotLoaded
            testCase.verifyTrue(pe.Status == peAfter.Status || ...
                pe.Status == "NotLoaded" || peAfter.Status == "NotLoaded", ...
                'Python status should remain consistent');
        end

        function testReturnsTrueWithCompatiblePython(testCase)
            %TESTRETURNSTRUEWITHCOMPATIBLEPYTHON Verify returns true if Python 3.10+

            pe = pyenv;

            if pe.Status == "Loaded"
                ver = str2double(pe.Version);
                result = derivux.configurePython();

                if ver >= 3.10
                    testCase.verifyTrue(result, ...
                        'Should return true when Python 3.10+ is loaded');
                end
            else
                % Python not loaded - result depends on system configuration
                testCase.verifyClass(derivux.configurePython(), 'logical');
            end
        end

        %% Warning Behavior Tests
        function testWarnsOnIncompatiblePython(testCase)
            %TESTWARNSONINCOMPATIBLEPYTHON Verify warning for old Python

            pe = pyenv;

            if pe.Status == "Loaded"
                ver = str2double(pe.Version);

                if ver < 3.10
                    testCase.verifyWarning(...
                        @() derivux.configurePython(), ...
                        'claudecode:pythonVersion');
                end
            end
        end

        %% No Error Tests
        function testNoErrorWhenPythonNotAvailable(testCase)
            %TESTNOERRRORWHENPYTHONNOTAVAILABLE Verify graceful handling

            % This should not throw an error, even if Python is not configured
            try
                result = derivux.configurePython();
                testCase.verifyClass(result, 'logical');
            catch ME
                testCase.verifyFail(['configurePython should not error: ', ME.message]);
            end
        end

        function testFunctionExists(testCase)
            %TESTFUNCTIONEXISTS Verify function is accessible

            testCase.verifyTrue(exist('derivux.configurePython', 'file') > 0 || ...
                exist('derivux.configurePython', 'class') > 0, ...
                'configurePython should exist in claudecode package');
        end

        %% Multiple Calls Test
        function testMultipleCallsNoSideEffects(testCase)
            %TESTMULTIPLECALLSNOSIDEEFFECTS Verify multiple calls don't cause issues

            pe1 = pyenv;

            for i = 1:5
                derivux.configurePython();
            end

            pe2 = pyenv;

            % Environment should be stable after multiple calls
            testCase.verifyEqual(pe1.Status, pe2.Status, ...
                'Multiple calls should not change Python status');
        end
    end
end
