# -*- coding: utf-8 -*-
"""Read-only built-in connection test for Arvectum Proxy Launcher.

Windows connection diagnostics verifies the full Windows routing chain without changing proxy or
recovery state: direct internet, configured upstream proxy reachability, local
HTTP and SOCKS5 proxy paths, PAC endpoint, and Windows system proxy state.
"""

import concurrent.futures
import socket
import time
import urllib.error
import urllib.request
from urllib.parse import urlsplit

import proxy_core as core


PASS = "PASS"
WARN = "WARN"
FAIL = "FAIL"
SKIP = "SKIP"
SCHEMA = "arvectum.connection_test.v1"


def _normalize_url(value):
    value = (value or "").strip()
    if not value:
        raise ValueError("URL проверки не указан")
    if not value.startswith(("http://", "https://")):
        value = "https://" + value
    parsed = urlsplit(value)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise ValueError("Некорректный URL проверки")
    return value


def _result(check_id, label, status, detail, duration_ms=0, action=None):
    item = {
        "id": check_id,
        "label": label,
        "status": status,
        "detail": str(detail),
        "duration_ms": int(max(0, duration_ms)),
    }
    if action:
        item["action"] = str(action)
    return item


def _timed_result(check_id, label, callback, action=None):
    started = time.monotonic()
    try:
        status, detail = callback()
    except Exception as exc:
        status, detail = FAIL, "внутренняя ошибка проверки — %s" % exc
    elapsed = int((time.monotonic() - started) * 1000)
    return _result(check_id, label, status, detail, elapsed, action=action)


def _open_url(url, timeout, proxy_url=None):
    proxies = {} if proxy_url is None else {"http": proxy_url, "https": proxy_url}
    opener = urllib.request.build_opener(urllib.request.ProxyHandler(proxies))
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "Arvectum-Proxy-Launcher/%s connection-test" % core.APP_VERSION},
    )
    try:
        response = opener.open(request, timeout=timeout)
        try:
            code = getattr(response, "status", response.getcode())
            final_url = response.geturl() or url
            response.read(1)
            return int(code), final_url
        finally:
            response.close()
    except urllib.error.HTTPError as exc:
        # HTTP 4xx/5xx still proves that DNS/TCP/TLS/HTTP connectivity worked.
        try:
            final_url = exc.geturl() or url
        except (AttributeError, KeyError):
            final_url = url
        return int(exc.code), final_url


def _check_direct_internet(target_url, timeout):
    def work():
        try:
            code, final_url = _open_url(target_url, timeout=timeout)
            suffix = "" if final_url == target_url else " (редирект: %s)" % final_url
            return PASS, "доступ есть, HTTP %s%s" % (code, suffix)
        except Exception as exc:
            return FAIL, "нет прямого доступа — %s" % exc

    return _timed_result(
        "internet.direct",
        "Интернет напрямую",
        work,
        action="Проверьте интернет-подключение, DNS и локальные правила сети.",
    )


def _probe_upstream(upstream, timeout):
    host = (upstream.get("host") or "").strip()
    port = int(upstream.get("port") or 0)
    started = time.monotonic()
    try:
        sock = socket.create_connection((host, port), timeout=timeout)
        try:
            pass
        finally:
            sock.close()
        return host, port, True, "", int((time.monotonic() - started) * 1000)
    except Exception as exc:
        return host, port, False, str(exc), int((time.monotonic() - started) * 1000)


def _check_upstream(settings, timeout):
    configured = [
        {"host": (item.get("host") or "").strip(), "port": int(item.get("port") or 0)}
        for item in (settings.get("upstream") or [])
        if (item.get("host") or "").strip()
    ]
    if not configured:
        return _result(
            "upstream.tcp",
            "Внешний прокси",
            FAIL,
            "внешний прокси не настроен",
            action="Откройте «Настройки прокси» и укажите адрес и порт.",
        )

    started = time.monotonic()
    per_probe_timeout = max(0.5, min(float(timeout), 3.0))
    max_workers = max(1, min(8, len(configured)))
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as pool:
        results = list(pool.map(lambda item: _probe_upstream(item, per_probe_timeout), configured))
    elapsed = int((time.monotonic() - started) * 1000)

    good = [item for item in results if item[2]]
    bad = [item for item in results if not item[2]]
    if len(good) == len(results):
        detail = "доступны все настроенные прокси (%s/%s)" % (len(good), len(results))
        return _result("upstream.tcp", "Внешний прокси", PASS, detail, elapsed)
    if good:
        failed = ", ".join("%s:%s" % (host, port) for host, port, *_ in bad[:3])
        detail = "доступно %s/%s; недоступны: %s" % (len(good), len(results), failed)
        return _result(
            "upstream.tcp",
            "Внешний прокси",
            WARN,
            detail,
            elapsed,
            action="Проверьте недоступные адреса внешних прокси или удалите их из failover-списка.",
        )

    failed = ", ".join("%s:%s" % (host, port) for host, port, *_ in bad[:3])
    return _result(
        "upstream.tcp",
        "Внешний прокси",
        FAIL,
        "не доступен ни один настроенный прокси: %s" % failed,
        elapsed,
        action="Проверьте адрес, порт, доступность внешнего прокси и сетевые ограничения.",
    )


