"""Canonical local proxy transport for Arvectum Proxy Launcher.

Owns the platform-neutral local enforcement plane: upstream preparation and failover, HTTP/CONNECT proxying, SOCKS5 tunnelling, PAC serving, relay loops and listener lifecycle. Process supervision, application orchestration and system-proxy mutation remain separate owners.
"""

from __future__ import annotations

import base64
import re
import select
import socket
import struct
import threading
import time
from types import ModuleType


# SOCKS5 reply BND.ADDR field per RFC 1928. ``0.0.0.0`` is serialized protocol
# data here, not a socket bind to all interfaces; Bandit B104 does not apply.
SOCKS5_REPLY_BIND_ADDR = socket.inet_aton("0.0.0.0")  # nosec B104

_CORE: ModuleType | None = None


def configure(core: ModuleType) -> None:
    """Bind the canonical composition module used for runtime collaborators."""
    global _CORE
    _CORE = core


def _core() -> ModuleType:
    if _CORE is None:
        raise RuntimeError("local proxy transport is not configured")
    return _CORE


class ProxyCore:
    """Local HTTP/SOCKS/PAC transport preserving the 0.2.3 wire contract."""

    def __init__(self, settings=None):
        core = _core()
        self.settings = settings if settings is not None else core.load_settings()
        self._stop = threading.Event()
        self._socks = []
        self._threads = []
        self._upstreams = self._build_upstreams()

    def _build_upstreams(self):
        out = []
        for up in self.settings.get("upstream") or []:
            host = (up.get("host") or "").strip()
            if not host:
                continue
            raw = ("%s:%s" % (up.get("username") or "", up.get("password") or "")).encode("utf-8")
            token = base64.b64encode(raw).decode("ascii")
            try:
                port = int(up.get("port", 8000))
            except (TypeError, ValueError):
                port = 8000
            out.append((host, port, token))
        return out

    @staticmethod
    def _read_proxy_response(stream):
        response = b""
        marker = b"\r\n\r\n"
        limit = 65536
        while marker not in response:
            if len(response) >= limit:
                raise OSError("upstream proxy response headers are too large")
            chunk = stream.recv(min(4096, limit - len(response)))
            if not chunk:
                raise OSError("upstream proxy closed before CONNECT response")
            response += chunk
        status_line = response.split(b"\r\n", 1)[0].split()
        if len(status_line) < 2:
            raise OSError("invalid upstream proxy response")
        try:
            status = int(status_line[1])
        except (TypeError, ValueError):
            raise OSError("invalid upstream proxy status")
        return status, response

    @staticmethod
    def _connect_request_with_auth(host, port, token, client_request=None):
        target = ("%s:%d" % (host, port)).encode("idna")
        if client_request is None:
            return (
                b"CONNECT " + target + b" HTTP/1.1\r\n"
                b"Host: " + target + b"\r\n"
                b"Proxy-Authorization: Basic " + token.encode("ascii")
                + b"\r\n\r\n"
            )

        headers = client_request.split(b"\r\n\r\n", 1)[0].split(b"\r\n")
        if not headers or not headers[0].startswith(b"CONNECT "):
            raise OSError("invalid client CONNECT request")
        preserved = [
            line for line in headers[1:]
            if line and not line.lower().startswith(b"proxy-authorization:")
        ]
        return b"\r\n".join(
            [headers[0], b"Proxy-Authorization: Basic " + token.encode("ascii")]
            + preserved
        ) + b"\r\n\r\n"

    def _open_upstream_tunnel(self, host, port, client_request=None):
        core = _core()
        for host_u, proxy_port, token in self._upstreams:
            stream = None
            started = time.monotonic()
            try:
                stream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                stream.settimeout(15)
                stream.connect((host_u, proxy_port))
                request = self._connect_request_with_auth(
                    host, port, token, client_request=client_request
                )
                stream.sendall(request)
                status, response = self._read_proxy_response(stream)
                elapsed_ms = int((time.monotonic() - started) * 1000)
                core.structured_log(
                    "upstream CONNECT response received",
                    event="proxy.connect.upstream_response",
                    proxy_host=host_u,
                    proxy_port=proxy_port,
                    target_port=port,
                    status=status,
                    header_bytes=len(response),
                    elapsed_ms=elapsed_ms,
                )
                if 200 <= status < 300:
                    stream.settimeout(300)
                    return stream, response
            except Exception as exc:
                core.structured_log(
                    "upstream CONNECT attempt failed",
                    level="WARNING",
                    event="proxy.connect.upstream_error",
                    proxy_host=host_u,
                    proxy_port=proxy_port,
                    target_port=port,
                    error_type=type(exc).__name__,
                    elapsed_ms=int((time.monotonic() - started) * 1000),
                )
            if stream is not None:
                try:
                    stream.close()
                except Exception:
                    pass
        return None, b""

    @staticmethod
    def _read_client_request(client):
        data = b""
        marker = b"\r\n\r\n"
        limit = 65536
        while marker not in data:
            if len(data) >= limit:
                raise OSError("client proxy request headers are too large")
            chunk = client.recv(min(8192, limit - len(data)))
            if not chunk:
                raise OSError("client proxy closed before request headers completed")
            data += chunk
        return data

    @staticmethod
    def _send_error(client, code, text):
        reason = {400: "Bad Request", 502: "Bad Gateway"}.get(code, "Error")
        body = (text or reason).encode("utf-8")
        try:
            client.sendall(
                b"HTTP/1.1 %d %s\r\nContent-Type: text/plain; charset=utf-8\r\n"
                b"Content-Length: %d\r\nConnection: close\r\n\r\n%s"
                % (code, reason.encode("ascii"), len(body), body)
            )
        except Exception:
            pass

    @staticmethod
    def _relay(src, dst, stop):
        core = _core()
        src_to_dst = 0
        dst_to_src = 0
        reason = "stop_requested"
        started = time.monotonic()
        try:
            while not stop.is_set():
                try:
                    ready, _, _ = select.select([src, dst], [], [], 300)
                except (OSError, ValueError) as exc:
                    reason = "select_error:%s" % type(exc).__name__
                    return
                if not ready:
                    # Match the proven legacy transport: retire fully idle
                    # tunnels so browsers cannot keep reusing a stale CONNECT.
                    reason = "idle_timeout"
                    break
                for stream in ready:
                    side = "upstream" if stream is src else "client"
                    try:
                        data = stream.recv(65536)
                    except OSError as exc:
                        reason = "recv_error:%s:%s" % (side, type(exc).__name__)
                        return
                    if not data:
                        reason = "eof:%s" % side
                        return
                    target = dst if stream is src else src
                    try:
                        target.sendall(data)
                    except OSError as exc:
                        reason = "send_error:%s:%s" % (
                            "client" if stream is src else "upstream",
                            type(exc).__name__,
                        )
                        return
                    if stream is src:
                        src_to_dst += len(data)
                    else:
                        dst_to_src += len(data)
        except Exception as exc:
            reason = "relay_error:%s" % type(exc).__name__
        finally:
            core.structured_log(
                "proxy relay closed",
                event="proxy.relay.closed",
                upstream_to_client_bytes=src_to_dst,
                client_to_upstream_bytes=dst_to_src,
                elapsed_ms=int((time.monotonic() - started) * 1000),
                termination_reason=reason,
            )
            for stream in (src, dst):
                try:
                    stream.close()
                except Exception:
                    pass

    def _handle_http(self, client):
        core = _core()
        try:
            client.settimeout(30)
            data = self._read_client_request(client)
            marker = b"\r\n\r\n"
            header_end = data.index(marker) + len(marker)
            request_headers = data[:header_end]
            buffered_after_headers = data[header_end:]
            first = request_headers.split(b"\r\n", 1)[0]
            is_connect = first.startswith(b"CONNECT")

            if is_connect:
                try:
                    dest = first.split(b" ")[1].decode()
                    host, port_s = dest.rsplit(":", 1)
                    port = int(port_s)
                except Exception:
                    self._send_error(client, 400, "Bad CONNECT")
                    return
                method = None
                path = None
            else:
                parts = first.split(b" ")
                if len(parts) < 2:
                    self._send_error(client, 400, "Bad request")
                    return
                method = parts[0]
                url = parts[1].decode()
                if url.startswith("http://"):
                    url = url[7:]
                elif url.startswith("https://"):
                    url = url[8:]
                slash = url.find("/")
                hostport = url if slash == -1 else url[:slash]
                path = "/" if slash == -1 else url[slash:]
                if ":" in hostport:
                    host, port_s = hostport.rsplit(":", 1)
                    try:
                        port = int(port_s)
                    except ValueError:
                        port = 80
                else:
                    host = hostport
                    port = 80

            host = core._normalize_host(host)
            if core.host_bypasses_proxy(host):
                try:
                    direct = socket.create_connection((host, port), timeout=15)
                except Exception:
                    self._send_error(client, 502, "Localhost connection failed")
                    return
                direct.settimeout(300)
                if is_connect:
                    client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                    if buffered_after_headers:
                        direct.sendall(buffered_after_headers)
                else:
                    rest = data.split(b"\r\n", 1)[1]
                    data = method + b" " + path.encode() + b" HTTP/1.1\r\n" + rest
                    direct.sendall(data)
                self._relay(direct, client, self._stop)
            else:
                if is_connect:
                    upstream, response = self._open_upstream_tunnel(
                        host, port, client_request=request_headers
                    )
                    if upstream is None:
                        self._send_error(client, 502, "All external proxies unreachable")
                        return
                    client.sendall(response)
                    core.structured_log(
                        "CONNECT response forwarded to client",
                        event="proxy.connect.client_ready",
                        target_port=port,
                        response_bytes=len(response),
                        buffered_client_bytes=len(buffered_after_headers),
                    )
                    if buffered_after_headers:
                        upstream.sendall(buffered_after_headers)
                    self._relay(upstream, client, self._stop)
                else:
                    upstream = None
                    for host_u, proxy_port, token in self._upstreams:
                        stream = None
                        try:
                            stream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                            stream.settimeout(15)
                            stream.connect((host_u, proxy_port))
                            header = (
                                b"Proxy-Authorization: Basic "
                                + token.encode("ascii")
                                + b"\r\n"
                            )
                            request = data.replace(b"\r\n", b"\r\n" + header, 1)
                            stream.sendall(request)
                            upstream = stream
                            break
                        except Exception:
                            if stream is not None:
                                try:
                                    stream.close()
                                except Exception:
                                    pass
                            continue
                    if upstream is None:
                        self._send_error(client, 502, "All external proxies unreachable")
                        return
                    self._relay(upstream, client, self._stop)
        except OSError:
            try:
                self._send_error(client, 502, "Proxy error")
            except Exception:
                pass
        finally:
            try:
                client.close()
            except Exception:
                pass

    def _handle_socks(self, client):
        core = _core()
        try:
            client.settimeout(15)
            if client.recv(1) != b"\x05":
                return
            nmethods = client.recv(1)[0]
            client.recv(nmethods)
            client.sendall(b"\x05\x00")
            data = client.recv(4)
            if len(data) < 4 or data[0] != 5:
                return
            atype = data[3]
            if atype == 1:
                host = socket.inet_ntoa(client.recv(4))
            elif atype == 3:
                length = client.recv(1)[0]
                host = client.recv(length).decode()
            elif atype == 4:
                host = socket.inet_ntop(socket.AF_INET6, client.recv(16))
            else:
                return
            port = struct.unpack(">H", client.recv(2))[0]

            upstream = None
            host = core._normalize_host(host)
            if core.host_bypasses_proxy(host):
                try:
                    upstream = socket.create_connection((host, port), timeout=15)
                except Exception:
                    upstream = None
            else:
                upstream, _response = self._open_upstream_tunnel(host, port)

            bind_addr = core._SOCKS5_REPLY_BIND_ADDR
            if upstream is None:
                client.sendall(b"\x05\x03\x00\x01" + bind_addr + struct.pack(">H", 0))
                return
            client.sendall(b"\x05\x00\x00\x01" + bind_addr + struct.pack(">H", 0))
            self._relay(upstream, client, self._stop)
        except Exception:
            pass
        finally:
            try:
                client.close()
            except Exception:
                pass

    def _handle_pac(self, client):
        core = _core()
        try:
            data = client.recv(4096)
            if not data:
                return
            match = re.search(rb"GET\s+(\S+)\s+HTTP", data)
            if not match:
                client.close()
                return
            path = match.group(1).decode()
            if path != self.settings.get("pac_path", "/proxy.pac"):
                response = b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            else:
                pac = core.build_pac().encode("utf-8")
                response = (
                    b"HTTP/1.1 200 OK\r\n"
                    b"Content-Type: application/x-ns-proxy-autoconfig\r\n"
                    b"Cache-Control: no-cache\r\n"
                    b"Content-Length: " + str(len(pac)).encode() + b"\r\n"
                    b"Connection: close\r\n\r\n" + pac
                )
            client.sendall(response)
        except Exception:
            pass
        finally:
            try:
                client.close()
            except Exception:
                pass

    def start(self):
        core = _core()
        if self._socks:
            return False, "Уже запущено"
        ports = (
            ("HTTP", int(self.settings.get("local_http_port", 8080)), self._handle_http),
            ("SOCKS5", int(self.settings.get("local_socks_port", 1080)), self._handle_socks),
            ("PAC", int(self.settings.get("local_pac_port", 8082)), self._handle_pac),
        )
        bound = []
        try:
            for _name, port, _handler in ports:
                listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                listener.bind(("127.0.0.1", port))
                listener.listen(200)
                listener.settimeout(1.0)
                bound.append(listener)
        except OSError as error:
            for listener in bound:
                try:
                    listener.close()
                except Exception:
                    pass
            return False, "Не удалось занять порт: %s" % error
        self._socks = bound
        self._stop = threading.Event()
        for listener, (_name, _port, handler) in zip(bound, ports):
            thread = threading.Thread(
                target=self._accept_loop,
                args=(listener, handler),
                daemon=True,
            )
            thread.start()
            self._threads.append(thread)
        core._log(
            "proxy started (http=%d socks=%d pac=%d, upstreams=%d)"
            % (ports[0][1], ports[1][1], ports[2][1], len(self._upstreams))
        )
        return True, "OK"

    def _accept_loop(self, listener, handler):
        while not self._stop.is_set():
            try:
                client, _ = listener.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            if self._stop.is_set():
                try:
                    client.close()
                except Exception:
                    pass
                break
            threading.Thread(target=handler, args=(client,), daemon=True).start()

    def stop(self):
        core = _core()
        self._stop.set()
        for listener in self._socks:
            try:
                listener.shutdown(socket.SHUT_RDWR)
            except Exception:
                pass
            try:
                listener.close()
            except Exception:
                pass
        self._socks = []
        core._log("proxy stopped")
        return True


def install_into_core(core: ModuleType) -> ModuleType:
    """Expose canonical transport ownership through the compatibility seam."""
    core._SOCKS5_REPLY_BIND_ADDR = SOCKS5_REPLY_BIND_ADDR
    core.ProxyCore = ProxyCore
    return core
