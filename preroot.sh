#!/bin/bash
# preroot.sh
#
# Laeuft als User "root", VOR dem Loeschen der alten Plugin-Ordner - sowohl bei
# der Erstinstallation als auch bei jedem Update (der LoxBerry-Installer ruft
# PREROOT immer als erstes root-Skript auf, noch bevor Dateien angefasst werden).
#
# Hier passiert alles, was gemacht werden muss, SOLANGE die alte Installation
# noch vorhanden ist:
#   Schritt 1: Laufende Homebridge sauber stoppen und Port 8082 freigeben.
#   Schritt 2: Bestehende Homebridge-Config sichern - der LoxBerry-Installer
#              loescht den Config-Ordner des Plugins gleich danach. postroot.sh
#              spielt das Backup nach der Neuinstallation wieder zurueck.
#   Schritt 3: Ueberbleibsel der alten, systemweiten npm-Installation (aus der
#              allerersten Plugin-Version) entfernen, falls noch vorhanden.
#
# Es wird bei jedem Lauf ein neues, zeitgestempeltes Backup angelegt und davon
# immer nur die letzten 5 behalten.
#
# Argumente: command <TEMPFOLDER> <NAME> <FOLDER> <VERSION> <BASEFOLDER> <TEMPPATH>

COMMAND=$0
PTEMPDIR=$1
PSHNAME=$2
PDIR=$3
PVERSION=$4
LBHOMEDIR=$5
PTEMPPATH=$6

PCONFIG=$LBPCONFIG/$PDIR
HB_STORAGE_DIR="$PCONFIG"

BACKUP_ROOT="$LBHOMEDIR/data/system/tmp/homebridge_config_backup"
KEEP_BACKUPS=5
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/backup_${TIMESTAMP}"

echo "============================================================"
echo "Schritt 1: Laufende Homebridge stoppen (Port 8082 freigeben)"
echo "============================================================"

# Sauber ueber systemd stoppen, solange die Binaries noch da sind - so entsteht
# kein verwaister Prozess, wenn der Installer gleich das PDATA-Verzeichnis loescht.
if systemctl list-unit-files 2>/dev/null | grep -q '^homebridge\.service'; then
    echo "Stoppe homebridge-Dienst ..."
    systemctl stop homebridge.service 2>/dev/null || true
    sleep 2
else
    echo "Kein homebridge-Dienst registriert - nichts zu stoppen."
fi

# Sicherheitsnetz: falls trotzdem noch etwas auf Port 8082 lauscht - z.B. eine
# Homebridge ohne registrierten systemd-Dienst (Ueberbleibsel eines frueheren
# Installationsversuchs) - den Port hart freigeben. Nutzt fuser ODER ss ODER lsof.
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
    echo "Port 8082 noch belegt (PID(s):$PORT_PIDS) - beende blockierende(n) Prozess(e)."
    for pid in $PORT_PIDS; do kill "$pid" 2>/dev/null || true; done
    sleep 3
    PORT_PIDS=$(pids_on_8082)
    if [ -n "${PORT_PIDS// /}" ]; then
        echo "Prozess(e) noch aktiv - erzwinge Beendigung (SIGKILL)."
        for pid in $PORT_PIDS; do kill -9 "$pid" 2>/dev/null || true; done
        sleep 2
    fi
else
    echo "Port 8082 ist frei."
fi

echo ""
echo "============================================================"
echo "Schritt 2: Bestehende Homebridge-Config sichern"
echo "============================================================"
echo "<INFO> Quelle: $HB_STORAGE_DIR"
echo "<INFO> Ziel:   $BACKUP_DIR"

if [ -d "$HB_STORAGE_DIR" ] && [ -n "$(ls -A "$HB_STORAGE_DIR" 2>/dev/null)" ]; then
    mkdir -p "$BACKUP_DIR"
    if cp -a "$HB_STORAGE_DIR"/. "$BACKUP_DIR"/; then
        echo "<OK> Homebridge-Konfiguration nach $BACKUP_DIR gesichert."
    else
        echo "<WARNING> Sicherung der Homebridge-Konfiguration ist fehlgeschlagen. Das Update laeuft trotzdem weiter - die bestehende Konfiguration koennte dabei verloren gehen."
        rm -rf "$BACKUP_DIR"
    fi
else
    echo "<INFO> Kein bestehendes/nicht-leeres Konfigurationsverzeichnis gefunden ($HB_STORAGE_DIR) - nichts zu sichern."
fi

# Rotation: nur die letzten $KEEP_BACKUPS Backups behalten.
if [ -d "$BACKUP_ROOT" ]; then
    mapfile -t OLD_BACKUPS < <(ls -1dt "$BACKUP_ROOT"/backup_* 2>/dev/null | tail -n "+$((KEEP_BACKUPS + 1))")
    if [ "${#OLD_BACKUPS[@]}" -gt 0 ]; then
        echo "<INFO> Entferne ${#OLD_BACKUPS[@]} alte Backup(s), behalte die letzten $KEEP_BACKUPS."
        for old in "${OLD_BACKUPS[@]}"; do
            rm -rf "$old"
        done
    fi
fi

echo ""
echo "============================================================"
echo "Schritt 3: Alte, systemweite Homebridge-Installation entfernen"
echo "============================================================"

# Die allererste Plugin-Version hat Homebridge + Config UI X per
# "npm install -g" komplett systemweit installiert (ueber ein per "n"
# eingerichtetes System-Node). Diese Installation liegt ausserhalb aller
# von diesem Plugin verwalteten Pfade und wird von keinem anderen Skript
# angefasst - sie bleibt sonst als tote Leiche liegen und die
# Homebridge-UI meldet "Multiple instances of Homebridge were found".
# Glob statt fester Namen: erwischt so auch alte, systemweit mitinstallierte
# Homebridge-Plugins (z.B. "homebridge-irgendwas"), nicht nur die beiden
# Kernpakete selbst.
shopt -s nullglob
OLD_HOMEBRIDGE_DIRS=(/usr/local/lib/node_modules/homebridge*)
shopt -u nullglob

if [ "${#OLD_HOMEBRIDGE_DIRS[@]}" -eq 0 ]; then
    echo "<INFO> Keine alten systemweiten homebridge*-Ordner unter /usr/local/lib/node_modules gefunden - nichts zu tun."
else
    for d in "${OLD_HOMEBRIDGE_DIRS[@]}"; do
        echo "<INFO> Entferne alte systemweite Installation $d ..."
        rm -rf "$d"
    done
fi
for b in /usr/local/bin/homebridge /usr/local/bin/hb-service; do
    if [ -e "$b" ]; then
        echo "<INFO> Entferne alten Symlink $b ..."
        rm -f "$b"
    else
        echo "<INFO> $b nicht vorhanden - nichts zu tun."
    fi
done

exit 0