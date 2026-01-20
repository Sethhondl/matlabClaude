classdef tSimulinkIntegration < matlab.unittest.TestCase
    %TSIMULINKINTEGRATION Simulink-specific integration tests
    %
    %   Run tests with:
    %       results = runtests('tSimulinkIntegration');
    %
    %   Note: These tests require Simulink to be installed.

    properties
        Bridge
        TestModelName = 'integration_test_model'
        SimulinkAvailable
    end

    methods (TestClassSetup)
        function checkSimulink(testCase)
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
        %% Full Model Workflow Tests
        function testCompleteModelWorkflow(testCase)
            %TESTCOMPLETEMODELWORKFLOW Full workflow: create, add, connect, params

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            % Create model
            new_system(testCase.TestModelName);

            % Set current model
            success = testCase.Bridge.setCurrentModel(testCase.TestModelName);
            testCase.verifyTrue(success, 'Should set current model');

            % Add blocks
            success1 = testCase.Bridge.addBlockFromLibrary(...
                'simulink/Sources/Constant', 'Input');
            success2 = testCase.Bridge.addBlockFromLibrary(...
                'simulink/Math Operations/Gain', 'Amplifier');
            success3 = testCase.Bridge.addBlockFromLibrary(...
                'simulink/Sinks/Scope', 'Output');

            testCase.verifyTrue(success1 && success2 && success3, ...
                'Should add all blocks');

            % Connect blocks
            conn1 = testCase.Bridge.connectBlocks('Input', 1, 'Amplifier', 1);
            conn2 = testCase.Bridge.connectBlocks('Amplifier', 1, 'Output', 1);

            testCase.verifyTrue(conn1 && conn2, 'Should connect blocks');

            % Set parameters
            paramSuccess = testCase.Bridge.setBlockParameter('Input', 'Value', '5');
            testCase.verifyTrue(paramSuccess, 'Should set parameter');

            paramSuccess2 = testCase.Bridge.setBlockParameter('Amplifier', 'Gain', '2');
            testCase.verifyTrue(paramSuccess2, 'Should set gain');

            % Extract context
            context = testCase.Bridge.extractModelContext();
            testCase.verifyTrue(isstruct(context));
            testCase.verifyEqual(context.name, testCase.TestModelName);
            testCase.verifyGreaterThanOrEqual(length(context.blocks), 3);

            close_system(testCase.TestModelName, 0);
        end

        %% Context Extraction Without Model Set
        function testContextExtractionWithoutModel(testCase)
            %TESTCONTEXTEXTRACTIONWITHOUTMODEL Verify error handling

            % Don't set a current model
            context = testCase.Bridge.extractModelContext();

            testCase.verifyTrue(isstruct(context));
            testCase.verifyTrue(isfield(context, 'error'), ...
                'Should return error when no model set');
        end

        function testBuildContextWithoutModel(testCase)
            %TESTBUILDCONTEXTWITHOUTMODEL Verify string output without model

            contextStr = testCase.Bridge.buildSimulinkContext();

            testCase.verifyClass(contextStr, 'char');
            % Should still produce valid output (possibly indicating no model)
        end

        %% Nested Subsystem Tests
        function testNestedSubsystemHandling(testCase)
            %TESTNESTEDSUBSYSTEMHANDLING Verify nested subsystems

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            % Create model with nested subsystem
            new_system(testCase.TestModelName);

            % Add a subsystem
            add_block('simulink/Ports & Subsystems/Subsystem', ...
                [testCase.TestModelName, '/OuterSubsystem']);

            % Add block inside subsystem
            add_block('simulink/Sources/Constant', ...
                [testCase.TestModelName, '/OuterSubsystem/InnerConstant']);

            testCase.Bridge.setCurrentModel(testCase.TestModelName);
            context = testCase.Bridge.extractModelContext();

            testCase.verifyTrue(isstruct(context));
            testCase.verifyNotEmpty(context.blocks);

            close_system(testCase.TestModelName, 0);
        end

        %% Multiple Block Operations
        function testMultipleBlockAdditions(testCase)
            %TESTMULTIPLEBLOCKADDITIONS Verify sequential block additions

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            testCase.Bridge.setCurrentModel(testCase.TestModelName);

            % Add multiple blocks in sequence
            blockNames = {'Const1', 'Const2', 'Const3', 'Const4', 'Const5'};

            for i = 1:length(blockNames)
                success = testCase.Bridge.addBlockFromLibrary(...
                    'simulink/Sources/Constant', blockNames{i});
                testCase.verifyTrue(success, ...
                    sprintf('Should add block %s', blockNames{i}));
            end

            % Verify all blocks exist
            context = testCase.Bridge.extractModelContext();
            testCase.verifyGreaterThanOrEqual(length(context.blocks), 5);

            close_system(testCase.TestModelName, 0);
        end

        %% Delete Connected Block Tests
        function testDeleteConnectedBlock(testCase)
            %TESTDELETECONNECTEDBLOCK Verify deleting connected blocks

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);

            % Add and connect blocks
            add_block('simulink/Sources/Constant', ...
                [testCase.TestModelName, '/Source']);
            add_block('simulink/Sinks/Scope', ...
                [testCase.TestModelName, '/Sink']);

            testCase.Bridge.setCurrentModel(testCase.TestModelName);
            testCase.Bridge.connectBlocks('Source', 1, 'Sink', 1);

            % Delete the source block
            success = testCase.Bridge.deleteBlock('Source');
            testCase.verifyTrue(success, 'Should delete connected block');

            % Verify block is gone
            blocks = find_system(testCase.TestModelName, 'Name', 'Source');
            testCase.verifyEmpty(blocks, 'Source should be deleted');

            close_system(testCase.TestModelName, 0);
        end

        %% Context String Format Tests
        function testContextStringFormat(testCase)
            %TESTCONTEXTSTRINGFORMAT Verify context string structure

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', ...
                [testCase.TestModelName, '/TestBlock']);

            testCase.Bridge.setCurrentModel(testCase.TestModelName);
            contextStr = testCase.Bridge.buildSimulinkContext();

            % Verify expected sections
            testCase.verifySubstring(contextStr, '## Simulink Model');
            testCase.verifySubstring(contextStr, '### Blocks');
            testCase.verifySubstring(contextStr, 'TestBlock');

            close_system(testCase.TestModelName, 0);
        end

        %% Model List Tests
        function testGetOpenModelsWithModel(testCase)
            %TESTGETOPENMODELSWITHMODEL Verify model appears in list

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);

            models = testCase.Bridge.getOpenModels();

            testCase.verifyTrue(iscell(models));
            testCase.verifyTrue(any(strcmp(models, testCase.TestModelName)), ...
                'Test model should appear in open models list');

            close_system(testCase.TestModelName, 0);
        end

        %% Workspace and Simulink Integration
        function testWorkspaceAndSimulinkTogether(testCase)
            %TESTWORKSPACEANDSIMULINKTOGETHER Verify both contexts work

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            % Create workspace variable
            evalin('base', 'simulink_test_var = 100;');

            % Create Simulink model
            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', ...
                [testCase.TestModelName, '/Const']);

            % Get both contexts
            testCase.Bridge.setCurrentModel(testCase.TestModelName);
            simulinkContext = testCase.Bridge.buildSimulinkContext();

            provider = claudecode.WorkspaceContextProvider();
            workspaceContext = provider.getWorkspaceContext();

            % Verify both contexts are valid
            testCase.verifySubstring(simulinkContext, 'Const');
            testCase.verifySubstring(workspaceContext, 'simulink_test_var');

            % Cleanup
            evalin('base', 'clear simulink_test_var');
            close_system(testCase.TestModelName, 0);
        end

        %% Error Recovery Tests
        function testRecoveryAfterInvalidOperation(testCase)
            %TESTRECOVERYAFTERINVALIDOPERATION Verify bridge recovers

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            testCase.Bridge.setCurrentModel(testCase.TestModelName);

            % Try invalid operations
            success1 = testCase.Bridge.connectBlocks('NonExistent1', 1, 'NonExistent2', 1);
            testCase.verifyFalse(success1);

            % Bridge should still work
            success2 = testCase.Bridge.addBlockFromLibrary(...
                'simulink/Sources/Constant', 'RecoveryTest');
            testCase.verifyTrue(success2, 'Bridge should recover after error');

            close_system(testCase.TestModelName, 0);
        end
    end
end
