#!/bin/bash
# ============================================================
#  Ubuntu Media Center Kiosk Setup
#  Turns your old notebook into a streaming box
# ============================================================

set -e

USER_NAME=$(whoami)
# Changed to a visible directory (removed the dot) for Snap compatibility
LAUNCHER_DIR="$HOME/MediaCenter"
LAUNCHER_HTML="$LAUNCHER_DIR/launcher.html"
EXTENSIONS_DIR="$LAUNCHER_DIR/extensions"
UBLOCK_DIR="$EXTENSIONS_DIR/ublock-origin"
AUTOSTART_DIR="$HOME/.config/autostart"
DESKTOP_FILE="$AUTOSTART_DIR/media-center.desktop"

echo "==========================================="
echo "  Media Center Kiosk Setup"
echo "  User: $USER_NAME"
echo "==========================================="
echo ""

# ----------------------------------------------------------
# 1. Install required packages
# ----------------------------------------------------------
echo "[1/6] Installing packages..."
sudo apt update -qq

sudo apt install -y unclutter xdotool unzip curl python3 git wget

# Google Chrome is strongly preferred — it ships with Widevine DRM which is
# required by Netflix, OnePlay, Disney+ and other streaming services.
# Chromium does NOT include Widevine by default on Linux.
if command -v google-chrome-stable &>/dev/null || command -v google-chrome &>/dev/null; then
    echo "  -> Google Chrome already installed"
else
    echo "  -> Installing Google Chrome (required for DRM/Widevine)..."
    CHROME_DEB=$(mktemp --suffix=.deb)
    wget -q "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" -O "$CHROME_DEB" 2>/dev/null \
        || curl -sL "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" -o "$CHROME_DEB" 2>/dev/null
    if [ -s "$CHROME_DEB" ]; then
        sudo dpkg -i "$CHROME_DEB" 2>/dev/null || sudo apt install -f -y
        rm -f "$CHROME_DEB"
        echo "  -> Google Chrome installed"
    else
        echo "  !! Could not download Google Chrome."
        echo "     Falling back to Chromium (DRM may not work without manual Widevine setup)."
        if apt-cache show chromium-browser &>/dev/null 2>&1; then
            CHROMIUM_PKG="chromium-browser"
        else
            CHROMIUM_PKG="chromium"
        fi
        sudo apt install -y "$CHROMIUM_PKG"
        echo "  -> Installed $CHROMIUM_PKG (Widevine not included)"
    fi
fi

# ----------------------------------------------------------
# 2. Enable auto-login (GDM3 or LightDM)
# ----------------------------------------------------------
echo ""
echo "[2/6] Configuring auto-login..."

# GDM3 (Ubuntu default)
GDM_CONF="/etc/gdm3/custom.conf"
if [ -f "$GDM_CONF" ]; then
    sudo cp "$GDM_CONF" "${GDM_CONF}.bak"
    sudo sed -i "s/^#\s*AutomaticLoginEnable.*/AutomaticLoginEnable = true/" "$GDM_CONF"
    sudo sed -i "s/^#\s*AutomaticLogin .*/AutomaticLogin = $USER_NAME/" "$GDM_CONF"
    # If the lines don't exist yet, add them
    if ! grep -q "AutomaticLoginEnable" "$GDM_CONF"; then
        sudo sed -i "/\[daemon\]/a AutomaticLoginEnable = true\nAutomaticLogin = $USER_NAME" "$GDM_CONF"
    fi
    echo "  -> GDM3 auto-login configured for '$USER_NAME'"
fi

# LightDM (some Ubuntu flavours)
LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
if [ -f "$LIGHTDM_CONF" ] || dpkg -l lightdm &>/dev/null 2>&1; then
    sudo mkdir -p /etc/lightdm
    sudo tee "$LIGHTDM_CONF" > /dev/null <<EOF
[Seat:*]
autologin-user=$USER_NAME
autologin-user-timeout=0
EOF
    echo "  -> LightDM auto-login configured for '$USER_NAME'"
