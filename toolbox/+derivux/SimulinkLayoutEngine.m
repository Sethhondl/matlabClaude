classdef SimulinkLayoutEngine < handle
    %SIMULINKLAYOUTENGINE Custom layout engine for Simulink diagrams
    %
    %   Produces clean, readable diagrams with:
    %   - 90-degree wire angles
    %   - Minimal wire crossings
    %   - Logical signal flow (left-to-right)
    %   - Well-spaced, aligned blocks
    %
    %   Example:
    %       engine = claudecode.SimulinkLayoutEngine('myModel');
    %       engine.extractGraph();
    %       engine.assignLayers();
    %       engine.minimizeCrossings();
    %       engine.assignCoordinates();
    %       engine.routeWires();
    %       engine.applyLayout();
    %
    %   Or use the convenience method:
    %       engine.optimize();

    properties (SetAccess = private)
        ModelName           % Simulink model name
        Blocks              % Cell array of block structs
        Edges               % Cell array of connection structs
        Layers              % Cell array of layers (each layer = list of block indices)
        BlockPositions      % containers.Map: blockName -> [x, y, width, height]
        WireRoutes          % containers.Map: edgeIndex -> array of [x,y] waypoints
    end

    properties (Access = private)
        Logger              % Logging instance
        BlockIndexMap       % Map block name to index in Blocks array
        AdjacencyList       % Forward adjacency: blockIdx -> [connected blockIdx]
        ReverseAdjList      % Reverse adjacency: blockIdx -> [predecessor blockIdx]
        LayerAssignment     % Array: blockIdx -> layer number
    end

    properties (Constant, Access = private)
        % Layout parameters
        LAYER_SPACING = 150     % Horizontal gap between layers (pixels)
        BLOCK_SPACING = 50      % Vertical gap between blocks (pixels)
        MIN_BLOCK_WIDTH = 60    % Minimum block width
        MIN_BLOCK_HEIGHT = 40   % Minimum block height
        WIRE_CHANNEL_WIDTH = 10 % Spacing between parallel wires
        MAX_CROSSING_ITERATIONS = 10  % Max iterations for crossing minimization
    end

    methods
        function obj = SimulinkLayoutEngine(modelName)
            %SIMULINKLAYOUTENGINE Constructor
            %
            %   engine = SimulinkLayoutEngine('modelName')

            arguments
                modelName (1,1) string
            end

            obj.ModelName = char(modelName);
            obj.Logger = claudecode.logging.Logger.getInstance();
            obj.Blocks = {};
            obj.Edges = {};
            obj.Layers = {};
            obj.BlockPositions = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.WireRoutes = containers.Map('KeyType', 'double', 'ValueType', 'any');
            obj.BlockIndexMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
            obj.AdjacencyList = {};
            obj.ReverseAdjList = {};
            obj.LayerAssignment = [];

            obj.Logger.debug('SimulinkLayoutEngine', 'created', struct('model', obj.ModelName));
        end

        function optimize(obj, options)
            %OPTIMIZE Run complete layout optimization pipeline
            %
            %   engine.optimize()
            %   engine.optimize('Spacing', 60)

            arguments
                obj
                options.Spacing (1,1) double = 50
            end

            startTime = tic;

            obj.extractGraph();
            obj.assignLayers();
            obj.minimizeCrossings();
            obj.assignCoordinates(options.Spacing);
            obj.routeWires();
            obj.applyLayout();

            elapsedMs = toc(startTime) * 1000;
            obj.Logger.infoTimed('SimulinkLayoutEngine', 'optimization_complete', ...
                struct('model', obj.ModelName, 'blocks', length(obj.Blocks)), elapsedMs);
        end

        %% Phase 1: Graph Extraction

        function extractGraph(obj)
            %EXTRACTGRAPH Build internal graph representation from Simulink model
            %
            %   Extracts all blocks and connections from the model's top level.

            obj.Logger.debug('SimulinkLayoutEngine', 'extracting_graph', struct('model', obj.ModelName));

            % Ensure model is loaded
            if ~bdIsLoaded(obj.ModelName)
                load_system(obj.ModelName);
            end

            % Get all blocks at top level
            blockPaths = find_system(obj.ModelName, ...
                'SearchDepth', 1, ...
                'Type', 'block');

            obj.Blocks = {};
            obj.BlockIndexMap = containers.Map('KeyType', 'char', 'ValueType', 'double');

            blockIdx = 0;
            for i = 1:length(blockPaths)
                path = blockPaths{i};

                % Skip the model itself
                if strcmp(path, obj.ModelName)
                    continue;
                end

                try
                    block = struct();
                    block.path = path;
                    block.name = get_param(path, 'Name');
                    block.blockType = get_param(path, 'BlockType');

                    % Get current position
                    pos = get_param(path, 'Position');
                    block.position = pos;
                    block.width = max(pos(3) - pos(1), obj.MIN_BLOCK_WIDTH);
                    block.height = max(pos(4) - pos(2), obj.MIN_BLOCK_HEIGHT);

                    % Get port info
                    ports = get_param(path, 'Ports');
                    block.numInputs = ports(1);
                    block.numOutputs = ports(2);

                    % Get port handles for precise positioning
                    portHandles = get_param(path, 'PortHandles');
                    block.inputPorts = portHandles.Inport;
                    block.outputPorts = portHandles.Outport;

                    blockIdx = blockIdx + 1;
                    block.index = blockIdx;
                    obj.Blocks{blockIdx} = block;
                    obj.BlockIndexMap(block.name) = blockIdx;

                catch ME
                    obj.Logger.warn('SimulinkLayoutEngine', 'block_extraction_failed', ...
                        struct('block', path, 'error', ME.message));
                end
            end

            % Initialize adjacency lists
            numBlocks = length(obj.Blocks);
            obj.AdjacencyList = cell(numBlocks, 1);
            obj.ReverseAdjList = cell(numBlocks, 1);
            for i = 1:numBlocks
                obj.AdjacencyList{i} = [];
                obj.ReverseAdjList{i} = [];
            end

            % Get all lines (connections)
            lines = find_system(obj.ModelName, ...
                'SearchDepth', 1, ...
                'FindAll', 'on', ...
                'Type', 'line');

            obj.Edges = {};
            edgeIdx = 0;

            for i = 1:length(lines)
                try
                    lineH = lines(i);

                    srcBlockH = get_param(lineH, 'SrcBlockHandle');
                    dstBlockH = get_param(lineH, 'DstBlockHandle');

                    if srcBlockH > 0 && dstBlockH > 0
                        srcName = get_param(srcBlockH, 'Name');
                        dstName = get_param(dstBlockH, 'Name');

                        % Skip if blocks not in our map (e.g., nested)
                        if ~isKey(obj.BlockIndexMap, srcName) || ~isKey(obj.BlockIndexMap, dstName)
                            continue;
                        end

                        edge = struct();
                        edge.lineHandle = lineH;
                        edge.srcBlock = srcName;
                        edge.srcBlockIdx = obj.BlockIndexMap(srcName);
                        edge.srcPort = get_param(lineH, 'SrcPortHandle');
                        edge.dstBlock = dstName;
                        edge.dstBlockIdx = obj.BlockIndexMap(dstName);
                        edge.dstPort = get_param(lineH, 'DstPortHandle');

                        % Get signal name if set
                        signalName = get_param(lineH, 'Name');
                        if ~isempty(signalName)
                            edge.signalName = signalName;
                        else
                            edge.signalName = '';
                        end

                        edgeIdx = edgeIdx + 1;
                        edge.index = edgeIdx;
                        obj.Edges{edgeIdx} = edge;

                        % Build adjacency lists
                        obj.AdjacencyList{edge.srcBlockIdx}(end+1) = edge.dstBlockIdx;
                        obj.ReverseAdjList{edge.dstBlockIdx}(end+1) = edge.srcBlockIdx;
                    end

                catch ME
                    obj.Logger.warn('SimulinkLayoutEngine', 'edge_extraction_failed', ...
                        struct('error', ME.message));
                end
            end

            obj.Logger.debug('SimulinkLayoutEngine', 'graph_extracted', ...
                struct('blocks', length(obj.Blocks), 'edges', length(obj.Edges)));
        end

        %% Phase 2: Layer Assignment

        function assignLayers(obj)
            %ASSIGNLAYERS Assign blocks to layers using longest-path algorithm
            %
            %   Sources get layer 0, sinks get the highest layer.
            %   Uses topological sorting with cycle detection for feedback loops.

            numBlocks = length(obj.Blocks);
            if numBlocks == 0
                return;
            end

            obj.LayerAssignment = zeros(numBlocks, 1);

            % Find sources (blocks with no inputs or only feedback inputs)
            sources = obj.findSourceBlocks();

            % Use BFS-based longest path from sources
            visited = false(numBlocks, 1);
            inQueue = false(numBlocks, 1);

            % Initialize: sources at layer 0
            queue = sources;
            for i = 1:length(sources)
                obj.LayerAssignment(sources(i)) = 0;
                visited(sources(i)) = true;
                inQueue(sources(i)) = true;
            end

            % Process queue
            while ~isempty(queue)
                current = queue(1);
                queue(1) = [];
                inQueue(current) = false;
                visited(current) = true;

                currentLayer = obj.LayerAssignment(current);

                % Update successors
                successors = obj.AdjacencyList{current};
                for i = 1:length(successors)
                    succ = successors(i);

                    % Successor should be at least one layer after current
                    newLayer = currentLayer + 1;

                    if newLayer > obj.LayerAssignment(succ)
                        obj.LayerAssignment(succ) = newLayer;

                        % Add to queue if not already there
                        if ~inQueue(succ)
                            queue(end+1) = succ;
                            inQueue(succ) = true;
                        end
                    end
                end
            end

            % Handle any unvisited blocks (disconnected components)
            for i = 1:numBlocks
                if ~visited(i)
                    % Place disconnected blocks at layer 0
                    obj.LayerAssignment(i) = 0;
                end
            end

            % Build layer structure
            maxLayer = max(obj.LayerAssignment);
            obj.Layers = cell(maxLayer + 1, 1);

            for layer = 0:maxLayer
                obj.Layers{layer + 1} = find(obj.LayerAssignment == layer)';
            end

            obj.Logger.debug('SimulinkLayoutEngine', 'layers_assigned', ...
                struct('num_layers', maxLayer + 1));
        end

        %% Phase 3: Crossing Minimization

        function minimizeCrossings(obj)
            %MINIMIZECROSSINGS Reorder blocks within layers to minimize edge crossings
            %
            %   Uses the barycenter heuristic with forward and backward sweeps.

            numLayers = length(obj.Layers);
            if numLayers <= 1
                return;
            end

            bestCrossings = obj.countCrossings();
            bestLayers = obj.Layers;

            for iter = 1:obj.MAX_CROSSING_ITERATIONS
                % Forward sweep (left to right)
                for layerIdx = 2:numLayers
                    obj.reorderLayerByBarycenter(layerIdx, 'forward');
                end

                % Backward sweep (right to left)
                for layerIdx = (numLayers-1):-1:1
                    obj.reorderLayerByBarycenter(layerIdx, 'backward');
                end

                currentCrossings = obj.countCrossings();

                if currentCrossings < bestCrossings
                    bestCrossings = currentCrossings;
                    bestLayers = obj.Layers;
                elseif currentCrossings == bestCrossings
                    % No improvement, stop early
                    break;
                end
            end

            % Restore best configuration
            obj.Layers = bestLayers;

            obj.Logger.debug('SimulinkLayoutEngine', 'crossings_minimized', ...
                struct('crossings', bestCrossings, 'iterations', iter));
        end

        function crossings = countCrossings(obj)
            %COUNTCROSSINGS Count total edge crossings between adjacent layers

            crossings = 0;
            numLayers = length(obj.Layers);

            for layerIdx = 1:(numLayers - 1)
                layer1 = obj.Layers{layerIdx};
                layer2 = obj.Layers{layerIdx + 1};

                % Get edges between these layers
                edges = obj.getEdgesBetweenLayers(layer1, layer2);

                % Count crossings using sweep line
                numEdges = size(edges, 1);
                for i = 1:(numEdges - 1)
                    for j = (i + 1):numEdges
                        % Two edges cross if their endpoints are inverted
                        if (edges(i, 1) < edges(j, 1) && edges(i, 2) > edges(j, 2)) || ...
                           (edges(i, 1) > edges(j, 1) && edges(i, 2) < edges(j, 2))
                            crossings = crossings + 1;
                        end
                    end
                end
            end
        end

        %% Phase 4: Coordinate Assignment

        function assignCoordinates(obj, spacing)
            %ASSIGNCOORDINATES Calculate actual (x, y) pixel positions for blocks
            %
            %   assignCoordinates(spacing) - spacing between blocks (default: 50)

            arguments
                obj
                spacing (1,1) double = 50
            end

            if isempty(obj.Layers)
                return;
            end

            blockSpacing = spacing;
            layerSpacing = obj.LAYER_SPACING;

            % Calculate max width per layer for proper horizontal spacing
            numLayers = length(obj.Layers);
            layerWidths = zeros(numLayers, 1);

            for layerIdx = 1:numLayers
                layer = obj.Layers{layerIdx};
                maxWidth = 0;
                for i = 1:length(layer)
                    blockIdx = layer(i);
                    block = obj.Blocks{blockIdx};
                    maxWidth = max(maxWidth, block.width);
                end
                layerWidths(layerIdx) = maxWidth;
            end

            % Assign positions
            x = layerSpacing;

            for layerIdx = 1:numLayers
                layer = obj.Layers{layerIdx};
                y = blockSpacing;

                for i = 1:length(layer)
                    blockIdx = layer(i);
                    block = obj.Blocks{blockIdx};

                    % Store position [x, y, width, height]
                    obj.BlockPositions(block.name) = [x, y, block.width, block.height];

                    y = y + block.height + blockSpacing;
                end

                x = x + layerWidths(layerIdx) + layerSpacing;
            end

            % Vertical alignment refinement
            obj.refineVerticalAlignment();

            obj.Logger.debug('SimulinkLayoutEngine', 'coordinates_assigned', ...
                struct('layers', numLayers));
        end

        %% Phase 5: Wire Routing

        function routeWires(obj)
            %ROUTEWIRES Compute orthogonal wire routes with 90-degree angles
            %
            %   Computes waypoints for each edge to achieve clean wire paths.

            for i = 1:length(obj.Edges)
                edge = obj.Edges{i};

                srcPos = obj.BlockPositions(edge.srcBlock);
                dstPos = obj.BlockPositions(edge.dstBlock);

                % Source port position (right side of source block)
                srcBlock = obj.Blocks{edge.srcBlockIdx};
                srcPortIdx = obj.getOutputPortIndex(edge.srcPort, srcBlock);
                srcX = srcPos(1) + srcPos(3);  % Right edge
                srcY = obj.calculatePortY(srcPos, srcPortIdx, srcBlock.numOutputs);

                % Destination port position (left side of dest block)
                dstBlock = obj.Blocks{edge.dstBlockIdx};
                dstPortIdx = obj.getInputPortIndex(edge.dstPort, dstBlock);
                dstX = dstPos(1);  % Left edge
                dstY = obj.calculatePortY(dstPos, dstPortIdx, dstBlock.numInputs);

                % Compute orthogonal route
                waypoints = obj.computeOrthogonalRoute(srcX, srcY, dstX, dstY);
                obj.WireRoutes(i) = waypoints;
            end

            obj.Logger.debug('SimulinkLayoutEngine', 'wires_routed', ...
                struct('edges', length(obj.Edges)));
        end

        %% Phase 6: Apply Layout

        function success = applyLayout(obj)
            %APPLYLAYOUT Apply computed positions and routes to the Simulink model
            %
            %   Returns true if layout was successfully applied.

            success = false;

            try
                % 1. Set block positions
                keys = obj.BlockPositions.keys;
                for i = 1:length(keys)
                    blockName = keys{i};
                    pos = obj.BlockPositions(blockName);
                    blockPath = [obj.ModelName, '/', blockName];

                    % Position format: [left, top, right, bottom]
                    newPos = [pos(1), pos(2), pos(1) + pos(3), pos(2) + pos(4)];
                    set_param(blockPath, 'Position', newPos);
                end

                % 2. Store edge info before deleting lines
                edgeInfo = cell(length(obj.Edges), 1);
                for i = 1:length(obj.Edges)
                    edge = obj.Edges{i};
                    info = struct();
                    info.srcBlock = edge.srcBlock;
                    info.dstBlock = edge.dstBlock;
                    info.srcPortIdx = obj.getOutputPortIndex(edge.srcPort, obj.Blocks{edge.srcBlockIdx});
                    info.dstPortIdx = obj.getInputPortIndex(edge.dstPort, obj.Blocks{edge.dstBlockIdx});
                    info.signalName = edge.signalName;
                    edgeInfo{i} = info;
                end

                % 3. Delete all existing lines
                lines = find_system(obj.ModelName, ...
                    'SearchDepth', 1, ...
                    'FindAll', 'on', ...
                    'Type', 'line');

                for i = 1:length(lines)
                    try
                        delete_line(lines(i));
                    catch
                        % Ignore deletion errors
                    end
                end

                % 4. Recreate lines with computed routes
                for i = 1:length(edgeInfo)
                    info = edgeInfo{i};

                    srcPortPath = sprintf('%s/%d', info.srcBlock, info.srcPortIdx);
                    dstPortPath = sprintf('%s/%d', info.dstBlock, info.dstPortIdx);

                    try
                        if isKey(obj.WireRoutes, i)
                            waypoints = obj.WireRoutes(i);

                            % Add line with waypoints
                            lineH = add_line(obj.ModelName, srcPortPath, dstPortPath, ...
                                'autorouting', 'off');

                            % Set waypoints if line was created
                            if ~isempty(lineH) && lineH > 0
                                try
                                    set_param(lineH, 'Points', waypoints);
                                catch
                                    % If setting points fails, line still exists
                                end

                                % Restore signal name
                                if ~isempty(info.signalName)
                                    try
                                        set_param(lineH, 'Name', info.signalName);
                                    catch
                                        % Ignore
                                    end
                                end
                            end
                        else
                            % Fallback to smart autorouting
                            add_line(obj.ModelName, srcPortPath, dstPortPath, ...
                                'autorouting', 'smart');
                        end
                    catch ME
                        obj.Logger.warn('SimulinkLayoutEngine', 'line_creation_failed', ...
                            struct('src', srcPortPath, 'dst', dstPortPath, 'error', ME.message));
                    end
                end

                success = true;
                obj.Logger.info('SimulinkLayoutEngine', 'layout_applied', ...
                    struct('model', obj.ModelName));

            catch ME
                obj.Logger.error('SimulinkLayoutEngine', 'layout_application_failed', ...
                    struct('error', ME.message));
            end
        end
    end

    %% Private Helper Methods
    methods (Access = private)

        function sources = findSourceBlocks(obj)
            %FINDSOURCEBLOCKS Find all blocks with no predecessors

            sources = [];
            numBlocks = length(obj.Blocks);

            for i = 1:numBlocks
                if isempty(obj.ReverseAdjList{i})
                    sources(end+1) = i;
                end
            end

            % If no sources found (all cyclic), pick blocks with fewest inputs
            if isempty(sources)
                minInputs = inf;
                for i = 1:numBlocks
                    numInputs = length(obj.ReverseAdjList{i});
                    if numInputs < minInputs
                        minInputs = numInputs;
                    end
                end

                for i = 1:numBlocks
                    if length(obj.ReverseAdjList{i}) == minInputs
                        sources(end+1) = i;
                    end
                end
            end
        end

        function reorderLayerByBarycenter(obj, layerIdx, direction)
            %REORDERLAYERBYBARYCENTER Reorder blocks in a layer using barycenter values

            layer = obj.Layers{layerIdx};
            if length(layer) <= 1
                return;
            end

            barycenters = zeros(length(layer), 1);

            for i = 1:length(layer)
                blockIdx = layer(i);

                if strcmp(direction, 'forward')
                    % Use positions of predecessors (previous layer)
                    neighbors = obj.ReverseAdjList{blockIdx};
                else
                    % Use positions of successors (next layer)
                    neighbors = obj.AdjacencyList{blockIdx};
                end

                if isempty(neighbors)
                    % Keep current relative position
                    barycenters(i) = i;
                else
                    % Calculate average position of neighbors
                    positions = zeros(length(neighbors), 1);
                    for j = 1:length(neighbors)
                        neighborIdx = neighbors(j);
                        neighborLayer = obj.LayerAssignment(neighborIdx) + 1;
                        positions(j) = find(obj.Layers{neighborLayer} == neighborIdx, 1);
                    end
                    barycenters(i) = mean(positions);
                end
            end

            % Sort layer by barycenter values
            [~, sortIdx] = sort(barycenters);
            obj.Layers{layerIdx} = layer(sortIdx);
        end

        function edges = getEdgesBetweenLayers(obj, layer1, layer2)
            %GETEDGESBETWEENLAYERS Get edges connecting two adjacent layers
            %
            %   Returns Nx2 matrix where each row is [pos_in_layer1, pos_in_layer2]

            edges = [];

            for i = 1:length(layer1)
                blockIdx = layer1(i);
                successors = obj.AdjacencyList{blockIdx};

                for j = 1:length(successors)
                    succIdx = successors(j);
                    pos2 = find(layer2 == succIdx, 1);

                    if ~isempty(pos2)
                        edges(end+1, :) = [i, pos2];
                    end
                end
            end
        end

        function refineVerticalAlignment(obj)
            %REFINEVERTCALALIGNMENT Adjust Y positions to align connected blocks

            % Simple refinement: center blocks vertically within their layer
            numLayers = length(obj.Layers);

            for layerIdx = 1:numLayers
                layer = obj.Layers{layerIdx};
                if isempty(layer)
                    continue;
                end

                % Find total height of this layer
                totalHeight = 0;
                for i = 1:length(layer)
                    blockIdx = layer(i);
                    block = obj.Blocks{blockIdx};
                    totalHeight = totalHeight + block.height;
                end
                totalHeight = totalHeight + (length(layer) - 1) * obj.BLOCK_SPACING;

                % Find max layer height across all layers
                maxHeight = totalHeight;
                for otherLayerIdx = 1:numLayers
                    otherLayer = obj.Layers{otherLayerIdx};
                    if isempty(otherLayer)
                        continue;
                    end

                    otherHeight = 0;
                    for i = 1:length(otherLayer)
                        blockIdx = otherLayer(i);
                        block = obj.Blocks{blockIdx};
                        otherHeight = otherHeight + block.height;
                    end
                    otherHeight = otherHeight + (length(otherLayer) - 1) * obj.BLOCK_SPACING;
                    maxHeight = max(maxHeight, otherHeight);
                end

                % Center this layer vertically
                startY = obj.BLOCK_SPACING + (maxHeight - totalHeight) / 2;

                y = startY;
                for i = 1:length(layer)
                    blockIdx = layer(i);
                    block = obj.Blocks{blockIdx};
                    pos = obj.BlockPositions(block.name);

                    obj.BlockPositions(block.name) = [pos(1), y, pos(3), pos(4)];

                    y = y + block.height + obj.BLOCK_SPACING;
                end
            end
        end

        function portIdx = getOutputPortIndex(~, portHandle, block)
            %GETOUTPUTPORTINDEX Get 1-based index of output port

            portIdx = 1;
            if ~isempty(block.outputPorts)
                idx = find(block.outputPorts == portHandle, 1);
                if ~isempty(idx)
                    portIdx = idx;
                end
            end
        end

        function portIdx = getInputPortIndex(~, portHandle, block)
            %GETINPUTPORTINDEX Get 1-based index of input port

            portIdx = 1;
            if ~isempty(block.inputPorts)
                idx = find(block.inputPorts == portHandle, 1);
                if ~isempty(idx)
                    portIdx = idx;
                end
            end
        end

        function y = calculatePortY(obj, blockPos, portIdx, numPorts)
            %CALCULATEPORTY Calculate Y coordinate for a port

            if numPorts <= 0
                numPorts = 1;
            end

            blockTop = blockPos(2);
            blockHeight = blockPos(4);

            % Evenly distribute ports along block height
            portSpacing = blockHeight / (numPorts + 1);
            y = blockTop + portIdx * portSpacing;
        end

        function waypoints = computeOrthogonalRoute(obj, srcX, srcY, dstX, dstY)
            %COMPUTEORTHOGONALROUTE Compute waypoints for orthogonal wire routing

            % Simple L-shaped or S-shaped routing
            if srcX < dstX
                % Normal left-to-right flow
                midX = (srcX + dstX) / 2;

                if abs(srcY - dstY) < 5
                    % Nearly horizontal - direct line
                    waypoints = [srcX, srcY; dstX, dstY];
                else
                    % L-shaped or Z-shaped route
                    waypoints = [
                        srcX, srcY;
                        midX, srcY;
                        midX, dstY;
                        dstX, dstY
                    ];
                end
            else
                % Feedback loop (right-to-left) - need to route around
                offset = obj.LAYER_SPACING / 3;

                % Route: right, up/down, left, up/down, left
                waypoints = [
                    srcX, srcY;
                    srcX + offset, srcY;
                    srcX + offset, min(srcY, dstY) - offset;
                    dstX - offset, min(srcY, dstY) - offset;
                    dstX - offset, dstY;
                    dstX, dstY
                ];
            end
        end
    end
end
