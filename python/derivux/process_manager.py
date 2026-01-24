"""
Claude Process Manager - Handles Claude CLI subprocess communication.
"""

import subprocess
import json
import os
import threading
import queue
from pathlib import Path
from typing import Optional, Callable, Dict, Any, List


class ClaudeProcessManager:
    """Manages Claude Code CLI subprocess communication.

    This class spawns Claude Code as a subprocess and handles
    bidirectional communication with streaming JSON output.

    Example:
        pm = ClaudeProcessManager()
        if pm.is_claude_available():
            response = pm.send_message("Hello Claude")
    """

    DEFAULT_TIMEOUT = 300  # 5 minutes in seconds

    def __init__(self):
        self.process: Optional[subprocess.Popen] = None
        self.session_id: str = ""
        self.is_running: bool = False
        self.last_error: str = ""
        self.claude_path, self.node_bin_dir = self._find_claude_cli()
        self._output_queue: queue.Queue = queue.Queue()
        self._reader_thread: Optional[threading.Thread] = None

    def is_claude_available(self) -> bool:
        """Check if Claude CLI is installed and accessible."""
        if not self.claude_path:
            return False

        try:
            env = self._get_env()
            result = subprocess.run(
                [self.claude_path, "--version"],
                capture_output=True,
                text=True,
                timeout=10,
                env=env
            )
            return result.returncode == 0
        except Exception:
            return False

    def get_claude_path(self) -> str:
        """Get the resolved path to Claude CLI."""
        return self.claude_path or ""

    def send_message(
        self,
        prompt: str,
        allowed_tools: Optional[List[str]] = None,
        timeout: float = DEFAULT_TIMEOUT,
        context: str = "",
        resume_session: bool = True
    ) -> Dict[str, Any]:
        """Send a message to Claude and get response.

        Args:
            prompt: The message to send
            allowed_tools: List of allowed tool names
            timeout: Timeout in seconds
            context: Additional context to prepend
            resume_session: Whether to resume previous session

        Returns:
            Dict with 'text', 'success', 'error', 'session_id', 'tool_uses'
        """
        if allowed_tools is None:
            allowed_tools = ['Edit', 'Write', 'Read', 'Bash', 'Glob', 'Grep']

        # Build full prompt with context
        full_prompt = f"{context}\n\n{prompt}" if context else prompt

        # Build command arguments
        args = self._build_command_args(full_prompt, allowed_tools, resume_session)

        # Execute and collect response
        return self._execute_command(args, timeout)

    def send_message_async(
        self,
        prompt: str,
        chunk_callback: Callable[[str], None],
        complete_callback: Callable[[Dict[str, Any]], None],
        allowed_tools: Optional[List[str]] = None,
        context: str = "",
        resume_session: bool = True
    ) -> None:
        """Send message asynchronously with callbacks.

        Args:
            prompt: The message to send
            chunk_callback: Called for each streamed text chunk
            complete_callback: Called when response is complete
            allowed_tools: List of allowed tool names
            context: Additional context
            resume_session: Whether to resume session
        """
        if allowed_tools is None:
            allowed_tools = ['Edit', 'Write', 'Read', 'Bash', 'Glob', 'Grep']

        full_prompt = f"{context}\n\n{prompt}" if context else prompt
        args = self._build_command_args(full_prompt, allowed_tools, resume_session)

        # Start in background thread
        thread = threading.Thread(
            target=self._async_execute,
            args=(args, chunk_callback, complete_callback),
            daemon=True
        )
        thread.start()

    def stop_process(self) -> None:
        """Gracefully terminate the subprocess."""
        if self.process and self.is_running:
            try:
                self.process.terminate()
                self.process.wait(timeout=5)
            except Exception:
                try:
                    self.process.kill()
                except Exception:
                    pass
            self.is_running = False

    def _build_command_args(
        self,
        prompt: str,
        allowed_tools: List[str],
        resume_session: bool
    ) -> List[str]:
        """Build CLI argument list."""
        args = [self.claude_path, '-p', '--output-format', 'stream-json']

        if allowed_tools:
            args.extend(['--allowedTools', ','.join(allowed_tools)])

        if resume_session and self.session_id:
            args.extend(['--resume', self.session_id])

        args.append(prompt)
        return args

    def _get_env(self) -> Dict[str, str]:
        """Get environment with node in PATH."""
        env = os.environ.copy()
        if self.node_bin_dir:
            env['PATH'] = f"{self.node_bin_dir}:{env.get('PATH', '')}"
        return env

    def _execute_command(self, args: List[str], timeout: float) -> Dict[str, Any]:
        """Execute command and collect full response."""
        response = {
            'text': '',
            'tool_uses': [],
            'session_id': '',
            'success': True,
            'error': ''
        }

        try:
            env = self._get_env()
            self.process = subprocess.Popen(
                args,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                cwd=os.getcwd()
            )
            self.is_running = True

            # Read output with timeout
            try:
                stdout, stderr = self.process.communicate(timeout=timeout)

                # Parse each line of NDJSON
                for line in stdout.strip().split('\n'):
                    if line:
                        parsed = self._parse_stream_line(line)
                        response = self._merge_response(response, parsed)

                if self.process.returncode != 0 and not response['error']:
                    response['success'] = False
                    response['error'] = stderr or f"Process exited with code {self.process.returncode}"

            except subprocess.TimeoutExpired:
                self.process.kill()
                response['success'] = False
                response['error'] = "Timeout waiting for Claude response"

        except Exception as e:
            response['success'] = False
            response['error'] = str(e)
        finally:
            self.is_running = False

        # Update session ID
        if response['session_id']:
            self.session_id = response['session_id']

        return response

    def _async_execute(
        self,
        args: List[str],
        chunk_callback: Callable[[str], None],
        complete_callback: Callable[[Dict[str, Any]], None]
    ) -> None:
        """Execute command asynchronously with streaming."""
        response = {
            'text': '',
            'tool_uses': [],
            'session_id': '',
            'success': True,
            'error': ''
        }

        try:
            env = self._get_env()
            self.process = subprocess.Popen(
                args,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                cwd=os.getcwd(),
                bufsize=1  # Line buffered
            )
            self.is_running = True

            # Read stdout line by line
            for line in self.process.stdout:
                line = line.strip()
                if line:
                    parsed = self._parse_stream_line(line)
                    response = self._merge_response(response, parsed)

                    # Send text chunks to callback
                    if 'text_delta' in parsed:
                        chunk_callback(parsed['text_delta'])
                    elif 'text' in parsed and parsed['text']:
                        chunk_callback(parsed['text'])

            # Wait for process to complete
            self.process.wait()

            if self.process.returncode != 0:
                stderr = self.process.stderr.read()
                if not response['error']:
                    response['success'] = False
                    response['error'] = stderr or f"Process exited with code {self.process.returncode}"

        except Exception as e:
            response['success'] = False
            response['error'] = str(e)
        finally:
            self.is_running = False

        # Update session ID
        if response['session_id']:
            self.session_id = response['session_id']

        complete_callback(response)

    def _parse_stream_line(self, line: str) -> Dict[str, Any]:
        """Parse a single line of NDJSON stream output."""
        parsed = {}

        try:
            data = json.loads(line)

            if 'type' not in data:
                return parsed

            msg_type = data['type']

            if msg_type == 'assistant':
                # Assistant message content
                if 'message' in data and 'content' in data['message']:
                    content = data['message']['content']
                    if isinstance(content, list):
                        for block in content:
                            if block.get('type') == 'text':
                                parsed['text'] = block.get('text', '')

            elif msg_type == 'content_block_delta':
                # Streaming text delta
                if 'delta' in data and 'text' in data['delta']:
                    parsed['text_delta'] = data['delta']['text']

            elif msg_type == 'result':
                # Final result with session info
                if 'session_id' in data:
                    parsed['session_id'] = data['session_id']
                if 'result' in data:
                    parsed['final_text'] = data['result']

            elif msg_type == 'tool_use':
                parsed['tool_use'] = data

            elif msg_type == 'error':
                if 'error' in data:
                    parsed['error'] = data['error']

        except json.JSONDecodeError:
            pass

        return parsed

    def _merge_response(
        self,
        response: Dict[str, Any],
        parsed: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Merge parsed data into response dict."""
        if 'text' in parsed:
            response['text'] += parsed['text']

        if 'text_delta' in parsed:
            response['text'] += parsed['text_delta']

        if 'final_text' in parsed:
            response['text'] = parsed['final_text']

        if 'session_id' in parsed:
            response['session_id'] = parsed['session_id']

        if 'tool_use' in parsed:
            response['tool_uses'].append(parsed['tool_use'])

        if 'error' in parsed:
            response['success'] = False
            response['error'] = parsed['error']

        return response

    def _find_claude_cli(self) -> tuple:
        """Search for Claude CLI in common locations.

        Returns:
            Tuple of (claude_path, node_bin_dir)
        """
        home = Path.home()

        # Try NVM first (most common for Node.js global packages)
        nvm_dir = home / '.nvm' / 'versions' / 'node'
        if nvm_dir.exists():
            for version_dir in nvm_dir.iterdir():
                if version_dir.is_dir() and not version_dir.name.startswith('.'):
                    bin_dir = version_dir / 'bin'
                    claude_path = bin_dir / 'claude'
                    if claude_path.exists():
                        return str(claude_path), str(bin_dir)

        # Standard installation paths
        standard_paths = [
            '/usr/local/bin/claude',
            '/usr/bin/claude',
            '/opt/homebrew/bin/claude',
            str(home / '.local' / 'bin' / 'claude'),
            str(home / 'bin' / 'claude'),
            str(home / '.npm-global' / 'bin' / 'claude'),
            str(home / '.yarn' / 'bin' / 'claude'),
        ]

        for path in standard_paths:
            if Path(path).exists():
                return path, str(Path(path).parent)

        # Try 'which claude'
        try:
            result = subprocess.run(
                ['which', 'claude'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                claude_path = result.stdout.strip()
                return claude_path, str(Path(claude_path).parent)
        except Exception:
            pass

        return '', ''
