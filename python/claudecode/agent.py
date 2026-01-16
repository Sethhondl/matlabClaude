"""
MATLAB Agent - Claude agent with MATLAB tools using the Claude Agent SDK.

This module provides a MatlabAgent class that wraps the Claude SDK and
exposes MATLAB-specific tools for code execution, workspace management,
plotting, and Simulink interaction.
"""

import asyncio
import os
import shutil
from typing import Optional, AsyncIterator, Dict, Any, List

from claude_agent_sdk import (
    ClaudeSDKClient,
    ClaudeAgentOptions,
    create_sdk_mcp_server,
)


def find_claude_cli() -> Optional[str]:
    """Find the Claude CLI executable.

    Returns a wrapper script that properly sets up the PATH for Node.js,
    which is needed because asyncio.subprocess_exec doesn't handle
    symlinks to scripts properly.
    """
    # First, use our wrapper script which handles PATH setup
    wrapper_path = os.path.join(os.path.dirname(__file__), 'claude_wrapper.sh')
    if os.path.isfile(wrapper_path) and os.access(wrapper_path, os.X_OK):
        return wrapper_path

    # Fallback: Check common locations and set PATH
    paths_to_check = [
        shutil.which('claude'),  # In PATH
        os.path.expanduser('~/.nvm/versions/node/v22.9.0/bin/claude'),
        os.path.expanduser('~/node_modules/.bin/claude'),
        '/usr/local/bin/claude',
        os.path.expanduser('~/.claude/local/claude'),
    ]

    # Also check NVM versions dynamically
    nvm_dir = os.path.expanduser('~/.nvm/versions/node')
    if os.path.isdir(nvm_dir):
        for version in sorted(os.listdir(nvm_dir), reverse=True):
            paths_to_check.append(os.path.join(nvm_dir, version, 'bin', 'claude'))

    for path in paths_to_check:
        if path and os.path.isfile(path) and os.access(path, os.X_OK):
            # Ensure the directory containing claude (and node) is in PATH
            cli_dir = os.path.dirname(path)
            current_path = os.environ.get('PATH', '')
            if cli_dir not in current_path:
                os.environ['PATH'] = cli_dir + os.pathsep + current_path
            return path

    return None

from .matlab_tools import MATLAB_TOOLS
from .simulink_tools import SIMULINK_TOOLS
from .file_tools import FILE_TOOLS
from .matlab_engine import get_engine, stop_engine


MATLAB_SYSTEM_PROMPT = """You are an expert MATLAB and Simulink assistant. You have access to tools that let you:

1. **Execute MATLAB Code** (matlab_execute): Run any MATLAB code and see the output
2. **Manage Workspace** (matlab_workspace): List, read, or write variables in the MATLAB workspace
3. **Create Plots** (matlab_plot): Generate MATLAB plots and visualizations
4. **Query Simulink Models** (simulink_query): Explore Simulink model structure, blocks, and connections
5. **Modify Simulink Models** (simulink_modify): Add blocks, connect signals, set parameters
6. **Read Files** (file_read): Read contents of files in MATLAB's current directory
7. **Write Files** (file_write): Create or modify files in MATLAB's current directory
8. **List Files** (file_list): List directory contents with glob pattern support
9. **Create Directories** (file_mkdir): Create directories in MATLAB's current directory

When helping users:
- Use the matlab_execute tool to run MATLAB commands
- Check the workspace with matlab_workspace to understand what variables exist
- Create visualizations with matlab_plot when asked for plots or figures
- For Simulink tasks, first query the model structure before making modifications
- Use file_read to examine existing code, file_write to create or update files
- All file operations are restricted to MATLAB's current working directory for security

Always explain what you're doing and show relevant results to the user."""


