#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
DATA_DIR="$HOME/.local/share/fr-kol-wiki-automation"
SYSTEMD_DIR="$HOME/.config/systemd/user"

for command in codex git gh jq uv flock systemctl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

install -d "$BIN_DIR" "$DATA_DIR" "$SYSTEMD_DIR"
install -m 0755 \
  "$SCRIPT_DIR/fr-kol-wiki-daily-update.sh" \
  "$BIN_DIR/fr-kol-wiki-daily-update.sh"
install -m 0644 \
  "$SCRIPT_DIR/daily-prompt.md" \
  "$SCRIPT_DIR/review-prompt.md" \
  "$SCRIPT_DIR/selection-prompt.md" \
  "$DATA_DIR/"
install -m 0644 \
  "$SCRIPT_DIR/systemd/fr-kol-wiki-daily.service" \
  "$SCRIPT_DIR/systemd/fr-kol-wiki-daily.timer" \
  "$SYSTEMD_DIR/"

systemctl --user daemon-reload
systemctl --user enable --now fr-kol-wiki-daily.timer

echo "Installed and enabled fr-kol-wiki-daily.timer."
echo "Check it with: systemctl --user status fr-kol-wiki-daily.timer"
