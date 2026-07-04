#!/bin/bash
if pgrep -x "quickshell" > /dev/null; then
    quickshell ipc call qsIpc toggleClipboard
else
    cliphist list | tofi --prompt-text " clipboard: " | cliphist decode | wl-copy
fi
