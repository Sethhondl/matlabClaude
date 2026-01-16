"""
MATLAB Bridge - Simplified interface for MATLAB to call Python functionality.

This module provides a single class that wraps all functionality,
making it easy to call from MATLAB using py.claudecode.MatlabBridge().
"""

from typing import Any, Dict, List, Optional, Callable
import threading
from .process_manager import ClaudeProcessManager
from .agent_manager import AgentManager


class MatlabBridge:
    """Bridge class for MATLAB integration.

    Provides a unified interface for MATLAB to access Claude Code
    functionality via Python.

    Example (MATLAB):
        bridge = py.claudecode.MatlabBridge();
        if bridge.is_claude_available()
            response = bridge.send_message("Hello Claude");
        end
    """

    def __init__(self):
        """Initialize the bridge with process manager and agent manager."""
        self.process_manager = ClaudeProcessManager()
        self.agent_manager = AgentManager()
        self._async_response: Optional[Dict[str, Any]] = None
        self._async_chunks: List[str] = []
        self._async_complete: bool = False
        self._async_lock = threading.Lock()

    def is_claude_available(self) -> bool:
        """Check if Claude CLI is available."""
        return self.process_manager.is_claude_available()

    def get_claude_path(self) -> str:
        """Get path to Claude CLI."""
        return self.process_manager.get_claude_path()

    def dispatch_to_agent(
        self,
        message: str,
        context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Try to dispatch message to a custom agent.

        Args:
            message: The user's message
            context: Optional context dict

        Returns:
            Dict with 'handled', 'response', 'agent_name'
        """
        handled, response, agent_name = self.agent_manager.dispatch(
            message, context or {}
        )
        return {
            'handled': handled,
            'response': response,
            'agent_name': agent_name
        }

    def send_message(
        self,
        prompt: str,
        context: str = "",
        allowed_tools: Optional[List[str]] = None,
        timeout: float = 300,
        resume_session: bool = True
    ) -> Dict[str, Any]:
        """Send a message to Claude (synchronous).

        Args:
            prompt: The message to send
            context: Additional context to prepend
            allowed_tools: List of allowed tools
            timeout: Timeout in seconds
            resume_session: Whether to resume session

        Returns:
            Dict with 'text', 'success', 'error', 'session_id'
        """
        return self.process_manager.send_message(
            prompt=prompt,
            context=context,
            allowed_tools=allowed_tools,
            timeout=timeout,
            resume_session=resume_session
        )

    def start_async_message(
        self,
        prompt: str,
        context: str = "",
        allowed_tools: Optional[List[str]] = None,
        resume_session: bool = True
    ) -> None:
        """Start an async message to Claude.

        Use poll_async_chunks() and get_async_response() to get results.

        Args:
            prompt: The message to send
            context: Additional context
            allowed_tools: List of allowed tools
            resume_session: Whether to resume session
        """
        with self._async_lock:
            self._async_response = None
            self._async_chunks = []
            self._async_complete = False

        def on_chunk(chunk: str) -> None:
            with self._async_lock:
                self._async_chunks.append(chunk)

        def on_complete(response: Dict[str, Any]) -> None:
            with self._async_lock:
                self._async_response = response
                self._async_complete = True

        self.process_manager.send_message_async(
            prompt=prompt,
            chunk_callback=on_chunk,
            complete_callback=on_complete,
            context=context,
            allowed_tools=allowed_tools,
            resume_session=resume_session
        )

    def poll_async_chunks(self) -> List[str]:
        """Poll for new async chunks.

        Returns:
            List of new text chunks since last poll
        """
        with self._async_lock:
            chunks = self._async_chunks.copy()
            self._async_chunks = []
            return chunks

    def is_async_complete(self) -> bool:
        """Check if async message is complete."""
        with self._async_lock:
            return self._async_complete

    def get_async_response(self) -> Optional[Dict[str, Any]]:
        """Get the complete async response.

        Returns:
            Response dict if complete, None otherwise
        """
        with self._async_lock:
            return self._async_response

    def stop_process(self) -> None:
        """Stop any running Claude process."""
        self.process_manager.stop_process()

    def register_agent(self, agent: Any) -> None:
        """Register a custom agent.

        Args:
            agent: Agent instance (must have can_handle and handle methods)
        """
        self.agent_manager.register_agent(agent)

    def remove_agent(self, agent_name: str) -> bool:
        """Remove an agent by name."""
        return self.agent_manager.remove_agent(agent_name)

    def get_agent_names(self) -> List[str]:
        """Get list of registered agent names."""
        return self.agent_manager.get_agent_names()

    def get_session_id(self) -> str:
        """Get current session ID."""
        return self.process_manager.session_id
