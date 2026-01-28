"""
MATLAB MCP Tools - Custom tools for Claude to interact with MATLAB.

These tools use the @tool decorator from claude-agent-sdk to create
in-process MCP tools that Claude can use autonomously.
"""

import base64
import tempfile
import os
import time
from typing import Any, Dict

from claude_agent_sdk import tool
from .matlab_engine import get_engine
from .image_queue import push_image
from .logger import get_logger

_logger = get_logger()

# Global headless mode setting (controlled by bridge.py)
_headless_mode: bool = True


def set_headless_mode(enabled: bool) -> None:
    """Set the global headless mode for figure suppression.

    Args:
        enabled: If True, figures will not appear on screen during execution.
    """
    global _headless_mode
    _headless_mode = enabled
    _logger.debug("matlab_tools", "headless_mode_set", {"enabled": enabled})


def get_headless_mode() -> bool:
    """Get the current headless mode setting."""
    return _headless_mode


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


def _capture_figure(engine, fig_handle: int, fmt: str = "png", close_after: bool = True) -> Dict[str, Any]:
    """Capture a figure as base64-encoded image.

    Args:
        engine: MATLAB engine instance
        fig_handle: Handle of the figure to capture
        fmt: Image format ('png' or 'svg')
        close_after: Whether to close the figure after capturing

    Returns:
        Dict with image content block
    """
    with tempfile.NamedTemporaryFile(suffix=f".{fmt}", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        # Ensure figure stays invisible during capture (defense in depth)
        # This handles edge cases where headless mode might not be fully applied
        if get_headless_mode():
            engine.eval(f"set({fig_handle}, 'Visible', 'off');", capture_output=False)

        # Use print command for better quality output
        if fmt == "png":
            # Use print with higher resolution for better quality
            engine.eval(
                f"print({fig_handle}, '-dpng', '-r150', '{tmp_path}')",
                capture_output=False
            )
        else:
            engine.eval(f"saveas({fig_handle}, '{tmp_path}')", capture_output=False)

        # Close the figure to avoid cluttering the desktop
        if close_after:
            engine.eval(f"close({fig_handle});", capture_output=False)

        # Read and encode the image
        with open(tmp_path, "rb") as f:
            image_data = f.read()

        base64_image = base64.b64encode(image_data).decode("utf-8")
        media_type = "image/png" if fmt == "png" else "image/svg+xml"

        image_block = {
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": media_type,
                "data": base64_image
            }
        }

        # Push to the image queue for direct delivery to UI
        push_image(image_block)

        return image_block
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


def _format_matrix_output(engine, output: str) -> str:
    """Format matrix output for nicer display.

    Attempts to detect matrix-like output and format it as a readable table.
    """
    if not output or not output.strip():
        return output

    lines = output.strip().split('\n')

    # Check if this looks like a matrix output (multiple lines of numbers)
    # MATLAB matrices typically have consistent column spacing
    is_matrix = True
    matrix_rows = []

    for line in lines:
        line = line.strip()
        if not line:
            continue

        # Try to parse as space-separated numbers
        parts = line.split()
        row_values = []
        for part in parts:
            try:
                # Handle various number formats
                val = float(part.replace('i', 'j'))  # complex numbers
                row_values.append(part)
            except ValueError:
                is_matrix = False
                break

        if is_matrix and row_values:
            matrix_rows.append(row_values)

    # If we detected a matrix with multiple rows and consistent columns
    if is_matrix and len(matrix_rows) > 1:
        # Check for consistent column count
        col_counts = [len(row) for row in matrix_rows]
        if len(set(col_counts)) == 1 and col_counts[0] > 1:
            # Format as aligned columns
            num_cols = col_counts[0]

            # Find max width for each column
            col_widths = []
            for col in range(num_cols):
                max_width = max(len(row[col]) for row in matrix_rows)
                col_widths.append(max_width)

            # Build formatted output
            formatted_lines = []
            for row in matrix_rows:
                formatted_row = "  ".join(
                    val.rjust(col_widths[i]) for i, val in enumerate(row)
                )
                formatted_lines.append(f"    {formatted_row}")

            return "\n".join(formatted_lines)

    return output


