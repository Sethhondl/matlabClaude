classdef WorkspaceContextProvider < handle
    %WORKSPACECONTEXTPROVIDER Extracts MATLAB workspace information for Claude
    %
    %   This class gathers information about variables in the MATLAB workspace
    %   and formats it as context for Claude to understand.
    %
    %   Example:
    %       provider = claudecode.WorkspaceContextProvider();
    %       context = provider.getWorkspaceContext();

    properties
        MaxVariableSize = 10000     % Max characters per variable in context
        MaxVariables = 50           % Max number of variables to include
        MaxArrayElements = 100      % Max array elements to show
        IncludeTypes = {'double', 'single', 'char', 'string', 'cell', ...
                       'struct', 'table', 'categorical', 'logical', ...
                       'int8', 'int16', 'int32', 'int64', ...
                       'uint8', 'uint16', 'uint32', 'uint64'}
    end

    properties (Access = private)
        Logger                      % Logging instance
    end

    methods
        function obj = WorkspaceContextProvider()
            %WORKSPACECONTEXTPROVIDER Constructor
            obj.Logger = claudecode.logging.Logger.getInstance();
        end

        function context = getWorkspaceContext(obj)
            %GETWORKSPACECONTEXT Get formatted workspace context

            startTime = tic;

            % Get all base workspace variables
            vars = evalin('base', 'whos');

            if isempty(vars)
                obj.Logger.debug('WorkspaceContextProvider', 'workspace_empty');
                context = '## MATLAB Workspace: (empty)';
                return;
            end

            % Sort by size (prioritize smaller, more readable variables)
            [~, idx] = sort([vars.bytes]);
            vars = vars(idx);

            % Build context
            lines = {'## MATLAB Workspace Variables:', ''};
            count = 0;

            for i = 1:length(vars)
                if count >= obj.MaxVariables
                    lines{end+1} = sprintf('... and %d more variables', length(vars) - count);
                    break;
                end

                v = vars(i);

                % Skip excluded types
                if ~ismember(v.class, obj.IncludeTypes)
                    continue;
                end

                % Skip very large variables
                if v.bytes > 1e7  % 10 MB limit
                    continue;
                end

                varStr = obj.formatVariable(v);
                if ~isempty(varStr)
                    lines{end+1} = varStr;
                    count = count + 1;
                end
            end

            context = strjoin(lines, newline);

            elapsedMs = toc(startTime) * 1000;
            obj.Logger.infoTimed('WorkspaceContextProvider', 'context_generated', struct(...
                'variable_count', count, ...
                'total_variables', length(vars), ...
                'context_length', strlength(context)), elapsedMs);
        end

        function summary = getWorkspaceSummary(obj)
            %GETWORKSPACESUMMARY Get a brief summary of the workspace

            vars = evalin('base', 'whos');

            if isempty(vars)
                summary = 'Workspace is empty';
                return;
            end

            % Count by type
            types = {vars.class};
            uniqueTypes = unique(types);
            typeCounts = cellfun(@(t) sum(strcmp(types, t)), uniqueTypes);

            % Build summary
            parts = cell(length(uniqueTypes), 1);
            for i = 1:length(uniqueTypes)
                parts{i} = sprintf('%d %s', typeCounts(i), uniqueTypes{i});
            end

            totalSize = sum([vars.bytes]);
            sizeStr = obj.formatBytes(totalSize);

            summary = sprintf('%d variables (%s total): %s', ...
                length(vars), sizeStr, strjoin(parts, ', '));
        end

        function contextStr = getCurrentDirectoryContext(obj)
            %GETCURRENTDIRECTORYCONTEXT Get current directory and file listing
            %
            %   Returns formatted context about the current working directory
            %   and lists files (limited to 20 items).

            currentDir = pwd;
            lines = {'## Current Directory:', sprintf('`%s`', currentDir), ''};

            % Get directory contents
            try
                contents = dir(currentDir);
                % Filter out . and ..
                contents = contents(~ismember({contents.name}, {'.', '..'}));

                if isempty(contents)
                    lines{end+1} = 'Directory is empty.';
                else
                    lines{end+1} = 'Files in directory:';

                    % Sort: directories first, then files
                    dirs = contents([contents.isdir]);
                    files = contents(~[contents.isdir]);

                    % Sort each group alphabetically
                    if ~isempty(dirs)
                        [~, idx] = sort(lower({dirs.name}));
                        dirs = dirs(idx);
                    end
                    if ~isempty(files)
                        [~, idx] = sort(lower({files.name}));
                        files = files(idx);
                    end

                    contents = [dirs; files];
                    maxItems = 20;
                    displayCount = min(length(contents), maxItems);

                    for i = 1:displayCount
                        item = contents(i);
                        if item.isdir
                            lines{end+1} = sprintf('- [DIR] %s/', item.name);
                        else
                            sizeStr = obj.formatBytes(item.bytes);
                            lines{end+1} = sprintf('- %s (%s)', item.name, sizeStr);
                        end
                    end

                    if length(contents) > maxItems
                        lines{end+1} = sprintf('... and %d more items', length(contents) - maxItems);
                    end
                end
            catch ME
                lines{end+1} = sprintf('Error listing directory: %s', ME.message);
            end

            contextStr = strjoin(lines, newline);
        end

        function contextStr = getEditorContext(~)
            %GETEDITORCONTEXT Get information about the currently open file
            %
            %   Returns formatted context about the active editor file,
            %   including filename, path, cursor position, and selected text.

            lines = {'## Currently Open File:'};

            try
                editorObj = matlab.desktop.editor.getActive();

                if isempty(editorObj)
                    lines{end+1} = 'No file currently open in editor.';
                else
                    % Get file information
                    [~, filename, ext] = fileparts(editorObj.Filename);
                    fullFilename = [filename, ext];

                    lines{end+1} = sprintf('- **File**: `%s`', fullFilename);
                    lines{end+1} = sprintf('- **Path**: `%s`', editorObj.Filename);

                    % Get cursor position
                    selection = editorObj.Selection;
                    if ~isempty(selection)
                        cursorLine = selection(1);
                        lines{end+1} = sprintf('- **Cursor at line**: %d', cursorLine);

                        % Check for selected text
                        selectedText = editorObj.SelectedText;
                        if ~isempty(selectedText)
                            % Truncate if too long
                            maxSelectionLen = 500;
                            if length(selectedText) > maxSelectionLen
                                selectedText = [selectedText(1:maxSelectionLen), '...'];
                            end
                            % Escape any backticks in selected text
                            selectedText = strrep(selectedText, '`', '\`');
                            lines{end+1} = sprintf('- **Selected text**: ```%s```', selectedText);
                        end
                    end
                end
            catch ME
                lines{end+1} = sprintf('Unable to get editor info: %s', ME.message);
            end

            contextStr = strjoin(lines, newline);
        end
    end

    methods (Access = private)
        function str = formatVariable(obj, varInfo)
            %FORMATVARIABLE Format a single variable for display

            name = varInfo.name;

            try
                value = evalin('base', name);

                % Format based on type
                switch varInfo.class
                    case {'double', 'single', 'int8', 'int16', 'int32', 'int64', ...
                          'uint8', 'uint16', 'uint32', 'uint64', 'logical'}
                        str = obj.formatNumeric(name, varInfo, value);

                    case {'char', 'string'}
                        str = obj.formatString(name, varInfo, value);

                    case 'struct'
                        str = obj.formatStruct(name, varInfo, value);

                    case 'cell'
                        str = obj.formatCell(name, varInfo, value);

                    case 'table'
                        str = obj.formatTable(name, varInfo, value);

                    case 'categorical'
                        str = obj.formatCategorical(name, varInfo, value);

                    otherwise
                        str = sprintf('- `%s`: %s %s', ...
                            name, mat2str(varInfo.size), varInfo.class);
                end

                % Truncate if too long
                if length(str) > obj.MaxVariableSize
                    str = [str(1:obj.MaxVariableSize), '...'];
                end

            catch
                str = '';  % Skip variables that can't be read
            end
        end

        function str = formatNumeric(obj, name, varInfo, value)
            %FORMATNUMERIC Format numeric variable

            sizeStr = mat2str(varInfo.size);
            typeStr = varInfo.class;

            if isscalar(value)
                % Scalar - show value
                str = sprintf('- `%s` (%s): %g', name, typeStr, value);

            elseif isvector(value) && numel(value) <= 10
                % Small vector - show all values
                str = sprintf('- `%s` (%s %s): %s', ...
                    name, sizeStr, typeStr, mat2str(value, 4));

            elseif numel(value) <= obj.MaxArrayElements
                % Small array - show shape and sample
                str = sprintf('- `%s` (%s %s): %s', ...
                    name, sizeStr, typeStr, mat2str(value, 4));

            else
                % Large array - show summary stats
                str = sprintf('- `%s` (%s %s): min=%g, max=%g, mean=%g', ...
                    name, sizeStr, typeStr, min(value(:)), max(value(:)), mean(value(:)));
            end
        end

        function str = formatString(~, name, varInfo, value)
            %FORMATSTRING Format string/char variable

            if ischar(value)
                preview = value;
            else
                preview = char(value);
            end

            % Flatten multi-line strings
            preview = strrep(preview, newline, '\n');

            if length(preview) > 100
                preview = [preview(1:100), '...'];
            end

            str = sprintf('- `%s` (%s): "%s"', name, varInfo.class, preview);
        end

        function str = formatStruct(~, name, varInfo, value)
            %FORMATSTRUCT Format struct variable

            fields = fieldnames(value);
            numElements = numel(value);

            if numElements == 1
                fieldList = strjoin(fields, ', ');
                if length(fieldList) > 80
                    fieldList = sprintf('%d fields', length(fields));
                end
                str = sprintf('- `%s` (struct): {%s}', name, fieldList);
            else
                str = sprintf('- `%s` (%s struct array with %d fields)', ...
                    name, mat2str(varInfo.size), length(fields));
            end
        end

        function str = formatCell(~, name, varInfo, ~)
            %FORMATCELL Format cell variable

            str = sprintf('- `%s` (%s cell array)', name, mat2str(varInfo.size));
        end

        function str = formatTable(~, name, ~, value)
            %FORMATTABLE Format table variable

            colNames = value.Properties.VariableNames;
            colList = strjoin(colNames, ', ');

            if length(colList) > 60
                colList = sprintf('%d columns', length(colNames));
            end

            str = sprintf('- `%s` (table %dx%d): [%s]', ...
                name, height(value), width(value), colList);
        end

        function str = formatCategorical(~, name, varInfo, value)
            %FORMATCATEGORICAL Format categorical variable

            cats = categories(value);
            catList = strjoin(cats, ', ');

            if length(catList) > 50
                catList = sprintf('%d categories', length(cats));
            end

            str = sprintf('- `%s` (%s categorical): {%s}', ...
                name, mat2str(varInfo.size), catList);
        end

        function str = formatBytes(~, bytes)
            %FORMATBYTES Format byte size for display

            if bytes < 1024
                str = sprintf('%d B', bytes);
            elseif bytes < 1024^2
                str = sprintf('%.1f KB', bytes/1024);
            elseif bytes < 1024^3
                str = sprintf('%.1f MB', bytes/1024^2);
            else
                str = sprintf('%.1f GB', bytes/1024^3);
            end
        end
    end
end
