#!/usr/bin/env bash
# wizard.sh — Interactive TUI installer for Discord Dad Joke Bot
# Usage: curl -fsSL https://raw.githubusercontent.com/DJTrumpDaddy/Discord-Dad-Joke-Bot/main/scripts/wizard.sh \
#          -o /tmp/dadjoke-wizard.sh && sudo bash /tmp/dadjoke-wizard.sh
set -euo pipefail

# ── Constants ──────────────────────────────────────────────────────────────────────
REPO_URL="https://github.com/DJTrumpDaddy/Discord-Dad-Joke-Bot.git"
BRANCH="main"
INSTALL_DIR="/opt/dadjoke-bot"
CONFIG_DIR="/etc/dadjoke-bot"
SERVICE_USER="dadjoke"
BOT_SERVICE="dadjoke-bot"
UPDATER_SERVICE="dadjoke-updater"
LOG="/tmp/dadjoke-install.log"
W=72   # dialog width
TT="Discord Dad Joke Bot Installer"

# ── Globals set later ────────────────────────────────────────────────────────────
FIFO=""
GAUGE_PID=""

# ── Cleanup ─────────────────────────────────────────────────────────────────────
cleanup() {
  [[ -n "$FIFO" ]]      && { exec 3>&- 2>/dev/null || true; rm -f "$FIFO"; }
  [[ -n "$GAUGE_PID" ]] && { kill "$GAUGE_PID" 2>/dev/null || true; }
}
trap cleanup EXIT

# ── whiptail helper (swaps stdout/stderr so we can capture the result) ───────
# whiptail draws the UI on stderr and writes the user's input to stdout.
# The swap lets us do: VAR=$(wt --inputbox ...) and get the typed text.
wt() { whiptail --title "$TT" "$@" 3>&1 1>&2 2>&3; }

# ── Preflight ───────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "This installer must be run as root."
  echo "Try:"
  echo "  curl -fsSL https://raw.githubusercontent.com/DJTrumpDaddy/Discord-Dad-Joke-Bot/main/scripts/wizard.sh \\"
  echo "    -o /tmp/dadjoke-wizard.sh && sudo bash /tmp/dadjoke-wizard.sh"
  exit 1
fi

[[ -f /etc/debian_version ]] || { echo "Debian/Ubuntu only." >&2; exit 1; }

if ! command -v whiptail &>/dev/null; then
  echo "Installing whiptail..."
  apt-get update -y -q
  apt-get install -y -q whiptail
fi

# ── Screen 1: Welcome ───────────────────────────────────────────────────────────
whiptail --title "$TT" --msgbox \
"Welcome! This wizard will:

  • Install .NET 8 and build dependencies via apt
  • Download and compile the bot from GitHub
  • Create a dedicated 'dadjoke' system user
  • Register and start two systemd services:

      dadjoke-bot      — runs the bot
      dadjoke-updater  — auto-pulls updates every 30 s

Press Enter to continue." 17 $W

# ── Screen 2: Discord Developer Portal reminder ────────────────────────
whiptail --title "$TT" --msgbox \
"You'll need a Discord bot token before continuing.

  1. Go to discord.com/developers/applications
  2. Create or select your application
  3. Open the Bot tab → click Reset Token → copy it

To support both server and personal installs:
  Installation → enable Guild Install + User Install
  Scopes → check bot and applications.commands

Press Enter when ready." 17 $W

# ── Screen 3: Bot token ───────────────────────────────────────────────────────
BOT_TOKEN=""
while [[ -z "$BOT_TOKEN" ]]; do
  BOT_TOKEN=$(wt --passwordbox "Enter your Discord bot token:" 9 $W "") \
    || { clear; exit 0; }
  [[ -z "$BOT_TOKEN" ]] && whiptail --title "$TT" --msgbox "Token cannot be empty." 7 $W
done

# ── Screen 4: Hi-Dad responder ─────────────────────────────────────────────────
RESPOND_TO_HI_DAD="false"
if whiptail --title "$TT" --yesno \
"Enable the Hi-Dad auto-responder?

When on, the bot replies to messages like
\"Hi @BotName\" with \"Hi [you], I'm Dad!\" + a joke.

Requires enabling the Message Content privileged
intent in the Developer Portal (Bot → Intents)
before the bot will work correctly.

Enable it?" 16 $W; then
  RESPOND_TO_HI_DAD="true"
fi

