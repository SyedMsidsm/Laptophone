# PersonalSender V1 — Tasks

Plan: [plan.md](plan.md) · Spec: [SPEC.md](../SPEC.md) · Design: [design/DESIGN.md](../design/DESIGN.md)

Phone device ID for commands: `R5CY34L920Y`. Every task also meets the **Definition of done** in plan.md.

---

## Phase 0 · Setup

### - [x] Task 1: Create the Flutter project

**Description:**
- Run `flutter create` at the repo root for `android` and `windows`, with project name `personal_sender`.
- Set the Android `applicationId` to `com.personalsender.app`, `minSdk 29`, `targetSdk 37`, and the app label "PersonalSender".
- Add `flutter_lints`, the empty folder layout from the spec and a `.gitignore` that excludes keystores and certificates.
- Run `git init` (local only).

**Acceptance criteria:**
- [x] `flutter run -d windows` and `flutter run -d R5CY34L920Y` both show a placeholder screen named "PersonalSender".
- [x] `.gitignore` covers `*.jks`, `*.keystore`, `key.properties`, `*.pem`.

**Verification:** `flutter analyze` · `flutter test` · run on both devices.
**Result (partial):** analyze clean, test passes, Windows debug build 88 s, APK debug build 168 s, `flutter run -d windows` started (no firewall prompt seen). Phone launch retried after reconnect: app installed and started on the S24 Ultra (com.personalsender.app), no prompts reported. `material_ui: ^1.1.0` came from the generated template (`package:flutter/material.dart` is deprecated in Flutter 3.50), so it was kept.
**Dependencies:** None
**Files:** `pubspec.yaml`, `analysis_options.yaml`, `lib/main.dart`, `android/app/build.gradle.kts`, `.gitignore`
**Scope:** S

---

## Phase 1 · Walking skeleton (M1)

### - [x] Task 2: Protocol models and safe filenames

**Description:**
- Pure-Dart models: `DeviceInfo`, `FileMeta`, `TransferOffer`, `TextMessage`, with JSON round-trip.
- `safeFileName()`: strips `..`, path separators and reserved Windows names (`CON`, `NUL`…), and trims length.
- `uniqueName()`: produces `photo (1).jpg` style names.

**Acceptance criteria:**
- [x] JSON round-trip is lossless for every model.
- [x] `..\..\evil.exe`, `/etc/passwd`, `CON.txt` and empty names all come out safe.
- [x] Duplicates get ` (1)`, ` (2)`… before the extension.

**Verification:** `flutter test test/core/protocol test/core/transfer`
**Result:** 13 tests pass (4 model round-trips, 5 safeFileName, 3 uniqueName, plus the widget test); analyze clean. Dots/spaces-only names fall back to `file`; reserved names get a `_` prefix.
**Dependencies:** 1
**Files:** `lib/core/protocol/models.dart`, `lib/core/transfer/file_names.dart`, `test/core/protocol/models_test.dart`, `test/core/transfer/file_names_test.dart`
**Scope:** S

### - [x] Task 3: Core server and client streaming over HTTP

**Description:**
- `shelf` server on port 47820 with `GET /api/v1/info`, `POST /api/v1/transfers` and `PUT /api/v1/transfers/{id}/files/{i}`.
- The receiver streams to `<name>.part` and renames only when the byte count matches.
- The client streams files with progress callbacks.

**Acceptance criteria:**
- [x] Loopback test: two instances on localhost; a small file and a generated 500 MB file arrive with matching SHA-256.
- [x] Process memory stays under +100 MB during the 500 MB send, which shows it's streamed.
- [x] A short upload (connection closed early) leaves no file under the final name.

**Verification:** `flutter test test/loopback/transfer_test.dart`
**Result:** 6 loopback tests pass in ~14 s. 500 MB arrives with matching SHA-256; peak RSS growth 10.8 MB. Short upload leaves no file. Added packages from the spec list, pinned exact: shelf 1.4.3, shelf_router 1.1.5, crypto 3.0.8, logging 1.3.0. No TLS or auth yet (Tasks 5-6).
**Dependencies:** 2
**Files:** `lib/core/server/server.dart`, `lib/core/client/client.dart`, `lib/core/transfer/receiver.dart`, `test/loopback/transfer_test.dart`
**Scope:** M

