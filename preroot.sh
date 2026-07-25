#!/bin/bash
# preroot.sh
#
# Laeuft als User "root", VOR dem Loeschen der alten Plugin-Ordner.
#
# Schritt 1: Homebridge stoppen, Port 8082 freigeben.
# Schritt 2: Alte Installation/Runtime uebernehmen (nach Prioritaet):
#            Zielpfad-Runtime schon da -> nur Reste putzen; sonst 0.3-Runtime
#            (data/system) komplett uebernehmen; sonst systemweite 0.1/0.2-Module
#            migrieren (homebridge/config-ui-x ausgenommen). Danach Quellen weg.
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
echo "Schritt 2: Alte Homebridge-Installation/Runtime uebernehmen"
echo "============================================================"

# Pfade:
#   NEW_RUNTIME_DIR  = isolierte Runtime am Zielpfad (ab 0.4)
#   HB03_RUNTIME_DIR = isolierte Runtime von 0.3 (externer data/system-Pfad)
#   /usr/lib bzw. /usr/local/lib/node_modules/homebridge* = systemweite 0.1/0.2-Reste
NEW_RUNTIME_DIR="$LBPDATA/$PDIR/homebridge_runtime"
NEW_NPM_GLOBAL_MODULES="$NEW_RUNTIME_DIR/npm-global/lib/node_modules"
HB03_RUNTIME_DIR="$LBHOMEDIR/data/system/homebridge_runtime"

# Systemweite 0.1/0.2-Reste (homebridge*-Module + bin-Symlinks) entfernen.
remove_systemwide_leftovers() {
    local d b OLD_MODULES_DIR
    for OLD_MODULES_DIR in /usr/local/lib/node_modules /usr/lib/node_modules; do
        shopt -s nullglob
        local dirs=("$OLD_MODULES_DIR"/homebridge*)
        shopt -u nullglob
        for d in "${dirs[@]}"; do
            echo "<INFO> Entferne alten Rest $d ..."
            rm -rf "$d"
        done
    done
    for b in /usr/local/bin/homebridge /usr/local/bin/hb-service /usr/bin/homebridge /usr/bin/hb-service; do
        [ -e "$b" ] && { echo "<INFO> Entferne Symlink $b ..."; rm -f "$b"; }
    done
}

if [ -d "$NEW_NPM_GLOBAL_MODULES" ] && [ -n "$(ls -A "$NEW_NPM_GLOBAL_MODULES" 2>/dev/null)" ]; then
    # Fall 1: Es liegt schon eine Runtime mit Modulen am Zielpfad - nur alte
    # Leichen (0.3-Runtime + systemweite Reste) aufraeumen.
    echo "<INFO> Runtime am Zielpfad vorhanden - entferne nur alte Reste."
    if [ -d "$HB03_RUNTIME_DIR" ]; then
        echo "<INFO> Entferne Runtime aus vorheriger Version ($HB03_RUNTIME_DIR) ..."
        rm -rf "$HB03_RUNTIME_DIR"
    fi
    remove_systemwide_leftovers

elif [ -d "$HB03_RUNTIME_DIR" ] && [ -n "$(ls -A "$HB03_RUNTIME_DIR" 2>/dev/null)" ]; then
    # Fall 2: Keine Runtime am Zielpfad, aber eine 0.3-Runtime unter data/system.
    # Die enthaelt ein isoliertes Node - komplett uebernehmen (Node wird in
    # postroot wiederverwendet, wenn die Version passt), danach Quelle + Reste weg.
    echo "<INFO> Uebernehme komplette Runtime aus vorheriger Version (inkl. Node) von $HB03_RUNTIME_DIR (kann je nach Groesse dauern) ..."
    if mkdir -p "$NEW_RUNTIME_DIR" && {
            # Hintergrund + vom Installer-Logfile abgekoppelt (>/dev/null 2>&1
            # </dev/null), sonst friert die Live-Anzeige auf LB3 ein (haelt
            # sonst die Log-Datei offen, siehe Node-Download in postroot.sh).
            cp -a "$HB03_RUNTIME_DIR"/. "$NEW_RUNTIME_DIR"/ >/dev/null 2>&1 </dev/null &
            CP_PID=$!
            SECONDS=0
            while kill -0 "$CP_PID" 2>/dev/null; do
                sleep 15
                MINS=$((SECONDS / 60)); SECS=$((SECONDS % 60))
                CUR_SIZE=$(du -sh "$NEW_RUNTIME_DIR" 2>/dev/null | cut -f1)
                echo "... Uebernahme laeuft (${MINS}m ${SECS}s) - bisher kopiert: ${CUR_SIZE:-0}"
            done
            wait "$CP_PID"
        }; then
        rm -rf "$HB03_RUNTIME_DIR"
        echo "<OK> Runtime aus vorheriger Version uebernommen."
    else
        echo "<WARNING> Uebernahme fehlgeschlagen - $HB03_RUNTIME_DIR bleibt vorerst erhalten."
    fi
    remove_systemwide_leftovers

else
    # Fall 3: Nur systemweite 0.1/0.2-Module - die Zusatz-Plugins migrieren
    # (homebridge + config-ui-x ueberspringen, werden in postroot frisch
    # installiert), danach die Quellen + Reste entfernen.
    FOUND_OLD=0
    for OLD_MODULES_DIR in /usr/local/lib/node_modules /usr/lib/node_modules; do
        shopt -s nullglob
        OLD_HOMEBRIDGE_DIRS=("$OLD_MODULES_DIR"/homebridge*)
        shopt -u nullglob
        [ "${#OLD_HOMEBRIDGE_DIRS[@]}" -eq 0 ] && continue
        FOUND_OLD=1
        mkdir -p "$NEW_NPM_GLOBAL_MODULES"
        for d in "${OLD_HOMEBRIDGE_DIRS[@]}"; do
            bn=$(basename "$d")
            case "$bn" in
                homebridge|homebridge-config-ui-x)
                    echo "<INFO> $bn wird neu installiert - Migration uebersprungen."
                    continue
                    ;;
            esac
            echo "<INFO> Migriere $bn von $OLD_MODULES_DIR (kann je nach Groesse dauern) ..."
            if cp -a "$d" "$NEW_NPM_GLOBAL_MODULES"/; then
                echo "<OK> $bn migriert."
            else
                echo "<WARNING> Migration von $d fehlgeschlagen."
            fi
        done
    done
    [ "$FOUND_OLD" -eq 0 ] && echo "<INFO> Keine alte Runtime/Module gefunden - Erstinstallation."
    remove_systemwide_leftovers
fi

# Alle drei Faelle koennen root-eigene Dateien in die Runtime bringen (cp -a
# erhaelt den Besitzer der Quelle) - preupgrade.sh (User loxberry) muss sie
# aber per "mv" sichern koennen, das braucht Schreibrecht auf jedes
# verschobene Verzeichnis selbst (rename() aktualisiert "..").
[ -d "$NEW_RUNTIME_DIR" ] && chown -R loxberry:loxberry "$NEW_RUNTIME_DIR"

exit 0
