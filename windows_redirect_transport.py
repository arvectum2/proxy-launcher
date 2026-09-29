# -*- coding: utf-8 -*-
"""Windows WFP transparent redirect socket helpers.

The kernel callout stores the original destination in localRedirectContext.
The accepted proxy socket exposes that context plus redirect records through
Windows-specific WSAIoctl controls. Redirect records must be attached to the
outbound proxy socket before connect so the WFP redirect chain remains intact.
"""
from __future__ import annotations

from dataclasses import dataclass
import ctypes
import socket
import struct
import sys
from typing import Callable, Optional, Tuple

SIO_QUERY_WFP_CONNECTION_REDIRECT_RECORDS = 0x980000DC
SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT = 0x980000DD
SIO_SET_WFP_CONNECTION_REDIRECT_RECORDS = 0x980000DE
REDIRECT_RECORDS_MAX = 8192
SOCKADDR_STORAGE_SIZE = 128
REDIRECT_CONTEXT_V1_SIZE = 8 + (SOCKADDR_STORAGE_SIZE * 2)
REDIRECT_CONTEXT_SIZE = (
    REDIRECT_CONTEXT_V1_SIZE + 8 + SOCKADDR_STORAGE_SIZE
)
CONTEXT_MAGIC = 0x52565041
CONTEXT_VERSION_V1 = 1
CONTEXT_VERSION = 2
CONTEXT_HAS_METADATA_ORIGINAL = 0x00000001


class WindowsRedirectTransportError(RuntimeError):
    pass


@dataclass(frozen=True)
class RedirectMetadata:
    original_remote: Tuple[str, int]
    original_local: Tuple[str, int]
    redirect_records: bytes


def parse_sockaddr_storage(data: bytes) -> Tuple[str, int]:
    raw = bytes(data)
    if len(raw) < SOCKADDR_STORAGE_SIZE:
        raise WindowsRedirectTransportError("short SOCKADDR_STORAGE")
    family = int.from_bytes(raw[0:2], "little")
    port = int.from_bytes(raw[2:4], "big")
    if family == socket.AF_INET:
        host = socket.inet_ntop(socket.AF_INET, raw[4:8])
    elif family == socket.AF_INET6:
        host = socket.inet_ntop(socket.AF_INET6, raw[8:24])
    else:
        raise WindowsRedirectTransportError(
            "unsupported redirected address family: %d" % family
        )
    if not host or port <= 0 or port > 65535:
        raise WindowsRedirectTransportError("invalid redirected endpoint")
    return host, port
def parse_redirect_context(data: bytes) -> Tuple[Tuple[str, int], Tuple[str, int]]:
    raw = bytes(data)
    if len(raw) not in (REDIRECT_CONTEXT_V1_SIZE, REDIRECT_CONTEXT_SIZE):
        raise WindowsRedirectTransportError("unexpected redirect context size")
    magic, version = struct.unpack_from("<II", raw, 0)
    if magic != CONTEXT_MAGIC or version not in (CONTEXT_VERSION_V1, CONTEXT_VERSION):
        raise WindowsRedirectTransportError("redirect context owner/version mismatch")
    if version == CONTEXT_VERSION_V1 and len(raw) != REDIRECT_CONTEXT_V1_SIZE:
        raise WindowsRedirectTransportError("redirect context version/size mismatch")
    if version == CONTEXT_VERSION and len(raw) != REDIRECT_CONTEXT_SIZE:
        raise WindowsRedirectTransportError("redirect context version/size mismatch")
    remote_start = 8
    local_start = remote_start + SOCKADDR_STORAGE_SIZE
    remote = parse_sockaddr_storage(
        raw[remote_start:remote_start + SOCKADDR_STORAGE_SIZE]
    )
    local = parse_sockaddr_storage(
        raw[local_start:local_start + SOCKADDR_STORAGE_SIZE]
    )
    if version == CONTEXT_VERSION:
        flags_start = local_start + SOCKADDR_STORAGE_SIZE
        flags, _reserved = struct.unpack_from("<II", raw, flags_start)
        metadata_start = flags_start + 8
        if flags & CONTEXT_HAS_METADATA_ORIGINAL:
            remote = parse_sockaddr_storage(
                raw[metadata_start:metadata_start + SOCKADDR_STORAGE_SIZE]
            )
    return remote, local


