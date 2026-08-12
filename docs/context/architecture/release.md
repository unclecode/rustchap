---
title: Signing, release, and TestFlight distribution
status: shipped
sources:
  - tools/release-testflight.py
  - apps/ios/build/ExportOptions.plist
  - .github/workflows/ci.yml
related:
  - architecture/ios-app.md
  - roadmap/build-order.md
---

# Signing, release, and TestFlight distribution

One command ships a build:

```
python3 tools/release-testflight.py
```

It verifies, bumps `CURRENT_PROJECT_VERSION`, archives, uploads, waits for App
Store Connect to process, adds the build to every external group, and submits it
for beta review. No Xcode UI, no browser, no Apple ID session.

## Why it does not use Xcode (2026-08-08)

Builds 1-4 were signed by **Xcode cloud signing**: with a live Apple ID session
on the paid team, Xcode asks Apple to sign server-side and the distribution
certificate never lands in the local keychain. On 2026-08-08 that session had
lapsed, and the Xcode account showed only a **Personal Team** for
`unclecode@kidocode.com`, which cannot sign for distribution at all. Uploads
failed with:

```
error: exportArchive Cloud signing permission error
error: exportArchive No signing certificate "iOS Distribution" found
```

Two wrong diagnoses came first, both worth remembering. Re-authenticating Xcode
was proposed before checking whether the certificate it produced actually
existed. Then the API key's role was upgraded, which did not help either: **an
API key cannot do cloud signing**, no matter its role. `security find-identity`
and `GET /v1/certificates` answered it in two minutes — the account had only
Developer ID (Mac) and Development certificates, and no distribution certificate
had ever existed.

The fix was to stop depending on Xcode's account state and own the certificate.

## The signing material (created once, 2026-08-08)

| What | Where | Detail |
| --- | --- | --- |
| API key | `~/.appstoreconnect/private_keys/AuthKey_RWQT453LQJ.p8` | `rustchap-ci`, **App Manager** |
| Private key + CSR | `~/.appstoreconnect/signing/rustchap-dist.{key,csr}` | generated with `openssl req` |
| Certificate | `~/.appstoreconnect/signing/rustchap-dist.{cer,pem,p12}` | id `LXNQDBSB4S`, expires **2027-08-08** |
| Keychain identity | login keychain | `Apple Distribution: HOSSEIN TOHIDI (TPP52TWEWR)` |
| Profile | `~/Library/MobileDevice/Provisioning Profiles/` | `RustChap AppStore`, `IOS_APP_STORE` |

The certificate was created by POSTing the CSR to `/v1/certificates` with
`certificateType: DISTRIBUTION`, and the profile by POSTing to `/v1/profiles`
tying that certificate to the `dev.rustchap.RustChap` bundle id.

**Back up `~/.appstoreconnect/signing/`.** Losing the private key means repeating
all of it; the `.p8` API key cannot be downloaded twice either.

**Gotcha:** OpenSSL 3's default `pkcs12 -export` produces a container macOS
`security` refuses with *"MAC verification failed"*. It needs the legacy
algorithms:

```
openssl pkcs12 -export -inkey k.key -in c.pem -out c.p12 -passout pass:… \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
```

`apps/ios/build/ExportOptions.plist` now uses `signingStyle: manual` with
`signingCertificate: Apple Distribution` and the named profile. Automatic signing
would send it back to needing an Apple ID session.

## Internal versus external groups

This is the distinction that repeatedly caused confusion:

- **Core Testers (internal)** receive every build the moment it validates. No
  beta review. Members must be **App Store Connect team users** — an internal
  group is not a list you can add arbitrary emails to. Adding a build to an
  internal group over the API returns `422 Builds cannot be assigned to this
  internal group`, which means "unnecessary", not "failed".
- **Friends (external)** needs each build **added to the group** *and*
  **submitted for beta review**. Miss the submission and the build sits on
  *Ready to Submit* forever, visible in the group but uninstallable. Both steps
  are automated in `distribute()`.

Testers stayed external by decision (2026-08-08): making them internal would
require inviting them as App Store Connect users, and Apple has no
TestFlight-only role — the lightest eligible role still exposes every app and
build on the account. A per-build beta review is the cheaper cost.

## App Store submission (separate track)

TestFlight and the public release are independent. Version 0.1 has been
`WAITING_FOR_REVIEW` carrying **build 3** since 2026-08-05, with manual release.
Swapping the build resets the queue position — that was measured when build 2 was
swapped for build 3 — so the submission is deliberately left alone and the
newer content ships as an update after approval.
