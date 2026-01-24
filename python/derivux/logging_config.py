"""
Logging configuration utilities for Derivux MATLAB Python backend.

This module provides utilities for configuring the logger from
MATLAB settings and environment variables.

Usage:
    from derivux.logging_config import configure_from_matlab_settings

    # Configure logger from MATLAB settings dict
    configure_from_matlab_settings({
        'loggingEnabled': True,
        'logLevel': 'DEBUG',
        'logDirectory': '/path/to/logs',
        'logSensitiveData': True,
    })
"""

import os
from typing import Any, Dict, Optional

from derivux.logger import configure_logger, get_logger


def configure_from_matlab_settings(settings: Dict[str, Any]) -> None:
    """Configure logger from MATLAB Settings object converted to dict.

    Args:
        settings: Dictionary with settings from MATLAB Settings.m
            Expected keys (all optional):
            - loggingEnabled: bool
            - logLevel: str ('ERROR', 'WARN', 'INFO', 'DEBUG', 'TRACE')
            - logDirectory: str (path to log directory)
            - logSensitiveData: bool
            - logMaxFileSize: int (bytes)
            - logMaxFiles: int
    """
    configure_logger(
        enabled=settings.get("loggingEnabled", True),
        level=settings.get("logLevel", "INFO"),
        log_directory=settings.get("logDirectory") or None,
        log_sensitive_data=settings.get("logSensitiveData", True),
        max_file_size=settings.get("logMaxFileSize", 10485760),
        max_files=settings.get("logMaxFiles", 10),
        session_id=settings.get("sessionId"),
    )


def configure_from_environment() -> None:
    """Configure logger from environment variables.

    Environment variables:
        DERIVUX_LOG_ENABLED: '0', '1', 'true', 'false'
        DERIVUX_LOG_LEVEL: 'ERROR', 'WARN', 'INFO', 'DEBUG', 'TRACE'
        DERIVUX_LOG_DIR: Path to log directory
        DERIVUX_LOG_SENSITIVE: '0', '1', 'true', 'false'
        DERIVUX_SESSION_ID: Session ID for correlation
    """
    enabled = _parse_bool(os.environ.get("DERIVUX_LOG_ENABLED", "1"), True)
    level = os.environ.get("DERIVUX_LOG_LEVEL", "INFO")
    log_dir = os.environ.get("DERIVUX_LOG_DIR")
    sensitive = _parse_bool(os.environ.get("DERIVUX_LOG_SENSITIVE", "1"), True)
    session_id = os.environ.get("DERIVUX_SESSION_ID")

    configure_logger(
        enabled=enabled,
        level=level,
        log_directory=log_dir,
        log_sensitive_data=sensitive,
        session_id=session_id,
    )


def _parse_bool(value: Optional[str], default: bool) -> bool:
    """Parse string to boolean."""
    if value is None:
        return default
    return value.lower() in ("1", "true", "yes", "on")


def get_session_id() -> str:
    """Get current session ID."""
    return get_logger().session_id


def set_session_id(session_id: str) -> None:
    """Set session ID for cross-component correlation."""
    get_logger().session_id = session_id


# Convenience re-exports
__all__ = [
    "configure_from_matlab_settings",
    "configure_from_environment",
    "get_session_id",
    "set_session_id",
]
