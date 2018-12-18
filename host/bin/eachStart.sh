#!/bin/sh
xrandr --output HDMI-1 --mode 1920x1080 --pos 800x0 --rotate normal --output DSI-1 --primary --mode 800x480 --pos 0x0 --rotate normal
xinput map-to-output `xinput list --id-only fts_ts` DSI-1

