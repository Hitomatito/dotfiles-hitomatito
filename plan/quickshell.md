# Quickshell Configuration Guide

This document explains the entire architecture, layout, and system integration of the native Quickshell configuration. The current setup fully replaces third-party tools (like `tofi`, external applets, and bash scripts for UI) with a cohesive, Wayland-native suite of QML components.

## 1. Architecture Overview

The desktop UI is powered by `quickshell`, taking advantage of QML's fluid animations and declarative UI, alongside Wayland protocols like `wlr-layer-shell`. The main configuration revolves around the `shell.qml` file, which orchestrates the Dynamic Island, Control Center, and acts as the parent for various specialized popups.

### Communication & IPC
- **Quickshell IPC**: We use `quickshell ipc call qsIpc <function>` to trigger UI updates from external bash scripts (e.g., `toggleControlCenter` or `toggleThemeSwitcher`).
- **Hyprland Interop**: We directly dispatch Hyprland commands (like `workspace X` or `hyprctl eval`) natively from QML.

## 2. The Dynamic Island (`PanelWindow`)

The top bar functions as a "Dynamic Island" that seamlessly expands and contracts (`notchRect`) depending on the content. It avoids taking up the entire width of the screen, opting for a floating, pill-like design.

**Features:**
- **Workspaces**: Dynamically reads Hyprland's active workspaces and displays numeric indicators.
- **Timer & Stopwatch**: When active, the countdown/countup seamlessly embeds into the island.
- **Mic Indicator**: A dynamic orange dot temporarily slides in for 1 second when the microphone is unmuted.

## 3. The Control Center (`PopupWindow`)

Triggered from the island, the Control Center is a comprehensive hub providing quick access to hardware and software controls.

**Key Components:**
- **Sliders**: Fluid `ModernSlider` components mapped to shell commands to control:
  - System Volume (`wpctl`) — The speaker icon acts as an interactive click-to-mute button.
  - Microphone Volume (`wpctl`) — The mic icon serves as a dynamic click-to-mute toggle.
  - Screen Brightness (`brightnessctl`)
- **Media Controls**: Displays the current Spotify track and playback controls (`playerctl`).
- **Toggles (Grid)**:
  - **Row 1**: Bluetooth & Wi-Fi (opens detailed sub-menus).
  - **Row 2**: Stopwatch & Timer toggles, plus a Configs/Notes launcher.

## 4. Specialized Popups (Tofi Migration)

We entirely eliminated `tofi` and dedicated launchers in favor of beautifully animated, unified Quickshell modules. All these popups share a consistent frosted glass design, hover animations, and cohesive typography.

*   **App Launcher (`AppLauncher.qml`)**:
    *   Powered by a backend Python script (`get_apps.py`) that parses `/usr/share/applications/` `.desktop` files into JSON.
    *   Features a responsive search bar, executing apps via `hyprctl dispatch exec`.
*   **Power Menu (`PowerMenu.qml`)**:
    *   A horizontal layout containing Lock, Suspend, Logout, Reboot, and Shutdown buttons.
    *   Supports full keyboard navigation (`Left`/`Right` and `Enter`).
*   **Clipboard Manager (`ClipboardManager.qml`)**:
    *   A scrollable interface for `cliphist list`.
    *   Clicking an entry immediately copies the content via `cliphist decode [id] | wl-copy`.
*   **Wi-Fi Menu (`WifiMenu.qml`)**:
    *   Parses `nmcli dev wifi list` dynamically.
    *   Allows 1-click connection to known networks and features inline password input for secured unknown networks.
*   **Bluetooth Menu (`BluetoothMenu.qml`)**:
    *   Uses `bluetoothctl` to scan, pair, connect, and disconnect devices straight from the UI.
*   **Theme Switcher (`ThemeSwitcher.qml`)**:
    *   Dynamically reads available Hyprland `.conf` themes and triggers `switch_theme.sh` seamlessly without jumping into a terminal or `tofi` window.

## 5. Design System & Aesthetics

- **Glassmorphism**: Uses layered transparent grays (e.g., 10% base opacity, 15% hover opacity) over a dark background for buttons and fields.
- **Animations**: `NumberAnimation` and `ColorAnimation` properties give every hover, click, and transition a premium feel.

## 6. Full System Integration Updates

Quickshell has successfully absorbed all bar, widget, and menu responsibilities, resulting in the complete removal of several legacy packages:
- **Waybar**: Completely removed. Quickshell is now the only panel running (launched via Hyprland's `autostart.conf`).
- **WOB (Wayland Overlay Bar)**: Completely removed. Volume and Brightness hotkeys now trigger an instant, native On-Screen Display (OSD) in Quickshell's Dynamic Island via direct IPC (`quickshell ipc call qsIpc showOsd <Type> <Value>`), eliminating the need for `wob.fifo` pipes.
