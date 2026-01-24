"""
Structured JSON-lines logger for Claude Code MATLAB Python backend.

This module provides a logging system that outputs JSON-lines format logs
for machine parsing and behavioral reconstruction. It correlates with
MATLAB-side logging via shared session IDs.

Usage:
    from claudecode.logger import get_logger, set_session_id

    # Get logger instance
    logger = get_logger()

    # Set session ID (usually received from MATLAB)
    set_session_id("abc123")

    # Log events
    logger.info("bridge", "message_received", {"length": 150})
    logger.error("agent", "api_error", {"error": str(e)})

    # Timed operations
    with logger.span("agent", "api_call") as span:
        result = make_api_call()
        span.set_data({"tokens": result.tokens})

    # Or manual timing
    start = time.time()
    do_work()
    logger.info_timed("component", "work_done", {}, (time.time() - start) * 1000)
"""

import json
import os
import time
import threading
from contextlib import contextmanager
from datetime import datetime, timezone
from enum import IntEnum
from pathlib import Path
from typing import Any, Dict, Optional, Generator


class LogLevel(IntEnum):
    """Log level enumeration matching MATLAB LogLevel."""
    TRACE = 5
    DEBUG = 10
    INFO = 20
    WARN = 30
    ERROR = 40

    @classmethod
    def from_string(cls, level_str: str) -> "LogLevel":
        """Parse string to LogLevel."""
        mapping = {
            "TRACE": cls.TRACE,
            "DEBUG": cls.DEBUG,
            "INFO": cls.INFO,
            "WARN": cls.WARN,
            "WARNING": cls.WARN,
            "ERROR": cls.ERROR,
        }
        return mapping.get(level_str.upper(), cls.INFO)


class LogSpan:
    """Context manager for timed operations."""

    def __init__(
        self,
        logger: "StructuredLogger",
        level: LogLevel,
        component: str,
        event: str,
        data: Optional[Dict[str, Any]] = None,
        trace_id: Optional[str] = None,
    ):
        self.logger = logger
        self.level = level
        self.component = component
        self.event = event
        self.data = data or {}
        self.trace_id = trace_id
        self.start_time: Optional[float] = None
        self.end_time: Optional[float] = None

    def __enter__(self) -> "LogSpan":
        self.start_time = time.perf_counter()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> bool:
        self.end_time = time.perf_counter()
        duration_ms = (self.end_time - self.start_time) * 1000

        # Add error info if exception occurred
        if exc_type is not None:
            self.data["error"] = str(exc_val)
            self.data["error_type"] = exc_type.__name__
            self.logger._log(
                LogLevel.ERROR,
                self.component,
                f"{self.event}_error",
                self.data,
                duration_ms=duration_ms,
                trace_id=self.trace_id,
            )
        else:
            self.logger._log(
                self.level,
                self.component,
                f"{self.event}_complete",
                self.data,
                duration_ms=duration_ms,
                trace_id=self.trace_id,
            )

        return False  # Don't suppress exceptions

    def set_data(self, data: Dict[str, Any]) -> None:
        """Update span data before completion."""
        self.data.update(data)


