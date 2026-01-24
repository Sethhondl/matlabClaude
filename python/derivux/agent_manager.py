"""
Agent Manager - Manages custom agents and dispatches messages.
"""

from typing import Any, Dict, List, Optional, Tuple
from .agents import BaseAgent, PingPongAgent


class AgentManager:
    """Manages custom agents and dispatches messages.

    The AgentManager maintains a list of registered agents and
    routes incoming messages to the appropriate agent based on
    priority and can_handle() results.

    Example:
        manager = AgentManager()
        manager.register_agent(PingPongAgent())
        handled, response, agent_name = manager.dispatch("ping", {})
    """

    def __init__(self, load_defaults: bool = True):
        """Initialize the agent manager.

        Args:
            load_defaults: If True, load default agents automatically
        """
        self._agents: List[BaseAgent] = []

        if load_defaults:
            self._load_default_agents()

    def register_agent(self, agent: BaseAgent) -> None:
        """Add an agent to the manager.

        Args:
            agent: The agent to register
        """
        self._agents.append(agent)
        self._sort_agents_by_priority()

    def remove_agent(self, agent_name: str) -> bool:
        """Remove an agent by name.

        Args:
            agent_name: Name of the agent to remove

        Returns:
            True if agent was found and removed
        """
        for i, agent in enumerate(self._agents):
            if agent.name == agent_name:
                del self._agents[i]
                return True
        return False

    def get_agents(self) -> List[BaseAgent]:
        """Get list of registered agents."""
        return self._agents.copy()

    def get_agent_names(self) -> List[str]:
        """Get list of registered agent names."""
        return [agent.name for agent in self._agents]

    def dispatch(
        self,
        message: str,
        context: Optional[Dict[str, Any]] = None
    ) -> Tuple[bool, str, str]:
        """Route message to appropriate agent.

        Args:
            message: The user's message
            context: Additional context

        Returns:
            Tuple of (handled, response, agent_name)
            - handled: True if an agent handled the message
            - response: The agent's response (empty if not handled)
            - agent_name: Name of handling agent (empty if not handled)
        """
        if context is None:
            context = {}

        for agent in self._agents:
            try:
                if agent.can_handle(message):
                    response = agent.handle(message, context)
                    return True, response, agent.name
            except Exception as e:
                print(f"Agent {agent.name} threw error: {e}")

        return False, "", ""

    def _load_default_agents(self) -> None:
        """Load built-in agents."""
        self.register_agent(PingPongAgent())

    def _sort_agents_by_priority(self) -> None:
        """Sort agents by priority (lower = higher priority)."""
        self._agents.sort(key=lambda a: a.priority)
