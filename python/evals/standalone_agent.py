"""
Standalone agent for running evaluations using Claude CLI.

Uses the Claude Code CLI directly, leveraging its built-in authentication,
instead of requiring a separate API key.
"""

import asyncio
import json
import os
import shutil
import subprocess
from typing import Any, Dict, List, Optional

from .mock_matlab import get_mock_engine, MockMatlabEngine


def find_claude_cli() -> Optional[str]:
    """Find the Claude CLI executable."""
    # Check common locations
    paths_to_check = [
        shutil.which('claude'),
        os.path.expanduser('~/.claude/local/claude'),
        '/usr/local/bin/claude',
    ]

    # Check NVM versions
    nvm_dir = os.path.expanduser('~/.nvm/versions/node')
    if os.path.isdir(nvm_dir):
        for version in sorted(os.listdir(nvm_dir), reverse=True):
            paths_to_check.append(os.path.join(nvm_dir, version, 'bin', 'claude'))

    for path in paths_to_check:
        if path and os.path.isfile(path) and os.access(path, os.X_OK):
            return path

    return None


# System prompt for MATLAB assistance
MATLAB_SYSTEM_PROMPT = """You are an expert MATLAB and Simulink assistant. When helping users with MATLAB tasks:

1. Write clear, syntactically correct MATLAB code
2. Use appropriate MATLAB functions (eye, zeros, ones, linspace, etc.)
3. Explain what your code does
4. For plotting, use standard MATLAB plotting functions (plot, bar, scatter, etc.)

When asked to execute code or use tools, describe what MATLAB code you would run and show the code clearly.
If asked to create variables, show the MATLAB assignment statements.
If asked to create plots, show the complete plotting code."""


class StandaloneAgent:
    """Standalone agent using Claude CLI for evaluations.

    This uses the Claude Code CLI directly, which has its own authentication,
    so no separate API key is required.
    """

    def __init__(
        self,
        max_turns: int = 10,
        mock_engine: Optional[MockMatlabEngine] = None
    ):
        """Initialize the standalone agent.

        Args:
            max_turns: Maximum conversation turns (not used in CLI mode).
            mock_engine: Mock MATLAB engine (for workspace context).
        """
        self.max_turns = max_turns
        self.engine = mock_engine or get_mock_engine()
        self._started = False
        self._cli_path = find_claude_cli()

    async def start(self) -> None:
        """Start the agent."""
        if not self._cli_path:
            raise RuntimeError(
                "Claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
            )

        if not self.engine.is_connected:
            self.engine.connect()
        self._started = True

    async def stop(self) -> None:
        """Stop the agent."""
        self._started = False

    def _build_context_prompt(self, prompt: str) -> str:
        """Build prompt with workspace context if available."""
        context_parts = []

        # Add workspace context if we have variables
        if self.engine.is_connected:
            variables = self.engine.list_variables()
            if variables:
                var_info = []
                for var in variables:
                    info = self.engine.get_variable_info(var)
                    var_info.append(f"  - {var}: {info.get('class', 'double')} {info.get('size', '')}")
                context_parts.append(
                    "Current MATLAB workspace variables:\n" + "\n".join(var_info)
                )

        if context_parts:
            context = "\n\n".join(context_parts)
            return f"{context}\n\nUser request: {prompt}"

        return prompt

    def _parse_tool_usage(self, response_text: str) -> List[str]:
        """Extract tool names from response text based on patterns."""
        tools_used = []

        # Look for patterns indicating tool usage
        text_lower = response_text.lower()

        # Check for MATLAB execution patterns
        if any(pattern in text_lower for pattern in [
            'matlab_execute', 'execute', 'running', 'run this code',
            '```matlab', 'i\'ll run', 'let me run', 'executing'
        ]):
            if '```matlab' in text_lower or 'matlab code' in text_lower:
                tools_used.append('matlab_execute')

        # Check for workspace patterns
        if any(pattern in text_lower for pattern in [
            'matlab_workspace', 'workspace', 'variables in'
        ]):
            if 'workspace' in text_lower and ('list' in text_lower or 'variables' in text_lower):
                tools_used.append('matlab_workspace')

        # Check for plotting patterns
        if any(pattern in text_lower for pattern in [
            'matlab_plot', 'plot(', 'figure', 'bar(', 'scatter('
        ]):
            tools_used.append('matlab_execute')  # Plotting uses matlab_execute

        return list(set(tools_used))  # Remove duplicates

    async def query_full(self, prompt: str) -> Dict[str, Any]:
        """Send a query and return complete response.

        Args:
            prompt: User's message/query.

        Returns:
            Dict with 'text', 'images', 'tool_uses', 'session_id'
        """
        if not self._started:
            raise RuntimeError("Agent not started. Call start() first.")

        result = {
            'text': '',
            'images': [],
            'tool_uses': [],
            'session_id': None
        }

        # Build the full prompt with context
        full_prompt = self._build_context_prompt(prompt)

        # Combine system prompt with user prompt
        combined_prompt = f"{MATLAB_SYSTEM_PROMPT}\n\n{full_prompt}"

        try:
            # Run claude CLI with print mode
            # Using --print (-p) for single-shot mode
            # Using --dangerously-skip-permissions to avoid interactive prompts
            process = await asyncio.create_subprocess_exec(
                self._cli_path,
                '--print', combined_prompt,
                '--output-format', 'text',
                '--dangerously-skip-permissions',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env={**os.environ, 'CLAUDE_CODE_ENTRYPOINT': 'evals'}
            )

            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=120  # 2 minute timeout
            )

            response_text = stdout.decode('utf-8', errors='replace').strip()

            if process.returncode != 0:
                error_text = stderr.decode('utf-8', errors='replace').strip()
                if error_text:
                    raise RuntimeError(f"CLI error: {error_text}")

            result['text'] = response_text

            # Infer tool usage from the response
            inferred_tools = self._parse_tool_usage(response_text)
            result['tool_uses'] = [{'name': t, 'input': {}} for t in inferred_tools]

        except asyncio.TimeoutError:
            raise RuntimeError("CLI request timed out after 120 seconds")
        except FileNotFoundError:
            raise RuntimeError(f"Claude CLI not found at: {self._cli_path}")
        except Exception as e:
            raise RuntimeError(f"CLI error: {e}")

        return result


def create_standalone_agent(max_turns: int = 10) -> StandaloneAgent:
    """Create a standalone agent for evaluations.

    Args:
        max_turns: Maximum conversation turns.

    Returns:
        StandaloneAgent instance.
    """
    engine = get_mock_engine()
    engine.connect()
    return StandaloneAgent(max_turns=max_turns, mock_engine=engine)