### - [x] Task 4: Bare-bones apps to send a photo by typed IP

**Description:**
- Laptop: start the server, save into `Desktop\PersonalSender Inbox\` (found via the Windows Desktop known folder) and show "Listening on <ip>:47820".
- Phone: an address field, a "Pick photo" button (`file_picker`), and send with a progress line.
- Debug-only cleartext setting on Android.

**Acceptance criteria:**
- [x] A photo picked on the S24 appears in `Desktop\PersonalSender Inbox\` byte-identical, on home Wi-Fi.
- [x] Written down: whether Android 17 asked for a local-network permission, and what the Windows Firewall prompt looked like.

**Verification:** Manual, on both devices; compare SHA-256 with `Get-FileHash` on the laptop.
**Result:** Phone to laptop on home Wi-Fi: 284994.jpg (261206 bytes) arrived with the same SHA-256 as the phone copy. Findings: (1) Android 17 needs `ACCESS_LOCAL_NETWORK`; without it connections fail ("Software caused connection abort" sending, timeouts receiving). It never prompted because the app did not request it. Now declared in the manifest and granted via `adb pm grant`; a runtime request is still needed (later task). (2) Windows Firewall: no prompt seen; the auto-created `personal_sender.exe` rules covered Public only, so the Private Wi-Fi blocked inbound until the user ticked Private. Rules are per exe path. (3) Scope widened at the user request: both apps now listen and send (`lib/shared_ui/dev_transfer_screen.dart`). Phone inbox is the app cache for now. (4) The laptop inbox `DesktopPersonalSender` is the same folder as this repo; needs a decision. Also verified: laptop to phone on Wi-Fi (59959 bytes, size match) and phone hotspot (laptop on hotspot as Private; phone to laptop 284997.jpg 289572 bytes, SHA-256 matches). Phone only accepts incoming while its app is in the foreground (expected until Stay ready, Task 20). Hotspot network on the laptop must be Private too.
**Dependencies:** 3
**Files:** `lib/main.dart`, `lib/phone/dev_send_screen.dart`, `lib/desktop/dev_receive_screen.dart`, `android/app/src/main/AndroidManifest.xml`, `lib/desktop/known_folders.dart`
**Scope:** M

### Checkpoint A — after Tasks 1–4
- [ ] `flutter analyze` clean, `flutter test` green
- [ ] Phone → laptop photo works on real devices
- [ ] Android permission and firewall findings recorded in plan.md Risks
- [ ] **Review with you before continuing**

---

## Phase 2 · Pairing and security (M2)

### - [ ] Task 5: Device identity and pinned TLS (spike first)

**Description:**
- Spike: generate an EC P-256 self-signed certificate on the phone and time it. Do one pinned HTTPS request in each direction.
- Then build `DeviceIdentity` (UUID, name, certificate, key in secure storage).
- Switch server and client to HTTPS with SHA-256 fingerprint pinning, and remove cleartext.

**Acceptance criteria:**
- [ ] Certificate generation takes < 3 s on the S24 and happens only once (it survives restarts).
- [ ] Loopback: the correct fingerprint connects, a wrong fingerprint is rejected.
- [ ] Android cleartext setting removed.

**Verification:** `flutter test test/loopback/tls_test.dart` · manual timing on the phone
**Dependencies:** 4
**Files:** `lib/core/identity/identity.dart`, `lib/core/identity/certificate.dart`, `lib/core/server/server.dart`, `lib/core/client/client.dart`, `test/loopback/tls_test.dart`
**Scope:** M

### - [ ] Task 6: Pairing protocol and auth

**Description:**
- `POST /api/v1/pair` with a single-use 6-digit code; it exchanges identity, fingerprint and a 32-byte shared secret.
- Auth middleware on every route except `/info` and `/pair`.
- `PairedDeviceStore` keeps the paired device, its fingerprint and the last good address.

**Acceptance criteria:**
- [ ] Loopback: pairing succeeds once; reusing the code fails.
- [ ] No token or a wrong secret → `401` on transfers and text routes.
- [ ] The paired device survives a restart (store reload test).

**Verification:** `flutter test test/loopback/pairing_test.dart test/core/storage`
**Dependencies:** 5
**Files:** `lib/core/pairing/pairing.dart`, `lib/core/storage/paired_store.dart`, `lib/core/server/server.dart`, `test/loopback/pairing_test.dart`
**Scope:** M

### - [ ] Task 7: Pairing screens

**Description:**
- Laptop **Pair phone** window: QR code (`qr_flutter`) with id, name, IPs, port, fingerprint and code, plus the "Can't scan?" address and code.
- Phone **Pair** screen: `mobile_scanner`, with camera permission asked on tap.
- Phone **Enter code instead** form with the wrong-code state.
- Plain styling for now (the theme comes in Task 10).

**Acceptance criteria:**
- [ ] Scanning pairs in < 30 s, and both apps remember each other after restart (spec criterion 1).
- [ ] The manual address + code path also pairs. A wrong code shows the error text from DESIGN.md.

**Verification:** Manual on both devices · `curl -k https://<laptop-ip>:47820/api/v1/transfers` from a third device or the laptop → `401`
**Dependencies:** 6
**Files:** `lib/desktop/pair_window.dart`, `lib/phone/pair_screen.dart`, `lib/phone/enter_code_screen.dart`, `android/app/src/main/AndroidManifest.xml`
**Scope:** M

