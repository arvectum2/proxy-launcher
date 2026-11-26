#!/usr/bin/env python3
"""Offline operator commands and host receipt checks; never authorize a device, runtime or release."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import secrets
import sys
import uuid

from validate_unified_synthetic_receipt import exact, need, read, uuidstr

KINDS = ("wireGuard", "amneziaWG1", "vlessReality")
PROBES = ("tcp4", "tcp6", "udp4", "udp6")
ACTIONS = ("prepareManager", "readManager", "run", "removeManager", "offControl")
BINDING = ("requestID", "owner", "reference", "action")
OPTIONAL = ("scope", "probe", "mode")


def new_id():
    return str(uuid.uuid4()).upper()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def reference(value):
    exact(value, "profileID revision kind")
    need(uuidstr(value["profileID"]) and uuidstr(value["revision"]) and value["kind"] in KINDS, "invalid fixture reference")


def validate_command(command):
    required = {"schema", *BINDING}
    need(type(command) is dict and required <= set(command) <= required | set(OPTIONAL) | {"nonce"}, "invalid command schema")
    need(type(command["schema"]) is int and command["schema"] == 1 and uuidstr(command["requestID"]) and uuidstr(command["owner"]) and command["requestID"] != command["owner"], "invalid command identity")
    reference(command["reference"])
    action = command["action"]
    need(action in ACTIONS, "invalid action")
    scope, probe, mode, nonce = (command.get(k) for k in (*OPTIONAL, "nonce"))
    if action == "offControl":
        kind = command["reference"]["kind"]
        if scope=="vlessGuardedLoss":
            need(kind=="vlessReality" and probe in ("udp4","udp6","dnsWire4") and mode=="observe-off" and type(nonce) is str and re.fullmatch("[0-9a-f]{40}",nonce) is not None,"invalid isolated loss off control")
            return
        full_route = (kind == "wireGuard" and scope == "wireGuardFull") or (kind == "amneziaWG1" and scope is None)
        need(full_route and probe in ("udp4","udp6","dnsWire4") and mode=="observe-off" and type(nonce) is str and re.fullmatch("[0-9a-f]{%d}" % (48 if kind == "amneziaWG1" else 40),nonce) is not None, "invalid OFF control")
        return
    if action != "run":
        need(all(v is None for v in (scope, probe, mode, nonce)), "manager command has probe options")
        return
    kind = command["reference"]["kind"]
    if scope=="vlessGuardedLoss":
        need(kind=="vlessReality" and probe in ("udp4","udp6","dnsWire4") and mode=="peer-loss" and type(nonce) is str and re.fullmatch("[0-9a-f]{40}",nonce) is not None,"invalid isolated loss command")
        return
    if scope == "vlessDNSWire":
        need(kind=="vlessReality" and probe=="dnsWire4" and mode=="positive" and type(nonce) is str and re.fullmatch("[0-9a-f]{40}",nonce) is not None,"invalid VLESS DNS wire command")
        return
    if mode == "peer-loss":
        full_route = (kind == "wireGuard" and scope == "wireGuardFull") or (kind == "amneziaWG1" and scope is None)
        need(full_route and probe in ("udp4","udp6","dns4") and type(nonce) is str and re.fullmatch("[0-9a-f]{%d}" % (48 if kind == "amneziaWG1" else 40),nonce) is not None,"invalid peer loss command")
        return
    need((probe in PROBES or (probe == "dns4" and mode == "positive" and ((kind == "amneziaWG1" and scope is None) or (kind == "wireGuard" and scope == "wireGuardFull")))) and type(nonce) is str and re.fullmatch("[0-9a-f]{%d}" % (48 if kind == "amneziaWG1" else 40), nonce) is not None, "invalid probe challenge")
    if kind == "amneziaWG1":
        need(scope is None and mode in ("positive", "wrong-key", "wrong-psk"), "invalid AWG scope or mode")
    else:
        expanded = "wireGuardFull" if kind == "wireGuard" else "vlessDatagrams"
        need((scope == expanded or (scope is None and probe == "tcp4")) and mode in ("positive", "wrong-key"), "invalid Xray scope or mode")


def post_loss_nonce(command):
    validate_command(command)
    need(command.get("mode")=="peer-loss","not a peer loss command")
    return sha(("APL-QA-POST-LOSS:"+command["nonce"]).encode())[:len(command["nonce"])]


def make_command(fixture, owner, action, scope=None, probe=None, mode=None):
    exact(fixture, "schema reference")
    need(type(fixture["schema"]) is int and fixture["schema"] == 1, "invalid fixture schema")
    reference(fixture["reference"])
    command = dict(schema=1, requestID=new_id(), owner=owner, reference=fixture["reference"], action=action)
    for name, value in zip(OPTIONAL, (scope, probe, mode)):
        if value is not None:
            command[name] = value
    if action in ("run", "offControl"):
        command["nonce"] = secrets.token_hex(24 if fixture["reference"]["kind"] == "amneziaWG1" else 20)
    validate_command(command)
    return command


def command_file(path, command):
    validate_command(command)
    parent = path.parent
    need(parent.is_dir() and not parent.is_symlink() and parent.stat().st_mode & 0o077 == 0, "output directory must be private")
    encoded = (json.dumps(command, sort_keys=True, separators=(",", ":")) + "\n").encode()
    need(len(encoded) <= 4096, "command too large")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as out:
        out.write(encoded)


def validate_identity(value, provider):
    exact(value, "epoch generation provider")
    need(uuidstr(value["epoch"]) and type(value["generation"]) is int and value["generation"] == 1 and value["provider"] == provider, "invalid control identity")


def verify_host(command, receipt):
    validate_command(command)
    required = {"schema", *BINDING, "setup", "probeAttempted", "managerReadback", "osOff", "independentWitnessRequired", "releaseAuthorized"}
    allowed = required | set(OPTIONAL) | {"responseSHA256", "drain", "loss"}
    need(type(receipt) is dict and required <= set(receipt) <= allowed, "invalid host receipt schema")
    need(type(receipt["schema"]) is int and receipt["schema"] == 1, "invalid host schema")
    for key in BINDING:
        need(receipt[key] == command[key], "command/receipt binding mismatch")
    for key in OPTIONAL:
        need(receipt.get(key) == command.get(key), "probe option mismatch")
    need(receipt["managerReadback"] is True and receipt["osOff"] is True and receipt["independentWitnessRequired"] is True and receipt["releaseAuthorized"] is False, "incomplete safety boundary")
    result = dict(status="host_receipt_correlated_only", action=command["action"], kind=command["reference"]["kind"], requestID=command["requestID"], independent_witness_required=True, runtime_authorized=False, release_authorized=False)
    need(command.get("scope") not in ("vlessDNSWire","vlessGuardedLoss"),"isolated DNS wire requires independent QA receipt")
    setup, drain = receipt["setup"], receipt.get("drain")
    if command.get("mode")=="peer-loss":
        allowed_loss={"firstStart","firstEnd","secondStart","secondEnd","secondChallengeSHA256"}
        loss=receipt.get("loss")
        need(type(loss) is dict and allowed_loss <= set(loss) <= allowed_loss | {"secondResponseSHA256"}, "missing loss transcript")
        times=[loss[k] for k in ("firstStart","firstEnd","secondStart","secondEnd")]
        need(all(type(t) in (int,float) and math.isfinite(t) and t>0 for t in times),"invalid loss timestamps")
        a,b,c,d=times
        probe_limit=10 if command["probe"]=="dns4" else 5
        need(a<=b<c<=d and 7.9<=c-b<=15 and b-a<=probe_limit and d-c<=probe_limit,"invalid loss timeline")
        need(loss["secondChallengeSHA256"]==sha(post_loss_nonce(command).encode()) and loss.get("secondResponseSHA256") is None,"unexpected post loss response")
    else:
        need("loss" not in receipt,"unexpected loss transcript")
    need(type(setup) is list, "invalid setup transcript")
    if command["action"] == "offControl":
        need(setup == [] and drain is None and receipt["probeAttempted"] is True and receipt.get("responseSHA256") is None, "invalid OFF control evidence")
        return dict(result,probe=command["probe"],mode=command["mode"],challengeSHA256=sha(command["nonce"].encode()))
    if command["action"] != "run":
        need(setup == [] and drain is None and receipt["probeAttempted"] is False and receipt.get("responseSHA256") is None, "manager-only receipt contains runtime evidence")
        return result
    need(len(setup) == 2 and drain is not None and receipt["probeAttempted"] is True, "missing control exchange")
    kind = command["reference"]["kind"]
    provider = "standalone-awg" if kind == "amneziaWG1" else "rust-xray"
    live = None
    seen = {command["requestID"], command["owner"]}
    for i, (exchange, action, state) in enumerate(zip([*setup, drain], ("observe", "observe", "drain"), ("starting", "rejected", "drained"))):
        exact(exchange, "request response")
        q, r = exchange["request"], exchange["response"]
        exact(q, "version id identity action")
        exact(r, "version id identity action state")
        need(type(q["version"]) is int and q["version"] == 1 and type(r["version"]) is int and r["version"] == 1 and uuidstr(q["id"]) and q["id"] not in seen, "duplicate/invalid control request")
        seen.add(q["id"])
        validate_identity(q["identity"], provider)
        validate_identity(r["identity"], provider)
        need(q["action"] == action and r == dict(q, state=state), "control response mismatch")
        if i == 0:
            live = q["identity"]
        elif i == 1:
            need(q["identity"]["epoch"] != live["epoch"], "stale epoch not distinct")
        else:
            need(q["identity"] == live, "drain does not match live identity")
    nonce = command["nonce"]
    expected = sha((("APL:" if kind == "amneziaWG1" else "APL_RECEIPT:") + nonce).encode())
    need(receipt.get("responseSHA256") == (expected if command["mode"] in ("positive","peer-loss") else None), "unexpected host probe result")
    return dict(result, probe=command["probe"], mode=command["mode"], challengeSHA256=sha(nonce.encode()))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="operation", required=True)
    m = sub.add_parser("make")
    m.add_argument("fixture", type=Path)
    m.add_argument("output", type=Path)
    m.add_argument("--owner", required=True)
    m.add_argument("--action", choices=ACTIONS, required=True)
    m.add_argument("--scope", choices=("wireGuardFull", "vlessDatagrams"))
    m.add_argument("--probe", choices=(*PROBES, "dns4", "dnsWire4"))
    m.add_argument("--mode", choices=("positive", "wrong-key", "wrong-psk", "observe-off", "peer-loss"))
    v = sub.add_parser("verify-host")
    v.add_argument("command", type=Path)
    v.add_argument("receipt", type=Path)
    a = p.parse_args()
    if a.operation == "make":
        command = make_command(read(a.fixture), a.owner, a.action, a.scope, a.probe, a.mode)
        command_file(a.output, command)
        result = {"status": "private_command_created", "requestID": command["requestID"], "action": command["action"], "runtime_authorized": False}
    else:
        result = verify_host(read(a.command), read(a.receipt))
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError) as exc:
        print("QA input rejected: " + type(exc).__name__, file=sys.stderr)
        sys.exit(1)