fi

# ----------------------------------------------------------
# 3. Create launcher directory & copy HTML
# ----------------------------------------------------------
echo ""
echo "[3/6] Setting up launcher page..."
mkdir -p "$LAUNCHER_DIR"

# The launcher.html should be placed next to this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/launcher.html" ]; then
    cp "$SCRIPT_DIR/launcher.html" "$LAUNCHER_HTML"
    echo "  -> Copied launcher.html to $LAUNCHER_DIR"
else
    echo "  !! launcher.html not found next to this script."
    echo "     Place it at: $SCRIPT_DIR/launcher.html"
    echo "     and re-run, or copy it manually to: $LAUNCHER_HTML"
fi

if [ -f "$SCRIPT_DIR/updater.py" ]; then
    cp "$SCRIPT_DIR/updater.py" "$LAUNCHER_DIR/updater.py"
    chmod +x "$LAUNCHER_DIR/updater.py"
    echo "  -> Copied updater.py to $LAUNCHER_DIR"
else
    echo "  !! updater.py not found next to this script."
    echo "     Place it at: $SCRIPT_DIR/updater.py"
    echo "     to enable UI-driven updates."
fi

# Copy bundled extensions (e.g. YouTube TV UA override)
if [ -d "$SCRIPT_DIR/extensions" ]; then
    cp -r "$SCRIPT_DIR/extensions/"* "$EXTENSIONS_DIR/" 2>/dev/null || true
    echo "  -> Copied bundled extensions to $EXTENSIONS_DIR"
fi

# ----------------------------------------------------------
# 4. Install uBlock Origin adblocker
# ----------------------------------------------------------
echo ""
echo "[4/6] Installing uBlock Origin extension..."
mkdir -p "$EXTENSIONS_DIR"

# Download and extract uBlock Origin (latest release from GitHub)
UBLOCK_URL="https://github.com/gorhill/uBlock/releases/download/1.58.0/uBlock0.chromium.zip"
TEMP_ZIP=$(mktemp)

if command -v wget &>/dev/null; then
    wget -q "$UBLOCK_URL" -O "$TEMP_ZIP" 2>/dev/null || {
        echo "  !! Failed to download uBlock Origin with wget"
        TEMP_ZIP=""
    }
elif command -v curl &>/dev/null; then
    curl -sL "$UBLOCK_URL" -o "$TEMP_ZIP" 2>/dev/null || {
        echo "  !! Failed to download uBlock Origin with curl"
        TEMP_ZIP=""
    }
fi

if [ -n "$TEMP_ZIP" ] && [ -f "$TEMP_ZIP" ]; then
    rm -rf "$UBLOCK_DIR"
    mkdir -p "$UBLOCK_DIR"
    unzip -q "$TEMP_ZIP" -d "$UBLOCK_DIR"
    rm "$TEMP_ZIP"
    echo "  -> uBlock Origin installed to $UBLOCK_DIR"
else
    echo "  !! Could not download uBlock Origin. You'll need to install it manually."
    echo "     - Install from Chrome Web Store: https://chrome.google.com/webstore"
    echo "     - Search for 'uBlock Origin'"
fi

# SponsorBlock — auto-skip YouTube sponsor segments
echo "  -> Installing SponsorBlock for YouTube..."
SPONSORBLOCK_URL="https://github.com/nichobi/nichobi.github.io/raw/master/nichobi-sponsorblock-chrome.zip"
SPONSORBLOCK_DIR="$EXTENSIONS_DIR/sponsorblock"
TEMP_ZIP2=$(mktemp)
wget -q "$SPONSORBLOCK_URL" -O "$TEMP_ZIP2" 2>/dev/null || curl -sL "$SPONSORBLOCK_URL" -o "$TEMP_ZIP2" 2>/dev/null || true
if [ -s "$TEMP_ZIP2" ]; then
    rm -rf "$SPONSORBLOCK_DIR"; mkdir -p "$SPONSORBLOCK_DIR"
    unzip -q "$TEMP_ZIP2" -d "$SPONSORBLOCK_DIR" 2>/dev/null || true
    rm -f "$TEMP_ZIP2"
    echo "  -> SponsorBlock installed"
