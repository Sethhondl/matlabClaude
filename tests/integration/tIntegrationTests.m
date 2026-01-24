classdef tIntegrationTests < matlab.unittest.TestCase
    %TINTEGRATIONTESTS Cross-component integration tests
    %
    %   Run tests with:
    %       results = runtests('tIntegrationTests');
    %
    %   These tests verify that components work together correctly.

    properties
        OriginalVars
    end

    methods (TestMethodSetup)
        function saveWorkspaceState(testCase)
            testCase.OriginalVars = evalin('base', 'who');
        end
    end

    methods (TestMethodTeardown)
        function restoreWorkspaceState(testCase)
            % Clean up test variables
            currentVars = evalin('base', 'who');
            testVars = setdiff(currentVars, testCase.OriginalVars);

            for i = 1:length(testVars)
                evalin('base', sprintf('clear %s', testVars{i}));
            end
        end
    end

    methods (Test)
        %% Settings and ExecutionPolicy Integration
        function testExecutionPolicyMapsToSettings(testCase)
            %TESTEXECUTIONPOLICYMAPSTOSETTINGS Verify policy maps to settings

            settings = derivux.config.Settings();

            % Verify codeExecutionMode values map to ExecutionPolicy
            validModes = {'auto', 'prompt', 'disabled'};

            for i = 1:length(validModes)
                settings.codeExecutionMode = validModes{i};
                testCase.verifyEqual(settings.codeExecutionMode, validModes{i});
            end
        end

        function testSettingsApplyToCodeExecutor(testCase)
            %TESTSETTINGSAPPLYTOCODEEXECUTOR Verify settings affect executor

            settings = derivux.config.Settings();
            executor = derivux.CodeExecutor();

            % Apply settings to executor
            executor.Timeout = settings.executionTimeout;
            executor.AllowSystemCommands = settings.allowSystemCommands;
            executor.AllowDestructiveOps = settings.allowDestructiveOps;

            testCase.verifyEqual(executor.Timeout, settings.executionTimeout);
            testCase.verifyEqual(executor.AllowSystemCommands, settings.allowSystemCommands);
            testCase.verifyEqual(executor.AllowDestructiveOps, settings.allowDestructiveOps);
        end

        %% CodeExecutor and WorkspaceContextProvider Integration
        function testCodeExecutorModifiesWorkspace(testCase)
            %TESTCODEEXECUTORMODIFIESWORKSPACE Verify executor changes are visible

            executor = derivux.CodeExecutor();
            provider = derivux.WorkspaceContextProvider();

            % Execute code that creates a variable
            executor.execute('integration_test_var = 42;');

            % Get workspace context
            context = provider.getWorkspaceContext();

            % Verify variable is visible in context
            testCase.verifySubstring(context, 'integration_test_var');
        end

        function testWorkspaceContextReflectsChanges(testCase)
            %TESTWORKSPACECONTEXTREFLECTSCHANGES Verify real-time updates

            provider = derivux.WorkspaceContextProvider();

            % Initial context
            context1 = provider.getWorkspaceContext();

            % Modify workspace
            evalin('base', 'integration_new_var = [1, 2, 3];');

            % Updated context
            context2 = provider.getWorkspaceContext();

            % New variable should appear
            testCase.verifySubstring(context2, 'integration_new_var');
        end

        %% Settings Persistence Integration
        function testSettingsSaveAndLoadRoundTrip(testCase)
            %TESTSETTINGSSAVEANDLOADROUNDTRIP Verify settings persistence

            % Create and modify settings
            settings1 = derivux.config.Settings();
            originalTheme = settings1.theme;
            originalTimeout = settings1.executionTimeout;

            settings1.theme = 'light';
            settings1.executionTimeout = 60;
            settings1.save();

            % Load in new instance
            settings2 = derivux.config.Settings.load();

            testCase.verifyEqual(settings2.theme, 'light');
            testCase.verifyEqual(settings2.executionTimeout, 60);

            % Restore original settings
            settings1.theme = originalTheme;
            settings1.executionTimeout = originalTimeout;
            settings1.save();
        end

        %% ExecutionPolicy Behavior Integration
        function testExecutionPolicyAutoAllowsExecution(testCase)
            %TESTEXECUTIONPOLICYAUTOALLOWSEXECUTION Verify Auto policy

            policy = derivux.config.ExecutionPolicy.Auto;
            executor = derivux.CodeExecutor();

            % Auto should not require approval
            executor.RequireApproval = policy.requiresApproval();

            % Execute safe code - should work without prompt
            [~, isError] = executor.execute('test_auto = 1;');

            testCase.verifyFalse(isError);
        end

        function testExecutionPolicyDisabledPreventsExecution(testCase)
            %TESTEXECUTIONPOLICYDISABLEDPREVENTSEXECUTION Verify Disabled policy

            policy = derivux.config.ExecutionPolicy.Disabled;

            testCase.verifyFalse(policy.isEnabled(), ...
                'Disabled policy should report not enabled');
        end

        %% CodeExecutor Validation and Logging Integration
        function testValidationAndLoggingIntegration(testCase)
            %TESTVALIDATIONANDLOGGINGINTEGRATION Verify validation logs correctly

            executor = derivux.CodeExecutor();
            executor.LogExecutions = true;
            executor.clearLog();

            % Execute safe code
            executor.execute('x = 1;');

            % Try blocked code
            executor.execute('system(''ls'');');

            % Get log
            log = executor.getExecutionLog();

            testCase.verifyLength(log, 2);
            testCase.verifyEqual(log{1}.status, 'success');
            testCase.verifyEqual(log{2}.status, 'blocked');
        end

        %% Multi-Component Workflow Test
        function testCompleteWorkflow(testCase)
            %TESTCOMPLETEWORKFLOW Verify full workflow

            % 1. Load settings
            settings = derivux.config.Settings();
            testCase.verifyClass(settings, 'derivux.config.Settings');

            % 2. Create executor with settings
            executor = derivux.CodeExecutor();
            executor.Timeout = settings.executionTimeout;
            testCase.verifyEqual(executor.Timeout, settings.executionTimeout);

            % 3. Create workspace provider
            provider = derivux.WorkspaceContextProvider();
            testCase.verifyClass(provider, 'derivux.WorkspaceContextProvider');

            % 4. Execute code
            [result, isError] = executor.execute('workflow_test = magic(3);');
            testCase.verifyFalse(isError);

            % 5. Verify in workspace context
            context = provider.getWorkspaceContext();
            testCase.verifySubstring(context, 'workflow_test');
        end

        %% SimulinkBridge Integration (without Simulink)
        function testSimulinkBridgeWithWorkspaceProvider(testCase)
            %TESTSIMULINKBRIDGEWITHWORKSPACEPROVIDER Verify components coexist

            bridge = derivux.SimulinkBridge();
            provider = derivux.WorkspaceContextProvider();

            % Both should work independently
            bridgeContext = bridge.buildSimulinkContext();
            workspaceContext = provider.getWorkspaceContext();

            testCase.verifyClass(bridgeContext, 'char');
            testCase.verifyClass(workspaceContext, 'char');
        end

        %% Settings Default Consistency
        function testAllSettingsHaveDefaults(testCase)
            %TESTALLSETTINGSHAVEDEFAULTS Verify all properties have values

            settings = derivux.config.Settings();
            props = properties(settings);

            for i = 1:length(props)
                propName = props{i};
                value = settings.(propName);

                testCase.verifyFalse(isempty(value) && ~ischar(value), ...
                    sprintf('Property %s should have a default value', propName));
            end
        end

        %% Error Handling Integration
        function testErrorHandlingAcrossComponents(testCase)
            %TESTERRORHANDLINGACROSSCOMPONENTS Verify errors are handled gracefully

            executor = derivux.CodeExecutor();
            executor.LogExecutions = true;
            executor.clearLog();

            % Execute code with syntax error
            [result, isError] = executor.execute('for i = 1:10');  % Missing end

            testCase.verifyTrue(isError);

            % Log should record the error
            log = executor.getExecutionLog();
            testCase.verifyNotEmpty(log);
            testCase.verifyEqual(log{end}.status, 'error');
        end
    end
end
