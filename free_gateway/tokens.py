"""Short-lived stateless credentials for the public gateway."""

import base64
import hashlib
import hmac
import time


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


class SessionTokenManager:
    def __init__(self, secret: str, ttl_seconds: int = 600, clock=None):
        if len(secret) < 32:
            raise ValueError("token secret is too short")
        self._secret = secret.encode("utf-8")
        self._ttl = min(int(ttl_seconds), 3600)
        self._clock = clock or time.time

    def issue(self, location_id: str) -> tuple[str, int]:
        expires = int(self._clock()) + self._ttl
        payload = f"{location_id}:{expires}".encode("utf-8")
        signature = hmac.new(self._secret, payload, hashlib.sha256).digest()
        return f"{expires}.{_b64(signature)}", expires

    def verify(self, location_id: str, token: str) -> bool:
        try:
            expires_text, supplied = token.split(".", 1)
            expires = int(expires_text)
        except (ValueError, AttributeError):
            return False
        now = int(self._clock())
        if expires < now or expires > now + 3600:
            return False
        payload = f"{location_id}:{expires}".encode("utf-8")
        expected = _b64(hmac.new(self._secret, payload, hashlib.sha256).digest())
        return hmac.compare_digest(supplied, expected)
