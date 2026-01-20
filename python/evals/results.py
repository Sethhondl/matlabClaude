"""
Result aggregation and reporting for evaluation runs.
"""

import json
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from .evaluator import TestCaseResult


@dataclass
class TagStats:
    """Statistics for a specific tag."""
    tag: str
    total: int = 0
    passed: int = 0
    failed: int = 0
    average_score: float = 0.0

    @property
    def pass_rate(self) -> float:
        """Calculate pass rate as percentage."""
        return (self.passed / self.total * 100) if self.total > 0 else 0.0

    def to_dict(self) -> Dict:
        """Convert to dictionary."""
        return {
            "tag": self.tag,
            "total": self.total,
            "passed": self.passed,
            "failed": self.failed,
            "pass_rate": self.pass_rate,
            "average_score": self.average_score
        }


@dataclass
class EvalSummary:
    """Summary of an evaluation run."""
    timestamp: str
    total_tests: int
    passed: int
    failed: int
    total_duration_seconds: float
    average_score: float
    pass_rate: float
    tag_stats: List[TagStats] = field(default_factory=list)
    results: List[TestCaseResult] = field(default_factory=list)

    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "summary": {
                "timestamp": self.timestamp,
                "total_tests": self.total_tests,
                "passed": self.passed,
                "failed": self.failed,
                "pass_rate": self.pass_rate,
                "average_score": self.average_score,
                "total_duration_seconds": self.total_duration_seconds
            },
            "by_tag": [ts.to_dict() for ts in self.tag_stats],
            "results": [r.to_dict() for r in self.results]
        }


class ResultsAggregator:
    """Aggregates and reports evaluation results."""

    def __init__(self, results: List[TestCaseResult]):
        """Initialize with evaluation results.

        Args:
            results: List of TestCaseResult objects from evaluation.
        """
        self.results = results
        self._summary: Optional[EvalSummary] = None

    def compute_summary(self) -> EvalSummary:
        """Compute summary statistics from results.

        Returns:
            EvalSummary with aggregated statistics.
        """
        if self._summary is not None:
            return self._summary

        total = len(self.results)
        passed = sum(1 for r in self.results if r.passed)
        failed = total - passed

        total_duration = sum(r.total_duration for r in self.results)

        scores = [r.best_score for r in self.results]
        average_score = sum(scores) / len(scores) if scores else 0.0

        pass_rate = (passed / total * 100) if total > 0 else 0.0

        # Compute per-tag statistics
        tag_stats = self._compute_tag_stats()

        self._summary = EvalSummary(
            timestamp=datetime.now().isoformat(),
            total_tests=total,
            passed=passed,
            failed=failed,
            total_duration_seconds=total_duration,
            average_score=average_score,
            pass_rate=pass_rate,
            tag_stats=tag_stats,
            results=self.results
        )

        return self._summary

    def _compute_tag_stats(self) -> List[TagStats]:
        """Compute statistics grouped by tag."""
        tag_results: Dict[str, List[TestCaseResult]] = defaultdict(list)

        for result in self.results:
            for tag in result.test_case.tags:
                tag_results[tag].append(result)

        stats = []
        for tag, results in sorted(tag_results.items()):
            total = len(results)
            passed = sum(1 for r in results if r.passed)
            scores = [r.best_score for r in results]
            avg_score = sum(scores) / len(scores) if scores else 0.0

            stats.append(TagStats(
                tag=tag,
                total=total,
                passed=passed,
                failed=total - passed,
                average_score=avg_score
            ))

        return stats

    def to_json(self, indent: int = 2) -> str:
        """Export results as JSON string.

        Args:
            indent: JSON indentation level.

        Returns:
            JSON string representation.
        """
        summary = self.compute_summary()
        return json.dumps(summary.to_dict(), indent=indent)

    def save_json(self, output_path: Path) -> None:
        """Save results to a JSON file.

        Args:
            output_path: Path to output file.
        """
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        with open(output_path, "w") as f:
            f.write(self.to_json())

    def print_summary(self) -> None:
        """Print a human-readable summary to console."""
        summary = self.compute_summary()

        print("\n" + "=" * 60)
        print("EVALUATION RESULTS")
        print("=" * 60)
        print(f"Timestamp: {summary.timestamp}")
        print(f"Total Duration: {summary.total_duration_seconds:.1f}s")
        print()

        # Overall stats
        print("OVERALL:")
        print(f"  Tests: {summary.total_tests}")
        print(f"  Passed: {summary.passed}")
        print(f"  Failed: {summary.failed}")
        print(f"  Pass Rate: {summary.pass_rate:.1f}%")
        print(f"  Avg Score: {summary.average_score:.2f}")
        print()

        # Per-tag stats
        if summary.tag_stats:
            print("BY TAG:")
            max_tag_len = max(len(ts.tag) for ts in summary.tag_stats)
            for ts in summary.tag_stats:
                tag_padded = ts.tag.ljust(max_tag_len)
                print(f"  {tag_padded}  {ts.passed}/{ts.total} passed  "
                      f"({ts.pass_rate:.0f}%)  avg: {ts.average_score:.2f}")
            print()

        # Individual results
        print("DETAILS:")
        for result in self.results:
            status = "PASS" if result.passed else "FAIL"
            status_color = "\033[92m" if result.passed else "\033[91m"
            reset_color = "\033[0m"
            print(f"  [{status_color}{status}{reset_color}] {result.test_case.id}: "
                  f"{result.test_case.name} (score: {result.best_score:.2f})")

            # Show failure reasons for failed tests
            if not result.passed and result.trials:
                last_trial = result.trials[-1]
                if last_trial.error:
                    print(f"        Error: {last_trial.error}")
                elif last_trial.judgment.reasoning:
                    reasoning = last_trial.judgment.reasoning[:100]
                    if len(last_trial.judgment.reasoning) > 100:
                        reasoning += "..."
                    print(f"        Reason: {reasoning}")

        print()
        print("=" * 60)

        # Exit status indicator
        if summary.passed == summary.total_tests:
            print("\033[92mAll tests passed!\033[0m")
        else:
            print(f"\033[91m{summary.failed} test(s) failed\033[0m")

    def get_exit_code(self, min_pass_rate: float = 0.0) -> int:
        """Get appropriate exit code based on results.

        Args:
            min_pass_rate: Minimum pass rate to return success (0-100).

        Returns:
            0 if pass rate meets threshold, 1 otherwise.
        """
        summary = self.compute_summary()
        return 0 if summary.pass_rate >= min_pass_rate else 1


def aggregate_results(results: List[TestCaseResult]) -> EvalSummary:
    """Convenience function to aggregate results.

    Args:
        results: List of TestCaseResult objects.

    Returns:
        EvalSummary with computed statistics.
    """
    aggregator = ResultsAggregator(results)
    return aggregator.compute_summary()
