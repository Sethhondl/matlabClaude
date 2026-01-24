"""
File Management MCP Tools - Tools for Claude to read/write files in MATLAB's working directory.

These tools provide file system access constrained to MATLAB's current working directory
for security. All path operations are validated to prevent directory traversal attacks.
"""

import os
import re
import fnmatch
from pathlib import Path
from typing import Any, Dict, List

from claude_agent_sdk import tool
from .matlab_engine import get_engine
from .logger import get_logger

_logger = get_logger()


# Dangerous file extensions that should not be written
BLOCKED_EXTENSIONS = {
    '.mlappinstall',  # MATLAB app installer
    '.mltbx',         # MATLAB toolbox
    '.prj',           # MATLAB project
    '.exe',           # Executable
    '.dll',           # Dynamic library
    '.so',            # Shared object
    '.dylib',         # macOS dynamic library
    '.bat',           # Batch file
    '.cmd',           # Command file
    '.sh',            # Shell script
    '.ps1',           # PowerShell
}

# Maximum file size for reading (1 MB)
MAX_READ_SIZE = 1024 * 1024

# Default maximum lines to read
DEFAULT_MAX_LINES = 500


def _get_matlab_pwd() -> str:
    """Get MATLAB's current working directory.

    Uses disp(pwd) to avoid the 'ans = ' prefix in MATLAB output.
    Falls back to parsing if needed.
    """
    engine = get_engine()
    if not engine.is_connected:
        engine.connect()

    # Use disp(pwd) to get clean output without 'ans = ' prefix
    pwd_result = engine.eval("disp(pwd)", capture_output=True)

    # Clean up the result - disp() outputs just the path with a newline
    pwd_path = pwd_result.strip()

    # Handle case where MATLAB might still include 'ans =' (shouldn't happen with disp)
    if 'ans' in pwd_path.lower():
        # Parse out the actual path - look for a quoted string
        match = re.search(r"'([^']+)'|\"([^\"]+)\"", pwd_path)
        if match:
            pwd_path = match.group(1) or match.group(2)
        else:
            # Try to get the last line that looks like a path
            lines = pwd_path.split('\n')
            for line in reversed(lines):
                line = line.strip()
                if line and line.startswith('/'):
                    pwd_path = line
                    break

    if not pwd_path or not pwd_path.startswith('/'):
        raise RuntimeError(
            f"Could not determine MATLAB's current directory. Got: {repr(pwd_result)}"
        )

    return pwd_path


def _validate_path(requested_path: str, base_dir: str) -> str:
    """Validate that a path is within the allowed base directory.

    Args:
        requested_path: The path requested by the user (relative or absolute)
        base_dir: The base directory that paths must be within

    Returns:
        The resolved absolute path if valid

    Raises:
        ValueError: If the path would escape the base directory
    """
    base_path = Path(base_dir).resolve()

    # Handle relative and absolute paths
    if os.path.isabs(requested_path):
        resolved = Path(requested_path).resolve()
    else:
        resolved = (base_path / requested_path).resolve()

    # Check that resolved path is within base directory
    try:
        resolved.relative_to(base_path)
    except ValueError:
        raise ValueError(
            f"Path '{requested_path}' is outside the allowed directory. "
            f"All file operations must be within MATLAB's current directory: {base_dir}"
        )

    return str(resolved)


def _check_extension(filepath: str, operation: str) -> None:
    """Check if file extension is allowed for the operation.

    Args:
        filepath: Path to check
        operation: 'read' or 'write'

    Raises:
        ValueError: If extension is blocked for write operations
    """
    if operation == 'write':
        ext = Path(filepath).suffix.lower()
        if ext in BLOCKED_EXTENSIONS:
            raise ValueError(
                f"Cannot write files with extension '{ext}' for security reasons. "
                f"Blocked extensions: {', '.join(sorted(BLOCKED_EXTENSIONS))}"
            )


