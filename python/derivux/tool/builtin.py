"""
Built-in Tool Definitions - Registers all standard tools in the global registry.

This module defines and registers:
- Claude Code built-in tools (Bash, Read, Write, Glob, Grep)
- MATLAB MCP tools (matlab_execute, matlab_workspace, matlab_plot)
- Simulink MCP tools (simulink_query, simulink_modify)
- File MCP tools (file_read, file_write, file_list, file_mkdir)

Call `register_builtin_tools()` to populate the global Tool registry.
"""

from .registry import Tool


def register_builtin_tools() -> None:
    """Register all built-in tools in the global registry.

    This function is idempotent - calling it multiple times is safe.
    """
    # =========================================================================
    # Claude Code Built-in Tools
    # =========================================================================

    Tool.register(
        "Bash",
        description="Execute bash commands in a shell",
        is_builtin=True,
        category="system",
        is_read_only=False,
    )

    Tool.register(
        "Read",
        description="Read file contents from the filesystem",
        is_builtin=True,
        category="file",
        is_read_only=True,
    )

    Tool.register(
        "Write",
        description="Write or create files on the filesystem",
        is_builtin=True,
        category="file",
        is_read_only=False,
    )

    Tool.register(
        "Glob",
        description="Find files matching glob patterns",
        is_builtin=True,
        category="file",
        is_read_only=True,
    )

    Tool.register(
        "Grep",
        description="Search for patterns in file contents",
        is_builtin=True,
        category="file",
        is_read_only=True,
    )

    # =========================================================================
    # MATLAB MCP Tools
    # =========================================================================

    Tool.register(
        "matlab_execute",
        description="Execute MATLAB code and return the output",
        parameters={
            "type": "object",
            "properties": {
                "code": {
                    "type": "string",
                    "description": "MATLAB code to execute"
                }
            },
            "required": ["code"]
        },
        is_mcp=True,
        category="matlab",
        is_read_only=False,
    )

    Tool.register(
        "matlab_workspace",
        description="List, read, or write variables in the MATLAB workspace",
        parameters={
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "enum": ["list", "read", "write"],
                    "description": "Action to perform"
                },
                "variable": {
                    "type": "string",
                    "description": "Variable name (required for read/write)"
                },
                "value": {
                    "type": "string",
                    "description": "Value to write (required for write)"
                }
            },
            "required": ["action"]
        },
        is_mcp=True,
        category="matlab",
        is_read_only=True,  # Read-only for list/read, but supports write
    )

    Tool.register(
        "matlab_plot",
        description="Generate MATLAB plots and visualizations",
        parameters={
            "type": "object",
            "properties": {
                "code": {
                    "type": "string",
                    "description": "MATLAB plotting code"
                }
            },
            "required": ["code"]
        },
        is_mcp=True,
        category="matlab",
        is_read_only=False,
    )

    # =========================================================================
    # Simulink MCP Tools
    # =========================================================================

    Tool.register(
        "simulink_query",
        description="Query Simulink model structure, blocks, and connections",
        parameters={
            "type": "object",
            "properties": {
                "model": {
                    "type": "string",
                    "description": "Model name or path"
                },
                "query_type": {
                    "type": "string",
                    "enum": ["info", "blocks", "connections", "parameters"],
                    "description": "Type of query"
                },
                "block_path": {
                    "type": "string",
                    "description": "Optional block path for detailed queries"
                }
            },
            "required": ["model", "query_type"]
        },
        is_mcp=True,
        category="simulink",
        is_read_only=True,
    )

    Tool.register(
        "simulink_modify",
        description="Add blocks, connect signals, and set parameters in Simulink models",
        parameters={
            "type": "object",
            "properties": {
                "model": {
                    "type": "string",
                    "description": "Model name or path"
                },
                "action": {
                    "type": "string",
                    "enum": ["add_block", "delete_block", "connect", "set_param"],
                    "description": "Modification action"
                },
                "params": {
                    "type": "object",
                    "description": "Action-specific parameters"
                }
            },
            "required": ["model", "action"]
        },
        is_mcp=True,
        category="simulink",
        is_read_only=False,
    )

    # =========================================================================
    # File MCP Tools (MATLAB directory restricted)
    # =========================================================================

    Tool.register(
        "file_read",
        description="Read file contents in MATLAB's current directory",
        parameters={
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Relative path to file"
                }
            },
            "required": ["path"]
        },
        is_mcp=True,
        category="file",
        is_read_only=True,
    )

    Tool.register(
        "file_write",
        description="Write or create files in MATLAB's current directory",
        parameters={
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Relative path to file"
                },
                "content": {
                    "type": "string",
                    "description": "Content to write"
                }
            },
            "required": ["path", "content"]
        },
        is_mcp=True,
        category="file",
        is_read_only=False,
    )

    Tool.register(
        "file_list",
        description="List directory contents with glob pattern support",
        parameters={
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Directory path (default: current)"
                },
                "pattern": {
                    "type": "string",
                    "description": "Optional glob pattern"
                }
            }
        },
        is_mcp=True,
        category="file",
        is_read_only=True,
    )

    Tool.register(
        "file_mkdir",
        description="Create directories in MATLAB's current directory",
        parameters={
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Directory path to create"
                }
            },
            "required": ["path"]
        },
        is_mcp=True,
        category="file",
        is_read_only=False,
    )


