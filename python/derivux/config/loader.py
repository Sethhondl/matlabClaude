"""
Configuration Loader - Load and merge configuration from multiple sources.

Configuration precedence (low → high):
1. ~/.derivux/config.json (global defaults)
2. .derivux/config.json (project config)
3. Environment variables (DERIVUX_*)
4. Runtime overrides

Supports:
- JSON configuration files
- Environment variable substitution
- Deep merging of nested configs
"""

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional


@dataclass
class DerivuxConfig:
    """Parsed Derivux configuration.

    Attributes:
        model: Claude model ID
        primary_agent: Default primary agent name
        permissions: Global permission defaults
        agents_dir: Directory containing agent markdown files
        log_level: Logging level
        log_directory: Directory for log files
    """
    model: str = "claude-sonnet-4-5"
    primary_agent: str = "build"
    permissions: Dict[str, str] = field(default_factory=dict)
    agents_dir: str = ".derivux/agents"
    log_level: str = "INFO"
    log_directory: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "model": self.model,
            "primary_agent": self.primary_agent,
            "permissions": self.permissions,
            "agents_dir": self.agents_dir,
            "log_level": self.log_level,
            "log_directory": self.log_directory,
        }


class ConfigLoader:
    """Load configuration from multiple sources with precedence.

    Example:
        loader = ConfigLoader(project_root="/path/to/project")
        config = loader.load()
        print(config.model)  # claude-sonnet-4-5
    """

    def __init__(
        self,
        project_root: Optional[str] = None,
        home_dir: Optional[str] = None,
    ):
        """Initialize the config loader.

        Args:
            project_root: Project root directory (default: current working dir)
            home_dir: Home directory (default: user's home)
        """
        self.project_root = Path(project_root) if project_root else Path.cwd()
        self.home_dir = Path(home_dir) if home_dir else Path.home()

        # Config file paths
        self.global_config_path = self.home_dir / ".derivux" / "config.json"
        self.project_config_path = self.project_root / ".derivux" / "config.json"

    def load(self) -> DerivuxConfig:
        """Load and merge configuration from all sources.

        Returns:
            Merged DerivuxConfig object
        """
        config_dict: Dict[str, Any] = {}

        # 1. Load global config (lowest priority)
        if self.global_config_path.exists():
            global_config = self._load_json(self.global_config_path)
            config_dict = self._deep_merge(config_dict, global_config)

        # 2. Load project config
        if self.project_config_path.exists():
            project_config = self._load_json(self.project_config_path)
            config_dict = self._deep_merge(config_dict, project_config)

        # 3. Apply environment variables
        config_dict = self._apply_env_vars(config_dict)

        # 4. Create config object with defaults
        return DerivuxConfig(
            model=config_dict.get("model", "claude-sonnet-4-5"),
            primary_agent=config_dict.get("primary_agent", "build"),
            permissions=config_dict.get("permissions", {}),
            agents_dir=config_dict.get("agents_dir", ".derivux/agents"),
            log_level=config_dict.get("log_level", "INFO"),
            log_directory=config_dict.get("log_directory"),
        )

    def _load_json(self, path: Path) -> Dict[str, Any]:
        """Load a JSON configuration file.

        Args:
            path: Path to JSON file

        Returns:
            Parsed JSON as dict, or empty dict on error
        """
        try:
            with open(path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            # Log warning but don't fail
            return {}

    def _deep_merge(
        self,
        base: Dict[str, Any],
        override: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Deep merge two dictionaries.

        Values from override take precedence. Nested dicts are merged recursively.

        Args:
            base: Base dictionary
            override: Override dictionary (takes precedence)

        Returns:
            Merged dictionary
        """
        result = base.copy()
        for key, value in override.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = self._deep_merge(result[key], value)
            else:
                result[key] = value
        return result

    def _apply_env_vars(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """Apply environment variable overrides.

        Environment variables with DERIVUX_ prefix override config values.
        Examples:
            DERIVUX_MODEL -> config["model"]
            DERIVUX_LOG_LEVEL -> config["log_level"]

        Args:
            config: Config dictionary to update

        Returns:
            Updated config dictionary
        """
        env_mappings = {
            "DERIVUX_MODEL": "model",
            "DERIVUX_PRIMARY_AGENT": "primary_agent",
            "DERIVUX_LOG_LEVEL": "log_level",
            "DERIVUX_LOG_DIRECTORY": "log_directory",
            "DERIVUX_AGENTS_DIR": "agents_dir",
        }

        for env_var, config_key in env_mappings.items():
            value = os.environ.get(env_var)
            if value is not None:
                config[config_key] = value

        return config

    def get_agents_dir(self) -> Path:
        """Get the resolved agents directory path.

        Returns:
            Path to agents directory
        """
        config = self.load()
        agents_dir = config.agents_dir

        # If relative path, resolve from project root
        if not os.path.isabs(agents_dir):
            return self.project_root / agents_dir

        return Path(agents_dir)

    def list_agent_files(self) -> List[Path]:
        """List all agent markdown files.

        Returns:
            List of paths to agent .md files
        """
        agents_dir = self.get_agents_dir()
        if not agents_dir.exists():
            return []

        return list(agents_dir.glob("*.md"))


def load_config(project_root: Optional[str] = None) -> DerivuxConfig:
    """Convenience function to load configuration.

    Args:
        project_root: Optional project root directory

    Returns:
        Loaded DerivuxConfig
    """
    loader = ConfigLoader(project_root=project_root)
    return loader.load()
