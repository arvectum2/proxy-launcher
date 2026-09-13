#!/usr/bin/env python3
"""Mirror a verified release payload to GitVerse.

The script deliberately uses GitVerse MCP for release metadata creation/update and
Public API for release assets. This avoids depending on GitHub for the final hosted
copy: after a successful run the GitVerse release owns its own asset copies.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import http.client
import json
import os
from pathlib import Path
import sys
import urllib.parse
import uuid

API_HOST = "api.gitverse.ru"
MCP_HOST = "mcp.gitverse.ru"
ACCEPT = "application/vnd.gitverse.object+json;version=1"


def fail(message: str) -> "NoReturn":
    raise RuntimeError(message)


def http_request(
    host: str,
    method: str,
    path: str,
    *,
    headers: dict[str, str] | None = None,
    body: bytes | None = None,
    timeout: int = 60,
) -> tuple[int, dict[str, str], bytes]:
    conn = http.client.HTTPSConnection(host, timeout=timeout)
    hdrs = dict(headers or {})
    if body is not None:
        hdrs.setdefault("Content-Length", str(len(body)))
    conn.request(method, path, body=body, headers=hdrs)
    response = conn.getresponse()
    data = response.read()
    response_headers = {k.lower(): v for k, v in response.getheaders()}
    status = response.status
    conn.close()
    return status, response_headers, data


def parse_json_bytes(data: bytes, context: str) -> object:
    try:
        return json.loads(data.decode("utf-8"))
    except Exception as exc:  # pragma: no cover - diagnostic path
        fail(f"{context}: invalid JSON response: {data[:1000]!r}; {exc}")


def parse_mcp_response(data: bytes, context: str) -> dict:
    text = data.decode("utf-8", errors="replace").strip()
    if text.startswith("{"):
        value = json.loads(text)
        if not isinstance(value, dict):
            fail(f"{context}: MCP response is not an object")
        return value

    # Streamable HTTP implementations may answer as SSE.
    for line in text.splitlines():
        if line.startswith("data:"):
            value = json.loads(line[5:].strip())
            if isinstance(value, dict):
                return value
    fail(f"{context}: unsupported MCP response: {text[:1000]!r}")


class GitVerseClient:
    def __init__(self, token: str, owner: str, repo: str) -> None:
        self.token = token
        self.owner = owner
        self.repo = repo
        self.session_id: str | None = None
        self.tools: dict[str, dict] = {}

    @property
    def api_headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.token}",
            "Accept": ACCEPT,
        }

    def api_get(self, path: str) -> tuple[int, object | None, bytes]:
        status, _, data = http_request(
            API_HOST, "GET", path, headers=self.api_headers
        )
        if not data:
            return status, None, data
        try:
            value = parse_json_bytes(data, f"GET {path}")
        except RuntimeError:
            return status, None, data
        return status, value, data

    def initialize_mcp(self) -> None:
        payload = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {
                    "name": "arvectum-gitverse-release-sync",
                    "version": "1.0",
                },
            },
        }
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        status, headers, data = http_request(
            MCP_HOST,
            "POST",
            "/",
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/json, text/event-stream",
                "Content-Type": "application/json",
            },
            body=body,
        )
        if status != 200:
            fail(f"MCP initialize failed HTTP {status}: {data[:1000]!r}")
        parsed = parse_mcp_response(data, "MCP initialize")
        if "error" in parsed:
            fail(f"MCP initialize error: {parsed['error']}")
        self.session_id = headers.get("mcp-session-id")
        if not self.session_id:
            fail("MCP initialize did not return Mcp-Session-Id")

        self._mcp_send(
            {
                "jsonrpc": "2.0",
                "method": "notifications/initialized",
                "params": {},
            },
            expect_response=False,
        )
        tools_response = self._mcp_send(
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
        )
        result = tools_response.get("result", {})
        tools = result.get("tools", []) if isinstance(result, dict) else []
        self.tools = {
            str(tool.get("name")): tool
            for tool in tools
            if isinstance(tool, dict) and tool.get("name")
        }
        for required in ("create_release", "update_release"):
            if required not in self.tools:
                fail(
                    f"GitVerse MCP tool {required!r} is unavailable; "
                    f"available={sorted(self.tools)}"
                )
        print("PASS GitVerse MCP release tools discovered")

    def _mcp_send(self, payload: dict, *, expect_response: bool = True) -> dict:
        if not self.session_id:
            fail("MCP session is not initialized")
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        status, _, data = http_request(
            MCP_HOST,
            "POST",
            "/",
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/json, text/event-stream",
                "Content-Type": "application/json",
                "Mcp-Session-Id": self.session_id,
            },
            body=body,
        )
        if not expect_response and status in (200, 202, 204):
            return {}
        if status != 200:
            fail(f"MCP request failed HTTP {status}: {data[:1000]!r}")
        parsed = parse_mcp_response(data, "MCP request")
        if "error" in parsed:
            fail(f"MCP JSON-RPC error: {parsed['error']}")
        return parsed

    def _tool_args(
        self,
        tool_name: str,
        *,
        tag: str,
        title: str,
        body: str,
        release_id: int | None = None,
    ) -> dict:
        tool = self.tools[tool_name]
        schema = tool.get("inputSchema") or tool.get("input_schema") or {}
        if not isinstance(schema, dict):
            fail(f"MCP {tool_name} input schema is invalid: {schema!r}")
        props = schema.get("properties") or {}
        required = set(schema.get("required") or [])
        if not isinstance(props, dict):
            fail(f"MCP {tool_name} properties are invalid")

        values = {
            "owner": self.owner,
            "owner_name": self.owner,
            "organization": self.owner,
            "namespace": self.owner,
            "repo": self.repo,
            "repo_name": self.repo,
            "repository_name": self.repo,
            "repository": f"{self.owner}/{self.repo}",
            "tag": tag,
            "tag_name": tag,
            "name": title,
            "title": title,
            "body": body,
            "description": body,
            "notes": body,
            "target_commitish": "main",
            "target": "main",
            "draft": False,
            "prerelease": False,
            "pre_release": False,
            "is_authorized_only": False,
            "authorized_only": False,
        }
        if release_id is not None:
            values["release_id"] = release_id
            values["id"] = release_id

        args = {key: values[key] for key in props if key in values}
        missing = sorted(key for key in required if key not in args)
        if missing:
            safe_schema = json.dumps(schema, ensure_ascii=False, sort_keys=True)
            fail(
                f"Unsupported required MCP fields for {tool_name}: {missing}; "
                f"schema={safe_schema}"
            )
        return args

    def call_release_tool(
        self,
        tool_name: str,
        *,
        tag: str,
        title: str,
        body: str,
        release_id: int | None = None,
    ) -> None:
        args = self._tool_args(
            tool_name,
            tag=tag,
            title=title,
            body=body,
            release_id=release_id,
        )
        response = self._mcp_send(
            {
                "jsonrpc": "2.0",
                "id": 100 if tool_name == "create_release" else 101,
                "method": "tools/call",
                "params": {"name": tool_name, "arguments": args},
            }
        )
        result = response.get("result", {})
        if isinstance(result, dict) and result.get("isError"):
            fail(f"GitVerse MCP {tool_name} failed: {result}")
        print(f"PASS GitVerse MCP {tool_name}")

    def release_by_tag(self, tag: str) -> tuple[int, dict | None]:
        encoded = urllib.parse.quote(tag, safe="")
        status, value, raw = self.api_get(
            f"/repos/{self.owner}/{self.repo}/releases/tags/{encoded}"
        )
        if status == 404:
            return status, None
        if status != 200 or not isinstance(value, dict):
            fail(f"GitVerse release lookup failed HTTP {status}: {raw[:1000]!r}")
        return status, value

    def list_assets(self, release_id: int) -> list[dict]:
        status, value, raw = self.api_get(
            f"/repos/{self.owner}/{self.repo}/releases/{release_id}/assets?per_page=50&page=1"
        )
        if status != 200 or not isinstance(value, list):
            fail(f"GitVerse asset list failed HTTP {status}: {raw[:1000]!r}")
        return [item for item in value if isinstance(item, dict)]

    def upload_asset(self, release_id: int, name: str, file_path: Path) -> None:
        boundary = f"----Arvectum{uuid.uuid4().hex}"
        file_bytes = file_path.read_bytes()
        prefix = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="attachment"; filename="{name}"\r\n'
            "Content-Type: application/octet-stream\r\n\r\n"
        ).encode("utf-8")
        suffix = f"\r\n--{boundary}--\r\n".encode("utf-8")
        body = prefix + file_bytes + suffix
        encoded_name = urllib.parse.quote(name, safe="")
        path = (
            f"/repos/{self.owner}/{self.repo}/releases/{release_id}/assets"
            f"?name={encoded_name}"
        )
        headers = dict(self.api_headers)
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
        status, _, data = http_request(
            API_HOST, "POST", path, headers=headers, body=body, timeout=180
        )
        if status != 201:
            fail(f"GitVerse asset upload failed for {name} HTTP {status}: {data[:1000]!r}")
        print(f"UPLOADED GitVerse asset: {name}")

    def download_url(self, url: str) -> bytes:
        current = url
        for _ in range(6):
            parsed = urllib.parse.urlsplit(current)
            if parsed.scheme != "https" or not parsed.hostname:
                fail(f"Unsafe asset download URL: {current}")
            path = parsed.path + (f"?{parsed.query}" if parsed.query else "")
            headers: dict[str, str] = {}
            if parsed.hostname == API_HOST:
                headers = self.api_headers
            status, response_headers, data = http_request(
                parsed.hostname, "GET", path, headers=headers, timeout=180
            )
            if status in (301, 302, 303, 307, 308):
                location = response_headers.get("location")
                if not location:
                    fail(f"Asset redirect without Location: {current}")
                current = urllib.parse.urljoin(current, location)
                continue
            if status != 200:
                fail(f"Asset download failed HTTP {status}: {current}")
            return data
        fail(f"Too many redirects downloading {url}")

    def verify_readme(self, local_readme: Path) -> None:
        status, value, raw = self.api_get(
            f"/repos/{self.owner}/{self.repo}/contents/README.md?ref=main"
        )
        if status != 200 or not isinstance(value, dict):
            fail(f"GitVerse README lookup failed HTTP {status}: {raw[:1000]!r}")
        content = value.get("content")
        if not isinstance(content, str):
            fail("GitVerse README response has no base64 content")
        remote = base64.b64decode(content)
        local = local_readme.read_bytes()
        if hashlib.sha256(remote).digest() != hashlib.sha256(local).digest():
            fail("GitVerse README does not match GitHub main checkout")
        print(f"PASS GitVerse README SHA-256: {hashlib.sha256(local).hexdigest()}")


def load_manifest(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        digest, name = line.split(maxsplit=1)
        if name in result:
            fail(f"Duplicate manifest entry: {name}")
        result[name] = digest.lower()
    if not result:
        fail("Release manifest is empty")
    return result


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--owner", default="arvectum")
    parser.add_argument("--repo", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--notes", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--assets-dir", type=Path, required=True)
    parser.add_argument("--readme", type=Path, default=Path("README.md"))
    args = parser.parse_args()

    token = os.environ.get("GITVERSE_TOKEN", "")
    if not token:
        fail("GITVERSE_TOKEN is missing")

    notes = args.notes.read_text(encoding="utf-8")
    manifest = load_manifest(args.manifest)
    if len(manifest) != 9:
        fail(f"Expected exactly 9 release assets; manifest has {len(manifest)}")

    for name, expected in manifest.items():
        local = args.assets_dir / name
        if not local.is_file():
            fail(f"Missing local release asset: {local}")
        actual = hashlib.sha256(local.read_bytes()).hexdigest()
        if actual != expected:
            fail(f"Local asset hash mismatch for {name}: {actual} != {expected}")
    print("PASS local release payload: exact 9/9 hashes")

    client = GitVerseClient(token, args.owner, args.repo)

    repo_status, _, repo_raw = client.api_get(f"/repos/{args.owner}/{args.repo}")
    if repo_status != 200:
        fail(f"GitVerse repository lookup failed HTTP {repo_status}: {repo_raw[:1000]!r}")
    print(f"PASS GitVerse repository API access: {args.owner}/{args.repo}")

    _, release = client.release_by_tag(args.tag)
    client.initialize_mcp()
    if release is None:
        client.call_release_tool(
            "create_release", tag=args.tag, title=args.title, body=notes
        )
        _, release = client.release_by_tag(args.tag)
        if release is None:
            fail("GitVerse MCP reported release creation but release is still absent")
    else:
        print(f"Found existing GitVerse release id={release.get('id')}")

    release_id_raw = release.get("id")
    if not isinstance(release_id_raw, int):
        fail(f"GitVerse release has invalid id: {release_id_raw!r}")
    release_id = release_id_raw

    client.call_release_tool(
        "update_release",
        tag=args.tag,
        title=args.title,
        body=notes,
        release_id=release_id,
    )
    _, release = client.release_by_tag(args.tag)
    if release is None:
        fail("GitVerse release disappeared after metadata update")
    if release.get("tag_name") != args.tag:
        fail(f"GitVerse release tag mismatch: {release.get('tag_name')!r}")
    if release.get("name") != args.title:
        fail(f"GitVerse release title mismatch: {release.get('name')!r}")
    if release.get("body") != notes:
        fail("GitVerse release notes do not match canonical notes file")
    if bool(release.get("draft")) or bool(release.get("prerelease")):
        fail("GitVerse release unexpectedly marked draft/prerelease")
    print(f"PASS GitVerse release metadata id={release_id}")

    existing = client.list_assets(release_id)
    by_name: dict[str, list[dict]] = {}
    for asset in existing:
        name = asset.get("name")
        if isinstance(name, str):
            by_name.setdefault(name, []).append(asset)

    unexpected = sorted(set(by_name) - set(manifest))
    if unexpected:
        fail(f"Unexpected GitVerse release assets already exist: {unexpected}")

    for name, expected in manifest.items():
        items = by_name.get(name, [])
        if len(items) > 1:
            fail(f"Duplicate GitVerse release asset: {name}")
        if len(items) == 1:
            url = items[0].get("browser_download_url")
            if not isinstance(url, str):
                fail(f"Existing GitVerse asset has no download URL: {name}")
            actual = sha256_bytes(client.download_url(url))
            if actual != expected:
                fail(f"Existing GitVerse asset hash mismatch for {name}: {actual} != {expected}")
            print(f"PASS existing GitVerse asset: {expected}  {name}")
        else:
            client.upload_asset(release_id, name, args.assets_dir / name)

    final_assets = client.list_assets(release_id)
    final_names = sorted(
        asset.get("name") for asset in final_assets if isinstance(asset.get("name"), str)
    )
    if final_names != sorted(manifest):
        fail(f"GitVerse final asset names mismatch: {final_names!r}")

    for asset in final_assets:
        name = asset.get("name")
        if name not in manifest:
            continue
        url = asset.get("browser_download_url")
        if not isinstance(url, str):
            fail(f"GitVerse final asset has no download URL: {name}")
        actual = sha256_bytes(client.download_url(url))
        expected = manifest[name]
        if actual != expected:
            fail(f"Final GitVerse asset hash mismatch for {name}: {actual} != {expected}")
        print(f"PASS final GitVerse asset: {expected}  {name}")

    client.verify_readme(args.readme)
    print("GITVERSE RELEASE MIRROR: PASS")
    print(f"release_id={release_id}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
