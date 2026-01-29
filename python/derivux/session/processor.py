"""
Session Processor - Thin wrapper on Claude Agent SDK.

This replaces the complex tool building logic in MatlabAgent with a
simpler design where:
1. Tools are registered globally
2. Permissions control access (not per-agent tool lists)
3. The processor just orchestrates SDK calls and tool execution
"""

import asyncio
import os
import shutil
import time
from typing import Any, AsyncIterator, Dict, List, Optional

from ..config.markdown import AgentDefinition
from ..permission import Permission
from ..tool import Tool
from ..tool.builtin import register_builtin_tools, ToolNames
from ..logger import get_logger


# Try to import the Claude SDK
try:
    from claude_agent_sdk import (
        ClaudeSDKClient,
        ClaudeAgentOptions,
        create_sdk_mcp_server,
    )
    SDK_AVAILABLE = True
except ImportError:
    SDK_AVAILABLE = False
    ClaudeSDKClient = None
    ClaudeAgentOptions = None
    create_sdk_mcp_server = None


def find_claude_cli() -> Optional[str]:
    """Find the Claude CLI executable.

    Returns a wrapper script that properly sets up the PATH for Node.js.
    """
    # First, check wrapper script
    wrapper_path = os.path.join(os.path.dirname(__file__), '..', 'derivux_wrapper.sh')
    if os.path.isfile(wrapper_path) and os.access(wrapper_path, os.X_OK):
        return wrapper_path

    # Check PATH
    claude_path = shutil.which('claude')
    if claude_path:
        return claude_path

    # Check common installation locations
    paths_to_check = [
        os.path.expanduser('~/.claude/local/bin/claude'),
        os.path.expanduser('~/.nvm/versions/node/v22.9.0/bin/claude'),
        '/usr/local/bin/claude',
    ]

    # Check NVM versions dynamically
    nvm_dir = os.path.expanduser('~/.nvm/versions/node')
    if os.path.isdir(nvm_dir):
        for version in sorted(os.listdir(nvm_dir), reverse=True):
            paths_to_check.append(os.path.join(nvm_dir, version, 'bin', 'claude'))

    for path in paths_to_check:
        if path and os.path.isfile(path) and os.access(path, os.X_OK):
            cli_dir = os.path.dirname(path)
            current_path = os.environ.get('PATH', '')
            if cli_dir not in current_path:
                os.environ['PATH'] = cli_dir + os.pathsep + current_path
            return path

    return None