# ── Screen 5: Test Guild ID ─────────────────────────────────────────────────────
TEST_GUILD_ID=$(wt --inputbox \
"Test Guild ID (optional)

Enter a Discord server ID to register slash commands
to that guild instantly (useful during development).

Leave blank to use global registration, which works
in all servers but takes up to one hour to propagate.

Server ID (or leave blank for global):" 17 $W "") || { clear; exit 0; }
TEST_GUILD_ID="${TEST_GUILD_ID//[[:space:]]/}"

# ── Screen 6: Confirm ────────────────────────────────────────────────────────────────
TOKEN_PREVIEW="$(printf '%.12s' "$BOT_TOKEN")••••"
GUILD_DISPLAY="${TEST_GUILD_ID:-"(global — ~1 hour propagation)"}"

whiptail --title "$TT" --yesno \
"Ready to install. Review your choices:

  Token:            $TOKEN_PREVIEW
  Hi-Dad responder: $RESPOND_TO_HI_DAD
  Test Guild ID:    $GUILD_DISPLAY
  Install path:     $INSTALL_DIR
  Config file:      $CONFIG_DIR/env

Proceed with installation?" 16 $W || { clear; exit 0; }

# ── Install ──────────────────────────────────────────────────────────────────────
: > "$LOG"

# Open a named pipe. whiptail --gauge reads integers from it to advance the
# progress bar. We write to it via fd 3 throughout the install steps below.
FIFO=$(mktemp -u /tmp/dadjoke-fifo-XXXXXX)
mkfifo "$FIFO"

whiptail --title "$TT" --gauge "Starting installation..." 7 $W 0 < "$FIFO" &
GAUGE_PID=$!
exec 3>"$FIFO"

# Helpers used during the install block.
progress() { printf '%s\n' "$1" >&3; }
log_step()  { printf '[%s] %s\n' "$(date '+%T')" "$*" >> "$LOG"; }

FAIL=""

# Disable automatic exit-on-error for this block so we can handle failures
# gracefully and always reach the cleanup at the bottom.
set +euo pipefail

# ─ 1: System packages ─────────────────────────────────────────────────────────────
progress 3
if [[ -z "$FAIL" ]]; then
  log_step "apt-get update"
  apt-get update -y -q >> "$LOG" 2>&1 || FAIL="apt-get update failed"
fi

if [[ -z "$FAIL" ]]; then
  log_step "Installing curl git ca-certificates"
  apt-get install -y -q curl git ca-certificates >> "$LOG" 2>&1 \
    || FAIL="Failed to install system packages"
fi

# ─ 2: .NET 8 SDK ─────────────────────────────────────────────────────────────────
progress 12
if [[ -z "$FAIL" ]]; then
  if command -v dotnet &>/dev/null && dotnet --list-sdks 2>/dev/null | grep -q '^8\.'; then
    log_step ".NET 8 already installed — skipping"
  else
    log_step "Adding Microsoft package feed"
    # shellcheck source=/dev/null
    source /etc/os-release
    MS_PKG="/tmp/ms-prod.deb"
    curl -fsSL \
      "https://packages.microsoft.com/config/${ID:-debian}/${VERSION_ID:-12}/packages-microsoft-prod.deb" \
      -o "$MS_PKG" >> "$LOG" 2>&1 || FAIL="Failed to download Microsoft package feed"

    if [[ -z "$FAIL" ]]; then
      dpkg -i "$MS_PKG" >> "$LOG" 2>&1 || true   # might already be registered
      rm -f "$MS_PKG"
      apt-get update -y -q >> "$LOG" 2>&1
      log_step "Installing dotnet-sdk-8.0 (this may take a minute)"
      apt-get install -y -q dotnet-sdk-8.0 >> "$LOG" 2>&1 \
        || FAIL="dotnet-sdk-8.0 installation failed"
    fi
  fi
fi

# ─ 3: Service user ───────────────────────────────────────────────────────────────
progress 38
if [[ -z "$FAIL" ]]; then
  if ! id "$SERVICE_USER" &>/dev/null; then
    log_step "Creating system user $SERVICE_USER"
    useradd \
      --system \
      --create-home --home-dir "/var/lib/$SERVICE_USER" \
      --shell /usr/sbin/nologin \
      "$SERVICE_USER" >> "$LOG" 2>&1 \
      || FAIL="useradd failed"
  else
    log_step "User $SERVICE_USER already exists — skipping"
  fi
fi

# ─ 4: Clone / update repository ────────────────────────────────────────────────
progress 48
if [[ -z "$FAIL" ]]; then
  if [[ -d "$INSTALL_DIR/repo/.git" ]]; then
    log_step "Pulling latest $BRANCH"
    git -C "$INSTALL_DIR/repo" fetch origin "$BRANCH" >> "$LOG" 2>&1 \
      && git -C "$INSTALL_DIR/repo" reset --hard "origin/$BRANCH" >> "$LOG" 2>&1 \
      || FAIL="git pull failed"
  else
    log_step "Cloning repository"
    mkdir -p "$INSTALL_DIR"
    git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$INSTALL_DIR/repo" >> "$LOG" 2>&1 \
      || FAIL="git clone failed"
  fi
fi

# ─ 5: Build ───────────────────────────────────────────────────────────────────────
progress 62
if [[ -z "$FAIL" ]]; then
  log_step "Building (dotnet publish -c Release)"
  dotnet publish "$INSTALL_DIR/repo/src/DadJokeBot" \
    -c Release -o "$INSTALL_DIR/publish" \
    --nologo -v quiet >> "$LOG" 2>&1 \
    || FAIL="Build failed"
fi

# ─ 6: Config file (never overwrite an existing one) ────────────────────────
progress 78
if [[ -z "$FAIL" ]]; then
  mkdir -p "$CONFIG_DIR"
  if [[ ! -f "$CONFIG_DIR/env" ]]; then
    log_step "Writing $CONFIG_DIR/env"
    {
      echo "DADJOKE__BOT__TOKEN=${BOT_TOKEN}"
      echo "DADJOKE__BOT__JOKESFILEPATH=data/dad_jokes.csv"
      echo "DADJOKE__BOT__RESPONDTOHIDAD=${RESPOND_TO_HI_DAD}"
      [[ -n "$TEST_GUILD_ID" ]] && echo "DADJOKE__BOT__TESTGUILDID=${TEST_GUILD_ID}"
    } > "$CONFIG_DIR/env"
    chmod 600 "$CONFIG_DIR/env"
  else
    log_step "$CONFIG_DIR/env already exists — preserving existing config"
  fi
fi

# ─ 7: Updater script + systemd units ─────────────────────────────────────────────
progress 84
if [[ -z "$FAIL" ]]; then
  log_step "Installing updater script"
  install -o root -g root -m 755 \
    "$INSTALL_DIR/repo/scripts/dadjoke-updater.sh" \
    "$INSTALL_DIR/dadjoke-updater.sh" >> "$LOG" 2>&1 \
    || FAIL="Updater script install failed"
fi

if [[ -z "$FAIL" ]]; then
  log_step "Writing systemd unit files"

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

  cat > "/etc/systemd/system/${UPDATER_SERVICE}.service" <<EOF
[Unit]
Description=Discord Dad Joke Bot auto-updater
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
fi

# ─ 8: Ownership and service start ──────────────────────────────────────────────
progress 92
if [[ -z "$FAIL" ]]; then
  log_step "Setting ownership"
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR" "$CONFIG_DIR"

  log_step "Enabling and starting services"
  systemctl daemon-reload >> "$LOG" 2>&1
  systemctl enable --now "$BOT_SERVICE"      >> "$LOG" 2>&1 || FAIL="Failed to start $BOT_SERVICE"
  systemctl enable --now "$UPDATER_SERVICE"  >> "$LOG" 2>&1 || FAIL="Failed to start $UPDATER_SERVICE"
fi

progress 100
exec 3>&-
wait "$GAUGE_PID" 2>/dev/null || true
FIFO=""       # prevent double-close in cleanup trap
GAUGE_PID=""

set -euo pipefail

# ── Result ───────────────────────────────────────────────────────────────────────
if [[ -n "$FAIL" ]]; then
  whiptail --title "$TT" --msgbox \
"Installation failed: $FAIL

Full log: $LOG

You can safely re-run this wizard — already-completed
steps (user creation, config file, etc.) will be skipped." 13 $W
  exit 1
fi

whiptail --title "$TT" --msgbox \
"Installation complete! The bot is running.

Useful commands:

  Bot logs:    journalctl -u $BOT_SERVICE -f
  Update log:  journalctl -u $UPDATER_SERVICE -f
  Config:      $CONFIG_DIR/env
  Restart bot: systemctl restart $BOT_SERVICE

The updater checks GitHub every 30 seconds and
automatically rebuilds and restarts on new commits." 18 $W

clear
echo "Bot is running. Stream logs with: journalctl -u ${BOT_SERVICE} -f"
