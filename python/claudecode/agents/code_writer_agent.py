"""
Code Writer Agent - Specialized agent for writing MATLAB code.
"""

from .specialized_agent import SpecializedAgent
from .agent_configs import CODE_WRITER_AGENT_CONFIG


class CodeWriterAgent(SpecializedAgent):
    """Specialized agent for writing MATLAB code.

    This agent handles code writing tasks including:
    - Creating new functions and scripts
    - Implementing algorithms
    - Writing classes and OOP code
    - Developing test scripts
    - Code documentation

    Has full tool access and extended thinking (16K tokens)
    for complex implementations.

    Example usage:
        # Explicit command
        /write create a function to filter signals

        # Auto-detected
        "implement a Kalman filter"
        "create a new class for data processing"
    """

    def __init__(self):
        """Initialize Code Writer agent with predefined configuration."""
        super().__init__(CODE_WRITER_AGENT_CONFIG)


# Create singleton instance for easy access
code_writer_agent = CodeWriterAgent()
