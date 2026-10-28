#!/bin/sh
# Zugang wieder entfernen:  curl -fsSL https://st.tim-arnold.de/off.sh | sudo sh
set -u
main() {
TARGET_HOME=$(eval echo "~${SUDO_USER:-root}")
f="$TARGET_HOME/.ssh/authorized_keys"
[ -f "$f" ] && sed -i.bak '/claude-st$/d' "$f" && rm -f "$f.bak"
TS=$(command -v tailscale || echo /Applications/Tailscale.app/Contents/MacOS/Tailscale)
[ -x "$TS" ] && "$TS" logout
echo "Schluessel entfernt, Geraet aus Tailscale abgemeldet. (SSH-Server und Tailscale bleiben installiert.)"
}
main "$@" </dev/null
