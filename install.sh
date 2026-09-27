#!/bin/sh
# Install teams-client and the Teams Clients tray plasmoid for the current user.
set -e
cd "$(dirname "$0")"
ID=io.github.jamesstuder.teamsclients

missing=""
command -v teams-for-linux >/dev/null || missing="$missing teams-for-linux"
python3 -c 'import gi; gi.require_version("Gio", "2.0")' 2>/dev/null || missing="$missing python-gobject"
command -v kdialog >/dev/null || missing="$missing kdialog"
command -v plasmashell >/dev/null || missing="$missing plasma-workspace"
if [ -n "$missing" ]; then
    echo "Missing:$missing" >&2
    exit 1
fi
command -v magick >/dev/null || echo "Note: ImageMagick not found; clients will use the plain Teams icon."

install -Dm755 teams-client "$HOME/.local/bin/teams-client"
rm -rf "$HOME/.local/share/plasma/plasmoids/$ID"
mkdir -p "$HOME/.local/share/plasma/plasmoids"
cp -r "plasmoid/$ID" "$HOME/.local/share/plasma/plasmoids/"

"$HOME/.local/bin/teams-client" setup "$@"

echo "Restarting plasmashell so the tray icon appears..."
kquitapp6 plasmashell >/dev/null 2>&1 || true
sleep 2
setsid plasmashell --replace >/dev/null 2>&1 < /dev/null &
echo "Done. Click the Teams icon in the system tray and choose \"Add client…\"."