### Checkpoint B — after Tasks 5–7
- [ ] All traffic is TLS. Unpaired requests get `401` (spec criterion 8, first half).
- [ ] Protocol contract frozen; parallel UI work is now safe (see plan.md)
- [ ] **Review with you**

---

## Phase 3 · Discovery (M3)

### - [ ] Task 8: Discovery without UDP

**Description:**
- `DiscoveryService` emits `connected / looking / offline`. It tries, in order: last good address → network gateway → `/24` subnet scan of `/api/v1/info`, matching the paired fingerprint.
- Re-checks every 5 s while looking and every 30 s while connected.

**Acceptance criteria:**
- [ ] Unit tests with a fake prober: correct order, stops at the first match, ignores devices with the wrong fingerprint.
- [ ] Subnet scan finishes in < 4 s (parallel probes, 300 ms timeout).
- [ ] Network type is reported as Wi-Fi / phone hotspot / laptop hotspot, never the Wi-Fi name.

**Verification:** `flutter test test/core/discovery`
**Dependencies:** 6
**Files:** `lib/core/discovery/discovery.dart`, `lib/core/discovery/gateway.dart`, `lib/core/discovery/subnet_scan.dart`, `test/core/discovery/discovery_test.dart`
**Scope:** M

### - [ ] Task 9: UDP announce and Android multicast lock

**Description:**
- Both apps send a small signed "hello" (id + port) by multicast and broadcast on UDP 47820, and listen for the other.
- On Android, a Kotlin method channel holds a `WifiManager.MulticastLock` while the app is open.
- A heard hello feeds `DiscoveryService`.

**Acceptance criteria:**
- [ ] With both apps open, they connect within 10 s on home Wi-Fi, the phone's hotspot and the Windows hotspot (spec criterion 5).
- [ ] Works with UDP blocked too (falls back to Task 8), just slower.

**Verification:** Manual test of all three network setups on real devices; results written in todo.md
**Dependencies:** 8
**Files:** `lib/core/discovery/udp_announce.dart`, `android/app/src/main/kotlin/com/personalsender/app/MainActivity.kt`, `lib/phone/multicast_lock.dart`
**Scope:** M

### Checkpoint C — after Tasks 8–9
- [ ] All three network setups pass
- [ ] **Review with you**

---

## Phase 4 · Look and both directions (M4)

### - [ ] Task 10: Theme, tokens and fonts

**Description:**
- Turn DESIGN.md tokens into code: light and dark `ColorScheme` for each app, a `DeviceColors` `ThemeExtension`, and type styles including Archivo `wdth 125`.
- Bundle Archivo + Roboto Mono. **Ask before downloading the font files.**

