"""
Tool system - Global tool registry and built-in tool definitions.

This module provides:
- Tool: Global tool registry (namespace singleton pattern)
- ToolDefinition: Schema for tool definitions
- Built-in tools for MATLAB, Simulink, and file operations
"""

from .registry import Tool, ToolDefinition

__all__ = ["Tool", "ToolDefinition"]
