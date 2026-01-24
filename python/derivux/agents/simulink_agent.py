"""
Simulink Agent - Specialized agent for Simulink modeling and simulation.
"""

from .specialized_agent import SpecializedAgent
from .agent_configs import SIMULINK_AGENT_CONFIG


class SimulinkAgent(SpecializedAgent):
    """Specialized agent for Simulink operations.

    This agent handles Simulink modeling tasks including:
    - Querying model structure and hierarchy
    - Adding and configuring blocks
    - Creating signal connections
    - Setting block parameters
    - Running simulations
    - Analyzing model behavior

    Features extended thinking (16K tokens) for complex model analysis.

    Example usage:
        # Explicit command
        /simulink show me the model structure

        # Auto-detected
        "what blocks are in this subsystem?"
        "connect the output to the scope"
    """

    def __init__(self):
        """Initialize Simulink agent with predefined configuration."""
        super().__init__(SIMULINK_AGENT_CONFIG)


# Create singleton instance for easy access
simulink_agent = SimulinkAgent()
