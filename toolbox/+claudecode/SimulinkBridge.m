classdef SimulinkBridge < handle
    %SIMULINKBRIDGE Provides Simulink model introspection and manipulation
    %
    %   This class enables Claude to understand and modify Simulink models
    %   through programmatic APIs.
    %
    %   Example:
    %       bridge = claudecode.SimulinkBridge();
    %       bridge.setCurrentModel('myModel');
    %       context = bridge.buildSimulinkContext();

    properties (SetAccess = private)
        CurrentModel = ''       % Current model name
        ModelHandle = []        % Handle to current model
    end

    properties (Access = private)
        Logger                  % Logging instance
    end

    methods
        function obj = SimulinkBridge()
            %SIMULINKBRIDGE Constructor
            obj.Logger = claudecode.logging.Logger.getInstance();
        end

        %% Model Discovery and Selection

        function models = getOpenModels(~)
            %GETOPENMODELS Get list of open Simulink models

            try
                models = find_system('SearchDepth', 0, 'Type', 'block_diagram');
            catch
                models = {};
            end
        end

        function success = setCurrentModel(obj, modelName)
            %SETCURRENTMODEL Set the current working model
            %
            %   success = bridge.setCurrentModel('myModel')

            obj.Logger.info('SimulinkBridge', 'model_selected', struct('model', modelName));

            try
                % Check if model exists/is loaded
                if ~bdIsLoaded(modelName)
                    load_system(modelName);
                end

                obj.CurrentModel = modelName;
                obj.ModelHandle = get_param(modelName, 'Handle');
                success = true;

                obj.Logger.debug('SimulinkBridge', 'model_loaded', struct('model', modelName));

            catch ME
                obj.Logger.warn('SimulinkBridge', 'model_load_failed', struct(...
                    'model', modelName, 'error', ME.message));
                warning('SimulinkBridge:ModelError', ...
                    'Could not set model: %s', ME.message);
                success = false;
            end
        end

        function name = getCurrentModel(obj)
            %GETCURRENTMODEL Get current model name

            name = obj.CurrentModel;
        end

        %% Context Extraction for Claude

        function context = extractModelContext(obj, modelName)
            %EXTRACTMODELCONTEXT Extract detailed model information
            %
            %   context = bridge.extractModelContext()
            %   context = bridge.extractModelContext('specificModel')

            if nargin < 2 || isempty(modelName)
                modelName = obj.CurrentModel;
            end

            if isempty(modelName)
                context = struct('error', 'No model selected');
                return;
            end

            try
                context = struct();
                context.name = modelName;
                context.blocks = obj.getBlockList(modelName);
                context.connections = obj.getConnections(modelName);
                context.subsystems = obj.getSubsystems(modelName);
                context.parameters = obj.getModelParameters(modelName);

            catch ME
                context = struct('error', ME.message);
            end
        end

        function blocks = getBlockList(~, modelName)
            %GETBLOCKLIST Get list of blocks in the model

            blockPaths = find_system(modelName, ...
                'SearchDepth', 1, ...
                'Type', 'block');

            blocks = cell(length(blockPaths), 1);

            for i = 1:length(blockPaths)
                path = blockPaths{i};

                % Skip the model itself
                if strcmp(path, modelName)
                    continue;
                end

                try
                    block = struct();
                    block.path = path;
                    block.name = get_param(path, 'Name');
                    block.blockType = get_param(path, 'BlockType');
                    block.position = get_param(path, 'Position');

                    % Get port info
                    ports = get_param(path, 'Ports');
                    block.numInputs = ports(1);
                    block.numOutputs = ports(2);

                    % Check if it's a subsystem
                    block.isSubsystem = strcmp(block.blockType, 'SubSystem');

                    blocks{i} = block;

                catch
                    % Skip blocks that can't be read
                end
            end

            % Remove empty entries
            blocks = blocks(~cellfun('isempty', blocks));
        end

        function connections = getConnections(~, modelName)
            %GETCONNECTIONS Get signal connections in the model

            lines = find_system(modelName, ...
                'SearchDepth', 1, ...
                'FindAll', 'on', ...
                'Type', 'line');

            connections = cell(length(lines), 1);

            for i = 1:length(lines)
                try
                    lineH = lines(i);
                    conn = struct();

                    srcBlockH = get_param(lineH, 'SrcBlockHandle');
                    dstBlockH = get_param(lineH, 'DstBlockHandle');

                    if srcBlockH > 0 && dstBlockH > 0
                        conn.srcBlock = get_param(srcBlockH, 'Name');
                        conn.srcPort = get_param(lineH, 'SrcPortHandle');
                        conn.dstBlock = get_param(dstBlockH, 'Name');
                        conn.dstPort = get_param(lineH, 'DstPortHandle');

                        % Get signal name if set
                        signalName = get_param(lineH, 'Name');
                        if ~isempty(signalName)
                            conn.signalName = signalName;
                        end

                        connections{i} = conn;
                    end

                catch
                    % Skip lines that can't be read
                end
            end

            % Remove empty entries
            connections = connections(~cellfun('isempty', connections));
        end

        function subsystems = getSubsystems(~, modelName)
            %GETSUBSYSTEMS Get list of subsystems

            ssPaths = find_system(modelName, ...
                'SearchDepth', 1, ...
                'BlockType', 'SubSystem');

            subsystems = cell(length(ssPaths), 1);

            for i = 1:length(ssPaths)
                path = ssPaths{i};

                if strcmp(path, modelName)
                    continue;
                end

                try
                    ss = struct();
                    ss.path = path;
                    ss.name = get_param(path, 'Name');

                    % Count internal blocks
                    internalBlocks = find_system(path, ...
                        'SearchDepth', 1, ...
                        'Type', 'block');
                    ss.numBlocks = length(internalBlocks) - 1;  % Exclude subsystem itself

                    subsystems{i} = ss;

                catch
                    % Skip subsystems that can't be read
                end
            end

            % Remove empty entries
            subsystems = subsystems(~cellfun('isempty', subsystems));
        end

        function params = getModelParameters(~, modelName)
            %GETMODELPARAMETERS Get model configuration parameters

            try
                params = struct();
                params.solver = get_param(modelName, 'Solver');
                params.stopTime = get_param(modelName, 'StopTime');
                params.startTime = get_param(modelName, 'StartTime');
                params.fixedStep = get_param(modelName, 'FixedStep');

            catch
                params = struct();
            end
        end

        %% Context Formatting for Claude

        function contextStr = buildSimulinkContext(obj)
            %BUILDSIMULINKCONTEXT Build formatted context string for Claude

            startTime = tic;

            if isempty(obj.CurrentModel)
                % Try to find an open model
                models = obj.getOpenModels();
                if isempty(models)
                    obj.Logger.debug('SimulinkBridge', 'no_models_open');
                    contextStr = '## Simulink: No models open';
                    return;
                end
                obj.setCurrentModel(models{1});
            end

            context = obj.extractModelContext();

            if isfield(context, 'error')
                obj.Logger.warn('SimulinkBridge', 'context_extraction_error', struct('error', context.error));
                contextStr = sprintf('## Simulink Error: %s', context.error);
                return;
            end

            lines = {
                sprintf('## Simulink Model: %s', context.name)
                ''
            };

            % Model parameters
            if ~isempty(fieldnames(context.parameters))
                lines{end+1} = '### Configuration:';
                lines{end+1} = sprintf('- Solver: %s', context.parameters.solver);
                lines{end+1} = sprintf('- Time: %s to %s', ...
                    context.parameters.startTime, context.parameters.stopTime);
                lines{end+1} = '';
            end

            % Blocks
            lines{end+1} = sprintf('### Blocks (%d):', length(context.blocks));
            for i = 1:min(length(context.blocks), 20)  % Limit to 20 blocks
                block = context.blocks{i};
                if block.isSubsystem
                    lines{end+1} = sprintf('- **%s** (SubSystem)', block.name);
                else
                    lines{end+1} = sprintf('- %s (%s) [in:%d, out:%d]', ...
                        block.name, block.blockType, block.numInputs, block.numOutputs);
                end
            end

            if length(context.blocks) > 20
                lines{end+1} = sprintf('  ... and %d more blocks', length(context.blocks) - 20);
            end

            lines{end+1} = '';

            % Connections
            lines{end+1} = sprintf('### Connections (%d):', length(context.connections));
            for i = 1:min(length(context.connections), 15)  % Limit connections
                conn = context.connections{i};
                connStr = sprintf('- %s -> %s', conn.srcBlock, conn.dstBlock);
                if isfield(conn, 'signalName') && ~isempty(conn.signalName)
                    connStr = sprintf('%s (signal: %s)', connStr, conn.signalName);
                end
                lines{end+1} = connStr;
            end

            if length(context.connections) > 15
                lines{end+1} = sprintf('  ... and %d more connections', length(context.connections) - 15);
            end

            contextStr = strjoin(lines, newline);

            elapsedMs = toc(startTime) * 1000;
            obj.Logger.infoTimed('SimulinkBridge', 'context_extracted', struct(...
                'model', context.name, ...
                'block_count', length(context.blocks), ...
                'connection_count', length(context.connections)), elapsedMs);
        end

        %% Model Modification

        function success = addBlockFromLibrary(obj, libraryPath, destName, params)
            %ADDBLOCKFROMLIBRARY Add a block from a library to the current model
            %
            %   success = bridge.addBlockFromLibrary('simulink/Sources/Constant', 'MyConstant')
            %   success = bridge.addBlockFromLibrary('...', 'MyConstant', struct('Value', '5'))

            if isempty(obj.CurrentModel)
                warning('SimulinkBridge:NoModel', 'No current model set');
                success = false;
                return;
            end

            try
                destPath = [obj.CurrentModel, '/', destName];
                add_block(libraryPath, destPath);

                % Set parameters if provided
                if nargin > 3 && ~isempty(params)
                    paramNames = fieldnames(params);
                    for i = 1:length(paramNames)
                        set_param(destPath, paramNames{i}, params.(paramNames{i}));
                    end
                end

                success = true;

            catch ME
                warning('SimulinkBridge:AddBlockError', ...
                    'Failed to add block: %s', ME.message);
                success = false;
            end
        end

        function success = connectBlocks(obj, srcBlock, srcPort, dstBlock, dstPort)
            %CONNECTBLOCKS Connect two blocks
            %
            %   success = bridge.connectBlocks('Source', 1, 'Sink', 1)

            if isempty(obj.CurrentModel)
                warning('SimulinkBridge:NoModel', 'No current model set');
                success = false;
                return;
            end

            try
                srcPortPath = sprintf('%s/%d', srcBlock, srcPort);
                dstPortPath = sprintf('%s/%d', dstBlock, dstPort);

                add_line(obj.CurrentModel, srcPortPath, dstPortPath, ...
                    'autorouting', 'smart');

                success = true;

            catch ME
                warning('SimulinkBridge:ConnectError', ...
                    'Failed to connect blocks: %s', ME.message);
                success = false;
            end
        end

        function success = setBlockParameter(obj, blockName, paramName, paramValue)
            %SETBLOCKPARAMETER Set a parameter on a block
            %
            %   success = bridge.setBlockParameter('MyGain', 'Gain', '2.5')

            if isempty(obj.CurrentModel)
                warning('SimulinkBridge:NoModel', 'No current model set');
                success = false;
                return;
            end

            try
                blockPath = [obj.CurrentModel, '/', blockName];
                set_param(blockPath, paramName, paramValue);
                success = true;

            catch ME
                warning('SimulinkBridge:SetParamError', ...
                    'Failed to set parameter: %s', ME.message);
                success = false;
            end
        end

        function success = deleteBlock(obj, blockName)
            %DELETEBLOCK Delete a block from the model
            %
            %   success = bridge.deleteBlock('OldBlock')

            if isempty(obj.CurrentModel)
                warning('SimulinkBridge:NoModel', 'No current model set');
                success = false;
                return;
            end

            try
                blockPath = [obj.CurrentModel, '/', blockName];
                delete_block(blockPath);
                success = true;

            catch ME
                warning('SimulinkBridge:DeleteError', ...
                    'Failed to delete block: %s', ME.message);
                success = false;
            end
        end

        function arrangeModel(obj)
            %ARRANGEMODEL Auto-arrange blocks in the model

            if isempty(obj.CurrentModel)
                return;
            end

            try
                Simulink.BlockDiagram.arrangeSystem(obj.CurrentModel);
            catch
                % Ignore errors in arrangement
            end
        end

        function success = executeSimulinkCommand(obj, command)
            %EXECUTESIMULINKCOMMAND Execute a Simulink command string
            %
            %   This allows Claude to suggest Simulink commands that get executed.
            %   Commands are validated before execution.

            % Basic validation - ensure it's a Simulink operation
            validPrefixes = {'add_block', 'add_line', 'delete_block', 'delete_line', ...
                            'set_param', 'get_param', 'Simulink.'};

            isValid = false;
            for i = 1:length(validPrefixes)
                if startsWith(strtrim(command), validPrefixes{i})
                    isValid = true;
                    break;
                end
            end

            if ~isValid
                warning('SimulinkBridge:InvalidCommand', ...
                    'Command does not appear to be a valid Simulink operation');
                success = false;
                return;
            end

            try
                evalin('base', command);
                success = true;
            catch ME
                warning('SimulinkBridge:CommandError', ...
                    'Command failed: %s', ME.message);
                success = false;
            end
        end
    end
end
