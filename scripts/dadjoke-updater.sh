#!/usr/bin/env bash
# dadjoke-updater.sh — Polls the main branch every 30 seconds.
# Managed by the dadjoke-updater systemd service; do not run directly.
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/dadjoke-bot}"
BOT_SERVICE="${BOT_SERVICE:-dadjoke-bot}"
BRANCH="main"
POLL_INTERVAL=30

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }

log "Updater started. Polling ${BRANCH} every ${POLL_INTERVAL}s."

while true; do
  sleep "$POLL_INTERVAL"

  # Fetch silently; if the network is down, log and continue the loop
  if ! git -C "$INSTALL_DIR/repo" fetch origin "$BRANCH" --quiet 2>&1; then
    log "WARN: git fetch failed — skipping this cycle."
    continue
  fi

  LOCAL=$(git -C "$INSTALL_DIR/repo" rev-parse HEAD)
  REMOTE=$(git -C "$INSTALL_DIR/repo" rev-parse "origin/$BRANCH")

  if [[ "$LOCAL" == "$REMOTE" ]]; then
    continue  # no update
  fi

  log "Update detected: $LOCAL -> $REMOTE"

  # Pull
  git -C "$INSTALL_DIR/repo" reset --hard "origin/$BRANCH"

  # Rebuild and publish
  log "Building..."
  if ! dotnet publish "$INSTALL_DIR/repo/src/DadJokeBot" \
        -c Release \
        -o "$INSTALL_DIR/publish" \
        --nologo -v quiet 2>&1; then
    log "ERROR: Build failed — keeping current version running."
    # Roll back so the next cycle doesn't re-attempt a broken commit
    git -C "$INSTALL_DIR/repo" reset --hard "$LOCAL"
    continue
  fi

  # Refresh the updater script itself in case it changed in the repo
  install -o root -g root -m 755 \
    "$INSTALL_DIR/repo/scripts/dadjoke-updater.sh" \
    "$INSTALL_DIR/dadjoke-updater.sh"

  # Restart the bot
  log "Restarting $BOT_SERVICE..."
  systemctl restart "$BOT_SERVICE"

  log "Update to $REMOTE applied successfully."
done
