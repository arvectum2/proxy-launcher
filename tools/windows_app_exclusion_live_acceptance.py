# -*- coding: utf-8 -*-
"""Real-Windows acceptance for app exclusions through the production service path."""

from __future__ import annotations

import os
import shutil
import socket
import subprocess
import tempfile
import threading
import time

import proxy_core as core
from application_exclusions import compile_windows_application_exclusion_enforcement_plan
from routing_ownership import RoutingOwnershipStore
from routing_rules import ApplicationIdentity
from windows_routing_controller import (
    NamedPipeWindowsRoutingClient,
    WindowsRoutingController,
)


def _free_port() -> int:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])
    finally:
        sock.close()


class _FakeUpstream:
    def __init__(self) -> None:
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(8)
        self.listener.settimeout(0.5)
        self.port = int(self.listener.getsockname()[1])
        self.stop = threading.Event()
        self.requests = 0
        self.thread = threading.Thread(target=self._run, daemon=True)

    def start(self) -> None:
        self.thread.start()

    def _run(self) -> None:
        while not self.stop.is_set():
            try:
                client, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            try:
                client.settimeout(3)
                data = b""
                while b"\r\n\r\n" not in data and len(data) < 65536:
                    chunk = client.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                self.requests += 1
                client.sendall(
                    b"HTTP/1.1 418 I'm a teapot\r\n"
                    b"Content-Length: 0\r\n"
                    b"Connection: close\r\n"
                    b"X-Arvectum-Acceptance: fake-upstream\r\n\r\n"
                )
            finally:
                try:
                    client.close()
                except OSError:
                    pass

    def close(self) -> None:
        self.stop.set()
        try:
            self.listener.close()
        except OSError:
            pass
        self.thread.join(timeout=2)


def _curl(path: str, proxy_port: int) -> tuple[int, str, str]:
    completed = subprocess.run(
        [
            path,
            "-4",
            "-sS",
            "--max-time",
            "20",
            "--noproxy",
            "",
            "--proxy",
            "http://127.0.0.1:%d" % proxy_port,
            "-o",
            "NUL",
            "-w",
            "%{http_code}",
            "http://example.com/",
        ],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    return completed.returncode, completed.stdout.strip(), completed.stderr.strip()


def main() -> int:
    if os.name != "nt":
        raise RuntimeError("Windows is required")
    selected = os.path.join(os.environ["WINDIR"], "System32", "curl.exe")
    if not os.path.isfile(selected):
        raise RuntimeError("system curl.exe is unavailable")

    work = tempfile.mkdtemp(prefix="apl-app-exclusion-live-")
    unselected = os.path.join(work, "unselected-curl.exe")
    shutil.copy2(selected, unselected)

    upstream = _FakeUpstream()
    upstream.start()
    settings = {
        "local_http_port": _free_port(),
        "local_socks_port": _free_port(),
        "local_pac_port": _free_port(),
        "pac_path": "/proxy.pac",
        "upstream": [
            {
                "host": "127.0.0.1",
                "port": upstream.port,
                "username": "acceptance",
                "password": "acceptance",
            }
        ],
    }
    proxy = core.ProxyCore(settings)
    controller = None
    activated = False
    try:
        ok, message = proxy.start()
        if not ok:
            raise RuntimeError("ProxyCore start failed: %s" % message)
        ok, message, direct_port = proxy.start_direct_listener()
        if not ok or not direct_port:
            raise RuntimeError("direct listener start failed: %s" % message)

        identity = ApplicationIdentity("windows", executable_path=selected)
        plans = compile_windows_application_exclusion_enforcement_plan(
            [identity],
            local_http_port=settings["local_http_port"],
        )
        ownership = RoutingOwnershipStore(os.path.join(work, "routing-ownership.json"))
        controller = WindowsRoutingController(
            ownership, NamedPipeWindowsRoutingClient()
        )
        controller.activate(
            plans,
            proxy_pid=os.getpid(),
            proxy_port=int(direct_port),
        )
        activated = True

        unselected_exit, unselected_http, unselected_err = _curl(
            unselected, settings["local_http_port"]
        )
        selected_exit, selected_http, selected_err = _curl(
            selected, settings["local_http_port"]
        )

        if unselected_exit != 0 or unselected_http != "418":
            raise RuntimeError(
                "unselected path did not use normal APL proxy: exit=%s http=%s stderr=%s"
                % (unselected_exit, unselected_http, unselected_err)
            )
        if selected_exit != 0 or selected_http != "200":
            raise RuntimeError(
                "selected path did not bypass upstream through direct listener: "
                "exit=%s http=%s stderr=%s"
                % (selected_exit, selected_http, selected_err)
            )
        if upstream.requests != 1:
            raise RuntimeError(
                "fake upstream observed %d requests, expected exactly one"
                % upstream.requests
            )

        if not controller.restore():
            raise RuntimeError("controller restore was not verified")
        activated = False
        if ownership.exists():
            raise RuntimeError("routing ownership journal survived verified restore")

        print("ARVECTUM_WINDOWS_APP_EXCLUSION_LIVE_PASS")
        print("unselected_http=%s" % unselected_http)
        print("selected_http=%s" % selected_http)
        print("fake_upstream_requests=%d" % upstream.requests)
        print("main_proxy_port=%d" % settings["local_http_port"])
        print("direct_listener_port=%d" % int(direct_port))
        return 0
    finally:
        if activated and controller is not None:
            try:
                controller.restore()
            except Exception:
                pass
        proxy.stop()
        upstream.close()
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
