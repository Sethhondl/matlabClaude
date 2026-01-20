"""
Evaluation Framework for Claude Code MATLAB

This package provides tools for testing the MatlabAgent by sending prompts
and using Claude-as-judge to evaluate responses against expected criteria.

Usage:
    # Run from command line
    python -m evals.runner --list              # List test cases
    python -m evals.runner                     # Run all tests
    python -m evals.runner --tags matlab basic # Filter by tags

    # Programmatic usage
    from evals import run_evaluations, TestCaseLoader

    # List available tests
    loader = TestCaseLoader()
    for tc in loader.list_test_cases():
        print(f"{tc['id']}: {tc['name']}")

    # Run evaluations
    results = run_evaluations(tags=["matlab", "basic"])
"""

from .config import EvalConfig, DEFAULT_CONFIG
from .loader import (
    TestCase,
    TestSuite,
    TestCaseLoader,
    WorkspaceVariable,
    WorkspaceState,
    TestContext,
    ToolUsageExpectation,
    TestCaseExpectation,
)
from .judge import ClaudeJudge, JudgmentResult, CriterionScore
from .evaluator import (
    Evaluator,
    TrialResult,
    TestCaseResult,
    run_evaluations,
)
from .results import (
    ResultsAggregator,
    EvalSummary,
    TagStats,
    aggregate_results,
)
from .mock_matlab import (
    MockMatlabEngine,
    MockVariable,
    ExecutionRecord,
    get_mock_engine,
    inject_mock_engine,
    restore_real_engine,
)

__all__ = [
    # Config
    "EvalConfig",
    "DEFAULT_CONFIG",
    # Loader
    "TestCase",
    "TestSuite",
    "TestCaseLoader",
    "WorkspaceVariable",
    "WorkspaceState",
    "TestContext",
    "ToolUsageExpectation",
    "TestCaseExpectation",
    # Judge
    "ClaudeJudge",
    "JudgmentResult",
    "CriterionScore",
    # Evaluator
    "Evaluator",
    "TrialResult",
    "TestCaseResult",
    "run_evaluations",
    # Results
    "ResultsAggregator",
    "EvalSummary",
    "TagStats",
    "aggregate_results",
    # Mock
    "MockMatlabEngine",
    "MockVariable",
    "ExecutionRecord",
    "get_mock_engine",
    "inject_mock_engine",
    "restore_real_engine",
]
