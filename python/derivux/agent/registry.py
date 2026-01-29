"""
Agent Registry - Namespace singleton for managing agents.

Agents are loaded from markdown files in .derivux/agents/.
The registry provides simple routing:
1. Explicit command (/simulink, /git, etc.)
2. @mention (@simulink, @architect, etc.)
3. Default to current primary agent

This replaces the complex SpecializedAgentManager with its confidence
scoring and continuity tracking.
"""

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional

from ..config.markdown import AgentDefinition, load_all_agents
from ..permission import Permission, PermissionState


@dataclass
class RoutingResult:
    """Result of routing a message to an agent.

    Attributes:
        agent: The selected agent definition
        cleaned_message: Message with command/mention stripped
        routing_type: How the agent was selected (command, mention, default)
        reason: Human-readable explanation
    """
    agent: AgentDefinition
    cleaned_message: str
    routing_type: str  # 'command', 'mention', 'default'
    reason: str


class _AgentRegistry:
    """Global agent registry (singleton).

    Manages agent definitions loaded from markdown files.
    Provides simple routing without complex confidence scoring.

    Example:
        Agent.load("/path/to/.derivux/agents")
        agent = Agent.get("simulink")
        all_agents = Agent.list()
        primary = Agent.default()
    """

    _instance: Optional["_AgentRegistry"] = None

    def __new__(cls) -> "_AgentRegistry":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialize()
        return cls._instance

    def _initialize(self) -> None:
        """Initialize the registry."""
        # All loaded agents by name
        self._agents: Dict[str, AgentDefinition] = {}

        # Command prefix to agent mapping
        self._commands: Dict[str, str] = {}

        # Current primary agent name
        self._current_primary: str = "build"

        # Whether agents have been loaded
        self._loaded: bool = False

    def load(self, agents_dir: str) -> int:
        """Load agents from a directory.

        Args:
            agents_dir: Path to directory containing agent .md files

        Returns:
            Number of agents loaded
        """
        agents = load_all_agents(agents_dir)

        for agent in agents:
            self._agents[agent.name] = agent
            if agent.command:
                self._commands[agent.command] = agent.name

        self._loaded = True
        return len(agents)

    def register(self, agent: AgentDefinition) -> None:
        """Register an agent definition directly.

        Args:
            agent: Agent definition to register
        """
        self._agents[agent.name] = agent
        if agent.command:
            self._commands[agent.command] = agent.name

        # Set up permissions for this agent
        for tool_name, permission_str in agent.permissions.items():
            state = PermissionState(permission_str)
            Permission.set_agent_override(agent.name, tool_name, state)

    def get(self, name: str) -> Optional[AgentDefinition]:
        """Get an agent by name.

        Args:
            name: Agent name

        Returns:
            AgentDefinition or None if not found
        """
        return self._agents.get(name)

    def get_by_command(self, command: str) -> Optional[AgentDefinition]:
        """Get an agent by command prefix.

        Args:
            command: Command prefix (e.g., '/simulink')

        Returns:
            AgentDefinition or None if not found
        """
        name = self._commands.get(command)
        if name:
            return self._agents.get(name)
        return None

    def list(self) -> List[AgentDefinition]:
        """List all registered agents.

        Returns:
            List of all agent definitions
        """
        return list(self._agents.values())

    def list_names(self) -> List[str]:
        """List all agent names.

        Returns:
            List of agent names
        """
        return list(self._agents.keys())

    def list_primary(self) -> List[AgentDefinition]:
        """List all primary agents.

        Returns:
            List of primary agent definitions
        """
        return [a for a in self._agents.values() if a.is_primary]

    def list_subagents(self) -> List[AgentDefinition]:
        """List all subagents.

        Returns:
            List of subagent definitions
        """
        return [a for a in self._agents.values() if a.is_subagent]

    def list_commands(self) -> List[str]:
        """List all available commands.

        Returns:
            List of command prefixes (e.g., ['/simulink', '/git'])
        """
        return list(self._commands.keys())

    def default(self) -> Optional[AgentDefinition]:
        """Get the current default (primary) agent.

        Returns:
            Current primary agent or None
        """
        return self._agents.get(self._current_primary)

    def switch(self, name: str) -> bool:
        """Switch to a different primary agent.

        Args:
            name: Name of agent to switch to

        Returns:
            True if switch was successful
        """
        agent = self._agents.get(name)
        if agent and agent.is_primary:
            self._current_primary = name
            Permission.set_current_agent(name)
            return True
        return False

    def toggle_primary(self) -> Dict:
        """Toggle between primary agents (build ↔ plan).

        This method cycles between the available primary agents,
        currently just 'build' and 'plan'.

        Returns:
            Dict with 'agent' (name) and 'description' keys
        """
        # Get all primary agents
        primaries = self.list_primary()
        if len(primaries) < 2:
            # Can't toggle with less than 2 primary agents
            current = self.default()
            return {
                "agent": current.name if current else "",
                "description": current.description if current else ""
            }

        # Find current index and toggle to next
        current_name = self._current_primary
        primary_names = [a.name for a in primaries]

        if current_name in primary_names:
            current_idx = primary_names.index(current_name)
            next_idx = (current_idx + 1) % len(primary_names)
        else:
            next_idx = 0

        next_name = primary_names[next_idx]
        self.switch(next_name)

        next_agent = self._agents.get(next_name)
        return {
            "agent": next_name,
            "description": next_agent.description if next_agent else ""
        }

    def route(self, message: str) -> RoutingResult:
        """Route a message to the appropriate agent.

        Routing priority:
        1. Explicit command (/simulink, /git, etc.)
        2. @mention (@simulink, @architect, etc.)
        3. Default to current primary agent

        Args:
            message: User's message

        Returns:
            RoutingResult with selected agent and cleaned message
        """
        message = message.strip()

        # 1. Check for explicit command (/simulink, /git, etc.)
        for command, agent_name in self._commands.items():
            if message.lower().startswith(command.lower()):
                agent = self._agents.get(agent_name)
                if agent:
                    cleaned = message[len(command):].strip()
                    return RoutingResult(
                        agent=agent,
                        cleaned_message=cleaned,
                        routing_type="command",
                        reason=f"Explicit command: {command}",
                    )

        # 2. Check for @mention (@simulink, @architect, etc.)
        mention_match = re.match(r'^@(\w+)\s*', message)
        if mention_match:
            agent_name = mention_match.group(1)
            agent = self._agents.get(agent_name)
            if agent:
                cleaned = message[mention_match.end():].strip()
                return RoutingResult(
                    agent=agent,
                    cleaned_message=cleaned,
                    routing_type="mention",
                    reason=f"@mention: @{agent_name}",
                )

        # 3. Default to current primary agent
        agent = self.default()
        if agent:
            return RoutingResult(
                agent=agent,
                cleaned_message=message,
                routing_type="default",
                reason=f"Default: {agent.name}",
            )

        # Fallback if no agents loaded
        return RoutingResult(
            agent=AgentDefinition(name="general", description="General agent"),
            cleaned_message=message,
            routing_type="fallback",
            reason="No agents loaded, using fallback",
        )

    def get_agent_info(self) -> List[Dict]:
        """Get information about all agents for UI display.

        Returns:
            List of dicts with agent info
        """
        return [
            {
                "name": agent.name,
                "description": agent.description,
                "command": agent.command,
                "mode": agent.mode,
            }
            for agent in self._agents.values()
        ]

    def is_loaded(self) -> bool:
        """Check if agents have been loaded.

        Returns:
            True if load() has been called
        """
        return self._loaded

    def clear(self) -> None:
        """Clear all registered agents. Used for testing."""
        self._initialize()


