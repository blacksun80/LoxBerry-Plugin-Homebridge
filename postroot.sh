#!/bin/bash
# postroot.sh
#
# Laeuft als User "root", ganz am Ende der Installation/des Updates.
#
# Schritt 1: System-Node/npm pruefen (betrifft nicht Homebridge selbst).
# Schritt 2: npm-Module neu bauen, falls postinstall.sh einen Node-Wechsel
#            markiert hat (braucht root, deshalb hier statt in postinstall.sh).
# Schritt 3: hb-service einrichten/neu starten.
#
# sudoers-Eintrag: siehe sudoers/sudoers (nativer LoxBerry-Mechanismus).
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
PDATA=$LBPDATA/$PDIR
HB_STORAGE_DIR="$PCONFIG"
HB_RUNTIME_DIR="$PDATA/homebridge_runtime"
HB_NODE_DIR="$HB_RUNTIME_DIR/nodejs"
HB_NPM_GLOBAL="$HB_RUNTIME_DIR/npm-global"

# Ziel des isolierten Node-Binaries, um es in der Anzeige markieren zu koennen.
ISO_NODE_REAL=$(readlink -f "$HB_NODE_DIR/bin/node" 2>/dev/null)

# Zeigt Version + ggf. Symlink-Ziel eines node-Binaries an; markiert, wenn es
# in Wahrheit auf die isolierte Runtime zeigt.
show_node() {
    local label="$1" p="$2" real ver extra=""
    if [ ! -e "$p" ]; then
        echo "$label: nicht vorhanden"
        return
    fi
    real=$(readlink -f "$p" 2>/dev/null)
    ver=$("$p" -v 2>/dev/null)
    if [ -z "$ver" ]; then
        echo "$label: <WARNING> vorhanden, aber nicht ausfuehrbar"
        return
    fi
    [ -L "$p" ] && extra=" -> $real"
    [ -n "$ISO_NODE_REAL" ] && [ "$real" = "$ISO_NODE_REAL" ] && extra="$extra (= isolierte Runtime!)"
    echo "$label: $ver$extra"
}

echo "============================================================"
echo "System-Info"
echo "============================================================"
HW_MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
if [ -z "$HW_MODEL" ]; then
    HW_MODEL=$(printf '%s %s' "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" "$(cat /sys/class/dmi/id/product_name 2>/dev/null)")
    HW_MODEL=$(echo "$HW_MODEL" | sed 's/^ *//; s/ *$//')
fi
[ -r /etc/os-release ] && . /etc/os-release
echo "Geraet:      ${HW_MODEL:-unbekannt}"
echo "OS:          ${PRETTY_NAME:-unbekannt}"
echo "Architektur: $(uname -m)"

echo ""
echo "============================================================"
echo "Schritt 1: Node/npm-Uebersicht (nur Anzeige)"
echo "============================================================"

# Explizit die bekannten System-Node-Pfade zeigen (nicht PATH-basiert, sonst
# wird ein /usr/local-Symlink auf die isolierte Runtime faelschlich als
# System-Node ausgegeben). LB2/LB3: /usr/bin (NodeSource); LB4: /usr/local/bin.
show_node "System-Node /usr/bin/node      " /usr/bin/node
show_node "System-Node /usr/local/bin/node" /usr/local/bin/node

echo ""
echo "============================================================"
echo "Schritt 2: npm-Module neu bauen (nur nach Node-Wechsel)"
echo "============================================================"

export PATH="$HB_NODE_DIR/bin:$HB_NPM_GLOBAL/bin:$PATH"
REBUILD_FLAG="$HB_RUNTIME_DIR/.rebuild-required"

