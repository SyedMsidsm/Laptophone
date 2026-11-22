# Spec: PersonalSender — V1

Status: **approved 2026-11-22** (open questions answered; see Decisions)

## Objective

A private app that moves photos, videos, any file, and text between **my Android phone** and **my Windows laptop**, in both directions, over the same Wi-Fi or a hotspot. No cloud, no accounts, no compression.

**User:** just me. One phone (Samsung Galaxy S24 Ultra, Android 17) and one laptop (Windows 11).

**User stories**

1. In the Gallery (or any app) I tap **Share → PersonalSender**, and the files arrive on my laptop at full quality.
2. On the laptop I drag files onto the PersonalSender window, and they arrive on my phone: photos and videos in the gallery, other files in Downloads.
3. I send a link or some copied text from one device, and it lands on the other device's clipboard. If it's a link, the laptop offers to open it in the browser.
4. It works on home Wi-Fi, when the laptop uses my phone's hotspot, and when the phone uses the laptop's hotspot, without typing IP addresses.
5. The laptop app is always ready: it starts with Windows, lives in the system tray and notifies me when something arrives.

## Assumptions (correct any that are wrong)

1. The app is installed on the phone straight from this laptop (USB or APK), not through the Play Store.
2. One phone is paired with one laptop. The data model allows more devices later, but the UI doesn't.
3. Both devices are on the same network: home Wi-Fi, or one device is the other's hotspot. The router does not block devices from talking to each other (some "guest" networks do).
4. Files are sent as the original bytes: same name, same format (HEIC stays HEIC), and no resizing.
5. The laptop app runs in the background all the time. The phone app is opened when needed, or left in **Stay ready** mode.

## How it works

```
 ┌──────────── Phone (Android) ───────────┐        ┌──────────── Laptop (Windows) ───────────┐
 │ UI · share target · QR scanner          │        │ UI · tray · drag-drop · notifications    │
 │ ─────────── lib/core (shared) ───────── │ HTTPS  │ ─────────── lib/core (shared) ────────── │
 │ HTTPS server + client · discovery       │◄──────►│ HTTPS server + client · discovery        │
 │ pairing · outbox · history              │  UDP   │ pairing · outbox · history               │
 └─────────────────────────────────────────┘        └──────────────────────────────────────────┘
```

- **One Flutter codebase** builds both apps. Everything that isn't UI (protocol, server, client, discovery, pairing, storage) lives in `lib/core` as pure Dart and is shared by both apps.
- **Each device runs a small HTTPS server** on TCP port `47820`. Sending means making an HTTPS request to the other device.
- **Pairing (once):** the laptop shows a QR code with its device ID, name, IP addresses, port, TLS certificate fingerprint and a one-time code. The phone scans it, connects, checks the fingerprint and sends the one-time code. Both devices then store each other plus a shared secret.
- **Security:** each device creates its own self-signed TLS certificate on first run, and every connection checks the other device's certificate against the fingerprint saved at pairing. Every request also carries the shared secret, so requests from unpaired devices get `401`. Secrets are kept in secure storage.
- **Discovery** of the paired device runs these steps, fastest first:
  1. Try the last address that worked.
  2. Try the network's gateway. This covers both hotspot setups: with the phone's hotspot, the phone is the gateway; with the Windows hotspot, the laptop is always `192.168.137.1`.
  3. Listen for and send UDP announcements (multicast + broadcast) on port `47820`.
  4. As a last resort, scan the local `/24` subnet for `GET /api/v1/info`.
- **Phone in the background:** Android stops apps that aren't on screen. Sending from the laptop to the phone therefore works in one of two ways:
  - It is delivered instantly if the phone app is open or in **Stay ready** mode. Stay ready is a foreground service with a permanent notification that you turn on or off.
  - Otherwise it waits in the laptop's **outbox** and is sent automatically the next time the phone app opens.

### Protocol (v1)

