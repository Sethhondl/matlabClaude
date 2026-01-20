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
import time

from .agent_manager import AgentManager
from .image_queue import poll_images, clear_images
from .specialized_agent_manager import SpecializedAgentManager, RoutingResult
from .logger import get_logger, configure_logger

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
        self._logger = get_logger()
        self.agent_manager = AgentManager()
        self._use_sdk = use_agent_sdk and AGENT_SDK_AVAILABLE

        # Specialized agent manager for routing
        self._specialized_manager = SpecializedAgentManager()
        self._current_routing: Optional[RoutingResult] = None

        # Model selection
        self._current_model: str = "claude-sonnet-4-5-20250514"

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
            self._agent = MatlabAgent(model=self._current_model)
            self._start_persistent_loop()
        else:
            self._process_manager = ClaudeProcessManager()

        self._logger.info("MatlabBridge", "bridge_initialized", {
            "sdk_mode": self._use_sdk,
            "sdk_available": AGENT_SDK_AVAILABLE,
            "model": self._current_model
        })

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

    def configure_logging(self, config: Dict[str, Any]) -> None:
        """Configure logging from MATLAB settings.

        Args:
            config: Dict with logging settings from MATLAB:
                - session_id: Session ID for correlation
                - enabled: Enable/disable logging
                - level: Log level string
                - log_directory: Directory for log files
                - log_sensitive_data: Whether to log sensitive data
        """
        configure_logger(
            enabled=config.get("enabled", True),
            level=config.get("level", "INFO"),
            log_directory=config.get("log_directory") or None,
            log_sensitive_data=config.get("log_sensitive_data", True),
            session_id=config.get("session_id"),
        )
        self._logger.info("MatlabBridge", "logging_configured", {
            "session_id": config.get("session_id", ""),
            "level": config.get("level", "INFO")
        })

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

        self._logger.info("MatlabBridge", "async_message_started", {
            "prompt_length": len(prompt),
            "context_length": len(context),
            "sdk_mode": self._use_sdk
        })

        with self._async_lock:
            self._async_response = None
            self._async_chunks = []
            self._async_content = []
            self._async_complete = False

        # Clear any stale images from previous requests
        clear_images()

        # Route to specialized agent (SDK mode only)
        routing = None
        if self._use_sdk:
            routing = self._specialized_manager.route_message(prompt, {"context": context})
            self._current_routing = routing

            self._logger.info("MatlabBridge", "agent_routing", {
                "agent_name": routing.config.name,
                "is_explicit": routing.is_explicit,
                "confidence": routing.confidence,
                "reason": routing.reason
            })

            # Add user message to context
            self._specialized_manager.add_message_to_context(
                "user", prompt, routing.config.name
            )

        if self._use_sdk:
            # Run SDK async in background thread
            self._async_thread = threading.Thread(
                target=self._run_sdk_async,
                args=(prompt, context, routing),
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

    def _run_sdk_async(
        self,
        prompt: str,
        context: str,
        routing: Optional[RoutingResult] = None
    ) -> None:
        """Run SDK query in background thread.

        Keeps the agent running between messages for conversation memory.
        Uses the persistent event loop to maintain SDK client state.

        Args:
            prompt: User's message
            context: Additional context
            routing: Optional routing result for specialized agent selection
        """
        # Use cleaned message if routing stripped a command
        message = routing.cleaned_message if routing else prompt
        full_prompt = f"{context}\n\n{message}" if context else message

        async def run():
            # Determine which agent to use based on routing
            agent = self._agent
            agent_name = "GeneralAgent"

            if routing and routing.config:
                agent_name = routing.config.name

                # Check if we need to switch agents
                current_config = getattr(self._agent, '_config_name', None)
                if current_config != agent_name:
                    # Stop current agent if running
                    if self._agent_running and self._agent:
                        await self._agent.stop()
                        self._agent_running = False

                    # Create new agent from config
                    self._agent = MatlabAgent.from_config(routing.config)
                    self._agent._config_name = agent_name  # Track config for switching
                    agent = self._agent

            if not agent:
                # Set error response for missing agent case
                with self._async_lock:
                    self._async_response = {
                        'text': '',
                        'images': [],
                        'success': False,
                        'error': 'Agent not initialized',
                        'session_id': '',
                        'agent_name': agent_name,
                        'routing_reason': routing.reason if routing else ''
                    }
                    self._async_complete = True
                return

            try:
                # Start agent lazily on first message (inside try for error handling)
                if not self._agent_running:
                    await agent.start()
                    self._agent_running = True
                text_parts = []
                images = []

                async for content in agent.query(full_prompt):
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

                response_text = ''.join(text_parts)

                with self._async_lock:
                    self._async_response = {
                        'text': response_text,
                        'images': images,
                        'success': True,
                        'error': '',
                        'session_id': agent.session_id or '',
                        'agent_name': agent_name,
                        'routing_reason': routing.reason if routing else ''
                    }
                    self._async_complete = True

                self._logger.info("MatlabBridge", "async_complete", {
                    "agent_name": agent_name,
                    "response_length": len(response_text),
                    "image_count": len(images),
                    "success": True
                })

                # Add assistant response to context
                self._specialized_manager.add_message_to_context(
                    "assistant", response_text[:500], agent_name
                )

                # Increment turn count for compaction tracking
                agent.increment_turn()

                # Check if we need to compact the conversation
                if agent.turn_count >= agent.COMPACTION_THRESHOLD:
                    await agent.compact_conversation()

            except Exception as e:
                self._logger.error("MatlabBridge", "async_error", {
                    "agent_name": agent_name,
                    "error": str(e),
                    "error_type": type(e).__name__
                })

                with self._async_lock:
                    self._async_response = {
                        'text': '',
                        'images': [],
                        'success': False,
                        'error': str(e),
                        'session_id': '',
                        'agent_name': agent_name,
                        'routing_reason': routing.reason if routing else ''
                    }
                    self._async_complete = True
                # Don't stop agent on error - let it recover

            finally:
                # Safety net: ensure _async_complete is always set
                # This catches any edge cases we might have missed
                with self._async_lock:
                    if not self._async_complete:
                        self._async_response = {
                            'text': '',
                            'images': [],
                            'success': False,
                            'error': 'Unexpected error during agent execution',
                            'session_id': '',
                            'agent_name': agent_name,
                            'routing_reason': routing.reason if routing else ''
                        }
                        self._async_complete = True

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
        # Clear specialized agent manager context
        self._specialized_manager.clear_context()
        self._current_routing = None

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

        # Create fresh agent instance with current model
        self._agent = MatlabAgent(model=self._current_model)

    def update_model(self, model_name: str) -> None:
        """Update the model for subsequent requests.

        Args:
            model_name: Claude model ID (e.g., 'claude-sonnet-4-5-20250514')

        Note:
            The model change takes effect on the next conversation reset
            or when a new agent is created. The current conversation
            continues with the existing model.
        """
        self._current_model = model_name

        # If using SDK mode, we need to recreate the agent to use new model
        # This happens automatically on next conversation reset
        # For immediate effect on new messages, we could reset here,
        # but that would lose conversation context, so we defer

    def get_model(self) -> str:
        """Get the currently configured model.

        Returns:
            Current model ID
        """
        return self._current_model

    def get_conversation_turns(self) -> int:
        """Get the current conversation turn count.

        Returns:
            Number of turns in the current conversation.
        """
        if self._use_sdk and self._agent:
            return self._agent.turn_count
        return 0

    # =========================================================================
    # Specialized Agent Routing API
    # =========================================================================

    def get_available_commands(self) -> List[str]:
        """Get list of available slash commands.

        Returns:
            List of command prefixes (e.g., ["/git", "/review", ...])
        """
        return self._specialized_manager.get_available_commands()

    def get_specialized_agent_info(self) -> List[Dict[str, str]]:
        """Get information about all available specialized agents.

        Returns:
            List of dicts with agent name, command, and description
        """
        return self._specialized_manager.get_agent_info()

    def get_current_agent_name(self) -> str:
        """Get the name of the currently active specialized agent.

        Returns:
            Agent name (e.g., "GitAgent") or empty string
        """
        return self._specialized_manager.get_current_agent()

    def get_last_routing_info(self) -> Dict[str, Any]:
        """Get information about the last routing decision.

        Returns:
            Dict with routing details:
            - agent_name: Name of selected agent
            - command: Command prefix (if explicit)
            - is_explicit: True if explicit command was used
            - confidence: Auto-detection confidence score
            - reason: Human-readable routing explanation
        """
        if not self._current_routing:
            return {
                'agent_name': '',
                'command': '',
                'is_explicit': False,
                'confidence': 0.0,
                'reason': ''
            }

        return {
            'agent_name': self._current_routing.config.name,
            'command': self._current_routing.config.command_prefix,
            'is_explicit': self._current_routing.is_explicit,
            'confidence': self._current_routing.confidence,
            'reason': self._current_routing.reason
        }

    def force_agent(self, agent_name: str) -> bool:
        """Force selection of a specific agent by name.

        Args:
            agent_name: Name of agent to select (e.g., "GitAgent")

        Returns:
            True if agent was found and selected
        """
        config = self._specialized_manager.force_agent(agent_name)
        return config is not None
