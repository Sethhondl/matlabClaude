"""
Specialized Agent Manager - Routes messages to appropriate specialized agents.

This module provides intelligent routing of user messages to specialized agents
based on explicit commands (/git, /review, etc.) and auto-detection via
confidence scoring.
"""

from typing import Dict, Any, List, Optional, Tuple
from dataclasses import dataclass, field

from .agents.specialized_agent import SpecializedAgent, AgentConfig
from .agents.agent_configs import (
    ALL_AGENT_CONFIGS,
    GENERAL_AGENT_CONFIG,
    GIT_AGENT_CONFIG,
    SIMULINK_AGENT_CONFIG,
    CODE_WRITER_AGENT_CONFIG,
    CODE_REVIEWER_AGENT_CONFIG,
    PLANNING_AGENT_CONFIG,
)


@dataclass
class RoutingResult:
    """Result of routing a message to an agent.

    Attributes:
        config: The selected agent configuration
        cleaned_message: Message with command prefix stripped (if any)
        is_explicit: True if agent was selected via explicit command
        confidence: Confidence score for auto-detection (0.0-1.0)
        reason: Human-readable explanation of routing decision
    """
    config: AgentConfig
    cleaned_message: str
    is_explicit: bool
    confidence: float
    reason: str


@dataclass
class ConversationContext:
    """Context for conversation continuity.

    Attributes:
        current_agent: Name of currently active agent
        turn_count: Number of turns with current agent
        recent_messages: Recent message summaries for context
    """
    current_agent: str = ""
    turn_count: int = 0
    recent_messages: List[Dict[str, str]] = field(default_factory=list)

    def add_message(self, role: str, content: str, agent: str) -> None:
        """Add a message to the context.

        Args:
            role: "user" or "assistant"
            content: Message content (will be truncated)
            agent: Agent that handled this message
        """
        # Keep last 20 messages
        if len(self.recent_messages) >= 20:
            self.recent_messages.pop(0)

        # Truncate content for context
        summary = content[:200] + "..." if len(content) > 200 else content
        self.recent_messages.append({
            "role": role,
            "content": summary,
            "agent": agent,
        })

    def get_context_summary(self) -> str:
        """Get a summary of recent conversation for context injection.

        Returns:
            Formatted string summarizing recent context
        """
        if not self.recent_messages:
            return ""

        lines = ["## Recent Conversation Context"]
        for msg in self.recent_messages[-5:]:  # Last 5 messages
            role = msg["role"].capitalize()
            agent = msg.get("agent", "")
            content = msg["content"]
            if agent:
                lines.append(f"**{role}** (via {agent}): {content}")
            else:
                lines.append(f"**{role}**: {content}")

        return "\n".join(lines)


