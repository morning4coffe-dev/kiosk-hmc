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

# Ubuntu 22.04+ ships 'chromium' (snap); older releases use 'chromium-browser' (deb)
if apt-cache show chromium-browser &>/dev/null 2>&1; then
    CHROMIUM_PKG="chromium-browser"
else
    CHROMIUM_PKG="chromium"
fi

sudo apt install -y "$CHROMIUM_PKG" unclutter xdotool
echo "  -> Installed $CHROMIUM_PKG"

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
if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    DISPLAY_FLAGS="--ozone-platform=wayland --enable-features=UseOzonePlatform"
else
    # Disable screen blanking & screensaver (X11 only)
    xset s off
    xset s noblank
    xset -dpms
    DISPLAY_FLAGS=""
fi

# Hide mouse cursor after 3 s of inactivity
unclutter -idle 3 -root &

# Kill any existing Chromium instances
pkill -f "chromium" 2>/dev/null || true
sleep 1

# Resolve the correct binary name
CHROMIUM_BIN="chromium-browser"
command -v chromium-browser &>/dev/null || CHROMIUM_BIN="chromium"

# Load uBlock Origin extension if it exists
LOAD_EXT=""
if [ -d "$HOME/MediaCenter/extensions/ublock-origin" ]; then
    LOAD_EXT="--load-extension=$HOME/MediaCenter/extensions/ublock-origin"
fi

# Launch Chromium in kiosk mode
# --disable-popup-blocking: lets the launcher open services in new windows
# --homepage: Alt+Home returns here from any streaming site
# --user-agent: Samsung Tizen TV UA — gives TV UI on Netflix/Disney+/YouTube/etc.
$CHROMIUM_BIN \
    $DISPLAY_FLAGS \
    $LOAD_EXT \
    --user-agent="Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/4.0 Chrome/76.0.3809.146 TV Safari/537.36" \
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
    --enable-features=OverlayScrollbar \
    --autoplay-policy=no-user-gesture-required \
    --disable-popup-blocking \
    --homepage="file://$LAUNCHER" \
    --check-for-update-interval=31536000 \
    --disable-component-update \
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