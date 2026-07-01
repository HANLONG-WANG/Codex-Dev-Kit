#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$(id -u)" == "0" ]]; then
  printf '[codex-dev] ERROR: Do not install as root. Run ./install.sh as your normal Fedora user.\n' >&2
  exit 1
fi

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"
install -m 0755 "$SRC_DIR/codex-dev" "$BIN_DIR/codex-dev"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/codex-dev"
mkdir -p "$CONFIG_DIR" "$CONFIG_DIR/build" "$HOME/Projects"

cat <<MSG
Installed: $BIN_DIR/codex-dev
Config:    $CONFIG_DIR
Projects:  $HOME/Projects

Next steps:
  1. Ensure ~/.local/bin is in PATH:
       export PATH="\$HOME/.local/bin:\$PATH"

  2. Check the host/container safety baseline:
       codex-dev doctor

  3. Create a project:
       codex-dev init demo python
       codex-dev build demo
       codex-dev enter demo
MSG