def _check_local_http(settings, target_url, timeout, running):
    if not running:
        return _result(
            "local.http",
            "HTTP через Launcher",
            SKIP,
            "proxy engine не запущен",
            action="Включите прокси и повторите проверку для end-to-end теста.",
        )

    port = int(settings.get("local_http_port", 8080))
    proxy_url = "http://127.0.0.1:%s" % port

    def work():
        try:
            code, final_url = _open_url(target_url, timeout=timeout, proxy_url=proxy_url)
            suffix = "" if final_url == target_url else " (редирект: %s)" % final_url
            return PASS, "локальный HTTP proxy отвечает, HTTP %s%s" % (code, suffix)
        except Exception as exc:
            return FAIL, "HTTP-маршрут через 127.0.0.1:%s не работает — %s" % (port, exc)

    return _timed_result(
        "local.http",
        "HTTP через Launcher",
        work,
        action="Проверьте внешний прокси, журнал Launcher и доступность локального HTTP-порта.",
    )


def _recv_exact(sock, length):
    data = b""
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            raise OSError("SOCKS5 закрыл соединение")
        data += chunk
    return data


def _socks_target(target_url):
    parsed = urlsplit(target_url)
    host = parsed.hostname
    if not host:
        raise ValueError("URL не содержит hostname")
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    encoded = host.encode("idna")
    if len(encoded) > 255:
        raise ValueError("hostname слишком длинный для SOCKS5")
    return encoded, int(port)


def _check_local_socks(settings, target_url, timeout, running):
    if not running:
        return _result(
            "local.socks",
            "SOCKS5 через Launcher",
            SKIP,
            "proxy engine не запущен",
            action="Включите прокси и повторите проверку.",
        )

    port = int(settings.get("local_socks_port", 1080))

    def work():
        sock = None
        try:
            target_host, target_port = _socks_target(target_url)
            sock = socket.create_connection(("127.0.0.1", port), timeout=timeout)
            sock.settimeout(timeout)
            sock.sendall(b"\x05\x01\x00")
            greeting = _recv_exact(sock, 2)
            if greeting != b"\x05\x00":
                return FAIL, "неожиданный ответ SOCKS5 greeting: %r" % (greeting,)

            request = (
                b"\x05\x01\x00\x03"
                + bytes([len(target_host)])
                + target_host
                + int(target_port).to_bytes(2, "big")
            )
            sock.sendall(request)
            header = _recv_exact(sock, 4)
            if header[0] != 5:
                return FAIL, "локальный порт ответил не как SOCKS5"
            if header[1] != 0:
                return FAIL, "SOCKS5 CONNECT отклонён, код 0x%02x" % header[1]

            atyp = header[3]
            if atyp == 1:
                _recv_exact(sock, 4)
            elif atyp == 3:
                size = _recv_exact(sock, 1)[0]
                _recv_exact(sock, size)
            elif atyp == 4:
                _recv_exact(sock, 16)
            else:
                return FAIL, "SOCKS5 вернул неизвестный тип адреса 0x%02x" % atyp
            _recv_exact(sock, 2)
            return PASS, "SOCKS5 CONNECT к %s:%s успешен" % (
                target_host.decode("idna"), target_port)
        except Exception as exc:
            return FAIL, "SOCKS5-маршрут через 127.0.0.1:%s не работает — %s" % (port, exc)
        finally:
            if sock is not None:
                try:
                    sock.close()
                except Exception:
                    pass

    return _timed_result(
        "local.socks",
        "SOCKS5 через Launcher",
        work,
        action="Проверьте внешний прокси, журнал Launcher и локальный SOCKS5-порт.",
    )


def _check_pac(settings, timeout, running):
    if not running:
        return _result(
            "pac.endpoint",
            "PAC",
            SKIP,
            "proxy engine не запущен",
            action="Включите прокси и повторите проверку.",
        )

    port = int(settings.get("local_pac_port", 8082))
    pac_path = str(settings.get("pac_path") or "/proxy.pac")
    url = "http://127.0.0.1:%s%s" % (port, pac_path)

    def work():
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        response = None
        try:
            response = opener.open(url, timeout=timeout)
            code = int(getattr(response, "status", response.getcode()))
            body = response.read(64 * 1024).decode("utf-8", "replace")
            if code != 200:
                return FAIL, "PAC endpoint вернул HTTP %s" % code
            if "FindProxyForURL" not in body or "127.0.0.1:" not in body:
                return FAIL, "PAC получен, но не похож на конфигурацию Arvectum"
            return PASS, "PAC доступен на 127.0.0.1:%s и содержит FindProxyForURL" % port
        except Exception as exc:
            return FAIL, "PAC endpoint недоступен — %s" % exc
        finally:
            if response is not None:
                try:
                    response.close()
                except Exception:
                    pass

    return _timed_result(
        "pac.endpoint",
        "PAC",
        work,
        action="Проверьте журнал Launcher и локальный PAC-порт.",
    )


