"""
MATLAB MCP Tools - Custom tools for Claude to interact with MATLAB.

These tools use the @tool decorator from claude-agent-sdk to create
in-process MCP tools that Claude can use autonomously.
"""

import base64
import tempfile
import os
from typing import Any, Dict

from claude_agent_sdk import tool
from .matlab_engine import get_engine


def _get_figure_handles(engine) -> set:
    """Get set of current figure handles."""
    try:
        # Get all figure handles as a MATLAB array
        handles_str = engine.eval("num2str(findall(0, 'Type', 'figure')')", capture_output=True)
        if handles_str and handles_str.strip():
            return set(int(float(h)) for h in handles_str.split() if h.strip())
    except Exception:
        pass
    return set()


def _capture_figure(engine, fig_handle: int, fmt: str = "png") -> Dict[str, Any]:
    """Capture a figure as base64-encoded image."""
    with tempfile.NamedTemporaryFile(suffix=f".{fmt}", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        # Save the figure
        engine.eval(f"saveas({fig_handle}, '{tmp_path}')", capture_output=False)

        # Read and encode the image
        with open(tmp_path, "rb") as f:
            image_data = f.read()

        base64_image = base64.b64encode(image_data).decode("utf-8")
        media_type = "image/png" if fmt == "png" else "image/svg+xml"

        return {
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": media_type,
                "data": base64_image
            }
        }
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


@tool(
    "matlab_execute",
    "Execute MATLAB code in the workspace and return the output. Use this to run MATLAB commands, create variables, perform calculations, etc. Any figures created will be automatically captured and returned as images.",
    {"code": str, "capture_output": bool, "capture_figures": bool}
)
async def matlab_execute(args: Dict[str, Any]) -> Dict[str, Any]:
    """Execute MATLAB code and return the result, including any new figures."""
    engine = get_engine()
    code = str(args.get("code", ""))
    capture = args.get("capture_output", True)
    capture_figures = args.get("capture_figures", True)

    if not code.strip():
        return {
            "content": [{"type": "text", "text": "Error: No code provided"}],
            "isError": True
        }

    try:
        # Ensure connected
        if not engine.is_connected:
            engine.connect()

        # Get existing figure handles before execution
        existing_figs = _get_figure_handles(engine) if capture_figures else set()

        # Execute the code
        result = engine.eval(code, capture_output=capture)

        if not result:
            result = "Code executed successfully (no output)"

        content = [{"type": "text", "text": result}]

        # Capture any new figures
        if capture_figures:
            new_figs = _get_figure_handles(engine) - existing_figs
            for fig_handle in sorted(new_figs):
                try:
                    image_block = _capture_figure(engine, fig_handle)
                    content.append(image_block)
                    content.append({"type": "text", "text": f"Figure {fig_handle} captured."})
                except Exception as e:
                    content.append({"type": "text", "text": f"Failed to capture figure {fig_handle}: {e}"})

        return {"content": content}

    except Exception as e:
        return {
            "content": [{"type": "text", "text": f"MATLAB Error: {str(e)}"}],
            "isError": True
        }


@tool(
    "matlab_workspace",
    "Read, write, or list variables in the MATLAB workspace.",
    {"action": str, "variable": str, "value": str}
)
async def matlab_workspace(args: Dict[str, Any]) -> Dict[str, Any]:
    """Read, write, or list MATLAB workspace variables."""
    engine = get_engine()
    action = str(args.get("action", "list"))
    variable = args.get("variable", "")
    value = args.get("value")

    try:
        if not engine.is_connected:
            engine.connect()

        if action == "list":
            variables = engine.list_variables()
            if not variables:
                return {"content": [{"type": "text", "text": "Workspace is empty"}]}

            # Get info for each variable
            var_info = []
            for var in variables:
                info = engine.get_variable_info(var)
                var_info.append(f"  {var}: {info.get('class', 'unknown')} {info.get('size', '')}")

            result = "Workspace variables:\n" + "\n".join(var_info)
            return {"content": [{"type": "text", "text": result}]}

        elif action == "read":
            if not variable:
                return {
                    "content": [{"type": "text", "text": "Error: variable name required for read"}],
                    "isError": True
                }

            val = engine.get_variable(variable)
            result = f"{variable} = {val}"
            return {"content": [{"type": "text", "text": result}]}

        elif action == "write":
            if not variable:
                return {
                    "content": [{"type": "text", "text": "Error: variable name required for write"}],
                    "isError": True
                }
            if value is None:
                return {
                    "content": [{"type": "text", "text": "Error: value required for write"}],
                    "isError": True
                }

            engine.set_variable(variable, value)
            return {"content": [{"type": "text", "text": f"Set {variable} = {value}"}]}

        else:
            return {
                "content": [{"type": "text", "text": f"Error: Unknown action '{action}'"}],
                "isError": True
            }

    except Exception as e:
        return {
            "content": [{"type": "text", "text": f"MATLAB Error: {str(e)}"}],
            "isError": True
        }


@tool(
    "matlab_plot",
    "Execute MATLAB plotting code and capture the resulting figure as an image. Returns a base64-encoded PNG image.",
    {"code": str, "format": str}
)
async def matlab_plot(args: Dict[str, Any]) -> Dict[str, Any]:
    """Execute plotting code and return figure as base64 image."""
    engine = get_engine()
    code = str(args.get("code", ""))
    fmt = args.get("format", "png")

    if not code.strip():
        return {
            "content": [{"type": "text", "text": "Error: No plotting code provided"}],
            "isError": True
        }

    try:
        if not engine.is_connected:
            engine.connect()

        # Create a new figure to ensure clean state
        engine.eval("figure;", capture_output=False)

        # Execute the plotting code
        engine.eval(code, capture_output=False)

        # Save to temporary file
        with tempfile.NamedTemporaryFile(suffix=f".{fmt}", delete=False) as tmp:
            tmp_path = tmp.name

        try:
            # Save the figure
            engine.eval(f"saveas(gcf, '{tmp_path}')", capture_output=False)
            engine.eval("close(gcf);", capture_output=False)

            # Read and encode the image
            with open(tmp_path, "rb") as f:
                image_data = f.read()

            base64_image = base64.b64encode(image_data).decode("utf-8")
            media_type = "image/png" if fmt == "png" else "image/svg+xml"

            return {
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": media_type,
                            "data": base64_image
                        }
                    },
                    {"type": "text", "text": "Plot generated successfully."}
                ]
            }

        finally:
            # Clean up temp file
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

    except Exception as e:
        return {
            "content": [{"type": "text", "text": f"MATLAB Plot Error: {str(e)}"}],
            "isError": True
        }


# List of all MATLAB tools for easy importing
MATLAB_TOOLS = [matlab_execute, matlab_workspace, matlab_plot]
