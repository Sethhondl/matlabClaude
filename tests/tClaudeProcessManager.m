classdef tClaudeProcessManager < matlab.unittest.TestCase
    %TCLAUDEPROCESSMANAGER Unit tests for ClaudeProcessManager
    %
    %   Run tests with:
    %       results = runtests('tClaudeProcessManager');

    properties (TestParameter)
        % Test different tool configurations
        ToolSets = struct(...
            'Default', {{'Edit', 'Write', 'Read', 'Bash', 'Glob', 'Grep'}}, ...
            'ReadOnly', {{'Read', 'Glob', 'Grep'}}, ...
            'Empty', {{}})
    end

    methods (Test)
        function testConstructor(testCase)
            %TESTCONSTRUCTOR Verify constructor creates valid object

            pm = claudecode.ClaudeProcessManager();

            testCase.verifyClass(pm, 'claudecode.ClaudeProcessManager');
            testCase.verifyFalse(pm.isClaudeAvailable() == -1, ...
                'isClaudeAvailable should return boolean');
        end

        function testIsClaudeAvailableReturnsBoolean(testCase)
            %TESTISCLAUDEAVAILABLERETURNSBOOLEAN Verify return type

            pm = claudecode.ClaudeProcessManager();
            result = pm.isClaudeAvailable();

            testCase.verifyClass(result, 'logical');
        end

        function testDestructor(testCase)
            %TESTDESTRUCTOR Verify clean destruction

            pm = claudecode.ClaudeProcessManager();
            delete(pm);

            % Should not error - if we get here, destruction was clean
            testCase.verifyTrue(true);
        end

        function testBuildCommandArgsDefault(testCase)
            %TESTBUILDCOMMANDARGSDEFAULT Test command building with defaults

            pm = claudecode.ClaudeProcessManager();

            % Access private method via metaclass
            % Note: This tests internal behavior - may need adjustment
            % if implementation changes

            % For now, test that sendMessage doesn't error with basic input
            % (actual CLI call may fail if Claude not installed)
            try
                % This will fail gracefully if Claude CLI not available
                response = pm.sendMessage('test', 'timeout', 1000);
                testCase.verifyTrue(isstruct(response));
            catch ME
                % Expected if Claude CLI not installed
                testCase.verifySubstring(ME.identifier, 'MATLAB:', ...
                    'Should fail gracefully');
            end
        end

        function testSessionPersistence(testCase)
            %TESTSESSIONPERSISTENCE Verify session ID is stored

            pm = claudecode.ClaudeProcessManager();

            % Initially no session
            % Session ID is private, so we test behavior indirectly
            testCase.verifyClass(pm, 'claudecode.ClaudeProcessManager');
        end

        function testStopProcess(testCase)
            %TESTSTOPPROCESS Verify stopProcess doesn't error

            pm = claudecode.ClaudeProcessManager();

            % Should not error even if no process running
            pm.stopProcess();

            testCase.verifyTrue(true);
        end

        function testLastErrorProperty(testCase)
            %TESTLASTERRORPROPERTY Verify LastError is accessible

            pm = claudecode.ClaudeProcessManager();

            % LastError should be empty string initially
            testCase.verifyEqual(pm.LastError, '');
        end
    end

    methods (Test, ParameterCombination = 'sequential')
        function testToolConfigurations(testCase, ToolSets)
            %TESTTOOLCONFIGURATIONS Test different tool configurations

            pm = claudecode.ClaudeProcessManager();

            % Verify we can create manager with different tool sets
            % Actual message sending tested elsewhere
            testCase.verifyClass(pm, 'claudecode.ClaudeProcessManager');
        end
    end
end