def _check_system_configuration(running, enabled, pending, orphaned, stale):
    if pending:
        return _result(
            "windows.system_proxy",
            "Системные настройки прокси",
            FAIL,
            "есть незавершённое восстановление сети",
            action="Нажмите «Восстановить настройки сети» и повторите проверку.",
        )
    if orphaned:
        return _result(
            "windows.system_proxy",
            "Системные настройки прокси",
            FAIL,
            "обнаружен старый PAC Arvectum без подтверждённого активного сеанса",
            action="Используйте безопасное удаление старого PAC в Launcher.",
        )
    if stale:
        return _result(
            "windows.system_proxy",
            "Системные настройки прокси",
            FAIL,
            "Система использует настройки Arvectum, но ownership активного сеанса не подтверждён",
            action="Откройте «Диагностика»; автоматический сброс намеренно не выполняется.",
        )
    if running and enabled:
        return _result(
            "windows.system_proxy",
            "Системные настройки прокси",
            PASS,
            "системный proxy включён и связан с активным сеансом Launcher",
        )
    if running and not enabled:
        return _result(
            "windows.system_proxy",
            "Системные настройки прокси",
            WARN,
            "proxy engine работает, но системный proxy не включён",
            action="Нажмите «Включить прокси», чтобы подключить системную маршрутизацию.",
        )
    if not running and enabled:
        return _result(
            "windows.system_proxy",
            "Системные настройки прокси",
            FAIL,
            "системный proxy включён, но активный proxy engine не найден",
            action="Откройте «Диагностика» и не сбрасывайте чужие настройки автоматически.",
        )
    return _result(
        "windows.system_proxy",
        "Системные настройки прокси",
        PASS,
        "Launcher выключен; система не направляет трафик через активный сеанс Arvectum",
    )


def _safe_state(core_module):
    running = bool(core_module.is_running())
    enabled = bool(core_module.system_proxy_enabled())
    pending = bool(core_module.network_restore_pending())
    orphaned = bool(core_module.orphaned_arvectum_pac())
    stale = False
    if not running and not pending and not orphaned:
        stale = bool(core_module.stale_system_proxy())
    return running, enabled, pending, orphaned, stale


def _overall(checks):
    statuses = {item.get("status") for item in checks}
    if FAIL in statuses:
        return FAIL
    if WARN in statuses or SKIP in statuses:
        return WARN
    return PASS


def _recommended_actions(checks):
    actions = []
    for item in checks:
        if item.get("status") == PASS:
            continue
        action = item.get("action")
        if action and action not in actions:
            actions.append(action)
    return actions


def run_connection_test(target_url="https://arvectum.com", timeout=6.0, core_module=core):
    """Run the read-only connection diagnostics health check and return a structured report."""
    target_url = _normalize_url(target_url)
    timeout = max(1.0, min(float(timeout), 20.0))
    settings = core_module.load_settings()
    running, enabled, pending, orphaned, stale = _safe_state(core_module)

    started = time.monotonic()
    checks = []

    # System configuration is local/read-only and should always be reported even
    # if every network probe times out.
    checks.append(_check_system_configuration(running, enabled, pending, orphaned, stale))

    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
        futures = [
            pool.submit(_check_direct_internet, target_url, timeout),
            pool.submit(_check_upstream, settings, timeout),
            pool.submit(_check_local_http, settings, target_url, timeout, running),
            pool.submit(_check_local_socks, settings, target_url, timeout, running),
            pool.submit(_check_pac, settings, timeout, running),
        ]
        for future in futures:
            checks.append(future.result())

    order = {
        "internet.direct": 0,
        "upstream.tcp": 1,
        "local.http": 2,
        "local.socks": 3,
        "pac.endpoint": 4,
        "windows.system_proxy": 5,
    }
    checks.sort(key=lambda item: order.get(item.get("id"), 99))
    counts = {status: 0 for status in (PASS, WARN, FAIL, SKIP)}
    for item in checks:
        counts[item["status"]] = counts.get(item["status"], 0) + 1

    return {
        "schema": SCHEMA,
        "overall": _overall(checks),
        "target_url": target_url,
        "duration_ms": int((time.monotonic() - started) * 1000),
        "checks": checks,
        "counts": counts,
        "recommended_actions": _recommended_actions(checks),
        "read_only": True,
    }


def format_report(report):
    overall = report.get("overall", FAIL)
    title = {
        PASS: "Проверка соединения: всё работает.",
        WARN: "Проверка соединения: есть предупреждения.",
        FAIL: "Проверка соединения: требуется действие.",
    }.get(overall, "Проверка соединения завершена.")

    lines = [title, "Цель: %s" % report.get("target_url", "")]
    for item in report.get("checks") or []:
        lines.append("[%s] %s — %s" % (
            item.get("status", "?"),
            item.get("label", item.get("id", "проверка")),
            item.get("detail", ""),
        ))

    actions = report.get("recommended_actions") or []
    if actions:
        lines.append("")
        lines.append("Что сделать:")
        for action in actions[:6]:
            lines.append("• %s" % action)
    return "\n".join(lines)
