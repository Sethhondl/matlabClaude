"""
Tool Registry - Global tool registry using namespace singleton pattern.

Tools exist in a global registry. Agents don't "have" tools - the permission
system determines what tools each agent can use.

This follows the OpenCode pattern where tools are registered once and
permissions control access, rather than each agent having its own tool list.
"""

from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Set


@dataclass
class ToolDefinition:
    """Definition of a tool that can be used by agents.

    Attributes:
        name: Unique identifier for the tool (e.g., "matlab_execute")
        description: Human-readable description of what the tool does
        parameters: JSON Schema for tool parameters
        execute: Optional function to execute the tool (for custom tools)
        is_builtin: True if this is a Claude Code built-in tool
        is_mcp: True if this is an MCP-provided tool
        category: Tool category for grouping (e.g., "matlab", "simulink", "file")
        is_read_only: True if tool doesn't modify state
    """
    name: str
    description: str
    parameters: Dict[str, Any] = field(default_factory=dict)
    execute: Optional[Callable] = None
    is_builtin: bool = False
    is_mcp: bool = False
    category: str = "general"
    is_read_only: bool = False

    @property
    def qualified_name(self) -> str:
        """Get the fully qualified tool name for SDK usage.

        MCP tools use format: mcp__<server>__<tool>
        Built-in tools use their name directly.
        """
        if self.is_mcp:
            return f"mcp__matlab__{self.name}"
        return self.name


class _ToolRegistry:
    """Global tool registry (singleton).

    This class manages all tool definitions. Use the `Tool` module-level
    instance to interact with the registry.

    Example:
        Tool.register("my_tool", {...})
        tool = Tool.get("my_tool")
        all_tools = Tool.list()
    """

    _instance: Optional["_ToolRegistry"] = None

    def __new__(cls) -> "_ToolRegistry":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._tools: Dict[str, ToolDefinition] = {}
            cls._instance._initialized = False
        return cls._instance

    def register(
        self,
        name: str,
        definition: Optional[Dict[str, Any]] = None,
        *,
        description: str = "",
        parameters: Optional[Dict[str, Any]] = None,
        execute: Optional[Callable] = None,
        is_builtin: bool = False,
        is_mcp: bool = False,
        category: str = "general",
        is_read_only: bool = False,
    ) -> ToolDefinition:
        """Register a tool in the global registry.

        Can be called with a dict definition or keyword arguments.

        Args:
            name: Unique tool identifier
            definition: Optional dict with tool properties
            description: Tool description (if not using definition dict)
            parameters: JSON Schema for parameters
            execute: Optional execution function
            is_builtin: True for Claude Code built-in tools
            is_mcp: True for MCP tools
            category: Tool category for grouping
            is_read_only: True if tool doesn't modify state

        Returns:
            The registered ToolDefinition

        Raises:
            ValueError: If tool already registered (use update to modify)
        """
        if name in self._tools:
            # Allow re-registration with same definition (idempotent)
            return self._tools[name]

        if definition:
            tool_def = ToolDefinition(
                name=name,
                description=definition.get("description", description),
                parameters=definition.get("parameters", parameters or {}),
                execute=definition.get("execute", execute),
                is_builtin=definition.get("is_builtin", is_builtin),
                is_mcp=definition.get("is_mcp", is_mcp),
                category=definition.get("category", category),
                is_read_only=definition.get("is_read_only", is_read_only),
            )
        else:
            tool_def = ToolDefinition(
                name=name,
                description=description,
                parameters=parameters or {},
                execute=execute,
                is_builtin=is_builtin,
                is_mcp=is_mcp,
                category=category,
                is_read_only=is_read_only,
            )

        self._tools[name] = tool_def
        return tool_def

    def get(self, name: str) -> Optional[ToolDefinition]:
        """Get a tool definition by name.

        Args:
            name: Tool identifier

        Returns:
            ToolDefinition or None if not found
        """
        return self._tools.get(name)

    def list(self) -> List[ToolDefinition]:
        """List all registered tools.

        Returns:
            List of all tool definitions
        """
        return list(self._tools.values())

    def list_names(self) -> List[str]:
        """List all registered tool names.

        Returns:
            List of tool names
        """
        return list(self._tools.keys())

    def list_by_category(self, category: str) -> List[ToolDefinition]:
        """List tools in a specific category.

        Args:
            category: Category to filter by

        Returns:
            List of tools in that category
        """
        return [t for t in self._tools.values() if t.category == category]

    def list_qualified_names(self, names: Optional[List[str]] = None) -> List[str]:
        """Get qualified names for SDK usage.

        Args:
            names: Optional list of tool names to filter. If None, returns all.

        Returns:
            List of qualified tool names (e.g., "mcp__matlab__matlab_execute")
        """
        if names is None:
            return [t.qualified_name for t in self._tools.values()]

        result = []
        for name in names:
            tool = self._tools.get(name)
            if tool:
                result.append(tool.qualified_name)
        return result

    def get_read_only_tools(self) -> List[str]:
        """Get names of all read-only tools.

        Returns:
            List of read-only tool names
        """
        return [t.name for t in self._tools.values() if t.is_read_only]

    def get_write_tools(self) -> List[str]:
        """Get names of all tools that can modify state.

        Returns:
            List of write tool names
        """
        return [t.name for t in self._tools.values() if not t.is_read_only]

    def is_registered(self, name: str) -> bool:
        """Check if a tool is registered.

        Args:
            name: Tool name to check

        Returns:
            True if tool is registered
        """
        return name in self._tools

    def clear(self) -> None:
        """Clear all registered tools. Used for testing."""
        self._tools.clear()
        self._initialized = False


# Global singleton instance
Tool = _ToolRegistry()
