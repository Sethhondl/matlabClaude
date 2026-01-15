classdef tCodeExecutor < matlab.unittest.TestCase
    %TCODEEXECUTOR Unit tests for CodeExecutor
    %
    %   Run tests with:
    %       results = runtests('tCodeExecutor');

    properties
        Executor
    end

    methods (TestMethodSetup)
        function createExecutor(testCase)
            testCase.Executor = claudecode.CodeExecutor();
        end
    end

    methods (TestMethodTeardown)
        function cleanupExecutor(testCase)
            delete(testCase.Executor);
        end
    end

    methods (Test)
        %% Constructor Tests
        function testConstructor(testCase)
            %TESTCONSTRUCTOR Verify constructor creates valid object

            executor = claudecode.CodeExecutor();
            testCase.verifyClass(executor, 'claudecode.CodeExecutor');
        end

        function testDefaultProperties(testCase)
            %TESTDEFAULTPROPERTIES Verify default property values

            testCase.verifyFalse(testCase.Executor.AllowSystemCommands);
            testCase.verifyTrue(testCase.Executor.AllowFileOperations);
            testCase.verifyFalse(testCase.Executor.AllowDestructiveOps);
            testCase.verifyEqual(testCase.Executor.Timeout, 30);
            testCase.verifyEqual(testCase.Executor.ExecutionWorkspace, 'base');
        end

        %% Validation Tests - Safe Code
        function testValidateSafeCode(testCase)
            %TESTVALIDATESAFECODE Verify safe code passes validation

            safeCode = 'x = 1 + 1;';
            [isValid, reason] = testCase.Executor.validateCode(safeCode);

            testCase.verifyTrue(isValid);
            testCase.verifyEmpty(reason);
        end

        function testValidateMathOperations(testCase)
            %TESTVALIDATEMATHOPERATIONS Verify math code is safe

            mathCode = 'y = sin(pi/4) * cos(pi/3);';
            [isValid, ~] = testCase.Executor.validateCode(mathCode);

            testCase.verifyTrue(isValid);
        end

        function testValidatePlotCode(testCase)
            %TESTVALIDATEPLOTCODE Verify plotting code is safe

            plotCode = 'figure; plot(1:10, rand(1,10)); title(''Test'');';
            [isValid, ~] = testCase.Executor.validateCode(plotCode);

            testCase.verifyTrue(isValid);
        end

        function testValidateLoopCode(testCase)
            %TESTVALIDATELOOPCODE Verify loop code is safe

            loopCode = 'for i = 1:10; disp(i); end';
            [isValid, ~] = testCase.Executor.validateCode(loopCode);

            testCase.verifyTrue(isValid);
        end

        function testValidateFunctionDefinition(testCase)
            %TESTVALIDATEFUNCTIONDEFINITION Verify function definitions

            funcCode = 'f = @(x) x.^2 + 2*x + 1;';
            [isValid, ~] = testCase.Executor.validateCode(funcCode);

            testCase.verifyTrue(isValid);
        end

        %% Validation Tests - Blocked Code
        function testBlockSystemCommand(testCase)
            %TESTBLOCKSYSTEMCOMMAND Verify system() is blocked

            dangerousCode = 'system(''rm -rf /'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'system');
        end

        function testBlockEval(testCase)
            %TESTBLOCKEVAL Verify eval() is blocked

            dangerousCode = 'eval(''delete(''''important.m'''')'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'eval');
        end

        function testBlockEvalin(testCase)
            %TESTBLOCKEVALIN Verify evalin() is blocked

            dangerousCode = 'evalin(''base'', ''clear all'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'evalin');
        end

        function testBlockDelete(testCase)
            %TESTBLOCKDELETE Verify delete() is blocked

            dangerousCode = 'delete(''*.m'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'delete');
        end

        function testBlockRmdir(testCase)
            %TESTBLOCKRMDIR Verify rmdir() is blocked

            dangerousCode = 'rmdir(''important_folder'', ''s'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'rmdir');
        end

        function testBlockShellEscape(testCase)
            %TESTBLOCKSHELLESC Verify ! operator is blocked

            dangerousCode = '!rm -rf /';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'Shell escape');
        end

        function testBlockDos(testCase)
            %TESTBLOCKDOS Verify dos() is blocked

            dangerousCode = 'dos(''del /f /q *.*'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'dos');
        end

        function testBlockUnix(testCase)
            %TESTBLOCKUNIX Verify unix() is blocked

            dangerousCode = 'unix(''rm -rf ~'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'unix');
        end

        function testBlockJavaRuntime(testCase)
            %TESTBLOCKJAVARUNTIME Verify Java Runtime access is blocked

            dangerousCode = 'java.lang.Runtime.getRuntime().exec(''calc'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'java.lang.Runtime');
        end

        function testBlockPythonOs(testCase)
            %TESTBLOCKPYTHONOS Verify Python os access is blocked

            dangerousCode = 'py.os.system(''whoami'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'py.os');
        end

        function testBlockClear(testCase)
            %TESTBLOCKCLEAR Verify clear is blocked

            dangerousCode = 'clear all;';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'clear');
        end

        function testBlockExit(testCase)
            %TESTBLOCKEXIT Verify exit is blocked

            dangerousCode = 'exit;';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'exit');
        end

        function testBlockQuit(testCase)
            %TESTBLOCKQUIT Verify quit is blocked

            dangerousCode = 'quit;';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'quit');
        end

        %% Edge Cases
        function testNotEqualOperatorAllowed(testCase)
            %TESTNOTEQUAOPERATORALLOWED Verify ~= is not blocked as !

            safeCode = 'if x ~= 5; disp(''not five''); end';
            [isValid, ~] = testCase.Executor.validateCode(safeCode);

            testCase.verifyTrue(isValid);
        end

        function testSystemVariableNameAllowed(testCase)
            %TESTSYSTEMVARIABLENAMEALLOWED Verify 'system' as variable is OK

            % Variable named 'system_data' should be allowed
            safeCode = 'system_data = [1, 2, 3];';
            [isValid, ~] = testCase.Executor.validateCode(safeCode);

            testCase.verifyTrue(isValid);
        end

        %% Execution Tests
        function testExecuteSafeCode(testCase)
            %TESTEXECUTESAFECODE Verify safe code executes

            [result, isError] = testCase.Executor.execute('disp(''hello'');');

            testCase.verifyFalse(isError);
            testCase.verifySubstring(result, 'hello');
        end

        function testExecuteMathReturnsResult(testCase)
            %TESTEXECUTEMATHRETURNSRESULT Verify math returns output

            [result, isError] = testCase.Executor.execute('2 + 2');

            testCase.verifyFalse(isError);
            testCase.verifySubstring(result, '4');
        end

        function testExecuteBlockedCodeReturnsError(testCase)
            %TESTEXECUTEBLOCKEDCODERETURNSSERROR Verify blocked code fails

            [result, isError] = testCase.Executor.execute('system(''ls'');');

            testCase.verifyTrue(isError);
            testCase.verifySubstring(result, 'blocked');
        end

        function testExecuteSyntaxErrorReturnsError(testCase)
            %TESTEXECUTESYNTAXERRORRETURNSSERROR Verify syntax errors reported

            [result, isError] = testCase.Executor.execute('for i = 1:10');  % Missing end

            testCase.verifyTrue(isError);
            testCase.verifySubstring(lower(result), 'error');
        end

        %% Logging Tests
        function testExecutionLogging(testCase)
            %TESTEXECUTIONLOGGING Verify executions are logged

            testCase.Executor.LogExecutions = true;
            testCase.Executor.clearLog();

            testCase.Executor.execute('x = 1;');
            testCase.Executor.execute('y = 2;');

            log = testCase.Executor.getExecutionLog();

            testCase.verifyLength(log, 2);
        end

        function testClearLog(testCase)
            %TESTCLEARLOG Verify log can be cleared

            testCase.Executor.execute('x = 1;');
            testCase.Executor.clearLog();

            log = testCase.Executor.getExecutionLog();

            testCase.verifyEmpty(log);
        end
    end
end
