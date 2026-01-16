"""
Base Agent - Abstract base class for custom agents.
"""

from abc import ABC, abstractmethod
from typing import Any, Dict


class BaseAgent(ABC):
    """Abstract base class for custom agents.

    Subclass this to create custom agents that can handle specific
    commands or patterns before they reach Claude.

    Example:
        class MyAgent(BaseAgent):
            def __init__(self):
                super().__init__()
                self.name = "MyAgent"
                self.priority = 50

            def can_handle(self, message: str) -> bool:
                return message.lower().startswith("mycommand")

            def handle(self, message: str, context: dict) -> str:
                return "Handled by MyAgent!"
    """

    def __init__(self):
        self.name: str = "BaseAgent"
        self.description: str = ""
        self.priority: int = 100  # Lower number = higher priority

    @abstractmethod
    def can_handle(self, message: str) -> bool:
        """Check if this agent can handle the given message.

        Args:
            message: The user's message

        Returns:
            True if this agent should handle the message
        """
        pass

    @abstractmethod
    def handle(self, message: str, context: Dict[str, Any]) -> str:
        """Process the message and return a response.

        Args:
            message: The user's message
            context: Additional context (workspace, simulink, etc.)

        Returns:
            Response string to display to user
        """
        pass