@tool(
    "matlab_execute",
    "Execute MATLAB code in the workspace and return the output. Use this to run MATLAB commands, create variables, perform calculations, etc. Any figures created will be automatically captured and returned as images.",
    {"code": str, "capture_output": bool, "capture_figures": bool, "format_output": bool}
)
async def matlab_execute(args: Dict[str, Any]) -> Dict[str, Any]:
    """Execute MATLAB code and return the result, including any new figures."""
    engine = get_engine()
    code = str(args.get("code", ""))
    capture = args.get("capture_output", True)
    capture_figures = args.get("capture_figures", True)
    format_output = args.get("format_output", True)

    start_time = time.perf_counter()
    _logger.debug("matlab_tools", "execute_called", {
        "code_length": len(code),
        "capture_output": capture,
        "capture_figures": capture_figures
    })

    if not code.strip():
        _logger.warn("matlab_tools", "execute_empty_code")
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

        # Apply headless mode - suppress figure windows during execution
        if _headless_mode:
            engine.eval("__claude_prev_visible = get(0, 'DefaultFigureVisible');", capture_output=False)
            engine.eval("set(0, 'DefaultFigureVisible', 'off');", capture_output=False)

        try:
            # Execute the code
            result = engine.eval(code, capture_output=capture)

            if not result:
                result = "Code executed successfully (no output)"
            elif format_output:
                # Try to format matrix output nicely
                result = _format_matrix_output(engine, result)

            content = [{"type": "text", "text": result}]

            # Capture any new figures WHILE STILL IN HEADLESS MODE
            # This prevents figures from flashing visible during capture
            figures_captured = 0
            if capture_figures:
                new_figs = _get_figure_handles(engine) - existing_figs

                # Force all new figures invisible before capture (handles user code
                # that explicitly set Visible='on')
                if _headless_mode and new_figs:
                    engine.eval("set(findall(0, 'Type', 'figure'), 'Visible', 'off');", capture_output=False)

                for fig_handle in sorted(new_figs):
                    try:
                        image_block = _capture_figure(engine, fig_handle, close_after=True)
                        content.append(image_block)
                        figures_captured += 1
                    except Exception as e:
                        content.append({"type": "text", "text": f"Failed to capture figure {fig_handle}: {e}"})
        finally:
            # Restore figure visibility setting AFTER capture is complete
            if _headless_mode:
                engine.eval("set(0, 'DefaultFigureVisible', __claude_prev_visible);", capture_output=False)
                engine.eval("clear __claude_prev_visible;", capture_output=False)

        duration_ms = (time.perf_counter() - start_time) * 1000
        _logger.info_timed("matlab_tools", "execute_complete", {
            "result_length": len(result),
            "figures_captured": figures_captured
        }, duration_ms)

        return {"content": content}

    except Exception as e:
        duration_ms = (time.perf_counter() - start_time) * 1000
        _logger.error("matlab_tools", "execute_error", {
            "error": str(e),
            "code_length": len(code)
        })
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

    _logger.debug("matlab_tools", "workspace_called", {
        "action": action,
        "variable": variable if action != "write" else "<redacted>"
    })

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

    start_time = time.perf_counter()
    _logger.debug("matlab_tools", "plot_called", {
        "code_length": len(code),
        "format": fmt
    })

    if not code.strip():
        return {
            "content": [{"type": "text", "text": "Error: No plotting code provided"}],
            "isError": True
        }

    try:
        if not engine.is_connected:
            engine.connect()

        # Apply headless mode - suppress figure windows during plotting
        if _headless_mode:
            engine.eval("__claude_prev_visible = get(0, 'DefaultFigureVisible');", capture_output=False)
            engine.eval("set(0, 'DefaultFigureVisible', 'off');", capture_output=False)

        try:
            # Create a new figure to ensure clean state
            engine.eval("figure;", capture_output=False)

            # Defense in depth: explicitly set the new figure invisible
            # (handles edge cases where DefaultFigureVisible might not fully apply)
            if _headless_mode:
                engine.eval("set(gcf, 'Visible', 'off');", capture_output=False)

            # Execute the plotting code
            engine.eval(code, capture_output=False)

            # Hide any figures that user code may have made visible before capture
            if _headless_mode:
                engine.eval("set(gcf, 'Visible', 'off');", capture_output=False)

            # Save to temporary file
            with tempfile.NamedTemporaryFile(suffix=f".{fmt}", delete=False) as tmp:
                tmp_path = tmp.name

            try:
                # Use print for higher quality output
                if fmt == "png":
                    engine.eval(f"print(gcf, '-dpng', '-r150', '{tmp_path}')", capture_output=False)
                else:
                    engine.eval(f"saveas(gcf, '{tmp_path}')", capture_output=False)
                engine.eval("close(gcf);", capture_output=False)

                # Read and encode the image
                with open(tmp_path, "rb") as f:
                    image_data = f.read()

                base64_image = base64.b64encode(image_data).decode("utf-8")
                media_type = "image/png" if fmt == "png" else "image/svg+xml"

                image_block = {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": media_type,
                        "data": base64_image
                    }
                }

                # Push to the image queue for direct delivery to UI
                push_image(image_block)

                duration_ms = (time.perf_counter() - start_time) * 1000
                _logger.info_timed("matlab_tools", "figure_captured", {
                    "format": fmt,
                    "image_size_bytes": len(image_data)
                }, duration_ms)

                return {
                    "content": [
                        image_block,
                        {"type": "text", "text": "Plot generated successfully."}
                    ]
                }

            finally:
                # Clean up temp file
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)

        finally:
            # Restore figure visibility setting
            if _headless_mode:
                engine.eval("set(0, 'DefaultFigureVisible', __claude_prev_visible);", capture_output=False)
                engine.eval("clear __claude_prev_visible;", capture_output=False)

    except Exception as e:
        _logger.error("matlab_tools", "plot_error", {
            "error": str(e)
        })
        return {
            "content": [{"type": "text", "text": f"MATLAB Plot Error: {str(e)}"}],
            "isError": True
        }


# List of all MATLAB tools for easy importing
MATLAB_TOOLS = [matlab_execute, matlab_workspace, matlab_plot]
