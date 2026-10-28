#!/bin/sh
# Tailscale + SSH-Zugang einrichten (Linux, macOS best effort)
#   curl -fsSL https://st.tim-arnold.de/sh | sudo sh
# Optional anderer Geraetename:  ... | sudo ST_NAME=mein-name sh
set -eu
main() {

PUBKEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILdqMzo+cXjipnNPcWhjMIlbcYipa+zUAxLzHPuYlqag claude-st'
NAME="${ST_NAME:-$(uname -n | cut -d. -f1)}"
NAME=$(printf '%s' "$NAME" | tr 'A-Z_ .' 'a-z---')

say()  { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Bitte mit sudo ausfuehren:  curl -fsSL https://st.tim-arnold.de/sh | sudo sh"

TARGET_USER="${SUDO_USER:-root}"
TARGET_HOME=$(eval echo "~$TARGET_USER")
OS=$(uname -s)

# --- Tailscale ---------------------------------------------------------------
say "Tailscale"
if [ "$OS" = Darwin ]; then
    TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale
    command -v tailscale >/dev/null 2>&1 && TS=$(command -v tailscale)
    [ -x "$TS" ] || die "macOS: Tailscale-App installieren (https://tailscale.com/download/mac), starten, dann dieses Skript erneut ausfuehren."
else
    if ! command -v tailscale >/dev/null 2>&1; then
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    TS=$(command -v tailscale)
    [ -d /run/systemd/system ] && systemctl enable --now tailscaled >/dev/null 2>&1 || true
fi

if ! "$TS" ip -4 >/dev/null 2>&1; then
    warn "Gleich erscheint ein QR-Code / Link."
    warn "Mit dem Handy scannen (dort bei Tailscale eingeloggt) und Geraet bestaetigen."
    "$TS" up --qr --hostname="$NAME"
fi
TSIP=$("$TS" ip -4 | head -n1)

# --- SSH-Server --------------------------------------------------------------
say "SSH-Server"
if [ "$OS" = Darwin ]; then
    systemsetup -setremotelogin on >/dev/null 2>&1 \
        || warn "Remote Login bitte manuell aktivieren: Systemeinstellungen -> Allgemein -> Teilen -> Entfernte Anmeldung"
else
    if ! command -v sshd >/dev/null 2>&1 && [ ! -x /usr/sbin/sshd ]; then
        if   command -v apt-get >/dev/null 2>&1; then DEBIAN_FRONTEND=noninteractive apt-get install -y -q openssh-server
        elif command -v dnf     >/dev/null 2>&1; then dnf install -y -q openssh-server
        elif command -v yum     >/dev/null 2>&1; then yum install -y -q openssh-server
        elif command -v pacman  >/dev/null 2>&1; then pacman -S --noconfirm --needed openssh
        elif command -v zypper  >/dev/null 2>&1; then zypper -n -q install openssh-server
        elif command -v apk     >/dev/null 2>&1; then apk add -q openssh
        else die "Kein bekannter Paketmanager - openssh-server bitte manuell installieren."
        fi
    fi
    if [ -d /run/systemd/system ]; then
        # Debian/Ubuntu: "ssh", sonst "sshd" (auf Debian ist sshd nur ein Alias)
        if systemctl list-unit-files ssh.service >/dev/null 2>&1; then UNIT=ssh; else UNIT=sshd; fi
        systemctl enable --now "$UNIT" >/dev/null 2>&1 || warn "SSH-Dienst konnte nicht gestartet werden: systemctl status $UNIT"
    elif command -v rc-service >/dev/null 2>&1; then
        rc-update add sshd default >/dev/null 2>&1 || true
        rc-service sshd start >/dev/null 2>&1 || warn "SSH-Dienst konnte nicht gestartet werden."
    else
        warn "Kein systemd/OpenRC erkannt - SSH-Dienst bitte manuell starten."
    fi
    # Firewall: SSH ueber das Tailscale-Interface erlauben
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow in on tailscale0 to any port 22 proto tcp >/dev/null
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd -q --permanent --add-service=ssh && firewall-cmd -q --reload
    fi
fi

# --- Schluessel eintragen ----------------------------------------------------
say "SSH-Schluessel fuer $TARGET_USER"
mkdir -p "$TARGET_HOME/.ssh"
touch "$TARGET_HOME/.ssh/authorized_keys"
grep -qF "$PUBKEY" "$TARGET_HOME/.ssh/authorized_keys" || echo "$PUBKEY" >> "$TARGET_HOME/.ssh/authorized_keys"
chmod 700 "$TARGET_HOME/.ssh"; chmod 600 "$TARGET_HOME/.ssh/authorized_keys"
chown -R "$TARGET_USER" "$TARGET_HOME/.ssh" 2>/dev/null || true

cat <<SUMMARY

$(printf '\033[32m')--- st.tim-arnold.de ---
Rechner:      $NAME ($(uname -sr))
Benutzer:     $TARGET_USER
Tailscale-IP: $TSIP
SSH:          ssh $TARGET_USER@$TSIP$(printf '\033[0m')

Fertig - diese Zeilen an Claude schicken.
Abschalten:   curl -fsSL https://st.tim-arnold.de/off.sh | sudo sh
SUMMARY
}
main "$@" </dev/null
