"""
Git Agent - Specialized agent for Git and version control operations.
"""

from .specialized_agent import SpecializedAgent
from .agent_configs import GIT_AGENT_CONFIG


class GitAgent(SpecializedAgent):
    """Specialized agent for Git operations.

    This agent handles version control tasks including:
    - Commits and commit message generation
    - Branch management
    - Merging and rebasing
    - Viewing history and diffs
    - Resolving conflicts

    Example usage:
        # Explicit command
        /git status

        # Auto-detected
        "commit my changes"
        "show me the branch history"
    """

    def __init__(self):
        """Initialize Git agent with predefined configuration."""
        super().__init__(GIT_AGENT_CONFIG)


# Create singleton instance for easy access
git_agent = GitAgent()
