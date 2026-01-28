"""
MATLAB Bridge - Simplified interface for MATLAB to call Python functionality.

This module provides a single class that wraps all functionality,
making it easy to call from MATLAB using py.derivux.MatlabBridge().

Uses the Claude Agent SDK for native tool support.
"""

from typing import Any, Dict, List, Optional
from dataclasses import dataclass, field
import threading
import asyncio
import atexit
import time


@dataclass
class SessionContext:
    """Stores context for a single chat session (tab).

    Each session maintains its own conversation history, enabling
    multiple independent chat sessions without spawning multiple processes.
    """
    tab_id: str
    messages: List[Dict[str, Any]] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)
    last_active_at: float = field(default_factory=time.time)

from .agent_manager import AgentManager
from .image_queue import poll_images, clear_images
from .specialized_agent_manager import SpecializedAgentManager, RoutingResult
from .logger import get_logger, configure_logger
from .matlab_tools import set_headless_mode as _set_headless_mode

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
        bridge = py.derivux.MatlabBridge();
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
        self._interrupt_requested: bool = False  # Flag for double-ESC interrupt
        self._current_task: Optional[asyncio.Task] = None  # Store running task for cancellation

        # Persistent event loop for SDK mode (keeps agent alive between messages)
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._loop_thread: Optional[threading.Thread] = None

        # Shutdown coordination
        self._shutdown_requested = False
        self._shutdown_lock = threading.Lock()
        self._atexit_registered = False

        # Multi-session support (one context per tab)
        self._session_contexts: Dict[str, SessionContext] = {}
        self._active_session_id: Optional[str] = None

        # Execution mode (default to 'prompt' for safety)
        self._execution_mode = 'prompt'

        # Initialize based on mode
        if self._use_sdk:
            self._agent = MatlabAgent(
                model=self._current_model,
                execution_mode=self._execution_mode
            )
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
        self._atexit_registered = True

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

    def _run_in_loop(self, coro, timeout: float = 30.0):
        """Run a coroutine in the persistent event loop and wait for result.

        Args:
            coro: The coroutine to run
            timeout: Maximum time to wait for result (default 30s)

        Returns:
            The coroutine result

        Raises:
            RuntimeError: If shutdown requested or event loop not running
            TimeoutError: If timeout exceeded
        """
        with self._shutdown_lock:
            if self._shutdown_requested:
                raise RuntimeError("Bridge is shutting down")

        if not self._loop or not self._loop.is_running():
            raise RuntimeError("Event loop not running")

        future = asyncio.run_coroutine_threadsafe(coro, self._loop)
        try:
            return future.result(timeout=timeout)
        except TimeoutError:
            future.cancel()
            raise

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
        # Guard: Don't start new async operations if shutting down
        with self._shutdown_lock:
            if self._shutdown_requested:
                # Set immediate completion with error
                with self._async_lock:
                    self._async_response = {
                        'text': '',
                        'images': [],
                        'success': False,
                        'error': 'Bridge is shutting down',
                        'session_id': '',
                        'agent_name': '',
                        'routing_reason': ''
                    }
                    self._async_complete = True
                return

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
            self._interrupt_requested = False  # Reset interrupt flag for new request

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

            # Check if execution mode changed (requires agent recreation)
            current_agent_mode = getattr(self._agent, 'execution_mode', 'prompt') if self._agent else 'prompt'
            mode_changed = current_agent_mode != self._execution_mode

            if routing and routing.config:
                agent_name = routing.config.name

                # Check if we need to switch agents (config change or mode change)
                current_config = getattr(self._agent, '_config_name', None)
                if current_config != agent_name or mode_changed:
                    # Stop current agent if running
                    if self._agent_running and self._agent:
                        await self._agent.stop()
                        self._agent_running = False

                    # Create new agent from config with current execution mode
                    self._agent = MatlabAgent.from_config(routing.config)
                    self._agent._config_name = agent_name  # Track config for switching
                    self._agent.execution_mode = self._execution_mode  # Apply current mode
                    agent = self._agent

            elif mode_changed:
                # No routing config change, but execution mode changed
                self._logger.info("MatlabBridge", "execution_mode_agent_switch", {
                    "old_mode": current_agent_mode,
                    "new_mode": self._execution_mode
                })

                # Stop current agent if running
                if self._agent_running and self._agent:
                    await self._agent.stop()
                    self._agent_running = False

                # Create new agent with updated execution mode
                self._agent = MatlabAgent(
                    model=self._current_model,
                    execution_mode=self._execution_mode
                )
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
                    # Check for interrupt request (double-ESC)
                    if self._interrupt_requested:
                        self._logger.info("MatlabBridge", "async_interrupted", {
                            "agent_name": agent_name,
                            "text_so_far": len(''.join(text_parts))
                        })
                        break

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

            except asyncio.CancelledError:
                # Task was cancelled by interrupt_process() - handle gracefully
                self._logger.info("MatlabBridge", "async_cancelled", {
                    "agent_name": agent_name
                })
                with self._async_lock:
                    self._async_response = {
                        'text': ''.join(text_parts) if text_parts else '',
                        'images': images if images else [],
                        'success': False,
                        'error': 'Cancelled by user',
                        'session_id': '',
                        'agent_name': agent_name,
                        'routing_reason': routing.reason if routing else '',
                        'interrupted': True
                    }
                    self._async_complete = True
                # Don't re-raise - let the wrapper's finally block clean up

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

        # Wrapper to capture the task reference for cancellation support
        async def run_with_cancel_support():
            # Store the task so interrupt_process() can cancel it
            self._current_task = asyncio.current_task()
            try:
                await run()
            finally:
                self._current_task = None

        # Submit to persistent event loop (non-blocking)
        if self._loop and self._loop.is_running():
            asyncio.run_coroutine_threadsafe(run_with_cancel_support(), self._loop)
        else:
            # Fallback if loop not available
            asyncio.run(run_with_cancel_support())

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

    def interrupt_process(self) -> bool:
        """Interrupt running async process (user pressed ESC-ESC).

        This method is called when the user presses ESC twice to interrupt
        the current Claude request. It sets flags to stop the async operation
        gracefully and marks the response as interrupted.

        Returns:
            True if an interrupt was triggered, False if nothing was running.
        """
        self._logger.info("MatlabBridge", "interrupt_requested", {
            "sdk_mode": self._use_sdk,
            "async_complete": self._async_complete
        })

        # Check if there's anything to interrupt
        with self._async_lock:
            if self._async_complete:
                self._logger.debug("MatlabBridge", "interrupt_nothing_to_stop", {})
                return False

            # Set interrupt flag for SDK mode
            self._interrupt_requested = True

            # Mark async as complete with interrupted status
            self._async_response = {
                'text': '',
                'images': [],
                'success': False,
                'error': 'Interrupted by user',
                'session_id': '',
                'agent_name': '',
                'routing_reason': '',
                'interrupted': True
            }
            self._async_complete = True

        # Cancel the running task if it exists (this forcefully interrupts waiting)
        if self._current_task and not self._current_task.done():
            self._logger.info("MatlabBridge", "cancelling_task", {})
            if self._loop and self._loop.is_running():
                # Schedule cancellation from the event loop thread
                self._loop.call_soon_threadsafe(self._current_task.cancel)
                # Brief wait to let cancellation propagate
                time.sleep(0.1)

        # Stop the agent if in SDK mode
        if self._use_sdk and self._agent_running and self._agent:
            try:
                if self._loop and self._loop.is_running():
                    # Stop agent via event loop
                    async def stop_agent():
                        try:
                            await self._agent.stop()
                        except Exception:
                            pass
                        finally:
                            self._agent_running = False

                    future = asyncio.run_coroutine_threadsafe(stop_agent(), self._loop)
                    try:
                        future.result(timeout=2.0)  # Quick timeout for interrupt
                    except Exception:
                        pass
            except Exception as e:
                self._logger.warn("MatlabBridge", "interrupt_agent_error", {
                    "error": str(e)
                })

        # Stop CLI process if in CLI mode
        if self._process_manager:
            self._process_manager.stop_process()

        self._logger.info("MatlabBridge", "interrupt_complete", {})

        # Reset interrupt flag for next request
        self._interrupt_requested = False

        return True

    def shutdown(self, timeout: float = 5.0) -> bool:
        """Gracefully shutdown the bridge with timeout protection.

        This method should be called when closing the MATLAB UI to ensure
        clean shutdown without freezing MATLAB.

        Args:
            timeout: Maximum time to wait for shutdown (default 5 seconds)

        Returns:
            True if shutdown completed cleanly, False if timeout occurred
        """
        self._logger.info("MatlabBridge", "shutdown_started", {
            "timeout": timeout,
            "sdk_mode": self._use_sdk
        })

        # Set shutdown flag to prevent new async operations
        with self._shutdown_lock:
            self._shutdown_requested = True

        # Mark any pending async as complete (so polling stops immediately)
        with self._async_lock:
            if not self._async_complete:
                self._async_response = {
                    'text': '',
                    'images': [],
                    'success': False,
                    'error': 'Shutdown requested',
                    'session_id': '',
                    'agent_name': '',
                    'routing_reason': ''
                }
                self._async_complete = True

        clean_shutdown = True

        # Stop agent and event loop (SDK mode)
        if self._use_sdk:
            clean_shutdown = self._shutdown_event_loop(timeout)

        # Stop CLI process manager (fallback mode)
        if self._process_manager:
            self._process_manager.stop_process()

        # Unregister atexit handler (we've already cleaned up)
        if self._atexit_registered:
            try:
                atexit.unregister(self._cleanup_loop)
                self._atexit_registered = False
            except Exception:
                pass

        self._logger.info("MatlabBridge", "shutdown_complete", {
            "clean": clean_shutdown
        })

        return clean_shutdown

    def _shutdown_event_loop(self, timeout: float) -> bool:
        """Shutdown the event loop gracefully with timeout.

        Args:
            timeout: Maximum time to wait for shutdown

        Returns:
            True if shutdown completed within timeout, False otherwise
        """
        if not self._loop or not self._loop.is_running():
            return True

        try:
            # Stop agent with timeout
            if self._agent_running and self._agent:
                async def stop_agent_with_timeout():
                    try:
                        await asyncio.wait_for(
                            self._agent.stop(),
                            timeout=timeout * 0.6  # Use 60% of timeout for agent
                        )
                    except asyncio.TimeoutError:
                        pass
                    except Exception:
                        pass

                future = asyncio.run_coroutine_threadsafe(
                    stop_agent_with_timeout(), self._loop
                )
                try:
                    future.result(timeout=timeout * 0.7)
                except Exception:
                    pass
                finally:
                    self._agent_running = False

            # Stop the event loop
            self._loop.call_soon_threadsafe(self._loop.stop)

            # Wait for loop thread to finish
            if self._loop_thread and self._loop_thread.is_alive():
                self._loop_thread.join(timeout=timeout * 0.3)
                if self._loop_thread.is_alive():
                    # Timeout - loop thread still running, but don't block
                    self._logger.warn("MatlabBridge", "event_loop_thread_timeout", {})
                    return False

            return True

        except Exception as e:
            self._logger.error("MatlabBridge", "shutdown_event_loop_error", {
                "error": str(e)
            })
            return False

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

        # Create fresh agent instance with current model and execution mode
        self._agent = MatlabAgent(
            model=self._current_model,
            execution_mode=self._execution_mode
        )

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

    def set_headless_mode(self, enabled: bool) -> None:
        """Set headless mode for figure/model window suppression.

        When enabled, MATLAB figures and Simulink model windows will not
        appear on screen during code execution. Images are still captured
        and sent to the chat UI.

        Args:
            enabled: If True, suppress pop-up windows. If False, allow windows.
        """
        _set_headless_mode(enabled)
        self._logger.info("MatlabBridge", "headless_mode_changed", {
            "enabled": enabled
        })

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

    # =========================================================================
    # Authentication API
    # =========================================================================

    def _find_claude_cli(self) -> Optional[str]:
        """Find Claude CLI executable across all common installation paths.

        Searches in this order:
        1. PATH via shutil.which() - standard system lookup
        2. Native installation path (~/.claude/local/bin/claude) - recommended since 2025
        3. nvm paths (~/.nvm/versions/node/*/bin/claude) - for npm installations
        4. Other common paths (homebrew, npm-global, etc.)

        Returns:
            Full path to claude executable if found, None otherwise
        """
        import shutil
        import glob
        import os

        # 1. Check PATH first (standard lookup)
        claude_path = shutil.which('claude')
        if claude_path:
            self._logger.debug("MatlabBridge", "cli_found_in_path", {"path": claude_path})
            return claude_path

        # 2. Check native installation path (recommended since 2025)
        native_path = os.path.expanduser('~/.claude/local/bin/claude')
        if os.path.exists(native_path):
            self._logger.debug("MatlabBridge", "cli_found_native", {"path": native_path})
            return native_path

        # 3. Check nvm paths (for npm installations via Node Version Manager)
        nvm_pattern = os.path.expanduser('~/.nvm/versions/node/*/bin/claude')
        nvm_matches = glob.glob(nvm_pattern)
        if nvm_matches:
            # Use the latest version (sorted alphabetically, last is highest)
            latest_nvm = sorted(nvm_matches)[-1]
            self._logger.debug("MatlabBridge", "cli_found_nvm", {"path": latest_nvm})
            return latest_nvm

        # 4. Check other common installation paths
        common_paths = [
            '/usr/local/bin/claude',
            '/opt/homebrew/bin/claude',
            os.path.expanduser('~/.npm-global/bin/claude'),
            os.path.expanduser('~/node_modules/.bin/claude'),
        ]

        for path in common_paths:
            if os.path.exists(path):
                self._logger.debug("MatlabBridge", "cli_found_common", {"path": path})
                return path

        self._logger.debug("MatlabBridge", "cli_not_found", {})
        return None

    def set_auth_method(self, method: str) -> None:
        """Set the current authentication method.

        Args:
            method: 'subscription' or 'api_key'
        """
        if method not in ('subscription', 'api_key'):
            raise ValueError(f"Invalid auth method: {method}")

        self._auth_method = method
        self._logger.info("MatlabBridge", "auth_method_set", {"method": method})

    def get_auth_method(self) -> str:
        """Get the current authentication method.

        Returns:
            'subscription' or 'api_key'
        """
        return getattr(self, '_auth_method', 'subscription')

    def set_api_key(self, api_key: str) -> None:
        """Set the API key in the environment for SDK use.

        This sets the ANTHROPIC_API_KEY environment variable so the
        Claude SDK will use it for API calls.

        Args:
            api_key: The Anthropic API key
        """
        import os
        if api_key:
            os.environ['ANTHROPIC_API_KEY'] = api_key
            self._logger.info("MatlabBridge", "api_key_set", {
                "key_length": len(api_key),
                "key_prefix": api_key[:13] if len(api_key) > 13 else "***"
            })
        else:
            self.clear_api_key()

    def clear_api_key(self) -> None:
        """Remove the API key from the environment."""
        import os
        if 'ANTHROPIC_API_KEY' in os.environ:
            del os.environ['ANTHROPIC_API_KEY']
            self._logger.info("MatlabBridge", "api_key_cleared", {})

    def validate_api_key(self, api_key: str) -> Dict[str, Any]:
        """Validate an API key format and optionally test it.

        Args:
            api_key: The API key to validate

        Returns:
            Dict with:
            - valid: True if key format is valid
            - message: Description of validation result
            - tested: True if live test was performed
        """
        result = {
            'valid': False,
            'message': '',
            'tested': False
        }

        # Basic format validation
        if not api_key:
            result['message'] = 'API key is empty'
            return result

        if not api_key.startswith('sk-ant-'):
            result['message'] = 'API key should start with "sk-ant-"'
            return result

        if len(api_key) < 100:
            result['message'] = 'API key appears too short'
            return result

        # Format is valid
        result['valid'] = True
        result['message'] = 'API key format is valid'

        # Optionally perform a live test (makes actual API call)
        # For now, we just validate format to avoid billing
        # Live testing can be added later if needed

        return result

    def check_cli_auth_status(self) -> Dict[str, Any]:
        """Check the authentication status of the Claude CLI.

        This checks if the user is logged in via Claude CLI by:
        1. Checking if claude command is available
        2. Running 'claude auth status' command
        3. Checking for ~/.claude/ config directory

        Returns:
            Dict with:
            - authenticated: True if CLI is authenticated
            - email: User email if available
            - method: 'cli' if authenticated via CLI
            - message: Status message
            - cli_installed: True if CLI is installed
        """
        import subprocess
        from pathlib import Path

        result = {
            'authenticated': False,
            'email': '',
            'method': '',
            'message': 'Not authenticated',
            'cli_installed': False
        }

        # Check if claude CLI is available using centralized search
        claude_path = self._find_claude_cli()

        if not claude_path:
            result['message'] = 'Click "Login with Claude" to install and authenticate.'
            result['cli_installed'] = False
            return result

        result['cli_installed'] = True

        # Check for ~/.claude/ directory as a quick indicator
        claude_dir = Path.home() / '.claude'
        if not claude_dir.exists():
            result['message'] = 'Not logged in. Click "Login with Claude" to authenticate.'
            return result

        # Try to run 'claude auth status' command
        try:
            proc = subprocess.run(
                [claude_path, 'auth', 'status'],
                capture_output=True,
                text=True,
                timeout=10
            )

            output = proc.stdout + proc.stderr

            # Parse the output to determine status
            if proc.returncode == 0:
                result['authenticated'] = True
                result['method'] = 'cli'

                # Try to extract email from output
                # Output format varies, look for common patterns
                for line in output.split('\n'):
                    line_lower = line.lower()
                    if 'email' in line_lower or '@' in line:
                        # Extract email-like pattern
                        import re
                        email_match = re.search(r'[\w\.-]+@[\w\.-]+', line)
                        if email_match:
                            result['email'] = email_match.group(0)
                            break
                    if 'logged in' in line_lower or 'authenticated' in line_lower:
                        result['message'] = 'Authenticated via Claude CLI'

                if not result['email']:
                    result['message'] = 'Authenticated via Claude CLI'
            else:
                # Command failed - not authenticated
                if 'not logged in' in output.lower() or 'not authenticated' in output.lower():
                    result['message'] = 'Not logged in. Click "Login with Claude" to authenticate.'
                else:
                    result['message'] = 'Not logged in. Click "Login with Claude" to authenticate.'

        except subprocess.TimeoutExpired:
            result['message'] = 'CLI check timed out. Try clicking "Check Status" again.'
        except Exception as e:
            result['message'] = f'Error checking status: {str(e)[:50]}'
            self._logger.error("MatlabBridge", "cli_auth_check_error", {
                "error": str(e)
            })

        return result

    def get_auth_info(self) -> Dict[str, Any]:
        """Get comprehensive authentication information.

        Returns:
            Dict with:
            - auth_method: Current method ('subscription' or 'api_key')
            - cli_authenticated: True if CLI is authenticated
            - cli_email: User email from CLI auth
            - has_api_key: True if API key is set in environment
            - api_key_masked: Masked version of API key
        """
        import os

        info = {
            'auth_method': self.get_auth_method(),
            'cli_authenticated': False,
            'cli_email': '',
            'has_api_key': False,
            'api_key_masked': ''
        }

        # Check CLI auth status
        cli_status = self.check_cli_auth_status()
        info['cli_authenticated'] = cli_status['authenticated']
        info['cli_email'] = cli_status['email']

        # Check for API key in environment
        api_key = os.environ.get('ANTHROPIC_API_KEY', '')
        if api_key:
            info['has_api_key'] = True
            # Mask the key for display
            if len(api_key) > 20:
                info['api_key_masked'] = api_key[:13] + '****' + api_key[-4:]
            else:
                info['api_key_masked'] = '****'

        return info

    def start_cli_login(self) -> Dict[str, Any]:
        """Start the Claude CLI login process, installing CLI if needed.

        This will:
        1. Check if Claude CLI is installed
        2. If not, attempt to install it via native installer (recommended since 2025)
        3. Run 'claude auth login' which opens a browser for OAuth

        Returns:
            Dict with:
            - started: True if login process was started
            - message: Status message
            - installing: True if CLI is being installed
        """
        import subprocess

        result = {
            'started': False,
            'message': '',
            'installing': False
        }

        # Check if claude CLI is available using centralized search
        claude_path = self._find_claude_cli()

        if not claude_path:
            # CLI not found - attempt to install it
            self._logger.info("MatlabBridge", "cli_not_found_attempting_install", {})

            install_result = self._install_claude_cli()
            if not install_result['success']:
                result['message'] = install_result['message']
                return result

            result['installing'] = True
            result['message'] = install_result['message']

            # After installation, search again for the CLI
            claude_path = self._find_claude_cli()

        if not claude_path:
            result['message'] = 'Claude CLI installation may have succeeded but command not found. Please restart MATLAB to update PATH.'
            return result

        def run_login():
            try:
                # Run claude auth login - this opens a browser
                subprocess.run(
                    [claude_path, 'auth', 'login'],
                    timeout=120  # 2 minute timeout for user to complete OAuth
                )
            except Exception as e:
                self._logger.error("MatlabBridge", "cli_login_error", {
                    "error": str(e)
                })

        try:
            # Start login in background thread (non-blocking)
            thread = threading.Thread(target=run_login, daemon=True)
            thread.start()

            result['started'] = True
            if result['installing']:
                result['message'] = 'Claude CLI installed! Please complete authentication in your browser.'
            else:
                result['message'] = 'Login started. Please complete authentication in your browser.'

            self._logger.info("MatlabBridge", "cli_login_started", {
                "cli_path": claude_path,
                "was_installed": result['installing']
            })

        except Exception as e:
            result['message'] = f'Error starting login: {str(e)}'

        return result

    def _install_claude_cli(self) -> Dict[str, Any]:
        """Install Claude CLI using the native installer (recommended since 2025).

        The native installer is now the recommended method:
        - Auto-updates automatically
        - No Node.js/npm dependency
        - Faster startup time

        Falls back to npm installation if native installer fails.

        Returns:
            Dict with:
            - success: True if installation succeeded
            - message: Status message
        """
        import subprocess
        import shutil

        result = {
            'success': False,
            'message': ''
        }

        # Check if curl is available (required for native installer)
        curl_path = shutil.which('curl')
        if not curl_path:
            result['message'] = (
                'curl not found. Please install Claude CLI manually:\n'
                'curl -fsSL https://claude.ai/install.sh | bash\n\n'
                'Or use the "Claude API" option with an API key instead.'
            )
            self._logger.warn("MatlabBridge", "curl_not_found", {})
            return result

        self._logger.info("MatlabBridge", "installing_claude_cli_native", {})

        try:
            # Run native installer: curl -fsSL https://claude.ai/install.sh | bash
            proc = subprocess.run(
                ['bash', '-c', 'curl -fsSL https://claude.ai/install.sh | bash'],
                capture_output=True,
                text=True,
                timeout=120  # 2 minute timeout for installation
            )

            if proc.returncode == 0:
                result['success'] = True
                result['message'] = 'Claude CLI installed successfully!'
                self._logger.info("MatlabBridge", "cli_installed_native", {
                    "output": proc.stdout[:500] if proc.stdout else ""
                })
            else:
                # Native installation failed - log error details
                error_msg = proc.stderr or proc.stdout or 'Unknown error'
                result['message'] = (
                    f'Native installation failed: {error_msg[:200]}\n\n'
                    'You can try installing manually:\n'
                    'curl -fsSL https://claude.ai/install.sh | bash'
                )
                self._logger.error("MatlabBridge", "cli_install_native_failed", {
                    "returncode": proc.returncode,
                    "stderr": proc.stderr[:500] if proc.stderr else "",
                    "stdout": proc.stdout[:500] if proc.stdout else ""
                })

        except subprocess.TimeoutExpired:
            result['message'] = (
                'Installation timed out. Please try manually:\n'
                'curl -fsSL https://claude.ai/install.sh | bash'
            )
            self._logger.error("MatlabBridge", "cli_install_timeout", {})
        except Exception as e:
            result['message'] = f'Installation error: {str(e)}'
            self._logger.error("MatlabBridge", "cli_install_error", {
                "error": str(e)
            })

        return result

    # =========================================================================
    # Execution Mode API
    # =========================================================================

    def set_execution_mode(self, mode: str) -> None:
        """Set the current code execution mode.

        Args:
            mode: One of:
                - 'plan': Interview/planning mode - no code execution
                - 'prompt': Normal mode - prompts before each code execution
                - 'auto': Auto mode - executes code automatically (security blocks active)
                - 'bypass': DANGEROUS - removes all restrictions including blocked functions

        Note:
            Plan mode affects the agent's system prompt to focus on planning and
            interview-style requirements gathering. The Python side stores this
            state but the actual code execution blocking is handled by MATLAB's
            CodeExecutor class.
        """
        valid_modes = ('plan', 'prompt', 'auto', 'bypass')
        if mode not in valid_modes:
            raise ValueError(f"Invalid execution mode: {mode}. Valid modes: {valid_modes}")

        self._execution_mode = mode
        self._logger.info("MatlabBridge", "execution_mode_set", {
            "mode": mode,
            "is_dangerous": mode == 'bypass'
        })

        # Log warning for dangerous mode
        if mode == 'bypass':
            self._logger.warn("MatlabBridge", "bypass_mode_warning", {
                "warning": "ALL SAFETY RESTRICTIONS DISABLED - Use with extreme caution"
            })

    def get_execution_mode(self) -> str:
        """Get the current code execution mode.

        Returns:
            Current mode ('plan', 'prompt', 'auto', or 'bypass')
        """
        return getattr(self, '_execution_mode', 'prompt')

    def is_plan_mode(self) -> bool:
        """Check if currently in plan mode.

        Returns:
            True if in plan mode (no code execution)
        """
        return self.get_execution_mode() == 'plan'

    def is_bypass_mode(self) -> bool:
        """Check if currently in bypass mode.

        Returns:
            True if in bypass mode (all restrictions disabled)
        """
        return self.get_execution_mode() == 'bypass'

    # =========================================================================
    # Multi-Session Context API
    # =========================================================================

    def create_session_context(self, tab_id: str) -> None:
        """Create a new session context for a tab.

        Args:
            tab_id: Unique identifier for the tab/session
        """
        if not tab_id:
            return

        if tab_id in self._session_contexts:
            self._logger.debug("MatlabBridge", "session_context_exists", {"tab_id": tab_id})
            return

        context = SessionContext(tab_id=tab_id)
        self._session_contexts[tab_id] = context

        self._logger.info("MatlabBridge", "session_context_created", {
            "tab_id": tab_id,
            "total_sessions": len(self._session_contexts)
        })

    def close_session_context(self, tab_id: str) -> None:
        """Close and remove a session context.

        Args:
            tab_id: The tab/session ID to close
        """
        if not tab_id or tab_id not in self._session_contexts:
            return

        # Clear active if closing active session
        if self._active_session_id == tab_id:
            self._active_session_id = None

        del self._session_contexts[tab_id]

        self._logger.info("MatlabBridge", "session_context_closed", {
            "tab_id": tab_id,
            "remaining_sessions": len(self._session_contexts)
        })

    def switch_session_context(self, tab_id: str) -> None:
        """Switch to a different session context.

        This saves the current conversation state to the old session
        and loads the conversation state from the new session.

        Args:
            tab_id: The tab/session ID to switch to
        """
        if not tab_id:
            return

        # Create context if it doesn't exist (for initial tab)
        if tab_id not in self._session_contexts:
            self.create_session_context(tab_id)

        old_session_id = self._active_session_id

        # Save current conversation to old session context
        if old_session_id and old_session_id in self._session_contexts:
            old_context = self._session_contexts[old_session_id]
            old_context.last_active_at = time.time()
            # Note: In SDK mode, conversation history is managed by the agent
            # We track session switching here for future message isolation

        # Switch to new session
        self._active_session_id = tab_id
        new_context = self._session_contexts[tab_id]
        new_context.last_active_at = time.time()

        self._logger.debug("MatlabBridge", "session_context_switched", {
            "from_tab_id": old_session_id or "",
            "to_tab_id": tab_id
        })

    def get_active_session_id(self) -> str:
        """Get the ID of the currently active session.

        Returns:
            Active session ID or empty string if none
        """
        return self._active_session_id or ""

    def get_session_context(self, tab_id: str) -> Optional[SessionContext]:
        """Get a session context by ID.

        Args:
            tab_id: The tab/session ID

        Returns:
            SessionContext or None if not found
        """
        return self._session_contexts.get(tab_id)

    def get_all_session_ids(self) -> List[str]:
        """Get all active session IDs.

        Returns:
            List of session IDs
        """
        return list(self._session_contexts.keys())