@tool(
    "file_read",
    "Read the contents of a file in MATLAB's current working directory. "
    "Supports text files with optional line limiting.",
    {"path": str, "max_lines": int, "offset": int}
)
async def file_read(args: Dict[str, Any]) -> Dict[str, Any]:
    """Read file contents with security constraints."""
    path = str(args.get("path", ""))
    max_lines = args.get("max_lines", DEFAULT_MAX_LINES)
    offset = args.get("offset", 0)

    _logger.debug("file_tools", "file_read", {"path": path, "max_lines": max_lines, "offset": offset})

    if not path:
        return {
            "content": [{"type": "text", "text": "Error: No path provided"}],
            "isError": True
        }

    try:
        base_dir = _get_matlab_pwd()
        resolved_path = _validate_path(path, base_dir)
        _check_extension(resolved_path, 'read')

        # Check file exists
        if not os.path.isfile(resolved_path):
            return {
                "content": [{"type": "text", "text": f"Error: File not found: {path}"}],
                "isError": True
            }

        # Check file size
        file_size = os.path.getsize(resolved_path)
        if file_size > MAX_READ_SIZE:
            return {
                "content": [{
                    "type": "text",
                    "text": f"Error: File too large ({file_size / 1024 / 1024:.2f} MB). "
                            f"Maximum allowed size is {MAX_READ_SIZE / 1024 / 1024:.0f} MB."
                }],
                "isError": True
            }

        # Read file
        with open(resolved_path, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()

        total_lines = len(lines)

        # Apply offset and limit
        if offset > 0:
            lines = lines[offset:]
        if max_lines > 0:
            lines = lines[:max_lines]

        content = ''.join(lines)

        # Build result with metadata
        rel_path = os.path.relpath(resolved_path, base_dir)
        result_text = f"File: {rel_path}\n"
        result_text += f"Total lines: {total_lines}"
        if offset > 0 or (max_lines > 0 and total_lines > max_lines + offset):
            result_text += f" (showing lines {offset + 1}-{offset + len(lines)})"
        result_text += f"\n{'─' * 40}\n{content}"

        return {"content": [{"type": "text", "text": result_text}]}

    except ValueError as e:
        return {
            "content": [{"type": "text", "text": f"Error: {str(e)}"}],
            "isError": True
        }
    except Exception as e:
        return {
            "content": [{"type": "text", "text": f"Error reading file: {str(e)}"}],
            "isError": True
        }


@tool(
    "file_write",
    "Write content to a file in MATLAB's current working directory. "
    "Requires overwrite=true to replace existing files. Creates parent directories as needed.",
    {"path": str, "content": str, "overwrite": bool}
)
async def file_write(args: Dict[str, Any]) -> Dict[str, Any]:
    """Write file contents with security constraints."""
    path = str(args.get("path", ""))
    content = str(args.get("content", ""))
    overwrite = args.get("overwrite", False)

    _logger.info("file_tools", "file_write", {"path": path, "content_length": len(content), "overwrite": overwrite})

    if not path:
        return {
            "content": [{"type": "text", "text": "Error: No path provided"}],
            "isError": True
        }

    try:
        base_dir = _get_matlab_pwd()
        resolved_path = _validate_path(path, base_dir)
        _check_extension(resolved_path, 'write')

        # Check if file exists and overwrite flag
        if os.path.exists(resolved_path) and not overwrite:
            return {
                "content": [{
                    "type": "text",
                    "text": f"Error: File already exists: {path}\n"
                            "Set overwrite=true to replace the existing file."
                }],
                "isError": True
            }

        # Create parent directories if needed
        parent_dir = os.path.dirname(resolved_path)
        if parent_dir and not os.path.exists(parent_dir):
            os.makedirs(parent_dir, exist_ok=True)

        # Write file
        with open(resolved_path, 'w', encoding='utf-8') as f:
            f.write(content)

        rel_path = os.path.relpath(resolved_path, base_dir)
        lines = content.count('\n') + (1 if content and not content.endswith('\n') else 0)
        size = len(content.encode('utf-8'))

        return {
            "content": [{
                "type": "text",
                "text": f"Successfully wrote {rel_path}\n"
                        f"  Lines: {lines}\n"
                        f"  Size: {size} bytes"
            }]
        }

    except ValueError as e:
        return {
            "content": [{"type": "text", "text": f"Error: {str(e)}"}],
            "isError": True
        }
    except Exception as e:
        return {
            "content": [{"type": "text", "text": f"Error writing file: {str(e)}"}],
            "isError": True
        }


@tool(
    "file_list",
    "List files and directories in MATLAB's current working directory. "
    "Supports glob patterns (e.g., '*.m', 'src/**/*.m').",
    {"path": str, "pattern": str, "recursive": bool}
)
async def file_list(args: Dict[str, Any]) -> Dict[str, Any]:
    """List directory contents with optional glob pattern matching."""
    path = str(args.get("path", "."))
    pattern = args.get("pattern", "*")
    recursive = args.get("recursive", False)

    _logger.debug("file_tools", "dir_list", {"path": path, "pattern": pattern, "recursive": recursive})

    try:
        base_dir = _get_matlab_pwd()
        resolved_path = _validate_path(path, base_dir)

        if not os.path.isdir(resolved_path):
            return {
                "content": [{"type": "text", "text": f"Error: Not a directory: {path}"}],
                "isError": True
            }

        results: List[str] = []
        max_results = 100

        if recursive:
            # Walk directory tree
            for root, dirs, files in os.walk(resolved_path):
                # Filter directories
                dirs[:] = [d for d in dirs if not d.startswith('.')]

                rel_root = os.path.relpath(root, resolved_path)
                if rel_root == '.':
                    rel_root = ''

                for d in sorted(dirs):
                    dir_path = os.path.join(rel_root, d) if rel_root else d
                    if fnmatch.fnmatch(d, pattern):
                        results.append(f"[DIR]  {dir_path}/")

                for f in sorted(files):
                    if f.startswith('.'):
                        continue
                    if fnmatch.fnmatch(f, pattern):
                        file_path = os.path.join(rel_root, f) if rel_root else f
                        full_path = os.path.join(root, f)
                        size = os.path.getsize(full_path)
                        size_str = _format_size(size)
                        results.append(f"[FILE] {file_path} ({size_str})")

                if len(results) >= max_results:
                    break
        else:
            # Single directory listing
            entries = sorted(os.listdir(resolved_path))
            for entry in entries:
                if entry.startswith('.'):
                    continue
                if not fnmatch.fnmatch(entry, pattern):
                    continue

                full_path = os.path.join(resolved_path, entry)
                if os.path.isdir(full_path):
                    results.append(f"[DIR]  {entry}/")
                else:
                    size = os.path.getsize(full_path)
                    size_str = _format_size(size)
                    results.append(f"[FILE] {entry} ({size_str})")

                if len(results) >= max_results:
                    break

        rel_path = os.path.relpath(resolved_path, base_dir)
        if rel_path == '.':
            rel_path = '(current directory)'

        header = f"Contents of {rel_path}"
        if pattern != '*':
            header += f" matching '{pattern}'"
        if recursive:
            header += " (recursive)"
        header += f":\n{'─' * 40}\n"

        if not results:
            return {
                "content": [{"type": "text", "text": header + "No matching files or directories found."}]
            }

        truncated = ""
        if len(results) >= max_results:
            truncated = f"\n... (truncated at {max_results} results)"

        return {
            "content": [{"type": "text", "text": header + "\n".join(results) + truncated}]
        }

    except ValueError as e:
        return {
            "content": [{"type": "text", "text": f"Error: {str(e)}"}],
            "isError": True
        }
    except Exception as e:
        return {
            "content": [{"type": "text", "text": f"Error listing directory: {str(e)}"}],
            "isError": True
        }


@tool(
    "file_mkdir",
    "Create a directory (and parent directories) in MATLAB's current working directory.",
    {"path": str}
)
async def file_mkdir(args: Dict[str, Any]) -> Dict[str, Any]:
    """Create a directory with security constraints."""
    path = str(args.get("path", ""))

    if not path:
        return {
            "content": [{"type": "text", "text": "Error: No path provided"}],
            "isError": True
        }

    try:
        base_dir = _get_matlab_pwd()
        resolved_path = _validate_path(path, base_dir)

        if os.path.exists(resolved_path):
            if os.path.isdir(resolved_path):
                return {
                    "content": [{"type": "text", "text": f"Directory already exists: {path}"}]
                }
            else:
                return {
                    "content": [{"type": "text", "text": f"Error: A file already exists at: {path}"}],
                    "isError": True
                }

        os.makedirs(resolved_path, exist_ok=True)

        rel_path = os.path.relpath(resolved_path, base_dir)
        return {
            "content": [{"type": "text", "text": f"Created directory: {rel_path}"}]
        }

    except ValueError as e:
        return {
            "content": [{"type": "text", "text": f"Error: {str(e)}"}],
            "isError": True
        }
    except Exception as e:
        return {
            "content": [{"type": "text", "text": f"Error creating directory: {str(e)}"}],
            "isError": True
        }


def _format_size(size_bytes: int) -> str:
    """Format file size in human-readable format."""
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1024 * 1024:
        return f"{size_bytes / 1024:.1f} KB"
    elif size_bytes < 1024 * 1024 * 1024:
        return f"{size_bytes / 1024 / 1024:.1f} MB"
    else:
        return f"{size_bytes / 1024 / 1024 / 1024:.1f} GB"


# List of all file tools for easy importing
FILE_TOOLS = [file_read, file_write, file_list, file_mkdir]
