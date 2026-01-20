"""
Mock MATLAB engine for offline testing.

Provides a MockMatlabEngine that simulates MATLAB operations without
requiring an actual MATLAB installation.
"""

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional
import re


@dataclass
class ExecutionRecord:
    """Record of a code execution."""
    code: str
    output: str
    success: bool
    error: Optional[str] = None


@dataclass
class MockVariable:
    """A mock MATLAB workspace variable."""
    name: str
    value: Any
    type: str = "double"
    size: str = "[1, 1]"


class MockMatlabEngine:
    """Mock MATLAB engine for testing without MATLAB installed.

    This mock engine:
    - Tracks workspace variables
    - Simulates basic MATLAB operations
    - Records all executed code for validation
    - Can be configured with initial workspace state
    """

    def __init__(self):
        self._connected: bool = False
        self._workspace: Dict[str, MockVariable] = {}
        self._execution_log: List[ExecutionRecord] = []
        self._figure_count: int = 0

    @property
    def is_available(self) -> bool:
        """Always available since it's a mock."""
        return True

    @property
    def is_connected(self) -> bool:
        """Check if 'connected' to the mock engine."""
        return self._connected

    def connect(self, shared_session: bool = True) -> bool:
        """Simulate connecting to MATLAB."""
        self._connected = True
        return True

    def disconnect(self) -> None:
        """Simulate disconnecting from MATLAB."""
        self._connected = False

    def eval(self, code: str, capture_output: bool = True) -> str:
        """Simulate executing MATLAB code.

        Args:
            code: MATLAB code to 'execute'.
            capture_output: Whether to return output.

        Returns:
            Simulated output string.
        """
        if not self._connected:
            self.connect()

        code = code.strip()
        output = ""
        success = True
        error = None

        try:
            # Handle common MATLAB commands
            output = self._simulate_command(code)
        except Exception as e:
            success = False
            error = str(e)
            output = f"Error: {error}"

        # Log the execution
        self._execution_log.append(ExecutionRecord(
            code=code,
            output=output,
            success=success,
            error=error
        ))

        return output if capture_output else ""

    def _simulate_command(self, code: str) -> str:
        """Simulate a MATLAB command and return output."""
        # Handle 'who' command
        if code.strip() == "who":
            if not self._workspace:
                return ""
            return " ".join(self._workspace.keys())

        # Handle 'whos' command
        if code.strip().startswith("whos"):
            match = re.match(r"whos\('(\w+)'\)", code)
            if match:
                var_name = match.group(1)
                if var_name in self._workspace:
                    var = self._workspace[var_name]
                    return f"  Name      Size            Bytes  Class     Attributes\n  {var.name}       {var.size}              8  {var.type}"
            return ""

        # Handle 'size' command
        size_match = re.match(r"size\((\w+)\)", code)
        if size_match:
            var_name = size_match.group(1)
            if var_name in self._workspace:
                var = self._workspace[var_name]
                # Parse size string like "[5, 5]" -> "5     5"
                size_str = var.size.strip("[]").replace(",", "")
                return size_str
            raise ValueError(f"Undefined function or variable '{var_name}'")

        # Handle 'class' command
        class_match = re.match(r"class\((\w+)\)", code)
        if class_match:
            var_name = class_match.group(1)
            if var_name in self._workspace:
                return self._workspace[var_name].type
            raise ValueError(f"Undefined function or variable '{var_name}'")

        # Handle 'eye' command (identity matrix)
        eye_match = re.match(r"(\w+)\s*=\s*eye\((\d+)\)", code)
        if eye_match:
            var_name = eye_match.group(1)
            n = int(eye_match.group(2))
            self._workspace[var_name] = MockVariable(
                name=var_name,
                value=f"eye({n})",
                type="double",
                size=f"[{n}, {n}]"
            )
            return ""

        # Handle 'zeros' command
        zeros_match = re.match(r"(\w+)\s*=\s*zeros\((\d+)(?:,\s*(\d+))?\)", code)
        if zeros_match:
            var_name = zeros_match.group(1)
            m = int(zeros_match.group(2))
            n = int(zeros_match.group(3)) if zeros_match.group(3) else m
            self._workspace[var_name] = MockVariable(
                name=var_name,
                value=f"zeros({m},{n})",
                type="double",
                size=f"[{m}, {n}]"
            )
            return ""

        # Handle 'ones' command
        ones_match = re.match(r"(\w+)\s*=\s*ones\((\d+)(?:,\s*(\d+))?\)", code)
        if ones_match:
            var_name = ones_match.group(1)
            m = int(ones_match.group(2))
            n = int(ones_match.group(3)) if ones_match.group(3) else m
            self._workspace[var_name] = MockVariable(
                name=var_name,
                value=f"ones({m},{n})",
                type="double",
                size=f"[{m}, {n}]"
            )
            return ""

        # Handle 'rand' command
        rand_match = re.match(r"(\w+)\s*=\s*rand\((\d+)(?:,\s*(\d+))?\)", code)
        if rand_match:
            var_name = rand_match.group(1)
            m = int(rand_match.group(2))
            n = int(rand_match.group(3)) if rand_match.group(3) else m
            self._workspace[var_name] = MockVariable(
                name=var_name,
                value=f"rand({m},{n})",
                type="double",
                size=f"[{m}, {n}]"
            )
            return ""

        # Handle 'linspace' command
        linspace_match = re.match(r"(\w+)\s*=\s*linspace\(([^,]+),\s*([^,]+),\s*(\d+)\)", code)
        if linspace_match:
            var_name = linspace_match.group(1)
            n = int(linspace_match.group(4))
            self._workspace[var_name] = MockVariable(
                name=var_name,
                value=f"linspace",
                type="double",
                size=f"[1, {n}]"
            )
            return ""

        # Handle simple variable assignment (e.g., x = 5)
        assign_match = re.match(r"(\w+)\s*=\s*(.+)", code)
        if assign_match:
            var_name = assign_match.group(1)
            value_str = assign_match.group(2).strip().rstrip(";")
            self._workspace[var_name] = MockVariable(
                name=var_name,
                value=value_str,
                type="double",
                size="[1, 1]"
            )
            return ""

        # Handle 'figure' command
        if code.strip().startswith("figure"):
            self._figure_count += 1
            return ""

        # Handle 'close' command
        if code.strip().startswith("close"):
            return ""

        # Handle plotting commands (just acknowledge them)
        if any(cmd in code for cmd in ["plot", "surf", "mesh", "contour", "bar", "histogram", "scatter"]):
            return ""

        # Handle 'print' and 'saveas' commands
        if code.strip().startswith("print") or code.strip().startswith("saveas"):
            return ""

        # Handle 'findall' for figure handles
        if "findall" in code and "figure" in code:
            return ""

        # Handle 'num2str' command
        if code.strip().startswith("num2str"):
            return ""

        # Handle 'disp' command
        disp_match = re.match(r"disp\((['\"]?)(.+)\1\)", code)
        if disp_match:
            return disp_match.group(2)

        # Handle 'fprintf' command
        if code.strip().startswith("fprintf"):
            return "[fprintf output]"

        # Default: just acknowledge execution
        return f"Code executed: {code[:50]}..." if len(code) > 50 else f"Code executed: {code}"

    def get_variable(self, name: str) -> Any:
        """Get a variable from the mock workspace."""
        if name not in self._workspace:
            raise ValueError(f"Undefined function or variable '{name}'")
        return self._workspace[name].value

    def set_variable(self, name: str, value: Any) -> None:
        """Set a variable in the mock workspace."""
        self._workspace[name] = MockVariable(
            name=name,
            value=value,
            type=type(value).__name__,
            size="[1, 1]"
        )

    def list_variables(self) -> List[str]:
        """List all variables in the mock workspace."""
        return list(self._workspace.keys())

    def get_variable_info(self, name: str) -> dict:
        """Get information about a variable."""
        if name not in self._workspace:
            return {"name": name, "size": "", "class": "", "bytes": 0}

        var = self._workspace[name]
        return {
            "name": var.name,
            "size": var.size,
            "class": var.type,
            "bytes": 8
        }

    def save_figure(self, filename: str, format: str = "png") -> str:
        """Simulate saving a figure."""
        return f"{filename}.{format}"

    # Methods for test setup and validation

    def setup_workspace(self, variables: List[MockVariable]) -> None:
        """Setup initial workspace state for testing.

        Args:
            variables: List of MockVariable objects to add to workspace.
        """
        for var in variables:
            self._workspace[var.name] = var

    def get_execution_log(self) -> List[ExecutionRecord]:
        """Get the log of all executed commands.

        Returns:
            List of ExecutionRecord objects.
        """
        return self._execution_log.copy()

    def clear_execution_log(self) -> None:
        """Clear the execution log."""
        self._execution_log.clear()

    def reset(self) -> None:
        """Reset the mock engine to initial state."""
        self._workspace.clear()
        self._execution_log.clear()
        self._figure_count = 0
        self._connected = False


# Global mock engine instance
_mock_engine: Optional[MockMatlabEngine] = None
_original_get_engine = None


def get_mock_engine() -> MockMatlabEngine:
    """Get the global mock MATLAB engine instance.

    Returns:
        MockMatlabEngine instance.
    """
    global _mock_engine
    if _mock_engine is None:
        _mock_engine = MockMatlabEngine()
    return _mock_engine


def inject_mock_engine() -> MockMatlabEngine:
    """Inject the mock engine into the matlab_engine module.

    This replaces the real get_engine function with one that returns
    the mock engine, allowing offline testing.

    Returns:
        The mock engine instance.
    """
    global _original_get_engine

    # Import here to avoid circular imports
    from claudecode import matlab_engine

    # Save original if not already saved
    if _original_get_engine is None:
        _original_get_engine = matlab_engine.get_engine

    # Create mock and inject
    mock = get_mock_engine()
    matlab_engine.get_engine = lambda: mock

    return mock


def restore_real_engine() -> None:
    """Restore the real MATLAB engine after mock injection."""
    global _original_get_engine

    if _original_get_engine is not None:
        from claudecode import matlab_engine
        matlab_engine.get_engine = _original_get_engine
        _original_get_engine = None
