# mssh — a mobile remote dev console

[中文](README.md) · **English**

A Flutter app that brings a trimmed-down "VS Code Remote-SSH" to your phone: connect to your own
machines, browse their file systems, preview files, and run terminals — **with voice input straight
from your phone's keyboard**, so you can drive an agent CLI on the remote box just by talking.

Networking is Tailscale's job; this app only speaks SSH. **Nothing to install on the target host and
no server side**: the phone runs its own SSH client (`dartssh2`) and connects directly.

---

## Download (Android)

Grab the latest `mssh-*.apk` from the [**Releases**](https://github.com/KonDaTrack/mssh/releases)
page, copy it to your phone and tap to install (allow "install unknown apps" the first time).
iOS requires building it yourself with Xcode — see below.

> The APK is signed with the debug key (Flutter's template default) — fine for personal use.
> Configure your own signing before publishing.

## Features

- **Hosts**: add / edit / delete hosts; log in with a password or a PEM private key. Secrets live in
  the platform secure store (Android Keystore / iOS Keychain), never in plaintext.
- **Files**: an expandable, lazily-loaded directory tree; tap a file to preview it on the right —
  text with line numbers, images with pinch-zoom, binary as a hex dump.
- **Upload / download** (VS Code sidebar style): **long-press a file** → "download to device",
  **long-press a folder** → "upload files into this folder" / "download this folder"; the preview
  pane also has a download button and the app bar an "upload to home" action. Transfers show a
  progress bar.
- **Tailscale integration**: when adding a host you can pick from the **online devices in your
  tailnet**; with no API key or no network it just falls back to typing the address by hand.
- **Terminals**: multiple tabs, each an independent shell; a new terminal can take a **startup
  command** (e.g. `claude`) that runs automatically once connected.
- **Keyboard / voice**: the terminal toolbar's "⌨ 键盘" button raises and lowers the phone's
  on-screen keyboard; talk into the keyboard's own microphone to type. Keys the soft keyboard can't
  produce (Enter / Esc / arrows / `^C` / pipe, …) are on the toolbar too.

## Layout

```
Host list ──tap a host──▶ Workspace
                            ├─ Files: tree on the left | preview on the right
                            │         (narrow screens swap between tree and preview)
                            └─ Terminals: tab strip + xterm terminal + soft-key toolbar
```

- Wide screens (≥720dp — landscape / tablet) split the Files tab left/right; on a portrait phone
  tapping a file shows a full-screen preview with a back button.
- Terminal toolbar: `esc tab ↑ ↓ ← → ^C ^D ^Z ^L / -` plus large `⌨ 键盘` and `⏎` buttons.

## Keyboard & voice input

1. Open **Terminals** and tap **⌨ 键盘** → the system keyboard appears (tap again to hide it).
2. Tap the **microphone** on your keyboard and speak → the text lands on the terminal input line.
3. Tap the **⏎** button to submit.

Because it uses your keyboard's own speech engine, Chinese accuracy and offline behaviour depend on
the IME you have installed (Gboard, Sogou, iFlytek, WeChat Keyboard, … all work). It applies equally
to TUI apps like `claude`: speaking is typing, Enter submits.

## Upload / download

- **Download**: long-press a file → "download to device", or tap the ⬇ in the preview header.
  Files under 64 MB open the system "save as" dialog; larger ones stream to a temp file and then the
  share sheet (so you can save or forward them) — a big download never has to fit in memory.
- **Upload**: long-press a **folder** → "upload files into this folder", or tap ⬆ in the app bar to
  upload into the home directory. Multi-select is supported.
- **Download a folder**: long-press it → "download this folder" — the remote side packs it (zip when
  available, otherwise tar.gz), the archive is streamed down, and the temp file is deleted on the
  server afterwards.
- Transfers run behind a progress dialog; on completion only the affected folder reloads, so the rest
  of the expanded tree stays put.

## Using it with Tailscale

The app doesn't care whether you're on a LAN — it just needs to reach SSH. With Tailscale running,
**enter the machine's MagicDNS name as the host** (e.g. `my-desktop` or
`my-desktop.tailnet-xxxx.ts.net`); as long as the phone is on the same tailnet it connects directly,
no IPs to remember.

**Picking a device automatically**: the add-host screen can list the **online devices in your
tailnet** in a dropdown and fill the address for you. A phone app can't read `tailscaled`'s local
API (the Tailscale app doesn't expose it), so this needs a Tailscale **API key**
(admin console → Settings → Keys → Generate access token, read-only on devices is enough); it's
stored once in the platform secure store. It's entirely optional — typing hostname / IP by hand
works the same, and the picker silently falls back to manual entry when the key is missing or the
network is down.

## Build & install

Prerequisites: Flutter SDK (3.29+, verified on 3.47.7 here), Android SDK / Xcode.

On a slow connection to pub.dev, use a China mirror:

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

### Android

```bash
flutter pub get
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
adb install build/app/outputs/flutter-apk/app-release.apk   # or copy the APK to the phone
```

> The release build is signed with the debug key (Flutter's template default) — fine for personal
> use. Configure `signingConfigs` in `android/app/build.gradle.kts` before publishing.

### iOS

Requires macOS + Xcode:

```bash
flutter build ios --release
# then open ios/Runner.xcworkspace in Xcode to sign and install (a free personal team works)
```

### Development

```bash
flutter run        # hot reload on a connected device
flutter analyze    # static analysis
flutter test       # unit tests + a compile smoke test
```

## Project layout

```
lib/
├── main.dart                 entry: wires HostStore, boots the app
├── app.dart                  MaterialApp + theme
├── theme.dart                dark UI theme
├── terminal_theme.dart       xterm palette
├── models/                   host / credential / remote_entry
├── services/
│   ├── host_store.dart       host persistence (metadata in SharedPreferences, secrets in secure store)
│   ├── ssh_service.dart      SSHClient wrapper: connect, shell+PTY, exec, SFTP
│   └── file_service.dart     SFTP wrapper: list directories, size-capped reads
├── screens/                  hosts / host_edit / workspace
├── widgets/                  file_tree / file_preview / terminal_pane
└── util/format.dart          path joining, size/time formatting, icons
```

## Dependencies

| Package | Purpose |
|---------|---------|
| [`dartssh2`](https://pub.dev/packages/dartssh2) | pure-Dart SSH2 client (connect / shell / SFTP) |
| [`xterm`](https://pub.dev/packages/xterm) | Flutter terminal emulator |
| `flutter_secure_storage` | secure storage for passwords / private keys |
| `shared_preferences` | host-list persistence |
| `provider` | state management |

## Security notes

- Passwords and private keys are written **only** to the platform secure store; the host list holds
  no secrets.
- The private key is parsed locally for authentication and never leaves the device.
- The server host key is **not verified** yet (to keep first connections easy). A known-hosts
  mechanism is a future improvement.

## Limitations / roadmap

- Editing / deleting remote files isn't supported yet (upload and download are).
- No server fingerprint verification (see above).
- No built-in speech recognition — deliberately, so your own IME's dictation stays the most accurate
  and least fussy option.
