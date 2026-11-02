"""Tiny HTTP helpers; the gateway intentionally has no web-framework dependency."""

import json


def response(status: int, payload: dict | list) -> bytes:
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    reason = {200: "OK", 201: "Created", 400: "Bad Request", 401: "Unauthorized",
              404: "Not Found", 405: "Method Not Allowed", 502: "Bad Gateway"}.get(status, "Error")
    return (
        f"HTTP/1.1 {status} {reason}\r\n"
        f"Content-Type: application/json; charset=utf-8\r\n"
        f"Content-Length: {len(body)}\r\n"
        "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
    ).encode("ascii") + body


async def read_request(reader, max_header=16384):
    data = await reader.readuntil(b"\r\n\r\n")
    if len(data) > max_header:
        raise ValueError("request headers too large")
    head = data.decode("iso-8859-1")
    lines = head.split("\r\n")
    method, target, version = lines[0].split(" ", 2)
    headers = {}
    for line in lines[1:]:
        if not line:
            continue
        name, value = line.split(":", 1)
        headers[name.lower().strip()] = value.strip()
    length = int(headers.get("content-length", "0"))
    body = await reader.readexactly(length) if length else b""
    return method, target, version, headers, body
