#!/usr/bin/env python3
"""Submit a build to App Store review. The half release-testflight.py does not do.

    python3 tools/submit-appstore.py --version 0.2 --build 6
    python3 tools/submit-appstore.py --version 0.2 --build 6 --dry-run

Creates the App Store version record, attaches the build, writes the release
notes, and submits for review.

WHY A SEPARATE TOOL: TestFlight and the App Store are independent tracks. A build
on TestFlight is not submitted to the store, and a store submission does not
reach testers. release-testflight.py ends at beta distribution; this begins where
an uploaded, processed build already exists.

NOTE ON VERSION STRINGS: the build's CFBundleShortVersionString must equal the
App Store version string. Bump MARKETING_VERSION before archiving, or Apple
rejects the pairing and the mismatch is not obvious from the error.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt  # PyJWT

KEY_ID = "RWQT453LQJ"
ISSUER = "8a620c89-3a69-400c-9c73-2039ab12ee04"
KEY_PATH = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8")
APP_ID = "6798180343"


def say(msg: str) -> None:
    print(f"  {msg}", flush=True)


def token() -> str:
    return jwt.encode({"iss": ISSUER, "exp": int(time.time()) + 900,
                       "aud": "appstoreconnect-v1"},
                      open(KEY_PATH).read(), algorithm="ES256",
                      headers={"kid": KEY_ID, "typ": "JWT"})


def api(method: str, path: str, body: dict | None = None) -> dict:
    req = urllib.request.Request(
        f"https://api.appstoreconnect.apple.com{path}", method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": f"Bearer {token()}",
                 "Content-Type": "application/json"})
    try:
        raw = urllib.request.urlopen(req, timeout=90).read()
        return json.loads(raw) if raw else {"ok": True}
    except urllib.error.HTTPError as e:
        return {"ERROR": e.code, "body": e.read().decode()[:500]}


def find_build(number: str) -> str | None:
    r = api("GET", f"/v1/builds?filter[app]={APP_ID}&limit=10&sort=-uploadedDate")
    for d in r.get("data", []):
        if d["attributes"].get("version") == number:
            state = d["attributes"].get("processingState")
            if state != "VALID":
                say(f"build {number} is {state}, not VALID - wait for processing")
                return None
            return d["id"]
    say(f"build {number} not found on the account")
    return None


def find_or_create_version(version: str, release_type: str) -> str | None:
    r = api("GET", f"/v1/apps/{APP_ID}/appStoreVersions?limit=10")
    for d in r.get("data", []):
        a = d["attributes"]
        if a["versionString"] == version:
            say(f"version {version} exists, state {a['appStoreState']}")
            if a["appStoreState"] in ("READY_FOR_SALE", "PENDING_DEVELOPER_RELEASE"):
                say("  that version is already released - pick a new number")
                return None
            return d["id"]
    r = api("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": version,
                       "releaseType": release_type},
        "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
    if "data" not in r:
        say(f"could not create version: {r}")
        return None
    say(f"created version {version} ({release_type})")
    return r["data"]["id"]


def set_release_notes(version_id: str, notes: str) -> None:
    r = api("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    for d in r.get("data", []):
        if d["attributes"]["locale"] == "en-US":
            u = api("PATCH", f"/v1/appStoreVersionLocalizations/{d['id']}",
                    {"data": {"type": "appStoreVersionLocalizations", "id": d["id"],
                              "attributes": {"whatsNew": notes}}})
            say("release notes: " + ("written" if "data" in u else str(u)))
            return
    say("no en-US localization found")


def submit(version_id: str) -> None:
    """A review submission needs the version added as an ITEM, then submitting.
    Creating the submission alone leaves it sitting unreviewed - that is the step
    people forget."""
    r = api("POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions",
        "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
    if "data" not in r:
        say(f"could not open a submission: {r}")
        return
    sid = r["data"]["id"]
    say(f"opened submission {sid}")

    item = api("POST", "/v1/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})
    say("added the version: " + ("ok" if "data" in item else str(item)))

    done = api("PATCH", f"/v1/reviewSubmissions/{sid}", {"data": {
        "type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})
    if "data" in done:
        say(f"SUBMITTED, state {done['data']['attributes'].get('state')}")
    else:
        say(f"submit failed: {done}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--build", required=True)
    ap.add_argument("--notes", default="")
    ap.add_argument("--release-type", default="AFTER_APPROVAL",
                    choices=["MANUAL", "AFTER_APPROVAL"])
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    build_id = find_build(a.build)
    if not build_id:
        return 1
    say(f"build {a.build} is VALID, id={build_id}")

    if a.dry_run:
        say("dry run: stopping before any change")
        return 0

    vid = find_or_create_version(a.version, a.release_type)
    if not vid:
        return 1

    r = api("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {
        "type": "appStoreVersions", "id": vid,
        "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    say("attached the build: " + ("ok" if "data" in r else str(r)))

    if a.notes:
        set_release_notes(vid, a.notes)

    submit(vid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
