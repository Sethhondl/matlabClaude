"""
Markdown Parser - Parse agent definition files with YAML frontmatter.

Agent files are markdown with YAML frontmatter:

```markdown
---
description: Agent description
mode: primary | subagent
command: /command (for subagents)
permissions:
  matlab_execute: allow
  file_write: deny
thinking_budget: 16384
---

System prompt content goes here...
```
"""

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

# Try to import yaml, fall back to simple parsing if not available
try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False


@dataclass
class AgentDefinition:
    """Parsed agent definition from markdown file.

    Attributes:
        name: Agent name (from filename)
        description: Human-readable description
        mode: Agent mode ('primary' or 'subagent')
        command: Slash command for invocation (e.g., '/simulink')
        system_prompt: Full system prompt content
        permissions: Dict of tool_name -> permission_state
        thinking_budget: Optional extended thinking token budget
        file_path: Path to the source markdown file
    """
    name: str
    description: str = ""
    mode: str = "subagent"  # 'primary' or 'subagent'
    command: str = ""
    system_prompt: str = ""
    permissions: Dict[str, str] = field(default_factory=dict)
    thinking_budget: Optional[int] = None
    file_path: Optional[str] = None

    @property
    def is_primary(self) -> bool:
        """Check if this is a primary agent."""
        return self.mode == "primary"

    @property
    def is_subagent(self) -> bool:
        """Check if this is a subagent."""
        return self.mode == "subagent"


class MarkdownParser:
    """Parse markdown agent files with YAML frontmatter.

    Example:
        parser = MarkdownParser()
        agent_def = parser.parse_file("/path/to/simulink.md")
        print(agent_def.name)  # "simulink"
        print(agent_def.system_prompt)  # The markdown content
    """

    # Regex to match YAML frontmatter
    FRONTMATTER_PATTERN = re.compile(
        r'^---\s*\n(.*?)\n---\s*\n',
        re.DOTALL
    )

    def parse_file(self, file_path: str) -> AgentDefinition:
        """Parse an agent definition from a markdown file.

        Args:
            file_path: Path to the markdown file

        Returns:
            Parsed AgentDefinition

        Raises:
            FileNotFoundError: If file doesn't exist
            ValueError: If file format is invalid
        """
        path = Path(file_path)
        if not path.exists():
            raise FileNotFoundError(f"Agent file not found: {file_path}")

        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()

        # Derive name from filename (without extension)
        name = path.stem

        return self.parse_content(content, name, str(path))

    def parse_content(
        self,
        content: str,
        name: str,
        file_path: Optional[str] = None
    ) -> AgentDefinition:
        """Parse agent definition from markdown content.

        Args:
            content: Markdown content with YAML frontmatter
            name: Agent name
            file_path: Optional source file path

        Returns:
            Parsed AgentDefinition
        """
        # Extract frontmatter and body
        frontmatter_dict, body = self._extract_frontmatter(content)

        # Build agent definition
        return AgentDefinition(
            name=name,
            description=frontmatter_dict.get("description", ""),
            mode=frontmatter_dict.get("mode", "subagent"),
            command=frontmatter_dict.get("command", f"/{name}"),
            system_prompt=body.strip(),
            permissions=frontmatter_dict.get("permissions", {}),
            thinking_budget=frontmatter_dict.get("thinking_budget"),
            file_path=file_path,
        )

    def _extract_frontmatter(self, content: str) -> tuple:
        """Extract YAML frontmatter and body from content.

        Args:
            content: Full markdown content

        Returns:
            Tuple of (frontmatter_dict, body)
        """
        match = self.FRONTMATTER_PATTERN.match(content)

        if not match:
            # No frontmatter, treat entire content as body
            return {}, content

        frontmatter_yaml = match.group(1)
        body = content[match.end():]

        # Parse YAML frontmatter
        if YAML_AVAILABLE:
            try:
                frontmatter_dict = yaml.safe_load(frontmatter_yaml) or {}
            except yaml.YAMLError:
                frontmatter_dict = self._simple_yaml_parse(frontmatter_yaml)
        else:
            frontmatter_dict = self._simple_yaml_parse(frontmatter_yaml)

        return frontmatter_dict, body

    def _simple_yaml_parse(self, yaml_content: str) -> Dict[str, Any]:
        """Simple YAML parser for basic key-value pairs.

        Used as fallback when PyYAML is not available.

        Args:
            yaml_content: YAML content to parse

        Returns:
            Parsed dictionary
        """
        result: Dict[str, Any] = {}
        current_key = None
        nested_dict: Optional[Dict[str, Any]] = None

        for line in yaml_content.split('\n'):
            line = line.rstrip()

            if not line or line.startswith('#'):
                continue

            # Check for nested dict
            if line.startswith('  ') and current_key:
                # This is a nested value
                stripped = line.strip()
                if ':' in stripped:
                    key, value = stripped.split(':', 1)
                    key = key.strip()
                    value = value.strip()
                    if nested_dict is None:
                        nested_dict = {}
                        result[current_key] = nested_dict
                    nested_dict[key] = self._parse_value(value)
                continue

            # Top-level key-value
            if ':' in line:
                current_key, value = line.split(':', 1)
                current_key = current_key.strip()
                value = value.strip()

                if value:
                    result[current_key] = self._parse_value(value)
                    nested_dict = None
                else:
                    # Empty value, might be followed by nested dict
                    nested_dict = None

        return result

    def _parse_value(self, value: str) -> Any:
        """Parse a YAML value string.

        Args:
            value: Value string to parse

        Returns:
            Parsed value (int, bool, or str)
        """
        # Remove quotes
        if (value.startswith('"') and value.endswith('"')) or \
           (value.startswith("'") and value.endswith("'")):
            return value[1:-1]

        # Try int
        try:
            return int(value)
        except ValueError:
            pass

        # Try bool
        if value.lower() in ('true', 'yes', 'on'):
            return True
        if value.lower() in ('false', 'no', 'off'):
            return False

        # Try null
        if value.lower() in ('null', 'none', '~'):
            return None

        return value


def load_agent_from_file(file_path: str) -> AgentDefinition:
    """Convenience function to load an agent definition from file.

    Args:
        file_path: Path to markdown file

    Returns:
        Parsed AgentDefinition
    """
    parser = MarkdownParser()
    return parser.parse_file(file_path)


def load_all_agents(agents_dir: str) -> List[AgentDefinition]:
    """Load all agent definitions from a directory.

    Args:
        agents_dir: Path to agents directory

    Returns:
        List of parsed AgentDefinition objects
    """
    agents_path = Path(agents_dir)
    if not agents_path.exists():
        return []

    parser = MarkdownParser()
    agents = []

    for md_file in agents_path.glob("*.md"):
        try:
            agent = parser.parse_file(str(md_file))
            agents.append(agent)
        except Exception:
            # Skip invalid files
            continue

    return agents
