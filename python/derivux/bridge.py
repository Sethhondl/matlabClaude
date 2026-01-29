"""
MATLAB Bridge - Simplified interface for MATLAB to call Python functionality.

This module provides a single class that wraps all functionality,
making it easy to call from MATLAB using py.derivux.MatlabBridge().

Restructured to use the new architecture:
- Agent registry for agent management
- Permission system for tool access control
- Session processor for Claude SDK interaction
"""

from typing import Any, Dict, List, Optional
from dataclasses import dataclass, field
import threading
import asyncio
import atexit
import time
import os
from pathlib import Path


@dataclass
class TabState:
    """Stores complete UI state for a single chat tab.

    This dataclass is the Python source of truth for tab state. JavaScript
    fetches this state on initialization and pushes updates back.

    Attributes:
        tab_id: Unique identifier for this tab
        label: Display name shown in the tab header
        messages: Full message history
        is_streaming: Whether a response is currently streaming
        current_stream_message: Accumulated text during streaming
        status: Tab status indicator
        unread_count: Number of unread messages
        scroll_position: Saved scroll position
        created_at: Timestamp when tab was created
        last_active_at: Timestamp of last user activity
    """
    tab_id: str
    label: str = "Chat 1"
    messages: List[Dict[str, Any]] = field(default_factory=list)
    is_streaming: bool = False
    current_stream_message: str = ""
    status: str = "ready"
    unread_count: int = 0
    scroll_position: int = 0
    created_at: float = field(default_factory=time.time)
    last_active_at: float = field(default_factory=time.time)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization."""
        return {
            "tabId": self.tab_id,
            "label": self.label,
            "messages": self.messages,
            "isStreaming": self.is_streaming,
            "currentStreamMessage": self.current_stream_message,
            "status": self.status,
            "unreadCount": self.unread_count,
            "scrollPosition": self.scroll_position,
            "createdAt": self.created_at,
            "lastActiveAt": self.last_active_at,
        }


# Import new architecture components
from .agent import Agent, RoutingResult, create_default_agents
from .permission import Permission, PermissionState, GlobalSettings
from .session import SessionProcessor
from .config import ConfigLoader, load_config
from .tool.builtin import register_builtin_tools

# Import existing utilities
from .agent_manager import AgentManager
from .image_queue import poll_images, clear_images
from .logger import get_logger, configure_logger
from .matlab_tools import set_headless_mode as _set_headless_mode

# Check SDK availability
try:
    from claude_agent_sdk import ClaudeAgentOptions
    AGENT_SDK_AVAILABLE = True
except ImportError:
    AGENT_SDK_AVAILABLE = False
    ClaudeAgentOptions = None

# Fallback process manager
from .process_manager import ClaudeProcessManager


class MatlabBridge:
    """Bridge class for MATLAB integration.

    Provides a unified interface for MATLAB to access Claude
    functionality via Python. Uses the new architecture with:
    - Agent registry for agent management
    - Permission system for tool access control
    - Session processor for Claude SDK interaction

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
        """
        self._logger = get_logger()
        self.agent_manager = AgentManager()  # Local interceptor agents
        self._use_sdk = use_agent_sdk and AGENT_SDK_AVAILABLE

        # Initialize new architecture
        self._initialize_new_architecture()

        # Model selection
        self._current_model: str = "claude-sonnet-4-5"

        # Session processor (replaces MatlabAgent)
        self._processor: Optional[SessionProcessor] = None
        self._processor_running = False

        # Current routing state
        self._current_routing: Optional[RoutingResult] = None

        # CLI fallback mode
        self._process_manager: Optional[ClaudeProcessManager] = None

        # Async state
        self._async_response: Optional[Dict[str, Any]] = None
        self._async_chunks: List[str] = []
        self._async_content: List[Dict[str, Any]] = []
        self._async_complete: bool = False
        self._async_lock = threading.Lock()
        self._async_thread: Optional[threading.Thread] = None
        self._interrupt_requested: bool = False
        self._current_task: Optional[asyncio.Task] = None

        # Persistent event loop
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._loop_thread: Optional[threading.Thread] = None

        # Shutdown coordination
        self._shutdown_requested = False
        self._shutdown_lock = threading.Lock()
        self._atexit_registered = False

        # Tab state storage
        self._tab_states: Dict[str, TabState] = {}
        self._active_tab_id: Optional[str] = None
        self._next_tab_number: int = 1

        # Initialize based on mode
        if self._use_sdk:
            self._processor = SessionProcessor(model=self._current_model)
            self._start_persistent_loop()
        else:
            self._process_manager = ClaudeProcessManager()

        self._logger.info("MatlabBridge", "bridge_initialized", {
            "sdk_mode": self._use_sdk,
            "sdk_available": AGENT_SDK_AVAILABLE,
            "model": self._current_model,
            "agents_loaded": len(Agent.list()),
        })

    def _initialize_new_architecture(self) -> None:
        """Initialize the new architecture components."""
        # Register built-in tools
        register_builtin_tools()

        # Load config
        try:
            config = load_config()
            self._config = config
        except Exception as e:
            self._logger.warn("MatlabBridge", "config_load_failed", {
                "error": str(e)
            })
            self._config = None

        # Try to load agents from .derivux/agents/
        project_root = Path.cwd()
        agents_dir = project_root / ".derivux" / "agents"

        if agents_dir.exists():
            count = Agent.load(str(agents_dir))
            self._logger.info("MatlabBridge", "agents_loaded_from_files", {
                "count": count,
                "path": str(agents_dir),
            })
        else:
            # Create default agents programmatically
            create_default_agents()
            self._logger.info("MatlabBridge", "default_agents_created", {
                "count": len(Agent.list()),
            })

    def _start_persistent_loop(self) -> None:
        """Start a persistent event loop in a background thread."""
        def run_loop():
            self._loop = asyncio.new_event_loop()
            asyncio.set_event_loop(self._loop)
            self._loop.run_forever()

        self._loop_thread = threading.Thread(target=run_loop, daemon=True)
        self._loop_thread.start()

        time.sleep(0.1)  # Give loop time to start

        atexit.register(self._cleanup_loop)
        self._atexit_registered = True

    def _cleanup_loop(self) -> None:
        """Clean up the persistent event loop."""
        if self._loop and self._loop.is_running():
            if self._processor_running and self._processor:
                future = asyncio.run_coroutine_threadsafe(
                    self._processor.stop(), self._loop
                )
                try:
                    future.result(timeout=5)
                except Exception:
                    pass
            self._loop.call_soon_threadsafe(self._loop.stop)

    def _run_in_loop(self, coro, timeout: float = 30.0):
        """Run a coroutine in the persistent event loop."""
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
        """Configure logging from MATLAB settings."""
        configure_logger(
            enabled=config.get("enabled", True),
            level=config.get("level", "INFO"),
            log_directory=config.get("log_directory") or None,
            log_sensitive_data=config.get("log_sensitive_data", True),
            session_id=config.get("session_id"),
        )

    @property
    def using_agent_sdk(self) -> bool:
        """Check if using Agent SDK mode."""
        return self._use_sdk

    def is_claude_available(self) -> bool:
        """Check if Claude is available."""
        if self._use_sdk:
            return AGENT_SDK_AVAILABLE
        else:
            return self._process_manager.is_claude_available()

    def get_claude_path(self) -> str:
        """Get path to Claude CLI."""
        if self._process_manager:
            return self._process_manager.get_claude_path()
        return ""

    def dispatch_to_agent(
        self,
        message: str,
        context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Try to dispatch message to a local interceptor agent."""
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
        """Send a message to Claude (synchronous)."""
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
        """Send message using Session Processor."""
        full_prompt = f"{context}\n\n{prompt}" if context else prompt

        try:
            response = self._run_in_loop(self._query_processor_async(full_prompt))
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

    async def _query_processor_async(self, prompt: str) -> Dict[str, Any]:
        """Query processor asynchronously."""
        if not self._processor:
            raise RuntimeError("Processor not initialized")

        # Start processor with current agent if needed
        if not self._processor_running:
            agent = Agent.default()
            if agent:
                await self._processor.start(agent)
                self._processor_running = True

        return await self._processor.query_full(prompt)

    def start_async_message(
        self,
        prompt: str,
        context: str = "",
        allowed_tools: Optional[List[str]] = None,
        resume_session: bool = True
    ) -> None:
        """Start an async message to Claude."""
        with self._shutdown_lock:
            if self._shutdown_requested:
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
            self._interrupt_requested = False

        clear_images()

        # Route message to appropriate agent
        routing = None
        if self._use_sdk:
            routing = Agent.route(prompt)
            self._current_routing = routing

            self._logger.info("MatlabBridge", "agent_routing", {
                "agent_name": routing.agent.name,
                "routing_type": routing.routing_type,
                "reason": routing.reason
            })

        if self._use_sdk:
            self._async_thread = threading.Thread(
                target=self._run_sdk_async,
                args=(prompt, context, routing),
                daemon=True
            )
            self._async_thread.start()
        else:
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
        """Run SDK query in background thread."""
        message = routing.cleaned_message if routing else prompt
        full_prompt = f"{context}\n\n{message}" if context else message
        agent_name = routing.agent.name if routing else "general"

        async def run():
            try:
                # Ensure processor is started with correct agent
                if routing and routing.agent:
                    # Use processor's actual state, not potentially-stale flag
                    processor_running = self._processor.is_running if self._processor else False
                    current_agent = self._processor.current_agent if self._processor else None

                    needs_restart = (
                        not processor_running or
                        not current_agent or
                        current_agent.name != routing.agent.name
                    )

                    if needs_restart:
                        # Stop if actually running (processor handles if already stopped)
                        if processor_running and self._processor:
                            await self._processor.stop()

                        await self._processor.start(routing.agent)
                        self._processor_running = True

                elif not (self._processor.is_running if self._processor else False):
                    agent = Agent.default()
                    if agent and self._processor:
                        await self._processor.start(agent)
                        self._processor_running = True

                text_parts = []
                images = []

                async for content in self._processor.query(full_prompt):
                    if self._interrupt_requested:
                        self._logger.info("MatlabBridge", "async_interrupted", {
                            "agent_name": agent_name,
                            "text_so_far": len(''.join(text_parts))
                        })
                        break

                    with self._async_lock:
                        self._async_content.append(content)

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
                        'session_id': self._processor.session_id or '',
                        'agent_name': agent_name,
                        'routing_reason': routing.reason if routing else ''
                    }
                    self._async_complete = True

                self._logger.info("MatlabBridge", "async_complete", {
                    "agent_name": agent_name,
                    "response_length": len(response_text),
                    "image_count": len(images),
                })

            except asyncio.CancelledError:
                self._logger.info("MatlabBridge", "async_cancelled", {
                    "agent_name": agent_name
                })
                with self._async_lock:
                    self._async_response = {
                        'text': '',
                        'images': [],
                        'success': False,
                        'error': 'Cancelled by user',
                        'session_id': '',
                        'agent_name': agent_name,
                        'routing_reason': routing.reason if routing else '',
                        'interrupted': True
                    }
                    self._async_complete = True

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

            finally:
                with self._async_lock:
                    if not self._async_complete:
                        self._async_response = {
                            'text': '',
                            'images': [],
                            'success': False,
                            'error': 'Unexpected error',
                            'session_id': '',
                            'agent_name': agent_name,
                            'routing_reason': routing.reason if routing else ''
                        }
                        self._async_complete = True

        async def run_with_cancel_support():
            self._current_task = asyncio.current_task()
            try:
                await run()
            finally:
                self._current_task = None

        if self._loop and self._loop.is_running():
            asyncio.run_coroutine_threadsafe(run_with_cancel_support(), self._loop)
        else:
            asyncio.run(run_with_cancel_support())

    def poll_async_chunks(self) -> List[str]:
        """Poll for new async text chunks."""
        with self._async_lock:
            chunks = self._async_chunks.copy()
            self._async_chunks = []
            return chunks

    def poll_async_content(self) -> List[Dict[str, Any]]:
        """Poll for new async content."""
        with self._async_lock:
            content = self._async_content.copy()
            self._async_content = []

        direct_images = poll_images()
        for img in direct_images:
            content.append(img)

        return content

    def is_async_complete(self) -> bool:
        """Check if async message is complete."""
        with self._async_lock:
            return self._async_complete

    def get_async_response(self) -> Optional[Dict[str, Any]]:
        """Get the complete async response."""
        with self._async_lock:
            return self._async_response

    def stop_process(self) -> None:
        """Stop any running process."""
        if self._process_manager:
            self._process_manager.stop_process()

    def interrupt_process(self) -> bool:
        """Interrupt running async process."""
        self._logger.info("MatlabBridge", "interrupt_requested", {
            "sdk_mode": self._use_sdk,
            "async_complete": self._async_complete
        })

        with self._async_lock:
            if self._async_complete:
                return False

            self._interrupt_requested = True
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

        if self._current_task and not self._current_task.done():
            if self._loop and self._loop.is_running():
                self._loop.call_soon_threadsafe(self._current_task.cancel)
                time.sleep(0.1)

        if self._use_sdk and self._processor_running and self._processor:
            try:
                if self._loop and self._loop.is_running():
                    async def stop_processor():
                        try:
                            await self._processor.stop()
                        except Exception:
                            pass
                        finally:
                            self._processor_running = False

                    future = asyncio.run_coroutine_threadsafe(stop_processor(), self._loop)
                    try:
                        future.result(timeout=2.0)
                    except Exception:
                        pass
            except Exception as e:
                self._logger.warn("MatlabBridge", "interrupt_processor_error", {
                    "error": str(e)
                })

        if self._process_manager:
            self._process_manager.stop_process()

        self._interrupt_requested = False
        return True

    def shutdown(self, timeout: float = 5.0) -> bool:
        """Gracefully shutdown the bridge."""
        self._logger.info("MatlabBridge", "shutdown_started", {
            "timeout": timeout,
            "sdk_mode": self._use_sdk
        })

        with self._shutdown_lock:
            self._shutdown_requested = True

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

        if self._use_sdk:
            clean_shutdown = self._shutdown_event_loop(timeout)

        if self._process_manager:
            self._process_manager.stop_process()

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
        """Shutdown the event loop gracefully."""
        if not self._loop or not self._loop.is_running():
            return True

        try:
            if self._processor_running and self._processor:
                async def stop_with_timeout():
                    try:
                        await asyncio.wait_for(
                            self._processor.stop(),
                            timeout=timeout * 0.6
                        )
                    except asyncio.TimeoutError:
                        pass
                    except Exception:
                        pass

                future = asyncio.run_coroutine_threadsafe(
                    stop_with_timeout(), self._loop
                )
                try:
                    future.result(timeout=timeout * 0.7)
                except Exception:
                    pass
                finally:
                    self._processor_running = False

            self._loop.call_soon_threadsafe(self._loop.stop)

            if self._loop_thread and self._loop_thread.is_alive():
                self._loop_thread.join(timeout=timeout * 0.3)
                if self._loop_thread.is_alive():
                    return False

            return True

        except Exception as e:
            self._logger.error("MatlabBridge", "shutdown_event_loop_error", {
                "error": str(e)
            })
            return False

    def register_agent(self, agent: Any) -> None:
        """Register a local interceptor agent."""
        self.agent_manager.register_agent(agent)

    def remove_agent(self, agent_name: str) -> bool:
        """Remove an agent by name."""
        return self.agent_manager.remove_agent(agent_name)

    def get_agent_names(self) -> List[str]:
        """Get list of registered agent names."""
        return self.agent_manager.get_agent_names()

    def get_session_id(self) -> str:
        """Get current session ID."""
        if self._use_sdk and self._processor:
            return self._processor.session_id or ''
        elif self._process_manager:
            return self._process_manager.session_id
        return ''

    def clear_conversation(self) -> None:
        """Clear conversation history and reset."""
        self._current_routing = None

        if self._use_sdk and self._processor:
            if self._loop and self._loop.is_running():
                future = asyncio.run_coroutine_threadsafe(
                    self._reset_processor_async(), self._loop
                )
                try:
                    future.result(timeout=10)
                except Exception:
                    pass
            else:
                asyncio.run(self._reset_processor_async())

    async def _reset_processor_async(self) -> None:
        """Reset the processor asynchronously."""
        if self._processor_running and self._processor:
            await self._processor.stop()
            self._processor_running = False

        self._processor = SessionProcessor(model=self._current_model)

    def update_model(self, model_name: str) -> None:
        """Update the model for subsequent requests."""
        self._current_model = model_name
        if self._processor:
            self._processor.set_model(model_name)

    def get_model(self) -> str:
        """Get the currently configured model."""
        return self._current_model

    def set_headless_mode(self, enabled: bool) -> None:
        """Set headless mode for figure/model window suppression."""
        _set_headless_mode(enabled)

    def get_conversation_turns(self) -> int:
        """Get the current conversation turn count."""
        if self._use_sdk and self._processor:
            return self._processor.turn_count
        return 0

    # =========================================================================
    # Agent Routing API (Updated for new architecture)
    # =========================================================================

    def get_available_commands(self) -> List[str]:
        """Get list of available slash commands."""
        return Agent.list_commands()

    def get_specialized_agent_info(self) -> List[Dict[str, str]]:
        """Get information about all available agents."""
        return Agent.get_agent_info()

    def get_current_agent_name(self) -> str:
        """Get the name of the currently active agent."""
        if self._processor and self._processor.current_agent:
            return self._processor.current_agent.name
        return ""

    def get_last_routing_info(self) -> Dict[str, Any]:
        """Get information about the last routing decision."""
        if not self._current_routing:
            return {
                'agent_name': '',
                'command': '',
                'is_explicit': False,
                'confidence': 0.0,
                'reason': ''
            }

        return {
            'agent_name': self._current_routing.agent.name,
            'command': self._current_routing.agent.command,
            'is_explicit': self._current_routing.routing_type == 'command',
            'confidence': 1.0 if self._current_routing.routing_type in ('command', 'mention') else 0.0,
            'reason': self._current_routing.reason
        }

    def force_agent(self, agent_name: str) -> bool:
        """Force selection of a specific agent by name."""
        agent = Agent.get(agent_name)
        return agent is not None

    def switch_primary_agent(self, agent_name: str) -> bool:
        """Switch to a different primary agent (build/plan)."""
        return Agent.switch(agent_name)

    def switch_agent(self, agent_name: str) -> bool:
        """Switch to a specific agent by name.

        This is the preferred method for MATLAB to use when the UI
        has already determined which agent to switch to. Unlike
        toggle_primary_agent(), this sets a specific agent rather
        than cycling.

        Args:
            agent_name: Name of the agent to switch to ('build' or 'plan')

        Returns:
            True if switch was successful
        """
        success = Agent.switch(agent_name)

        if success:
            self._logger.info("MatlabBridge", "agent_switched", {
                "agent_name": agent_name
            })
        else:
            self._logger.warn("MatlabBridge", "agent_switch_failed", {
                "agent_name": agent_name
            })

        return success

    # =========================================================================
    # Agent and Global Settings API (New Architecture)
    # =========================================================================

    def toggle_primary_agent(self) -> Dict[str, Any]:
        """Toggle between primary agents (build ↔ plan).

        Returns:
            Dict with 'agent' (name) and 'description' keys
        """
        result = Agent.toggle_primary()

        self._logger.info("MatlabBridge", "primary_agent_toggled", {
            "new_agent": result.get("agent", ""),
            "description": result.get("description", "")
        })

        return result

    def set_auto_execute(self, enabled: bool) -> None:
        """Set the auto-execute global setting.

        When enabled, tools that require ASK permission are
        automatically approved.

        Args:
            enabled: True to enable auto-execute
        """
        Permission.set_auto_execute(enabled)

        self._logger.info("MatlabBridge", "auto_execute_set", {
            "enabled": enabled
        })

    def set_bypass_mode(self, enabled: bool) -> None:
        """Set the bypass mode global setting.

        When enabled, CodeExecutor security blocks are disabled.
        This is dangerous and should only be used when explicitly needed.

        Args:
            enabled: True to enable bypass mode
        """
        Permission.set_bypass_mode(enabled)

        self._logger.info("MatlabBridge", "bypass_mode_set", {
            "enabled": enabled
        })

    def get_global_settings(self) -> Dict[str, Any]:
        """Get the current global settings.

        Returns:
            Dict with 'auto_execute', 'bypass_mode', and 'current_agent' keys
        """
        settings = Permission.get_global_settings()
        current_agent = Agent.default()

        return {
            "auto_execute": settings.auto_execute,
            "bypass_mode": settings.bypass_mode,
            "current_agent": current_agent.name if current_agent else "build"
        }

    # =========================================================================
    # Execution Mode API (Deprecated - kept for backward compatibility)
    # =========================================================================

    def set_execution_mode(self, mode: str) -> None:
        """DEPRECATED: Set the current code execution mode.

        This method is kept for backward compatibility. New code should use:
        - toggle_primary_agent() or switch_primary_agent() for agent switching
        - set_auto_execute(bool) for auto-execute toggle
        - set_bypass_mode(bool) for bypass toggle

        Args:
            mode: Execution mode ('plan', 'prompt', 'auto', 'bypass')
        """
        import warnings
        warnings.warn(
            "set_execution_mode is deprecated. Use agent switching and "
            "global settings (set_auto_execute, set_bypass_mode) instead.",
            DeprecationWarning,
            stacklevel=2
        )

        valid_modes = ('plan', 'prompt', 'auto', 'bypass')
        if mode not in valid_modes:
            raise ValueError(f"Invalid execution mode: {mode}")

        # Map old modes to new architecture
        if mode == 'plan':
            Agent.switch('plan')
            Permission.set_auto_execute(False)
            Permission.set_bypass_mode(False)
        elif mode == 'prompt':
            Agent.switch('build')
            Permission.set_auto_execute(False)
            Permission.set_bypass_mode(False)
        elif mode == 'auto':
            Agent.switch('build')
            Permission.set_auto_execute(True)
            Permission.set_bypass_mode(False)
        elif mode == 'bypass':
            Agent.switch('build')
            Permission.set_auto_execute(True)
            Permission.set_bypass_mode(True)

        self._logger.info("MatlabBridge", "execution_mode_set_deprecated", {
            "mode": mode,
            "primary_agent": Agent.default().name if Agent.default() else ""
        })

    def get_execution_mode(self) -> str:
        """DEPRECATED: Get the current code execution mode.

        This method maps the new architecture back to old mode names
        for backward compatibility.

        Returns:
            Mode string ('plan', 'prompt', 'auto', 'bypass')
        """
        current_agent = Agent.default()
        settings = Permission.get_global_settings()

        if current_agent and current_agent.name == 'plan':
            return 'plan'
        elif settings.bypass_mode:
            return 'bypass'
        elif settings.auto_execute:
            return 'auto'
        else:
            return 'prompt'

    def is_plan_mode(self) -> bool:
        """Check if currently using the plan agent."""
        current_agent = Agent.default()
        return current_agent is not None and current_agent.name == 'plan'

    def is_bypass_mode(self) -> bool:
        """Check if bypass mode is enabled."""
        return Permission.is_bypass_mode()

    # =========================================================================
    # Tab State API (Unchanged from original)
    # =========================================================================

    def get_all_tab_state(self) -> Dict[str, Any]:
        """Get complete state for all tabs."""
        tabs_list = [state.to_dict() for state in self._tab_states.values()]
        return {
            "tabs": tabs_list,
            "activeTabId": self._active_tab_id or "",
            "nextTabNumber": self._next_tab_number,
        }

    def get_tab_state(self, tab_id: str) -> Optional[Dict[str, Any]]:
        """Get state for a single tab."""
        state = self._tab_states.get(tab_id)
        return state.to_dict() if state else None

    def create_tab(self, tab_id: str = "", label: str = "") -> Dict[str, Any]:
        """Create a new tab."""
        if not tab_id:
            import uuid
            tab_id = f"tab_{int(time.time())}_{uuid.uuid4().hex[:5]}"

        if not label:
            label = f"Chat {self._next_tab_number}"
            self._next_tab_number += 1

        if tab_id in self._tab_states:
            return self._tab_states[tab_id].to_dict()

        tab_state = TabState(tab_id=tab_id, label=label)
        self._tab_states[tab_id] = tab_state

        if self._active_tab_id is None:
            self._active_tab_id = tab_id

        return tab_state.to_dict()

    def close_tab(self, tab_id: str) -> bool:
        """Close and remove a tab."""
        if not tab_id or tab_id not in self._tab_states:
            return False

        if self._active_tab_id == tab_id:
            remaining = [tid for tid in self._tab_states.keys() if tid != tab_id]
            self._active_tab_id = remaining[0] if remaining else None

        del self._tab_states[tab_id]
        return True

    def switch_tab(
        self,
        from_tab_id: str,
        to_tab_id: str,
        scroll_position: int = 0
    ) -> Optional[Dict[str, Any]]:
        """Switch from one tab to another."""
        if from_tab_id and from_tab_id in self._tab_states:
            old_state = self._tab_states[from_tab_id]
            old_state.scroll_position = scroll_position
            old_state.last_active_at = time.time()

        if to_tab_id not in self._tab_states:
            self.create_tab(to_tab_id)

        self._active_tab_id = to_tab_id
        new_state = self._tab_states[to_tab_id]
        new_state.last_active_at = time.time()
        new_state.unread_count = 0
        if new_state.status == 'unread':
            new_state.status = 'ready'

        return new_state.to_dict()

    def add_message(
        self,
        tab_id: str,
        role: str,
        content: str,
        images: Optional[List[Dict[str, Any]]] = None
    ) -> bool:
        """Add a message to a tab's history."""
        if not tab_id or tab_id not in self._tab_states:
            return False

        state = self._tab_states[tab_id]
        message = {
            "role": role,
            "content": content,
            "timestamp": time.time(),
        }
        if images:
            message["images"] = images

        state.messages.append(message)

        if tab_id != self._active_tab_id:
            state.unread_count += 1
            if state.status not in ('working', 'attention'):
                state.status = 'unread'

        return True

    def update_streaming_state(
        self,
        tab_id: str,
        is_streaming: bool,
        current_text: str = ""
    ) -> bool:
        """Update streaming state for a tab."""
        if not tab_id or tab_id not in self._tab_states:
            return False

        state = self._tab_states[tab_id]
        state.is_streaming = is_streaming
        state.current_stream_message = current_text

        if is_streaming:
            state.status = 'working'
        elif state.status == 'working':
            state.status = 'ready'

        return True

    def save_scroll_position(self, tab_id: str, scroll_position: int) -> bool:
        """Save scroll position for a tab."""
        if not tab_id or tab_id not in self._tab_states:
            return False

        self._tab_states[tab_id].scroll_position = scroll_position
        return True

    def clear_tab(self, tab_id: str) -> bool:
        """Clear messages for a tab."""
        if not tab_id or tab_id not in self._tab_states:
            return False

        state = self._tab_states[tab_id]
        state.messages = []
        state.is_streaming = False
        state.current_stream_message = ""
        state.status = 'ready'
        state.unread_count = 0
        state.scroll_position = 0

        return True

    def update_tab_status(self, tab_id: str, status: str) -> bool:
        """Update status indicator for a tab."""
        valid_statuses = ('ready', 'working', 'attention', 'unread')
        if status not in valid_statuses:
            return False

        if not tab_id or tab_id not in self._tab_states:
            return False

        self._tab_states[tab_id].status = status
        return True

    # =========================================================================
    # Authentication API (Unchanged from original)
    # =========================================================================

    def _find_claude_cli(self) -> Optional[str]:
        """Find Claude CLI executable."""
        import shutil
        import glob

        claude_path = shutil.which('claude')
        if claude_path:
            return claude_path

        native_path = os.path.expanduser('~/.claude/local/bin/claude')
        if os.path.exists(native_path):
            return native_path

        nvm_pattern = os.path.expanduser('~/.nvm/versions/node/*/bin/claude')
        nvm_matches = glob.glob(nvm_pattern)
        if nvm_matches:
            return sorted(nvm_matches)[-1]

        common_paths = [
            '/usr/local/bin/claude',
            '/opt/homebrew/bin/claude',
            os.path.expanduser('~/.npm-global/bin/claude'),
        ]

        for path in common_paths:
            if os.path.exists(path):
                return path

        return None

    def set_auth_method(self, method: str) -> None:
        """Set the current authentication method."""
        if method not in ('subscription', 'api_key'):
            raise ValueError(f"Invalid auth method: {method}")
        self._auth_method = method

    def get_auth_method(self) -> str:
        """Get the current authentication method."""
        return getattr(self, '_auth_method', 'subscription')

    def set_api_key(self, api_key: str) -> None:
        """Set the API key in the environment."""
        if api_key:
            os.environ['ANTHROPIC_API_KEY'] = api_key
        else:
            self.clear_api_key()

    def clear_api_key(self) -> None:
        """Remove the API key from the environment."""
        if 'ANTHROPIC_API_KEY' in os.environ:
            del os.environ['ANTHROPIC_API_KEY']

    def validate_api_key(self, api_key: str) -> Dict[str, Any]:
        """Validate an API key format."""
        result = {'valid': False, 'message': '', 'tested': False}

        if not api_key:
            result['message'] = 'API key is empty'
            return result

        if not api_key.startswith('sk-ant-'):
            result['message'] = 'API key should start with "sk-ant-"'
            return result

        if len(api_key) < 100:
            result['message'] = 'API key appears too short'
            return result

        result['valid'] = True
        result['message'] = 'API key format is valid'
        return result

    def check_cli_auth_status(self) -> Dict[str, Any]:
        """Check the authentication status of the Claude CLI."""
        import subprocess
        from pathlib import Path

        result = {
            'authenticated': False,
            'email': '',
            'method': '',
            'message': 'Not authenticated',
            'cli_installed': False
        }

        claude_path = self._find_claude_cli()

        if not claude_path:
            result['message'] = 'Click "Login with Claude" to install and authenticate.'
            return result

        result['cli_installed'] = True

        claude_dir = Path.home() / '.claude'
        if not claude_dir.exists():
            result['message'] = 'Not logged in. Click "Login with Claude" to authenticate.'
            return result

        try:
            proc = subprocess.run(
                [claude_path, 'auth', 'status'],
                capture_output=True,
                text=True,
                timeout=10
            )

            output = proc.stdout + proc.stderr

            if proc.returncode == 0:
                result['authenticated'] = True
                result['method'] = 'cli'
                result['message'] = 'Authenticated via Claude CLI'

                import re
                for line in output.split('\n'):
                    email_match = re.search(r'[\w\.-]+@[\w\.-]+', line)
                    if email_match:
                        result['email'] = email_match.group(0)
                        break
            else:
                result['message'] = 'Not logged in. Click "Login with Claude" to authenticate.'

        except subprocess.TimeoutExpired:
            result['message'] = 'CLI check timed out.'
        except Exception as e:
            result['message'] = f'Error: {str(e)[:50]}'

        return result

    def get_auth_info(self) -> Dict[str, Any]:
        """Get comprehensive authentication information."""
        info = {
            'auth_method': self.get_auth_method(),
            'cli_authenticated': False,
            'cli_email': '',
            'has_api_key': False,
            'api_key_masked': ''
        }

        cli_status = self.check_cli_auth_status()
        info['cli_authenticated'] = cli_status['authenticated']
        info['cli_email'] = cli_status['email']

        api_key = os.environ.get('ANTHROPIC_API_KEY', '')
        if api_key:
            info['has_api_key'] = True
            if len(api_key) > 20:
                info['api_key_masked'] = api_key[:13] + '****' + api_key[-4:]
            else:
                info['api_key_masked'] = '****'

        return info

    def start_cli_login(self) -> Dict[str, Any]:
        """Start the Claude CLI login process."""
        import subprocess

        result = {
            'started': False,
            'message': '',
            'installing': False
        }

        claude_path = self._find_claude_cli()

        if not claude_path:
            install_result = self._install_claude_cli()
            if not install_result['success']:
                result['message'] = install_result['message']
                return result

            result['installing'] = True
            result['message'] = install_result['message']
            claude_path = self._find_claude_cli()

        if not claude_path:
            result['message'] = 'CLI not found after installation. Restart MATLAB.'
            return result

        def run_login():
            try:
                subprocess.run([claude_path, 'auth', 'login'], timeout=120)
            except Exception:
                pass

        try:
            thread = threading.Thread(target=run_login, daemon=True)
            thread.start()

            result['started'] = True
            if result['installing']:
                result['message'] = 'Claude CLI installed! Complete authentication in browser.'
            else:
                result['message'] = 'Login started. Complete authentication in browser.'

        except Exception as e:
            result['message'] = f'Error starting login: {str(e)}'

        return result

    def _install_claude_cli(self) -> Dict[str, Any]:
        """Install Claude CLI using the native installer."""
        import subprocess
        import shutil

        result = {'success': False, 'message': ''}

        curl_path = shutil.which('curl')
        if not curl_path:
            result['message'] = 'curl not found. Install manually or use API key.'
            return result

        try:
            proc = subprocess.run(
                ['bash', '-c', 'curl -fsSL https://claude.ai/install.sh | bash'],
                capture_output=True,
                text=True,
                timeout=120
            )

            if proc.returncode == 0:
                result['success'] = True
                result['message'] = 'Claude CLI installed successfully!'
            else:
                result['message'] = f'Installation failed: {proc.stderr[:200]}'

        except subprocess.TimeoutExpired:
            result['message'] = 'Installation timed out.'
        except Exception as e:
            result['message'] = f'Installation error: {str(e)}'

        return result
