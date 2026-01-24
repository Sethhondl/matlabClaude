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
            testCase.Executor = derivux.CodeExecutor();
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

            executor = derivux.CodeExecutor();
            testCase.verifyClass(executor, 'derivux.CodeExecutor');
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

        %% RequireApproval Property Tests
        function testRequireApprovalDefaultFalse(testCase)
            %TESTREQUIREAPPROVALDEFAULTFALSE Verify default is false

            testCase.verifyFalse(testCase.Executor.RequireApproval);
        end

        function testRequireApprovalCanBeSet(testCase)
            %TESTREQUIREAPPROVALCANBESET Verify property can be changed

            testCase.Executor.RequireApproval = true;
            testCase.verifyTrue(testCase.Executor.RequireApproval);
        end

        %% Log Entry Details Tests
        function testLogEntryContainsTimestamp(testCase)
            %TESTLOGENTRYCONTAINSTIMESTAMP Verify log entries have timestamps

            testCase.Executor.LogExecutions = true;
            testCase.Executor.clearLog();
            testCase.Executor.execute('x = 1;');

            log = testCase.Executor.getExecutionLog();

            testCase.verifyNotEmpty(log);
            testCase.verifyTrue(isfield(log{1}, 'timestamp'));
            testCase.verifyClass(log{1}.timestamp, 'datetime');
        end

        function testLogEntryContainsStatus(testCase)
            %TESTLOGENTRYCONTAINSSTATUS Verify log entries have status

            testCase.Executor.LogExecutions = true;
            testCase.Executor.clearLog();
            testCase.Executor.execute('y = 2;');

            log = testCase.Executor.getExecutionLog();

            testCase.verifyTrue(isfield(log{1}, 'status'));
            testCase.verifyEqual(log{1}.status, 'success');
        end

        function testLogEntryContainsCode(testCase)
            %TESTLOGENTRYCONTAINSCODE Verify log entries have original code

            testCase.Executor.LogExecutions = true;
            testCase.Executor.clearLog();

            code = 'z = 3 + 4;';
            testCase.Executor.execute(code);

            log = testCase.Executor.getExecutionLog();

            testCase.verifyTrue(isfield(log{1}, 'code'));
            testCase.verifyEqual(log{1}.code, code);
        end

        %% Log Size Limit Tests
        function testLogSizeLimit(testCase)
            %TESTLOGSIZELIMIT Verify log doesn't exceed 100 entries

            testCase.Executor.LogExecutions = true;
            testCase.Executor.clearLog();

            % Execute more than 100 commands
            for i = 1:110
                testCase.Executor.execute(sprintf('limit_test_%d = %d;', i, i));
            end

            log = testCase.Executor.getExecutionLog();

            testCase.verifyLessThanOrEqual(length(log), 100, ...
                'Log should not exceed 100 entries');
        end

        %% Additional Blocked Operations Tests
        function testBlockEvalc(testCase)
            %TESTBLOCKEVALC Verify evalc() is blocked

            dangerousCode = 'evalc(''disp(1)'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'evalc');
        end

        function testBlockFeval(testCase)
            %TESTBLOCKFEVAL Verify feval() is blocked

            dangerousCode = 'feval(''disp'', 1);';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'feval');
        end

        function testBlockBuiltin(testCase)
            %TESTBLOCKBUILTIN Verify builtin() is blocked

            dangerousCode = 'builtin(''disp'', ''hello'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'builtin');
        end

        function testBlockPerl(testCase)
            %TESTBLOCKPERL Verify perl() is blocked

            dangerousCode = 'perl(''script.pl'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'perl');
        end

        function testBlockUrlread(testCase)
            %TESTBLOCKURLREAD Verify urlread() is blocked

            dangerousCode = 'urlread(''http://evil.com'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'urlread');
        end

        function testBlockUrlwrite(testCase)
            %TESTBLOCKURLWRITE Verify urlwrite() is blocked

            dangerousCode = 'urlwrite(''http://example.com'', ''file.txt'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'urlwrite');
        end

        function testBlockWebread(testCase)
            %TESTBLOCKWEBREAD Verify webread() is blocked

            dangerousCode = 'webread(''http://api.example.com'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'webread');
        end

        function testBlockWebwrite(testCase)
            %TESTBLOCKWEBWRITE Verify webwrite() is blocked

            dangerousCode = 'webwrite(''http://api.example.com'', data);';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'webwrite');
        end

        function testBlockWebsave(testCase)
            %TESTBLOCKWEBSAVE Verify websave() is blocked

            dangerousCode = 'websave(''file.dat'', ''http://example.com/file'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'websave');
        end

        function testBlockPythonCommand(testCase)
            %TESTBLOCKPYTHONCOMMAND Verify python() is blocked

            dangerousCode = 'python(''script.py'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'python');
        end

        function testBlockPySubprocess(testCase)
            %TESTBLOCKPYSUBPROCESS Verify py.subprocess is blocked

            dangerousCode = 'py.subprocess.call(''ls'');';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'py.subprocess');
        end

        %% ExecutionWorkspace Property Tests
        function testExecutionWorkspaceDefault(testCase)
            %TESTEXECUTIONWORKSPACEDEFAULT Verify default workspace

            testCase.verifyEqual(testCase.Executor.ExecutionWorkspace, 'base');
        end

        function testExecutionWorkspaceCanBeChanged(testCase)
            %TESTEXECUTIONWORKSPACECANBECHANGED Verify can change workspace

            testCase.Executor.ExecutionWorkspace = 'caller';
            testCase.verifyEqual(testCase.Executor.ExecutionWorkspace, 'caller');
        end

        %% Multiline Code Tests
        function testMultilineCodeWithDangerousOperation(testCase)
            %TESTMULTILINECODEWITHSDANGEROUSOPERATION Verify multiline detection

            multilineCode = sprintf('x = 1;\ny = 2;\nsystem(''ls'');\nz = 3;');
            [isValid, reason] = testCase.Executor.validateCode(multilineCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'system');
        end

        function testMultilineSafeCode(testCase)
            %TESTMULTILINESAFECODE Verify multiline safe code works

            multilineCode = sprintf('x = 1;\ny = 2;\nz = x + y;');
            [isValid, ~] = testCase.Executor.validateCode(multilineCode);

            testCase.verifyTrue(isValid);
        end

        %% Variable Name Edge Cases
        function testDeleteVariableNameAllowed(testCase)
            %TESTDELETEVARIABLENAMEALLOWED Verify 'delete_var' variable allowed

            safeCode = 'delete_flag = true;';
            [isValid, ~] = testCase.Executor.validateCode(safeCode);

            testCase.verifyTrue(isValid, ...
                'Variable names containing ''delete'' should be allowed');
        end

        function testSystemVariableAllowed(testCase)
            %TESTSYSTEMVARIABLEALLOWED Verify 'system_info' variable allowed

            safeCode = 'system_info = struct();';
            [isValid, ~] = testCase.Executor.validateCode(safeCode);

            testCase.verifyTrue(isValid, ...
                'Variable names containing ''system'' should be allowed');
        end

        function testEvalVariableAllowed(testCase)
            %TESTEVALVARIABLEALLOWED Verify 'eval_result' variable allowed

            safeCode = 'eval_result = 42;';
            [isValid, ~] = testCase.Executor.validateCode(safeCode);

            testCase.verifyTrue(isValid, ...
                'Variable names containing ''eval'' should be allowed');
        end

        %% Blocked Status in Log Tests
        function testBlockedCodeLogStatus(testCase)
            %TESTBLOCKEDCODELOGSTATUS Verify blocked code logs as blocked

            testCase.Executor.LogExecutions = true;
            testCase.Executor.clearLog();

            testCase.Executor.execute('system(''whoami'');');

            log = testCase.Executor.getExecutionLog();

            testCase.verifyNotEmpty(log);
            testCase.verifyEqual(log{1}.status, 'blocked');
            testCase.verifyTrue(log{1}.isError);
        end

        %% Clear Variants Tests
        function testBlockClearvars(testCase)
            %TESTBLOCKCLEARVARS Verify clearvars is blocked

            dangerousCode = 'clearvars;';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'clearvars');
        end

        function testBlockRestart(testCase)
            %TESTBLOCKRESTART Verify restart is blocked

            dangerousCode = 'restart;';
            [isValid, reason] = testCase.Executor.validateCode(dangerousCode);

            testCase.verifyFalse(isValid);
            testCase.verifySubstring(reason, 'restart');
        end

        %% LogExecutions Property Tests
        function testLogExecutionsDefaultTrue(testCase)
            %TESTLOGEXECUTIONSDEFAULTTRUE Verify logging enabled by default

            testCase.verifyTrue(testCase.Executor.LogExecutions);
        end

        function testLogExecutionsDisabled(testCase)
            %TESTLOGEXECUTIONSDISABLED Verify logging can be disabled

            testCase.Executor.LogExecutions = false;
            testCase.Executor.clearLog();

            testCase.Executor.execute('x = 1;');

            log = testCase.Executor.getExecutionLog();
            testCase.verifyEmpty(log, ...
                'Log should be empty when logging disabled');
        end
    end
end