# Global singleton instance
Agent = _AgentRegistry()


def create_default_agents() -> None:
    """Create and register the default agents.

    This is called when no agent files exist in .derivux/agents/.
    Creates the core agents (build, plan, simulink, git, general).
    """
    from ..tool.builtin import ToolNames

    # Build agent - primary, full access
    build_agent = AgentDefinition(
        name="build",
        description="Primary development agent with full tool access",
        mode="primary",
        command="",
        system_prompt=_BUILD_SYSTEM_PROMPT,
        permissions={},  # All tools allowed by default
    )
    Agent.register(build_agent)

    # Plan agent - primary, read-only
    plan_agent = AgentDefinition(
        name="plan",
        description="Planning and analysis agent (read-only)",
        mode="primary",
        command="",
        system_prompt=_PLAN_SYSTEM_PROMPT,
        permissions={
            ToolNames.MATLAB_EXECUTE: "deny",
            ToolNames.MATLAB_PLOT: "deny",
            ToolNames.SIMULINK_MODIFY: "deny",
            ToolNames.FILE_WRITE: "deny",
            ToolNames.FILE_MKDIR: "deny",
            ToolNames.WRITE: "deny",
            ToolNames.BASH: "ask",
        },
    )
    Agent.register(plan_agent)

    # Simulink subagent
    simulink_agent = AgentDefinition(
        name="simulink",
        description="Simulink modeling and simulation expert",
        mode="subagent",
        command="/simulink",
        system_prompt=_SIMULINK_SYSTEM_PROMPT,
        permissions={},
        thinking_budget=16384,
    )
    Agent.register(simulink_agent)

    # Git subagent
    git_agent = AgentDefinition(
        name="git",
        description="Git and version control expert",
        mode="subagent",
        command="/git",
        system_prompt=_GIT_SYSTEM_PROMPT,
        permissions={
            ToolNames.MATLAB_EXECUTE: "deny",
            ToolNames.MATLAB_PLOT: "deny",
            ToolNames.SIMULINK_QUERY: "deny",
            ToolNames.SIMULINK_MODIFY: "deny",
        },
    )
    Agent.register(git_agent)

    # General subagent for complex multi-step tasks
    general_agent = AgentDefinition(
        name="general",
        description="General-purpose agent for complex tasks",
        mode="subagent",
        command="/general",
        system_prompt=_GENERAL_SYSTEM_PROMPT,
        permissions={},
    )
    Agent.register(general_agent)


