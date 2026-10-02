"""Canonical portable-executable lifecycle for Arvectum Proxy Launcher.

Owns the Windows portable stable-copy lifecycle: hash-verified replacement, install-owner marking, safe handoff and canonical-install recognition. Runtime collaborators resolve through the canonical composition module.
"""

from __future__ import annotations

import hashlib
import io
import os
import shutil
import subprocess
import sys
from types import ModuleType
from typing import Iterable


_CORE: ModuleType | None = None


def configure(core: ModuleType) -> None:
    """Bind the canonical composition module used for runtime collaborators."""
    global _CORE
    _CORE = core


def _core() -> ModuleType:
    if _CORE is None:
        raise RuntimeError("portable lifecycle is not configured")
    return _CORE


def _sha256_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


_PORTABLE_BUILD_MANIFEST = "build_manifest.json"
_PORTABLE_WINDIVERT_DIR = "WINDOWS_WINDIVERT"


def _is_historical_documents_copy(path: str) -> bool:
    core = _core()
    return core._same_path(path, core.historical_documents_app_exe())


def _directory_hashes(root: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for current, _dirs, files in os.walk(root):
        for name in sorted(files):
            path = os.path.join(current, name)
            relative = os.path.relpath(path, root).replace("\\", "/")
            result[relative] = _sha256_file(path)
    return result


def _sync_portable_support_files(source_dir: str, target_dir: str) -> None:
    manifest_source = os.path.join(
        source_dir, _PORTABLE_BUILD_MANIFEST
    )
    manifest_target = os.path.join(
        target_dir, _PORTABLE_BUILD_MANIFEST
    )
    if os.path.isfile(manifest_source):
        temporary = manifest_target + ".%s.tmp" % os.getpid()
        try:
            shutil.copy2(manifest_source, temporary)
            if (
                _sha256_file(manifest_source)
                != _sha256_file(temporary)
            ):
                raise IOError("portable build manifest copy hash mismatch")
            os.replace(temporary, manifest_target)
        finally:
            if os.path.exists(temporary):
                os.remove(temporary)
    # Absence beside the invoking portable executable is not authority to
    # delete support metadata owned by an already-installed canonical build.
    # Historical/partial portable copies may legitimately lack these files.
    # Readiness remains fail-closed on manifest identity/hash when they exist.

    bundle_source = os.path.join(
        source_dir, _PORTABLE_WINDIVERT_DIR
    )
    bundle_target = os.path.join(
        target_dir, _PORTABLE_WINDIVERT_DIR
    )
    if os.path.isdir(bundle_source):
        temporary_bundle = bundle_target + ".%s.tmp" % os.getpid()
        if os.path.exists(temporary_bundle):
            shutil.rmtree(temporary_bundle)
        try:
            shutil.copytree(bundle_source, temporary_bundle)
            if (
                _directory_hashes(bundle_source)
                != _directory_hashes(temporary_bundle)
            ):
                raise IOError("portable WinDivert sidecar copy hash mismatch")
            if os.path.exists(bundle_target):
                shutil.rmtree(bundle_target)
            os.replace(temporary_bundle, bundle_target)
        finally:
            if os.path.exists(temporary_bundle):
                shutil.rmtree(temporary_bundle)


def ensure_stable_app_copy() -> str | None:
    """Copy a frozen Windows portable launcher to the canonical per-user app path.

    Copying is best-effort so a launcher opened from Downloads can still render
    actionable UI. An existing canonical copy is used only when its SHA-256
    matches the running executable; otherwise it is atomically replaced.
    """
    core = _core()
    if not (core.is_windows() and getattr(sys, "frozen", False)):
        return None
    core._LAST_SELF_HEAL_ERROR = ""
    source = os.path.realpath(sys.executable)
    target = os.path.realpath(core.stable_app_exe())
    if core._same_path(source, target):
        return target
    try:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if (
            os.path.isfile(target)
            and core._sha256_file(source) == core._sha256_file(target)
        ):
            _sync_portable_support_files(
                os.path.dirname(source),
                os.path.dirname(target),
            )
            return target
        temporary = target + ".%s.tmp" % os.getpid()
        try:
            shutil.copy2(source, temporary)
            if core._sha256_file(source) != core._sha256_file(temporary):
                raise IOError("stable executable copy hash mismatch")
            os.replace(temporary, target)
        finally:
            if os.path.exists(temporary):
                try:
                    os.remove(temporary)
                except OSError:
                    pass
        _sync_portable_support_files(
            os.path.dirname(source),
            os.path.dirname(target),
        )
        with io.open(
            os.path.join(os.path.dirname(target), core._INSTALL_OWNER_MARKER),
            "w",
            encoding="ascii",
        ) as marker:
            marker.write(core._INSTALL_OWNER_VALUE)
        core._log("portable launcher copied to canonical LocalAppData Programs location: %s" % target)
        return target
    except Exception as error:
        core._LAST_SELF_HEAL_ERROR = (
            "Не удалось обновить постоянную копию Launcher в LocalAppData: %s" % error
        )
        core._log("portable launcher self-heal failed: %r" % error)
        return None


def self_heal_error() -> str:
    return _core()._LAST_SELF_HEAL_ERROR


def managed_executable() -> str | None:
    """Return the only executable path allowed in Windows Run entries."""
    core = _core()
    if not getattr(sys, "frozen", False):
        return None
    return core.ensure_stable_app_copy()


def handoff_to_stable_copy(arguments: Iterable[str] | None = None) -> bool:
    """Continue an interactive/start portable launch from the canonical copy.

    Stop, status and rollback are maintenance commands whose caller must be able
    to wait for the exact process that performs the operation. They therefore
    never use the asynchronous portable handoff. This is especially important
    during installer migration from the historical Documents location.
    """
    core = _core()
    args = list(arguments or [])
    if args and args[0] in ("--stop", "--status", "--rollback"):
        return False
    if not (core.is_windows() and getattr(sys, "frozen", False)):
        return False
    source = os.path.realpath(sys.executable)
    target = core.ensure_stable_app_copy()
    if not target or core._same_path(source, target):
        return False
    try:
        subprocess.Popen(
            [target] + args,
            cwd=os.path.dirname(target),
            creationflags=getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0),
        )
        core._log("portable launcher handed off to canonical LocalAppData Programs copy")
        return True
    except Exception as error:
        core._log(
            "portable launcher handoff failed; keeping current GUI open: %r" % error
        )
        return False


def canonical_install_exe() -> str | None:
    """Return the canonical per-user app path only when it matches this executable."""
    core = _core()
    if not getattr(sys, "frozen", False):
        return None
    target = os.path.realpath(core.stable_app_exe())
    source = os.path.realpath(sys.executable)
    if core._same_path(source, target):
        return None
    try:
        if (
            os.path.isfile(target)
            and core._sha256_file(source) == core._sha256_file(target)
        ):
            return target
    except Exception:
        pass
    return None


def handoff_to_canonical_install() -> bool:
    """Compatibility wrapper for the single canonical handoff mechanism."""
    return _core().handoff_to_stable_copy()


def install_into_core(core: ModuleType) -> ModuleType:
    """Expose canonical portable-lifecycle seams through the core module object."""
    core._sha256_file = _sha256_file
    core._is_historical_documents_copy = _is_historical_documents_copy
    core.ensure_stable_app_copy = ensure_stable_app_copy
    core.self_heal_error = self_heal_error
    core.managed_executable = managed_executable
    core.handoff_to_stable_copy = handoff_to_stable_copy
    core.canonical_install_exe = canonical_install_exe
    core.handoff_to_canonical_install = handoff_to_canonical_install
    return core
