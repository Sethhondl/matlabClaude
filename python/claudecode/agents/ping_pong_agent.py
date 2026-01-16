"""
Ping Pong Agent - Simple demonstration agent.
"""

from typing import Any, Dict
from .base_agent import BaseAgent


class PingPongAgent(BaseAgent):
    """Simple agent that responds to "ping" with "pong".

    A demonstration agent showing how to create custom handlers
    for specific commands.

    Example:
        agent = PingPongAgent()
        if agent.can_handle("ping"):
            response = agent.handle("ping", {})
    """

    def __init__(self):
        super().__init__()
        self.name = "PingPongAgent"
        self.description = "Responds to ping with pong"
        self.priority = 10  # High priority (low number)

    def can_handle(self, message: str) -> bool:
        """Check if message is 'ping'."""
        return message.strip().lower() == "ping"

    def handle(self, message: str, context: Dict[str, Any]) -> str:
        """Respond with pong."""
        return "pong"