| Method & path | Auth | Purpose |
|---|---|---|
| `GET /api/v1/info` | none | ID, name, platform and app version. Used by discovery. |
| `POST /api/v1/pair` | one-time code | Exchange identity, fingerprint and shared secret |
| `POST /api/v1/transfers` | secret | Announce a batch of files `{name, size, mime, modified}` and get back a `transferId` |
| `PUT /api/v1/transfers/{id}/files/{index}` | secret | Upload one file's bytes (streamed) |
| `POST /api/v1/text` | secret | Send text or a link `{text, isUrl}` |

The receiver writes uploads to `<name>.part` and renames the file only when the byte count matches. Incoming filenames are cleaned up: no `..`, no path separators and no reserved Windows names. A file with the same name as an existing one is saved as `photo (1).jpg`.

### Where received things go

| Received on | Photos and videos | Other files | Text |
|---|---|---|---|
| Laptop | `Desktop\PersonalSender Inbox\` (resolved via the Windows Desktop known-folder, so OneDrive-redirected desktops work; can be changed) | same | copied to clipboard + notification ("Open link" button for URLs) |
| Phone | Gallery album **PersonalSender** | `Downloads/PersonalSender/` | copied to clipboard + notification + shown in history |

## Capability map

| Module ID | Responsibility | Depends on |
|---|---|---|
| `core-identity` | Device ID and name, TLS certificate, pairing, secure storage | — |
| `core-discovery` | Finding the paired device: last address, gateway check, UDP announce, subnet scan | `core-identity` |
| `core-transfer` | HTTPS server and client, file streaming, text messages, outbox, history | `core-identity`, `core-discovery` |
| `desktop-shell` | Windows window, tray, drag-drop, notifications, start at login, single instance | `core-transfer` |
| `phone-shell` | Android UI, QR scanner, share target, saving to gallery or Downloads, Stay ready service | `core-transfer` |
| `text-sync` | Sending text and clipboard both ways, opening links | `core-transfer`, both shells |

### Build order: milestones, each ending in something to try on real devices

| # | Milestone | You can try |
|---|---|---|
| M1 | Walking skeleton: project, core server and client, plain HTTP, IP typed by hand | Send a photo from the phone → it appears on the laptop |
| M2 | Pairing + TLS + auth | Scan the QR code once; the devices remember each other after restarts; an unpaired `curl` gets `401` |
| M3 | Discovery | Open both apps on Wi-Fi or either hotspot → they connect within 10 s with no IP typing |
| M4 | Both directions + saving + history + notifications | Files sent to the phone land in the gallery and Downloads; Windows notification on arrival |
| M5 | Phone share menu + laptop drag-drop, tray and start at login | Gallery → Share → PersonalSender; drag onto the window |
| M6 | Text and clipboard | Share a link from the phone → the laptop offers "Open link"; tray → "Send clipboard to phone" |
| M7 | Outbox, Stay ready, handling interrupted transfers, release builds | Send to the phone while its app is closed → it arrives when the app opens |

The detailed task breakdown (`tasks/plan.md`, `tasks/todo.md`) gets written after this spec is approved.

## Tech stack

- **Flutter 3.50 / Dart 3.14** (stable, already installed and `flutter doctor` is clean). Targets: `android`, `windows`.
- **Android:** `minSdk 29` (Android 10, needed for clean MediaStore saving) and `targetSdk 37`.
- Candidate packages (pinned to exact versions when the project is set up):

| Need | Package |
|---|---|
| HTTP server | `shelf`, `shelf_router` (client = `dart:io` `HttpClient` with certificate pinning) |
| Self-signed certificate | `basic_utils` |
| QR show / scan | `qr_flutter` / `mobile_scanner` |
| Android share target | `receive_sharing_intent` |
| Save to gallery | `gal` (Downloads via MediaStore, small Kotlin channel if needed) |
| Pick files | `file_picker` |
| Windows tray, window, drag-drop | `tray_manager`, `window_manager`, `desktop_drop` |
| Notifications | `local_notifier` (Windows), `flutter_local_notifications` (Android) |
| Start at login | `launch_at_startup` |
| Stay ready service | `flutter_foreground_task` |
| Storage | `flutter_secure_storage` (secrets), `shared_preferences` (settings + history) |
| Network info | `network_info_plus` |
| Misc | `url_launcher`, `uuid`, `crypto`, `logging` |

## Commands

```powershell
flutter pub get                               # install dependencies
flutter run -d windows                        # run laptop app (debug)
flutter run -d R5CY34L920Y                    # run phone app on the S24 Ultra over USB (debug)
flutter analyze                               # lint
dart format .                                 # format
flutter test                                  # unit + loopback integration tests
flutter test --coverage                       # with coverage (lcov in coverage/)
flutter build windows --release               # laptop release build → build\windows\x64\runner\Release\
flutter build apk --release                   # phone release APK → build\app\outputs\flutter-apk\app-release.apk
flutter install -d R5CY34L920Y --release      # install release APK on the phone
```

## Project structure

```
PersonalSender/
  SPEC.md                    → this file
  tasks/                     → plan.md, todo.md (after approval)
  lib/
    main.dart                → starts the phone or desktop app depending on platform
    core/                    → pure Dart, NO Flutter imports, shared by both apps
      protocol/              → JSON models, routes, version
      identity/              → device ID, certificate, pairing, secure storage
      discovery/             → last address, gateway check, UDP announce, subnet scan
      server/                → HTTPS server + request handlers
      client/                → HTTPS client with pinning, streamed uploads
      transfer/              → send queue, outbox, progress, receive-folder writer
      history/               → recent transfers
    phone/                   → Android screens, share target, Stay ready service, gallery saving
    desktop/                 → Windows window, tray, drag-drop, notifications, start at login
    shared_ui/               → widgets both apps use (progress, history list, device card)
  test/                      → unit tests, mirroring lib/core
  test/loopback/             → two core instances on localhost talking to each other
  android/  windows/         → platform folders (generated by flutter create)
