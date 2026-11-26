"""Validate explicit, complete session-control acceptance; no device actions."""
REQUIRED = ("nativeControlAccepted", "nativeReady", "nativeOSConnected", "nativeStaleRejected", "nativeDrained", "nativeOSOff")


def validate_native_control(item):
    if any(item.get(key) is not True for key in REQUIRED) or item.get("nativeFailure") is not False:
        raise RuntimeError("Incomplete native session-control receipt")
