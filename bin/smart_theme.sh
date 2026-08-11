#!/bin/bash
if pgrep -x "quickshell" > /dev/null; then
    quickshell ipc call qsIpc toggleThemeSwitcher
else
    "$HOME/.config/hypr/scripts/switch_theme.sh"
fi