```

## Code style

`flutter_lints` + `dart format`. Files `snake_case.dart`, classes `PascalCase`. `lib/core` never imports Flutter, so it can be unit-tested and shared. Use `logging` instead of `print`. Files are always streamed and never read whole into memory.

```dart
/// A batch of files the sender wants to deliver. Sent before any bytes.
final class TransferOffer {
  const TransferOffer({required this.senderId, required this.files});

  final String senderId;
  final List<FileMeta> files;

  Map<String, Object?> toJson() => {
        'senderId': senderId,
        'files': [for (final f in files) f.toJson()],
      };

  factory TransferOffer.fromJson(Map<String, Object?> json) => TransferOffer(
        senderId: json['senderId']! as String,
        files: [
          for (final f in json['files']! as List<Object?>)
            FileMeta.fromJson(f! as Map<String, Object?>),
        ],
      );
}
```

## Testing strategy

| Level | Tool | What |
|---|---|---|
| Unit | `flutter test` | Protocol JSON round-trips, filename cleanup (`..\..\evil.exe`), duplicate naming, token checks, fingerprint pinning, outbox queue rules |
| Loopback integration | `flutter test test/loopback` | Two `core` instances on `localhost`: pair; send a small file and a generated 500 MB file (memory stays flat, SHA-256 matches); send text; unpaired → `401`; wrong fingerprint → rejected; interrupted upload leaves no final file |
| Manual on devices | checklist in `tasks/todo.md` | Wi-Fi, phone hotspot and Windows hotspot; share from Gallery; drag-drop; tray; notifications; phone app closed → outbox |

Target: **≥ 80 % line coverage on `lib/core`**. UI code has no coverage target.

## Boundaries

- **Always:** keep `lib/core` free of Flutter imports · run `flutter analyze` and `flutter test` before each commit · stream files · clean up incoming filenames · check the other device's fingerprint on every connection.
- **Ask first:** adding a package not listed above · changing the protocol once both apps are installed · changing default save locations · anything that needs admin rights or a Windows firewall or network-profile change (you make those yourself) · adding iOS or macOS.
- **Never:** commit signing keystores, certificates or secrets · turn off TLS checks globally · accept anything from an unpaired device · send any data anywhere except the paired device (no analytics, no cloud).

## Success criteria

1. **Pairing:** scanning the laptop's QR code pairs the devices in under 30 s, and they stay paired after both apps restart.
2. **Phone → laptop:** sharing 10 photos from the Gallery puts them in `Desktop\PersonalSender Inbox\` with the original names and the same SHA-256 as the originals, plus a Windows notification.
3. **Laptop → phone:** dragging 3 files (including a 1 GB video) onto the window puts the photos and video in the gallery album *PersonalSender* and the other file in `Downloads/PersonalSender/`, all byte-identical.
4. **Speed and memory:** a 1 GB video moves at **≥ 10 MB/s** on 5 GHz Wi-Fi, and the phone app stays under **200 MB** of memory while sending.
5. **Discovery:** on home Wi-Fi, the phone's hotspot and the Windows hotspot, the devices connect within **10 s** of opening the app, with no IP typing.
6. **Text:** a link shared from the phone lands on the laptop's clipboard with an "Open link" notification. Tray → "Send clipboard to phone" lands on the phone's clipboard.
7. **Outbox:** a file sent while the phone app is closed shows as *Waiting* and is delivered within 10 s of opening the phone app.
8. **Security:** requests from an unpaired device or with a wrong secret get `401`, all traffic is TLS, and incoming filenames can't write outside the receive folder.
9. **Laptop app:** starts in the tray at Windows login, closing the window keeps it running, and opening it a second time focuses the existing window.
10. **Interruptions:** turning Wi-Fi off mid-transfer shows *Failed — Retry* on the sender, and no partial file is left under the final name.

## Risks

| Risk | What we do |
|---|---|
| Windows Firewall blocks incoming connections on **Public** networks. Phone hotspots usually count as Public. | On first run, Windows asks; allow PersonalSender on Private **and** Public. Or set the hotspot network to *Private* in Windows Settings. You do this yourself. |
| UDP discovery is unreliable on hotspots and some routers | Gateway check + last address + QR code containing the IPs + subnet scan + typing an IP by hand as a fallback |
| Android 17 may require the new local-network permission | The app asks for it on first run. Confirmed on the S24 Ultra in M1. |
| Samsung puts background apps to sleep | Stay ready uses a foreground service. Add PersonalSender to *Never sleeping apps*. The outbox covers the rest. |
| The Share menu copies large videos into the app's cache first | Delete the cache copy after sending. Check free space before accepting. |
| Android limits some foreground-service types (`dataSync` time limits) | Use the `specialUse` type. That's fine for an app installed outside the Play Store. |

## Out of scope (deferred to V2+)

- **iPhone app:** needs a Mac or a cloud build service plus an Apple developer account.
- **Auto-backup of new camera photos:** a separate background capability.
- **Continuous automatic clipboard sync:** Android blocks reading the clipboard in the background. V1 sends text by hand.
- **Resuming an interrupted file where it stopped:** V1 retries the whole file. The `.part` files leave room to add this.
- **Away from home (Tailscale or a relay server):** V1 is Wi-Fi + hotspot only.
- **Explorer right-click "Send to phone"** (Windows *SendTo* folder).
- **Sending whole folders** with their structure kept.
- **More than one phone or laptop.**
- **Thumbnail gallery of received items and history search.**
- **Global hotkey for "Send clipboard".**

## Decisions (2026-11-22)

1. **Laptop receive folder:** `Desktop\PersonalSender Inbox\`.
2. **Stay ready on the phone:** off by default; turned on by hand when you want instant laptop → phone delivery.
3. **Links received on the laptop:** notification with an **Open link** button; never opened automatically.
4. **App name and package ID:** "PersonalSender" / `com.personalsender.app`.

## Open questions

None for now. The visual design is in [design/DESIGN.md](design/DESIGN.md), with mockups on the linked design canvas.
