#!/bin/bash
# preroot.sh
#
# Laeuft als User "root", VOR dem Loeschen der alten Plugin-Ordner.
#
# Schritt 1: Homebridge stoppen, Port 8082 freigeben.
# Schritt 2: Alte systemweite npm-Installation (0.1/0.2) in die neue,
#            isolierte Runtime migrieren (falls vorhanden).
# Schritt 3: Alte, externe Runtime aus fruehreren Versionen (0.3) migrieren (falls vorhanden).
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
echo "Schritt 2: Alte, systemweite Homebridge-Installation migrieren"
echo "============================================================"

# Node 0.1/0.2 installierte per "npm install -g" in den System-Node-Praefix.
# Je nach Debian-Basisversion liegt der unter /usr/local (Bookworm/Trixie,
# DietPi-Node) oder /usr (Buster/Bullseye, NodeSource-Node) - siehe
# Claude_Gedaechtnis/LoxBerry/Node-Version-je-Debian.md. Das Node-Binary
# selbst bleibt unangetastet (die neue Runtime laedt sich ihr eigenes);
# migriert werden nur die node_modules, damit nachinstallierte Plugins
# (npm-Konvention: auch die heissen "homebridge-*") nicht verloren gehen.
NEW_RUNTIME_DIR="$LBPDATA/$PDIR/homebridge_runtime"
NEW_NPM_GLOBAL_MODULES="$NEW_RUNTIME_DIR/npm-global/lib/node_modules"
HB03_RUNTIME_DIR="$LBHOMEDIR/data/system/homebridge_runtime"

# Ist schon eine "echte" Runtime vorhanden (Zielpfad ODER der 0.3-Zwischenpfad,
# der erst in Schritt 3 umgezogen wird)? Dann sind /usr/lib|/usr/local/lib-
# Reste nur alte, nie aufgeraeumte 0.1/0.2-Leichen - NICHT mehr uebernehmen.
# Sonst wuerde Schritt 3 gleich danach die echte, aktuelle 0.3-Runtime am
# Zwischenpfad nur noch loeschen (weil der Zielpfad ja "schon existiert"),
# statt sie zu migrieren.
HAVE_REAL_RUNTIME=0
[ -d "$NEW_NPM_GLOBAL_MODULES" ] && [ -n "$(ls -A "$NEW_NPM_GLOBAL_MODULES" 2>/dev/null)" ] && HAVE_REAL_RUNTIME=1
[ -d "$HB03_RUNTIME_DIR" ] && [ -n "$(ls -A "$HB03_RUNTIME_DIR" 2>/dev/null)" ] && HAVE_REAL_RUNTIME=1

FOUND_OLD=0
for OLD_MODULES_DIR in /usr/local/lib/node_modules /usr/lib/node_modules; do
    shopt -s nullglob
    OLD_HOMEBRIDGE_DIRS=("$OLD_MODULES_DIR"/homebridge*)
    shopt -u nullglob
    [ "${#OLD_HOMEBRIDGE_DIRS[@]}" -eq 0 ] && continue
    FOUND_OLD=1

    if [ "$HAVE_REAL_RUNTIME" -eq 1 ]; then
        echo "<INFO> Es existiert bereits eine aktuelle Runtime (0.3+) - entferne nur die veralteten Reste in $OLD_MODULES_DIR/homebridge*."
    else
        mkdir -p "$NEW_NPM_GLOBAL_MODULES"
        for d in "${OLD_HOMEBRIDGE_DIRS[@]}"; do
            bn=$(basename "$d")
            # homebridge + config-ui-x werden in postroot ohnehin frisch
            # installiert - nur die Zusatz-Plugins muessen migriert werden.
            case "$bn" in
                homebridge|homebridge-config-ui-x)
                    echo "<INFO> $bn wird neu installiert - Migration uebersprungen."
                    continue
                    ;;
            esac
            echo "<INFO> Migriere $bn von $OLD_MODULES_DIR nach $NEW_NPM_GLOBAL_MODULES (kann je nach Groesse dauern) ..."
            if cp -a "$d" "$NEW_NPM_GLOBAL_MODULES"/; then
                echo "<OK> $bn migriert."
            else
                echo "<WARNING> Migration von $d fehlgeschlagen."
            fi
        done
        # cp -a erhaelt den root:root-Besitz der Quelle - preupgrade.sh
        # (User loxberry) muesste die Runtime spaeter aber per "mv"
        # verschieben koennen, dafuer braucht es Schreibrecht auf das
        # Verzeichnis selbst (rename() aktualisiert den ".."-Eintrag).
        chown -R loxberry:loxberry "$NEW_RUNTIME_DIR"
    fi

    for d in "${OLD_HOMEBRIDGE_DIRS[@]}"; do
        echo "<INFO> Entferne $d ..."
        rm -rf "$d"
    done
done
[ "$FOUND_OLD" -eq 0 ] && echo "<INFO> Keine alten systemweiten homebridge*-Ordner gefunden."

for b in /usr/local/bin/homebridge /usr/local/bin/hb-service /usr/bin/homebridge /usr/bin/hb-service; do
    if [ -e "$b" ]; then
        echo "<INFO> Entferne Symlink $b ..."
        rm -f "$b"
    fi
done

echo ""
echo "============================================================"
echo "Schritt 3: Alte, externe Runtime aus fruehreren Versionen migrieren"
echo "============================================================"

OLD_RUNTIME_DIR="$LBHOMEDIR/data/system/homebridge_runtime"
NEW_RUNTIME_DIR="$LBPDATA/$PDIR/homebridge_runtime"

if [ -d "$OLD_RUNTIME_DIR" ]; then
    if [ -d "$NEW_RUNTIME_DIR" ]; then
        echo "<INFO> $NEW_RUNTIME_DIR existiert bereits - entferne nur $OLD_RUNTIME_DIR."
        rm -rf "$OLD_RUNTIME_DIR"
    elif mkdir -p "$NEW_RUNTIME_DIR" && cp -a "$OLD_RUNTIME_DIR"/. "$NEW_RUNTIME_DIR"/; then
        rm -rf "$OLD_RUNTIME_DIR"
        echo "<OK> Runtime von $OLD_RUNTIME_DIR nach $NEW_RUNTIME_DIR migriert."
    else
        echo "<WARNING> Migration fehlgeschlagen - $OLD_RUNTIME_DIR bleibt vorerst erhalten."
    fi
else
    echo "<INFO> Kein alter Runtime-Ordner gefunden."
fi

exit 0
