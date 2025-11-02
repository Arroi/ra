#!/usr/bin/env bash
# =============================================================================
#  ONE-CLICK: Keep Flutter Web + YOUR ./playit-linux-amd64 ALIVE (Debian)
#  1. Put your playit binary at: /usr/local/bin/playit-linux-amd64
#  2. Run: curl -sL https://raw.githubusercontent.com/Arroi/ra/main/ejb.sh
# =============================================================================

set -euo pipefail

log()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }

log "Starting auto-setup (NO playit.gg download)..."

# ----------------------------------------------------------------------
# 1. Check your playit binary exists
# ----------------------------------------------------------------------
PLAYIT_BIN="/usr/local/bin/playit-linux-amd64"
if [ ! -f "$PLAYIT_BIN" ]; then
    error "ERROR: $PLAYIT_BIN not found!
    → Download it from https://playit.gg
    → Place it at: $PLAYIT_BIN
    → Make executable: chmod +x $PLAYIT_BIN"
fi
chmod +x "$PLAYIT_BIN"
log "Found your playit binary: $PLAYIT_BIN"

# ----------------------------------------------------------------------
# 2. System packages
# ----------------------------------------------------------------------
log "Installing system packages..."
apt-get update -y
apt-get install -y --no-install-recommends \
    curl ca-certificates git unzip xz-utils libglu1-mesa openjdk-11-jdk \
    systemd procps net-tools

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
    log "Flutter already installed"
fi

# ----------------------------------------------------------------------
# 4. Minimal Flutter web app
# ----------------------------------------------------------------------
APP_DIR="/opt/flutter-web-app"
if [ ! -d "$APP_DIR" ]; then
    log "Creating demo Flutter web app..."
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
    log "Flutter app already exists"
fi

# ----------------------------------------------------------------------
# 5. Keep-alive daemon (uses YOUR playit binary)
# ----------------------------------------------------------------------
KEEPALIVE_SCRIPT="/usr/local/bin/keep-flutter-playit-alive.sh"

cat > "$KEEPALIVE_SCRIPT" <<EOS
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/flutter-web-app"
FLUTTER_DIR="/opt/flutter"
FLUTTER="\$FLUTTER_DIR/bin/flutter"
PLAYIT="$PLAYIT_BIN"
LOG="/var/log/keepalive.log"

log() { echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" | tee -a "\$LOG"; }

start_playit() {
    if ! pgrep -f "\$(basename "\$PLAYIT")" >/dev/null; then
        log "Starting YOUR playit-linux-amd64 tunnel..."
        nohup "\$PLAYIT" >/dev/null 2>&1 &
        sleep 5
    fi
}

start_flutter() {
    if ! pgrep -f "flutter.*web-server" >/dev/null; then
        log "Launching Flutter web server (:6000)..."
        pushd "\$APP_DIR" >/dev/null
        nohup "\$FLUTTER" run -d web-server \
            --web-port 6000 --web-hostname 0.0.0.0 \
            >/dev/null 2>&1 &
        popd >/dev/null
        sleep 10
    fi
}

health_check() {
    curl -fs --max-time 8 http://127.0.0.1:6000 >/dev/null
}

log "=== keepalive daemon started (using YOUR playit) ==="
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
    sleep 180
done
EOS

chmod +x "$KEEPALIVE_SCRIPT"

# ----------------------------------------------------------------------
# 6. systemd service
# ----------------------------------------------------------------------
SERVICE_FILE="/etc/systemd/system/keepalive.service"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Keep Flutter Web + YOUR playit-linux-amd64 Alive
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

[Install]
WantedBy=multi-user.target
EOF

# ----------------------------------------------------------------------
# 7. Enable & start
# ----------------------------------------------------------------------
log "Reloading systemd..."
systemctl daemon-reload
systemctl enable keepalive.service

log "Starting service..."
sleep 3
systemctl start keepalive.service

# ----------------------------------------------------------------------
# DONE
# ----------------------------------------------------------------------
log "ALL DONE!"
log "   • Flutter web → http://$(hostname -I | awk '{print $1}'):6000"
log "   • YOUR playit-linux-amd64 is running"
log "   • Logs: journalctl -u keepalive.service -f"
log "   • Reboot? It auto-starts."
log ""
log "Replace /opt/flutter-web-app with your real app anytime."