**Acceptance criteria:**
- [ ] A widget test pumps both apps' themes in light and dark without errors.
- [ ] A test asserts the key contrast pairs from DESIGN.md are ≥ 4.5 : 1.
- [ ] No runtime font fetching.

**Verification:** `flutter test test/shared_ui/theme_test.dart`
**Dependencies:** 1
**Files:** `lib/shared_ui/tokens.dart`, `lib/shared_ui/theme.dart`, `pubspec.yaml`, `assets/fonts/*`, `test/shared_ui/theme_test.dart`
**Scope:** S

### - [ ] Task 11: Connection line widget

**Description:** `LinkIndicator(state, network)`: two device badges and a half-orange, half-blue line, with solid, dashed and broken states and a network chip. The dashes drift only when animations are allowed. `Semantics` label = the status sentence.

**Acceptance criteria:**
- [ ] Widget tests: each state renders, the semantics label is right, and there's no animation when `disableAnimations` is true.
- [ ] Golden images for the 3 states (light + dark).

**Verification:** `flutter test test/shared_ui/link_indicator_test.dart`
**Dependencies:** 10
**Files:** `lib/shared_ui/link_indicator.dart`, `test/shared_ui/link_indicator_test.dart`
**Scope:** S

### - [ ] Task 12: Phone Home screen

**Description:**
- Home as drawn: orange band, connection card fed by `DiscoveryService`, and Stay ready row (switch disabled until Task 20).
- "Today" activity list from a new `HistoryStore`.
- Send photos & videos (system photo picker) and Send files. "Send copied text" stays hidden until Task 18.
- Send buttons are disabled with an explanation when offline.

**Acceptance criteria:**
- [ ] Sending photos and files from Home works, and items appear in Today with the phone-orange tile.
- [ ] Offline state matches the design: disabled buttons, Try again.
- [ ] Usable at 200 % font size without clipping.

**Verification:** `flutter test test/core/history test/phone` · manual on the S24
**Dependencies:** 7, 9, 11
**Files:** `lib/phone/home_screen.dart`, `lib/shared_ui/activity_row.dart`, `lib/core/history/history_store.dart`, `test/core/history/history_store_test.dart`
**Scope:** M

### - [ ] Task 13: Laptop main window

**Description:**
- Main window as drawn: blue band, connection pill, and drop zone (`desktop_drop`) with the drag-over state and count badge.
- Choose files… (Ctrl+O), the Activity list, and Open received folder.
- Keyboard focus order as in DESIGN.md.

**Acceptance criteria:**
- [ ] Dragging 3 files onto the window sends them to the phone, with progress in Activity.
- [ ] Everything works keyboard-only.
- [ ] Below 760 px wide, Activity stacks under the drop zone.

**Verification:** Manual on Windows · `flutter test test/desktop`
**Dependencies:** 7, 9, 11
**Files:** `lib/desktop/main_window.dart`, `lib/desktop/drop_zone.dart`, `lib/desktop/shortcuts.dart`, `test/desktop/main_window_test.dart`
**Scope:** M

### - [ ] Task 14: Saving on the phone and arrival notifications

**Description:**
- Phone: photos and videos go to the Gallery album "PersonalSender" (`gal`). Other files go to `Downloads/PersonalSender/` via a Kotlin MediaStore channel.
- Notifications on both apps for arrivals, with the actions from DESIGN.md (Show in Gallery / Open folder).

**Acceptance criteria:**
- [ ] Laptop → phone: 2 photos, a 1 GB video and a PDF all land in the right places, byte-identical (spec criterion 3).
- [ ] Phone → laptop: 10 photos arrive with a Windows notification (spec criterion 2).
- [ ] 1 GB moves at ≥ 10 MB/s on 5 GHz; phone memory stays < 200 MB (spec criterion 4). Numbers written down.

**Verification:** Manual on both devices, with SHA-256 checks
**Dependencies:** 12, 13
**Files:** `lib/phone/media_saver.dart`, `android/app/src/main/kotlin/com/personalsender/app/MediaStoreChannel.kt`, `lib/phone/notifications.dart`, `lib/desktop/notifications.dart`
**Scope:** M

