#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(eval echo "~$TARGET_USER")"
TARGET_UID="$(id -u "$TARGET_USER")"

NEED_INITRAMFS=false
CHANGES_MADE=()

# --- Colors & helpers ---

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m' "$1"; }
yellow() { printf '\033[33m%s\033[0m' "$1"; }
red() { printf '\033[31m%s\033[0m' "$1"; }

info()  { echo "  $(green "=>") $1"; }
warn()  { echo "  $(yellow "!!") $1"; }
error() { echo "  $(red "ERROR:") $1" >&2; }

step() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bold "  Step $1: $2"
    echo ""
    echo "  $3"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ask "question" default
# default: y or n — what happens when the user just presses Enter
ask() {
    local prompt="$1" default="$2" reply
    if [[ "$default" == "y" ]]; then
        read -rp "  $prompt [Y/n] " reply
        reply="${reply:-y}"
    else
        read -rp "  $prompt [y/N] " reply
        reply="${reply:-n}"
    fi
    [[ "${reply,,}" == "y" ]]
}

is_installed() {
    pacman -Q "$1" &>/dev/null
}

install_pkg() {
    local pkg="$1"
    if is_installed "$pkg"; then
        info "$pkg is already installed, skipping"
    else
        sudo pacman -S --noconfirm "$pkg"
        info "Installed $pkg"
    fi
}

copy_config() {
    local src="$1" dest="$2"
    sudo mkdir -p "$(dirname "$dest")"
    if [[ -f "$dest" ]] && diff -q "$src" "$dest" &>/dev/null; then
        info "$(basename "$dest") already in place, skipping"
    else
        if [[ -f "$dest" ]]; then
            warn "$(basename "$dest") differs from repo version — overwriting (backup at ${dest}.bak)"
            sudo cp "$dest" "${dest}.bak"
        fi
        sudo cp "$src" "$dest"
        info "Copied $(basename "$dest")"
    fi
}

track() {
    CHANGES_MADE+=("$1")
}

# --- Pre-flight checks ---

echo ""
echo "  ┌──────────────────────────────────────────────────┐"
echo "  │  T2 MacBook Omarchy Setup                        │"
echo "  │  Interactive installer for T2-specific configs    │"
echo "  └──────────────────────────────────────────────────┘"
echo ""
info "User: $TARGET_USER ($TARGET_HOME, UID $TARGET_UID)"

if [[ $EUID -eq 0 ]]; then
    error "Don't run this script as root. It will call sudo when needed."
    exit 1
fi

# Validate sudo access early
info "This script needs sudo for system-level changes."
sudo -v || { error "sudo access required"; exit 1; }

# --- Step 1: arch-mact2 repo ---

step 1 "Add arch-mact2 repository" \
    "The T2 packages (kernel, drivers) come from a community repository.\n  Without it, pacman can't find linux-t2, apple-bce, etc."

if grep -q "\[arch-mact2\]" /etc/pacman.conf; then
    info "arch-mact2 repo already configured"
else
    if ask "Add the arch-mact2 repo to /etc/pacman.conf?" "y"; then
        sudo tee -a /etc/pacman.conf > /dev/null << 'REPO'

[arch-mact2]
Server = https://mirror.funami.tech/arch-mact2/os/x86_64
SigLevel = Never
REPO
        sudo pacman -Sy
        track "Added arch-mact2 repo to pacman.conf"
        info "Repository added and package database synced"
    else
        warn "Skipped. T2 packages will fail to install without this repo."
    fi
fi

# --- Step 2: T2 kernel ---

step 2 "Install T2 kernel" \
    "The mainline Arch kernel has no T2 drivers. linux-t2 is a patched\n  kernel with T2 chip support for keyboard, trackpad, storage, and more."

if ask "Install linux-t2 + linux-t2-headers?" "y"; then
    install_pkg linux-t2
    install_pkg linux-t2-headers
    track "Installed linux-t2 kernel"
fi

# --- Step 3: apple-bce (T2 chip driver) ---

step 3 "Install apple-bce driver" \
    "The T2 chip routes keyboard, trackpad, audio, and SSD through an\n  internal USB/PCIe bus. Without apple-bce, none of those devices work."

if ask "Install apple-bce?" "y"; then
    install_pkg apple-bce
    track "Installed apple-bce"
fi

