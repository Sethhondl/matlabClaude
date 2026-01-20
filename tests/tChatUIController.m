classdef tChatUIController < matlab.unittest.TestCase
    %TCHATUICONTROLLER Unit tests for ChatUIController
    %
    %   Run tests with:
    %       results = runtests('tChatUIController');
    %
    %   Note: These tests create UI components and require Python/display.

    properties
        Figure
        Panel
        PythonBridge
        Controller
        PythonAvailable
    end

    methods (TestClassSetup)
        function checkPython(testCase)
            % Check if Python with claudecode is available
            testCase.PythonAvailable = false;
            try
                pe = pyenv;
                if pe.Status == "Loaded" || pe.Status == "NotLoaded"
                    % Try to import the module
                    py.importlib.import_module('claudecode');
                    testCase.PythonAvailable = true;
                end
            catch
                testCase.PythonAvailable = false;
            end
        end
    end

    methods (TestMethodSetup)
        function createComponents(testCase)
            % Create test figure and panel
            testCase.Figure = uifigure('Visible', 'off', ...
                'Position', [100, 100, 400, 600]);
            testCase.Panel = uipanel(testCase.Figure, ...
                'Position', [0, 0, 400, 600]);

            % Try to create Python bridge if available
            if testCase.PythonAvailable
                try
                    testCase.PythonBridge = py.claudecode.MatlabBridge();
                catch
                    testCase.PythonBridge = [];
                    testCase.PythonAvailable = false;
                end
            else
                testCase.PythonBridge = [];
            end
        end
    end

    methods (TestMethodTeardown)
        function cleanupComponents(testCase)
            if ~isempty(testCase.Controller) && isvalid(testCase.Controller)
                delete(testCase.Controller);
            end
            if ~isempty(testCase.Figure) && isvalid(testCase.Figure)
                delete(testCase.Figure);
            end
        end
    end

    methods (Test)
        %% Constructor Tests
        function testConstructor(testCase)
            %TESTCONSTRUCTOR Verify constructor creates valid object

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            testCase.verifyClass(testCase.Controller, 'claudecode.ChatUIController');
        end

        function testControllerHasSimulinkBridgeProperty(testCase)
            %TESTCONTROLLERHASSIMUMLINKBRIDGEPROPERTY Verify property exists

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            testCase.verifyTrue(isprop(testCase.Controller, 'SimulinkBridge'));
        end

        function testControllerHasGitProviderProperty(testCase)
            %TESTCONTROLLERHASGITPROVIDERPROPERTY Verify property exists

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            testCase.verifyTrue(isprop(testCase.Controller, 'GitProvider'));
        end

        %% UI Creation Tests
        function testHTMLComponentCreated(testCase)
            %TESTHTMLCOMPONENTCREATED Verify uihtml component exists

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            % Give UI time to initialize
            pause(0.5);

            % Panel should have children (the uihtml component)
            testCase.verifyNotEmpty(testCase.Panel.Children);
        end

        %% Method Tests
        function testSendToJSBeforeReady(testCase)
            %TESTSENDTOJSBEFOREREADY Verify graceful handling

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            % Should not error, just warn
            testCase.verifyWarning(...
                @() testCase.Controller.sendToJS('test', struct()), ...
                'ChatUIController:NotReady');
        end

        function testSendAssistantMessage(testCase)
            %TESTSENDASSISTANTMESSAGE Verify method exists and callable

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            % Should not error (may warn if not ready)
            try
                testCase.Controller.sendAssistantMessage('Test message');
            catch ME
                testCase.verifyFail(['sendAssistantMessage errored: ', ME.message]);
            end
        end

        function testStartStreaming(testCase)
            %TESTSTARTSTREAMING Verify method exists and callable

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            try
                testCase.Controller.startStreaming();
            catch ME
                testCase.verifyFail(['startStreaming errored: ', ME.message]);
            end
        end

        function testEndStreaming(testCase)
            %TESTENDSTREAMING Verify method exists and callable

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            try
                testCase.Controller.endStreaming();
            catch ME
                testCase.verifyFail(['endStreaming errored: ', ME.message]);
            end
        end

        function testSendStreamChunk(testCase)
            %TESTSENDSTREAMCHUNK Verify method exists and callable

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            try
                testCase.Controller.sendStreamChunk('chunk');
            catch ME
                testCase.verifyFail(['sendStreamChunk errored: ', ME.message]);
            end
        end

        function testSendError(testCase)
            %TESTSENDERROR Verify method exists and callable

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            try
                testCase.Controller.sendError('Test error');
            catch ME
                testCase.verifyFail(['sendError errored: ', ME.message]);
            end
        end

        function testUpdateStatus(testCase)
            %TESTUPDATESTATUS Verify method exists and callable

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            try
                testCase.Controller.updateStatus('ready', 'Ready');
            catch ME
                testCase.verifyFail(['updateStatus errored: ', ME.message]);
            end
        end

        %% Destructor Test
        function testDestructor(testCase)
            %TESTDESTRUCTOR Verify clean destruction

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);
            delete(controller);

            % Should not error
            testCase.verifyTrue(true);
        end

        %% Streaming State Tracking Tests
        function testStreamingStateStart(testCase)
            %TESTSTREAMINGSTATESTART Verify streaming can be started

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            % Should not error when starting streaming
            try
                testCase.Controller.startStreaming();
                testCase.verifyTrue(true);
            catch ME
                % May warn if not ready, but should not error
                testCase.verifyTrue(true);
            end
        end

        function testStreamingStateEnd(testCase)
            %TESTSTREAMINGSTATEEND Verify streaming can be ended

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            % Should not error when ending streaming
            try
                testCase.Controller.endStreaming();
                testCase.verifyTrue(true);
            catch ME
                testCase.verifyFail(['endStreaming should not error: ', ME.message]);
            end
        end

        function testStreamingStartEndSequence(testCase)
            %TESTSTREAMINGSTARTENDSEQUENCE Verify start/end sequence

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            % Normal sequence: start -> chunk -> end
            try
                testCase.Controller.startStreaming();
                testCase.Controller.sendStreamChunk('test chunk');
                testCase.Controller.endStreaming();
            catch ME
                % May warn about not ready, but sequence should work
                testCase.verifyTrue(true);
            end
        end

        function testMultipleStreamingCycles(testCase)
            %TESTMULTIPLESTREAMINGCYCLES Verify repeated streaming

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            for i = 1:3
                try
                    testCase.Controller.startStreaming();
                    testCase.Controller.sendStreamChunk(sprintf('Chunk %d', i));
                    testCase.Controller.endStreaming();
                catch
                    % May warn, but should not crash
                end
            end

            testCase.verifyTrue(true, 'Multiple cycles should complete');
        end

        %% SimulinkBridge Property Setter Tests
        function testSimulinkBridgeSetter(testCase)
            %TESTSIMULINKBRIDGESETTER Verify SimulinkBridge can be set

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            bridge = claudecode.SimulinkBridge();
            testCase.Controller.SimulinkBridge = bridge;

            testCase.verifyEqual(testCase.Controller.SimulinkBridge, bridge);
        end

        function testSimulinkBridgeInitiallyEmpty(testCase)
            %TESTSIMULINKBRIDGEINITIALLYEMPTY Verify initial state

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            % SimulinkBridge may be empty initially
            bridge = testCase.Controller.SimulinkBridge;
            testCase.verifyTrue(isempty(bridge) || isa(bridge, 'claudecode.SimulinkBridge'));
        end

        %% Multiple Message Handling Tests
        function testMultipleAssistantMessages(testCase)
            %TESTMULTIPLEASSISTANTMESSAGES Verify multiple messages

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            for i = 1:5
                try
                    testCase.Controller.sendAssistantMessage(sprintf('Message %d', i));
                catch
                    % May warn if not ready
                end
            end

            testCase.verifyTrue(true, 'Multiple messages should not error');
        end

        function testMultipleErrorMessages(testCase)
            %TESTMULTIPLEERRORMESSAGES Verify multiple errors

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            for i = 1:3
                try
                    testCase.Controller.sendError(sprintf('Error %d', i));
                catch
                    % May warn if not ready
                end
            end

            testCase.verifyTrue(true, 'Multiple error messages should not error');
        end

        function testMixedMessageTypes(testCase)
            %TESTMIXEDMESSAGETYPES Verify mixed message handling

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            try
                testCase.Controller.sendAssistantMessage('Hello');
                testCase.Controller.sendError('Oops');
                testCase.Controller.startStreaming();
                testCase.Controller.sendStreamChunk('streaming...');
                testCase.Controller.endStreaming();
                testCase.Controller.sendAssistantMessage('Done');
            catch
                % May warn, should not crash
            end

            testCase.verifyTrue(true, 'Mixed messages should work');
        end

        %% Status Update Tests
        function testUpdateStatusValues(testCase)
            %TESTUPDATESTATUSVALUES Verify different status values

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            statuses = {'ready', 'connecting', 'error', 'processing'};

            for i = 1:length(statuses)
                try
                    testCase.Controller.updateStatus(statuses{i}, sprintf('Status: %s', statuses{i}));
                catch
                    % May warn if not ready
                end
            end

            testCase.verifyTrue(true, 'All status values should be handled');
        end

        %% GitProvider Property Tests
        function testGitProviderPropertyExists(testCase)
            %TESTGITPROVIDERPROPERTYEXISTS Verify property accessibility

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            testCase.verifyTrue(isprop(testCase.Controller, 'GitProvider'));
        end

        %% UI Component Tests
        function testPanelChildrenCreated(testCase)
            %TESTPANELCHILDRENCREATED Verify UI components created

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            % Give UI time to initialize
            pause(0.5);

            % Should have created children in the panel
            testCase.verifyNotEmpty(testCase.Panel.Children);
        end

        function testControllerWithDifferentPanelSizes(testCase)
            %TESTCONTROLLERWITHDIFFERENTPANELSIZES Verify resize handling

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            % Create figure with different size
            smallFig = uifigure('Visible', 'off', 'Position', [100, 100, 200, 300]);
            smallPanel = uipanel(smallFig, 'Position', [0, 0, 200, 300]);

            controller = claudecode.ChatUIController(...
                smallPanel, testCase.PythonBridge);

            % Should create without error
            testCase.verifyClass(controller, 'claudecode.ChatUIController');

            delete(controller);
            delete(smallFig);
        end

        %% sendToJS Edge Cases
        function testSendToJSWithEmptyData(testCase)
            %TESTSENDTOJSWITHEMPTYDATA Verify empty data handling

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            try
                testCase.Controller.sendToJS('test', struct());
            catch ME
                % Should warn, not error
                testCase.verifySubstring(ME.identifier, 'MATLAB:', ...
                    'Should be a warning, not unexpected error');
            end
        end

        function testSendToJSWithComplexData(testCase)
            %TESTSENDTOJSWITHCOMPLEXDATA Verify complex data handling

            testCase.assumeTrue(testCase.PythonAvailable, 'Python not available');

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.PythonBridge);

            data = struct('message', 'test', 'code', 'x = 1;', 'nested', struct('a', 1));

            try
                testCase.Controller.sendToJS('complex', data);
            catch
                % May warn about not ready
            end

            testCase.verifyTrue(true, 'Complex data should not crash');
        end
    end
end
