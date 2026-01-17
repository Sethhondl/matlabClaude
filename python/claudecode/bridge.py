"""
MATLAB Bridge - Simplified interface for MATLAB to call Python functionality.

This module provides a single class that wraps all functionality,
making it easy to call from MATLAB using py.claudecode.MatlabBridge().

Uses the Claude Agent SDK for native tool support.
"""

from typing import Any, Dict, List, Optional
import threading
import asyncio
import atexit

from .agent_manager import AgentManager
from .image_queue import poll_images, clear_images

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
        self._agent_running = False  # Track if agent is actively running

        # CLI fallback mode
        self._process_manager: Optional[ClaudeProcessManager] = None

        # Async state
        self._async_response: Optional[Dict[str, Any]] = None
        self._async_chunks: List[str] = []  # Text-only chunks for backward compat
        self._async_content: List[Dict[str, Any]] = []  # Full structured content
        self._async_complete: bool = False
        self._async_lock = threading.Lock()
        self._async_thread: Optional[threading.Thread] = None

        # Persistent event loop for SDK mode (keeps agent alive between messages)
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._loop_thread: Optional[threading.Thread] = None

        # Initialize based on mode
        if self._use_sdk:
            self._agent = MatlabAgent()
            self._start_persistent_loop()
        else:
            self._process_manager = ClaudeProcessManager()

    def _start_persistent_loop(self) -> None:
        """Start a persistent event loop in a background thread.

        This keeps the SDK client alive between messages for conversation memory.
        """
        def run_loop():
            self._loop = asyncio.new_event_loop()
            asyncio.set_event_loop(self._loop)
            self._loop.run_forever()

        self._loop_thread = threading.Thread(target=run_loop, daemon=True)
        self._loop_thread.start()

        # Give the loop time to start
        import time
        time.sleep(0.1)

        # Register cleanup on exit
        atexit.register(self._cleanup_loop)

    def _cleanup_loop(self) -> None:
        """Clean up the persistent event loop."""
        if self._loop and self._loop.is_running():
            # Stop the agent first
            if self._agent_running and self._agent:
                future = asyncio.run_coroutine_threadsafe(
                    self._agent.stop(), self._loop
                )
                try:
                    future.result(timeout=5)
                except Exception:
                    pass
            self._loop.call_soon_threadsafe(self._loop.stop)

    def _run_in_loop(self, coro):
        """Run a coroutine in the persistent event loop and wait for result."""
        if not self._loop or not self._loop.is_running():
            raise RuntimeError("Event loop not running")
        future = asyncio.run_coroutine_threadsafe(coro, self._loop)
        return future.result()

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
            # Run async code in persistent event loop
            response = self._run_in_loop(self._query_agent_async(full_prompt))
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
        """Query agent asynchronously.

        Keeps the agent running between messages for conversation memory.
        """
        if not self._agent:
            raise RuntimeError("Agent not initialized")

        # Start agent lazily on first message
        if not self._agent_running:
            await self._agent.start()
            self._agent_running = True

        # Query without stopping - agent stays alive for conversation memory
        return await self._agent.query_full(prompt)

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
            self._async_content = []
            self._async_complete = False

        # Clear any stale images from previous requests
        clear_images()

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
        """Run SDK query in background thread.

        Keeps the agent running between messages for conversation memory.
        Uses the persistent event loop to maintain SDK client state.
        """
        full_prompt = f"{context}\n\n{prompt}" if context else prompt

        async def run():
            if not self._agent:
                return

            # Start agent lazily on first message
            if not self._agent_running:
                await self._agent.start()
                self._agent_running = True

            try:
                text_parts = []
                images = []

                async for content in self._agent.query(full_prompt):
                    with self._async_lock:
                        # Store full structured content
                        self._async_content.append(content)

                        # Also store text-only for backward compatibility
                        if content.get('type') == 'text':
                            self._async_chunks.append(content.get('text', ''))
                            text_parts.append(content.get('text', ''))
                        elif content.get('type') == 'image':
                            images.append(content.get('source', {}))
                        elif content.get('type') == 'tool_use':
                            tool_text = f"\n[Using tool: {content.get('name', 'unknown')}]\n"
                            self._async_chunks.append(tool_text)
                            text_parts.append(tool_text)

                with self._async_lock:
                    self._async_response = {
                        'text': ''.join(text_parts),
                        'images': images,
                        'success': True,
                        'error': '',
                        'session_id': self._agent.session_id or ''
                    }
                    self._async_complete = True

                # Increment turn count for compaction tracking
                self._agent.increment_turn()

                # Check if we need to compact the conversation
                if self._agent.turn_count >= self._agent.COMPACTION_THRESHOLD:
                    await self._agent.compact_conversation()

            except Exception as e:
                with self._async_lock:
                    self._async_response = {
                        'text': '',
                        'images': [],
                        'success': False,
                        'error': str(e),
                        'session_id': ''
                    }
                    self._async_complete = True
                # Don't stop agent on error - let it recover

        # Submit to persistent event loop (non-blocking)
        if self._loop and self._loop.is_running():
            asyncio.run_coroutine_threadsafe(run(), self._loop)
        else:
            # Fallback if loop not available
            asyncio.run(run())

    def poll_async_chunks(self) -> List[str]:
        """Poll for new async text chunks (backward compatible).

        Returns:
            List of new text chunks since last poll
        """
        with self._async_lock:
            chunks = self._async_chunks.copy()
            self._async_chunks = []
            return chunks

    def poll_async_content(self) -> List[Dict[str, Any]]:
        """Poll for new async content (text, images, tool use).

        Returns:
            List of content dicts since last poll. Each dict has:
            - {"type": "text", "text": "..."}
            - {"type": "image", "source": {"type": "base64", "media_type": "...", "data": "..."}}
            - {"type": "tool_use", "name": "..."}
        """
        with self._async_lock:
            content = self._async_content.copy()
            self._async_content = []

        # Also poll the direct image queue (for images from MCP tools)
        direct_images = poll_images()
        for img in direct_images:
            content.append(img)

        return content

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

    def clear_conversation(self) -> None:
        """Clear conversation history and reset the agent.

        This should be called when the user clicks the "Clear" button
        to start a fresh conversation.
        """
        if self._use_sdk and self._agent:
            if self._loop and self._loop.is_running():
                future = asyncio.run_coroutine_threadsafe(
                    self._reset_agent_async(), self._loop
                )
                try:
                    future.result(timeout=10)
                except Exception:
                    pass
            else:
                asyncio.run(self._reset_agent_async())

    async def _reset_agent_async(self) -> None:
        """Reset the agent asynchronously."""
        if self._agent_running and self._agent:
            await self._agent.stop()
            self._agent_running = False

        # Create fresh agent instance
        self._agent = MatlabAgent()

    def get_conversation_turns(self) -> int:
        """Get the current conversation turn count.

        Returns:
            Number of turns in the current conversation.
        """
        if self._use_sdk and self._agent:
            return self._agent.turn_count
        return 0