class MatlabAgent:
    """Claude agent with MATLAB and Simulink tools.

    Example:
        agent = MatlabAgent()
        await agent.start()

        async for text in agent.query("Create a sine wave plot"):
            print(text, end="")

        await agent.stop()
    """

    def __init__(
        self,
        system_prompt: Optional[str] = None,
        include_file_tools: bool = True,
        max_turns: Optional[int] = None
    ):
        """Initialize the MATLAB agent.

        Args:
            system_prompt: Custom system prompt (uses default if None)
            include_file_tools: Include Read, Write, Glob, Grep tools
            max_turns: Maximum conversation turns (None for unlimited)
        """
        self.system_prompt = system_prompt or MATLAB_SYSTEM_PROMPT
        self.include_file_tools = include_file_tools
        self.max_turns = max_turns
        self.client: Optional[ClaudeSDKClient] = None
        self._session_id: Optional[str] = None

        # Build tool list
        self._build_tools()

    def _build_tools(self) -> None:
        """Build the MCP server and allowed tools list."""
        # Create MCP server with MATLAB + Simulink + File tools
        all_tools = MATLAB_TOOLS + SIMULINK_TOOLS + FILE_TOOLS

        self.mcp_server = create_sdk_mcp_server(
            name="matlab",
            version="1.0.0",
            tools=all_tools
        )

        # Build allowed tools list
        self.allowed_tools: List[str] = [
            # MATLAB tools (MCP format: mcp__{server}__{tool})
            "mcp__matlab__matlab_execute",
            "mcp__matlab__matlab_workspace",
            "mcp__matlab__matlab_plot",
            # Simulink tools
            "mcp__matlab__simulink_query",
            "mcp__matlab__simulink_modify",
            # File tools
            "mcp__matlab__file_read",
            "mcp__matlab__file_write",
            "mcp__matlab__file_list",
            "mcp__matlab__file_mkdir",
        ]

        if self.include_file_tools:
            self.allowed_tools.extend([
                "Read", "Write", "Glob", "Grep"
            ])

    def _get_options(self) -> ClaudeAgentOptions:
        """Get ClaudeAgentOptions for the client."""
        # Find Claude CLI
        cli_path = find_claude_cli()
        if not cli_path:
            raise RuntimeError(
                "Claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
            )

        options = ClaudeAgentOptions(
            system_prompt=self.system_prompt,
            mcp_servers={"matlab": self.mcp_server},
            allowed_tools=self.allowed_tools,
            permission_mode='acceptEdits',
            cli_path=cli_path
        )

        if self.max_turns:
            options.max_turns = self.max_turns

        return options

    async def start(self) -> None:
        """Start the agent client and connect to MATLAB."""
        # Connect to MATLAB engine
        engine = get_engine()
        if not engine.is_connected:
            engine.connect()

        # Create and start SDK client
        options = self._get_options()
        self.client = ClaudeSDKClient(options=options)
        await self.client.__aenter__()

    async def stop(self) -> None:
        """Stop the agent client."""
        if self.client:
            await self.client.__aexit__(None, None, None)
            self.client = None

    async def _create_message_stream(self, prompt: str):
        """Create an async message generator for streaming input."""
        yield {
            "type": "user",
            "message": {
                "role": "user",
                "content": prompt
            }
        }

    async def query(self, prompt: str) -> AsyncIterator[Dict[str, Any]]:
        """Send a query and yield response content (text, images, tool use).

        Args:
            prompt: User's message/query

        Yields:
            Dict with 'type' and content. Types:
            - {"type": "text", "text": "..."}
            - {"type": "image", "source": {"type": "base64", "media_type": "...", "data": "..."}}
            - {"type": "tool_use", "name": "..."}
        """
        if not self.client:
            raise RuntimeError("Agent not started. Call start() first.")

        await self.client.query(prompt)

        async for message in self.client.receive_response():
            msg_type = type(message).__name__

            if msg_type == 'AssistantMessage':
                # Extract content blocks (text, images, tool use)
                if hasattr(message, 'content'):
                    for block in message.content:
                        if hasattr(block, 'text'):
                            yield {"type": "text", "text": block.text}
                        elif hasattr(block, 'type') and block.type == 'image':
                            # Image block from tool result
                            yield {
                                "type": "image",
                                "source": block.source if hasattr(block, 'source') else {}
                            }
                        elif hasattr(block, 'name'):  # Tool use block
                            yield {"type": "tool_use", "name": block.name}

            elif msg_type == 'ToolResult':
                # Tool results may contain images
                if hasattr(message, 'content'):
                    for block in message.content:
                        if isinstance(block, dict) and block.get('type') == 'image':
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
                # Capture session ID
                if hasattr(message, 'session_id'):
                    self._session_id = message.session_id

    async def query_full(self, prompt: str) -> Dict[str, Any]:
        """Send a query and return complete response.

        Args:
            prompt: User's message/query

        Returns:
            Dict with 'text', 'images', 'tool_uses', 'session_id'
        """
        if not self.client:
            raise RuntimeError("Agent not started. Call start() first.")

        result = {
            'text': '',
            'images': [],
            'tool_uses': [],
            'session_id': self._session_id
        }

        await self.client.query(prompt)

        async for message in self.client.receive_response():
            msg_type = type(message).__name__

            if msg_type == 'AssistantMessage':
                if hasattr(message, 'content'):
                    for block in message.content:
                        if hasattr(block, 'text'):
                            result['text'] += block.text
                        elif hasattr(block, 'type') and block.type == 'image':
                            result['images'].append({
                                'source': block.source if hasattr(block, 'source') else {}
                            })
                        elif hasattr(block, 'name'):  # Tool use block
                            result['tool_uses'].append({
                                'name': block.name,
                                'input': getattr(block, 'input', {})
                            })

            elif msg_type == 'ToolResult':
                # Tool results may contain images
                if hasattr(message, 'content'):
                    for block in message.content:
                        if isinstance(block, dict) and block.get('type') == 'image':
                            result['images'].append({
                                'source': block.get('source', {})
                            })
                        elif hasattr(block, 'type') and block.type == 'image':
                            result['images'].append({
                                'source': block.source if hasattr(block, 'source') else {}
                            })

            elif msg_type == 'ResultMessage':
                if hasattr(message, 'session_id'):
                    result['session_id'] = message.session_id
                    self._session_id = message.session_id

        return result

    @property
    def session_id(self) -> Optional[str]:
        """Get the current session ID."""
        return self._session_id


async def run_matlab_agent(prompt: str) -> str:
    """Convenience function to run a single query.

    Args:
        prompt: User's message/query

    Returns:
        Complete response text
    """
    agent = MatlabAgent()
    await agent.start()

    try:
        text = ""
        async for chunk in agent.query(prompt):
            text += chunk
        return text
    finally:
        await agent.stop()


# For synchronous usage (e.g., from MATLAB)
def run_query_sync(prompt: str) -> str:
    """Synchronous wrapper for run_matlab_agent.

    Args:
        prompt: User's message/query

    Returns:
        Complete response text
    """
    return asyncio.run(run_matlab_agent(prompt))
