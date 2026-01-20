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

        %% Nested Subsystem Context Extraction Tests
        function testNestedSubsystemContextExtraction(testCase)
            %TESTNESTEDSUBSYSTEMCONTEXTEXTRACTION Verify nested subsystem handling

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            % Create model with nested subsystem
            new_system(testCase.TestModelName);
            add_block('simulink/Ports & Subsystems/Subsystem', ...
                [testCase.TestModelName, '/OuterSub']);
            add_block('simulink/Sources/Constant', ...
                [testCase.TestModelName, '/OuterSub/InnerConst']);

            testCase.Bridge.setCurrentModel(testCase.TestModelName);
            context = testCase.Bridge.extractModelContext();

            testCase.verifyTrue(isstruct(context));
            testCase.verifyNotEmpty(context.blocks);

            close_system(testCase.TestModelName, 0);
        end

        function testDeeplyNestedSubsystem(testCase)
            %TESTDEEPLYNESTEDSUBSYSTEM Verify deep nesting

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Ports & Subsystems/Subsystem', ...
                [testCase.TestModelName, '/Level1']);
            add_block('simulink/Ports & Subsystems/Subsystem', ...
                [testCase.TestModelName, '/Level1/Level2']);
            add_block('simulink/Sources/Constant', ...
                [testCase.TestModelName, '/Level1/Level2/DeepConst']);

            testCase.Bridge.setCurrentModel(testCase.TestModelName);
            context = testCase.Bridge.extractModelContext();

            testCase.verifyTrue(isstruct(context));

            close_system(testCase.TestModelName, 0);
        end

        %% Delete Connected Block Tests
        function testDeleteConnectedBlockSuccess(testCase)
            %TESTDELETECONNECTEDBLOCKSUCCESS Verify deleting connected blocks

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', ...
                [testCase.TestModelName, '/Src']);
            add_block('simulink/Sinks/Scope', ...
                [testCase.TestModelName, '/Dst']);

            testCase.Bridge.setCurrentModel(testCase.TestModelName);

            % Connect and then delete
            testCase.Bridge.connectBlocks('Src', 1, 'Dst', 1);
            success = testCase.Bridge.deleteBlock('Src');

            testCase.verifyTrue(success);

            % Verify block is gone
            blocks = find_system(testCase.TestModelName, 'Name', 'Src');
            testCase.verifyEmpty(blocks);

            close_system(testCase.TestModelName, 0);
        end

        function testDeleteNonExistentBlock(testCase)
            %TESTDELETENONEXISTENTBLOCK Verify graceful failure

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            testCase.Bridge.setCurrentModel(testCase.TestModelName);

            success = testCase.Bridge.deleteBlock('NonExistent');

            testCase.verifyFalse(success);

            close_system(testCase.TestModelName, 0);
        end

        %% Multiple Block Addition Tests
        function testMultipleBlockAdditionsSequence(testCase)
            %TESTMULTIPLEBLOCKADDITIONSSEQUENCE Verify sequential additions

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            testCase.Bridge.setCurrentModel(testCase.TestModelName);

            % Add multiple blocks
            results = [];
            for i = 1:5
                name = sprintf('Block%d', i);
                success = testCase.Bridge.addBlockFromLibrary(...
                    'simulink/Sources/Constant', name);
                results(end+1) = success;
            end

            testCase.verifyTrue(all(results), 'All blocks should be added');

            % Verify count
            blocks = find_system(testCase.TestModelName, 'Type', 'Block');
            testCase.verifyGreaterThanOrEqual(length(blocks), 5);

            close_system(testCase.TestModelName, 0);
        end

        function testAddDuplicateBlockName(testCase)
            %TESTADDDUPLICATEBLOCKNAME Verify duplicate name handling

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            testCase.Bridge.setCurrentModel(testCase.TestModelName);

            % Add first block
            success1 = testCase.Bridge.addBlockFromLibrary(...
                'simulink/Sources/Constant', 'DupeBlock');
            testCase.verifyTrue(success1);

            % Try to add block with same name
            success2 = testCase.Bridge.addBlockFromLibrary(...
                'simulink/Sources/Constant', 'DupeBlock');

            % Second should fail or auto-rename
            % Either way, should not crash
            testCase.verifyClass(success2, 'logical');

            close_system(testCase.TestModelName, 0);
        end

        %% Current Model Property Tests
        function testCurrentModelProperty(testCase)
            %TESTCURRENTMODELPROPERTY Verify CurrentModel property

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            testCase.Bridge.setCurrentModel(testCase.TestModelName);

            testCase.verifyEqual(testCase.Bridge.CurrentModel, testCase.TestModelName);

            close_system(testCase.TestModelName, 0);
        end

        function testCurrentModelAfterClose(testCase)
            %TESTCURRENTMODELAFTERCLOSE Verify behavior after model close

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            testCase.Bridge.setCurrentModel(testCase.TestModelName);
            close_system(testCase.TestModelName, 0);

            % CurrentModel property should still have the name
            % (Bridge doesn't auto-clear on external close)
            testCase.verifyEqual(testCase.Bridge.CurrentModel, testCase.TestModelName);
        end

        %% Block Parameter Edge Cases
        function testSetInvalidParameter(testCase)
            %TESTSETINVALIDPARAMETER Verify invalid parameter handling

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', ...
                [testCase.TestModelName, '/Const']);

            testCase.Bridge.setCurrentModel(testCase.TestModelName);

            % Try to set non-existent parameter
            success = testCase.Bridge.setBlockParameter('Const', 'FakeParam', '123');

            testCase.verifyFalse(success);

            close_system(testCase.TestModelName, 0);
        end

        function testSetParameterOnNonExistentBlock(testCase)
            %TESTSETPARAMETERONNONEXISTENTBLOCK Verify handling

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            testCase.Bridge.setCurrentModel(testCase.TestModelName);

            success = testCase.Bridge.setBlockParameter('Ghost', 'Value', '1');

            testCase.verifyFalse(success);

            close_system(testCase.TestModelName, 0);
        end

        %% Connection Edge Cases
        function testConnectInvalidPorts(testCase)
            %TESTCONNECTINVALIDPORTS Verify invalid port handling

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', ...
                [testCase.TestModelName, '/Const']);
            add_block('simulink/Sinks/Scope', ...
                [testCase.TestModelName, '/Scope']);

            testCase.Bridge.setCurrentModel(testCase.TestModelName);

            % Try to connect with invalid port numbers
            success = testCase.Bridge.connectBlocks('Const', 99, 'Scope', 99);

            testCase.verifyFalse(success);

            close_system(testCase.TestModelName, 0);
        end

        %% Model Discovery Tests
        function testGetOpenModelsReturnsCorrectCount(testCase)
            %TESTGETOPENMODELSRETURNSCORRECTCOUNT Verify model counting

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            % Get initial count
            initialModels = testCase.Bridge.getOpenModels();

            % Create test model
            new_system(testCase.TestModelName);

            % Get new count
            newModels = testCase.Bridge.getOpenModels();

            testCase.verifyGreaterThanOrEqual(length(newModels), length(initialModels));

            close_system(testCase.TestModelName, 0);
        end
    end
end
