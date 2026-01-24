"""
Core evaluation logic for running test cases against the MatlabAgent.
"""

import asyncio
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

from .config import EvalConfig, DEFAULT_CONFIG
from .loader import TestCase, TestCaseLoader, WorkspaceVariable
from .judge import ClaudeJudge, JudgmentResult, CriterionScore
from .mock_matlab import (
    MockMatlabEngine,
    MockVariable,
    inject_mock_engine,
    restore_real_engine,
    get_mock_engine
)


@dataclass
class TrialResult:
    """Result of a single trial for a test case."""
    trial_number: int
    response_text: str
    tools_used: List[str]
    judgment: JudgmentResult
    duration_seconds: float
    error: Optional[str] = None

    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "trial_number": self.trial_number,
            "response_text": self.response_text[:500] + "..." if len(self.response_text) > 500 else self.response_text,
            "tools_used": self.tools_used,
            "judgment": self.judgment.to_dict(),
            "duration_seconds": self.duration_seconds,
            "error": self.error
        }


@dataclass
class TestCaseResult:
    """Result of evaluating a test case (possibly multiple trials)."""
    test_case: TestCase
    trials: List[TrialResult] = field(default_factory=list)
    tool_usage_result: Optional[CriterionScore] = None

    @property
    def passed(self) -> bool:
        """Test case passes if any trial passed."""
        return any(t.judgment.passed for t in self.trials)

    @property
    def best_score(self) -> float:
        """Return the best score across all trials."""
        if not self.trials:
            return 0.0
        return max(t.judgment.score for t in self.trials)

    @property
    def average_score(self) -> float:
        """Return the average score across all trials."""
        if not self.trials:
            return 0.0
        return sum(t.judgment.score for t in self.trials) / len(self.trials)

    @property
    def total_duration(self) -> float:
        """Total duration across all trials."""
        return sum(t.duration_seconds for t in self.trials)

    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "test_case_id": self.test_case.id,
            "test_case_name": self.test_case.name,
            "tags": self.test_case.tags,
            "passed": self.passed,
            "best_score": self.best_score,
            "average_score": self.average_score,
            "total_duration": self.total_duration,
            "num_trials": len(self.trials),
            "trials": [t.to_dict() for t in self.trials],
            "tool_usage_result": {
                "passed": self.tool_usage_result.passed,
                "score": self.tool_usage_result.score,
                "reasoning": self.tool_usage_result.reasoning
            } if self.tool_usage_result else None
        }


