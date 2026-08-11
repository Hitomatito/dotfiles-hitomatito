#!/bin/bash
ACTION=$1

case $ACTION in
    up)
        brightnessctl s 5%+
        ;;
    down)
        brightnessctl s 5%-
        ;;
esac

PCT=$(brightnessctl i | grep -oP '\(\K[^%]+')

if pgrep -x "quickshell" > /dev/null; then
    quickshell ipc call qsIpc showOsd B "$PCT"
else
    # Fallback: wob OSD when Quickshell is not running
    echo "$PCT" > $XDG_RUNTIME_DIR/wob.fifo
fi
