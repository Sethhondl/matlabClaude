"""
MATLAB Bridge - Simplified interface for MATLAB to call Python functionality.

This module provides a single class that wraps all functionality,
making it easy to call from MATLAB using py.claudecode.MatlabBridge().

Uses the Claude Agent SDK for native tool support.
"""

from typing import Any, Dict, List, Optional
import threading
import asyncio

from .agent_manager import AgentManager

# Try to import the agent (requires claude-agent-sdk and Python 3.10+)
try:
    from claude_agent_sdk import ClaudeAgentOptions
    from .agent import MatlabAgent
    AGENT_SDK_AVAILABLE = True
except ImportError:
    AGENT_SDK_AVAILABLE = False
    MatlabAgent = None
    ClaudeAgentOptions = None

# Fallback to process manager if SDK not available
from .process_manager import ClaudeProcessManager


class MatlabBridge:
    """Bridge class for MATLAB integration.

    Provides a unified interface for MATLAB to access Claude
    functionality via Python. Uses the Claude Agent SDK when available,
    with fallback to CLI wrapper.

    Example (MATLAB):
        bridge = py.claudecode.MatlabBridge();
        if bridge.is_claude_available()
            response = bridge.send_message("Hello Claude");
        end
    """

    def __init__(self, use_agent_sdk: bool = True):
        """Initialize the bridge.

        Args:
            use_agent_sdk: If True, use Claude Agent SDK (recommended).
                          If False or SDK unavailable, use CLI wrapper.
        """
        self.agent_manager = AgentManager()
        self._use_sdk = use_agent_sdk and AGENT_SDK_AVAILABLE

        # Agent SDK mode
        self._agent: Optional[MatlabAgent] = None
        self._agent_started = False

        # CLI fallback mode
        self._process_manager: Optional[ClaudeProcessManager] = None

        # Async state
        self._async_response: Optional[Dict[str, Any]] = None
        self._async_chunks: List[str] = []
        self._async_complete: bool = False
        self._async_lock = threading.Lock()
        self._async_thread: Optional[threading.Thread] = None

        # Initialize based on mode
        if self._use_sdk:
            self._agent = MatlabAgent()
        else:
            self._process_manager = ClaudeProcessManager()

    @property
    def using_agent_sdk(self) -> bool:
        """Check if using Agent SDK mode."""
        return self._use_sdk

    def is_claude_available(self) -> bool:
        """Check if Claude is available."""
        if self._use_sdk:
            # SDK mode - always available if SDK is installed
            return AGENT_SDK_AVAILABLE
        else:
            # CLI mode
            return self._process_manager.is_claude_available()

    def get_claude_path(self) -> str:
        """Get path to Claude CLI (CLI mode only)."""
        if self._process_manager:
            return self._process_manager.get_claude_path()
        return ""

    def dispatch_to_agent(
        self,
        message: str,
        context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Try to dispatch message to a local interceptor agent.

        Args:
            message: The user's message
            context: Optional context dict

        Returns:
            Dict with 'handled', 'response', 'agent_name'
        """
        message = str(message) if message else ""

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
            allowed_tools: List of allowed tools (CLI mode only)
            timeout: Timeout in seconds
            resume_session: Whether to resume session

        Returns:
            Dict with 'text', 'success', 'error', 'session_id'
        """
        prompt = str(prompt) if prompt else ""
        context = str(context) if context else ""

        if self._use_sdk:
            return self._send_message_sdk(prompt, context)
        else:
            return self._process_manager.send_message(
                prompt=prompt,
                context=context,
                allowed_tools=allowed_tools,
                timeout=timeout,
                resume_session=resume_session
            )

    def _send_message_sdk(self, prompt: str, context: str) -> Dict[str, Any]:
        """Send message using Agent SDK (synchronous wrapper)."""
        full_prompt = f"{context}\n\n{prompt}" if context else prompt

        try:
            # Run async code in new event loop
            response = asyncio.run(self._query_agent_async(full_prompt))
            return {
                'text': response.get('text', ''),
                'success': True,
                'error': '',
                'session_id': response.get('session_id', ''),
                'tool_uses': response.get('tool_uses', [])
            }
        except Exception as e:
            return {
                'text': '',
                'success': False,
                'error': str(e),
                'session_id': '',
                'tool_uses': []
            }

    async def _query_agent_async(self, prompt: str) -> Dict[str, Any]:
        """Query agent asynchronously."""
        if not self._agent:
            raise RuntimeError("Agent not initialized")

        await self._agent.start()
        try:
            return await self._agent.query_full(prompt)
        finally:
            await self._agent.stop()

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
            allowed_tools: List of allowed tools (CLI mode only)
            resume_session: Whether to resume session
        """
        prompt = str(prompt) if prompt else ""
        context = str(context) if context else ""

        with self._async_lock:
            self._async_response = None
            self._async_chunks = []
            self._async_complete = False

        if self._use_sdk:
            # Run SDK async in background thread
            self._async_thread = threading.Thread(
                target=self._run_sdk_async,
                args=(prompt, context),
                daemon=True
            )
            self._async_thread.start()
        else:
            # Use process manager async
            def on_chunk(chunk: str) -> None:
                with self._async_lock:
                    self._async_chunks.append(chunk)

            def on_complete(response: Dict[str, Any]) -> None:
                with self._async_lock:
                    self._async_response = response
                    self._async_complete = True

            self._process_manager.send_message_async(
                prompt=prompt,
                chunk_callback=on_chunk,
                complete_callback=on_complete,
                context=context,
                allowed_tools=allowed_tools,
                resume_session=resume_session
            )

    def _run_sdk_async(self, prompt: str, context: str) -> None:
        """Run SDK query in background thread."""
        full_prompt = f"{context}\n\n{prompt}" if context else prompt

        async def run():
            if not self._agent:
                return

            await self._agent.start()
            try:
                async for chunk in self._agent.query(full_prompt):
                    with self._async_lock:
                        self._async_chunks.append(chunk)

                with self._async_lock:
                    self._async_response = {
                        'text': ''.join(self._async_chunks),
                        'success': True,
                        'error': '',
                        'session_id': self._agent.session_id or ''
                    }
                    self._async_complete = True
            except Exception as e:
                with self._async_lock:
                    self._async_response = {
                        'text': '',
                        'success': False,
                        'error': str(e),
                        'session_id': ''
                    }
                    self._async_complete = True
            finally:
                await self._agent.stop()

        asyncio.run(run())

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
        """Stop any running process."""
        if self._process_manager:
            self._process_manager.stop_process()

    def register_agent(self, agent: Any) -> None:
        """Register a local interceptor agent.

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
        if self._use_sdk and self._agent:
            return self._agent.session_id or ''
        elif self._process_manager:
            return self._process_manager.session_id
        return ''
