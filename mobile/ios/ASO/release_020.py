#!/usr/bin/env python3
"""Guarded App Store Connect iOS 0.2.0(48) release: no privacy, ads, or 0.1.41 writes."""
import argparse
from pathlib import Path
import sys
from import_appstore import ASC, APP_ID, ImportErrorASC, payload, verify_asset_processing, load_rows

VERSION = "0.2.0"
BUILD = "48"
PREVIOUS = "0.1.41"
NOTES = Path(__file__).with_name("release_notes_020.tsv")
EDITABLE = {"PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW"}

def apple_version(api):
    all_versions = api.list(f"/apps/{APP_ID}/appStoreVersions?limit=100")
    def matching(name):
        return [v for v in all_versions if v["attributes"].get("platform") == "IOS"
                and v["attributes"].get("versionString") == name]
    old, current = matching(PREVIOUS), matching(VERSION)
    if len(old) != 1 or old[0]["attributes"]["appStoreState"] != "READY_FOR_SALE":
        raise ImportErrorASC("Previous iOS 0.1.41 is not released")
    if len(current) != 1:
        raise ImportErrorASC(f"Expected one iOS 0.2.0, got {len(current)}")
    return current[0]

def edited_version(api):
    v = apple_version(api)
    if v["attributes"]["appStoreState"] not in EDITABLE:
        raise ImportErrorASC("iOS 0.2.0 is not editable: " + v["attributes"]["appStoreState"])
    return v

def notes_map():
    pairs = [line.split("\t", 1) for line in NOTES.read_text("utf-8").splitlines()]
    if len(pairs) != 47 or any(len(p) != 2 for p in pairs):
        raise ImportErrorASC("Expected 47 locale/tab/note records")
    result = dict(pairs)
    if len(result) != 47 or any(not 10 <= len(x) <= 4000 for x in result.values()):
        raise ImportErrorASC("Duplicate or invalid localized note")
    return result

def version_locales(api, version_id):
    return {i["attributes"]["locale"]: i for i in
            api.list(f"/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=200")}

def update_notes(api, version):
    expected, existing = notes_map(), version_locales(api, version["id"])
    if set(expected) != set(existing):
        raise ImportErrorASC("ASO locale mismatch: " + str(sorted(set(expected) ^ set(existing))))
    changed = 0
    for locale in sorted(expected):
        item = existing[locale]
        if item["attributes"].get("whatsNew") != expected[locale]:
            api.call("PATCH", f"/appStoreVersionLocalizations/{item['id']}",
                     payload("appStoreVersionLocalizations",
                             {"whatsNew": expected[locale]}, item["id"]))
            changed += 1
            if changed % 10 == 0: print("NOTES_UPDATED_PROGRESS", changed, flush=True)
    print("APPLE_020_NOTES", len(existing), "UPDATED", changed, flush=True)

def uploaded_build(api):
    items = api.list(f"/builds?filter[app]={APP_ID}&limit=100")
    found = [i for i in items if i["attributes"].get("version") == BUILD]
    if len(found) != 1:
        raise ImportErrorASC(f"Expected one build 48, found {len(found)}")
    b = found[0]
    if b["attributes"].get("processingState") != "VALID":
        raise ImportErrorASC("Apple build not yet VALID: " + str(b["attributes"].get("processingState")))
    pre = api.call("GET", f"/builds/{b['id']}/preReleaseVersion")["data"]
    if pre["attributes"].get("version") != VERSION:
        raise ImportErrorASC("Apple build 48 belongs to different app version")
    return b

def attach(api, version):
    b = uploaded_build(api)
    v = api.call("GET", f"/appStoreVersions/{version['id']}?include=build")["data"]
    rel = v.get("relationships", {}).get("build", {}).get("data")
    if rel and rel["id"] != b["id"]:
        raise ImportErrorASC("Different build selected in Apple; manual inspection required")
    if not rel:
        api.call("PATCH", f"/appStoreVersions/{version['id']}/relationships/build",
                 {"data": {"type": "builds", "id": b["id"]}})
    print("APPLE_020_BUILD_ATTACHED", b["id"], flush=True)

