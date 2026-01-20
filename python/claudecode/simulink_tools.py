"""
Simulink MCP Tools - Custom tools for Claude to interact with Simulink models.

These tools allow Claude to query and modify Simulink models through
the MATLAB Engine API.
"""

from typing import Any, Dict

from claude_agent_sdk import tool
from .matlab_engine import get_engine
from .logger import get_logger

_logger = get_logger()


@tool(
    "simulink_query",
    "Query information about a Simulink model. Can list blocks, get parameters, show connections, or describe subsystems.",
    {"model": str, "query_type": str, "block_path": str}
)
async def simulink_query(args: Dict[str, Any]) -> Dict[str, Any]:
    """Query Simulink model structure and properties."""
    engine = get_engine()
    model = str(args.get("model", ""))
    query_type = str(args.get("query_type", "blocks"))
    block_path = args.get("block_path", "")

    _logger.debug("simulink_tools", "model_query", {"model": model, "query_type": query_type, "block_path": block_path})

    if not model:
        return {
            "content": [{"type": "text", "text": "Error: Model name required"}],
            "isError": True
        }

    try:
        if not engine.is_connected:
            engine.connect()

        # Ensure model is loaded
        engine.eval(f"load_system('{model}')", capture_output=False)

        if query_type == "info":
            # Get basic model info
            result = engine.eval(f"""
                info = struct();
                info.name = '{model}';
                info.blocks = length(find_system('{model}', 'SearchDepth', 1, 'Type', 'block'));
                info.subsystems = length(find_system('{model}', 'BlockType', 'SubSystem'));
                disp(['Model: ', info.name]);
                disp(['Blocks (top level): ', num2str(info.blocks)]);
                disp(['Subsystems: ', num2str(info.subsystems)]);
            """)
            return {"content": [{"type": "text", "text": result}]}

        elif query_type == "blocks":
            # List all blocks at top level
            result = engine.eval(f"""
                blocks = find_system('{model}', 'SearchDepth', 1, 'Type', 'block');
                for i = 1:length(blocks)
                    blockType = get_param(blocks{{i}}, 'BlockType');
                    disp([blocks{{i}}, ' (', blockType, ')']);
                end
            """)
            return {"content": [{"type": "text", "text": f"Blocks in {model}:\n{result}"}]}

        elif query_type == "connections":
            # Show signal connections
            result = engine.eval(f"""
                lines = find_system('{model}', 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'line');
                disp(['Found ', num2str(length(lines)), ' signal lines']);
                for i = 1:min(length(lines), 20)
                    srcBlock = get_param(lines(i), 'SrcBlockHandle');
                    dstBlock = get_param(lines(i), 'DstBlockHandle');
                    if srcBlock > 0 && dstBlock > 0
                        srcName = get_param(srcBlock, 'Name');
                        dstName = get_param(dstBlock, 'Name');
                        disp([srcName, ' -> ', dstName]);
                    end
                end
            """)
            return {"content": [{"type": "text", "text": f"Connections in {model}:\n{result}"}]}

        elif query_type == "parameters":
            # Get block parameters
            if not block_path:
                block_path = model

            result = engine.eval(f"""
                params = get_param('{block_path}', 'ObjectParameters');
                fn = fieldnames(params);
                for i = 1:min(length(fn), 30)
                    try
                        val = get_param('{block_path}', fn{{i}});
                        if ischar(val) || isstring(val)
                            disp([fn{{i}}, ': ', char(val)]);
                        elseif isnumeric(val) && numel(val) == 1
                            disp([fn{{i}}, ': ', num2str(val)]);
                        end
                    catch
                    end
                end
            """)
            return {"content": [{"type": "text", "text": f"Parameters for {block_path}:\n{result}"}]}

        elif query_type == "subsystem":
            # Describe subsystem contents
            path = block_path if block_path else model
            result = engine.eval(f"""
                blocks = find_system('{path}', 'SearchDepth', 1, 'Type', 'block');
                disp(['Subsystem: {path}']);
                disp(['Contains ', num2str(length(blocks)-1), ' blocks:']);
                for i = 1:length(blocks)
                    if ~strcmp(blocks{{i}}, '{path}')
                        blockType = get_param(blocks{{i}}, 'BlockType');
                        [~, name] = fileparts(blocks{{i}});
                        disp(['  ', name, ' (', blockType, ')']);
                    end
                end
            """)
            return {"content": [{"type": "text", "text": result}]}

        else:
            return {
                "content": [{"type": "text", "text": f"Error: Unknown query type '{query_type}'"}],
                "isError": True
            }

    except Exception as e:
        return {
            "content": [{"type": "text", "text": f"Simulink Error: {str(e)}"}],
            "isError": True
        }


