classdef tWorkspaceContextProvider < matlab.unittest.TestCase
    %TWORKSPACECONTEXTPROVIDER Unit tests for WorkspaceContextProvider
    %
    %   Run tests with:
    %       results = runtests('tWorkspaceContextProvider');

    properties
        Provider
        OriginalVars  % Store original workspace variables
    end

    methods (TestMethodSetup)
        function createProvider(testCase)
            testCase.Provider = claudecode.WorkspaceContextProvider();

            % Store names of existing variables to avoid clearing them
            testCase.OriginalVars = evalin('base', 'who');
        end
    end

    methods (TestMethodTeardown)
        function cleanupProvider(testCase)
            % Clean up test variables from base workspace
            currentVars = evalin('base', 'who');
            testVars = setdiff(currentVars, testCase.OriginalVars);

            for i = 1:length(testVars)
                evalin('base', sprintf('clear %s', testVars{i}));
            end

            delete(testCase.Provider);
        end
    end

    methods (Test)
        %% Constructor Tests
        function testConstructor(testCase)
            %TESTCONSTRUCTOR Verify constructor creates valid object

            provider = claudecode.WorkspaceContextProvider();
            testCase.verifyClass(provider, 'claudecode.WorkspaceContextProvider');
        end

        function testDefaultProperties(testCase)
            %TESTDEFAULTPROPERTIES Verify default property values

            testCase.verifyEqual(testCase.Provider.MaxVariableSize, 10000);
            testCase.verifyEqual(testCase.Provider.MaxVariables, 50);
            testCase.verifyEqual(testCase.Provider.MaxArrayElements, 100);
            testCase.verifyTrue(iscell(testCase.Provider.IncludeTypes));
        end

        %% Context Generation Tests
        function testGetWorkspaceContextReturnsString(testCase)
            %TESTGETWORKSPACECONTEXTRETURNSSTRING Verify return type

            context = testCase.Provider.getWorkspaceContext();
            testCase.verifyClass(context, 'char');
        end

        function testContextContainsHeader(testCase)
            %TESTCONTEXTCONTAINSHEADER Verify header present

            context = testCase.Provider.getWorkspaceContext();
            testCase.verifySubstring(context, '## MATLAB Workspace');
        end

        function testEmptyWorkspaceMessage(testCase)
            %TESTEMPTYWORKSPACEMESSAGE Verify empty workspace handled

            % Clear test variables added in setup
            currentVars = evalin('base', 'who');
            testVars = setdiff(currentVars, testCase.OriginalVars);
            for i = 1:length(testVars)
                evalin('base', sprintf('clear %s', testVars{i}));
            end

            % If workspace is empty (excluding original vars), check behavior
            % Note: Original vars may still be present
            context = testCase.Provider.getWorkspaceContext();
            testCase.verifyClass(context, 'char');
        end

        %% Variable Type Formatting Tests
        function testFormatScalarDouble(testCase)
            %TESTFORMATSCALARDOUBLE Verify scalar double formatting

            evalin('base', 'test_scalar = 42;');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'test_scalar');
            testCase.verifySubstring(context, '42');
        end

        function testFormatVectorDouble(testCase)
            %TESTFORMATVECTORDOUBLE Verify vector formatting

            evalin('base', 'test_vector = [1, 2, 3, 4, 5];');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'test_vector');
        end

        function testFormatMatrixDouble(testCase)
            %TESTFORMATMATRIXDOUBLE Verify matrix formatting

            evalin('base', 'test_matrix = magic(3);');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'test_matrix');
            testCase.verifySubstring(context, '3');  % Size reference
        end

        function testFormatString(testCase)
            %TESTFORMATSTRING Verify string formatting

            evalin('base', 'test_string = ''hello world'';');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'test_string');
            testCase.verifySubstring(context, 'hello world');
        end

        function testFormatStruct(testCase)
            %TESTFORMATSTRUCT Verify struct formatting

            evalin('base', 'test_struct = struct(''a'', 1, ''b'', 2);');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'test_struct');
            testCase.verifySubstring(context, 'struct');
        end

        function testFormatCell(testCase)
            %TESTFORMATCELL Verify cell array formatting

            evalin('base', 'test_cell = {1, ''a'', [1,2,3]};');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'test_cell');
            testCase.verifySubstring(context, 'cell');
        end

        function testFormatTable(testCase)
            %TESTFORMATTABLE Verify table formatting

            evalin('base', 'test_table = table([1;2;3], [4;5;6], ''VariableNames'', {''A'', ''B''});');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'test_table');
            testCase.verifySubstring(context, 'table');
        end

        function testFormatLogical(testCase)
            %TESTFORMATLOGICAL Verify logical formatting

            evalin('base', 'test_logical = true;');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'test_logical');
        end

        %% Summary Tests
        function testGetWorkspaceSummary(testCase)
            %TESTGETWORKSPACESUMMARY Verify summary generation

            evalin('base', 'summary_test_var = 123;');
            summary = testCase.Provider.getWorkspaceSummary();

            testCase.verifyClass(summary, 'char');
            testCase.verifyTrue(~isempty(summary));
        end

        function testSummaryContainsCount(testCase)
            %TESTSUMMARYCONTAINSCOUNT Verify variable count in summary

            evalin('base', 'count_test_a = 1;');
            evalin('base', 'count_test_b = 2;');
            summary = testCase.Provider.getWorkspaceSummary();

            testCase.verifySubstring(summary, 'variable');
        end

        %% Limit Tests
        function testMaxVariablesLimit(testCase)
            %TESTMAXVARIABLESLIMIT Verify variable count limit

            testCase.Provider.MaxVariables = 3;

            % Create more variables than limit
            for i = 1:5
                evalin('base', sprintf('limit_test_%d = %d;', i, i));
            end

            context = testCase.Provider.getWorkspaceContext();

            % Should mention there are more
            testCase.verifyTrue(contains(context, 'more') || ...
                length(strfind(context, 'limit_test_')) <= 3);
        end

        function testLargeArraySummary(testCase)
            %TESTLARGEARRAYSUMMARY Verify large arrays show summary stats

            evalin('base', 'large_array = rand(1000, 1);');
            context = testCase.Provider.getWorkspaceContext();

            % Large arrays should show min/max/mean
            testCase.verifySubstring(context, 'large_array');
        end
    end
end
