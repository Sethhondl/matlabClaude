"""
Configuration settings for the evaluation framework.
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


@dataclass
class EvalConfig:
    """Configuration for evaluation runs."""

    # Paths
    test_cases_dir: Path = field(default_factory=lambda: Path(__file__).parent / "test_cases")
    output_dir: Path = field(default_factory=lambda: Path(__file__).parent / "results")

    # Timeouts (in seconds)
    default_timeout: int = 60
    judge_timeout: int = 30

    # Pass/fail thresholds
    pass_threshold: float = 0.7  # Minimum score to pass a test case

    # Judge model configuration
    judge_model: str = "claude-sonnet-4-20250514"
    judge_max_tokens: int = 1024

    # Agent configuration
    agent_model: Optional[str] = None  # Use default if None
    agent_max_turns: int = 10

    # Retry configuration
    max_retries: int = 2
    retry_delay: float = 1.0  # seconds

    # Mock MATLAB settings
    use_mock_matlab: bool = True

    def __post_init__(self):
        """Ensure directories exist."""
        self.test_cases_dir = Path(self.test_cases_dir)
        self.output_dir = Path(self.output_dir)


# Default configuration instance
DEFAULT_CONFIG = EvalConfig()
