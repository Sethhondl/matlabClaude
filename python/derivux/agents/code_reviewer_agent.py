"""
Code Reviewer Agent - Specialized agent for reviewing MATLAB code (read-only).
"""

from .specialized_agent import SpecializedAgent
from .agent_configs import CODE_REVIEWER_AGENT_CONFIG


class CodeReviewerAgent(SpecializedAgent):
    """Specialized agent for code review (read-only).

    This agent handles code review tasks including:
    - Checking code correctness
    - Identifying performance issues
    - Reviewing code style and readability
    - Finding potential bugs
    - Security analysis (eval, system calls)
    - Suggesting improvements

    IMPORTANT: This agent has READ-ONLY access.
    It cannot modify any files, ensuring safe code review.

    Features extended thinking (32K tokens) for thorough analysis.

    Example usage:
        # Explicit command
        /review check myFunction.m for issues

        # Auto-detected
        "review my code"
        "find bugs in this script"
        "check code quality"
    """

    def __init__(self):
        """Initialize Code Reviewer agent with predefined configuration."""
        super().__init__(CODE_REVIEWER_AGENT_CONFIG)


# Create singleton instance for easy access
code_reviewer_agent = CodeReviewerAgent()