# --- Step 4: WiFi/Bluetooth firmware ---

step 4 "Install WiFi/Bluetooth firmware" \
    "The T2 has a Broadcom BCM4364 chip. This package provides the\n  proprietary firmware blobs needed for WiFi and Bluetooth."

if ask "Install apple-bcm-firmware?" "y"; then
    install_pkg apple-bcm-firmware
    track "Installed apple-bcm-firmware"
fi

# --- Step 5: Audio config ---

step 5 "Install audio routing config" \
    "Audio on T2 Macs is routed through the T2's internal codec.\n  This package provides the UCM profiles so PipeWire/ALSA can use it."

if ask "Install apple-t2-audio-config?" "y"; then
    install_pkg apple-t2-audio-config
    track "Installed apple-t2-audio-config"
fi

# --- Step 6: Fan control ---

step 6 "Install fan control daemon" \
    "macOS firmware manages fans, but under Linux there's no built-in fan\n  control. Without t2fanrd, fans may never spin up — risking overheating.\n  Default config: fans off below 55°C, linear ramp to full at 75°C."

if ask "Install t2fanrd + config?" "y"; then
    install_pkg t2fanrd
    copy_config "$SCRIPT_DIR/etc/t2fand.conf" "/etc/t2fand.conf"
    sudo systemctl enable t2fanrd.service
    sudo systemctl start t2fanrd.service
    track "Installed t2fanrd + config + enabled service"
fi

# --- Step 7: Webcam ---

step 7 "Install FaceTime HD webcam driver" \
    "The built-in webcam needs a reverse-engineered driver and Apple's\n  firmware blobs. This installs the DKMS module and firmware files."

if ask "Install facetimehd (webcam)?" "y"; then
    install_pkg facetimehd-firmware
    install_pkg facetimehd-data
    install_pkg facetimehd-dkms
    copy_config "$SCRIPT_DIR/etc/modules-load.d/facetimehd.conf" "/etc/modules-load.d/facetimehd.conf"
    track "Installed facetimehd webcam driver"
fi

# --- Step 8: Boot parameters ---

step 8 "Configure boot parameters" \
    "The T2 chip needs specific kernel params to work:\n  - intel_iommu=on iommu=pt — IOMMU passthrough for T2 internal devices\n  - pcie_ports=compat — compatibility mode for T2's PCIe bridge\n  These are added via limine-entry-tool.d (appended to kernel cmdline)."

if ask "Install boot parameter config?" "y"; then
    copy_config "$SCRIPT_DIR/etc/limine-entry-tool.d/t2-mac.conf" "/etc/limine-entry-tool.d/t2-mac.conf"
    track "Installed boot parameters (limine-entry-tool.d)"

    echo ""
    warn "You should also add mem_sleep_default=s2idle to /boot/limine.conf"
    warn "T2 Macs lack S3 deep sleep — this prevents the kernel from trying and failing."
    warn "Edit /boot/limine.conf manually and add it to the CMDLINE for your entry."
fi

# --- Step 9: Kernel module configs ---

step 9 "Configure kernel modules" \
    "Installs configs for:\n  - initramfs: loads apple-bce, usbhid, hid_apple early (needed for\n    keyboard at disk encryption prompt)\n  - modules-load.d: auto-loads apple-bce at boot\n  - modprobe.d:\n    * brcmfmac: disables buggy WiFi firmware features that cause dropouts\n    * hid_apple: F1-F12 as default (Fn for media keys)\n    * usbcore: disables USB autosuspend (prevents keyboard/trackpad freezing)"

if ask "Install kernel module configs?" "y"; then
    copy_config "$SCRIPT_DIR/etc/mkinitcpio.conf.d/apple-t2.conf" "/etc/mkinitcpio.conf.d/apple-t2.conf"
    copy_config "$SCRIPT_DIR/etc/modules-load.d/apple-bce.conf" "/etc/modules-load.d/apple-bce.conf"
    copy_config "$SCRIPT_DIR/etc/modprobe.d/brcmfmac.conf" "/etc/modprobe.d/brcmfmac.conf"
    copy_config "$SCRIPT_DIR/etc/modprobe.d/hid_apple.conf" "/etc/modprobe.d/hid_apple.conf"
    copy_config "$SCRIPT_DIR/etc/modprobe.d/disable-usb-autosuspend.conf" "/etc/modprobe.d/disable-usb-autosuspend.conf"
    NEED_INITRAMFS=true
    track "Installed kernel module configs (initramfs, modules-load, modprobe)"
