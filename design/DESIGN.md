# PersonalSender — Design V1

Visual mockups: [PersonalSender Design canvas](https://claude.ai/artifact/FFoSYQ2oYWqEacERG54H63) (private to you).
Product requirements: [SPEC.md](../SPEC.md).

## Direction: bold and colourful

- **Job of the app:** move something across the gap between phone and laptop, then get out of the way.
- **Big idea: each device owns a colour.** The phone is **orange**, the laptop is **blue**, on both apps.
  - Each app is led by its own device's colour: a coloured band at the top and coloured main buttons.
  - Everything in Activity shows the colour of the device it **came from**, so you can see at a glance what you sent and what you received.
- **Signature: the connection line.** The two device badges, joined by a thick line that is half orange, half blue.
  - Connected: solid. Looking: dashed. Not reachable: broken and grey.
  - A heading beside it always names the state.
- **App icon** repeats the idea: an orange half and a blue half joined by a white line.
- **Headings and big numbers** use **Archivo Expanded** (heavy, wide, like a parcel label). All other text uses the system font for readability.

## Platform approach

| | Phone (Android) | Laptop (Windows 11) |
|---|---|---|
| Components | Material 3 (`useMaterial3: true`) | Windows 11 look: 32 px buttons, 6 px radius, 40×20 toggles, Segoe UI Variable |
| Navigation | Home → All activity, Settings (no bottom bar: one real destination) | One main window + Settings window + Pair window; every command also in the tray menu |
| Top band | Phone orange, behind the app bar and the top of the connection card | Laptop blue, the title bar and header |
| Main actions | Bottom of the screen, within thumb reach | Inside the drop zone, plus keyboard shortcuts |
| Theme | Follows system light/dark; no in-app switch | Same |

## Tokens

| Role | Light | Dark | Use | Contrast |
|---|---|---|---|---|
| background | `#F5F6F8` | `#0E1014` | Screen / window | — |
| surface | `#FFFFFF` | `#171A1F` | Cards, lists, sheets | — |
| surface2 | `#EDEFF2` | `#20242B` | Tracks, neutral tiles | — |
| line | `#D5D9E0` | `#2F343D` | Dividers (decorative) | — |
| ink | `#15171C` | `#ECEEF2` | Text | 17.9 / 15.0 : 1 |
| ink2 | `#575E6B` | `#A2A9B6` | Secondary text, switch outlines | 6.5 / 7.4 : 1 |
| phone | `#C2410C` | `#FF8F57` | Phone buttons, phone badge, phone half of the line, phone-origin icons | white on it 5.2 : 1 · `#1B0B02` on dark 8.5 : 1 |
| phoneBand | `#C2410C` | `#7C2D12` | Phone app's top band | white on it 5.2 / 9.4 : 1 |
| phoneSoft | `#FFE7D6` | `#3B2015` | Tonal buttons, phone-origin tiles | text `#7C2D12` 7.9 : 1 · `#FFC3A1` 9.7 : 1 |
| laptop | `#1D4ED8` | `#8AB0FF` | Laptop buttons, laptop badge, laptop half of the line, laptop-origin icons | white on it 6.7 : 1 · `#0A1530` on dark 8.4 : 1 |
| laptopBand | `#1D4ED8` | `#1E3A8A` | Laptop app's top band | white on it 6.7 / 10.4 : 1 · secondary `#E1E9FF` 5.5 : 1 / `#C7D7FF` 7.2 : 1 |
| laptopSoft | `#E1E9FF` | `#172554` | Tonal buttons, laptop-origin tiles, drop-zone highlight | text `#1E3A8A` 8.5 : 1 · `#C7D7FF` 10.2 : 1 |
| danger | `#BE123C` | `#FF7A93` | Failures and Unpair only, always with icon or word | 6.3 / 7.0 : 1 |
| dangerSoft | `#FFE4EA` | `#3A1520` | Failed-item tile | — |

Rules:
- **Never** put orange text on phoneSoft (4.4 : 1 fails) or pale-orange text on the orange band (4.4 : 1 fails). Use `#7C2D12` text on phoneSoft, and white on the band.
- **Never** put blue directly on orange (1.3 : 1). Device badges always sit on a white or surface background.
- Waiting = grey + clock. Finished = grey + check. No warning colour exists any more.
- Flutter mapping:
  - Each app gets its own `ColorScheme`. The phone app uses `primary: phone, primaryContainer: phoneSoft, onPrimaryContainer: #7C2D12`; the laptop app uses `primary: laptop, primaryContainer: laptopSoft, onPrimaryContainer: #1E3A8A`.
  - Both share `surface`, `onSurface: ink`, `onSurfaceVariant: ink2`, `outlineVariant: line` and `error: danger`.
  - A shared `ThemeExtension<DeviceColors>` holds both devices' colours for badges, tiles and the line.

### Type

| Style | Font | Size/line · weight |
|---|---|---|
| Display: screen titles, "Connected", drop-zone heading | Archivo, `wdth 125` | 30/36, 24/30, 22/28 · 800 |
| Section heading ("Today", "Activity") | Archivo, `wdth 125` | 18/24 phone, 15/20 laptop · 800 |
| Big number (share progress) | Archivo, `wdth 125` | 40/44 · 800 |
| Phone body / main button / supporting | Roboto | 16/22 · 400 / 17 · 700 / 13/18 · 400 |
| Laptop body / button / caption | Segoe UI Variable | 14/20 · 400 / 14 · 600 / 12/16 · 400 |
| Data: sizes, speeds, addresses, codes | Roboto Mono | 12 phone / 11 laptop; 18–22 in code fields |

- Bundle **Archivo** (variable, open licence) and **Roboto Mono** as assets. Wide headings: `TextStyle(fontFamily: 'Archivo', fontWeight: FontWeight.w800, fontVariations: [FontVariation('wdth', 125)])`.
- Archivo is for headings and numbers only, never body text or buttons.
- Never clamp `TextScaler`. Layouts must survive 200 % text: rows grow; the laptop window stacks Activity under the drop zone below 760 px wide; long display headings wrap.

### Shape and spacing

- Phone: cards 22–28 radius, sheet 32, pill buttons. 16 px side margins. 60 px main button, 52 px secondary, 64 px device badges.
- Laptop: window 8 radius, cards 14, buttons 6. 24 px window padding. 32 px buttons, 36 px in the drop zone, 44 px badges.

## Components → Flutter

| Element | Build with |
|---|---|
| Connection line | Custom `LinkIndicator(state: connected / looking / offline)`. The two halves come from `DeviceColors`, 4 px thick, with the network chip in the middle. `Semantics(label:)` = the status sentence. Dashes drift only when `MediaQuery.disableAnimationsOf(context)` is false. |
| Network label | "Wi-Fi", "phone hotspot", "laptop hotspot". **Never the network name**: Android needs location permission to read it. |
| Top band | A coloured `Container` behind the app bar. The connection card overlaps its bottom edge. The status bar icons stay light on the band. |
| Send buttons (phone) | `FilledButton` (60 high, phone colour) + 2× `FilledButton.tonal` (52 high) in a bottom area. All disabled with the explanation in the card when the laptop isn't reachable. |
| Share sheet | `showModalBottomSheet(showDragHandle: true)` with a mini connection line, big Archivo percentage, a 12 px determinate bar, and "2 of 4 · 18.4 of 41.0 MB · 12 MB/s". Swiping it away **keeps sending** (progress continues in the notification); **Cancel** stops. The done state waits for **Done**, with no auto-close. |
| Activity rows | Tile coloured by origin device (phoneSoft/phone or laptopSoft/laptop), name, "direction arrow · To/From … · size · time". Failed rows: dangerSoft tile, rose text, tinted row, **Retry**. Batches collapse to "4 photos". |
| All activity (phone) | `FilterChip` row: All / Sent / Received / Not sent, 40 px high. Groups by day ("Today", "Yesterday", "Monday 18 November"). |
| Enter code instead | Two `TextField`s with visible labels: address (`TextInputType.numberWithOptions(decimal: true)`) and 6-digit code (`TextInputType.number`, grouped "482 913"). Wrong code: rose border + "That code didn't work. Check the 6 digits on the laptop and try again." |
| Switches | M3 `Switch` in phone orange; Windows-style toggle in laptop blue with "On/Off" label. The whole row toggles. |
| Drop zone (laptop) | `desktop_drop` `DropTarget`. Idle: 3 px dashed blue. Drag-over: solid blue border, laptopSoft fill, orange phone badge with a blue count badge, "Drop to send 3 items". Still accepts drops when the phone is offline (outbox). |
| Tray menu | `tray_manager`, in this order: two-colour status line · Open PersonalSender · Send files… (Ctrl+O) · Send clipboard to phone · — · Open received folder · Pair phone… · Settings · — · Quit PersonalSender |
| Windows notifications | `local_notifier`: "4 photos from Galaxy S24 Ultra / Saved to Desktop › PersonalSender. / [Open folder]", "Link from … / github.com · Copied to clipboard. / [Open link]", "Text from … / Copied to clipboard." |
| Android notifications | Ongoing "Sending…" with orange progress + Cancel; "3 photos from Laptop / Saved to Gallery › PersonalSender. / Show in Gallery"; "Link from Laptop / Open link"; Stay ready ongoing with Turn off |
| Pairing | Laptop: `qr_flutter` 224 px with quiet zone; steps numbered in the colour of the device that does each step. Phone: `mobile_scanner` with orange corner brackets on a dark viewfinder, plus **Enter code instead**. |

### App icon

- **Concept:** square split on the diagonal, phone orange bottom-left and laptop blue top-right. Two white nodes with coloured centres, joined by a white line.
- **Android adaptive icon:** 108 dp canvas. Background layer = the two halves. Foreground = line and nodes, kept inside the 66 dp safe circle (nodes at 40/68 and 68/40, radius 13).
- **Android themed icon:** a monochrome layer with just the line and two ring nodes.
- **Windows:** `.ico` at 16, 24, 32, 48 and 256. Below 32 px it becomes a split circle with a thicker line. Nodes are spaced wider at 64 px and up.

## Screens and states

| Screen | States drawn | Notes |
|---|---|---|
| Phone · Pair | Scanning | Camera permission is asked when you tap Scan, with "The camera is used only to read this code." |
| Phone · Enter code instead | ready / wrong code (Tweaks) | Reached from Pair. The code works once. |
| Phone · Home | connected / looking / offline (Tweaks) | "See all" opens All activity. |
| Phone · All activity | All filter | |
| Phone · Share sheet | sending / done / offline (Tweaks) | Opens straight into sending: one paired laptop, so no picker. |
| Phone · Notifications | sending, received, link, Stay ready | |
| Phone · Settings | — | Unpair asks for confirmation. |
| Laptop · Main | connected / looking / offline (Tweaks) | Offline: "Files you send wait and go when PersonalSender opens on the phone." |
| Laptop · Drag over | drag-over | |
| Laptop · Pair phone | showing code | The code dies when the window closes. No countdowns. |
| Laptop · Settings | — | Includes the firewall tip (phone hotspots count as Public networks). |
| Dark mode | Phone Home, Laptop Main | The other screens follow the same token swap. |
| Windows · Tray & notifications | menu open, 3 notifications | |
| App icon | full, Android masks, themed, Windows sizes | |

## Words

- Sentence case everywhere (Android and Windows both use it).
- Device names come from what you named them: "Laptop", "Galaxy S24 Ultra" (renamable in Settings).
- Verbs stay the same through a flow: **Send → Sending → Sent**, **Received**, **Waiting**, **Not sent · reason → Retry**.
- Kept out of the main screens: "transfer", "peer", "payload", "IP". Addresses appear only in Settings › Connection details and the pairing fallback.
- Notifications never show the contents of received text, and links show only the site name (`github.com`).
- Errors say what happened and what to do: "Not reachable. Open PersonalSender on the laptop and join the same Wi-Fi or hotspot."

## Accessibility checklist

- [ ] Phone targets ≥ 48 dp. Laptop controls ≥ 32 px, toggles hit-tested on the whole row.
- [ ] Every icon-only button has a label (Settings, Back, Close, Dismiss, Minimize, Maximize). Status icons have labels (Sent, Received).
- [ ] No state shown by colour alone:
  - connection = line shape + heading
  - direction = arrow + "To/From" words (tile colour is extra)
  - waiting = clock + word
  - failed = icon + "Not sent"
- [ ] The device colours (orange vs blue) also differ in lightness, so they stay distinguishable for red-green colour blindness.
- [ ] Laptop: full keyboard use. Tab order goes header buttons → Choose files → Send clipboard → activity rows. Ctrl+O, Ctrl+V. Esc closes the Pair and Settings windows.
- [ ] 200 % text on both platforms without clipping. The wide Archivo headings wrap rather than truncate.
- [ ] "Remove animations" (Android) / "Animation effects off" (Windows): the connection-line dashes stand still; progress bars still fill.
- [ ] Dark mode checked on real devices.

## Not designed yet

- Dark versions of screens other than the two Home/Main screens (they follow the token swap).
- Windows high-contrast mode.
- Landscape and foldable layouts for the phone.