def readiness(api, version):
    expected, existing = notes_map(), version_locales(api, version["id"])
    if set(expected) != set(existing):
        raise ImportErrorASC("Missing Apple 0.2.0 locales")
    stale = [k for k, value in expected.items()
             if (existing[k]["attributes"].get("whatsNew") or "") != value]
    if stale:
        raise ImportErrorASC("Obsolete or missing WhatsNew: " + str(stale))
    rows = [row for row in load_rows() if row["locale"] in existing]
    verify_asset_processing(api, version["id"], rows)
    build = uploaded_build(api)
    v = api.call("GET", f"/appStoreVersions/{version['id']}?include=build")["data"]
    rel = v.get("relationships", {}).get("build", {}).get("data")
    if not rel or rel["id"] != build["id"]:
        raise ImportErrorASC("Build 48 is not linked to version 0.2.0")
    print("APPLE_020_READY", len(existing), "locales, 94 COMPLETE screenshots, build", build["id"], flush=True)

def submit(api, version):
    readiness(api, version)
    submissions = api.list(f"/apps/{APP_ID}/reviewSubmissions?limit=100")
    drafts = [r for r in submissions if r["attributes"].get("platform") == "IOS"
              and r["attributes"].get("state") == "READY_FOR_REVIEW"]
    if len(drafts) > 1:
        raise ImportErrorASC("Multiple iOS review drafts")
    if drafts:
        draft = drafts[0]
    else:
        draft = api.call("POST", "/reviewSubmissions", {
            "data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                     "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}
        })["data"]
    items = api.list(f"/reviewSubmissions/{draft['id']}/items?limit=100")
    if items:
        if len(items) != 1:
            raise ImportErrorASC("Unrelated review submission items")
        item = api.call("GET", f"/reviewSubmissionItems/{items[0]['id']}?include=appStoreVersion")["data"]
        rel = item.get("relationships", {}).get("appStoreVersion", {}).get("data")
        if not rel or rel["id"] != version["id"]:
            raise ImportErrorASC("Existing review draft belongs to another app version")
    else:
        api.call("POST", "/reviewSubmissionItems", {
            "data": {"type": "reviewSubmissionItems", "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": draft["id"]}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}
            }}
        })
    if edited_version(api)["id"] != version["id"]:
        raise ImportErrorASC("Version changed before review submission")
    result = api.call("PATCH", f"/reviewSubmissions/{draft['id']}", {
        "data": {"type": "reviewSubmissions", "id": draft["id"],
                 "attributes": {"submitted": True}}
    })["data"]
    print("APPLE_020_REVIEW_SUBMITTED", draft["id"], result["attributes"].get("state"), flush=True)

def main():
    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group(required=True)
    for name in ("status", "notes", "attach", "ready", "submit"):
        modes.add_argument("--" + name, action="store_true")
    parser.add_argument("--confirm-version")
    args = parser.parse_args()
    if (args.notes or args.attach or args.submit) and args.confirm_version != VERSION:
        parser.error("Writes require --confirm-version 0.2.0")
    api = ASC()
    v = apple_version(api) if args.status else edited_version(api)
    print("APPLE_020_VERSION", v["id"], v["attributes"]["appStoreState"], flush=True)
    if args.notes: update_notes(api, v)
    elif args.attach: attach(api, v)
    elif args.ready: readiness(api, v)
    elif args.submit: submit(api, v)

if __name__ == "__main__":
    try:
        main()
    except (ImportErrorASC, ValueError, KeyError, AssertionError) as exc:
        print("APPLE_020_RELEASE_GATE_FAILED", str(exc)[:650], file=sys.stderr)
        sys.exit(2)
