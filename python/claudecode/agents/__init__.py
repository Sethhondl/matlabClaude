"""
Claude Code Agents - Custom agent framework.

This module provides:
- Base classes for interceptor agents (BaseAgent)
- Specialized agents with custom system prompts (SpecializedAgent)
- Agent configurations (AgentConfig) for declarative agent definition
"""

from .base_agent import BaseAgent
from .ping_pong_agent import PingPongAgent

# Specialized agent infrastructure
from .specialized_agent import AgentConfig, SpecializedAgent, ToolNames

# Agent configurations
from .agent_configs import (
    ALL_AGENT_CONFIGS,
    GIT_AGENT_CONFIG,
    SIMULINK_AGENT_CONFIG,
    CODE_WRITER_AGENT_CONFIG,
    CODE_REVIEWER_AGENT_CONFIG,
    PLANNING_AGENT_CONFIG,
    GENERAL_AGENT_CONFIG,
    get_agent_config,
    get_agent_by_command,
)

# Specialized agent implementations
from .git_agent import GitAgent, git_agent
from .simulink_agent import SimulinkAgent, simulink_agent
from .code_writer_agent import CodeWriterAgent, code_writer_agent
from .code_reviewer_agent import CodeReviewerAgent, code_reviewer_agent
from .planning_agent import PlanningAgent, planning_agent

__all__ = [
    # Base agent classes
    "BaseAgent",
    "PingPongAgent",

    # Specialized agent infrastructure
    "AgentConfig",
    "SpecializedAgent",
    "ToolNames",

    # Agent configurations
    "ALL_AGENT_CONFIGS",
    "GIT_AGENT_CONFIG",
    "SIMULINK_AGENT_CONFIG",
    "CODE_WRITER_AGENT_CONFIG",
    "CODE_REVIEWER_AGENT_CONFIG",
    "PLANNING_AGENT_CONFIG",
    "GENERAL_AGENT_CONFIG",
    "get_agent_config",
    "get_agent_by_command",

    # Specialized agents
    "GitAgent",
    "git_agent",
    "SimulinkAgent",
    "simulink_agent",
    "CodeWriterAgent",
    "code_writer_agent",
    "CodeReviewerAgent",
    "code_reviewer_agent",
    "PlanningAgent",
    "planning_agent",
]
