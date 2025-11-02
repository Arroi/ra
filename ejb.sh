#!/usr/bin/env bash
# =============================================================================
#  ONE-CLICK: Keep Flutter Web + playit.gg ALIVE Forever (Debian)
#  Run on any Debian machine:
#    curl -sL https://raw.githubusercontent.com/yourname/keepalive/main/install.sh | sudo bash
# =============================================================================

set -euo pipefail

log() { echo -e "\033[1;32m[+]\033[0m $*"; }
error() { echo -e "\033[1;31m[-]\033[0m $*"; exit 1; }

log "Starting full auto-setup..."

# --- 1. Install dependencies -------------------------------------------------
log "Installing system packages..."
apt update -y
apt install -y curl git unzip xz-utils libglu1-mesa openjdk-11-jdk systemd

# --- 2. Install playit.gg ----------------------------------------------------
PLAYIT_BIN="/usr/local/bin/playit"
log "Installing playit.gg tunnel..."
curl -L -o "$PLAYIT_BIN" https://playit.gg/downloads/playit-linux_64
chmod +x "$PLAYIT_BIN"

# --- 3. Install Flutter ------------------------------------------------------
FLUTTER_DIR="/opt/flutter"
if [ ! -d "$FLUTTER_DIR" ]; then
    log "Installing Flutter SDK..."
    curl -L https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.3-stable.tar.xz | tar xJ -C /opt
    chown -R root:root "$FLUTTER_DIR"
fi
export PATH="$PATH:$FLUTTER_DIR/bin"

# --- 4. Create app directory -------------------------------------------------
APP_DIR="/opt/flutter-web-app"
if [ ! -d "$APP_DIR" ]; then
    log "Creating minimal Flutter web app..."
    mkdir -p "$APP_DIR"
    pushd "$APP_DIR" >/dev/null
    flutter create .
    # Enable web
    flutter config --enable-web
    # Replace main.dart with hello world
    cat > lib/main.dart <<'EOF'
import 'package:flutter/material.dart';
void main() => runApp(MaterialApp(home: Scaffold(
  body: Center(child: Text('KEEPALIVE ACTIVE - Flutter Web Running!')),
)));
EOF
    flutter pub get
    popd >/dev/null
fi

# --- 5. Create keep-alive script ---------------------------------------------
KEEPALIVE_SCRIPT="/usr/local/bin/keep-flutter-playit-alive.sh"

cat > "$KEEPALIVE_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/flutter-web-app"
FLUTTER="$FLUTTER_DIR/bin/flutter"
PLAYIT="/usr/local/bin/playit"
LOG="/var/log/keepalive.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG"; }

# Start playit
start_playit() {
    if ! pgrep -f playit > /dev/null; then
        log "Starting playit.gg tunnel..."
        nohup "$PLAYIT" >/dev/null 2>&1 &
        sleep 5
    fi
}

# Start Flutter web server
start_flutter() {
    if ! pgrep -f "flutter.*web-server" > /dev/null; then
        log "Starting Flutter web server on :6000..."
        pushd "$APP_DIR" >/dev/null
        nohup "$FLUTTER" run -d web-server --web-port 6000 --web-hostname 0.0.0.0 >/dev/null 2>&1 &
        popd >/dev/null
        sleep 8
    fi
}

# Health check
check() {
    curl -s -f http://127.0.0.1:6000 >/dev/null || return 1
    return 0
}

log "Keepalive service started"
while true; do
    start_playit
    start_flutter
    if check; then
        log "App is alive"
    else
        log "App DOWN — restarting..."
        pkill -f "flutter.*web-server" || true
        sleep 3
    fi
    sleep 180  # 3 minutes
done
EOF

chmod +x "$KEEPALIVE_SCRIPT"

# --- 6. Systemd service ------------------------------------------------------
SERVICE_FILE="/etc/systemd/system/keepalive.service"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Keep Flutter Web + playit.gg Alive
After=network.target

[Service]
Type=simple
ExecStart=$KEEPALIVE_SCRIPT
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment=PATH=/usr/local/bin:/usr/bin:/bin:$FLUTTER_DIR/bin

[Install]
WantedBy=multi-user.target
EOF

# --- 7. Enable & start -------------------------------------------------------
systemctl daemon-reload
systemctl enable --now keepalive.service

# --- Done -------------------------------------------------------------------
log "ALL DONE!"
log "   - Flutter web: http://YOUR-IP:6000"
log "   - playit.gg tunnel: running"
log "   - Logs: journalctl -u keepalive.service -f"
log "   - Reboot? It will auto-start."
echo
echo "Replace /opt/flutter-web-app with your own app later."
echo "Your web app is now IMMORTAL."
