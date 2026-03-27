# T2 MacBook Omarchy Setup & Customizations

Configuration files and customizations for running [Omarchy](https://github.com/basecamp/omarchy) (Arch Linux) on a MacBook Air with T2 chip.

> **Warning — Suspend/Wake is broken.** T2 Macs only support `s2idle` (no S3 deep sleep). Waking from suspend frequently results in a black screen with an unresponsive keyboard, requiring a hard reboot. This is a known issue with no reliable fix — see [Open Issues](#open-issues) for details. If you rely on suspend, be aware that **you may lose unsaved work**.

## Quick Start

```bash
git clone https://github.com/fedesapuppo/t2-mac-customizations.git
cd t2-mac-customizations
bash setup.sh
```

The setup script walks you through every step interactively — it explains what each component does, asks before installing anything, and lets you skip what you don't need. Safe to re-run.

## System Info
- **Kernel**: `linux-t2` (6.18.13-arch1-Watanare-T2-1-t2)
- **Boot Loader**: Limine
- **Model**: MacBook Air with T2 chip

## Packages

- `linux-t2` + `linux-t2-headers` — patched kernel with T2 chip support (mainline Linux has no T2 drivers)
- `apple-bce` — T2 chip driver: keyboard, trackpad, audio, and SSD are all routed through the T2's internal USB/PCIe bus. Without this module, none of those devices appear to the kernel.
- `apple-bcm-firmware` — WiFi/Bluetooth firmware for the Broadcom BCM4364 chip inside the T2
- `apple-t2-audio-config` — UCM profiles that tell PipeWire/ALSA how to route audio through the T2's internal codec
- `t2fanrd` — fan control daemon (macOS firmware normally manages fans; under Linux there is no built-in fan management)
- `facetimehd-firmware`, `facetimehd-data`, `facetimehd-dkms` — FaceTime HD webcam driver and firmware
- `power-profiles-daemon` — enables switching between `performance` and `power-saver` profiles
- `orca` — screen reader (not included in Omarchy, installed separately) + Piper TTS (natural voice, installed via setup script)
- Custom repo: `[arch-mact2]` in `/etc/pacman.conf` — configured with `SigLevel = Never` (package signatures are not verified). This is standard for community T2 repos that don't maintain signing keys, but means you're trusting the mirror operator. Use a trusted network when syncing packages.

## Configuration Files

All config files mirror their system paths. Copy them to `/` to apply.

### Boot Parameters

- [`etc/limine-entry-tool.d/t2-mac.conf`](etc/limine-entry-tool.d/t2-mac.conf) — kernel command line: `intel_iommu=on iommu=pt pcie_ports=compat`
  - `intel_iommu=on iommu=pt` — the T2 chip sits behind an IOMMU; without passthrough mode, internal devices (keyboard, trackpad, storage) can fail to initialize or work unreliably
  - `pcie_ports=compat` — the T2's PCIe bridge doesn't fully support native hotplug signaling; compatibility mode prevents device enumeration failures at boot

Additional boot params in `/boot/limine.conf`: `mem_sleep_default=s2idle` — T2 Macs lack ACPI S3 (deep sleep), so `s2idle` is the only suspend mode available. Setting it explicitly avoids the kernel attempting S3 and failing silently.

### Kernel Modules

- [`etc/mkinitcpio.conf.d/apple-t2.conf`](etc/mkinitcpio.conf.d/apple-t2.conf) — loads `apple-bce`, `usbhid`, `hid_apple`, `xhci_pci`, `xhci_hcd` in the initramfs. These must be available during early boot because the keyboard and trackpad are routed through the T2 chip's internal USB bus — without them, there's no input at the disk encryption prompt or recovery console.
- [`etc/modules-load.d/apple-bce.conf`](etc/modules-load.d/apple-bce.conf) — auto-load `apple-bce`
- [`etc/modules-load.d/facetimehd.conf`](etc/modules-load.d/facetimehd.conf) — auto-load `facetimehd` (webcam)

### Modprobe Options

- [`etc/modprobe.d/brcmfmac.conf`](etc/modprobe.d/brcmfmac.conf) — `feature_disable=0x82000` disables firmware features in the Broadcom WiFi driver that cause frequent disconnections and failed scans on the T2's BCM4364 chip. Without this flag, WiFi drops randomly or fails to connect after boot.
- [`etc/modprobe.d/hid_apple.conf`](etc/modprobe.d/hid_apple.conf) — `fnmode=2` makes the top row behave as F1–F12 by default, requiring Fn to access media keys. The kernel default (`fnmode=1`) is the opposite, which doesn't match the standard Linux desktop expectation for function keys.
- [`etc/modprobe.d/disable-usb-autosuspend.conf`](etc/modprobe.d/disable-usb-autosuspend.conf) — disables USB autosuspend (`autosuspend=-1`). The T2 routes the internal keyboard and trackpad over USB via `apple-bce`; with autosuspend enabled, the kernel suspends this bus after idle, causing the keyboard and trackpad to go unresponsive.

### Fan Control

The T2 chip normally manages fans through macOS firmware. Under Linux, there is no built-in fan management — without `t2fanrd`, fans may not spin up at all, risking thermal throttling or hardware damage.

- [`etc/t2fand.conf`](etc/t2fand.conf) — linear fan curve from 55°C to 75°C. Fans stay off below 55°C and ramp linearly to full speed at 75°C.
- Service: `t2fanrd.service` (enabled)

### Power Profiles (auto-switch on AC plug/unplug)

Automatically switches to `performance` on AC and `power-saver` on battery. Also plays plug/unplug sounds. Without this, the system stays on whatever profile was last set manually — easy to forget and either waste battery on performance mode or run sluggishly on AC in power-saver.

- [`usr/local/bin/power-config.sh`](usr/local/bin/power-config.sh) — main script (profile switch + sound)
- [`etc/udev/rules.d/95-power-config.rules`](etc/udev/rules.d/95-power-config.rules) — udev rule triggers script on power supply change
- [`etc/systemd/system/power-profile-boot.service`](etc/systemd/system/power-profile-boot.service) — systemd service sets correct profile at boot

### Power/Suspend

- `HandlePowerKey=ignore` in `/etc/systemd/logind.conf` — since suspend is broken on T2 Macs (see [Open Issues](#open-issues)), the power key is disabled to avoid accidentally triggering a suspend that results in a black screen requiring a hard reboot.
- [`etc/systemd/system.conf.d/10-faster-shutdown.conf`](etc/systemd/system.conf.d/10-faster-shutdown.conf) — reduces `DefaultTimeoutStopSec` from 90s to 5s. If a service hangs during shutdown (which T2 drivers occasionally do), the system force-kills it after 5 seconds instead of waiting a minute and a half.

### WiFi

- [`etc/udev/rules.d/99-wifi-powersave.rules`](etc/udev/rules.d/99-wifi-powersave.rules) — toggles WiFi power save based on AC state: enabled on battery to extend battery life, disabled on AC for lower latency and fewer dropouts. Update the username in the path before using.
- [`usr/lib/systemd/system-sleep/wifi-resume`](usr/lib/systemd/system-sleep/wifi-resume) — reloads `brcmfmac` after resume. The Broadcom driver loses its connection state through suspend on T2 Macs; without a full module reload, WiFi silently fails to reconnect after waking.

### Active Kernel Modules

`applesmc`, `apple_mfi_fastcharge`, `mac_hid`, `hid_magicmouse`, `hid_apple`, `apple_bce`, `facetimehd`

---

## Omarchy Customizations

### Keyboard Backlight Step Size

The T2 MacBook Air has 512 brightness levels for keyboard backlight (`apple::kbd_backlight`). Omarchy's default script (`omarchy-brightness-keyboard`) steps by 1 unit, assuming keyboards have only 3-4 discrete levels. Each keystroke changes brightness by ~0.2%.

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

## Cross-Reference with GitHub Issues

Sources:
- https://github.com/basecamp/omarchy/discussions/773
- https://github.com/basecamp/omarchy/issues/3883

| Suggestion | Status |
|---|---|
| T2 kernel + `apple-bce` | Done |
| `apple-bcm-firmware` for WiFi | Done |
| `hid_apple` + `usbhid` in mkinitcpio | Done |
| `pcie_ports=compat` boot param | Done |
| `intel_iommu=on iommu=pt` | Done |
| `brcmfmac feature_disable=0x82000` | Done |
| Fan daemon (`t2fanrd`) | Done |
| Webcam via `facetimehd` driver | Done |
| WiFi resume hook (reload `brcmfmac` after suspend) | Done |
| Keyboard backlight 10% step size | Done |
| Auto power profile (performance/power-saver) | Done (udev + systemd) |
| Natural voice screen reader (Orca + Piper TTS) | Done |
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