else
    echo "  !! SponsorBlock download failed (optional, skipping)"
fi

# Dark Reader — force dark mode on all sites
echo "  -> Installing Dark Reader..."
DARKREADER_URL="https://github.com/nichobi/nichobi.github.io/raw/master/nichobi-darkreader-chrome.zip"
DARKREADER_DIR="$EXTENSIONS_DIR/dark-reader"
TEMP_ZIP3=$(mktemp)
wget -q "$DARKREADER_URL" -O "$TEMP_ZIP3" 2>/dev/null || curl -sL "$DARKREADER_URL" -o "$TEMP_ZIP3" 2>/dev/null || true
if [ -s "$TEMP_ZIP3" ]; then
    rm -rf "$DARKREADER_DIR"; mkdir -p "$DARKREADER_DIR"
    unzip -q "$TEMP_ZIP3" -d "$DARKREADER_DIR" 2>/dev/null || true
    rm -f "$TEMP_ZIP3"
    echo "  -> Dark Reader installed"
else
    echo "  !! Dark Reader download failed (optional, skipping)"
fi

# ----------------------------------------------------------
# 5. Create the kiosk launch script
# ----------------------------------------------------------
echo ""
echo "[5/6] Creating kiosk launch script..."

cat > "$LAUNCHER_DIR/start-kiosk.sh" <<'KIOSK'
#!/bin/bash
# Wait for the desktop to fully load
sleep 3

LAUNCHER="$HOME/MediaCenter/launcher.html"

# Detect Wayland vs X11
DISPLAY_FLAGS=()
if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    DISPLAY_FLAGS+=(--ozone-platform=wayland --enable-features=UseOzonePlatform)
else
    # Disable screen blanking & screensaver (X11 only)
    xset s off
    xset s noblank
    xset -dpms
fi

# Hide mouse cursor after 3 s of inactivity
unclutter -idle 3 -root &

# Kill any existing browser instances from previous kiosk runs
pkill -f "google-chrome|chromium" 2>/dev/null || true
sleep 1

# Prefer browsers Netflix officially supports when available.
# Chromium remains a fallback, but desktop playback is usually more reliable in
# Google Chrome than in a Chromium build pretending to be a smart TV.
BROWSER_BIN=""
for candidate in google-chrome-stable google-chrome chromium-browser chromium; do
    if command -v "$candidate" &>/dev/null; then
        BROWSER_BIN="$candidate"
        break
    fi
done

if [ -z "$BROWSER_BIN" ]; then
    echo "No supported browser binary found."
    exit 1
fi

