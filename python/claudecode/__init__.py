"""
Claude Code MATLAB Integration - Python Core

This package provides the core functionality for Claude Code integration,
designed to be called from MATLAB via py.claudecode.* syntax.
"""

from .process_manager import ClaudeProcessManager
from .agent_manager import AgentManager
from .bridge import MatlabBridge

__version__ = "0.1.0"
__all__ = ["ClaudeProcessManager", "AgentManager", "MatlabBridge"]
