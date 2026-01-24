function debugPath()
%DEBUGPATH Diagnostic script to debug Claude CLI path detection

    fprintf('=== Claude CLI Path Debugging ===\n\n');

    % Check HOME
    homeDir = getenv('HOME');
    fprintf('1. HOME = "%s"\n', homeDir);

    if isempty(homeDir)
        fprintf('   ERROR: HOME environment variable is empty!\n');
        fprintf('   Try: setenv(''HOME'', ''/Users/sethhondl'')\n');
        return;
    end

    % Check NVM directory
    nvmDir = fullfile(homeDir, '.nvm', 'versions', 'node');
    fprintf('2. NVM dir = "%s"\n', nvmDir);
    fprintf('   exists? %d\n', exist(nvmDir, 'dir'));

    if exist(nvmDir, 'dir')
        % List node versions
        nodeVersions = dir(nvmDir);
        fprintf('3. Node versions found:\n');
        for i = 1:length(nodeVersions)
            name = nodeVersions(i).name;
            isDir = nodeVersions(i).isdir;
            fprintf('   - "%s" (isdir=%d)\n', name, isDir);

            if isDir && ~startsWith(name, '.')
                candidatePath = fullfile(nvmDir, name, 'bin', 'claude');
                existVal = exist(candidatePath, 'file');
                fprintf('     claude path: "%s"\n', candidatePath);
                fprintf('     exist() = %d\n', existVal);

                if existVal
                    fprintf('\n   SUCCESS! Found Claude at: %s\n', candidatePath);
                    nodeBinDir = fullfile(nvmDir, name, 'bin');
                    fprintf('   Node bin dir: %s\n', nodeBinDir);

                    % Test if we can run it WITH PATH set
                    cmd = sprintf('export PATH="%s:$PATH" && "%s" --version', nodeBinDir, candidatePath);
                    fprintf('   Running: %s\n', cmd);
                    [status, output] = system(cmd);
                    fprintf('   Version check: status=%d, output=%s\n', status, strtrim(output));
                    return;
                end
            end
        end
    end

    % Try which command
    fprintf('\n4. Trying "which claude"...\n');
    [status, result] = system('which claude 2>/dev/null');
    fprintf('   status=%d, result="%s"\n', status, strtrim(result));

    fprintf('\n=== End Debug ===\n');
end
