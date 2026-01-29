"""
Permission System - Two-tier permission model (allow/ask/deny).

Provides:
- Permission: Global permission registry (namespace singleton)
- PermissionState: Enum of allow/ask/deny states
- GlobalSettings: Dataclass for auto_execute and bypass_mode settings
- Cascading permissions: global → agent

Global settings (auto_execute, bypass_mode) modify behavior at check time
without changing the underlying permission cascade.

The permission system determines what tools an agent can use without
requiring each agent to maintain its own tool list.
"""

from .permission import (
    Permission,
    PermissionState,
    PermissionRequest,
    GlobalSettings,
    configure_permissions_for_mode,  # Deprecated but kept for compatibility
)

__all__ = [
    "Permission",
    "PermissionState",
    "PermissionRequest",
    "GlobalSettings",
    "configure_permissions_for_mode",
]
