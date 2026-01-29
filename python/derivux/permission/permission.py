"""
Permission System - Two-tier permission model for tool access control.

Permissions cascade in this order (later overrides earlier):
1. Global defaults (from config)
2. Agent-specific overrides (from agent definition)

Global settings (auto_execute, bypass_mode) modify behavior without
changing the underlying permission cascade.

Each permission can be:
- allow: Tool can be used without prompting
- ask: Tool requires user approval before each use
- deny: Tool cannot be used at all
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Callable, Dict, List, Optional, Set
import asyncio
import uuid


@dataclass
class GlobalSettings:
    """Global settings that apply across all agents.

    These settings modify permission behavior without changing the
    underlying permission cascade:
    - auto_execute: When True, ASK permissions become ALLOW
    - bypass_mode: When True, enables dangerous operations in CodeExecutor

    Attributes:
        auto_execute: Auto-approve tools that would normally require ASK
        bypass_mode: Disable CodeExecutor security blocks
    """
    auto_execute: bool = False
    bypass_mode: bool = False


class PermissionState(Enum):
    """Permission state for a tool."""
    ALLOW = "allow"
    ASK = "ask"
    DENY = "deny"


@dataclass
class PermissionRequest:
    """A request for permission approval.

    When a tool has PermissionState.ASK, a request is created and
    passed to the approval callback for user decision.

    Attributes:
        request_id: Unique identifier for this request
        tool_name: Name of the tool requesting permission
        agent_name: Name of the agent making the request
        context: Additional context about the tool usage
        approved: Whether the request was approved (None if pending)
        remember: If approved, whether to remember for future requests
    """
    request_id: str
    tool_name: str
    agent_name: str
    context: Dict = field(default_factory=dict)
    approved: Optional[bool] = None
    remember: bool = False

    @classmethod
    def create(
        cls,
        tool_name: str,
        agent_name: str = "",
        context: Optional[Dict] = None
    ) -> "PermissionRequest":
        """Create a new permission request.

        Args:
            tool_name: Tool requesting permission
            agent_name: Agent making the request
            context: Additional context

        Returns:
            New PermissionRequest instance
        """
        return cls(
            request_id=str(uuid.uuid4()),
            tool_name=tool_name,
            agent_name=agent_name,
            context=context or {},
        )


class _PermissionRegistry:
    """Global permission registry (singleton).

    Manages permission states for tools with cascading overrides:
    1. Global defaults
    2. Agent-specific permissions

    Global settings (auto_execute, bypass_mode) modify behavior at check time.

    Example:
        Permission.set_default("matlab_execute", PermissionState.ALLOW)
        Permission.set_agent_override("plan", "matlab_execute", PermissionState.DENY)

        state = Permission.check("matlab_execute", agent="build")  # ALLOW
        state = Permission.check("matlab_execute", agent="plan")   # DENY

        # With auto_execute enabled:
        Permission.set_auto_execute(True)
        state = Permission.check("some_tool")  # ASK becomes ALLOW
    """

    _instance: Optional["_PermissionRegistry"] = None

    def __new__(cls) -> "_PermissionRegistry":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialize()
        return cls._instance

    def _initialize(self) -> None:
        """Initialize the permission registry."""
        # Global default permissions
        self._defaults: Dict[str, PermissionState] = {}

        # Agent-specific overrides: {agent_name: {tool_name: state}}
        self._agent_overrides: Dict[str, Dict[str, PermissionState]] = {}

        # Global settings (replaces runtime overrides)
        self._global_settings: GlobalSettings = GlobalSettings()

        # Current agent name for context
        self._current_agent: str = ""

        # Approval callback for "ask" permissions
        self._approval_callback: Optional[Callable] = None

        # Pending requests
        self._pending_requests: Dict[str, PermissionRequest] = {}

        # Remembered approvals (tool_name -> True means always allow)
        self._remembered: Dict[str, bool] = {}

    def set_default(self, tool_name: str, state: PermissionState) -> None:
        """Set the global default permission for a tool.

        Args:
            tool_name: Tool to set permission for
            state: Permission state
        """
        self._defaults[tool_name] = state

    def set_defaults_bulk(self, permissions: Dict[str, PermissionState]) -> None:
        """Set multiple default permissions at once.

        Args:
            permissions: Dict mapping tool names to states
        """
        self._defaults.update(permissions)

    def set_agent_override(
        self,
        agent_name: str,
        tool_name: str,
        state: PermissionState
    ) -> None:
        """Set an agent-specific permission override.

        Args:
            agent_name: Agent this override applies to
            tool_name: Tool to override
            state: Permission state for this agent
        """
        if agent_name not in self._agent_overrides:
            self._agent_overrides[agent_name] = {}
        self._agent_overrides[agent_name][tool_name] = state

    def set_agent_overrides_bulk(
        self,
        agent_name: str,
        permissions: Dict[str, PermissionState]
    ) -> None:
        """Set multiple agent-specific overrides at once.

        Args:
            agent_name: Agent these overrides apply to
            permissions: Dict mapping tool names to states
        """
        if agent_name not in self._agent_overrides:
            self._agent_overrides[agent_name] = {}
        self._agent_overrides[agent_name].update(permissions)

    def set_auto_execute(self, enabled: bool) -> None:
        """Set the global auto-execute setting.

        When enabled, ASK permissions are automatically converted to ALLOW.

        Args:
            enabled: True to auto-approve tools, False to require approval
        """
        self._global_settings.auto_execute = enabled

    def set_bypass_mode(self, enabled: bool) -> None:
        """Set the global bypass mode setting.

        When enabled, CodeExecutor security blocks are disabled.

        Args:
            enabled: True to disable security blocks
        """
        self._global_settings.bypass_mode = enabled

    def get_global_settings(self) -> GlobalSettings:
        """Get the current global settings.

        Returns:
            GlobalSettings dataclass with current values
        """
        return self._global_settings

    def is_auto_execute(self) -> bool:
        """Check if auto-execute is enabled.

        Returns:
            True if auto-execute is enabled
        """
        return self._global_settings.auto_execute

    def is_bypass_mode(self) -> bool:
        """Check if bypass mode is enabled.

        Returns:
            True if bypass mode is enabled
        """
        return self._global_settings.bypass_mode

    def set_current_agent(self, agent_name: str) -> None:
        """Set the current agent for permission checks.

        Args:
            agent_name: Name of the current agent
        """
        self._current_agent = agent_name

    def check(
        self,
        tool_name: str,
        agent: Optional[str] = None
    ) -> PermissionState:
        """Check the permission state for a tool.

        Cascading order (later overrides earlier):
        1. Global default (or ALLOW if not set)
        2. Agent-specific override (if exists)

        After cascade, global settings are applied:
        - If auto_execute is enabled, ASK becomes ALLOW

        Args:
            tool_name: Tool to check
            agent: Agent name (uses current agent if not specified)

        Returns:
            PermissionState for this tool/agent combination
        """
        agent_name = agent or self._current_agent

        # Start with default (ALLOW if not specified)
        state = self._defaults.get(tool_name, PermissionState.ALLOW)

        # Apply agent override if exists
        if agent_name and agent_name in self._agent_overrides:
            agent_perms = self._agent_overrides[agent_name]
            if tool_name in agent_perms:
                state = agent_perms[tool_name]

        # Apply auto_execute setting: ASK becomes ALLOW
        if state == PermissionState.ASK and self._global_settings.auto_execute:
            state = PermissionState.ALLOW

        # Check remembered approvals for ASK state
        if state == PermissionState.ASK:
            if self._remembered.get(tool_name):
                state = PermissionState.ALLOW

        return state

    def is_allowed(
        self,
        tool_name: str,
        agent: Optional[str] = None
    ) -> bool:
        """Check if a tool is currently allowed.

        Args:
            tool_name: Tool to check
            agent: Agent name (uses current agent if not specified)

        Returns:
            True if tool is allowed (permission is ALLOW)
        """
        return self.check(tool_name, agent) == PermissionState.ALLOW

    def is_denied(
        self,
        tool_name: str,
        agent: Optional[str] = None
    ) -> bool:
        """Check if a tool is denied.

        Args:
            tool_name: Tool to check
            agent: Agent name (uses current agent if not specified)

        Returns:
            True if tool is denied
        """
        return self.check(tool_name, agent) == PermissionState.DENY

    def needs_approval(
        self,
        tool_name: str,
        agent: Optional[str] = None
    ) -> bool:
        """Check if a tool requires approval.

        Args:
            tool_name: Tool to check
            agent: Agent name (uses current agent if not specified)

        Returns:
            True if tool requires approval (permission is ASK)
        """
        return self.check(tool_name, agent) == PermissionState.ASK

    def set_approval_callback(
        self,
        callback: Callable[[PermissionRequest], None]
    ) -> None:
        """Set the callback for approval requests.

        The callback receives a PermissionRequest and should update
        its `approved` field when the user responds.

        Args:
            callback: Function to call when approval is needed
        """
        self._approval_callback = callback

    async def request_approval(
        self,
        tool_name: str,
        agent_name: str = "",
        context: Optional[Dict] = None
    ) -> bool:
        """Request approval for a tool.

        Creates a PermissionRequest and waits for approval via callback.

        Args:
            tool_name: Tool requesting approval
            agent_name: Agent making the request
            context: Additional context for the request

        Returns:
            True if approved, False if denied
        """
        request = PermissionRequest.create(tool_name, agent_name, context)
        self._pending_requests[request.request_id] = request

        # Call approval callback if set
        if self._approval_callback:
            self._approval_callback(request)

            # Wait for approval (poll for response)
            for _ in range(300):  # 30 second timeout
                if request.approved is not None:
                    break
                await asyncio.sleep(0.1)

        # Clean up and return result
        self._pending_requests.pop(request.request_id, None)

        if request.approved and request.remember:
            self._remembered[tool_name] = True

        return request.approved or False

    def approve(
        self,
        request_id: str,
        remember: bool = False
    ) -> bool:
        """Approve a pending permission request.

        Args:
            request_id: ID of the request to approve
            remember: If True, remember this approval for future requests

        Returns:
            True if request was found and approved
        """
        request = self._pending_requests.get(request_id)
        if request:
            request.approved = True
            request.remember = remember
            return True
        return False

    def deny(self, request_id: str) -> bool:
        """Deny a pending permission request.

        Args:
            request_id: ID of the request to deny

        Returns:
            True if request was found and denied
        """
        request = self._pending_requests.get(request_id)
        if request:
            request.approved = False
            return True
        return False

    def get_allowed_tools(
        self,
        agent: Optional[str] = None,
        all_tools: Optional[List[str]] = None
    ) -> List[str]:
        """Get list of allowed tools for an agent.

        Args:
            agent: Agent name (uses current agent if not specified)
            all_tools: List of all tool names to check. If None, returns
                      tools from defaults only.

        Returns:
            List of tool names that are allowed
        """
        tools_to_check = all_tools or list(self._defaults.keys())
        return [
            tool for tool in tools_to_check
            if self.check(tool, agent) == PermissionState.ALLOW
        ]

    def get_denied_tools(
        self,
        agent: Optional[str] = None,
        all_tools: Optional[List[str]] = None
    ) -> List[str]:
        """Get list of denied tools for an agent.

        Args:
            agent: Agent name (uses current agent if not specified)
            all_tools: List of all tool names to check

        Returns:
            List of tool names that are denied
        """
        tools_to_check = all_tools or list(self._defaults.keys())
        return [
            tool for tool in tools_to_check
            if self.check(tool, agent) == PermissionState.DENY
        ]

    def clear_remembered(self) -> None:
        """Clear all remembered approvals."""
        self._remembered.clear()

    def clear(self) -> None:
        """Clear all permissions. Used for testing."""
        self._initialize()


# Global singleton instance
Permission = _PermissionRegistry()


def configure_permissions_for_mode(mode: str) -> None:
    """DEPRECATED: Configure permissions for an execution mode.

    This function is kept for backward compatibility during migration.
    The new architecture uses agent-based permissions with global settings.

    New approach:
    - Use Agent.switch('build') or Agent.switch('plan') for agent switching
    - Use Permission.set_auto_execute(True/False) for auto-execute toggle
    - Use Permission.set_bypass_mode(True/False) for bypass toggle

    Args:
        mode: Execution mode ('plan', 'prompt', 'auto', 'bypass')
    """
    import warnings
    warnings.warn(
        "configure_permissions_for_mode is deprecated. "
        "Use agent switching and global settings instead.",
        DeprecationWarning,
        stacklevel=2
    )

    # Map old modes to new architecture
    if mode == "plan":
        # Plan agent has its own permission restrictions
        Permission.set_auto_execute(False)
        Permission.set_bypass_mode(False)

    elif mode == "prompt":
        # Normal mode: no auto-execute, no bypass
        Permission.set_auto_execute(False)
        Permission.set_bypass_mode(False)

    elif mode == "auto":
        # Auto mode: enable auto-execute
        Permission.set_auto_execute(True)
        Permission.set_bypass_mode(False)

    elif mode == "bypass":
        # Bypass mode: enable both
        Permission.set_auto_execute(True)
        Permission.set_bypass_mode(True)
