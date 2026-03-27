#!/bin/bash
set -euo pipefail

# Pinned for reproducibility. Check https://github.com/rhasspy/piper/releases for newer versions.
PIPER_VERSION="2023.11.14-2"
PIPER_URL="https://github.com/rhasspy/piper/releases/download/${PIPER_VERSION}/piper_linux_x86_64.tar.gz"
VOICE_BASE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium"
VOICE_NAME="en_US-lessac-medium"

PIPER_BIN="$HOME/.local/bin/piper-tts"
PIPER_LIB="$HOME/.local/share/piper-tts/lib"
PIPER_VOICES="$HOME/.local/share/piper-tts/voices"
SPEECHD_MODULES="/etc/speech-dispatcher/modules"
SPEECHD_CONF="/etc/speech-dispatcher/speechd.conf"

info() { echo "=> $1"; }
fail() { echo "ERROR: $1" >&2; exit 1; }

if ! command -v orca &>/dev/null; then
    fail "orca is not installed. Install it first: sudo pacman -S orca"
fi

if ! command -v paplay &>/dev/null; then
    fail "paplay is not installed. Install pulseaudio-utils or pipewire-pulse."
fi

# Download and install piper binary + libraries
if [ -x "$PIPER_BIN" ]; then
    info "piper-tts binary already installed, skipping download"
else
    info "Downloading piper ${PIPER_VERSION}..."
    TMP=$(mktemp -d)
    curl -L "$PIPER_URL" -o "$TMP/piper.tar.gz"
    tar xzf "$TMP/piper.tar.gz" -C "$TMP"

    mkdir -p "$(dirname "$PIPER_BIN")" "$PIPER_LIB"
    cp "$TMP/piper/piper" "$PIPER_BIN"
    chmod +x "$PIPER_BIN"
    cp "$TMP"/piper/lib*.so* "$TMP"/piper/libtashkeel_model.ort "$PIPER_LIB/"
    cp "$TMP/piper/espeak-ng" "$PIPER_LIB/"
    cp -r "$TMP/piper/espeak-ng-data" "$PIPER_LIB/"

    rm -rf "$TMP"
    info "piper-tts installed to $PIPER_BIN"
fi

# Download voice model
if [ -f "$PIPER_VOICES/${VOICE_NAME}.onnx" ]; then
    info "Voice model already downloaded, skipping"
else
    info "Downloading voice model: ${VOICE_NAME}..."
    mkdir -p "$PIPER_VOICES"
    curl -L "${VOICE_BASE_URL}/${VOICE_NAME}.onnx" -o "$PIPER_VOICES/${VOICE_NAME}.onnx"
    curl -L "${VOICE_BASE_URL}/${VOICE_NAME}.onnx.json" -o "$PIPER_VOICES/${VOICE_NAME}.onnx.json"
    info "Voice model downloaded"
fi

# Verify piper works
info "Testing piper binary..."
export LD_LIBRARY_PATH="$PIPER_LIB"
echo "test" | "$PIPER_BIN" --model "$PIPER_VOICES/${VOICE_NAME}.onnx" --output_file /dev/null 2>/dev/null \
    || fail "piper-tts binary failed. Check library dependencies."

# Create speech-dispatcher module config (requires sudo)
info "Configuring speech-dispatcher (requires sudo)..."

sudo tee "$SPEECHD_MODULES/piper-tts.conf" > /dev/null << CONF
Debug 0

GenericExecuteSynth \\
"export LD_LIBRARY_PATH=${PIPER_LIB} && printf %s '\$DATA' | ${PIPER_BIN} --model ${PIPER_VOICES}/${VOICE_NAME}.onnx --output_raw | paplay --raw --rate=22050 --channels=1 --format=s16le"

GenericCmdDependency "piper-tts"
GenericSoundIconFolder "/usr/share/sounds/sound-icons/"

GenericPunctNone ""
GenericPunctSome ""
GenericPunctAll ""

GenericRateAdd 0
GenericPitchAdd 0
GenericVolumeAdd 0

AddVoice "en" "FEMALE1" "${VOICE_NAME}"
DefaultVoice "${VOICE_NAME}"
CONF

# Register module in speechd.conf if not already present
if ! grep -q 'AddModule "piper-tts"' "$SPEECHD_CONF"; then
    sudo sed -i '/#AddModule "cicero"/a\\nAddModule "piper-tts" "sd_generic" "piper-tts.conf"' "$SPEECHD_CONF"
    info "Registered piper-tts module in speechd.conf"
else
    info "piper-tts module already registered in speechd.conf"
fi

# Set piper-tts as default module if not already
if ! grep -q '^DefaultModule piper-tts' "$SPEECHD_CONF"; then
    if grep -q '^DefaultModule ' "$SPEECHD_CONF"; then
        sudo sed -i 's/^DefaultModule .*/DefaultModule piper-tts/' "$SPEECHD_CONF"
    else
        sudo sed -i 's/^# DefaultModule espeak-ng/# DefaultModule espeak-ng\nDefaultModule piper-tts/' "$SPEECHD_CONF"
    fi
    info "Set piper-tts as default speech-dispatcher module"
else
    info "piper-tts already set as default module"
fi

# Restart speech-dispatcher and test
killall speech-dispatcher 2>/dev/null || true
sleep 1

info "Testing speech-dispatcher integration..."
spd-say -o piper-tts -w "Piper text to speech is ready"

echo ""
echo "Setup complete! Orca will now use the piper natural voice."
echo "Launch Orca with: orca"
echo "Test manually with: spd-say -o piper-tts \"hello world\""
