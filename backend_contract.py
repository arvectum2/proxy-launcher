# -*- coding: utf-8 -*-
"""Executable unified backend contract and regression matrix (the unified backend contract).

This module is intentionally declarative. It does not mutate operating-system
proxy state. Instead it defines the stable public backend surface, validates
concrete backend classes, and publishes the regression obligations that every
governed backend must satisfy before release.
"""

from dataclasses import asdict, dataclass
from inspect import Parameter, signature
from typing import Dict, Tuple

from capability_model import Feature, capabilities_for_backend, declared_backend_ids
from proxy_backend import ProxyBackend

BACKEND_CONTRACT_VERSION = "1"


@dataclass(frozen=True)
class BackendOperation:
    name: str
    positional_arguments: Tuple[str, ...]
    purpose: str


BACKEND_OPERATIONS: Tuple[BackendOperation, ...] = (
    BackendOperation(
        "enable",
        ("config",),
        "Persist rollback evidence before applying the resolved Arvectum proxy configuration.",
    ),
    BackendOperation(
        "disable",
        (),
        "Restore only state owned or proven by Arvectum and preserve foreign proxy state.",
    ),
    BackendOperation(
        "is_enabled",
        ("config",),
        "Report enabled only when active state belongs to the supplied resolved configuration.",
    ),
    BackendOperation(
        "restore_pending",
        (),
        "Report durable incomplete-rollback evidence without silently clearing it.",
    ),
    BackendOperation(
        "sync_no_proxy",
        ("config",),
        "Synchronize active bypass state while preserving pre-existing user entries.",
    ),
)


@dataclass(frozen=True)
class RegressionRequirement:
    requirement_id: str
    invariant: str
    backends: Tuple[str, ...]
    evidence: Tuple[str, ...]


_ALL_BACKENDS = tuple(declared_backend_ids())

REGRESSION_MATRIX: Tuple[RegressionRequirement, ...] = (
    RegressionRequirement(
        "CONTRACT-001",
        "Every governed backend is a complete ProxyBackend implementation with the canonical five-operation surface.",
        _ALL_BACKENDS,
        ("tests.test_backend_contract_matrix",),
    ),
    RegressionRequirement(
        "LIFECYCLE-001",
        "Enable/status/sync/disable lifecycle remains configuration-specific and fail-safe.",
        _ALL_BACKENDS,
        (
            "tests.test_windows_backend",
            "tests.test_macos_backend",
            "tests.test_linux_backend",
        ),
    ),
    RegressionRequirement(
        "ROLLBACK-001",
        "Rollback evidence is durable, ownership-aware, and fail-closed when incomplete or unreadable.",
        _ALL_BACKENDS,
        (
            "tests.test_windows_backend",
            "tests.test_macos_backend",
            "tests.test_linux_backend",
        ),
    ),
    RegressionRequirement(
        "FOREIGN-001",
        "Foreign or administrator-managed proxy state is not silently replaced or destroyed.",
        _ALL_BACKENDS,
        (
            "tests.test_foreign_proxy_protection",
            "tests.test_windows_backend",
            "tests.test_macos_backend",
            "tests.test_linux_backend",
        ),
    ),
    RegressionRequirement(
        "BYPASS-001",
        "Bypass/no-proxy synchronization preserves existing user entries and applies resolved Arvectum exclusions.",
        _ALL_BACKENDS,
        (
            "tests.test_windows_backend",
            "tests.test_macos_backend",
            "tests.test_linux_backend",
        ),
    ),
    RegressionRequirement(
        "RUNTIME-001",
        "Runtime platform selection resolves to exactly one governed backend and fails closed elsewhere.",
        _ALL_BACKENDS,
        ("tests.test_backend_runtime", "tests.test_backend_runtime_wiring"),
    ),
    RegressionRequirement(
        "CAPABILITY-001",
        "Backend selection and capability declarations stay one-to-one; supported system-proxy features are not inferred ad hoc.",
        _ALL_BACKENDS,
        ("tests.test_capability_model", "tests.test_backend_contract_matrix"),
    ),
    RegressionRequirement(
        "WINDOWS-BASELINE-001",
        "The customer-proven Windows legacy mutation path remains behind the adapter and is not reimplemented by the unified contract.",
        ("windows",),
        ("tests.test_customer_baseline_freeze", "tests.test_backend_runtime_wiring"),
    ),
)


