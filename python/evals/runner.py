"""
CLI entry point for running evaluations.

Usage:
    python -m evals.runner                          # Run all tests
    python -m evals.runner --tags matlab basic      # Filter by tags
    python -m evals.runner --test-case matlab_gen_001  # Run specific test
    python -m evals.runner --use-real-matlab        # Use real MATLAB
    python -m evals.runner --output results/run.json  # Save results
    python -m evals.runner --list                   # List available tests
"""

import argparse
import asyncio
import sys
from pathlib import Path
from typing import List, Optional

from .config import EvalConfig
from .evaluator import Evaluator
from .loader import TestCaseLoader
from .results import ResultsAggregator


def create_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        description="Run evaluations for the MATLAB Claude agent",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python -m evals.runner                            # Run all tests
  python -m evals.runner --tags matlab basic        # Filter by tags
  python -m evals.runner --test-case matlab_gen_001 # Run specific test
  python -m evals.runner --use-real-matlab          # Use real MATLAB
  python -m evals.runner --output results/run.json  # Save JSON results
  python -m evals.runner --list                     # List available tests
        """
    )

    parser.add_argument(
        "--tags",
        nargs="+",
        help="Filter test cases by tags (AND logic - all must match)"
    )

    parser.add_argument(
        "--test-case",
        dest="test_case",
        help="Run only a specific test case by ID"
    )

    parser.add_argument(
        "--use-real-matlab",
        dest="use_real_matlab",
        action="store_true",
        help="Use real MATLAB instead of mock (requires MATLAB installed)"
    )

    parser.add_argument(
        "--output", "-o",
        type=Path,
        help="Save results to JSON file"
    )

    parser.add_argument(
        "--list", "-l",
        action="store_true",
        help="List available test cases and exit"
    )

    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Show detailed progress output"
    )

    parser.add_argument(
        "--min-pass-rate",
        type=float,
        default=0.0,
        help="Minimum pass rate (0-100) for exit code 0 (default: 0)"
    )

    parser.add_argument(
        "--timeout",
        type=int,
        default=60,
        help="Default timeout per test case in seconds (default: 60)"
    )

    return parser


def list_test_cases() -> None:
    """Print a list of all available test cases."""
    loader = TestCaseLoader()
    test_cases = loader.list_test_cases()

    if not test_cases:
        print("No test cases found.")
        print(f"Test cases directory: {loader.config.test_cases_dir}")
        return

    print(f"\nAvailable test cases ({len(test_cases)} total):\n")

    # Group by suite
    by_suite = {}
    for tc in test_cases:
        suite = tc.get("suite", "Unknown")
        if suite not in by_suite:
            by_suite[suite] = []
        by_suite[suite].append(tc)

    for suite, cases in sorted(by_suite.items()):
        print(f"  {suite}:")
        for tc in cases:
            tags_str = f" [{', '.join(tc['tags'])}]" if tc["tags"] else ""
            print(f"    - {tc['id']}: {tc['name']}{tags_str}")
        print()


def create_progress_callback(verbose: bool):
    """Create a progress callback function."""
    def callback(message: str):
        if verbose:
            print(message)
        elif message.startswith("[") or message.startswith("Running"):
            # Always show test case progress
            print(message)

    return callback


async def run_evals(
    tags: Optional[List[str]] = None,
    test_id: Optional[str] = None,
    use_mock_matlab: bool = True,
    verbose: bool = False,
    default_timeout: int = 60
) -> ResultsAggregator:
    """Run evaluations and return aggregator.

    Args:
        tags: Filter by tags.
        test_id: Run specific test case.
        use_mock_matlab: Use mock MATLAB.
        verbose: Show detailed output.
        default_timeout: Default timeout per test.

    Returns:
        ResultsAggregator with results.
    """
    config = EvalConfig(
        use_mock_matlab=use_mock_matlab,
        default_timeout=default_timeout
    )

    progress_callback = create_progress_callback(verbose)
    evaluator = Evaluator(config=config, progress_callback=progress_callback)

    results = await evaluator.run_all(tags=tags, test_id=test_id)
    return ResultsAggregator(results)


def main() -> int:
    """Main entry point.

    Returns:
        Exit code (0 for success, 1 for failure).
    """
    parser = create_parser()
    args = parser.parse_args()

    # Handle --list
    if args.list:
        list_test_cases()
        return 0

    # Run evaluations
    print("MATLAB Agent Evaluation Framework")
    print("-" * 40)

    use_mock = not args.use_real_matlab
    print(f"MATLAB Mode: {'Mock' if use_mock else 'Real'}")

    if args.tags:
        print(f"Filter tags: {', '.join(args.tags)}")
    if args.test_case:
        print(f"Test case: {args.test_case}")

    print()

    try:
        aggregator = asyncio.run(run_evals(
            tags=args.tags,
            test_id=args.test_case,
            use_mock_matlab=use_mock,
            verbose=args.verbose,
            default_timeout=args.timeout
        ))

        # Print summary
        aggregator.print_summary()

        # Save results if requested
        if args.output:
            aggregator.save_json(args.output)
            print(f"\nResults saved to: {args.output}")

        # Return appropriate exit code
        return aggregator.get_exit_code(min_pass_rate=args.min_pass_rate)

    except KeyboardInterrupt:
        print("\n\nEvaluation interrupted by user")
        return 130

    except Exception as e:
        print(f"\nError during evaluation: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