class StructuredLogger:
    """Thread-safe structured JSON-lines logger."""

    def __init__(self):
        self._lock = threading.RLock()
        self._session_id: str = self._generate_session_id()
        self._level: LogLevel = LogLevel.INFO
        self._enabled: bool = True
        self._log_sensitive_data: bool = True
        self._log_directory: Optional[Path] = None
        self._file_handle: Optional[Any] = None
        self._current_file_path: Optional[Path] = None
        self._max_file_size: int = 10 * 1024 * 1024  # 10 MB
        self._max_files: int = 10
        self._write_count: int = 0
        self._console_output: bool = False

    def _generate_session_id(self) -> str:
        """Generate unique session identifier."""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        random_part = format(int(time.time() * 1000000) % 65536, "04X")
        return f"{timestamp}_{random_part}"

    @property
    def session_id(self) -> str:
        """Get current session ID."""
        return self._session_id

    @session_id.setter
    def session_id(self, value: str) -> None:
        """Set session ID (usually from MATLAB)."""
        with self._lock:
            self._session_id = value
            self._close_file()  # Will reopen with new session ID

    @property
    def level(self) -> LogLevel:
        """Get current log level."""
        return self._level

    @level.setter
    def level(self, value: LogLevel) -> None:
        """Set minimum log level."""
        self._level = value

    def set_level_from_string(self, level_str: str) -> None:
        """Set level from string."""
        self._level = LogLevel.from_string(level_str)

    @property
    def enabled(self) -> bool:
        """Check if logging is enabled."""
        return self._enabled

    @enabled.setter
    def enabled(self, value: bool) -> None:
        """Enable or disable logging."""
        self._enabled = value

    @property
    def log_sensitive_data(self) -> bool:
        """Check if sensitive data logging is enabled."""
        return self._log_sensitive_data

    @log_sensitive_data.setter
    def log_sensitive_data(self, value: bool) -> None:
        """Enable or disable sensitive data logging."""
        self._log_sensitive_data = value

    def set_log_directory(self, directory: Optional[str]) -> None:
        """Set log directory."""
        with self._lock:
            if directory:
                self._log_directory = Path(directory)
            else:
                self._log_directory = None
            self._close_file()

    def set_console_output(self, enabled: bool) -> None:
        """Enable/disable console output."""
        self._console_output = enabled

    def configure(
        self,
        enabled: bool = True,
        level: str = "INFO",
        log_directory: Optional[str] = None,
        log_sensitive_data: bool = True,
        max_file_size: int = 10485760,
        max_files: int = 10,
        session_id: Optional[str] = None,
    ) -> None:
        """Configure logger from settings."""
        with self._lock:
            self._enabled = enabled
            self._level = LogLevel.from_string(level)
            self._log_sensitive_data = log_sensitive_data
            self._max_file_size = max_file_size
            self._max_files = max_files

            if log_directory:
                self._log_directory = Path(log_directory)
            else:
                self._log_directory = None

            if session_id:
                self._session_id = session_id

            self._close_file()

    # Level-specific logging methods
    def error(
        self,
        component: str,
        event: str,
        data: Optional[Dict[str, Any]] = None,
        trace_id: Optional[str] = None,
    ) -> None:
        """Log error-level message."""
        self._log(LogLevel.ERROR, component, event, data, trace_id=trace_id)

    def warn(
        self,
        component: str,
        event: str,
        data: Optional[Dict[str, Any]] = None,
        trace_id: Optional[str] = None,
    ) -> None:
        """Log warning-level message."""
        self._log(LogLevel.WARN, component, event, data, trace_id=trace_id)

    def info(
        self,
        component: str,
        event: str,
        data: Optional[Dict[str, Any]] = None,
        trace_id: Optional[str] = None,
    ) -> None:
        """Log info-level message."""
        self._log(LogLevel.INFO, component, event, data, trace_id=trace_id)

    def debug(
        self,
        component: str,
        event: str,
        data: Optional[Dict[str, Any]] = None,
        trace_id: Optional[str] = None,
    ) -> None:
        """Log debug-level message."""
        self._log(LogLevel.DEBUG, component, event, data, trace_id=trace_id)

    def trace(
        self,
        component: str,
        event: str,
        data: Optional[Dict[str, Any]] = None,
        trace_id: Optional[str] = None,
    ) -> None:
        """Log trace-level message."""
        self._log(LogLevel.TRACE, component, event, data, trace_id=trace_id)

    # Timed logging methods
    def error_timed(
        self,
        component: str,
        event: str,
        data: Optional[Dict[str, Any]],
        duration_ms: float,
        trace_id: Optional[str] = None,
    ) -> None:
        """Log error with duration."""
        self._log(
            LogLevel.ERROR, component, event, data, duration_ms=duration_ms, trace_id=trace_id
        )

    def warn_timed(
        self,
        component: str,
        event: str,
        data: Optional[Dict[str, Any]],
        duration_ms: float,
        trace_id: Optional[str] = None,
    ) -> None:
        """Log warning with duration."""
        self._log(
            LogLevel.WARN, component, event, data, duration_ms=duration_ms, trace_id=trace_id
        )

    def info_timed(
        self,
        component: str,
        event: str,
        data: Optional[Dict[str, Any]],
        duration_ms: float,
        trace_id: Optional[str] = None,
    ) -> None:
        """Log info with duration."""
        self._log(
            LogLevel.INFO, component, event, data, duration_ms=duration_ms, trace_id=trace_id
        )

    def debug_timed(
        self,
        component: str,
        event: str,
        data: Optional[Dict[str, Any]],
        duration_ms: float,
        trace_id: Optional[str] = None,
    ) -> None:
        """Log debug with duration."""
        self._log(
            LogLevel.DEBUG, component, event, data, duration_ms=duration_ms, trace_id=trace_id
        )

    def trace_timed(
        self,
        component: str,
        event: str,
        data: Optional[Dict[str, Any]],
        duration_ms: float,
        trace_id: Optional[str] = None,
    ) -> None:
        """Log trace with duration."""
        self._log(
            LogLevel.TRACE, component, event, data, duration_ms=duration_ms, trace_id=trace_id
        )

    # Span context managers
    @contextmanager
    def span(
        self,
        component: str,
        event: str,
        data: Optional[Dict[str, Any]] = None,
        level: LogLevel = LogLevel.INFO,
        trace_id: Optional[str] = None,
    ) -> Generator[LogSpan, None, None]:
        """Create a timed span for an operation.

        Usage:
            with logger.span("agent", "api_call") as span:
                result = make_call()
                span.set_data({"tokens": result.tokens})
        """
        span_obj = LogSpan(self, level, component, event, data, trace_id)
        with span_obj:
            yield span_obj

    @contextmanager
    def info_span(
        self,
        component: str,
        event: str,
        data: Optional[Dict[str, Any]] = None,
        trace_id: Optional[str] = None,
    ) -> Generator[LogSpan, None, None]:
        """Convenience span at INFO level."""
        with self.span(component, event, data, LogLevel.INFO, trace_id) as s:
            yield s

    @contextmanager
    def debug_span(
        self,
        component: str,
        event: str,
        data: Optional[Dict[str, Any]] = None,
        trace_id: Optional[str] = None,
    ) -> Generator[LogSpan, None, None]:
        """Convenience span at DEBUG level."""
        with self.span(component, event, data, LogLevel.DEBUG, trace_id) as s:
            yield s

    def close(self) -> None:
        """Close log file."""
        with self._lock:
            self._close_file()

    def flush(self) -> None:
        """Flush buffered writes."""
        with self._lock:
            if self._file_handle:
                self._file_handle.flush()

    def _log(
        self,
        level: LogLevel,
        component: str,
        event: str,
        data: Optional[Dict[str, Any]] = None,
        duration_ms: Optional[float] = None,
        trace_id: Optional[str] = None,
    ) -> None:
        """Core logging method."""
        if not self._enabled or level < self._level:
            return

        try:
            entry = self._create_entry(level, component, event, data, duration_ms, trace_id)
            json_str = json.dumps(entry, default=str)

            if self._console_output:
                print(f"[{level.name}] {component}.{event}: {json_str}")

            self._write_to_file(json_str)

        except Exception as e:
            if self._console_output:
                print(f"Logger error: {e}")

    def _create_entry(
        self,
        level: LogLevel,
        component: str,
        event: str,
        data: Optional[Dict[str, Any]] = None,
        duration_ms: Optional[float] = None,
        trace_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Create structured log entry."""
        entry: Dict[str, Any] = {
            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
            "level": level.name,
            "session_id": self._session_id,
            "component": component,
            "event": event,
        }

        if data:
            # Sanitize sensitive data if needed
            if self._log_sensitive_data:
                entry["data"] = self._sanitize_data(data)
            else:
                entry["data"] = self._redact_sensitive(data)

        if duration_ms is not None:
            entry["duration_ms"] = round(duration_ms, 3)

        if trace_id:
            entry["trace_id"] = trace_id

        return entry

    def _sanitize_data(self, data: Any) -> Any:
        """Sanitize data for JSON encoding."""
        if isinstance(data, dict):
            return {k: self._sanitize_data(v) for k, v in data.items()}
        elif isinstance(data, (list, tuple)):
            return [self._sanitize_data(v) for v in data]
        elif isinstance(data, (str, int, float, bool, type(None))):
            return data
        elif isinstance(data, bytes):
            return f"<bytes:{len(data)}>"
        elif isinstance(data, Exception):
            return {"type": type(data).__name__, "message": str(data)}
        else:
            try:
                return str(data)
            except Exception:
                return f"<{type(data).__name__}>"

    def _redact_sensitive(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Redact potentially sensitive fields."""
        sensitive_keys = {
            "message",
            "content",
            "code",
            "password",
            "token",
            "key",
            "secret",
        }
        result = {}
        for k, v in data.items():
            if k.lower() in sensitive_keys:
                if isinstance(v, str):
                    result[k] = f"<redacted:{len(v)} chars>"
                else:
                    result[k] = "<redacted>"
            elif isinstance(v, dict):
                result[k] = self._redact_sensitive(v)
            else:
                result[k] = self._sanitize_data(v)
        return result

    def _write_to_file(self, json_str: str) -> None:
        """Write JSON string to log file."""
        with self._lock:
            if self._file_handle is None:
                self._open_file()

            if self._file_handle is None:
                return

            try:
                self._file_handle.write(json_str + "\n")
                self._file_handle.flush()  # Immediate flush

                self._write_count += 1
                if self._write_count % 100 == 0:
                    self._check_rotation()
            except Exception:
                pass  # Silently fail to not crash the app

    def _open_file(self) -> None:
        """Open log file for writing."""
        log_path = self._get_log_path()

        # Ensure directory exists
        log_path.parent.mkdir(parents=True, exist_ok=True)

        try:
            self._file_handle = open(log_path, "a", encoding="utf-8")
            self._current_file_path = log_path
        except Exception as e:
            if self._console_output:
                print(f"Failed to open log file {log_path}: {e}")

    def _close_file(self) -> None:
        """Close log file."""
        if self._file_handle:
            try:
                self._file_handle.close()
            except Exception:
                pass
            self._file_handle = None
            self._current_file_path = None

    def _get_log_path(self) -> Path:
        """Get path to log file."""
        if self._log_directory:
            log_dir = self._log_directory
        else:
            # Default to logs/ in project root
            log_dir = self._get_default_log_directory()

        return log_dir / f"python_{self._session_id}.jsonl"

    def _get_default_log_directory(self) -> Path:
        """Get default log directory (project root/logs)."""
        # Navigate up from python/claudecode to project root
        current_file = Path(__file__).resolve()
        project_root = current_file.parent.parent.parent  # logger.py -> claudecode -> python -> root

        # Verify by checking for CLAUDE.md
        if (project_root / "CLAUDE.md").exists():
            return project_root / "logs"

        # Fallback to temp directory
        import tempfile

        return Path(tempfile.gettempdir()) / "claudecode_logs"

    def _check_rotation(self) -> None:
        """Check if log rotation is needed."""
        if self._current_file_path and self._current_file_path.exists():
            if self._current_file_path.stat().st_size > self._max_file_size:
                self._rotate_files()

    def _rotate_files(self) -> None:
        """Rotate log files."""
        self._close_file()

        if not self._current_file_path:
            return

        log_dir = self._current_file_path.parent
        stem = self._current_file_path.stem
        suffix = self._current_file_path.suffix

        # Find existing rotated files
        pattern = f"{stem}.*{suffix}"
        existing = list(log_dir.glob(pattern))

        # Delete oldest if at limit
        if len(existing) >= self._max_files:
            existing.sort(key=lambda p: p.stat().st_mtime)
            for old_file in existing[: len(existing) - self._max_files + 1]:
                try:
                    old_file.unlink()
                except Exception:
                    pass

        # Rename current file
        rotation_num = len(existing) + 1
        rotated_path = log_dir / f"{stem}.{rotation_num}{suffix}"
        try:
            self._current_file_path.rename(rotated_path)
        except Exception:
            pass

        # Generate new session ID and open new file
        self._session_id = self._generate_session_id()
        self._open_file()


# Module-level singleton instance
_logger_instance: Optional[StructuredLogger] = None
_logger_lock = threading.Lock()


def get_logger() -> StructuredLogger:
    """Get the global logger instance."""
    global _logger_instance
    with _logger_lock:
        if _logger_instance is None:
            _logger_instance = StructuredLogger()
        return _logger_instance


def set_session_id(session_id: str) -> None:
    """Set the session ID for correlation with MATLAB logs."""
    get_logger().session_id = session_id


def configure_logger(
    enabled: bool = True,
    level: str = "INFO",
    log_directory: Optional[str] = None,
    log_sensitive_data: bool = True,
    max_file_size: int = 10485760,
    max_files: int = 10,
    session_id: Optional[str] = None,
) -> None:
    """Configure the global logger."""
    get_logger().configure(
        enabled=enabled,
        level=level,
        log_directory=log_directory,
        log_sensitive_data=log_sensitive_data,
        max_file_size=max_file_size,
        max_files=max_files,
        session_id=session_id,
    )