# Tool name constants for convenience (matches existing ToolNames pattern)
class ToolNames:
    """Constants for tool names used throughout the codebase.

    This provides a single source of truth for tool name strings,
    preventing typos and enabling IDE autocomplete.
    """

    # Claude Code built-in tools
    BASH = "Bash"
    READ = "Read"
    WRITE = "Write"
    GLOB = "Glob"
    GREP = "Grep"

    # MATLAB MCP tools
    MATLAB_EXECUTE = "matlab_execute"
    MATLAB_WORKSPACE = "matlab_workspace"
    MATLAB_PLOT = "matlab_plot"

    # Simulink MCP tools
    SIMULINK_QUERY = "simulink_query"
    SIMULINK_MODIFY = "simulink_modify"

    # File MCP tools
    FILE_READ = "file_read"
    FILE_WRITE = "file_write"
    FILE_LIST = "file_list"
    FILE_MKDIR = "file_mkdir"

    @classmethod
    def all_matlab_tools(cls) -> list:
        """Get all MATLAB-related tool names."""
        return [cls.MATLAB_EXECUTE, cls.MATLAB_WORKSPACE, cls.MATLAB_PLOT]

    @classmethod
    def all_simulink_tools(cls) -> list:
        """Get all Simulink-related tool names."""
        return [cls.SIMULINK_QUERY, cls.SIMULINK_MODIFY]

    @classmethod
    def all_file_tools(cls) -> list:
        """Get all file operation tool names."""
        return [
            cls.FILE_READ, cls.FILE_WRITE, cls.FILE_LIST, cls.FILE_MKDIR,
            cls.READ, cls.WRITE, cls.GLOB, cls.GREP,
        ]

    @classmethod
    def read_only_tools(cls) -> list:
        """Get read-only tool names."""
        return [
            cls.READ, cls.GLOB, cls.GREP,
            cls.FILE_READ, cls.FILE_LIST,
            cls.MATLAB_WORKSPACE, cls.SIMULINK_QUERY,
        ]

    @classmethod
    def write_tools(cls) -> list:
        """Get tools that can modify state."""
        return [
            cls.BASH, cls.WRITE,
            cls.MATLAB_EXECUTE, cls.MATLAB_PLOT,
            cls.SIMULINK_MODIFY,
            cls.FILE_WRITE, cls.FILE_MKDIR,
        ]

    @classmethod
    def all_tools(cls) -> list:
        """Get all tool names."""
        return (
            [cls.BASH, cls.READ, cls.WRITE, cls.GLOB, cls.GREP] +
            cls.all_matlab_tools() +
            cls.all_simulink_tools() +
            [cls.FILE_READ, cls.FILE_WRITE, cls.FILE_LIST, cls.FILE_MKDIR]
        )
