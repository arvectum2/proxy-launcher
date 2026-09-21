# -*- coding: utf-8 -*-
"""Operating-system proxy integration boundary for Arvectum Proxy Launcher.

the platform backend contract deliberately defines the contract only.  Concrete Windows,
macOS, and Linux implementations are introduced separately so the proven
proxy engine can evolve without coupling transport logic to OS mutation code.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Tuple


@dataclass(frozen=True)
class ProxyBackendConfig:
    """Resolved OS-facing proxy configuration.

    The backend receives already-resolved values rather than application file
    paths or the complete ``proxy_settings.json`` model.  This keeps platform
    code independent from configuration persistence and from ProxyCore itself.
    """

    pac_url: str
    http_proxy_url: str
    no_proxy: Tuple[str, ...] = ()


class ProxyBackend(ABC):
    """Abstract boundary for mutating and inspecting system proxy state.

    Contract invariants for every concrete backend:

    * ``enable`` must be fail-safe: persistent rollback state is created before
      platform proxy settings are changed.
    * ``disable`` restores only state owned/proven by Arvectum and must not
      replace unrelated user or administrator proxy settings.
    * ``is_enabled`` is an ownership-aware check for *this* configuration, not
      a generic "some proxy is enabled" test.
    * ``restore_pending`` reports incomplete rollback evidence and therefore
      must never silently clear it.
    * ``sync_no_proxy`` updates active bypass state without taking ownership of
      pre-existing user bypass entries.
    * ``refresh`` may reassert only state already proven to belong to this
      backend; the default implementation performs no mutation.

    Backends do not start/stop ProxyCore, persist product settings, generate
    PAC content, or implement GUI policy.  Those responsibilities remain in
    the platform-neutral core/application layers.
    """

    @property
    @abstractmethod
    def backend_id(self) -> str:
        """Stable backend identifier, for example ``windows`` or ``macos``."""
        raise NotImplementedError

    @abstractmethod
    def enable(self, config: ProxyBackendConfig) -> bool:
        """Enable this launcher's system proxy configuration safely."""
        raise NotImplementedError

    def refresh(self, config: ProxyBackendConfig):
        """Reassert already-owned live state without acquiring ownership."""
        return False

    @abstractmethod
    def disable(self) -> bool:
        """Restore the pre-Arvectum system proxy state owned by this backend."""
        raise NotImplementedError

    @abstractmethod
    def is_enabled(self, config: ProxyBackendConfig) -> bool:
        """Return True only when the active system proxy belongs to *config*."""
        raise NotImplementedError

    @abstractmethod
    def restore_pending(self) -> bool:
        """Return True when durable evidence shows rollback is incomplete."""
        raise NotImplementedError

    @abstractmethod
    def sync_no_proxy(self, config: ProxyBackendConfig) -> bool:
        """Synchronize bypass/no-proxy state for an already active backend."""
        raise NotImplementedError
