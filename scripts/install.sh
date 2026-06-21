#!/usr/bin/env bash
# install.sh — Installs the Discord Dad Joke Bot on a Debian server.
# Run once as root: sudo bash scripts/install.sh
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
REPO_URL="https://github.com/DJTrumpDaddy/Discord-Dad-Joke-Bot.git"
BRANCH="main"
INSTALL_DIR="/opt/dadjoke-bot"
CONFIG_DIR="/etc/dadjoke-bot"
SERVICE_USER="dadjoke"
BOT_SERVICE="dadjoke-bot"
UPDATER_SERVICE="dadjoke-updater"

# ── Helpers ──────────────────────────────────────────────────────────────────
info()  { echo "[INFO]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || error "This script must be run as root (sudo bash $0)."
}

# ── Preflight ────────────────────────────────────────────────────────────────
require_root

[[ -f /etc/debian_version ]] || error "This script targets Debian/Ubuntu only."

# ── Install dependencies ──────────────────────────────────────────────────────
info "Installing system packages..."
apt-get update -y -q
apt-get install -y -q curl git ca-certificates

# Install .NET 8 SDK via Microsoft package feed if not already present
if ! command -v dotnet &>/dev/null || ! dotnet --list-sdks | grep -q '^8\.'; then
  info "Installing .NET 8 SDK..."
  # Detect Debian/Ubuntu version
  # shellcheck source=/dev/null
  source /etc/os-release
  DISTRO_ID="${ID:-debian}"
  VERSION="${VERSION_ID:-12}"

  MS_PKG="/tmp/packages-microsoft-prod.deb"
  curl -fsSL "https://packages.microsoft.com/config/${DISTRO_ID}/${VERSION}/packages-microsoft-prod.deb" \
    -o "$MS_PKG"
  dpkg -i "$MS_PKG"
  rm -f "$MS_PKG"
  apt-get update -y -q
  apt-get install -y -q dotnet-sdk-8.0
else
  info ".NET 8 SDK already present — skipping."
fi

# ── Service user ─────────────────────────────────────────────────────────────
if ! id "$SERVICE_USER" &>/dev/null; then
  info "Creating system user '$SERVICE_USER'..."
  useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
fi

# ── Clone or update repo ──────────────────────────────────────────────────────
if [[ -d "$INSTALL_DIR/repo/.git" ]]; then
  info "Repository already exists — pulling latest $BRANCH..."
  git -C "$INSTALL_DIR/repo" fetch origin "$BRANCH"
  git -C "$INSTALL_DIR/repo" checkout "$BRANCH"
  git -C "$INSTALL_DIR/repo" reset --hard "origin/$BRANCH"
else
  info "Cloning repository..."
  mkdir -p "$INSTALL_DIR"
  git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$INSTALL_DIR/repo"
fi

# ── Build & publish ───────────────────────────────────────────────────────────
info "Building and publishing..."
dotnet publish "$INSTALL_DIR/repo/src/DadJokeBot" \
  -c Release \
  -o "$INSTALL_DIR/publish" \
  --nologo -v quiet

# ── Config directory ─────────────────────────────────────────────────────────
mkdir -p "$CONFIG_DIR"

# Write the env file only if it doesn't already exist (preserve existing token)
if [[ ! -f "$CONFIG_DIR/env" ]]; then
  # Prompt for the bot token
  echo
  read -rp "Enter your Discord bot token: " BOT_TOKEN
  [[ -n "$BOT_TOKEN" ]] || error "Bot token cannot be empty."

  cat > "$CONFIG_DIR/env" <<EOF
# Environment variables for the Discord Dad Joke Bot.
# This file is NOT managed by git — it will not be overwritten on updates.
DADJOKE__BOT__TOKEN=${BOT_TOKEN}
DADJOKE__BOT__JOKESFILEPATH=data/dad_jokes.csv
DADJOKE__BOT__RESPONDTOHIDAD=false
# Uncomment and set to your test guild ID for instant command registration:
# DADJOKE__BOT__TESTGUILDID=
EOF
  chmod 600 "$CONFIG_DIR/env"
  info "Config written to $CONFIG_DIR/env"
else
  info "$CONFIG_DIR/env already exists — preserving existing configuration."
fi

chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR" "$CONFIG_DIR"

# ── Install updater script ────────────────────────────────────────────────────
install -o root -g root -m 755 \
  "$INSTALL_DIR/repo/scripts/dadjoke-updater.sh" \
  "$INSTALL_DIR/dadjoke-updater.sh"

# ── Install systemd unit: bot ─────────────────────────────────────────────────
cat > "/etc/systemd/system/${BOT_SERVICE}.service" <<EOF
[Unit]
Description=Discord Dad Joke Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}/publish
EnvironmentFile=${CONFIG_DIR}/env
ExecStart=/usr/bin/dotnet ${INSTALL_DIR}/publish/DadJokeBot.dll
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${BOT_SERVICE}

[Install]
WantedBy=multi-user.target
EOF

# ── Install systemd unit: updater ─────────────────────────────────────────────
cat > "/etc/systemd/system/${UPDATER_SERVICE}.service" <<EOF
[Unit]
Description=Discord Dad Joke Bot — auto-updater
After=network-online.target ${BOT_SERVICE}.service
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Environment=INSTALL_DIR=${INSTALL_DIR}
Environment=BOT_SERVICE=${BOT_SERVICE}
ExecStart=${INSTALL_DIR}/dadjoke-updater.sh
Restart=always
RestartSec=10s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${UPDATER_SERVICE}

[Install]
WantedBy=multi-user.target
EOF

# ── Enable and start ──────────────────────────────────────────────────────────
systemctl daemon-reload
systemctl enable --now "$BOT_SERVICE"
systemctl enable --now "$UPDATER_SERVICE"

info "Done."
echo
echo "  Bot status:     sudo systemctl status $BOT_SERVICE"
echo "  Updater status: sudo systemctl status $UPDATER_SERVICE"
echo "  Bot logs:       sudo journalctl -u $BOT_SERVICE -f"
echo "  Updater logs:   sudo journalctl -u $UPDATER_SERVICE -f"
echo "  Config:         $CONFIG_DIR/env"
