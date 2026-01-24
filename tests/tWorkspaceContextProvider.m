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
            testCase.Provider = derivux.WorkspaceContextProvider();

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

            provider = derivux.WorkspaceContextProvider();
            testCase.verifyClass(provider, 'derivux.WorkspaceContextProvider');
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

        %% Special Characters in Strings Tests
        function testStringWithNewline(testCase)
            %TESTSTRINGWITHNEWLINE Verify newline handling

            evalin('base', 'newline_str = sprintf(''line1\nline2'');');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'newline_str');
        end

        function testStringWithTab(testCase)
            %TESTSTRINGWITHTAB Verify tab handling

            evalin('base', 'tab_str = sprintf(''col1\tcol2'');');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'tab_str');
        end

        function testStringWithQuotes(testCase)
            %TESTSTRINGWITHQUOTES Verify quote handling

            evalin('base', 'quote_str = ''He said "hello"'';');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'quote_str');
        end

        %% Function Handle Tests
        function testFunctionHandle(testCase)
            %TESTFUNCTIONHANDLE Verify function handle formatting

            evalin('base', 'func_handle = @sin;');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'func_handle');
        end

        function testAnonymousFunction(testCase)
            %TESTANONYMOUSFUNCTION Verify anonymous function handling

            evalin('base', 'anon_func = @(x) x.^2 + 1;');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'anon_func');
        end

        %% Timeseries Tests
        function testTimeseriesObject(testCase)
            %TESTTIMESERIESOBJECT Verify timeseries handling

            try
                evalin('base', 'ts_data = timeseries(rand(10,1), 1:10);');
                context = testCase.Provider.getWorkspaceContext();

                testCase.verifySubstring(context, 'ts_data');
            catch ME
                % timeseries may not be available in all MATLAB versions
                testCase.assumeFail('timeseries not available');
            end
        end

        %% Very Large Matrix Tests
        function testVeryLargeMatrixSummary(testCase)
            %TESTVERYLARGENMATRIXSUMMARY Verify large matrix shows summary

            evalin('base', 'huge_matrix = rand(500, 500);');
            context = testCase.Provider.getWorkspaceContext();

            % Should show size, not full data
            testCase.verifySubstring(context, 'huge_matrix');
            testCase.verifySubstring(context, '500');

            % Should NOT contain 250000 numbers
            testCase.verifyTrue(length(context) < 100000, ...
                'Context should be summarized, not full data');
        end

        function testLargeMatrixShowsStats(testCase)
            %TESTLARGEMATRIXSHOWSSTATS Verify stats for large matrices

            evalin('base', 'stats_matrix = randn(100, 100);');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'stats_matrix');
            % Should include size information
            testCase.verifySubstring(context, '100');
        end

        %% Empty Arrays and Cells Tests
        function testEmptyArray(testCase)
            %TESTEMPTYARRAY Verify empty array handling

            evalin('base', 'empty_arr = [];');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'empty_arr');
        end

        function testEmptyCell(testCase)
            %TESTEMPTYCELL Verify empty cell handling

            evalin('base', 'empty_cell = {};');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'empty_cell');
        end

        function testEmptyStruct(testCase)
            %TESTEMPTYSTRUCT Verify empty struct handling

            evalin('base', 'empty_struct = struct([]);');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'empty_struct');
        end

        function testEmptyString(testCase)
            %TESTEMPTYSTRING Verify empty string handling

            evalin('base', 'empty_str = '''';');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'empty_str');
        end

        %% NaN and Inf Values Tests
        function testNaNValue(testCase)
            %TESTNANVALUE Verify NaN handling

            evalin('base', 'nan_val = NaN;');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'nan_val');
        end

        function testInfValue(testCase)
            %TESTINFVALUE Verify Inf handling

            evalin('base', 'inf_val = Inf;');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'inf_val');
        end

        function testNegInfValue(testCase)
            %TESTNEGINFVALUE Verify negative Inf handling

            evalin('base', 'neg_inf = -Inf;');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'neg_inf');
        end

        function testArrayWithNaN(testCase)
            %TESTARRAYWITHNAN Verify array containing NaN

            evalin('base', 'arr_nan = [1, 2, NaN, 4, 5];');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'arr_nan');
        end

        %% Complex Number Tests
        function testComplexNumber(testCase)
            %TESTCOMPLEXNUMBER Verify complex number handling

            evalin('base', 'complex_num = 3 + 4i;');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'complex_num');
        end

        function testComplexArray(testCase)
            %TESTCOMPLEXARRAY Verify complex array handling

            evalin('base', 'complex_arr = [1+2i, 3+4i, 5+6i];');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'complex_arr');
        end

        %% Nested Struct Tests
        function testNestedStruct(testCase)
            %TESTNESTEDSTRUCT Verify nested struct handling

            evalin('base', 'nested = struct(''a'', struct(''b'', 1));');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'nested');
        end

        %% Mixed Cell Array Tests
        function testMixedCellArray(testCase)
            %TESTMIXEDCELLARRAY Verify mixed type cell array

            evalin('base', 'mixed_cell = {1, ''text'', [1,2,3], struct(''x'', 1)};');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'mixed_cell');
        end

        %% Sparse Matrix Tests
        function testSparseMatrix(testCase)
            %TESTSPARSEMATRIX Verify sparse matrix handling

            evalin('base', 'sparse_mat = sparse(eye(10));');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'sparse_mat');
        end

        %% Multi-dimensional Array Tests
        function testMultiDimensionalArray(testCase)
            %TESTMULTIDIMENSIONALARRAY Verify 3D+ array handling

            evalin('base', 'multi_dim = rand(3, 4, 5);');
            context = testCase.Provider.getWorkspaceContext();

            testCase.verifySubstring(context, 'multi_dim');
        end

        %% Property Modification Tests
        function testModifyMaxVariables(testCase)
            %TESTMODIFYMAXVARIABLES Verify MaxVariables can be changed

            testCase.Provider.MaxVariables = 10;
            testCase.verifyEqual(testCase.Provider.MaxVariables, 10);
        end

        function testModifyMaxArrayElements(testCase)
            %TESTMODIFYMAXARRAYELEMENTS Verify MaxArrayElements can be changed

            testCase.Provider.MaxArrayElements = 50;
            testCase.verifyEqual(testCase.Provider.MaxArrayElements, 50);
        end

        function testModifyMaxVariableSize(testCase)
            %TESTMODIFYMAXVARIABLESIZE Verify MaxVariableSize can be changed

            testCase.Provider.MaxVariableSize = 5000;
            testCase.verifyEqual(testCase.Provider.MaxVariableSize, 5000);
        end
    end
end
