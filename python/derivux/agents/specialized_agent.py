"""
Specialized Agent - Base class and configuration for specialized Claude agents.

This module provides:
- AgentConfig: Declarative configuration for agent capabilities
- SpecializedAgent: Base class that wraps MatlabAgent with custom config
"""

from dataclasses import dataclass, field
from typing import List, Optional, Dict, Any
import re


@dataclass
class AgentConfig:
    """Configuration for a specialized agent.

    Attributes:
        name: Unique identifier for the agent (e.g., "GitAgent")
        description: Human-readable description of the agent's purpose
        command_prefix: Slash command to explicitly invoke (e.g., "/git")
        system_prompt: Custom system prompt for this agent
        allowed_tools: List of tool names this agent can use
        thinking_budget: Optional extended thinking token budget (None for standard)
        auto_detect_patterns: Regex patterns for auto-detecting when to use this agent
        priority: Agent priority (lower = higher priority, used for tie-breaking)
    """
    name: str
    description: str
    command_prefix: str
    system_prompt: str
    allowed_tools: List[str]
    thinking_budget: Optional[int] = None
    auto_detect_patterns: List[str] = field(default_factory=list)
    priority: int = 100

    def matches_command(self, message: str) -> bool:
        """Check if message starts with this agent's command prefix.

        Args:
            message: User's message to check

        Returns:
            True if message starts with command prefix
        """
        return message.strip().lower().startswith(self.command_prefix.lower())

    def strip_command(self, message: str) -> str:
        """Remove command prefix from message.

        Args:
            message: User's message with command prefix

        Returns:
            Message with command prefix stripped
        """
        if self.matches_command(message):
            return message.strip()[len(self.command_prefix):].strip()
        return message

    def calculate_confidence(self, message: str) -> float:
        """Calculate confidence score for auto-detecting this agent.

        Uses a scoring algorithm where:
        - Each matching pattern adds to the score
        - First match is worth more (0.5) as a strong signal
        - Additional matches add incrementally (0.15 each)
        - Score is capped at 1.0

        Args:
            message: User's message to analyze

        Returns:
            Confidence score from 0.0 to 1.0
        """
        if not self.auto_detect_patterns:
            return 0.0

        message_lower = message.lower()
        matches = 0

        for pattern in self.auto_detect_patterns:
            try:
                if re.search(pattern, message_lower, re.IGNORECASE):
                    matches += 1
            except re.error:
                # Invalid regex, skip
                continue

        if matches == 0:
            return 0.0

        # First match is a strong signal (0.5), each additional adds 0.15
        # This means: 1 match = 0.5, 2 matches = 0.65, 3 matches = 0.8, etc.
        score = 0.5 + (matches - 1) * 0.15
        return min(1.0, score)


class SpecializedAgent:
    """Wrapper for a specialized agent with custom configuration.

    This class holds the configuration and provides methods for
    routing decisions. The actual MatlabAgent is created by
    MatlabAgent.from_config() when needed.

    Example:
        config = AgentConfig(
            name="GitAgent",
            command_prefix="/git",
            system_prompt="You are a Git expert...",
            allowed_tools=["Bash", "Read", "Glob", "Grep"],
        )
        agent = SpecializedAgent(config)

        if agent.should_handle("/git status"):
            # Create MatlabAgent with this config
            matlab_agent = MatlabAgent.from_config(config)
    """

    def __init__(self, config: AgentConfig):
        """Initialize specialized agent.

        Args:
            config: Agent configuration
        """
        self.config = config

    @property
    def name(self) -> str:
        """Get agent name."""
        return self.config.name

    @property
    def command_prefix(self) -> str:
        """Get command prefix."""
        return self.config.command_prefix

    def matches_command(self, message: str) -> bool:
        """Check if message explicitly invokes this agent.

        Args:
            message: User's message

        Returns:
            True if message starts with this agent's command
        """
        return self.config.matches_command(message)

    def strip_command(self, message: str) -> str:
        """Remove command prefix from message.

        Args:
            message: User's message

        Returns:
            Message with command prefix removed
        """
        return self.config.strip_command(message)

    def calculate_confidence(self, message: str) -> float:
        """Calculate auto-detection confidence score.

        Args:
            message: User's message

        Returns:
            Confidence score from 0.0 to 1.0
        """
        return self.config.calculate_confidence(message)

    def should_handle(self, message: str, confidence_threshold: float = 0.6) -> bool:
        """Check if this agent should handle the message.

        Args:
            message: User's message
            confidence_threshold: Minimum confidence for auto-detection

        Returns:
            True if agent should handle (explicit command or high confidence)
        """
        if self.matches_command(message):
            return True
        return self.calculate_confidence(message) >= confidence_threshold


# Tool name constants for easy reference
class ToolNames:
    """Constants for tool names used in agent configurations."""

    # Claude Code built-in tools
    BASH = "Bash"
    READ = "Read"
    WRITE = "Write"
    GLOB = "Glob"
    GREP = "Grep"

    # MCP MATLAB tools (prefixed format)
    MATLAB_EXECUTE = "mcp__matlab__matlab_execute"
    MATLAB_WORKSPACE = "mcp__matlab__matlab_workspace"
    MATLAB_PLOT = "mcp__matlab__matlab_plot"

    # MCP Simulink tools
    SIMULINK_QUERY = "mcp__matlab__simulink_query"
    SIMULINK_MODIFY = "mcp__matlab__simulink_modify"

    # MCP File tools
    FILE_READ = "mcp__matlab__file_read"
    FILE_WRITE = "mcp__matlab__file_write"
    FILE_LIST = "mcp__matlab__file_list"
    FILE_MKDIR = "mcp__matlab__file_mkdir"

    @classmethod
    def all_matlab_tools(cls) -> List[str]:
        """Get all MATLAB-related tools."""
        return [
            cls.MATLAB_EXECUTE,
            cls.MATLAB_WORKSPACE,
            cls.MATLAB_PLOT,
        ]

    @classmethod
    def all_simulink_tools(cls) -> List[str]:
        """Get all Simulink-related tools."""
        return [
            cls.SIMULINK_QUERY,
            cls.SIMULINK_MODIFY,
        ]

    @classmethod
    def all_file_tools(cls) -> List[str]:
        """Get all file tools (both MCP and built-in)."""
        return [
            cls.FILE_READ,
            cls.FILE_WRITE,
            cls.FILE_LIST,
            cls.FILE_MKDIR,
            cls.READ,
            cls.WRITE,
            cls.GLOB,
            cls.GREP,
        ]

    @classmethod
    def read_only_tools(cls) -> List[str]:
        """Get read-only tools (cannot modify files)."""
        return [
            cls.READ,
            cls.GLOB,
            cls.GREP,
            cls.FILE_READ,
            cls.FILE_LIST,
            cls.MATLAB_WORKSPACE,  # Can read workspace
            cls.SIMULINK_QUERY,   # Can query models
        ]

    @classmethod
    def all_tools(cls) -> List[str]:
        """Get all available tools."""
        return (
            [cls.BASH, cls.READ, cls.WRITE, cls.GLOB, cls.GREP] +
            cls.all_matlab_tools() +
            cls.all_simulink_tools() +
            [cls.FILE_READ, cls.FILE_WRITE, cls.FILE_LIST, cls.FILE_MKDIR]
        )