@tool(
    "simulink_modify",
    "Modify a Simulink model by adding blocks, deleting blocks, connecting signals, or setting parameters.",
    {"model": str, "action": str, "params": dict}
)
async def simulink_modify(args: Dict[str, Any]) -> Dict[str, Any]:
    """Modify a Simulink model."""
    engine = get_engine()
    model = str(args.get("model", ""))
    action = str(args.get("action", ""))
    params = args.get("params", {})

    _logger.info("simulink_tools", "model_modify", {"model": model, "action": action})

    if not model:
        return {
            "content": [{"type": "text", "text": "Error: Model name required"}],
            "isError": True
        }

    if not action:
        return {
            "content": [{"type": "text", "text": "Error: Action required"}],
            "isError": True
        }

    try:
        if not engine.is_connected:
            engine.connect()

        # Ensure model is loaded
        engine.eval(f"load_system('{model}')", capture_output=False)

        if action == "add_block":
            source = params.get("source", "")
            name = params.get("name", "NewBlock")
            destination = f"{model}/{name}"

            if not source:
                return {
                    "content": [{"type": "text", "text": "Error: source block library path required (e.g., 'simulink/Sources/Constant')"}],
                    "isError": True
                }

            engine.eval(f"add_block('{source}', '{destination}')", capture_output=False)
            return {"content": [{"type": "text", "text": f"Added block '{name}' from '{source}'"}]}

        elif action == "delete_block":
            block_path = params.get("block_path", "")
            if not block_path:
                return {
                    "content": [{"type": "text", "text": "Error: block_path required"}],
                    "isError": True
                }

            engine.eval(f"delete_block('{block_path}')", capture_output=False)
            return {"content": [{"type": "text", "text": f"Deleted block '{block_path}'"}]}

        elif action == "connect":
            src_block = params.get("src_block", "")
            src_port = params.get("src_port", 1)
            dst_block = params.get("dst_block", "")
            dst_port = params.get("dst_port", 1)

            if not src_block or not dst_block:
                return {
                    "content": [{"type": "text", "text": "Error: src_block and dst_block required"}],
                    "isError": True
                }

            # Use add_line to connect
            engine.eval(
                f"add_line('{model}', '{src_block}/{src_port}', '{dst_block}/{dst_port}')",
                capture_output=False
            )
            return {"content": [{"type": "text", "text": f"Connected {src_block}/{src_port} to {dst_block}/{dst_port}"}]}

        elif action == "set_param":
            block_path = params.get("block_path", "")
            param_name = params.get("param_name", "")
            value = params.get("value", "")

            if not block_path or not param_name:
                return {
                    "content": [{"type": "text", "text": "Error: block_path and param_name required"}],
                    "isError": True
                }

            # Handle string vs numeric values
            if isinstance(value, str):
                engine.eval(f"set_param('{block_path}', '{param_name}', '{value}')", capture_output=False)
            else:
                engine.eval(f"set_param('{block_path}', '{param_name}', {value})", capture_output=False)

            return {"content": [{"type": "text", "text": f"Set {param_name}={value} on {block_path}"}]}

        elif action == "save":
            engine.eval(f"save_system('{model}')", capture_output=False)
            return {"content": [{"type": "text", "text": f"Saved model '{model}'"}]}

        else:
            return {
                "content": [{"type": "text", "text": f"Error: Unknown action '{action}'"}],
                "isError": True
            }

    except Exception as e:
        return {
            "content": [{"type": "text", "text": f"Simulink Error: {str(e)}"}],
            "isError": True
        }


