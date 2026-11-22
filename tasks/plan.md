# Implementation Plan: PersonalSender V1

Source spec: [SPEC.md](../SPEC.md) · Design: [design/DESIGN.md](../design/DESIGN.md) · Tasks: [tasks/todo.md](todo.md)

## Overview

One Flutter codebase builds an Android app (Galaxy S24 Ultra) and a Windows app. Each runs a small HTTPS server on port 47820. Phone and laptop pair once with a QR code, then find each other on Wi-Fi or either hotspot. They send files and text in both directions, at full quality, with no cloud.

The build follows the spec's milestones M1–M7. Each task is a thin vertical slice that leaves something you can try on the real devices.

## Architecture decisions

| Decision | Why |
|---|---|
| Flutter project lives at the repo root (`lib/`, `android/`, `windows/`, `test/`). Project name `personal_sender`, Android `applicationId` set by hand to `com.personalsender.app`. | Matches the spec's layout. `flutter create` alone can't give that exact ID with a good Dart package name. |
| `lib/core/` is pure Dart with **no Flutter imports**. Platform work (gallery, MediaStore, multicast lock, notifications) lives in `lib/phone/` and `lib/desktop/`. | Core can be tested with two instances on localhost in one test process, and it's shared by both apps. |
| Plain HTTP only in M1 (Tasks 3–4), replaced by HTTPS + pinning in Task 5. | Get bytes moving on real devices first. The risky TLS work comes immediately after, before anything else is built on top. |
| TLS: per-device self-signed **EC P-256** certificate (via `basic_utils`), served with `dart:io` `SecurityContext`. The client pins the peer's SHA-256 fingerprint in `badCertificateCallback`. RSA-2048 as fallback. | EC keys generate fast on a phone. Pinning means no certificate authority is needed. |
| Auth: a shared secret from pairing, sent as a bearer token over TLS. `/info` and `/pair` are the only open routes. | Simple and enough on top of pinned TLS. |
| State: plain `ChangeNotifier` / `ValueNotifier` + `ListenableBuilder`. No state-management package. | A small app; fewer dependencies to approve. |
| Storage: `flutter_secure_storage` for the private key and shared secret; `shared_preferences` (JSON) for settings, paired device, last address, history (last 500 items) and the outbox index. | No database needed at this size. |
| Fonts **Archivo** (variable) and **Roboto Mono** are bundled as assets, never fetched at runtime. | The spec's "no data to anyone but the paired device" rules out `google_fonts` fetching from Google. |
| Each app gets its own `ColorScheme` (phone orange / laptop blue) + a shared `DeviceColors` theme extension. | Straight from DESIGN.md. |

## Phases (detail and acceptance checks in [todo.md](todo.md))

| Phase | Tasks | Ends with |
|---|---|---|
| 0 · Setup | 1 | Empty apps run on the phone and on Windows |
| 1 · Walking skeleton (M1) | 2–4 | **Checkpoint A:** a photo goes phone → laptop by typed IP |
| 2 · Pairing + security (M2) | 5–7 | **Checkpoint B:** QR pairing, TLS, unpaired requests get 401 |
| 3 · Discovery (M3) | 8–9 | **Checkpoint C:** auto-connect on Wi-Fi + both hotspots within 10 s |
| 4 · Look + both directions (M4) | 10–14 | **Checkpoint D:** designed Home and Main screens; files both ways land in the right places with notifications |
| 5 · Platform integration (M5) | 15–17 | **Checkpoint E:** share from Gallery, tray, start at login, settings |
| 6 · Text (M6) | 18 | Text and links both ways |
| 7 · Reliability + release (M7) | 19–23 | **Final checkpoint:** all 10 spec success criteria + accessibility checklist |

### What can run in parallel

Safe in separate sessions only **after Checkpoint B**, because the protocol and pairing contract are stable by then:
- Phone UI tasks (12, 15, 20, 22) alongside laptop UI tasks (13, 16).
- Task 10 (theme) can start any time after Task 1. Tasks 12 and 13 need it.

Must stay in order:
- Tasks 2 → 3 → 5 → 6: they all change the core server, client and protocol.
- Task 8 → 9: they change the same discovery service.

## Definition of done (every task)

- `flutter analyze` is clean and `flutter test` passes.
- `lib/core` has no Flutter imports. Files are streamed, never read whole into memory.
- New core logic has tests. `lib/core` coverage stays ≥ 80 % (`flutter test --coverage`).
- The task's manual check was done on the real phone and/or laptop where it says so, and the result was written down.
- No secrets, keystores or certificates in the repo.
- Anything new from the spec's **Ask first** list was approved: new packages beyond the spec's list, protocol changes, firewall/admin changes, save locations.

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Android 17 blocks local-network access without a new permission | High | Found out on day one in Task 4 on the S24. If needed, add the permission request before anything else. |
| Self-signed TLS + pinning misbehaves on Android or Windows `dart:io` | High | Task 5 is a spike first: generate a cert on the phone, time it (< 3 s) and do one pinned request each way. Fallback is RSA-2048, generated once and stored. |
| Windows Firewall blocks inbound on Public networks (phone hotspot) | Medium | First-run prompt: you allow Private + Public. The settings tip covers the rest. Checked in Task 4 and Checkpoint C. |
| UDP multicast unreliable on hotspots; Android needs a MulticastLock | Medium | Gateway check, last address and subnet scan (Task 8) work without UDP. UDP (Task 9) only speeds things up. |
| Samsung puts the phone app to sleep | Medium | Laptop outbox (Task 19) + Stay ready foreground service (Task 20) + "never sleeping apps" hint. |
| Writing to Downloads via MediaStore needs native code | Medium | Small Kotlin method channel in Task 14. Photos and videos use the `gal` package. |
| Share intent copies big videos into cache first | Low | Stream from the cache copy and delete it after sending. Check free space first (Task 15). |
| M1 plain HTTP needs cleartext allowed on Android | Low | Debug-only setting, removed in Task 5. |

## Open questions

1. **Git:** Task 1 runs `git init` locally (no remote, no pushing). Commits happen only when you ask. OK?
2. **Fonts:** Task 10 needs Archivo (variable) and Roboto Mono `.ttf` files from the official Google Fonts GitHub repo (open licence, together about 1 MB). I'll ask before downloading them.
3. **Release signing:** Task 23 creates a local Android keystore outside the repo. Where would you like it kept (default `%USERPROFILE%\.personalsender\release.jks`)?
