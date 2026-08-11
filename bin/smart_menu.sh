#!/bin/bash
if pgrep -x "quickshell" > /dev/null; then
    # Quickshell active: use its IPC
    quickshell ipc call qsIpc toggleAppLauncher
else
    # Fallback to Tofi when Quickshell is not running
    tofi-drun --drun-launch=true
fi
