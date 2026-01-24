"""
Derivux MATLAB Integration - Python Core

This package provides the core functionality for Derivux integration,
designed to be called from MATLAB via py.derivux.* syntax.

Uses the Claude Agent SDK for native tool support when available.
"""

from .process_manager import ClaudeProcessManager
from .agent_manager import AgentManager
from .bridge import MatlabBridge
from .matlab_engine import get_engine, stop_engine, MatlabEngineWrapper

# Try to import agent (requires claude-agent-sdk)
try:
    from .agent import MatlabAgent, run_query_sync
    AGENT_SDK_AVAILABLE = True
except ImportError:
    AGENT_SDK_AVAILABLE = False
    MatlabAgent = None
    run_query_sync = None

__version__ = "0.1.0"
__all__ = [
    "ClaudeProcessManager",
    "AgentManager",
    "MatlabBridge",
    "MatlabEngineWrapper",
    "get_engine",
    "stop_engine",
    "MatlabAgent",
    "run_query_sync",
    "AGENT_SDK_AVAILABLE",
]
