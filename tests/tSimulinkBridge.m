classdef tSimulinkBridge < matlab.unittest.TestCase
    %TSIMULINKBRIDGE Unit tests for SimulinkBridge
    %
    %   Run tests with:
    %       results = runtests('tSimulinkBridge');
    %
    %   Note: Some tests require Simulink to be installed.

    properties
        Bridge
        TestModelName = 'test_model_temp'
        SimulinkAvailable
    end

    methods (TestClassSetup)
        function checkSimulink(testCase)
            % Check if Simulink is available
            testCase.SimulinkAvailable = license('test', 'Simulink');
        end
    end

    methods (TestMethodSetup)
        function createBridge(testCase)
            testCase.Bridge = claudecode.SimulinkBridge();
        end
    end

    methods (TestMethodTeardown)
        function cleanupBridge(testCase)
            % Close test model if open
            if testCase.SimulinkAvailable
                try
                    if bdIsLoaded(testCase.TestModelName)
                        close_system(testCase.TestModelName, 0);
                    end
                catch
                    % Ignore errors
                end
            end
            delete(testCase.Bridge);
        end
    end

    methods (Test)
        %% Constructor Tests
        function testConstructor(testCase)
            %TESTCONSTRUCTOR Verify constructor creates valid object

            bridge = claudecode.SimulinkBridge();
            testCase.verifyClass(bridge, 'claudecode.SimulinkBridge');
        end

        function testInitialState(testCase)
            %TESTINITIALSTATE Verify initial state

            testCase.verifyEmpty(testCase.Bridge.CurrentModel);
        end

        %% Model Discovery Tests
        function testGetOpenModelsReturnsCell(testCase)
            %TESTGETOPENMODELSRETURNSCELL Verify return type

            models = testCase.Bridge.getOpenModels();
            testCase.verifyClass(models, 'cell');
        end

        function testGetCurrentModelInitiallyEmpty(testCase)
            %TESTGETCURRENTMODELINITIALLYEMPTY Verify no model set initially

            name = testCase.Bridge.getCurrentModel();
            testCase.verifyEmpty(name);
        end

        %% Context Extraction Tests (without Simulink)
        function testExtractContextWithoutModel(testCase)
            %TESTEXTRACTCONTEXTWITHOUTMODEL Verify error handling

            context = testCase.Bridge.extractModelContext();

            testCase.verifyTrue(isstruct(context));
            testCase.verifyTrue(isfield(context, 'error'));
        end

        function testBuildContextWithoutModel(testCase)
            %TESTBUILDCONTEXTWITHOUTMODEL Verify string output

            contextStr = testCase.Bridge.buildSimulinkContext();

            testCase.verifyClass(contextStr, 'char');
        end

        %% Model Modification Tests (without active model)
        function testAddBlockWithoutModel(testCase)
            %TESTADDBLOCKWITHOUTMODEL Verify graceful failure

            success = testCase.Bridge.addBlockFromLibrary(...
                'simulink/Sources/Constant', 'TestConst');

            testCase.verifyFalse(success);
        end

        function testConnectBlocksWithoutModel(testCase)
            %TESTCONNECTBLOCKSWITHOUTMODEL Verify graceful failure

            success = testCase.Bridge.connectBlocks('A', 1, 'B', 1);

            testCase.verifyFalse(success);
        end

        function testSetBlockParameterWithoutModel(testCase)
            %TESTSETBLOCKPARAMETERWITHOUTMODEL Verify graceful failure

            success = testCase.Bridge.setBlockParameter('Block', 'Param', 'Value');

            testCase.verifyFalse(success);
        end

        function testDeleteBlockWithoutModel(testCase)
            %TESTDELETEBLOCKWITHOUTMODEL Verify graceful failure

            success = testCase.Bridge.deleteBlock('SomeBlock');

            testCase.verifyFalse(success);
        end

        %% Command Validation Tests
        function testExecuteValidSimulinkCommand(testCase)
            %TESTEXECUTEVALIDSIMULINKCOMMAND Verify valid command prefix check

            % This won't actually execute without a model, but tests validation
            success = testCase.Bridge.executeSimulinkCommand('invalid_command');

            testCase.verifyFalse(success);
        end

        function testRejectNonSimulinkCommand(testCase)
            %TESTREJECTNONSIMUMLINKCOMMAND Verify non-Simulink commands rejected

            success = testCase.Bridge.executeSimulinkCommand('disp(''hello'')');

            testCase.verifyFalse(success);
        end
    end

    methods (Test)
        %% Tests requiring Simulink
        function testSetCurrentModelWithSimulink(testCase)
            %TESTSETCURRENTMODELWITHSIMULINK Test model selection

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            % Create a test model
            new_system(testCase.TestModelName);

            success = testCase.Bridge.setCurrentModel(testCase.TestModelName);

            testCase.verifyTrue(success);
            testCase.verifyEqual(testCase.Bridge.CurrentModel, testCase.TestModelName);

            close_system(testCase.TestModelName, 0);
        end

        function testExtractModelContextWithSimulink(testCase)
            %TESTEXTRACTMODELCONTEXTWITHSIMULINK Test context extraction

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            % Create a test model with some blocks
            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', ...
                [testCase.TestModelName, '/Const1']);
            add_block('simulink/Sinks/Scope', ...
                [testCase.TestModelName, '/Scope1']);

            testCase.Bridge.setCurrentModel(testCase.TestModelName);
            context = testCase.Bridge.extractModelContext();

            testCase.verifyTrue(isstruct(context));
            testCase.verifyEqual(context.name, testCase.TestModelName);
            testCase.verifyTrue(iscell(context.blocks));
            testCase.verifyGreaterThanOrEqual(length(context.blocks), 2);

            close_system(testCase.TestModelName, 0);
        end

        function testAddBlockWithSimulink(testCase)
            %TESTADDBLOCKWITHSIMULINK Test block addition

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            testCase.Bridge.setCurrentModel(testCase.TestModelName);

            success = testCase.Bridge.addBlockFromLibrary(...
                'simulink/Sources/Constant', 'MyConstant');

            testCase.verifyTrue(success);

            % Verify block exists
            blocks = find_system(testCase.TestModelName, 'Name', 'MyConstant');
            testCase.verifyNotEmpty(blocks);

            close_system(testCase.TestModelName, 0);
        end

        function testConnectBlocksWithSimulink(testCase)
            %TESTCONNECTBLOCKSWITHSIMULINK Test block connection

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', ...
                [testCase.TestModelName, '/Source']);
            add_block('simulink/Sinks/Scope', ...
                [testCase.TestModelName, '/Sink']);

            testCase.Bridge.setCurrentModel(testCase.TestModelName);
            success = testCase.Bridge.connectBlocks('Source', 1, 'Sink', 1);

            testCase.verifyTrue(success);

            % Verify connection exists
            lines = find_system(testCase.TestModelName, 'FindAll', 'on', 'Type', 'line');
            testCase.verifyNotEmpty(lines);

            close_system(testCase.TestModelName, 0);
        end

        function testSetBlockParameterWithSimulink(testCase)
            %TESTSETBLOCKPARAMETERWITHSIMULINK Test parameter setting

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', ...
                [testCase.TestModelName, '/Const1']);

            testCase.Bridge.setCurrentModel(testCase.TestModelName);
            success = testCase.Bridge.setBlockParameter('Const1', 'Value', '42');

            testCase.verifyTrue(success);

            % Verify parameter was set
            value = get_param([testCase.TestModelName, '/Const1'], 'Value');
            testCase.verifyEqual(value, '42');

            close_system(testCase.TestModelName, 0);
        end

        function testBuildSimulinkContextFormat(testCase)
            %TESTBUILDSIMULINKCONTEXTFORMAT Test context string format

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', ...
                [testCase.TestModelName, '/Const1']);

            testCase.Bridge.setCurrentModel(testCase.TestModelName);
            contextStr = testCase.Bridge.buildSimulinkContext();

            % Verify it contains expected sections
            testCase.verifySubstring(contextStr, '## Simulink Model');
            testCase.verifySubstring(contextStr, '### Blocks');
            testCase.verifySubstring(contextStr, 'Const1');

            close_system(testCase.TestModelName, 0);
        end
    end
end
