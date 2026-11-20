TAC MAP OVERLAY FOR MAC (A-TAK)  -  Apple Silicon, macOS 12+

INSTALL
1. Unzip the download and drag "Tac Map Overlay" into your Applications folder.
   (Or open "mac/build/Tac Map Overlay.app" straight from a downloaded copy of this repository: the newest build is kept there.)
2. The FIRST time: right-click the app -> Open -> Open.
   (macOS warns because the app is not notarized by Apple - that costs $99/year and this project is free.
    Everything is open source: the code is in the "mac" folder of the repository.)
   On macOS 15 (Sequoia) or newer the right-click trick is not enough: open System Settings -> Privacy & Security,
   scroll down and press "Open Anyway" next to Tac Map Overlay.
3. Keep the app in Applications (or any folder you can write to) so the one-click update can replace it.

USE
- A small tablet appears in the bottom-right corner, plus a map icon in the menu bar.
- Control + Option + T opens / minimizes the tablet (works over your game). Click the small tablet to open it too.
- The round buttons on the frame (ATAK): settings (gear), address bar (globe), live view, timers, notes.
  The pilot display has 24 buttons around the screen; Settings -> Pilot buttons lets you choose what each one does.
- Settings (gear): look and size, live corner view, shortcuts, pilot buttons, timers / bookmarks / presets, browser and updates.
- Live view: turn it on, then minimize - the frame disappears and only the screen stays in the corner. It does not take
  mouse clicks. With the TOC video wall open, the streams keep playing there.
- While the tablet is open your mouse stays inside it. Minimize it (shortcut) to get the mouse back,
  or turn "Keep the mouse inside the tablet" off in Settings.

SHORTCUTS (all Control + Option + ..., changeable in Settings)
  T open / minimize    P hold to peek    N notes    L live view    M move live view
  B bigger (cycle)     O transparency    1 / 2 timers    S stopwatch
  Control + Option + Shift + Q = close the app instantly (always works)

PRIVACY AND SAFETY
- No special macOS permissions are needed (no Accessibility, no Screen Recording, no Input Monitoring).
- The shortcuts use Apple's hot-key API, which only reports those exact combinations - it cannot see other keys.
- The only things the app contacts besides the sites you open: one small text file on GitHub (version-mac.txt) to see whether
  a newer version exists, and - only when you press "Update now" - the new version from the releases page.
- Ads/trackers are blocked, only https sites are allowed (except your local network), downloads are refused,
  camera and microphone are denied to web pages.

TROUBLESHOOTING
- App stuck or you want it gone right now: Control + Option + Shift + Q, or the map icon in the menu bar -> Quit.
  Last resort: Activity Monitor -> search 'Tac Map' -> select it -> the X button -> Force Quit.
- The app closes itself if it crashes or freezes for 20 seconds. After a bad exit the next start is 'safe':
  custom pictures and mouse lock are turned off (turn them back on in Settings).
- Shortcut does nothing: another app may use it. Pick another in Settings -> Shortcuts.
- Log file for bug reports: ~/Library/Logs/TacMapOverlay.log   (Settings -> Browser & data -> Show the log file)
- Reset everything: Settings -> Browser & data -> Restart with default settings.

LICENSE: MIT for the program code. The pictures in mac/Resources (tablet case photo, app icon) are not part of that license.