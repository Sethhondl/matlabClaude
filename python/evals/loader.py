"""
Test case loading from YAML files.
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional
import yaml

from .config import EvalConfig, DEFAULT_CONFIG


@dataclass
class WorkspaceVariable:
    """Represents a variable in the MATLAB workspace."""
    name: str
    type: str = "double"
    size: str = "[1, 1]"
    value: Optional[Any] = None


@dataclass
class WorkspaceState:
    """Represents the state of the MATLAB workspace."""
    existing_vars: List[WorkspaceVariable] = field(default_factory=list)


@dataclass
class TestContext:
    """Optional context for a test case."""
    workspace_state: Optional[WorkspaceState] = None
    simulink_model: Optional[str] = None
    current_directory: Optional[str] = None


@dataclass
class ToolUsageExpectation:
    """Expected tool usage for a test case."""
    required: List[str] = field(default_factory=list)
    forbidden: List[str] = field(default_factory=list)


@dataclass
class TestCaseExpectation:
    """Expected outcomes for a test case."""
    tool_usage: Optional[ToolUsageExpectation] = None
    contains_code: bool = False
    output_pattern: Optional[str] = None


@dataclass
class TestCase:
    """A single test case for evaluation."""
    id: str
    name: str
    prompt: str
    evaluation_criteria: List[str]

    # Optional fields
    tags: List[str] = field(default_factory=list)
    context: Optional[TestContext] = None
    expected: Optional[TestCaseExpectation] = None
    timeout: int = 60
    trials: int = 1

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TestCase":
        """Create a TestCase from a dictionary (parsed YAML)."""
        # Parse context if present
        context = None
        if "context" in data:
            ctx_data = data["context"]
            workspace_state = None

            if "workspace_state" in ctx_data:
                ws_data = ctx_data["workspace_state"]
                existing_vars = []
                for var_data in ws_data.get("existing_vars", []):
                    existing_vars.append(WorkspaceVariable(
                        name=var_data.get("name", ""),
                        type=var_data.get("type", "double"),
                        size=var_data.get("size", "[1, 1]"),
                        value=var_data.get("value")
                    ))
                workspace_state = WorkspaceState(existing_vars=existing_vars)

            context = TestContext(
                workspace_state=workspace_state,
                simulink_model=ctx_data.get("simulink_model"),
                current_directory=ctx_data.get("current_directory")
            )

        # Parse expected if present
        expected = None
        if "expected" in data:
            exp_data = data["expected"]
            tool_usage = None

            if "tool_usage" in exp_data:
                tu_data = exp_data["tool_usage"]
                tool_usage = ToolUsageExpectation(
                    required=tu_data.get("required", []),
                    forbidden=tu_data.get("forbidden", [])
                )

            expected = TestCaseExpectation(
                tool_usage=tool_usage,
                contains_code=exp_data.get("contains_code", False),
                output_pattern=exp_data.get("output_pattern")
            )

        return cls(
            id=data.get("id", ""),
            name=data.get("name", ""),
            prompt=data.get("prompt", ""),
            evaluation_criteria=data.get("evaluation_criteria", []),
            tags=data.get("tags", []),
            context=context,
            expected=expected,
            timeout=data.get("timeout", 60),
            trials=data.get("trials", 1)
        )


@dataclass
class TestSuite:
    """A collection of test cases from a single YAML file."""
    version: str
    name: str
    test_cases: List[TestCase]
    source_file: Optional[Path] = None

    @classmethod
    def from_yaml(cls, yaml_content: str, source_file: Optional[Path] = None) -> "TestSuite":
        """Parse a TestSuite from YAML content."""
        data = yaml.safe_load(yaml_content)

        test_cases = []
        for tc_data in data.get("test_cases", []):
            test_cases.append(TestCase.from_dict(tc_data))

        return cls(
            version=data.get("version", "1.0"),
            name=data.get("name", "Unnamed Suite"),
            test_cases=test_cases,
            source_file=source_file
        )

    @classmethod
    def from_file(cls, file_path: Path) -> "TestSuite":
        """Load a TestSuite from a YAML file."""
        with open(file_path, "r") as f:
            content = f.read()
        return cls.from_yaml(content, source_file=file_path)


class TestCaseLoader:
    """Loads test cases from YAML files."""

    def __init__(self, config: Optional[EvalConfig] = None):
        """Initialize the loader.

        Args:
            config: Evaluation configuration. Uses default if None.
        """
        self.config = config or DEFAULT_CONFIG

    def load_all(self) -> List[TestSuite]:
        """Load all test suites from the test_cases directory.

        Returns:
            List of TestSuite objects.
        """
        suites = []
        test_cases_dir = self.config.test_cases_dir

        if not test_cases_dir.exists():
            return suites

        for yaml_file in test_cases_dir.glob("*.yaml"):
            try:
                suite = TestSuite.from_file(yaml_file)
                suites.append(suite)
            except Exception as e:
                print(f"Warning: Failed to load {yaml_file}: {e}")

        # Also check for .yml files
        for yaml_file in test_cases_dir.glob("*.yml"):
            try:
                suite = TestSuite.from_file(yaml_file)
                suites.append(suite)
            except Exception as e:
                print(f"Warning: Failed to load {yaml_file}: {e}")

        return suites

    def load_file(self, file_path: Path) -> TestSuite:
        """Load a single test suite from a file.

        Args:
            file_path: Path to the YAML file.

        Returns:
            TestSuite object.
        """
        return TestSuite.from_file(file_path)

    def get_all_test_cases(self) -> List[TestCase]:
        """Get all test cases from all suites.

        Returns:
            Flat list of all test cases.
        """
        all_cases = []
        for suite in self.load_all():
            all_cases.extend(suite.test_cases)
        return all_cases

    def filter_by_tags(self, test_cases: List[TestCase], tags: List[str]) -> List[TestCase]:
        """Filter test cases by tags (AND logic - all tags must match).

        Args:
            test_cases: List of test cases to filter.
            tags: Tags to filter by.

        Returns:
            Filtered list of test cases.
        """
        if not tags:
            return test_cases

        return [tc for tc in test_cases if all(tag in tc.tags for tag in tags)]

    def filter_by_id(self, test_cases: List[TestCase], test_id: str) -> List[TestCase]:
        """Filter test cases by ID.

        Args:
            test_cases: List of test cases to filter.
            test_id: Test case ID to find.

        Returns:
            List containing the matching test case, or empty list if not found.
        """
        return [tc for tc in test_cases if tc.id == test_id]

    def list_test_cases(self) -> List[Dict[str, Any]]:
        """List all available test cases with summary info.

        Returns:
            List of dicts with id, name, tags, and source file info.
        """
        result = []
        for suite in self.load_all():
            for tc in suite.test_cases:
                result.append({
                    "id": tc.id,
                    "name": tc.name,
                    "tags": tc.tags,
                    "suite": suite.name,
                    "source": str(suite.source_file) if suite.source_file else None
                })
        return result
