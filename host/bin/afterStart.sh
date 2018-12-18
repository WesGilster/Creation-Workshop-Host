#!/bin/sh
sleep 5s
echo "afterStart begins!"
DISPLAY=:0 xrandr --output HDMI-1 --mode 3840x2160 --pos 800x0 --rotate normal --output DSI-1 --primary --mode 800x480 --pos 0x0 --rotate normal
DISPLAY=:0 xinput map-to-output `DISPLAY=:0 xinput list --id-only fts_ts` DSI-1
DISPLAY=:0 xdotool mousemove 0 0

sleep 5s
DISPLAY=:0 chromium --disable-aggressive-cache-discard --disable-notifications --incognito --no-first-run --disable --disable-translate --disable-infobars --disable-suggestion-service --disable-save-password-bubble --kiosk "http://localhost:9091/" --user-data-dir=/tmp --disable-extensions --noerrdialogs &
DISPLAY=:0 unclutter

