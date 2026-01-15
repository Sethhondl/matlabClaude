function results = runAllTests(options)
%RUNALLTESTS Run all unit tests for Claude Code MATLAB integration
%
%   results = runAllTests() runs all tests and returns results
%   results = runAllTests('Verbose', true) runs with verbose output
%
%   Example:
%       results = runAllTests();
%       disp(results);

    arguments
        options.Verbose (1,1) logical = false
        options.GenerateReport (1,1) logical = false
        options.ReportFolder (1,:) char = 'test-results'
    end

    % Get test directory
    testDir = fileparts(mfilename('fullpath'));

    % Add toolbox to path if not already
    toolboxDir = fullfile(testDir, '..', 'toolbox');
    if ~contains(path, toolboxDir)
        addpath(toolboxDir);
    end

    % Create test suite
    suite = matlab.unittest.TestSuite.fromFolder(testDir, ...
        'IncludingSubfolders', true);

    % Configure runner
    runner = matlab.unittest.TestRunner.withTextOutput;

    if options.Verbose
        runner = matlab.unittest.TestRunner.withTextOutput('Verbosity', 3);
    end

    % Add report generation if requested
    if options.GenerateReport
        if ~exist(options.ReportFolder, 'dir')
            mkdir(options.ReportFolder);
        end

        % Try to add HTML report plugin (requires R2017a+)
        try
            import matlab.unittest.plugins.TestReportPlugin
            htmlFile = fullfile(options.ReportFolder, 'test-report.html');
            htmlPlugin = TestReportPlugin.producingHTML(htmlFile);
            runner.addPlugin(htmlPlugin);
        catch
            warning('runAllTests:NoHTMLReport', ...
                'HTML report plugin not available');
        end
    end

    % Run tests
    fprintf('Running %d test(s)...\n\n', numel(suite));
    results = runner.run(suite);

    % Display summary
    fprintf('\n');
    fprintf('========================================\n');
    fprintf('TEST SUMMARY\n');
    fprintf('========================================\n');
    fprintf('Total:  %d\n', numel(results));
    fprintf('Passed: %d\n', sum([results.Passed]));
    fprintf('Failed: %d\n', sum([results.Failed]));
    fprintf('Incomplete: %d\n', sum([results.Incomplete]));
    fprintf('Duration: %.2f seconds\n', sum([results.Duration]));
    fprintf('========================================\n');

    % List failures if any
    if any([results.Failed])
        fprintf('\nFAILED TESTS:\n');
        failedTests = results([results.Failed]);
        for i = 1:numel(failedTests)
            fprintf('  - %s\n', failedTests(i).Name);
        end
    end

    % Return success/failure as exit code for CI
    if nargout == 0
        if any([results.Failed])
            error('runAllTests:TestsFailed', '%d test(s) failed', sum([results.Failed]));
        end
    end
end
