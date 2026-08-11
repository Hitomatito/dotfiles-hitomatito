#!/bin/bash
if pgrep -x "quickshell" > /dev/null; then
    # Quickshell active: use its IPC
    quickshell ipc call qsIpc togglePowerMenu
else
    # Fallback to Tofi when Quickshell is not running
    "$HOME/.config/tofi/powermenu.sh"
fi