class SessionProcessor:
    """Thin wrapper on Claude Agent SDK for session management.

    Unlike the old MatlabAgent which rebuilt tools per execution mode,
    this processor:
    1. Uses global tool registry
    2. Lets permission system control access
    3. Maintains conversation state through SDK client

    Example:
        processor = SessionProcessor()
        await processor.start(agent_def)

        async for content in processor.query("Create a plot"):
            print(content)

        await processor.stop()
    """

    def __init__(self, model: Optional[str] = None):
        """Initialize the session processor.

        Args:
            model: Claude model ID (uses default if None)
        """
        self._logger = get_logger()
        self._model = model or "claude-sonnet-4-5"
        self._client: Optional[ClaudeSDKClient] = None
        self._current_agent: Optional[AgentDefinition] = None
        self._mcp_server = None
        self._session_id: Optional[str] = None
        self._turn_count = 0

        # Ensure tools are registered
        register_builtin_tools()

    async def start(self, agent: AgentDefinition) -> None:
        """Start a session with a specific agent.

        Args:
            agent: Agent definition to use

        Raises:
            RuntimeError: If SDK not available or CLI not found
        """
        if not SDK_AVAILABLE:
            raise RuntimeError("Claude Agent SDK not available")

        cli_path = find_claude_cli()
        if not cli_path:
            raise RuntimeError(
                "Claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
            )

        self._current_agent = agent
        Permission.set_current_agent(agent.name)

        # Build MCP server with MATLAB/Simulink tools
        self._mcp_server = self._create_mcp_server()

        # Get allowed tools based on permissions
        allowed_tools = self._get_allowed_tools()

        # Build options
        options = ClaudeAgentOptions(
            system_prompt=agent.system_prompt,
            mcp_servers={"matlab": self._mcp_server},
            allowed_tools=allowed_tools,
            permission_mode='acceptEdits',
            cli_path=cli_path,
        )

        if self._model:
            options.model = self._model

        if agent.thinking_budget:
            options.thinking_budget = agent.thinking_budget

        self._logger.info("SessionProcessor", "starting", {
            "agent": agent.name,
            "model": self._model,
            "tools_count": len(allowed_tools),
        })

        # Start client
        self._client = ClaudeSDKClient(options=options)
        await self._client.__aenter__()

    async def stop(self) -> None:
        """Stop the current session."""
        if self._client:
            self._logger.info("SessionProcessor", "stopping", {
                "agent": self._current_agent.name if self._current_agent else "",
                "turns": self._turn_count,
            })
            try:
                # Add timeout to prevent hanging on SDK cleanup
                await asyncio.wait_for(
                    self._client.__aexit__(None, None, None),
                    timeout=5.0
                )
            except asyncio.TimeoutError:
                self._logger.warn("SessionProcessor", "stop_timeout", {
                    "agent": self._current_agent.name if self._current_agent else "",
                })
            except Exception as e:
                self._logger.warn("SessionProcessor", "stop_error", {
                    "error": str(e),
                })
            finally:
                # Always clean up state, even if __aexit__ fails
                self._client = None
                self._current_agent = None
                self._turn_count = 0

    async def query(self, prompt: str) -> AsyncIterator[Dict[str, Any]]:
        """Send a query and stream response content.

        Args:
            prompt: User's message

        Yields:
            Content dicts:
            - {"type": "text", "text": "..."}
            - {"type": "image", "source": {...}}
            - {"type": "tool_use", "name": "..."}
        """
        if not self._client:
            raise RuntimeError("Session not started. Call start() first.")

        await self._client.query(prompt)

        async for message in self._client.receive_response():
            msg_type = type(message).__name__

            if msg_type == 'AssistantMessage':
                if hasattr(message, 'content'):
                    for block in message.content:
                        if hasattr(block, 'text'):
                            yield {"type": "text", "text": block.text}
                        elif hasattr(block, 'type') and block.type == 'image':
                            yield {
                                "type": "image",
                                "source": block.source if hasattr(block, 'source') else {}
                            }
                        elif hasattr(block, 'name'):
                            yield {"type": "tool_use", "name": block.name}

            elif msg_type in ('ToolResult', 'McpToolResult', 'McpToolResultMessage'):
                if hasattr(message, 'content'):
                    for block in message.content:
                        if isinstance(block, dict):
                            if block.get('type') == 'image':
                                yield {
                                    "type": "image",
                                    "source": block.get('source', {})
                                }
                        elif hasattr(block, 'type') and block.type == 'image':
                            yield {
                                "type": "image",
                                "source": block.source if hasattr(block, 'source') else {}
                            }

            elif msg_type == 'ResultMessage':
                if hasattr(message, 'session_id'):
                    self._session_id = message.session_id

        self._turn_count += 1

    async def query_full(self, prompt: str) -> Dict[str, Any]:
        """Send a query and return complete response.

        Args:
            prompt: User's message

        Returns:
            Dict with 'text', 'images', 'tool_uses', 'session_id'
        """
        result = {
            'text': '',
            'images': [],
            'tool_uses': [],
            'session_id': self._session_id,
        }

        async for content in self.query(prompt):
            if content.get('type') == 'text':
                result['text'] += content.get('text', '')
            elif content.get('type') == 'image':
                result['images'].append(content.get('source', {}))
            elif content.get('type') == 'tool_use':
                result['tool_uses'].append(content.get('name', ''))

        result['session_id'] = self._session_id
        return result

    def _create_mcp_server(self):
        """Create MCP server with MATLAB/Simulink tools."""
        # Import existing tools
        from ..matlab_tools import MATLAB_TOOLS
        from ..simulink_tools import SIMULINK_TOOLS
        from ..file_tools import FILE_TOOLS

        all_tools = MATLAB_TOOLS + SIMULINK_TOOLS + FILE_TOOLS

        return create_sdk_mcp_server(
            name="matlab",
            version="1.0.0",
            tools=all_tools
        )

    def _get_allowed_tools(self) -> List[str]:
        """Get list of allowed tools based on current permissions.

        Returns:
            List of qualified tool names for SDK
        """
        all_tool_names = ToolNames.all_tools()
        allowed = []

        for name in all_tool_names:
            if Permission.is_allowed(name):
                tool = Tool.get(name)
                if tool:
                    allowed.append(tool.qualified_name)

        # Always include basic read tools if allowed
        basic_tools = ["Read", "Glob", "Grep"]
        for name in basic_tools:
            if Permission.is_allowed(name) and name not in allowed:
                allowed.append(name)

        return allowed

    @property
    def current_agent(self) -> Optional[AgentDefinition]:
        """Get the current agent definition."""
        return self._current_agent

    @property
    def session_id(self) -> Optional[str]:
        """Get the current session ID."""
        return self._session_id

    @property
    def turn_count(self) -> int:
        """Get the conversation turn count."""
        return self._turn_count

    @property
    def is_running(self) -> bool:
        """Check if a session is currently running."""
        return self._client is not None

    def set_model(self, model: str) -> None:
        """Set the model for future sessions.

        Args:
            model: Claude model ID
        """
        self._model = model