fi

# --- Step 10: Systemd configs ---

step 10 "Configure systemd (faster shutdown + power key)" \
    "Two tweaks:\n  - Reduces shutdown timeout from 90s to 5s (T2 drivers sometimes hang)\n  - Disables the power key to prevent accidental suspend (suspend is\n    broken on T2 Macs — waking often results in a black screen)"

if ask "Install systemd configs?" "y"; then
    copy_config "$SCRIPT_DIR/etc/systemd/system.conf.d/10-faster-shutdown.conf" "/etc/systemd/system.conf.d/10-faster-shutdown.conf"

    # Disable power key in logind.conf
    if grep -q "^HandlePowerKey=ignore" /etc/systemd/logind.conf; then
        info "Power key already disabled"
    elif grep -q "^#\?HandlePowerKey=" /etc/systemd/logind.conf; then
        sudo sed -i 's/^#\?HandlePowerKey=.*/HandlePowerKey=ignore/' /etc/systemd/logind.conf
        info "Set HandlePowerKey=ignore in logind.conf"
    else
        echo "HandlePowerKey=ignore" | sudo tee -a /etc/systemd/logind.conf > /dev/null
        info "Added HandlePowerKey=ignore to logind.conf"
    fi
    track "Installed systemd configs (faster shutdown + power key disabled)"
fi

# --- Step 11: Power profile switching ---

step 11 "Auto power profile (performance on AC, power-saver on battery)" \
    "Installs power-profiles-daemon and a script + udev rule that\n  automatically switches profiles when you plug/unplug AC.\n  Also plays a sound on plug/unplug and sets the right profile at boot."

if ask "Install power profile auto-switching?" "y"; then
    install_pkg power-profiles-daemon
    sudo systemctl enable power-profiles-daemon.service
    sudo systemctl start power-profiles-daemon.service

    # Install power-config script with correct UID
    sudo cp "$SCRIPT_DIR/usr/local/bin/power-config.sh" "/usr/local/bin/power-config.sh"
    sudo sed -i "s/^UID_TARGET=.*/UID_TARGET=$TARGET_UID/" "/usr/local/bin/power-config.sh"
    sudo chmod +x "/usr/local/bin/power-config.sh"
    info "Installed power-config.sh (UID=$TARGET_UID)"

    copy_config "$SCRIPT_DIR/etc/udev/rules.d/95-power-config.rules" "/etc/udev/rules.d/95-power-config.rules"
    copy_config "$SCRIPT_DIR/etc/systemd/system/power-profile-boot.service" "/etc/systemd/system/power-profile-boot.service"
    sudo systemctl enable power-profile-boot.service
    sudo udevadm control --reload-rules
    track "Installed power profile auto-switching"
fi

# --- Step 12: WiFi resume + powersave ---

step 12 "WiFi resume hook + powersave switching" \
    "Two fixes:\n  - Resume hook: reloads the Broadcom WiFi driver after waking from\n    suspend (the driver loses connection state and silently fails)\n  - Powersave rule: enables WiFi power save on battery, disables on AC\n    (saves battery but reduces latency when plugged in)"

if ask "Install WiFi resume hook + powersave rules?" "y"; then
    sudo cp "$SCRIPT_DIR/usr/lib/systemd/system-sleep/wifi-resume" "/usr/lib/systemd/system-sleep/wifi-resume"
    sudo chmod +x "/usr/lib/systemd/system-sleep/wifi-resume"
    info "Installed wifi-resume hook"

    # Generate wifi powersave rule with correct username
    sudo mkdir -p /etc/udev/rules.d
    sed "s|/home/<your-username>/|/home/$TARGET_USER/|g" \
        "$SCRIPT_DIR/etc/udev/rules.d/99-wifi-powersave.rules" \
        | sudo tee /etc/udev/rules.d/99-wifi-powersave.rules > /dev/null
    info "Installed wifi-powersave udev rule (user: $TARGET_USER)"
    sudo udevadm control --reload-rules
    track "Installed WiFi resume hook + powersave rules"
fi

# --- Step 13: Keyboard backlight ---

