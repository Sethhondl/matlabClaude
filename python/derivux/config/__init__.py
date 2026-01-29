"""
Configuration System - Load configs from multiple sources with precedence.

Provides:
- ConfigLoader: Load and merge configuration from files
- MarkdownParser: Parse markdown agent files with YAML frontmatter
- AgentDefinition: Parsed agent definition from markdown

Configuration precedence (low → high):
1. ~/.derivux/config.json (global defaults)
2. .derivux/config.json (project config)
3. .derivux/agents/*.md (agent definitions)
4. Runtime overrides
"""

from .loader import ConfigLoader, load_config
from .markdown import MarkdownParser, AgentDefinition

__all__ = ["ConfigLoader", "load_config", "MarkdownParser", "AgentDefinition"]
