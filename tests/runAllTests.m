function results = runAllTests(options)
%RUNALLTESTS Run all unit tests for Claude Code MATLAB integration
%
%   results = runAllTests() runs all tests and returns results
%   results = runAllTests('Verbose', true) runs with verbose output
%   results = runAllTests('Tags', {'unit'}) runs tests with specific tags
%   results = runAllTests('Parallel', true) runs tests in parallel
%   results = runAllTests('StopOnFailure', true) stops on first failure
%   results = runAllTests('Coverage', true) generates coverage report
%   results = runAllTests('ExcludeIntegration', true) excludes integration tests
%
%   Options:
%       Verbose             - Enable verbose output (default: false)
%       GenerateReport      - Generate HTML test report (default: false)
%       ReportFolder        - Output folder for reports (default: 'test-results')
%       Tags                - Cell array of tags to filter by (default: {})
%       Parallel            - Run tests in parallel if PCT available (default: false)
%       StopOnFailure       - Stop on first failure (default: false)
%       Coverage            - Generate coverage report (default: false)
%       ExcludeIntegration  - Exclude integration tests (default: false)
%       JUnitOutput         - Generate JUnit XML output for CI (default: false)
%
%   Example:
%       results = runAllTests();
%       results = runAllTests('Verbose', true);
%       results = runAllTests('Tags', {'unit'}, 'ExcludeIntegration', true);
%       results = runAllTests('Coverage', true, 'GenerateReport', true);

    arguments
        options.Verbose (1,1) logical = false
        options.GenerateReport (1,1) logical = false
        options.ReportFolder (1,:) char = 'test-results'
        options.Tags cell = {}
        options.Parallel (1,1) logical = false
        options.StopOnFailure (1,1) logical = false
        options.Coverage (1,1) logical = false
        options.ExcludeIntegration (1,1) logical = false
        options.JUnitOutput (1,1) logical = false
    end

    % Get test directory
    testDir = fileparts(mfilename('fullpath'));

    % Add toolbox to path if not already
    toolboxDir = fullfile(testDir, '..', 'toolbox');
    if ~contains(path, toolboxDir)
        addpath(toolboxDir);
    end

    % Create test suite
    if options.ExcludeIntegration
        % Only include tests from main test directory (not subfolders)
        suite = matlab.unittest.TestSuite.fromFolder(testDir, ...
            'IncludingSubfolders', false);
    else
        % Include all tests including integration folder
        suite = matlab.unittest.TestSuite.fromFolder(testDir, ...
            'IncludingSubfolders', true);
    end

    % Filter by tags if specified
    if ~isempty(options.Tags)
        import matlab.unittest.selectors.HasTag
        selector = HasTag(options.Tags{1});
        for i = 2:length(options.Tags)
            selector = selector | HasTag(options.Tags{i});
        end
        suite = suite.selectIf(selector);
    end

    % Configure runner
    if options.Verbose
        runner = matlab.unittest.TestRunner.withTextOutput('Verbosity', 3);
    else
        runner = matlab.unittest.TestRunner.withTextOutput;
    end

    % Add stop on failure plugin if requested
    if options.StopOnFailure
        import matlab.unittest.plugins.StopOnFailuresPlugin
        runner.addPlugin(StopOnFailuresPlugin);
    end

    % Add parallel execution if requested and available
    if options.Parallel
        try
            % Check if Parallel Computing Toolbox is available
            if license('test', 'Distrib_Computing_Toolbox')
                % Use runInParallel method if available (R2018a+)
                fprintf('Running tests in parallel with up to %d workers...\n', ...
                    feature('numcores'));
            else
                warning('runAllTests:NoPCT', ...
                    'Parallel Computing Toolbox not available. Running serially.');
            end
        catch
            warning('runAllTests:ParallelError', ...
                'Could not enable parallel execution. Running serially.');
        end
    end

    % Ensure report folder exists
    if options.GenerateReport || options.Coverage || options.JUnitOutput
        if ~exist(options.ReportFolder, 'dir')
            mkdir(options.ReportFolder);
        end
    end

    % Add report generation if requested
    if options.GenerateReport
        try
            import matlab.unittest.plugins.TestReportPlugin
            htmlFile = fullfile(options.ReportFolder, 'test-report.html');
            htmlPlugin = TestReportPlugin.producingHTML(htmlFile);
            runner.addPlugin(htmlPlugin);
            fprintf('HTML report will be generated at: %s\n', htmlFile);
        catch
            warning('runAllTests:NoHTMLReport', ...
                'HTML report plugin not available');
        end
    end

    % Add JUnit XML output if requested
    if options.JUnitOutput
        try
            import matlab.unittest.plugins.XMLPlugin
            xmlFile = fullfile(options.ReportFolder, 'test-results.xml');
            xmlPlugin = XMLPlugin.producingJUnitFormat(xmlFile);
            runner.addPlugin(xmlPlugin);
            fprintf('JUnit XML will be generated at: %s\n', xmlFile);
        catch
            warning('runAllTests:NoXMLPlugin', ...
                'JUnit XML plugin not available');
        end
    end

    % Add code coverage if requested
    if options.Coverage
        try
            % Check if coverage is supported
            import matlab.unittest.plugins.CodeCoveragePlugin
            import matlab.unittest.plugins.codecoverage.CoberturaFormat

            % Get source files to analyze
            sourceDir = fullfile(testDir, '..', 'toolbox', '+derivux');

            % Generate coverage report
            coverageFile = fullfile(options.ReportFolder, 'coverage.xml');
            coveragePlugin = CodeCoveragePlugin.forFolder(sourceDir, ...
                'IncludingSubfolders', true, ...
                'Producing', CoberturaFormat(coverageFile));
            runner.addPlugin(coveragePlugin);
            fprintf('Coverage report will be generated at: %s\n', coverageFile);
        catch ME
            warning('runAllTests:NoCoverage', ...
                'Code coverage not available: %s', ME.message);
        end
    end

    % Run tests
    fprintf('\n');
    fprintf('========================================\n');
    fprintf('RUNNING TESTS\n');
    fprintf('========================================\n');
    fprintf('Test count: %d\n', numel(suite));

    if options.ExcludeIntegration
        fprintf('Mode: Unit tests only (integration excluded)\n');
    else
        fprintf('Mode: All tests (including integration)\n');
    end

    if ~isempty(options.Tags)
        fprintf('Tags: %s\n', strjoin(options.Tags, ', '));
    end

    fprintf('========================================\n\n');

    startTime = tic;
    results = runner.run(suite);
    totalDuration = toc(startTime);

    % Display enhanced summary
    fprintf('\n');
    fprintf('========================================\n');
    fprintf('TEST SUMMARY\n');
    fprintf('========================================\n');

    totalTests = numel(results);
    passedTests = sum([results.Passed]);
    failedTests = sum([results.Failed]);
    incompleteTests = sum([results.Incomplete]);

    passPercent = 100 * passedTests / max(totalTests, 1);

    fprintf('Total:       %d\n', totalTests);
    fprintf('Passed:      %d (%.1f%%)\n', passedTests, passPercent);
    fprintf('Failed:      %d\n', failedTests);
    fprintf('Incomplete:  %d\n', incompleteTests);
    fprintf('Duration:    %.2f seconds\n', totalDuration);
    fprintf('========================================\n');

    % List failures with details if any
    if any([results.Failed])
        fprintf('\nFAILED TESTS:\n');
        fprintf('----------------------------------------\n');
        failedResults = results([results.Failed]);
        for i = 1:numel(failedResults)
            fprintf('\n  [%d] %s\n', i, failedResults(i).Name);

            % Show failure details if available
            if ~isempty(failedResults(i).Details)
                if isfield(failedResults(i).Details, 'DiagnosticRecord')
                    diags = failedResults(i).Details.DiagnosticRecord;
                    if ~isempty(diags)
                        for j = 1:numel(diags)
                            if isprop(diags(j), 'Report') || isfield(diags(j), 'Report')
                                fprintf('      Reason: %s\n', diags(j).Report);
                            end
                        end
                    end
                end
            end
        end
        fprintf('\n----------------------------------------\n');
    end

    % List incomplete tests (skipped due to assumptions) if any
    if any([results.Incomplete])
        fprintf('\nINCOMPLETE TESTS (skipped):\n');
        fprintf('----------------------------------------\n');
        incompleteResults = results([results.Incomplete]);
        for i = 1:numel(incompleteResults)
            fprintf('  - %s\n', incompleteResults(i).Name);
        end
        fprintf('----------------------------------------\n');
    end

    % Report generated files
    if options.GenerateReport || options.Coverage || options.JUnitOutput
        fprintf('\nGENERATED REPORTS:\n');
        fprintf('----------------------------------------\n');

        if options.GenerateReport
            htmlFile = fullfile(options.ReportFolder, 'test-report.html');
            if exist(htmlFile, 'file')
                fprintf('  HTML Report: %s\n', htmlFile);
            end
        end

        if options.JUnitOutput
            xmlFile = fullfile(options.ReportFolder, 'test-results.xml');
            if exist(xmlFile, 'file')
                fprintf('  JUnit XML:   %s\n', xmlFile);
            end
        end

        if options.Coverage
            coverageFile = fullfile(options.ReportFolder, 'coverage.xml');
            if exist(coverageFile, 'file')
                fprintf('  Coverage:    %s\n', coverageFile);
            end
        end

        fprintf('----------------------------------------\n');
    end

    % Final status
    fprintf('\n');
    if failedTests == 0
        fprintf('SUCCESS: All tests passed!\n');
    else
        fprintf('FAILURE: %d test(s) failed\n', failedTests);
    end
    fprintf('\n');

    % Return success/failure as exit code for CI
    if nargout == 0
        if any([results.Failed])
            error('runAllTests:TestsFailed', '%d test(s) failed', sum([results.Failed]));
        end
    end
end
