"""
Session System - Thin wrapper on Claude Agent SDK.

Provides:
- SessionProcessor: Manages agent sessions and tool execution
"""

from .processor import SessionProcessor

__all__ = ["SessionProcessor"]
