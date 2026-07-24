#!/bin/bash
# preroot.sh
#
# Laeuft als User "root", VOR dem Loeschen der alten Plugin-Ordner.
#
# Schritt 1: Homebridge stoppen, Port 8082 freigeben.
# Schritt 2: Alte systemweite npm-Installation entfernen (falls vorhanden).
# Schritt 3: Alte, externe Runtime aus fruehreren Versionen entfernen (falls vorhanden).
#
# Argumente: command <TEMPFOLDER> <NAME> <FOLDER> <VERSION> <BASEFOLDER> <TEMPPATH>

COMMAND=$0
PTEMPDIR=$1
PSHNAME=$2
PDIR=$3
PVERSION=$4
LBHOMEDIR=$5
PTEMPPATH=$6

echo "============================================================"
echo "Schritt 1: Homebridge stoppen (Port 8082 freigeben)"
echo "============================================================"

if systemctl list-unit-files 2>/dev/null | grep -q '^homebridge\.service'; then
    echo "Stoppe homebridge-Dienst ..."
    systemctl stop homebridge.service 2>/dev/null || true
    sleep 2
else
    echo "Kein homebridge-Dienst registriert."
fi

pids_on_8082() {
    local pids=""
    if command -v fuser >/dev/null 2>&1; then
        pids=$(fuser 8082/tcp 2>/dev/null | tr -s ' ')
    fi
    if [ -z "${pids// /}" ] && command -v ss >/dev/null 2>&1; then
        pids=$(ss -ltnpH 'sport = :8082' 2>/dev/null | grep -oP 'pid=\K[0-9]+' | sort -u | tr '\n' ' ')
    fi
    if [ -z "${pids// /}" ] && command -v lsof >/dev/null 2>&1; then
        pids=$(lsof -t -i :8082 -sTCP:LISTEN 2>/dev/null | tr '\n' ' ')
    fi
    echo "$pids"
}

PORT_PIDS=$(pids_on_8082)
if [ -n "${PORT_PIDS// /}" ]; then
    echo "Port 8082 noch belegt (PID(s):$PORT_PIDS) - beende Prozess(e)."
    for pid in $PORT_PIDS; do kill "$pid" 2>/dev/null || true; done
    sleep 3
    PORT_PIDS=$(pids_on_8082)
    if [ -n "${PORT_PIDS// /}" ]; then
        echo "Erzwinge Beendigung (SIGKILL)."
        for pid in $PORT_PIDS; do kill -9 "$pid" 2>/dev/null || true; done
        sleep 2
    fi
else
    echo "Port 8082 ist frei."
fi

echo ""
echo "============================================================"
echo "Schritt 2: Alte, systemweite Homebridge-Installation entfernen"
echo "============================================================"

shopt -s nullglob
OLD_HOMEBRIDGE_DIRS=(/usr/local/lib/node_modules/homebridge*)
shopt -u nullglob

if [ "${#OLD_HOMEBRIDGE_DIRS[@]}" -eq 0 ]; then
    echo "<INFO> Keine alten systemweiten homebridge*-Ordner gefunden."
else
    for d in "${OLD_HOMEBRIDGE_DIRS[@]}"; do
        echo "<INFO> Entferne $d ..."
        rm -rf "$d"
    done
fi
for b in /usr/local/bin/homebridge /usr/local/bin/hb-service; do
    if [ -e "$b" ]; then
        echo "<INFO> Entferne Symlink $b ..."
        rm -f "$b"
    fi
done

echo ""
echo "============================================================"
echo "Schritt 3: Alte, externe Runtime entfernen (fruehere Skript-Version)"
echo "============================================================"

OLD_RUNTIME_DIR="$LBHOMEDIR/data/system/homebridge_runtime"

if [ -d "$OLD_RUNTIME_DIR" ]; then
    echo "<INFO> $OLD_RUNTIME_DIR gefunden - wird entfernt."
    rm -rf "$OLD_RUNTIME_DIR"
    echo "<OK> Alte Runtime entfernt."
else
    echo "<INFO> Kein alter Runtime-Ordner gefunden."
fi

exit 0
