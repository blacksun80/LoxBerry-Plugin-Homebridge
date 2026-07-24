#!/bin/bash
# postroot.sh
#
# Laeuft als User "root", ganz am Ende der Installation/des Updates.
#
# Schritt 1: System-Node/npm pruefen (betrifft nicht Homebridge selbst).
# Schritt 2: hb-service einrichten/neu starten.
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

echo "============================================================"
echo "Schritt 1: System-Node/npm pruefen"
echo "============================================================"

check_system_node() {
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        SYS_NODE_VERSION=$(node -v 2>/dev/null) || return 1
        SYS_NPM_VERSION=$(npm -v 2>/dev/null) || return 1
        [ -n "$SYS_NODE_VERSION" ] && [ -n "$SYS_NPM_VERSION" ]
        return $?
    fi
    return 1
}

NODESOURCE_REPO_FOUND=""
if grep -rl "deb.nodesource.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | grep -q .; then
    NODESOURCE_REPO_FOUND=1
fi

if check_system_node; then
    echo "System-Node ($SYS_NODE_VERSION) / System-npm ($SYS_NPM_VERSION) vorhanden."
elif [ -n "$NODESOURCE_REPO_FOUND" ]; then
    echo "<INFO> System-Node/npm fehlt, NodeSource-Repo gefunden - automatische Reparatur wird uebersprungen."
else
    echo "System-Node/npm fehlt - versuche Reparatur via apt-get ..."
    apt-get update || echo "<INFO> apt-get update fehlgeschlagen."
    apt-get install -y --reinstall nodejs npm || apt-get install -y nodejs npm || true
    if check_system_node; then
        echo "<OK> System-Node/npm repariert."
    else
        echo "<INFO> System-Node/npm konnte nicht repariert werden."
    fi
fi

echo ""
echo "============================================================"
echo "Schritt 2: hb-service einrichten (Storage: $HB_STORAGE_DIR)"
echo "============================================================"

export PATH="$HB_NODE_DIR/bin:$HB_NPM_GLOBAL/bin:$PATH"
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
echo "System-Node:       ${SYS_NODE_VERSION:-n/a}"
echo "Homebridge-Node:   $("$HB_NODE_DIR/bin/node" -v)"
echo "Homebridge-Storage: $HB_STORAGE_DIR"
echo "Fertig."

exit 0
