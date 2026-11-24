# Input Overlay

A see-through, click-through keyboard + mouse overlay for macOS. It floats above
every window (including full-screen apps) and lights up keys as you press them.
It lives in the menu bar.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools: `xcode-select --install` (full Xcode not needed)
- VS Code (optional) with the official **Swift** extension

## Files

```
InputOverlay/
├── Package.swift       Swift package manifest
├── Info.plist          App bundle metadata (menu-bar-only app)
├── build_app.sh        Builds / installs the app
├── App.swift           Entry point
├── AppDelegate.swift   Overlay window, menu bar menu, edit modes, launch at login
├── Settings.swift      Saved options + live key/mouse state
├── InputMonitor.swift  Global key/mouse listener (CGEventTap, read-only)
├── KeyLayout.swift     Layout model + layout.json loading/saving
└── OverlayView.swift   SwiftUI drawing of keys and mouse
```

## Install it so you can open it any time

```bash
chmod +x build_app.sh
./build_app.sh --install
```

This builds the app, copies it to `/Applications/Input Overlay.app` and launches it.
After that you can open it from Spotlight (Cmd+Space → "Input Overlay"), Launchpad or Finder.
Opening it again while it's running brings the overlay back if you hid it.

**Start automatically:** menu bar icon → **Launch at Login**
(approve it in System Settings → General → Login Items if macOS asks).

**Update later:** edit code, then run `./build_app.sh --install` again.

### Permission (required)

macOS only lets an app see keystrokes in other apps with **Input Monitoring**:

1. On first launch you'll get a prompt / alert. Open
   **System Settings → Privacy & Security → Input Monitoring**.
2. Switch on **Input Overlay** (use `+` and pick it from /Applications if it isn't listed).
3. If keys don't light up right away, quit from the menu bar icon and relaunch.

The app is read-only: it never blocks, alters, records or sends anything.

**Stop macOS forgetting the permission on every rebuild:** the default ad-hoc signature
changes each build. Create a free local certificate once:
Keychain Access → Certificate Assistant → Create a Certificate… → name it
`InputOverlay Dev`, type **Code Signing**. Then build with:

```bash
CODESIGN_ID="InputOverlay Dev" ./build_app.sh --install
```

If the permission does get stuck, reset it and grant it again:

```bash
tccutil reset ListenEvent com.example.inputoverlay
```

## Moving and editing

Everything is in the menu bar icon:

| Menu item | What it does |
|-----------|--------------|
| **Move Overlay** | Drag the whole overlay anywhere (any screen). The spot is remembered. |
| **Edit Keys** | Drag individual keys (and the mouse) to rearrange them; snaps to a 2-pt grid and saves automatically. |
| **Done Editing** | Back to normal click-through mode. |
| **Position** | Snap to a corner or screen edge. |
| **Size / Opacity / Color** | Scale 50-200%, transparency, and the highlight color. |
| **Show Mouse** | Hide the mouse and Shift key for a compact keyboard-only overlay. |

While editing, the overlay gets a blue tint and dashed border so you can see its bounds.

### Editing the layout file (add/remove keys, change labels)

Menu → **Layout File → Open layout.json** (opens in VS Code if installed).
It lives at `~/Library/Application Support/InputOverlay/layout.json`:

```json
{
  "canvasWidth": 740, "canvasHeight": 300, "keyboardWidth": 400,
  "mouseX": 432, "mouseY": 50,
  "keys": [
    { "label": "Q", "codes": [12], "x": 64, "y": 60 },
    { "label": "SHIFT", "codes": [56, 60], "x": 656, "y": 240, "w": 64, "fontSize": 20, "mouseOnly": true }
  ]
}
```

- `codes` are macOS key codes (a list of them is at the bottom of `KeyLayout.swift`).
  A key lights up if any code in its list is pressed.
- `w`, `h`, `fontSize` and `mouseOnly` are optional.
- `canvasWidth/Height` is the overlay's size; make it bigger if you add keys beyond the edge.
- After saving the file choose **Reload layout.json**. **Reset Layout to Default…** restores the original.

## Other tweaks

- **Look:** edit `OutlinedShape` and `KeyView` in `OverlayView.swift` (fill, outline width, font).
- **App icon:** put an `AppIcon.icns` next to `build_app.sh`; it's picked up on the next build.
- **Share with a friend:**
  ```bash
  hdiutil create -volname "Input Overlay" -srcfolder "dist/Input Overlay.app" -ov -format UDZO dist/InputOverlay.dmg
  ```
  They'll need to right-click → Open the first time, since the app isn't notarized
  (that requires a paid Apple Developer account).

## Optional: VS Code build task

Create `.vscode/tasks.json`, then press **Cmd+Shift+B** to rebuild, install and relaunch:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Build & Install Input Overlay",
      "type": "shell",
      "command": "./build_app.sh --install",
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": []
    }
  ]
}
```

## Troubleshooting

- **Nothing shows up:** menu bar keyboard icon → "Show Overlay" should be ticked.
- **Overlay on the wrong screen:** it follows the main display; drag it with **Move Overlay** to put it elsewhere.
- **Keys don't react:** Input Monitoring isn't granted (see above). Keystrokes in password fields are hidden by macOS itself.
- **Scroll direction looks reversed:** it follows your system's natural-scrolling setting.
- **layout.json error on reload:** usually a missing comma or bracket; the old layout stays active until it's fixed.