step 13 "Keyboard backlight step size" \
    "The T2 MacBook has 512 backlight levels. Omarchy's default script\n  changes brightness by 1 unit per keypress (~0.2% — invisible).\n  This override steps by a percentage of max brightness."

if ask "Install keyboard backlight override?" "y"; then
    echo ""
    echo "  How much should each keypress change brightness?"
    echo "    1) 5%  (20 steps from off to max — finer control)"
    echo "    2) 10% (10 steps from off to max — recommended)"
    echo "    3) 20% (5 steps from off to max — coarser jumps)"
    echo ""
    read -rp "  Choose [1/2/3, default=2]: " bl_choice
    bl_choice="${bl_choice:-2}"

    case "$bl_choice" in
        1) divisor=20; pct="5%" ;;
        3) divisor=5;  pct="20%" ;;
        *) divisor=10; pct="10%" ;;
    esac

    dest="$TARGET_HOME/.local/share/omarchy/bin/omarchy-brightness-keyboard"
    mkdir -p "$(dirname "$dest")"
    sed "s|^STEP_DIVISOR=.*|STEP_DIVISOR=$divisor|" \
        "$SCRIPT_DIR/usr/local/bin/omarchy-brightness-keyboard" > "$dest"
    chmod +x "$dest"
    info "Installed keyboard backlight override ($pct steps)"
    track "Installed keyboard backlight override ($pct steps)"
fi

# --- Step 14: Orca + Piper TTS ---

step 14 "Screen reader with natural voice (Orca + Piper TTS)" \
    "Orca is a screen reader for accessibility. Omarchy does not include\n  one by default. If you need a screen reader, this installs Orca with\n  Piper TTS — a neural text-to-speech engine that sounds natural instead\n  of the default robotic espeak-ng voice."

if ask "Install Orca + Piper TTS (screen reader)?" "n"; then
    install_pkg orca
    info "Running Piper TTS setup..."
    bash "$SCRIPT_DIR/usr/local/bin/setup-orca-piper.sh"

    # Install toggle script and F3 keybinding
    sudo cp "$SCRIPT_DIR/usr/local/bin/omarchy-toggle-orca" "/usr/local/bin/omarchy-toggle-orca"
    sudo chmod +x "/usr/local/bin/omarchy-toggle-orca"
    info "Installed omarchy-toggle-orca"

    BINDINGS_FILE="$TARGET_HOME/.config/hypr/bindings.conf"
    if [[ -f "$BINDINGS_FILE" ]] && ! grep -q "omarchy-toggle-orca" "$BINDINGS_FILE"; then
        echo "" >> "$BINDINGS_FILE"
        echo "# Toggle Orca screen reader on/off" >> "$BINDINGS_FILE"
        echo 'bindd = , XF86LaunchA, Toggle Orca screen reader, exec, omarchy-toggle-orca' >> "$BINDINGS_FILE"
        info "Added Fn+F3 (XF86LaunchA) keybinding for Orca toggle"
    elif grep -q "omarchy-toggle-orca" "$BINDINGS_FILE" 2>/dev/null; then
        info "Fn+F3 Orca keybinding already configured"
    else
        warn "Hyprland bindings file not found — add this line manually:"
        warn "bindd = , XF86LaunchA, Toggle Orca screen reader, exec, omarchy-toggle-orca"
    fi

    track "Installed Orca + Piper TTS + F3 toggle keybinding"
fi

# --- Step 15: Rebuild initramfs ---

if $NEED_INITRAMFS; then
    step 15 "Rebuild initramfs" \
        "Kernel module configs changed. The initramfs needs to be rebuilt\n  so the new modules (apple-bce, usbhid, etc.) are available at early boot."

    if ask "Rebuild initramfs now? (required for changes to take effect)" "y"; then
        sudo mkinitcpio -P
        track "Rebuilt initramfs"
    else
        warn "Skipped. Run 'sudo mkinitcpio -P' before rebooting!"
    fi
fi

# --- Summary ---

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bold "  Setup complete!"
echo ""

if [[ ${#CHANGES_MADE[@]} -eq 0 ]]; then
    info "No changes were made."
else
    info "What was done:"
    for change in "${CHANGES_MADE[@]}"; do
        echo "    - $change"
    done
fi

echo ""
warn "Reboot to apply all changes: sudo reboot"
echo ""
