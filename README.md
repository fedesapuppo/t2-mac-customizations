# T2 MacBook Extra Customizations for Omarchy

Additional tweaks and configurations for running [Omarchy](https://github.com/basecamp/omarchy) on a MacBook with T2 chip — beyond what Omarchy ships out of the box.

> **Warning — Suspend/Wake is broken.** T2 Macs only support `s2idle` (no S3 deep sleep). Waking from suspend frequently results in a black screen with an unresponsive keyboard, requiring a hard reboot. This is a known issue with no reliable fix — see [Open Issues](#open-issues) for details. If you rely on suspend, be aware that **you may lose unsaved work**.

## Prerequisites

Omarchy's installer auto-detects T2 hardware and handles the basics:
- T2 kernel (`linux-t2`) + headers
- `apple-bce` driver (keyboard, trackpad, storage)
- WiFi/Bluetooth firmware (`apple-bcm-firmware`)
- Audio routing (`apple-t2-audio-config`)
- Fan daemon (`t2fanrd`) with default config
- Boot parameters (`intel_iommu=on iommu=pt pcie_ports=compat`)
- Kernel module configs (initramfs, modprobe, modules-load)
- F-key behavior (`hid_apple fnmode=2`)
- USB autosuspend disable

**Install Omarchy first**, then run this setup for the extras.

## Quick Start

```bash
git clone https://github.com/fedesapuppo/t2-mac-customizations.git
cd t2-mac-customizations
bash setup.sh
```

The setup script walks you through every step interactively — it explains what each component does, asks before installing anything, and lets you skip what you don't need. Safe to re-run.

## What This Repo Adds

### Custom Fan Curve

Omarchy installs `t2fanrd` with its default config. This repo provides a custom fan curve optimized for the MacBook Air.

- [`etc/t2fand.conf`](etc/t2fand.conf) — linear fan curve from 55°C to 75°C. Fans stay off below 55°C and ramp linearly to full speed at 75°C.

### FaceTime HD Webcam

Omarchy does not include webcam support for T2 Macs. This installs the reverse-engineered FaceTime HD driver and firmware.

- Packages: `facetimehd-firmware`, `facetimehd-data`, `facetimehd-dkms`
- [`etc/modules-load.d/facetimehd.conf`](etc/modules-load.d/facetimehd.conf) — auto-load `facetimehd` at boot

### Power Profiles (auto-switch on AC plug/unplug)

Automatically switches to `performance` on AC and `power-saver` on battery. Also plays plug/unplug sounds. Without this, the system stays on whatever profile was last set manually.

- [`usr/local/bin/power-config.sh`](usr/local/bin/power-config.sh) — main script (profile switch + sound)
- [`etc/udev/rules.d/95-power-config.rules`](etc/udev/rules.d/95-power-config.rules) — udev rule triggers script on power supply change
- [`etc/systemd/system/power-profile-boot.service`](etc/systemd/system/power-profile-boot.service) — systemd service sets correct profile at boot

### Power/Suspend Workarounds

- `HandlePowerKey=ignore` in `/etc/systemd/logind.conf` — since suspend is broken on T2 Macs, the power key is disabled to avoid accidentally triggering a suspend that results in a black screen.
- [`etc/systemd/system.conf.d/10-faster-shutdown.conf`](etc/systemd/system.conf.d/10-faster-shutdown.conf) — reduces `DefaultTimeoutStopSec` from 90s to 5s. T2 drivers occasionally hang during shutdown.

### WiFi

- [`etc/udev/rules.d/99-wifi-powersave.rules`](etc/udev/rules.d/99-wifi-powersave.rules) — toggles WiFi power save based on AC state: enabled on battery, disabled on AC. Update the username in the path before using.
- [`usr/lib/systemd/system-sleep/wifi-resume`](usr/lib/systemd/system-sleep/wifi-resume) — reloads `brcmfmac` after resume. The Broadcom driver loses its connection state through suspend on T2 Macs.

### Keyboard Backlight Step Size

The T2 MacBook Air has 512 brightness levels for keyboard backlight (`apple::kbd_backlight`). Omarchy's default script steps by 1 unit (~0.2% — invisible).

- [`usr/local/bin/omarchy-brightness-keyboard`](usr/local/bin/omarchy-brightness-keyboard) — replacement script that steps by 10% of max brightness

Copy to `~/.local/share/omarchy/bin/omarchy-brightness-keyboard` to override the default. Change the divisor from `10` to `20` for 5% steps if 10% feels too coarse.

---

## Screen Reader with Natural Voice (Orca + Piper TTS)

Omarchy does not ship with a screen reader. For accessibility, you need to install [Orca](https://wiki.gnome.org/Projects/Orca) separately (`sudo pacman -S orca`). Orca's default TTS engine is espeak-ng, which produces a robotic, hard-to-understand voice. I replaced it with [Piper](https://github.com/rhasspy/piper), a fast neural TTS engine that produces a natural human voice — a much better experience for extended use.

> **Note:** The `piper-tts` AUR package currently fails to build due to an espeak-ng phoneme compilation bug. The setup script downloads the prebuilt binary from GitHub releases instead.

### Requirements

- `orca` — install with `sudo pacman -S orca`
- `speech-dispatcher` (comes with orca)
- Internet connection (for initial download of piper binary + voice model)

### Setup

```bash
bash usr/local/bin/setup-orca-piper.sh
```

The script:
1. Downloads the piper binary to `~/.local/bin/piper-tts`
2. Downloads shared libraries to `~/.local/share/piper-tts/lib/`
3. Downloads the `en_US-lessac-medium` voice model to `~/.local/share/piper-tts/voices/`
4. Configures speech-dispatcher to use piper as the default module (requires sudo)
5. Restarts speech-dispatcher and plays a test sentence

After setup, Orca will automatically use the natural piper voice. Test manually with:

```bash
spd-say -o piper-tts "hello world"
```

### Fn+F3 toggle keybinding

Press **Fn+F3** to start Orca, press **Fn+F3** again to quit it. On T2 MacBooks, Fn+F3 sends `XF86LaunchA` (the Mission Control key). The setup script adds this binding to Hyprland automatically. To add it manually, append to `~/.config/hypr/bindings.conf`:

```
bindd = , XF86LaunchA, Toggle Orca screen reader, exec, omarchy-toggle-orca
```

### Config files

- [`usr/local/bin/setup-orca-piper.sh`](usr/local/bin/setup-orca-piper.sh) — setup script (idempotent, safe to re-run)
- [`usr/local/bin/omarchy-toggle-orca`](usr/local/bin/omarchy-toggle-orca) — toggle script: starts Orca if not running, quits it if running
- [`etc/speech-dispatcher/modules/piper-tts.conf`](etc/speech-dispatcher/modules/piper-tts.conf) — speech-dispatcher module config (reference — the setup script generates a user-specific version with resolved paths)

---

## Cross-Reference with Upstream

Sources:
- https://github.com/basecamp/omarchy/discussions/773
- https://github.com/basecamp/omarchy/issues/3883

| Feature | Status |
|---|---|
| T2 kernel + `apple-bce` | Handled by Omarchy |
| `apple-bcm-firmware` for WiFi | Handled by Omarchy |
| `hid_apple` + `usbhid` in mkinitcpio | Handled by Omarchy |
| `pcie_ports=compat` boot param | Handled by Omarchy |
| `intel_iommu=on iommu=pt` | Handled by Omarchy |
| `brcmfmac feature_disable=0x82000` | Handled by Omarchy |
| F-key behavior (`fnmode=2`) | Handled by Omarchy |
| USB autosuspend disable | Handled by Omarchy |
| Fan daemon (`t2fanrd`) | Handled by Omarchy (default config) |
| Custom fan curve | Done (this repo) |
| Webcam via `facetimehd` driver | Done (this repo) |
| WiFi resume hook (reload `brcmfmac` after suspend) | Done (this repo) |
| Keyboard backlight 10% step size | Done (this repo) |
| Auto power profile (performance/power-saver) | Done (this repo) |
| Natural voice screen reader (Orca + Piper TTS) | Done (this repo) |
| Suspend/wake black screen fix | **Not solved** (open issue) |

## Open Issues

### Suspend/wake black screen

This is the big unsolved issue. After suspending via `s2idle` (the only option — T2 Macs lack ACPI S3 deep sleep), waking results in a black screen with unresponsive keyboard. Hard reboot is the only recovery.

**Why it's broken (multiple layers):**

1. **The `apple-bce` driver cannot cleanly suspend/resume.** This reverse-engineered driver (keyboard, trackpad, internal USB/PCIe) does not handle power state transitions properly. Suspend works fine when `apple-bce` is not loaded — the driver itself is the primary culprit.
2. **`s2idle` is inherently fragile.** Unlike S3 (where hardware manages power-down), `s2idle` requires every driver to correctly freeze and thaw. One misbehaving driver breaks the entire chain.
3. **macOS Sonoma firmware regression.** A T2 firmware update bundled with Sonoma made suspend worse, even for users who previously had it partially working. The T2 firmware is only updatable through macOS and Apple controls it.
4. **The T2 chip is a black box.** Apple has never published documentation for its power management interface. Proper suspend/resume would require understanding undocumented firmware-level transitions.

**Known workaround (partial):** The [t2linux wiki](https://wiki.t2linux.org/guides/postinstall/) documents a systemd service that force-unloads `apple-bce` before suspend and reloads it after wake. This helps some users but results in ~30 second resume times and does not work reliably across suspend cycles.

**Honest prognosis:** This is unlikely to be fully fixed. The T2 chip is undocumented, Apple has moved on to Apple Silicon, the `apple-bce` driver has no upstream maintainer investing in power management, and the developer pool working on T2 Linux is small and shrinking. The most practical alternatives are hibernate (suspend-to-disk) or simply locking the screen on lid close instead of suspending.

**References:**
- [t2linux wiki — Suspend status](https://wiki.t2linux.org/guides/postinstall/)
- [Omarchy Issue #1840](https://github.com/basecamp/omarchy/issues/1840)
- [T2Linux-Suspend-Fix script](https://github.com/deqrocks/T2Linux-Suspend-Fix)