class Evaluator:
    """Runs evaluations against the MatlabAgent."""

    def __init__(
        self,
        config: Optional[EvalConfig] = None,
        progress_callback: Optional[Callable[[str], None]] = None
    ):
        """Initialize the evaluator.

        Args:
            config: Evaluation configuration. Uses default if None.
            progress_callback: Optional callback for progress updates.
        """
        self.config = config or DEFAULT_CONFIG
        self.loader = TestCaseLoader(config=self.config)
        self.judge = ClaudeJudge(config=self.config)
        self.progress_callback = progress_callback or (lambda x: None)

        self._agent = None
        self._mock_engine: Optional[MockMatlabEngine] = None

    def _log(self, message: str) -> None:
        """Log a progress message."""
        self.progress_callback(message)

    async def _setup_agent(self) -> None:
        """Setup the MatlabAgent for evaluation."""
        if self.config.use_mock_matlab:
            self._mock_engine = inject_mock_engine()
            self._mock_engine.connect()

        # Try to use the real MatlabAgent if SDK is available
        try:
            from derivux.agent import MatlabAgent
            self._agent = MatlabAgent(max_turns=self.config.agent_max_turns)
            await self._agent.start()
            self._log("Using MatlabAgent with Claude Agent SDK")
        except ImportError:
            # Fall back to standalone agent for evaluations
            from .standalone_agent import StandaloneAgent
            self._agent = StandaloneAgent(
                max_turns=self.config.agent_max_turns,
                mock_engine=self._mock_engine
            )
            await self._agent.start()
            self._log("Using StandaloneAgent (Claude Agent SDK not available)")

    async def _teardown_agent(self) -> None:
        """Cleanup the agent after evaluation."""
        if self._agent:
            await self._agent.stop()
            self._agent = None

        if self.config.use_mock_matlab:
            restore_real_engine()
            self._mock_engine = None

    def _setup_workspace_context(self, test_case: TestCase) -> None:
        """Setup workspace state from test case context."""
        if not self._mock_engine:
            return

        if not test_case.context or not test_case.context.workspace_state:
            return

        # Convert WorkspaceVariable to MockVariable and setup
        mock_vars = []
        for var in test_case.context.workspace_state.existing_vars:
            mock_vars.append(MockVariable(
                name=var.name,
                value=var.value,
                type=var.type,
                size=var.size
            ))

        self._mock_engine.setup_workspace(mock_vars)
        self._mock_engine.clear_execution_log()

    async def run_single_trial(
        self,
        test_case: TestCase,
        trial_number: int
    ) -> TrialResult:
        """Run a single trial of a test case.

        Args:
            test_case: The test case to run.
            trial_number: Which trial this is (1-indexed).

        Returns:
            TrialResult with response and judgment.
        """
        start_time = time.time()
        error = None
        response_text = ""
        tools_used = []

        try:
            # Setup workspace context
            self._setup_workspace_context(test_case)

            # Run the query
            self._log(f"  Trial {trial_number}: Sending prompt...")
            result = await asyncio.wait_for(
                self._agent.query_full(test_case.prompt),
                timeout=test_case.timeout
            )

            response_text = result.get("text", "")
            tools_used = [tu.get("name", "") for tu in result.get("tool_uses", [])]

            self._log(f"  Trial {trial_number}: Got response ({len(response_text)} chars, {len(tools_used)} tools)")

        except asyncio.TimeoutError:
            error = f"Timeout after {test_case.timeout} seconds"
            self._log(f"  Trial {trial_number}: {error}")
        except Exception as e:
            error = str(e)
            self._log(f"  Trial {trial_number}: Error - {error}")

        duration = time.time() - start_time

        # Judge the response
        self._log(f"  Trial {trial_number}: Evaluating response...")
        if error:
            judgment = JudgmentResult(
                passed=False,
                score=0.0,
                reasoning=f"Trial failed with error: {error}",
                criteria_scores=[],
                suggestions=[]
            )
        else:
            judgment = await self.judge.evaluate(
                prompt=test_case.prompt,
                response=response_text,
                criteria=test_case.evaluation_criteria,
                tools_used=tools_used
            )

        return TrialResult(
            trial_number=trial_number,
            response_text=response_text,
            tools_used=tools_used,
            judgment=judgment,
            duration_seconds=duration,
            error=error
        )

    async def run_test_case(self, test_case: TestCase) -> TestCaseResult:
        """Run all trials for a test case.

        Args:
            test_case: The test case to evaluate.

        Returns:
            TestCaseResult with all trial results.
        """
        self._log(f"Running test: {test_case.id} - {test_case.name}")

        trials = []
        for trial_num in range(1, test_case.trials + 1):
            trial_result = await self.run_single_trial(test_case, trial_num)
            trials.append(trial_result)

            # Early exit if trial passed and we have enough
            if trial_result.judgment.passed:
                self._log(f"  Trial {trial_num} passed, skipping remaining trials")
                break

        # Check tool usage requirements
        tool_usage_result = None
        if test_case.expected and test_case.expected.tool_usage:
            # Aggregate tools used across all trials
            all_tools_used = set()
            for trial in trials:
                all_tools_used.update(trial.tools_used)

            tool_usage_result = self.judge.evaluate_tool_usage(
                tools_used=list(all_tools_used),
                required_tools=test_case.expected.tool_usage.required,
                forbidden_tools=test_case.expected.tool_usage.forbidden
            )
            self._log(f"  Tool usage: {'PASS' if tool_usage_result.passed else 'FAIL'}")

        result = TestCaseResult(
            test_case=test_case,
            trials=trials,
            tool_usage_result=tool_usage_result
        )

        self._log(f"  Result: {'PASS' if result.passed else 'FAIL'} (score: {result.best_score:.2f})")
        return result

    async def run_all(
        self,
        test_cases: Optional[List[TestCase]] = None,
        tags: Optional[List[str]] = None,
        test_id: Optional[str] = None
    ) -> List[TestCaseResult]:
        """Run evaluation on multiple test cases.

        Args:
            test_cases: Specific test cases to run. If None, loads all.
            tags: Filter by tags (if test_cases is None).
            test_id: Run only a specific test case ID (if test_cases is None).

        Returns:
            List of TestCaseResult objects.
        """
        # Load test cases if not provided
        if test_cases is None:
            test_cases = self.loader.get_all_test_cases()

            # Apply filters
            if test_id:
                test_cases = self.loader.filter_by_id(test_cases, test_id)
            elif tags:
                test_cases = self.loader.filter_by_tags(test_cases, tags)

        if not test_cases:
            self._log("No test cases found matching criteria")
            return []

        self._log(f"Running {len(test_cases)} test case(s)...")

        results = []
        try:
            await self._setup_agent()

            for i, test_case in enumerate(test_cases, 1):
                self._log(f"\n[{i}/{len(test_cases)}] ", )
                result = await self.run_test_case(test_case)
                results.append(result)

        finally:
            await self._teardown_agent()

        return results


def run_evaluations(
    tags: Optional[List[str]] = None,
    test_id: Optional[str] = None,
    use_mock_matlab: bool = True,
    progress_callback: Optional[Callable[[str], None]] = None
) -> List[TestCaseResult]:
    """Convenience function to run evaluations synchronously.

    Args:
        tags: Filter by tags.
        test_id: Run only a specific test case ID.
        use_mock_matlab: Use mock MATLAB instead of real.
        progress_callback: Optional callback for progress updates.

    Returns:
        List of TestCaseResult objects.
    """
    config = EvalConfig(use_mock_matlab=use_mock_matlab)
    evaluator = Evaluator(config=config, progress_callback=progress_callback)
    return asyncio.run(evaluator.run_all(tags=tags, test_id=test_id))
