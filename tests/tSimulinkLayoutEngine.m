classdef tSimulinkLayoutEngine < matlab.unittest.TestCase
    %TSIMULINKLAYOUTENGINE Unit tests for SimulinkLayoutEngine
    %
    %   Run tests with:
    %       results = runtests('tSimulinkLayoutEngine');
    %
    %   Note: Most tests require Simulink to be installed.

    properties
        Engine
        TestModelName = 'test_layout_model_temp'
        SimulinkAvailable
    end

    methods (TestClassSetup)
        function checkSimulink(testCase)
            % Check if Simulink is available
            testCase.SimulinkAvailable = license('test', 'Simulink');
        end
    end

    methods (TestMethodSetup)
        function setupTest(testCase)
            % Create fresh engine for each test
            if testCase.SimulinkAvailable
                testCase.Engine = claudecode.SimulinkLayoutEngine(testCase.TestModelName);
            end
        end
    end

    methods (TestMethodTeardown)
        function cleanupTest(testCase)
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
        end
    end

    methods (Test)
        %% Constructor Tests

        function testConstructor(testCase)
            %TESTCONSTRUCTOR Verify constructor creates valid object

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            engine = claudecode.SimulinkLayoutEngine('testModel');
            testCase.verifyClass(engine, 'claudecode.SimulinkLayoutEngine');
        end

        function testConstructorSetsModelName(testCase)
            %TESTCONSTRUCTORSETSMODELNAME Verify model name is stored

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            engine = claudecode.SimulinkLayoutEngine('myTestModel');
            testCase.verifyEqual(engine.ModelName, 'myTestModel');
        end

        function testInitialStateEmpty(testCase)
            %TESTINITIALSTATEEMPTY Verify initial state has empty collections

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            engine = claudecode.SimulinkLayoutEngine('testModel');
            testCase.verifyEmpty(engine.Blocks);
            testCase.verifyEmpty(engine.Edges);
            testCase.verifyEmpty(engine.Layers);
        end

        %% Graph Extraction Tests

        function testExtractGraphSimpleModel(testCase)
            %TESTEXTRACTGRAPHSIMPLEMODEL Test extraction from simple model

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            % Create simple model
            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', ...
                [testCase.TestModelName, '/Source']);
            add_block('simulink/Sinks/Scope', ...
                [testCase.TestModelName, '/Sink']);
            add_line(testCase.TestModelName, 'Source/1', 'Sink/1');

            testCase.Engine.extractGraph();

            testCase.verifyLength(testCase.Engine.Blocks, 2);
            testCase.verifyLength(testCase.Engine.Edges, 1);
        end

        function testExtractGraphMultipleBlocks(testCase)
            %TESTEXTRACTGRAPHMULTIPLEBLOCKS Test extraction with multiple blocks

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Const1']);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Const2']);
            add_block('simulink/Math Operations/Sum', [testCase.TestModelName, '/Sum']);
            add_block('simulink/Sinks/Scope', [testCase.TestModelName, '/Scope']);

            % Set Sum block to have 2 inputs
            set_param([testCase.TestModelName, '/Sum'], 'Inputs', '++');

            add_line(testCase.TestModelName, 'Const1/1', 'Sum/1');
            add_line(testCase.TestModelName, 'Const2/1', 'Sum/2');
            add_line(testCase.TestModelName, 'Sum/1', 'Scope/1');

            testCase.Engine.extractGraph();

            testCase.verifyLength(testCase.Engine.Blocks, 4);
            testCase.verifyLength(testCase.Engine.Edges, 3);
        end

        function testExtractGraphNoConnections(testCase)
            %TESTEXTRACTGRAPHNOCONNECTIONS Test extraction with disconnected blocks

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Block1']);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Block2']);

            testCase.Engine.extractGraph();

            testCase.verifyLength(testCase.Engine.Blocks, 2);
            testCase.verifyEmpty(testCase.Engine.Edges);
        end

        %% Layer Assignment Tests

        function testAssignLayersLinearChain(testCase)
            %TESTASSIGNLAYERSLINEARCHAIN Test layer assignment for linear signal flow

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            % Create linear chain: Source -> Gain -> Scope
            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Source']);
            add_block('simulink/Math Operations/Gain', [testCase.TestModelName, '/Gain']);
            add_block('simulink/Sinks/Scope', [testCase.TestModelName, '/Sink']);

            add_line(testCase.TestModelName, 'Source/1', 'Gain/1');
            add_line(testCase.TestModelName, 'Gain/1', 'Sink/1');

            testCase.Engine.extractGraph();
            testCase.Engine.assignLayers();

            % Should have 3 layers
            testCase.verifyLength(testCase.Engine.Layers, 3);

            % Each layer should have 1 block
            testCase.verifyLength(testCase.Engine.Layers{1}, 1);
            testCase.verifyLength(testCase.Engine.Layers{2}, 1);
            testCase.verifyLength(testCase.Engine.Layers{3}, 1);
        end

        function testAssignLayersParallelPaths(testCase)
            %TESTASSIGNLAYERSPARALLELPATHS Test with parallel signal paths

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            % Create: Source -> Gain1 -> Sum -> Scope
            %         Source -> Gain2 -> Sum
            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Source']);
            add_block('simulink/Math Operations/Gain', [testCase.TestModelName, '/Gain1']);
            add_block('simulink/Math Operations/Gain', [testCase.TestModelName, '/Gain2']);
            add_block('simulink/Math Operations/Sum', [testCase.TestModelName, '/Sum']);
            add_block('simulink/Sinks/Scope', [testCase.TestModelName, '/Sink']);

            set_param([testCase.TestModelName, '/Sum'], 'Inputs', '++');

            add_line(testCase.TestModelName, 'Source/1', 'Gain1/1');
            add_line(testCase.TestModelName, 'Source/1', 'Gain2/1');
            add_line(testCase.TestModelName, 'Gain1/1', 'Sum/1');
            add_line(testCase.TestModelName, 'Gain2/1', 'Sum/2');
            add_line(testCase.TestModelName, 'Sum/1', 'Sink/1');

            testCase.Engine.extractGraph();
            testCase.Engine.assignLayers();

            % Should have 4 layers: Source, Gains, Sum, Sink
            testCase.verifyLength(testCase.Engine.Layers, 4);

            % Second layer should have 2 blocks (Gain1, Gain2)
            testCase.verifyLength(testCase.Engine.Layers{2}, 2);
        end

        function testAssignLayersDisconnectedBlocks(testCase)
            %TESTASSIGNLAYERSDISCONNECTEDBLOCKS Handle disconnected blocks

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Block1']);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Block2']);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Block3']);

            testCase.Engine.extractGraph();
            testCase.Engine.assignLayers();

            % All disconnected blocks should be in layer 0
            testCase.verifyLength(testCase.Engine.Layers{1}, 3);
        end

        %% Crossing Minimization Tests

        function testMinimizeCrossingsReducesCrossings(testCase)
            %TESTMINIMIZECROSSINGSREDUCESCROSSINGS Verify crossings decrease or stay same

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            % Create model with potential crossings
            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Src1']);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Src2']);
            add_block('simulink/Sinks/Scope', [testCase.TestModelName, '/Sink1']);
            add_block('simulink/Sinks/Scope', [testCase.TestModelName, '/Sink2']);

            % Create crossing pattern: Src1 -> Sink2, Src2 -> Sink1
            add_line(testCase.TestModelName, 'Src1/1', 'Sink2/1');
            add_line(testCase.TestModelName, 'Src2/1', 'Sink1/1');

            testCase.Engine.extractGraph();
            testCase.Engine.assignLayers();

            initialCrossings = testCase.Engine.countCrossings();
            testCase.Engine.minimizeCrossings();
            finalCrossings = testCase.Engine.countCrossings();

            testCase.verifyLessThanOrEqual(finalCrossings, initialCrossings);
        end

        function testCountCrossingsZeroForAligned(testCase)
            %TESTCOUNTCROSSINGSZEROFORALIGNED Zero crossings for aligned connections

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Src1']);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Src2']);
            add_block('simulink/Sinks/Scope', [testCase.TestModelName, '/Sink1']);
            add_block('simulink/Sinks/Scope', [testCase.TestModelName, '/Sink2']);

            % Parallel connections (no crossings)
            add_line(testCase.TestModelName, 'Src1/1', 'Sink1/1');
            add_line(testCase.TestModelName, 'Src2/1', 'Sink2/1');

            testCase.Engine.extractGraph();
            testCase.Engine.assignLayers();

            crossings = testCase.Engine.countCrossings();
            testCase.verifyEqual(crossings, 0);
        end

        %% Coordinate Assignment Tests

        function testAssignCoordinatesPopulatesPositions(testCase)
            %TESTASSIGNCOORDINATESPOPULATESPOSITIONS Verify positions are assigned

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Source']);
            add_block('simulink/Sinks/Scope', [testCase.TestModelName, '/Sink']);
            add_line(testCase.TestModelName, 'Source/1', 'Sink/1');

            testCase.Engine.extractGraph();
            testCase.Engine.assignLayers();
            testCase.Engine.assignCoordinates();

            % Both blocks should have positions
            testCase.verifyTrue(isKey(testCase.Engine.BlockPositions, 'Source'));
            testCase.verifyTrue(isKey(testCase.Engine.BlockPositions, 'Sink'));
        end

        function testAssignCoordinatesLeftToRight(testCase)
            %TESTASSIGNCOORDINATESLEFTTORIGHT Verify left-to-right signal flow

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Source']);
            add_block('simulink/Sinks/Scope', [testCase.TestModelName, '/Sink']);
            add_line(testCase.TestModelName, 'Source/1', 'Sink/1');

            testCase.Engine.extractGraph();
            testCase.Engine.assignLayers();
            testCase.Engine.assignCoordinates();

            srcPos = testCase.Engine.BlockPositions('Source');
            sinkPos = testCase.Engine.BlockPositions('Sink');

            % Source should be to the left of Sink
            testCase.verifyLessThan(srcPos(1), sinkPos(1));
        end

        function testAssignCoordinatesCustomSpacing(testCase)
            %TESTASSIGNCOORDINATESCUSTOMSPACING Verify custom spacing is applied

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Block1']);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Block2']);

            testCase.Engine.extractGraph();
            testCase.Engine.assignLayers();

            % Use large spacing
            testCase.Engine.assignCoordinates(100);

            pos1 = testCase.Engine.BlockPositions('Block1');
            pos2 = testCase.Engine.BlockPositions('Block2');

            % Vertical spacing should be at least 100
            verticalGap = abs(pos2(2) - (pos1(2) + pos1(4)));
            testCase.verifyGreaterThanOrEqual(verticalGap, 100);
        end

        %% Wire Routing Tests

        function testRouteWiresCreatesRoutes(testCase)
            %TESTROUTEWIRESCREATESROUTES Verify wire routes are created

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Source']);
            add_block('simulink/Sinks/Scope', [testCase.TestModelName, '/Sink']);
            add_line(testCase.TestModelName, 'Source/1', 'Sink/1');

            testCase.Engine.extractGraph();
            testCase.Engine.assignLayers();
            testCase.Engine.assignCoordinates();
            testCase.Engine.routeWires();

            % Should have one wire route
            testCase.verifyTrue(isKey(testCase.Engine.WireRoutes, 1));

            % Route should have at least 2 waypoints
            route = testCase.Engine.WireRoutes(1);
            testCase.verifyGreaterThanOrEqual(size(route, 1), 2);
        end

        function testRouteWiresOrthogonal(testCase)
            %TESTROUTEWIRESORTHOGONAL Verify routes are orthogonal (90-degree angles)

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Source']);
            add_block('simulink/Sinks/Scope', [testCase.TestModelName, '/Sink']);
            add_line(testCase.TestModelName, 'Source/1', 'Sink/1');

            testCase.Engine.extractGraph();
            testCase.Engine.assignLayers();
            testCase.Engine.assignCoordinates();
            testCase.Engine.routeWires();

            route = testCase.Engine.WireRoutes(1);

            % Check each segment is horizontal or vertical
            for i = 1:(size(route, 1) - 1)
                dx = route(i+1, 1) - route(i, 1);
                dy = route(i+1, 2) - route(i, 2);

                % Either dx or dy should be ~0 (orthogonal)
                isOrthogonal = (abs(dx) < 1) || (abs(dy) < 1);
                testCase.verifyTrue(isOrthogonal, ...
                    sprintf('Segment %d is not orthogonal: dx=%f, dy=%f', i, dx, dy));
            end
        end

        %% Apply Layout Tests

        function testApplyLayoutSuccess(testCase)
            %TESTAPPLAYLAYOUTSUCCESS Verify layout is applied to model

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Source']);
            add_block('simulink/Sinks/Scope', [testCase.TestModelName, '/Sink']);
            add_line(testCase.TestModelName, 'Source/1', 'Sink/1');

            testCase.Engine.extractGraph();
            testCase.Engine.assignLayers();
            testCase.Engine.assignCoordinates();
            testCase.Engine.routeWires();
            success = testCase.Engine.applyLayout();

            testCase.verifyTrue(success);

            % Verify block positions were updated
            srcPos = get_param([testCase.TestModelName, '/Source'], 'Position');
            sinkPos = get_param([testCase.TestModelName, '/Sink'], 'Position');

            % Source should be to the left of Sink
            testCase.verifyLessThan(srcPos(3), sinkPos(1));
        end

        function testApplyLayoutPreservesConnections(testCase)
            %TESTAPPLAYLAYOUTPRESERVESCONNECTIONS Verify connections are maintained

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Source']);
            add_block('simulink/Sinks/Scope', [testCase.TestModelName, '/Sink']);
            add_line(testCase.TestModelName, 'Source/1', 'Sink/1');

            testCase.Engine.extractGraph();
            testCase.Engine.assignLayers();
            testCase.Engine.assignCoordinates();
            testCase.Engine.routeWires();
            testCase.Engine.applyLayout();

            % Verify connection still exists
            lines = find_system(testCase.TestModelName, 'FindAll', 'on', 'Type', 'line');
            testCase.verifyNotEmpty(lines);
        end

        %% Full Pipeline (optimize) Tests

        function testOptimizeSimpleModel(testCase)
            %TESTOPTIMIZESIMPLEMODEL Test full optimization pipeline

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Source']);
            add_block('simulink/Math Operations/Gain', [testCase.TestModelName, '/Gain']);
            add_block('simulink/Sinks/Scope', [testCase.TestModelName, '/Sink']);
            add_line(testCase.TestModelName, 'Source/1', 'Gain/1');
            add_line(testCase.TestModelName, 'Gain/1', 'Sink/1');

            % Run full optimization
            testCase.Engine.optimize();

            % Verify signal flow is left-to-right
            srcPos = get_param([testCase.TestModelName, '/Source'], 'Position');
            gainPos = get_param([testCase.TestModelName, '/Gain'], 'Position');
            sinkPos = get_param([testCase.TestModelName, '/Sink'], 'Position');

            testCase.verifyLessThan(srcPos(3), gainPos(1), 'Source should be left of Gain');
            testCase.verifyLessThan(gainPos(3), sinkPos(1), 'Gain should be left of Sink');
        end

        function testOptimizeWithCustomSpacing(testCase)
            %TESTOPTIMIZEWITHCUSTOMSPACING Test optimization with custom spacing

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Block1']);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Block2']);

            % Optimize with large spacing
            testCase.Engine.optimize('Spacing', 100);

            % Verify blocks exist
            testCase.verifyNotEmpty(testCase.Engine.Blocks);
        end

        function testOptimizeComplexModel(testCase)
            %TESTOPTIMIZECOMPLEXMODEL Test with more complex model

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);

            % Create a diamond pattern
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/In']);
            add_block('simulink/Math Operations/Gain', [testCase.TestModelName, '/Upper']);
            add_block('simulink/Math Operations/Gain', [testCase.TestModelName, '/Lower']);
            add_block('simulink/Math Operations/Sum', [testCase.TestModelName, '/Sum']);
            add_block('simulink/Sinks/Scope', [testCase.TestModelName, '/Out']);

            set_param([testCase.TestModelName, '/Sum'], 'Inputs', '++');

            add_line(testCase.TestModelName, 'In/1', 'Upper/1');
            add_line(testCase.TestModelName, 'In/1', 'Lower/1');
            add_line(testCase.TestModelName, 'Upper/1', 'Sum/1');
            add_line(testCase.TestModelName, 'Lower/1', 'Sum/2');
            add_line(testCase.TestModelName, 'Sum/1', 'Out/1');

            % Should not error
            testCase.Engine.optimize();

            % Verify all connections preserved
            lines = find_system(testCase.TestModelName, 'FindAll', 'on', 'Type', 'line');
            testCase.verifyGreaterThanOrEqual(length(lines), 5);
        end

        %% SimulinkBridge Integration Tests

        function testSimulinkBridgeOptimizeLayout(testCase)
            %TESTSIMUMLINKBRIDGEOPTIMIZYLAYOUT Test integration with SimulinkBridge

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            new_system(testCase.TestModelName);
            add_block('simulink/Sources/Constant', [testCase.TestModelName, '/Source']);
            add_block('simulink/Sinks/Scope', [testCase.TestModelName, '/Sink']);
            add_line(testCase.TestModelName, 'Source/1', 'Sink/1');

            bridge = claudecode.SimulinkBridge();
            bridge.setCurrentModel(testCase.TestModelName);
            result = bridge.optimizeLayout();

            testCase.verifyTrue(result.success);
            testCase.verifyGreaterThan(result.blocksProcessed, 0);
        end

        function testSimulinkBridgeOptimizeLayoutNoModel(testCase)
            %TESTSIMUMLINKBRIDGEOPTIMIZYLAYOUTNOMODEL Test error handling

            testCase.assumeTrue(testCase.SimulinkAvailable, ...
                'Simulink not available');

            bridge = claudecode.SimulinkBridge();
            result = bridge.optimizeLayout();

            testCase.verifyFalse(result.success);
            testCase.verifySubstring(result.message, 'No current model');
        end
    end
end