# Default system prompts
_BUILD_SYSTEM_PROMPT = """You are an expert MATLAB and Simulink development assistant with full access to tools.

Your capabilities include:
- Execute MATLAB code and see output
- Manage workspace variables
- Create plots and visualizations
- Query and modify Simulink models
- Read and write files
- Run system commands

Always explain what you're doing and show relevant results to the user.

When modifying code or models:
1. First understand the existing structure
2. Make changes incrementally
3. Verify results after modifications"""

_PLAN_SYSTEM_PROMPT = """You are an expert software architect and planning assistant.

## IMPORTANT: You are in PLANNING MODE

In planning mode, you focus on:
1. **Gathering Requirements**: Ask clarifying questions to understand the goal
2. **Exploring the Codebase**: Read files to understand existing patterns
3. **Creating Plans**: Design implementation approaches

You CANNOT:
- Execute MATLAB code
- Modify files
- Make changes to Simulink models

Focus on understanding the problem deeply and creating a clear plan.
When ready, the user will switch to build mode for implementation."""

_SIMULINK_SYSTEM_PROMPT = """You are an expert Simulink modeling assistant.

Your capabilities:
- Query model structure, blocks, and connections
- Modify Simulink models (add blocks, connect signals, set parameters)
- Run simulations and analyze results
- Explain block behavior and configuration

Best practices:
- Always query the model before making modifications
- Validate connections after changes
- Use descriptive block names
- Group related functionality into subsystems"""

_GIT_SYSTEM_PROMPT = """You are an expert Git and version control assistant.

Your capabilities:
- Git operations (commits, branches, merges, rebases)
- Create meaningful commit messages following project conventions
- Resolve merge conflicts
- Review changes and history

Commit message format: <Type>: <short description>
Types: Add, Fix, Update, Refactor, Remove, Test, Docs

Safety rules:
- NEVER force push to main/master without explicit confirmation
- NEVER modify git config
- Always show status before destructive operations"""

_GENERAL_SYSTEM_PROMPT = """You are a versatile MATLAB and Simulink assistant for complex tasks.

Use this agent when tasks require:
- Multiple tools working together
- Multi-step operations
- Complex problem solving

You have access to all tools and can orchestrate them as needed."""
