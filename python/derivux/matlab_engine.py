"""
MATLAB Engine Wrapper - Manages connection to MATLAB.

This module provides a singleton wrapper around the MATLAB Engine API
for Python, handling connection lifecycle and providing utility methods.
"""

from typing import Optional, Any, List
import io

# Try to import matlab.engine - it may not be installed
try:
    import matlab.engine
    MATLAB_AVAILABLE = True
except ImportError:
    MATLAB_AVAILABLE = False
    matlab = None


class MatlabEngineWrapper:
    """Wrapper for MATLAB Engine with connection management."""

    def __init__(self):
        self._engine: Optional[Any] = None
        self._connected: bool = False

    @property
    def is_available(self) -> bool:
        """Check if MATLAB Engine API is available."""
        return MATLAB_AVAILABLE

    @property
    def is_connected(self) -> bool:
        """Check if connected to MATLAB."""
        return self._connected and self._engine is not None

    def connect(self, shared_session: bool = True) -> bool:
        """Connect to MATLAB engine.

        Args:
            shared_session: If True, try to connect to existing shared session first.

        Returns:
            True if connection successful.
        """
        if not MATLAB_AVAILABLE:
            raise RuntimeError(
                "MATLAB Engine API not available. "
                "Install with: pip install matlabengine"
            )

        if self._connected and self._engine:
            return True

        try:
            if shared_session:
                # Try to connect to existing shared session
                sessions = matlab.engine.find_matlab()
                if sessions:
                    self._engine = matlab.engine.connect_matlab(sessions[0])
                    self._connected = True
                    return True

            # Start new MATLAB session
            self._engine = matlab.engine.start_matlab()
            self._connected = True
            return True

        except Exception as e:
            self._connected = False
            raise RuntimeError(f"Failed to connect to MATLAB: {e}")

    def disconnect(self) -> None:
        """Disconnect from MATLAB engine."""
        if self._engine:
            try:
                self._engine.quit()
            except Exception:
                pass
            self._engine = None
        self._connected = False

    def eval(self, code: str, capture_output: bool = True) -> str:
        """Execute MATLAB code and return output.

        Args:
            code: MATLAB code to execute.
            capture_output: If True, capture command window output.

        Returns:
            Output from MATLAB command window.
        """
        if not self.is_connected:
            self.connect()

        if capture_output:
            out = io.StringIO()
            err = io.StringIO()
            self._engine.eval(code, nargout=0, stdout=out, stderr=err)
            result = out.getvalue()
            errors = err.getvalue()
            if errors:
                result += f"\n[Warnings/Errors]:\n{errors}"
            return result
        else:
            self._engine.eval(code, nargout=0)
            return ""

    def get_variable(self, name: str) -> Any:
        """Get a variable from MATLAB workspace.

        Args:
            name: Variable name.

        Returns:
            Variable value (converted to Python type).
        """
        if not self.is_connected:
            self.connect()

        return self._engine.workspace[name]

    def set_variable(self, name: str, value: Any) -> None:
        """Set a variable in MATLAB workspace.

        Args:
            name: Variable name.
            value: Value to set.
        """
        if not self.is_connected:
            self.connect()

        self._engine.workspace[name] = value

    def list_variables(self) -> List[str]:
        """List all variables in MATLAB workspace.

        Returns:
            List of variable names.
        """
        if not self.is_connected:
            self.connect()

        # Use 'who' command to get variable names
        out = io.StringIO()
        self._engine.eval("who", nargout=0, stdout=out)
        output = out.getvalue()

        # Parse the output - 'who' returns space-separated names
        if not output.strip():
            return []

        return output.split()

    def get_variable_info(self, name: str) -> dict:
        """Get information about a variable.

        Args:
            name: Variable name.

        Returns:
            Dict with 'size', 'class', 'bytes' info.
        """
        if not self.is_connected:
            self.connect()

        out = io.StringIO()
        self._engine.eval(f"whos('{name}')", nargout=0, stdout=out)

        # Parse whos output
        info = {"name": name, "size": "", "class": "", "bytes": 0}

        # Try to get size
        try:
            size = self._engine.eval(f"size({name})", nargout=1)
            info["size"] = str(list(size[0]))
        except Exception:
            pass

        # Try to get class
        try:
            cls = self._engine.eval(f"class({name})", nargout=1)
            info["class"] = str(cls)
        except Exception:
            pass

        return info

    def save_figure(self, filename: str, format: str = "png") -> str:
        """Save current figure to file.

        Args:
            filename: Output filename (without extension).
            format: Image format ('png', 'svg', 'pdf', 'jpg').

        Returns:
            Full path to saved file.
        """
        if not self.is_connected:
            self.connect()

        full_path = f"{filename}.{format}"
        self._engine.eval(f"saveas(gcf, '{full_path}')", nargout=0)
        return full_path


# Global singleton instance
_engine_wrapper: Optional[MatlabEngineWrapper] = None


def get_engine() -> MatlabEngineWrapper:
    """Get the global MATLAB engine wrapper instance.

    Returns:
        MatlabEngineWrapper instance.
    """
    global _engine_wrapper
    if _engine_wrapper is None:
        _engine_wrapper = MatlabEngineWrapper()
    return _engine_wrapper


def stop_engine() -> None:
    """Stop and cleanup the global MATLAB engine."""
    global _engine_wrapper
    if _engine_wrapper:
        _engine_wrapper.disconnect()
        _engine_wrapper = None
