#!/usr/bin/env bash
# =============================================================================
#  ONE-CLICK: Keep Flutter Web + playit.gg ALIVE Forever (Debian 11/12)
#  Run: curl -sL https://raw.githubusercontent.com/yourname/keepalive/main/install.sh | sudo bash
# =============================================================================

set -euo pipefail

log()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }

log "Starting full auto-setup..."

# ----------------------------------------------------------------------
# 1. System packages (including TLS certs)
# ----------------------------------------------------------------------
log "Updating package index..."
apt-get update -y

log "Installing required packages..."
apt-get install -y --no-install-recommends \
    curl ca-certificates git unzip xz-utils libglu1-mesa openjdk-11-jdk \
    systemd procps net-tools

# ----------------------------------------------------------------------
# 2. playit.gg tunnel
# ----------------------------------------------------------------------
PLAYIT_BIN="/usr/local/bin/playit"
log "Downloading playit.gg..."
curl -fsSL https://playit.gg/downloads/playit-linux_64 -o "$PLAYIT_BIN"
chmod +x "$PLAYIT_BIN"

# ----------------------------------------------------------------------
# 3. Flutter SDK
# ----------------------------------------------------------------------
FLUTTER_DIR="/opt/flutter"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.3-stable.tar.xz"

if [ ! -d "$FLUTTER_DIR" ]; then
    log "Downloading Flutter SDK..."
    curl -fsSL "$FLUTTER_URL" | tar xJ -C /opt
    chown -R root:root "$FLUTTER_DIR"
else
    log "Flutter already present – skipping download"
fi

# ----------------------------------------------------------------------
# 4. Minimal Flutter web app
# ----------------------------------------------------------------------
APP_DIR="/opt/flutter-web-app"
if [ ! -d "$APP_DIR" ]; then
    log "Creating a tiny Flutter web demo..."
    mkdir -p "$APP_DIR"
    pushd "$APP_DIR" >/dev/null

    "$FLUTTER_DIR/bin/flutter" create --platforms=web .
    "$FLUTTER_DIR/bin/flutter" config --enable-web

    cat > lib/main.dart <<'EOF'
import 'package:flutter/material.dart';
void main() => runApp(const MaterialApp(
  home: Scaffold(
    body: Center(child: Text('KEEPALIVE ACTIVE – Flutter Web Running!')),
  ),
));
EOF

    "$FLUTTER_DIR/bin/flutter" pub get
    popd >/dev/null
else
    log "Flutter app already exists – skipping"
fi

# ----------------------------------------------------------------------
# 5. Keep-alive daemon script
# ----------------------------------------------------------------------
KEEPALIVE_SCRIPT="/usr/local/bin/keep-flutter-playit-alive.sh"

cat > "$KEEPALIVE_SCRIPT" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/flutter-web-app"
FLUTTER_DIR="/opt/flutter"
FLUTTER="$FLUTTER_DIR/bin/flutter"
PLAYIT="/usr/local/bin/playit"
LOG="/var/log/keepalive.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG"; }

start_playit() {
    if ! pgrep -f "$(basename "$PLAYIT")" >/dev/null; then
        log "Starting playit.gg tunnel..."
        nohup "$PLAYIT" >/dev/null 2>&1 &
        sleep 5
    fi
}

start_flutter() {
    if ! pgrep -f "flutter.*web-server" >/dev/null; then
        log "Launching Flutter web server (:6000)..."
        pushd "$APP_DIR" >/dev/null
        nohup "$FLUTTER" run -d web-server \
            --web-port 6000 --web-hostname 0.0.0.0 \
            >/dev/null 2>&1 &
        popd >/dev/null
        sleep 10
    fi
}

health_check() {
    curl -fs --max-time 8 http://127.0.0.1:6000 >/dev/null
}

log "=== keepalive daemon started ==="
while :; do
    start_playit
    start_flutter
    if health_check; then
        log "Web app healthy"
    else
        log "Web app DOWN – restarting Flutter..."
        pkill -f "flutter.*web-server" || true
        sleep 3
    fi
    sleep 180   # 3-minute ping interval
done
EOS

chmod +x "$KEEPALIVE_SCRIPT"

# ----------------------------------------------------------------------
# 6. systemd service (robust)
# ----------------------------------------------------------------------
SERVICE_FILE="/etc/systemd/system/keepalive.service"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Keep Flutter Web + playit.gg Alive
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$KEEPALIVE_SCRIPT
Restart=always
RestartSec=12
StandardOutput=journal
StandardError=journal
Environment=PATH=/usr/local/bin:/usr/bin:/bin:$FLUTTER_DIR/bin
Environment=FLUTTER_HOME=$FLUTTER_DIR
User=root
WorkingDirectory=/root

[Install]
WantedBy=multi-user.target
EOF

# ----------------------------------------------------------------------
# 7. Enable & start
# ----------------------------------------------------------------------
log "Reloading systemd..."
systemctl daemon-reload

log "Enabling service..."
systemctl enable keepalive.service

log "Starting service (with short delay)..."
sleep 3
systemctl start keepalive.service

# ----------------------------------------------------------------------
# DONE
# ----------------------------------------------------------------------
log "ALL DONE!"
log "   • Flutter web → http://$(hostname -I | awk '{print $1}'):6000"
log "   • playit.gg tunnel is running"
log "   • Logs: journalctl -u keepalive.service -f"
log "   • Reboot? Service will auto-start."
log ""
log "Replace /opt/flutter-web-app with your own project whenever you want."