### Checkpoint D — after Tasks 10–14
- [ ] Spec criteria 2, 3, 4 measured and passing
- [ ] Home and Main look like the canvas in light and dark
- [ ] **Review with you**

---

## Phase 5 · Platform integration (M5)

### - [ ] Task 15: Phone share menu and share sheet

**Description:**
- Intent filters for `SEND` / `SEND_MULTIPLE` (any type, plus text) via `receive_sharing_intent`.
- A share sheet that opens straight into sending, with sending / done / offline states and a big percentage.
- Swiping the sheet away keeps sending. The cache copy is deleted after sending, and free space is checked first.

**Acceptance criteria:**
- [ ] Gallery → Share → PersonalSender sends 4 photos, shows progress, then Done.
- [ ] Offline shows Try again; Cancel stops cleanly.
- [ ] No leftover files in the app cache after sending.

**Verification:** Manual on the S24
**Dependencies:** 14
**Files:** `android/app/src/main/AndroidManifest.xml`, `lib/phone/share_intake.dart`, `lib/phone/share_sheet.dart`
**Scope:** M

### - [ ] Task 16: Tray, close to tray, single instance, start at login

**Description:**
- `tray_manager` menu with the exact items in DESIGN.md.
- Closing the window hides it to the tray.
- A second launch focuses the existing window.
- `launch_at_startup` starts the app hidden in the tray.

**Acceptance criteria:**
- [ ] After a reboot, PersonalSender is in the tray and the phone can send to it (spec criterion 9).
- [ ] Every tray item works. Quit really exits.

**Verification:** Manual on Windows, including a reboot
**Dependencies:** 13
**Files:** `lib/desktop/tray.dart`, `lib/desktop/window_lifecycle.dart`, `lib/main.dart`, `windows/runner/main.cpp`
**Scope:** M

### - [ ] Task 17: Settings on both apps

**Description:**
- Phone settings: paired laptop, Unpair (with confirm), Stay ready (wired in Task 20), save locations, copy received text, name, connection details, version.
- Laptop settings: receive folder Open / Change…, notifications toggle, copy text toggle, Unpair…, firewall tip, start with Windows.

**Acceptance criteria:**
- [ ] Every setting persists across restarts and changes behaviour.
- [ ] Unpair asks for confirmation, forgets the device on both sides and returns to the Pair screen.

**Verification:** `flutter test test/core/storage/settings_test.dart` · manual on both devices
**Dependencies:** 12, 13
**Files:** `lib/core/storage/settings.dart`, `lib/phone/settings_screen.dart`, `lib/desktop/settings_window.dart`, `test/core/storage/settings_test.dart`
**Scope:** M

### Checkpoint E — after Tasks 15–17
- [ ] Share from Gallery, tray and start at login all work
- [ ] **Review with you**

---

## Phase 6 · Text (M6)

### - [ ] Task 18: Text and links both ways

**Description:**
- `POST /api/v1/text`.
- Phone: "Send copied text" button, and shared text goes through the share sheet.
- Laptop: Send clipboard (button, Ctrl+V, tray).
- On arrival: copy to clipboard (if enabled) and notify. Links get **Open link**. Notifications show only the domain and never the contents of text.

**Acceptance criteria:**
- [ ] A link shared from the phone lands on the laptop clipboard with an "Open link" notification (spec criterion 6).
- [ ] Tray → Send clipboard to phone lands on the phone clipboard.
- [ ] Unit tests: URL detection, domain extraction, endpoint auth.

**Verification:** `flutter test test/core/protocol/text_test.dart test/loopback/text_test.dart` · manual
**Dependencies:** 15, 16
**Files:** `lib/core/server/text_route.dart`, `lib/core/protocol/links.dart`, `lib/phone/home_screen.dart`, `lib/desktop/main_window.dart`, `test/loopback/text_test.dart`
**Scope:** M

---

## Phase 7 · Reliability and release (M7)

### - [ ] Task 19: Laptop outbox

