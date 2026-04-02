#!/bin/bash
# ============================================================
#  Ubuntu Media Center Kiosk Setup
#  Turns your old notebook into a streaming box
# ============================================================

set -e

USER_NAME=$(whoami)
LAUNCHER_DIR="$HOME/.media-center"
LAUNCHER_HTML="$LAUNCHER_DIR/launcher.html"
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
sudo apt install -y chromium-browser unclutter xdotool

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
# 4. Create the kiosk launch script
# ----------------------------------------------------------
echo ""
echo "[4/6] Creating kiosk launch script..."

cat > "$LAUNCHER_DIR/start-kiosk.sh" <<'KIOSK'
#!/bin/bash
# Wait for the desktop to fully load
sleep 3

# Disable screen blanking & screensaver
xset s off
xset s noblank
xset -dpms

# Hide the mouse cursor after 3 seconds of inactivity
unclutter -idle 3 -root &

# Kill any existing Chromium instances
pkill -f chromium-browser 2>/dev/null || true
sleep 1

LAUNCHER="$HOME/.media-center/launcher.html"

# Launch Chromium in kiosk mode
chromium-browser \
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
    --check-for-update-interval=31536000 \
    --disable-component-update \
    "file://$LAUNCHER"
KIOSK

chmod +x "$LAUNCHER_DIR/start-kiosk.sh"
echo "  -> Created $LAUNCHER_DIR/start-kiosk.sh"

# ----------------------------------------------------------
# 5. Register as autostart application
# ----------------------------------------------------------
echo ""
echo "[5/6] Registering autostart entry..."
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
# 6. Power & performance tweaks
# ----------------------------------------------------------
echo ""
echo "[6/6] Applying power & performance tweaks..."

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
echo "  2. To EXIT kiosk mode:  Alt+F4  or  Ctrl+Alt+T (terminal)"
echo ""
echo "  3. Recommended Chromium extensions (install manually):"
echo "     - uBlock Origin   (blocks YouTube ads)"
echo "     - SponsorBlock     (skips YouTube sponsor segments)"
echo "     - Return Dislike   (restores YouTube dislike count)"
echo "     - Dark Reader       (dark mode on all sites)"
echo "     - Vimium            (keyboard navigation)"
echo ""
echo "  4. After first boot, sign in to Netflix/YouTube/etc."
echo "     once — Chromium will remember your sessions."
echo ""
echo "  5. To disable kiosk mode later:"
echo "       rm $DESKTOP_FILE"
echo ""
echo "==========================================="
