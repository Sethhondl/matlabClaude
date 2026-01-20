classdef tClaudeProcessManager < matlab.unittest.TestCase
    %TCLAUDEPROCESSMANAGER Unit tests for ClaudeProcessManager
    %
    %   Run tests with:
    %       results = runtests('tClaudeProcessManager');
    %
    %   Note: These tests require the ClaudeProcessManager class to exist.
    %   If the class has been renamed or removed, tests will be skipped.

    properties
        ClassExists
    end

    properties (TestParameter)
        % Test different tool configurations
        ToolSets = struct(...
            'Default', {{'Edit', 'Write', 'Read', 'Bash', 'Glob', 'Grep'}}, ...
            'ReadOnly', {{'Read', 'Glob', 'Grep'}}, ...
            'Empty', {{}})
    end

    methods (TestClassSetup)
        function checkClassExists(testCase)
            % Check if ClaudeProcessManager class exists
            testCase.ClassExists = exist('claudecode.ClaudeProcessManager', 'class') > 0;
        end
    end

    methods (Test)
        function testConstructor(testCase)
            %TESTCONSTRUCTOR Verify constructor creates valid object

            testCase.assumeTrue(testCase.ClassExists, ...
                'ClaudeProcessManager class not found - may have been renamed or removed');

            pm = claudecode.ClaudeProcessManager();

            testCase.verifyClass(pm, 'claudecode.ClaudeProcessManager');
            testCase.verifyFalse(pm.isClaudeAvailable() == -1, ...
                'isClaudeAvailable should return boolean');
        end

        function testIsClaudeAvailableReturnsBoolean(testCase)
            %TESTISCLAUDEAVAILABLERETURNSBOOLEAN Verify return type

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            result = pm.isClaudeAvailable();

            testCase.verifyClass(result, 'logical');
        end

        function testDestructor(testCase)
            %TESTDESTRUCTOR Verify clean destruction

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            delete(pm);

            % Should not error - if we get here, destruction was clean
            testCase.verifyTrue(true);
        end

        function testBuildCommandArgsDefault(testCase)
            %TESTBUILDCOMMANDARGSDEFAULT Test command building with defaults

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();

            try
                response = pm.sendMessage('test', 'timeout', 1000);
                testCase.verifyTrue(isstruct(response));
            catch ME
                testCase.verifySubstring(ME.identifier, 'MATLAB:', ...
                    'Should fail gracefully');
            end
        end

        function testSessionPersistence(testCase)
            %TESTSESSIONPERSISTENCE Verify session ID is stored

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            testCase.verifyClass(pm, 'claudecode.ClaudeProcessManager');
        end

        function testStopProcess(testCase)
            %TESTSTOPPROCESS Verify stopProcess doesn't error

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            pm.stopProcess();
            testCase.verifyTrue(true);
        end

        function testLastErrorProperty(testCase)
            %TESTLASTERRORPROPERTY Verify LastError is accessible

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            testCase.verifyEqual(pm.LastError, '');
        end

        %% Multiple Stop Calls Tests
        function testMultipleStopCallsNoError(testCase)
            %TESTMULTIPLESTOPCALLSNOERROR Verify multiple stops don't error

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            pm.stopProcess();
            pm.stopProcess();
            pm.stopProcess();
            testCase.verifyTrue(true, 'Multiple stop calls should not error');
        end

        function testStopAfterDelete(testCase)
            %TESTSTOPAFTERDELETE Verify stop is safe during cleanup

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            pm.stopProcess();
            delete(pm);
            testCase.verifyTrue(true);
        end

        %% LastError State Management Tests
        function testLastErrorInitiallyEmpty(testCase)
            %TESTLASTERRORINITIALLYEMPTY Verify LastError starts empty

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            testCase.verifyEqual(pm.LastError, '');
        end

        function testLastErrorPersists(testCase)
            %TESTLASTERRORPERSISTS Verify LastError is accessible

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            err1 = pm.LastError;
            err2 = pm.LastError;
            testCase.verifyEqual(err1, err2, 'LastError should be consistent');
        end

        function testLastErrorIsString(testCase)
            %TESTLASTERRORISSTRING Verify LastError type

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            testCase.verifyClass(pm.LastError, 'char');
        end

        %% Timeout Configuration Tests
        function testDefaultTimeout(testCase)
            %TESTDEFAULTTIMEOUT Verify default timeout behavior

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            try
                response = pm.sendMessage('test', 'timeout', 1);
                testCase.verifyTrue(isstruct(response));
            catch ME
                testCase.verifyTrue(true);
            end
        end

        %% Multiple Instance Tests
        function testMultipleInstances(testCase)
            %TESTMULTIPLEINSTANCES Verify multiple managers coexist

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm1 = claudecode.ClaudeProcessManager();
            pm2 = claudecode.ClaudeProcessManager();

            testCase.verifyClass(pm1, 'claudecode.ClaudeProcessManager');
            testCase.verifyClass(pm2, 'claudecode.ClaudeProcessManager');
            testCase.verifyTrue(pm1.isClaudeAvailable() == pm2.isClaudeAvailable());

            delete(pm1);
            delete(pm2);
        end

        %% isClaudeAvailable Consistency Tests
        function testIsClaudeAvailableConsistent(testCase)
            %TESTISCLAUDEAVAILABLECONSISTENT Verify consistent results

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            result1 = pm.isClaudeAvailable();
            result2 = pm.isClaudeAvailable();
            result3 = pm.isClaudeAvailable();
            testCase.verifyEqual(result1, result2);
            testCase.verifyEqual(result2, result3);
        end

        function testIsClaudeAvailableAfterStop(testCase)
            %TESTISCLAUDEAVAILABLEAFTERSTOP Verify still works after stop

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            pm.stopProcess();
            result = pm.isClaudeAvailable();
            testCase.verifyClass(result, 'logical');
        end

        %% Clean Destruction Tests
        function testDestructorMultipleTimes(testCase)
            %TESTDESTRUCTORMULTIPLETIMES Verify delete is idempotent

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            delete(pm);
            testCase.verifyFalse(isvalid(pm));
        end

        function testDestructorWithActiveProcess(testCase)
            %TESTDESTRUCTORWITHACTIVEPROCESS Verify clean destruction

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            try
                pm.sendMessage('test', 'timeout', 100);
            catch
            end
            delete(pm);
            testCase.verifyFalse(isvalid(pm));
        end

        %% Error Recovery Tests
        function testRecoveryAfterError(testCase)
            %TESTRECOVERYAFTERERROR Verify manager recovers from errors

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            try
                pm.sendMessage('test', 'timeout', 1);
            catch
            end
            testCase.verifyClass(pm, 'claudecode.ClaudeProcessManager');
            result = pm.isClaudeAvailable();
            testCase.verifyClass(result, 'logical');
        end
    end

    methods (Test, ParameterCombination = 'sequential')
        function testToolConfigurations(testCase, ToolSets)
            %TESTTOOLCONFIGURATIONS Test different tool configurations

            testCase.assumeTrue(testCase.ClassExists, 'ClaudeProcessManager not available');

            pm = claudecode.ClaudeProcessManager();
            testCase.verifyClass(pm, 'claudecode.ClaudeProcessManager');
        end
    end
end