if [ -f "$REBUILD_FLAG" ]; then
    NPM_INSTALL_LOG="$HB_RUNTIME_DIR/npm-install.log"

    # Ueber die Config-UI nachinstallierte Plugins liegen root-eigen (die UI
    # installiert per "sudo npm"); der Dienst laeuft aber als "loxberry".
    chown -R loxberry:loxberry "$HB_RUNTIME_DIR" 2>/dev/null || true

    # Rebuild im Hintergrund + Heartbeat, sonst steht die Anzeige im
    # LoxBerry-Log minutenlang still (Ausgabe geht komplett ins Logfile).
    run_with_heartbeat() {
        local label="$1"; shift
        "$@" >> "$NPM_INSTALL_LOG" 2>&1 &
        local pid=$! mins secs last
        SECONDS=0
        while kill -0 "$pid" 2>/dev/null; do
            sleep 15
            mins=$((SECONDS / 60)); secs=$((SECONDS % 60))
            last=$(tail -n 1 "$NPM_INSTALL_LOG" 2>/dev/null)
            echo "... $label laeuft (${mins}m ${secs}s) - zuletzt: ${last:-...}"
        done
        wait "$pid"
    }

    echo "Node-Wechsel erkannt - alle npm-Module gegen das neue Node neu bauen ..."
    if run_with_heartbeat "Rebuild" "$HB_NPM_GLOBAL/bin/hb-service" rebuild --all; then
        echo "Rebuild abgeschlossen (hb-service rebuild --all)."
    else
        echo "<WARNING> hb-service rebuild --all fehlgeschlagen - versuche 'npm rebuild' ..."
        # --unsafe-perm: npm laeuft hier als root und wuerde die Build-Skripte
        # sonst mit reduzierten Rechten ausfuehren (schlaegt mit EACCES fehl).
        if run_with_heartbeat "npm rebuild" "$HB_NODE_DIR/bin/npm" rebuild -g \
                --prefix "$HB_NPM_GLOBAL" --cache "$HB_RUNTIME_DIR/.npm-cache" --unsafe-perm; then
            echo "Rebuild abgeschlossen (npm rebuild)."
        else
            echo "<WARNING> npm rebuild ebenfalls mit Fehlern - Plugins ggf. in der Config-UI neu installieren."
        fi
    fi

    chown -R loxberry:loxberry "$HB_RUNTIME_DIR" 2>/dev/null || true
    rm -f "$REBUILD_FLAG"
else
    echo "Kein Node-Wechsel - Rebuild nicht noetig."
fi

echo ""
echo "============================================================"
echo "Schritt 3: hb-service einrichten (Storage: $HB_STORAGE_DIR)"
echo "============================================================"

HB_SERVICE="$HB_NPM_GLOBAL/bin/hb-service"

if [ ! -x "$HB_SERVICE" ]; then
    echo "FEHLER: hb-service nicht gefunden unter $HB_SERVICE"
    exit 1
fi

SERVICE_UNIT="/etc/systemd/system/homebridge.service"

if systemctl list-unit-files 2>/dev/null | grep -q "^homebridge\.service"; then
    echo "Vorhandenen homebridge-Dienst gefunden - wird neu registriert."
    "$HB_SERVICE" uninstall || true
    if [ -f "$SERVICE_UNIT" ]; then
        systemctl disable --now homebridge.service 2>/dev/null || true
        rm -f "$SERVICE_UNIT"
        systemctl daemon-reload 2>/dev/null || true
    fi
else
    echo "Kein bestehender homebridge-Dienst - Erstinstallation."
fi

echo "Registriere Dienst (Storage: $HB_STORAGE_DIR, Port 8082, User loxberry) ..."
"$HB_SERVICE" -U "$HB_STORAGE_DIR" --user loxberry --port 8082 install

if [ -f "$SERVICE_UNIT" ]; then
    NODE_UNIT_PATH="${HB_NODE_DIR}/bin:${HB_NPM_GLOBAL}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    NODE_UNIT_MODULE_PATH="${HB_NPM_GLOBAL}/lib/node_modules"
    sed -i '/^Environment=PATH=/d' "$SERVICE_UNIT"
    sed -i '/^Environment=NODE_PATH=/d' "$SERVICE_UNIT"
    sed -i "/^\[Service\]/a Environment=PATH=${NODE_UNIT_PATH}" "$SERVICE_UNIT"
    sed -i "/^\[Service\]/a Environment=NODE_PATH=${NODE_UNIT_MODULE_PATH}" "$SERVICE_UNIT"
    systemctl daemon-reload
    systemctl restart homebridge.service
    echo "Environment=PATH/NODE_PATH gesetzt, Dienst neu gestartet."
else
    echo "FEHLER: $SERVICE_UNIT nicht gefunden nach 'hb-service install'."
    exit 1
fi

echo ""
echo "============================================================"
echo "Zusammenfassung"
echo "============================================================"
echo "Geraet:            ${HW_MODEL:-unbekannt}"
echo "OS:                ${PRETTY_NAME:-unbekannt} / $(uname -m)"
show_node "System-Node /usr/bin/node      " /usr/bin/node
show_node "System-Node /usr/local/bin/node" /usr/local/bin/node
echo "Homebridge-Node (isoliert): $("$HB_NODE_DIR/bin/node" -v 2>/dev/null || echo n/a) / npm $("$HB_NODE_DIR/bin/npm" -v 2>/dev/null || echo n/a)"
echo "Homebridge-Storage: $HB_STORAGE_DIR"
echo "Fertig."

exit 0