**Description:**
- Sends to an unreachable phone go into a persisted outbox. Rows show *Waiting for phone* with Cancel.
- Delivered automatically when discovery reports the phone connected.

**Acceptance criteria:**
- [ ] Sending while the phone app is closed shows Waiting; it delivers within 10 s of opening the phone app (spec criterion 7).
- [ ] The outbox survives a laptop app restart. Cancel removes the item.

**Verification:** `flutter test test/core/transfer/outbox_test.dart` · manual
**Dependencies:** 14
**Files:** `lib/core/transfer/outbox.dart`, `test/core/transfer/outbox_test.dart`, `lib/desktop/main_window.dart`
**Scope:** S

### - [ ] Task 20: Phone Stay ready

**Description:**
- `flutter_foreground_task` with the `specialUse` type keeps the server running while Stay ready is on.
- Ongoing notification with Turn off.
- The switch on Home and in Settings is wired up.
- One-time hint to add the app to Samsung's *Never sleeping apps*.

**Acceptance criteria:**
- [ ] With Stay ready on and the app closed, a file from the laptop arrives instantly.
- [ ] Turning it off stops the service and removes the notification.

**Verification:** Manual on the S24, including after 30 min with the screen off
**Dependencies:** 17, 19
**Files:** `lib/phone/stay_ready_service.dart`, `android/app/src/main/AndroidManifest.xml`, `lib/phone/home_screen.dart`
**Scope:** S

### - [ ] Task 21: Interrupted transfers and Retry

**Description:**
- Connection drops mark the item *Not sent · reason* on the sender, with **Retry** (whole file).
- The receiver deletes stale `.part` files on start and after 10 min of no data.

**Acceptance criteria:**
- [ ] Turning Wi-Fi off mid-transfer shows Not sent + Retry, and no partial file keeps the final name (spec criterion 10).
- [ ] Retry completes after Wi-Fi returns.
- [ ] Loopback test that kills the connection mid-stream.

**Verification:** `flutter test test/loopback/interrupt_test.dart` · manual
**Dependencies:** 14
**Files:** `lib/core/transfer/receiver.dart`, `lib/core/client/client.dart`, `lib/shared_ui/activity_row.dart`, `test/loopback/interrupt_test.dart`
**Scope:** M

### - [ ] Task 22: Phone All activity screen

**Description:** "See all" opens the full history, with filter chips (All / Sent / Received / Not sent), day groups and Retry on failed items.

**Acceptance criteria:**
- [ ] Filters show the right items.
- [ ] Day grouping is correct across midnight (unit test on the grouping function).
- [ ] Retry works from here.

**Verification:** `flutter test test/phone/activity_groups_test.dart` · manual
**Dependencies:** 21
**Files:** `lib/phone/activity_screen.dart`, `lib/core/history/grouping.dart`, `test/phone/activity_groups_test.dart`
**Scope:** S

### - [ ] Task 23: App icon and release builds

**Description:**
- Android adaptive icon (background + foreground + monochrome) and Windows `.ico` (16–256), from DESIGN.md.
- Release-sign the APK with a local keystore kept outside the repo.
- Build both release versions and install them.

**Acceptance criteria:**
- [ ] The icon looks right on the S24 home screen (themed icons on and off) and in the Windows taskbar and tray.
- [ ] The release APK is installed on the phone, and the release `.exe` runs and starts at login.
- [ ] `git status` shows no keystore or `key.properties`.

**Verification:** `flutter build apk --release` · `flutter build windows --release` · `flutter install -d R5CY34L920Y --release`
**Dependencies:** 16
**Files:** `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`, `android/app/src/main/res/drawable/*`, `windows/runner/resources/app_icon.ico`, `android/app/build.gradle.kts`
**Scope:** M

### Final checkpoint — after Tasks 18–23
- [ ] All 10 success criteria in SPEC.md pass on the real devices
- [ ] DESIGN.md accessibility checklist done: 200 % text, TalkBack spot check, keyboard-only laptop, animations off, dark mode
- [ ] `lib/core` coverage ≥ 80 %
- [ ] **Review with you, then V1 is done**
