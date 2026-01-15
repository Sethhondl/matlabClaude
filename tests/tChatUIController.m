classdef tChatUIController < matlab.unittest.TestCase
    %TCHATUICONTROLLER Unit tests for ChatUIController
    %
    %   Run tests with:
    %       results = runtests('tChatUIController');
    %
    %   Note: These tests create UI components and require a display.

    properties
        Figure
        Panel
        ProcessManager
        Controller
    end

    methods (TestMethodSetup)
        function createComponents(testCase)
            % Create test figure and panel
            testCase.Figure = uifigure('Visible', 'off', ...
                'Position', [100, 100, 400, 600]);
            testCase.Panel = uipanel(testCase.Figure, ...
                'Position', [0, 0, 400, 600]);
            testCase.ProcessManager = claudecode.ClaudeProcessManager();
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

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.ProcessManager);

            testCase.verifyClass(testCase.Controller, 'claudecode.ChatUIController');
        end

        function testControllerHasSimulinkBridgeProperty(testCase)
            %TESTCONTROLLERHASSIMUMLINKBRIDGEPROPERTY Verify property exists

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.ProcessManager);

            testCase.verifyTrue(isprop(testCase.Controller, 'SimulinkBridge'));
        end

        function testControllerHasGitProviderProperty(testCase)
            %TESTCONTROLLERHASGITPROVIDERPROPERTY Verify property exists

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.ProcessManager);

            testCase.verifyTrue(isprop(testCase.Controller, 'GitProvider'));
        end

        %% UI Creation Tests
        function testHTMLComponentCreated(testCase)
            %TESTHTMLCOMPONENTCREATED Verify uihtml component exists

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.ProcessManager);

            % Give UI time to initialize
            pause(0.5);

            % Panel should have children (the uihtml component)
            testCase.verifyNotEmpty(testCase.Panel.Children);
        end

        %% Method Tests
        function testSendToJSBeforeReady(testCase)
            %TESTSENDTOJSBEFOREREADY Verify graceful handling

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.ProcessManager);

            % Should not error, just warn
            testCase.verifyWarning(...
                @() testCase.Controller.sendToJS('test', struct()), ...
                'ChatUIController:NotReady');
        end

        function testSendAssistantMessage(testCase)
            %TESTSENDASSISTANTMESSAGE Verify method exists and callable

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.ProcessManager);

            % Should not error (may warn if not ready)
            try
                testCase.Controller.sendAssistantMessage('Test message');
            catch ME
                testCase.verifyFail(['sendAssistantMessage errored: ', ME.message]);
            end
        end

        function testStartStreaming(testCase)
            %TESTSTARTSTREAMING Verify method exists and callable

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.ProcessManager);

            try
                testCase.Controller.startStreaming();
            catch ME
                testCase.verifyFail(['startStreaming errored: ', ME.message]);
            end
        end

        function testEndStreaming(testCase)
            %TESTENDSTREAMING Verify method exists and callable

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.ProcessManager);

            try
                testCase.Controller.endStreaming();
            catch ME
                testCase.verifyFail(['endStreaming errored: ', ME.message]);
            end
        end

        function testSendStreamChunk(testCase)
            %TESTSENDSTREAMCHUNK Verify method exists and callable

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.ProcessManager);

            try
                testCase.Controller.sendStreamChunk('chunk');
            catch ME
                testCase.verifyFail(['sendStreamChunk errored: ', ME.message]);
            end
        end

        function testSendError(testCase)
            %TESTSENDERROR Verify method exists and callable

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.ProcessManager);

            try
                testCase.Controller.sendError('Test error');
            catch ME
                testCase.verifyFail(['sendError errored: ', ME.message]);
            end
        end

        function testUpdateStatus(testCase)
            %TESTUPDATESTATUS Verify method exists and callable

            testCase.Controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.ProcessManager);

            try
                testCase.Controller.updateStatus('ready', 'Ready');
            catch ME
                testCase.verifyFail(['updateStatus errored: ', ME.message]);
            end
        end

        %% Destructor Test
        function testDestructor(testCase)
            %TESTDESTRUCTOR Verify clean destruction

            controller = claudecode.ChatUIController(...
                testCase.Panel, testCase.ProcessManager);
            delete(controller);

            % Should not error
            testCase.verifyTrue(true);
        end
    end
end
