TAC MAP OVERLAY FOR MAC (A-TAK)  -  Apple Silicon, macOS 12+

INSTALL
1. Open "mac/build/Tac Map Overlay.app" directly from a downloaded/checked-out copy of this repository,
   or unzip the mac ZIP and drag "Tac Map Overlay" into your Applications folder.
2. The FIRST time: right-click the app -> Open -> Open.
   (macOS warns because the app is not notarized by Apple - that costs $99/year and this project is free.
    Everything is open source: the code is in the "mac" folder of the repository.)
   If you only see "can't be opened": System Settings -> Privacy & Security -> scroll down -> "Open Anyway".

USE
- A small tablet appears in the bottom-right corner, plus a map icon in the menu bar.
- Control + Option + T opens / minimizes the tablet (works over your game). Click the small tablet to open it too.
- The gear on the tablet opens Settings (shortcut, size, transparency, theme, security options).
- The globe button shows an address bar so you can open any website.
- While the tablet is open your mouse stays inside it. Minimize it (shortcut) to get the mouse back,
  or turn "Lock the mouse" off in Settings.

PRIVACY AND SAFETY
- No special macOS permissions are needed (no Accessibility, no Screen Recording, no Input Monitoring).
- The shortcut uses Apple's hot-key API, which only reports that one combination - it cannot see other keys.
- The only thing the app contacts besides the sites you open is one small text file on GitHub (version-mac.txt)
  to see whether a newer version exists. Nothing is ever downloaded or installed automatically.
- Ads/trackers are blocked, only https sites are allowed (except your local network), downloads are refused,
  camera and microphone are denied to web pages.

TROUBLESHOOTING
- App stuck or you want it gone right now: press Control + Option + Shift + Q (closes it instantly), or use the map icon in the
  menu bar -> Quit. Last resort: Activity Monitor -> search 'Tac Map' -> select it -> the X button -> Force Quit.
- The app closes itself if it crashes or freezes for 20 seconds. After a bad exit the next start is 'safe':
  custom picture and mouse lock are turned off (turn them back on in Settings).
- The Settings window closes by itself when you click another app, and with the Esc key.
- Shortcut does nothing: another app may use it. Pick another in Settings.
- Log file for bug reports: ~/Library/Logs/TacMapOverlay.log
- Reset everything: quit the app, then in Terminal:  defaults delete io.github.coloseal.tacmapoverlay

LICENSE: MIT.
