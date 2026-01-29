"""
Derivux Agents - Custom agent framework.

This module provides:
- Base classes for interceptor agents (BaseAgent)
- PingPongAgent for testing

Note: Specialized agents are now defined as markdown files in .derivux/agents/
and managed through the Agent registry in derivux.agent.registry
"""

from .base_agent import BaseAgent
from .ping_pong_agent import PingPongAgent

__all__ = [
    # Base agent classes
    "BaseAgent",
    "PingPongAgent",
]
