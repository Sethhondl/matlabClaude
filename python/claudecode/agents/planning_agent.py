"""
Planning Agent - Specialized agent for task breakdown and implementation planning.
"""

from .specialized_agent import SpecializedAgent
from .agent_configs import PLANNING_AGENT_CONFIG


class PlanningAgent(SpecializedAgent):
    """Specialized agent for planning and architecture.

    This agent handles planning tasks including:
    - Breaking down complex features into steps
    - Exploring codebase to understand architecture
    - Identifying files that need modification
    - Considering trade-offs between approaches
    - Creating detailed implementation plans
    - Saving plans as markdown files

    IMPORTANT: This agent is a PLANNER only.
    It explores and designs but does NOT implement code.
    Plans are saved as .md files for user review before execution.

    Features extended thinking (32K tokens) for complex planning.

    Example usage:
        # Explicit command
        /plan add user authentication feature

        # Auto-detected
        "how should I implement this?"
        "plan the architecture for..."
        "break down this task"
    """

    def __init__(self):
        """Initialize Planning agent with predefined configuration."""
        super().__init__(PLANNING_AGENT_CONFIG)


# Create singleton instance for easy access
planning_agent = PlanningAgent()
