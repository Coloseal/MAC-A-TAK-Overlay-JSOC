## Tac Map Overlay for Mac - v0.2.0 (big update: the Mac app now has what the Windows app has)

**New**
- **Live corner view**: minimize and the frame disappears, the screen stays in the corner (default 30% of the monitor, click-through so the game keeps the mouse). Move it by hand, pick a corner, set the size.
- **TOC video wall fix**: with the TOC wall open, the live view keeps the streams playing instead of going black.
- **Pilot display** (helicopter MFD) with 24 buttons on 3 pages, rockers and an ON/OFF switch. Every button can be reassigned in Settings.
- **ATAK buttons**: address bar, live view, timers and notes next to the settings button.
- **Clock, 4 timers, stopwatch, mission clock** with an on-screen panel and alarm (sound + flashing banner, also in the live view).
- **Notes pad** (3 pages + a mission log with time stamps) and **tools**: bearing / distance between grids, 9-line template, checklist. All saved on your Mac.
- **Shortcuts**: open/minimize, size, transparency, hold-to-peek, notes, live view, move live view, timer 1, timer 2, stopwatch. All changeable.
- **Layout presets**, **bookmarks**, **game-aware** mode (only show while the game is in front), **export / import settings**, restart with default settings.
- **One-click update**: the app tells you about a new version and installs it when you press "Update now" (checked against a fingerprint).
- Themes: Coyote Tan, Black, Ranger Green, Arid, JG Camo, MultiCam, Navy. Your own PNG picture for each device.
- Page dialogs (alert / confirm) and file chooser now work inside the tablet.

**Safer** - emergency exit Control + Option + Shift + Q, crash and freeze guard, safe start after a bad exit.

**First start** - the app is free and open source but not notarized by Apple, so macOS asks once. Unzip, drag **Tac Map Overlay** into Applications, then right-click -> Open -> Open. On macOS 15 or newer: System Settings -> Privacy & Security -> scroll down -> "Open Anyway".
## Tac Map Overlay for Mac - v0.1.1

**Fixes**
- Choose picture no longer freezes the app: the file chooser now opens on top of the Settings window, and bad or huge pictures are rejected with a message.
- Settings closes with Esc and closes by itself when you click another app.

**Safety**
- New emergency shortcut **Control + Option + Shift + Q** closes the app instantly, even if it is stuck.
- Quit (menu bar / Settings) now closes the app immediately.
- Crash handler: if the app crashes it closes itself; if it freezes for 20 seconds it is closed automatically; a dialog can't stay open more than 3 minutes.
- After a bad exit, the next start is safe (custom picture and mouse lock off) and tells you.

## Tac Map Overlay for Mac - v0.1.0 (first test version)

A native Mac version of the A-TAK tablet for **Apple Silicon (M1/M2/M3/M4)**, macOS 12 or newer.

**What it does**
- The ATAK tablet floats over your game (also over full-screen apps). It opens on the tac map.
- Open / minimize with **Control + Option + T** (change it in Settings). Clicking the small tablet in the corner also opens it.
- Address bar (globe button) to open any site, with back / forward / reload / home.
- Built-in ad and tracker blocking, secure-only (https) browsing, no downloads, camera and microphone denied.
- Mouse stays inside the tablet while it is open (can be turned off).
- Themes, size, transparency, your own tablet picture (PNG), open/close animation.
- Menu-bar icon with the same controls. Update notice in the menu.

**First start (important)** - the app is free and open source but not notarized by Apple, so macOS asks once:
1. Unzip, drag **Tac Map Overlay** into Applications.
2. Right-click it -> **Open** -> **Open**. (Or: System Settings -> Privacy & Security -> "Open Anyway".)

Source code is in the `mac` folder of this repository. This is the first Mac test build: please report anything odd.