@tool(
    "simulink_layout",
    "Optimize Simulink model layout for better readability. Produces clean diagrams with 90-degree wire angles, minimal crossings, and logical left-to-right signal flow.",
    {"model": str, "action": str, "spacing": int}
)
async def simulink_layout(args: Dict[str, Any]) -> Dict[str, Any]:
    """Optimize or arrange Simulink model layout."""
    engine = get_engine()
    model = str(args.get("model", ""))
    action = str(args.get("action", "optimize"))
    spacing = int(args.get("spacing", 50))

    _logger.info("simulink_tools", "layout_action", {"model": model, "action": action, "spacing": spacing})

    if not model:
        return {
            "content": [{"type": "text", "text": "Error: Model name required"}],
            "isError": True
        }

    try:
        if not engine.is_connected:
            engine.connect()

        # Ensure model is loaded
        engine.eval(f"load_system('{model}')", capture_output=False)

        if action == "optimize":
            # Use custom layout engine for optimal arrangement
            result = engine.eval(f"""
                bridge = claudecode.SimulinkBridge();
                bridge.setCurrentModel('{model}');
                result = bridge.optimizeLayout('Spacing', {spacing});
                disp(['Success: ', num2str(result.success)]);
                disp(['Message: ', result.message]);
                disp(['Blocks processed: ', num2str(result.blocksProcessed)]);
                disp(['Edges processed: ', num2str(result.edgesProcessed)]);
            """)
            return {"content": [{"type": "text", "text": f"Layout optimization for {model}:\n{result}"}]}

        elif action == "arrange":
            # Use Simulink's built-in arrangement
            engine.eval(f"Simulink.BlockDiagram.arrangeSystem('{model}')", capture_output=False)
            return {"content": [{"type": "text", "text": f"Arranged model '{model}' using Simulink auto-arrange"}]}

        elif action == "info":
            # Get layout information
            result = engine.eval(f"""
                blocks = find_system('{model}', 'SearchDepth', 1, 'Type', 'block');
                lines = find_system('{model}', 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'line');
                disp(['Model: {model}']);
                disp(['Blocks: ', num2str(length(blocks)-1)]);
                disp(['Signal lines: ', num2str(length(lines))]);

                % Calculate bounding box
                minX = inf; minY = inf; maxX = -inf; maxY = -inf;
                for i = 1:length(blocks)
                    if ~strcmp(blocks{{i}}, '{model}')
                        pos = get_param(blocks{{i}}, 'Position');
                        minX = min(minX, pos(1));
                        minY = min(minY, pos(2));
                        maxX = max(maxX, pos(3));
                        maxY = max(maxY, pos(4));
                    end
                end
                if minX ~= inf
                    disp(['Diagram bounds: [', num2str(minX), ', ', num2str(minY), '] to [', num2str(maxX), ', ', num2str(maxY), ']']);
                    disp(['Diagram size: ', num2str(maxX-minX), ' x ', num2str(maxY-minY), ' pixels']);
                end
            """)
            return {"content": [{"type": "text", "text": result}]}

        else:
            return {
                "content": [{"type": "text", "text": f"Error: Unknown action '{action}'. Valid actions: optimize, arrange, info"}],
                "isError": True
            }

    except Exception as e:
        return {
            "content": [{"type": "text", "text": f"Simulink Layout Error: {str(e)}"}],
            "isError": True
        }


# List of all Simulink tools for easy importing
SIMULINK_TOOLS = [simulink_query, simulink_modify, simulink_layout]