class BackendContractError(TypeError):
    """Raised when a concrete backend drifts from the governed public contract."""


def _public_positional_arguments(method) -> Tuple[str, ...]:
    parameters = tuple(signature(method).parameters.values())
    names = []
    for parameter in parameters:
        if parameter.name == "self":
            continue
        if parameter.kind in (Parameter.POSITIONAL_ONLY, Parameter.POSITIONAL_OR_KEYWORD):
            names.append(parameter.name)
    return tuple(names)


def validate_backend_class(backend_cls, expected_backend_id: str) -> bool:
    """Validate structural compatibility without instantiating or mutating the OS."""
    expected_backend_id = str(expected_backend_id or "").strip().lower()
    if expected_backend_id not in declared_backend_ids():
        raise BackendContractError("unknown governed backend: %s" % (expected_backend_id or "<empty>"))
    if not isinstance(backend_cls, type) or not issubclass(backend_cls, ProxyBackend):
        raise BackendContractError("%r is not a ProxyBackend subclass" % (backend_cls,))
    if getattr(backend_cls, "__abstractmethods__", None):
        raise BackendContractError(
            "%s leaves abstract contract members unresolved: %s"
            % (backend_cls.__name__, sorted(backend_cls.__abstractmethods__))
        )

    backend_id_property = getattr(backend_cls, "backend_id", None)
    if not isinstance(backend_id_property, property):
        raise BackendContractError("%s.backend_id must remain a property" % backend_cls.__name__)

    for operation in BACKEND_OPERATIONS:
        method = getattr(backend_cls, operation.name, None)
        if not callable(method):
            raise BackendContractError(
                "%s is missing callable %s" % (backend_cls.__name__, operation.name)
            )
        actual = _public_positional_arguments(method)
        if actual != operation.positional_arguments:
            raise BackendContractError(
                "%s.%s signature drift: expected %r, got %r"
                % (backend_cls.__name__, operation.name, operation.positional_arguments, actual)
            )
    return True


def governed_backend_classes() -> Dict[str, type]:
    """Return the canonical concrete classes, imported without constructing them."""
    from linux_backend import LinuxBackend
    from macos_backend import MacOSBackend
    from windows_backend import WindowsBackend

    return {
        "windows": WindowsBackend,
        "macos": MacOSBackend,
        "linux": LinuxBackend,
    }


def validate_all_backends() -> bool:
    classes = governed_backend_classes()
    declared = set(declared_backend_ids())
    if set(classes) != declared:
        raise BackendContractError(
            "backend registry/capability mismatch: classes=%r capabilities=%r"
            % (sorted(classes), sorted(declared))
        )
    for backend_id in sorted(classes):
        validate_backend_class(classes[backend_id], backend_id)
    return True


def regression_requirements_for(backend_id: str) -> Tuple[RegressionRequirement, ...]:
    backend_id = str(backend_id or "").strip().lower()
    capabilities_for_backend(backend_id)  # governed/fail-closed validation
    return tuple(row for row in REGRESSION_MATRIX if backend_id in row.backends)


def contract_manifest() -> Dict[str, object]:
    """Return a deterministic machine-readable contract summary for CI/tooling."""
    validate_all_backends()
    return {
        "contract_version": BACKEND_CONTRACT_VERSION,
        "backends": list(declared_backend_ids()),
        "operations": [asdict(operation) for operation in BACKEND_OPERATIONS],
        "required_features": [
            Feature.SYSTEM_PROXY.value,
            Feature.BYPASS_RULES.value,
            Feature.SAFE_ROLLBACK.value,
        ],
        "regressions": [asdict(requirement) for requirement in REGRESSION_MATRIX],
    }