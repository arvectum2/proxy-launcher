"""Provider-neutral contracts for Arvectum-managed proxy nodes."""

from .allocator import NoCapacityError, select_node
from .models import ExitClass, ManagedAccess, ManagedNode, ProductSpec, Transport
from .provisioning import issue_access
from .xray import RealityServerSecrets, render_client_uri, render_server_config

__all__ = [
    "ExitClass",
    "ManagedAccess",
    "ManagedNode",
    "NoCapacityError",
    "ProductSpec",
    "RealityServerSecrets",
    "Transport",
    "issue_access",
    "render_client_uri",
    "render_server_config",
    "select_node",
]
