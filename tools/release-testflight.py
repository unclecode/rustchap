#!/usr/bin/env python3
"""Ship a build to TestFlight. No Xcode UI, no browser, no Apple ID session.

    python3 tools/release-testflight.py                 # bump, build, upload, distribute
    python3 tools/release-testflight.py --skip-gates    # when you already ran them
    python3 tools/release-testflight.py --no-bump       # re-upload the current number
    python3 tools/release-testflight.py --dry-run       # everything except upload

Steps: verify → bump build number → archive → upload → wait for processing →
add to external groups → submit for beta review.

WHY THIS EXISTS (2026-08-08): builds 1-4 were signed by Xcode's cloud signing,
which needs a live Apple ID session on the paid team. That session lapsed and the
Xcode account fell back to a Personal Team, which cannot sign for distribution at
all, so the upload failed with "No signing certificate iOS Distribution found".
The fix was to stop depending on Xcode: a real distribution certificate was
created through the API from a local CSR, and the export switched to manual
signing. Everything here now runs from an App Store Connect API key.

SETUP THIS DEPENDS ON (already done, documented in docs/context/architecture/release.md):
  ~/.appstoreconnect/private_keys/AuthKey_RWQT453LQJ.p8   App Manager key
  ~/.appstoreconnect/signing/rustchap-dist.p12            distribution cert + key
  Apple Distribution: HOSSEIN TOHIDI (TPP52TWEWR)         in the login keychain
  RustChap AppStore                                       provisioning profile
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

import jwt  # PyJWT

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IOS = f"{ROOT}/apps/ios"
PBXPROJ = f"{IOS}/RustChap.xcodeproj/project.pbxproj"

KEY_ID = "RWQT453LQJ"
ISSUER = "8a620c89-3a69-400c-9c73-2039ab12ee04"
KEY_PATH = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8")
APP_ID = "6798180343"
DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer"


def say(msg: str) -> None:
    print(f"  {msg}", flush=True)


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    env = {**os.environ, "DEVELOPER_DIR": DEVELOPER_DIR}
    return subprocess.run(cmd, cwd=kw.pop("cwd", ROOT), env=env,
                          capture_output=True, text=True, **kw)


# ------------------------------------------------------------------ ASC API
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
        return {"ERROR": e.code, "body": e.read().decode()[:400]}


# -------------------------------------------------------------------- steps
def gates() -> bool:
    checks = [
        ("content", [sys.executable, "tools/repair-content.py", "--scan"]),
        ("style", [sys.executable, "tools/check-style.py"]),
        ("review cards", [sys.executable, "tools/validate-review.py"]),
        ("progression", [sys.executable, "tools/audit-progression.py"]),
        ("rust tests", ["cargo", "test", "--workspace", "-q"]),
    ]
    ok = True
    for name, cmd in checks:
        r = run(cmd)
        bad = r.returncode != 0
        if name == "content":
            bad = "0 broken node(s)" not in r.stdout
        say(f"{'FAIL' if bad else 'ok  '} {name}")
        ok = ok and not bad
    return ok


def current_build() -> int:
    return int(re.search(r"CURRENT_PROJECT_VERSION = (\d+);",
                         open(PBXPROJ).read()).group(1))


def bump_build() -> int:
    src = open(PBXPROJ).read()
    now = current_build()
    open(PBXPROJ, "w").write(
        src.replace(f"CURRENT_PROJECT_VERSION = {now};",
                    f"CURRENT_PROJECT_VERSION = {now + 1};"))
    return now + 1


def archive() -> bool:
    run(["rm", "-rf", f"{IOS}/build/RustChap.xcarchive"])
    r = run(["xcodebuild", "archive", "-project", "RustChap.xcodeproj",
             "-scheme", "RustChap", "-configuration", "Release",
             "-archivePath", "build/RustChap.xcarchive",
             "-destination", "generic/platform=iOS"], cwd=IOS)
    return "ARCHIVE SUCCEEDED" in r.stdout


def upload() -> bool:
    r = run(["xcodebuild", "-exportArchive",
             "-archivePath", "build/RustChap.xcarchive",
             "-exportOptionsPlist", "build/ExportOptions.plist",
             "-authenticationKeyPath", KEY_PATH,
             "-authenticationKeyID", KEY_ID,
             "-authenticationKeyIssuerID", ISSUER], cwd=IOS)
    if "EXPORT SUCCEEDED" not in r.stdout:
        print(r.stdout[-1500:])
        return False
    return True


def wait_for_build(version: int, minutes: int = 20) -> str | None:
    """App Store Connect processes the upload before it can be distributed."""
    deadline = time.time() + minutes * 60
    while time.time() < deadline:
        r = api("GET", f"/v1/builds?filter[app]={APP_ID}&limit=5&sort=-uploadedDate")
        for d in r.get("data", []):
            if d["attributes"].get("version") == str(version):
                state = d["attributes"].get("processingState")
                if state == "VALID":
                    return d["id"]
                if state in ("INVALID", "FAILED"):
                    say(f"processing {state}")
                    return None
                say(f"processing... ({state})")
                break
        time.sleep(30)
    say("timed out waiting for processing")
    return None


def distribute(build_id: str) -> None:
    """Internal groups get builds automatically. External ones must be given the
    build AND have it submitted for beta review, which is the step that leaves a
    build sitting on 'Ready to Submit' if you forget it."""
    groups = api("GET", f"/v1/betaGroups?filter[app]={APP_ID}")
    for g in groups.get("data", []):
        name = g["attributes"]["name"]
        if g["attributes"].get("isInternalGroup"):
            say(f"{name}: internal, gets the build automatically")
            continue
        r = api("POST", f"/v1/betaGroups/{g['id']}/relationships/builds",
                {"data": [{"type": "builds", "id": build_id}]})
        say(f"{name}: {'added' if r.get('ok') else r}")

    r = api("POST", "/v1/betaAppReviewSubmissions",
            {"data": {"type": "betaAppReviewSubmissions",
                      "relationships": {"build": {"data": {"type": "builds",
                                                           "id": build_id}}}}})
    if "data" in r:
        say(f"beta review: {r['data']['attributes'].get('betaReviewState')}")
    else:
        say(f"beta review: {r}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-gates", action="store_true")
    ap.add_argument("--no-bump", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    if not os.path.exists(KEY_PATH):
        print(f"missing API key at {KEY_PATH}")
        return 1

    if not a.skip_gates:
        print("verifying:")
        if not gates():
            print("\ngates failed, nothing shipped")
            return 1

    build = current_build() if a.no_bump else bump_build()
    print(f"\nbuild {build}:")

    say("archiving...")
    if not archive():
        say("archive failed")
        return 1

    if a.dry_run:
        say(f"dry run: archive ready at {IOS}/build/RustChap.xcarchive")
        return 0

    say("uploading...")
    if not upload():
        return 1

    say("waiting for App Store Connect to process...")
    build_id = wait_for_build(build)
    if not build_id:
        say("uploaded, but not processed yet - rerun distribution later")
        return 1

    distribute(build_id)
    print(f"\nbuild {build} is on TestFlight")
    return 0


if __name__ == "__main__":
    sys.exit(main())