class SpecializedAgentManager:
    """Manages specialized agents and routes messages appropriately.

    Routing Priority:
    1. Explicit command (/git, /review, etc.)
    2. Auto-detection via confidence scoring (threshold: 0.6)
    3. Session continuity (stay with current agent if no strong signal)
    4. Fallback to GeneralAgent

    Example:
        manager = SpecializedAgentManager()

        # Route a message
        result = manager.route_message("/git status")
        # result.config == GIT_AGENT_CONFIG
        # result.cleaned_message == "status"
        # result.is_explicit == True

        # Auto-detection
        result = manager.route_message("review my code for bugs")
        # result.config == CODE_REVIEWER_AGENT_CONFIG
        # result.is_explicit == False
        # result.confidence > 0.6
    """

    # Minimum confidence for auto-detection
    # With the scoring algorithm: 1 match = 0.5, 2 matches = 0.65
    # A threshold of 0.5 means at least one strong pattern match required
    CONFIDENCE_THRESHOLD = 0.5

    # Confidence boost for current agent (session continuity)
    CONTINUITY_BOOST = 0.2

    def __init__(self):
        """Initialize the manager with all specialized agents."""
        # Create agents from configs (sorted by priority)
        self._agents: List[SpecializedAgent] = [
            SpecializedAgent(config)
            for config in sorted(ALL_AGENT_CONFIGS, key=lambda c: c.priority)
        ]

        # Conversation context for continuity
        self._context = ConversationContext()

        # Map command prefixes to agents for fast lookup
        self._command_map: Dict[str, SpecializedAgent] = {
            agent.command_prefix: agent
            for agent in self._agents
            if agent.command_prefix
        }

    @property
    def context(self) -> ConversationContext:
        """Get the conversation context."""
        return self._context

    def get_available_commands(self) -> List[str]:
        """Get list of available slash commands.

        Returns:
            List of command prefixes (e.g., ["/git", "/review", ...])
        """
        return [
            agent.command_prefix
            for agent in self._agents
            if agent.command_prefix
        ]

    def get_agent_info(self) -> List[Dict[str, str]]:
        """Get information about all available agents.

        Returns:
            List of dicts with agent name, command, and description
        """
        return [
            {
                "name": agent.name,
                "command": agent.command_prefix,
                "description": agent.config.description,
            }
            for agent in self._agents
            if agent.command_prefix  # Skip general agent
        ]

    def route_message(
        self,
        message: str,
        context: Optional[Dict[str, Any]] = None
    ) -> RoutingResult:
        """Route a message to the appropriate specialized agent.

        Args:
            message: User's message
            context: Optional additional context

        Returns:
            RoutingResult with selected agent config and metadata
        """
        message = message.strip()

        # 1. Check for explicit command
        for prefix, agent in self._command_map.items():
            if message.lower().startswith(prefix.lower()):
                cleaned = agent.strip_command(message)
                self._update_context(agent.name)
                return RoutingResult(
                    config=agent.config,
                    cleaned_message=cleaned,
                    is_explicit=True,
                    confidence=1.0,
                    reason=f"Explicit command: {prefix}",
                )

        # 2. Auto-detect via confidence scoring
        scores: List[Tuple[SpecializedAgent, float]] = []
        for agent in self._agents:
            if not agent.config.auto_detect_patterns:
                continue

            confidence = agent.calculate_confidence(message)

            # Apply continuity boost if this is the current agent
            if agent.name == self._context.current_agent:
                confidence = min(1.0, confidence + self.CONTINUITY_BOOST)

            if confidence > 0:
                scores.append((agent, confidence))

        # Sort by confidence (descending), then by priority (ascending)
        scores.sort(key=lambda x: (-x[1], x[0].config.priority))

        # 3. Check if best score meets threshold
        if scores and scores[0][1] >= self.CONFIDENCE_THRESHOLD:
            best_agent, best_confidence = scores[0]
            self._update_context(best_agent.name)
            return RoutingResult(
                config=best_agent.config,
                cleaned_message=message,
                is_explicit=False,
                confidence=best_confidence,
                reason=f"Auto-detected: {best_agent.name} (confidence: {best_confidence:.2f})",
            )

        # 4. Session continuity - stay with current agent if active
        if self._context.current_agent and self._context.turn_count < 10:
            for agent in self._agents:
                if agent.name == self._context.current_agent:
                    self._update_context(agent.name)
                    return RoutingResult(
                        config=agent.config,
                        cleaned_message=message,
                        is_explicit=False,
                        confidence=0.0,
                        reason=f"Session continuity: {agent.name}",
                    )

        # 5. Fallback to general agent
        general_agent = SpecializedAgent(GENERAL_AGENT_CONFIG)
        self._update_context(general_agent.name)
        return RoutingResult(
            config=general_agent.config,
            cleaned_message=message,
            is_explicit=False,
            confidence=0.0,
            reason="Fallback to GeneralAgent",
        )

    def _update_context(self, agent_name: str) -> None:
        """Update context when agent changes.

        Args:
            agent_name: Name of the new active agent
        """
        if agent_name == self._context.current_agent:
            self._context.turn_count += 1
        else:
            self._context.current_agent = agent_name
            self._context.turn_count = 1

    def add_message_to_context(
        self,
        role: str,
        content: str,
        agent_name: str = ""
    ) -> None:
        """Add a message to the conversation context.

        Args:
            role: "user" or "assistant"
            content: Message content
            agent_name: Name of agent that handled this message
        """
        self._context.add_message(role, content, agent_name)

    def clear_context(self) -> None:
        """Clear conversation context (called on chat clear)."""
        self._context = ConversationContext()

    def get_context_summary(self) -> str:
        """Get context summary for injection into new agent.

        Returns:
            Formatted context summary string
        """
        return self._context.get_context_summary()

    def get_current_agent(self) -> str:
        """Get the name of the currently active agent.

        Returns:
            Agent name or empty string if none
        """
        return self._context.current_agent

    def force_agent(self, agent_name: str) -> Optional[AgentConfig]:
        """Force selection of a specific agent by name.

        Args:
            agent_name: Name of agent to select

        Returns:
            AgentConfig if found, None otherwise
        """
        for agent in self._agents:
            if agent.name == agent_name:
                self._update_context(agent_name)
                return agent.config
        return None