# Load all unpacked extensions from the extensions directory
EXTENSION_FLAGS=()
EXT_PATHS=""
for ext_dir in "$HOME/MediaCenter/extensions"/*/; do
    [ -f "${ext_dir}manifest.json" ] && EXT_PATHS="${EXT_PATHS:+$EXT_PATHS,}${ext_dir%/}"
done
if [ -n "$EXT_PATHS" ]; then
    EXTENSION_FLAGS+=(--load-extension="$EXT_PATHS")
fi

# Start the local updater service if available.
if [ -f "$HOME/MediaCenter/updater.py" ]; then
    pkill -f "updater.py" 2>/dev/null || true
    python3 "$HOME/MediaCenter/updater.py" >/tmp/media-center-updater.log 2>&1 &
fi

# IMPORTANT: Do NOT override the user agent. Fake TV/Chromecast UAs break DRM
# because Netflix/OnePlay/Disney+ then expect a certified device stack.
# The browser's native UA + Widevine (included in Google Chrome) is all we need.
# YouTube TV interface is accessed via youtube.com/tv URL, no UA trick needed.

# Launch the browser in kiosk mode
# --disable-popup-blocking: lets the launcher open services in new windows
# --homepage: Alt+Home returns here from any streaming site
"$BROWSER_BIN" \
    "${DISPLAY_FLAGS[@]}" \
    "${EXTENSION_FLAGS[@]}" \
    --allow-file-access-from-files \
    --kiosk \
    --start-fullscreen \
    --start-maximized \
    --no-first-run \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-features=TranslateUI \
    --disable-pinch \
    --overscroll-history-navigation=0 \
    --password-store=basic \
    --noerrdialogs \
    --enable-features=OverlayScrollbar,VaapiVideoDecoder,VaapiVideoEncoder \
    --autoplay-policy=no-user-gesture-required \
    --disable-popup-blocking \
    --enable-gpu-rasterization \
    --enable-zero-copy \
    --ignore-gpu-blocklist \
    --enable-accelerated-video-decode \
    --homepage="file://$LAUNCHER" \
    "file://$LAUNCHER"
KIOSK

chmod +x "$LAUNCHER_DIR/start-kiosk.sh"
echo "  -> Created $LAUNCHER_DIR/start-kiosk.sh"

# ----------------------------------------------------------
# 6. Register as autostart application
# ----------------------------------------------------------
echo ""
echo "[6/7] Registering autostart entry..."
mkdir -p "$AUTOSTART_DIR"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Media Center Kiosk
Exec=$LAUNCHER_DIR/start-kiosk.sh
X-GNOME-Autostart-enabled=true
EOF

echo "  -> Created $DESKTOP_FILE"

# ----------------------------------------------------------
# 7. Power & performance tweaks
# ----------------------------------------------------------
echo ""
echo "[7/7] Applying power & performance tweaks..."

# Prevent lid-close suspend (so you can close the notebook lid
# if using an external monitor)
LOGIND_CONF="/etc/systemd/logind.conf"
if [ -f "$LOGIND_CONF" ]; then
    sudo cp "$LOGIND_CONF" "${LOGIND_CONF}.bak"
    sudo sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' "$LOGIND_CONF"
    sudo sed -i 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' "$LOGIND_CONF"
    sudo sed -i 's/^#\?IdleAction=.*/IdleAction=ignore/' "$LOGIND_CONF"
    echo "  -> Lid-close suspend disabled"
    echo "  -> Idle suspend disabled"
fi

# Disable GNOME automatic screen lock & blank
gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
gsettings set org.gnome.desktop.screensaver idle-activation-enabled false 2>/dev/null || true
gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' 2>/dev/null || true
echo "  -> GNOME screen lock & sleep disabled"

echo ""
echo "==========================================="
echo "  Setup complete!"
echo "==========================================="
echo ""
echo "  WHAT'S NEXT:"
echo ""
echo "  1. Reboot to test auto-login + kiosk:"
echo "       sudo reboot"
echo ""
echo "  2. Navigation shortcuts (shown on-screen in the launcher):"
echo "     - Alt+Home    : return to the launcher from any streaming site"
echo "     - Alt+F4      : close the current window / exit kiosk"
echo "     - Ctrl+Alt+T  : open a terminal (exit kiosk entirely)"
echo ""
echo "  3. Installed & recommended extensions:"
echo "     ✓ uBlock Origin    (blocks ads on YouTube & all sites)"
echo ""
echo "     Optional extensions (install manually from Chrome Web Store):"
echo "     - SponsorBlock     (skips YouTube sponsor segments)"
echo "     - Return Dislike   (restores YouTube dislike count)"
echo "     - Dark Reader      (dark mode on all sites)"
echo "     - Vimium           (keyboard navigation)"
echo ""
echo "  4. After first boot, sign in to Netflix/YouTube/etc."
echo "     once — Chromium will remember your sessions."
echo ""
echo "  5. To disable kiosk mode later:"
echo "       rm $DESKTOP_FILE"
echo ""
echo "==========================================="