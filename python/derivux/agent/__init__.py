"""
Agent System - Agent registry and definitions.

Provides:
- Agent: Global agent registry (namespace singleton)
- RoutingResult: Result of message routing
- create_default_agents: Create built-in agents when no files exist
"""

from .registry import Agent, RoutingResult, create_default_agents

__all__ = ["Agent", "RoutingResult", "create_default_agents"]
