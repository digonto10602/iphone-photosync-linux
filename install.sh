#!/usr/bin/env bash
# install.sh — install the iPhone → Linux PC transfer kit for the current user.
#
# Copies the scripts, systemd user services, app-launcher entry and Omarchy bar plugin into
# your home folder, creates ~/iphone_backup/{images,videos}, generates a WebDAV password
# (only if none exists yet) and starts the services. Nothing here needs root; the two steps
# that do (installing rclone, opening the firewall port) are printed at the end.
#
# Usage: ./install.sh            install and start
#        SKIP_SYSTEMD=1 ./install.sh   copy files only (no systemctl calls)
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)

install -Dm755 -t "$HOME/.local/bin" "$here"/bin/*
install -Dm644 -t "$HOME/.config/systemd/user" "$here"/systemd/*.service
install -Dm644 -t "$HOME/.local/share/applications" "$here"/applications/iphone-transfers.desktop
mkdir -p "$HOME/.config/omarchy/plugins"
cp -r "$here/omarchy-plugin/iphone-transfers" "$HOME/.config/omarchy/plugins/"
mkdir -p "$HOME/iphone_backup/images" "$HOME/iphone_backup/videos"

env_file="$HOME/.config/iphone-webdav/env"
if [[ ! -f $env_file ]]; then
  mkdir -p "$(dirname "$env_file")"
  chmod 700 "$(dirname "$env_file")"
  pass=$(tr -dc 'abcdefghjkmnpqrstuvwxyz23456789' < /dev/urandom | head -c 12 || true)
  (umask 077; printf 'RCLONE_USER=iphone\nRCLONE_PASS=%s\n' "$pass" > "$env_file")
  echo "Created WebDAV login in $env_file  (user: iphone  password: $pass)"
else
  echo "Keeping existing WebDAV login in $env_file"
fi

if [[ ${SKIP_SYSTEMD:-0} != 1 ]]; then
  systemctl --user daemon-reload
  systemctl --user enable --now iphone-backup-sorter.service
  if command -v rclone >/dev/null; then
    systemctl --user enable --now iphone-webdav.service iphone-transfers-autoopen.service
  else
    echo "rclone is not installed: WebDAV not started (see step 1 below)."
  fi
fi

cat <<'EOF'

Installed. Remaining steps:
  1. Install rclone (WebDAV server), then re-run ./install.sh:
       sudo pacman -S rclone            # Arch / Omarchy
  2. Let your home network reach the WebDAV port (adjust the subnet to yours):
       sudo ufw allow from 192.168.1.0/24 to any port 8080 proto tcp
  3. Omarchy only — put the widget on the bar:
       omarchy plugin enable digimonk.iphone-transfers --section right
       omarchy restart shell            # if the widget does not appear
  4. In PhotoSync (iPhone): Configure → WebDAV → server = this PC's IP, port 8080,
     SSL off, login/password from ~/.config/iphone-webdav/env, Directory /videos,
     Create Sub-Directories = Recording Date (Year + Month).
EOF
