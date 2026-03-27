#!/bin/bash
UID_TARGET=1000
SOUND_DIR="/usr/share/sounds/freedesktop/stereo"

# Find the AC adapter dynamically (name varies across T2 Mac models: ADP1, AC0, etc.)
STATUS=""
for supply in /sys/class/power_supply/*/type; do
    if [[ "$(cat "$supply" 2>/dev/null)" == "Mains" ]]; then
        STATUS=$(cat "$(dirname "$supply")/online" 2>/dev/null)
        break
    fi
done

if [ "$STATUS" = "1" ]; then
    SOUND="$SOUND_DIR/power-plug.oga"
    powerprofilesctl set performance
else
    SOUND="$SOUND_DIR/power-unplug.oga"
    powerprofilesctl set power-saver
fi

# Run paplay detached via systemd-run so udev's timeout doesn't kill the sound.
sudo -u "#$UID_TARGET" \
    XDG_RUNTIME_DIR="/run/user/$UID_TARGET" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_TARGET/bus" \
    systemd-run --user --quiet paplay "$SOUND" 2>/dev/null || true