def _winsock_ioctl(
    sock: socket.socket,
    code: int,
    *,
    input_bytes: bytes = b"",
    output_size: int = 0,
) -> bytes:
    if not sys.platform.lower().startswith("win"):
        raise WindowsRedirectTransportError("WFP redirect metadata requires Windows")
    try:
        ws2_32 = ctypes.WinDLL("Ws2_32.dll", use_last_error=True)
    except Exception as exc:
        raise WindowsRedirectTransportError("Ws2_32.dll is unavailable") from exc

    wsa_ioctl = ws2_32.WSAIoctl
    wsa_ioctl.argtypes = [
        ctypes.c_size_t,
        ctypes.c_ulong,
        ctypes.c_void_p,
        ctypes.c_ulong,
        ctypes.c_void_p,
        ctypes.c_ulong,
        ctypes.POINTER(ctypes.c_ulong),
        ctypes.c_void_p,
        ctypes.c_void_p,
    ]
    wsa_ioctl.restype = ctypes.c_int

    in_buffer = None
    in_pointer = None
    if input_bytes:
        in_buffer = ctypes.create_string_buffer(bytes(input_bytes))
        in_pointer = ctypes.cast(in_buffer, ctypes.c_void_p)

    out_buffer = None
    out_pointer = None
    if output_size:
        out_buffer = ctypes.create_string_buffer(int(output_size))
        out_pointer = ctypes.cast(out_buffer, ctypes.c_void_p)

    returned = ctypes.c_ulong(0)
    result = int(wsa_ioctl(
        ctypes.c_size_t(sock.fileno()),
        ctypes.c_ulong(int(code)),
        in_pointer,
        ctypes.c_ulong(len(input_bytes)),
        out_pointer,
        ctypes.c_ulong(int(output_size)),
        ctypes.byref(returned),
        None,
        None,
    ))
    if result != 0:
        error = int(ws2_32.WSAGetLastError())
        raise WindowsRedirectTransportError(
            "WSAIoctl 0x%08X failed: %d" % (int(code), error)
        )
    if not out_buffer:
        return b""
    if returned.value > output_size:
        raise WindowsRedirectTransportError("WSAIoctl returned oversized payload")
    return bytes(out_buffer.raw[: returned.value])


def query_redirect_metadata(
    client: socket.socket,
    *,
    ioctl: Callable[..., bytes] = _winsock_ioctl,
) -> RedirectMetadata:
    records = bytes(ioctl(
        client,
        SIO_QUERY_WFP_CONNECTION_REDIRECT_RECORDS,
        output_size=REDIRECT_RECORDS_MAX,
    ))
    if not records:
        raise WindowsRedirectTransportError("redirect records are empty")
    context = bytes(ioctl(
        client,
        SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT,
        output_size=REDIRECT_CONTEXT_SIZE,
    ))
    remote, local = parse_redirect_context(context)
    return RedirectMetadata(remote, local, records)


def attach_redirect_records(
    outbound: socket.socket,
    records: bytes,
    *,
    ioctl: Callable[..., bytes] = _winsock_ioctl,
) -> None:
    payload = bytes(records)
    if not payload or len(payload) > REDIRECT_RECORDS_MAX:
        raise WindowsRedirectTransportError("invalid redirect record payload")
    ioctl(
        outbound,
        SIO_SET_WFP_CONNECTION_REDIRECT_RECORDS,
        input_bytes=payload,
        output_size=0,
    )


def prepare_outbound_socket(
    metadata: RedirectMetadata,
    *,
    ioctl: Callable[..., bytes] = _winsock_ioctl,
) -> Callable[[socket.socket], None]:
    def _prepare(outbound: socket.socket) -> None:
        attach_redirect_records(outbound, metadata.redirect_records, ioctl=ioctl)
    return _prepare
