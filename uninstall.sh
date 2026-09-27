#!/bin/sh
# Remove teams-client and the tray plasmoid. Client profiles (logins) in
# ~/.config/teams-client-* and the client list in ~/.config/teams-clients are kept.
ID=io.github.jamesstuder.teamsclients
A="$HOME/.local/share/applications"
for f in "$A"/teams-cycle.desktop "$A"/teams-slot-*.desktop "$A"/teams-for-linux.desktop \
         "$HOME/.config/autostart/teams-clients.desktop"; do
    rm -f "$f"
done
if [ -f "$HOME/.config/teams-clients/clients.json" ]; then
    python3 -c 'import json,sys; [print(c["slug"]) for c in json.load(open(sys.argv[1]))["clients"]]' \
        "$HOME/.config/teams-clients/clients.json" | while read -r s; do rm -f "$A/teams-$s.desktop"; done
fi
update-desktop-database "$A" 2>/dev/null
rm -rf "$HOME/.local/share/plasma/plasmoids/$ID" "$HOME/.local/share/icons/teams-clients"
rm -f "$HOME/.local/bin/teams-client"
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
for (const p of panels()) for (const w of p.widgets()) if (w.type == 'org.kde.plasma.systemtray') {
    w.currentConfigGroup = ['General'];
    for (const k of ['extraItems', 'knownItems', 'hiddenItems']) {
        const v = w.readConfig(k);
        const l = (Array.isArray(v) ? v : String(v || '').split(',')).filter(x => x && x != '$ID' && !/^teams-.*_status_icon_1\$/.test(x));
        w.writeConfig(k, l);
    }
    w.reloadConfig();
}" >/dev/null 2>&1
echo "Removed. Shortcuts can be cleared in System Settings > Shortcuts; restart plasmashell to drop the tray icon."
