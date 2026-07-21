#!/bin/bash
# postroot.sh
#
# Laeuft als User "root", ganz am Ende der Installation/des Updates.
#
# Schritt 0: Homebridge-Config aus dem preupgrade.sh-Backup wiederherstellen.
# Schritt 1: System-Node/npm pruefen, Fremdinstallationen einmalig entfernen.
# Schritt 2: Benoetigte Node-Version fuer Homebridge ermitteln.
# Schritt 3: Isoliertes Node.js fuer Homebridge einrichten (in PDATA).
# Schritt 4: Homebridge + Config UI X installieren (isoliert).
# Schritt 5: hb-service einrichten/neu starten.
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
HB_NODE_DIR="$PDATA/nodejs"
HB_NPM_GLOBAL="$PDATA/npm-global"

set -e

mkdir -p "$HB_STORAGE_DIR"
mkdir -p "$PDATA" "$HB_NPM_GLOBAL"

echo "============================================================"
echo "Schritt 0: Homebridge-Config wiederherstellen (falls Backup da)"
echo "============================================================"

BACKUP_ROOT="$LBHOMEDIR/data/system/tmp/homebridge_config_backup"
LATEST_BACKUP=$(ls -1dt "$BACKUP_ROOT"/backup_* 2>/dev/null | head -1)

if [ -n "$LATEST_BACKUP" ] && [ -d "$LATEST_BACKUP" ]; then
    echo "<INFO> Backup gefunden unter $LATEST_BACKUP - wird nach $HB_STORAGE_DIR zurueckgespielt."
    cp -a "$LATEST_BACKUP"/. "$HB_STORAGE_DIR"/
    chown -R loxberry:loxberry "$HB_STORAGE_DIR"
    echo "<OK> Homebridge-Config wiederhergestellt und Owner auf loxberry:loxberry gesetzt."
else
    echo "<INFO> Kein Backup unter $BACKUP_ROOT gefunden."
    chown -R loxberry:loxberry "$HB_STORAGE_DIR" 2>/dev/null || true
fi

echo ""
echo "============================================================"
echo "Schritt 1: System-Node/npm pruefen, Fremdinstallationen entfernen"
echo "============================================================"

NODE_CLEANUP_MARKER="$LBHOMEDIR/data/system/homebridge_node_cleanup_done"

if [ -f "$NODE_CLEANUP_MARKER" ]; then
    echo "Fremd-Node-Bereinigung wurde bereits einmal durchgefuehrt (am $(cat "$NODE_CLEANUP_MARKER" 2>/dev/null))."
    echo "Wird uebersprungen. Zum erneuten Ausfuehren: Datei $NODE_CLEANUP_MARKER loeschen."
    echo "Aktuelles System-Node: $(node -v 2>/dev/null || echo 'kein System-Node gefunden')"
else

NODESOURCE_FILE="/etc/apt/sources.list.d/nodesource.list"
FOREIGN_NODE=0

if [ -f "$NODESOURCE_FILE" ]; then
    echo "NodeSource-Fremdquelle gefunden ($NODESOURCE_FILE)."
    FOREIGN_NODE=1
fi

for p in /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/n; do
    if [ -e "$p" ]; then
        echo "Fremdinstallation gefunden: $p"
        FOREIGN_NODE=1
    fi
done

if [ -d /usr/local/n ]; then
    echo "Verzeichnis /usr/local/n gefunden."
    FOREIGN_NODE=1
fi

CURRENT_NODE_PATH=$(command -v node 2>/dev/null || true)
if [ -n "$CURRENT_NODE_PATH" ] && [[ "$CURRENT_NODE_PATH" != /usr/bin/* ]]; then
    echo "Aktives 'node' im PATH liegt nicht unter /usr/bin ($CURRENT_NODE_PATH)."
    FOREIGN_NODE=1
fi

if [ "$FOREIGN_NODE" -eq 1 ]; then
    echo "-> Fremd-Node/npm erkannt. Wird entfernt und durch die apt-Version ersetzt."

    rm -f "$NODESOURCE_FILE"
    rm -f /etc/apt/keyrings/nodesource.gpg /usr/share/keyrings/nodesource.gpg 2>/dev/null || true

    apt-get remove -y --purge nodejs npm libnode-dev 'libnode*' 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true

    rm -rf /usr/local/n /usr/local/lib/node_modules
    rm -f /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/n
    hash -r

    apt-get update -qq || echo "WARNUNG: apt-get update hatte Fehler - fahre trotzdem fort."
    apt-get install -y nodejs
    command -v npm >/dev/null 2>&1 || apt-get install -y npm 2>/dev/null || true
    hash -r

    echo "System-Node jetzt: $(node -v 2>/dev/null || echo 'FEHLER: node nicht gefunden')"
else
    echo "Kein Fremd-Node/npm gefunden."
    echo "System-Node: $(node -v 2>/dev/null || echo 'kein System-Node installiert')"
fi

mkdir -p "$(dirname "$NODE_CLEANUP_MARKER")"
date '+%Y-%m-%d %H:%M:%S' > "$NODE_CLEANUP_MARKER"
echo "Vermerkt unter $NODE_CLEANUP_MARKER."

fi

echo ""
echo "============================================================"
echo "Schritt 2: Homebridge-Version & benoetigte Node-Version ermitteln"
echo "============================================================"

LATEST_HB_UI_VERSION=$(npm view homebridge-config-ui-x version 2>/dev/null || echo "")
INSTALLED_HB_UI_PKG="$HB_NPM_GLOBAL/lib/node_modules/homebridge-config-ui-x/package.json"
INSTALLED_HB_UI_VERSION=""
if [ -f "$INSTALLED_HB_UI_PKG" ]; then
    INSTALLED_HB_UI_VERSION=$(node -e "try{console.log(require('$INSTALLED_HB_UI_PKG').version)}catch(e){}" 2>/dev/null || echo "")
fi

if [ -n "$LATEST_HB_UI_VERSION" ]; then
    if [ -n "$INSTALLED_HB_UI_VERSION" ] && [ "$INSTALLED_HB_UI_VERSION" = "$LATEST_HB_UI_VERSION" ]; then
        echo "homebridge-config-ui-x ist bereits aktuell (v$INSTALLED_HB_UI_VERSION)."
    else
        echo "Update verfuegbar: installiert=${INSTALLED_HB_UI_VERSION:-keine}, aktuell auf npm=$LATEST_HB_UI_VERSION"
    fi
else
    echo "Konnte aktuelle homebridge-config-ui-x Version nicht von npm abfragen."
fi

REQUIRED_RANGE=$(npm view homebridge-config-ui-x engines.node 2>/dev/null || echo "")
if [ -z "$REQUIRED_RANGE" ]; then
    echo "Konnte engines.node nicht abfragen - Fallback auf Node 22."
    TARGET_MAJOR=22
else
    echo "engines.node von homebridge-config-ui-x: $REQUIRED_RANGE"
    TARGET_MAJOR=$(echo "$REQUIRED_RANGE" | grep -oP '\^\K[0-9]+' | sort -n | head -1)
    if [ -z "$TARGET_MAJOR" ]; then
        echo "Konnte keine Major-Version herauslesen - Fallback auf Node 22."
        TARGET_MAJOR=22
    fi
fi
echo "Gewaehlte Ziel-Major-Version fuer das isolierte Homebridge-Node: v${TARGET_MAJOR}"

echo ""
echo "============================================================"
echo "Schritt 3: Isoliertes Node.js fuer Homebridge einrichten (in PDATA)"
echo "============================================================"

ARCH=$(uname -m)
case "$ARCH" in
    aarch64) NODE_ARCH="arm64" ;;
    armv7l)  NODE_ARCH="armv7l" ;;
    x86_64)  NODE_ARCH="x64" ;;
    *)
        echo "FEHLER: Unbekannte/nicht unterstuetzte Architektur: $ARCH"
        exit 1
        ;;
esac

echo "Erkannte Architektur: $ARCH -> Node-Paket-Architektur: $NODE_ARCH"

NODE_FULL_VERSION=$(curl -fsSL https://nodejs.org/dist/index.json \
    | grep -oP "\"version\":\"v${TARGET_MAJOR}\.[0-9]+\.[0-9]+\"" \
    | head -1 | grep -oP 'v[0-9.]+')

if [ -z "$NODE_FULL_VERSION" ]; then
    echo "FEHLER: Konnte keine Node v${TARGET_MAJOR}.x Version von nodejs.org ermitteln."
    exit 1
fi

echo "Neueste verfuegbare Node v${TARGET_MAJOR}.x Version: $NODE_FULL_VERSION"

CURRENT_LOCAL_VERSION=""
if [ -x "$HB_NODE_DIR/bin/node" ]; then
    CURRENT_LOCAL_VERSION=$("$HB_NODE_DIR/bin/node" -v)
fi

if [ "$CURRENT_LOCAL_VERSION" != "$NODE_FULL_VERSION" ]; then
    echo "Installiere isoliertes Node $NODE_FULL_VERSION nach $HB_NODE_DIR ..."
    TMP_TAR="$PDATA/node-${NODE_FULL_VERSION}-linux-${NODE_ARCH}.tar.xz"
    curl -fsSL "https://nodejs.org/dist/${NODE_FULL_VERSION}/node-${NODE_FULL_VERSION}-linux-${NODE_ARCH}.tar.xz" -o "$TMP_TAR"
    rm -rf "$HB_NODE_DIR"
    mkdir -p "$HB_NODE_DIR"
    tar -xJf "$TMP_TAR" -C "$HB_NODE_DIR" --strip-components=1
    rm -f "$TMP_TAR"
    echo "Isoliertes Node installiert: $("$HB_NODE_DIR/bin/node" -v)"
else
    echo "Isoliertes Node ist bereits aktuell ($CURRENT_LOCAL_VERSION)."
fi

LOCAL_NODE="$HB_NODE_DIR/bin/node"
LOCAL_NPM="$HB_NODE_DIR/bin/npm"

if [ ! -x "$LOCAL_NODE" ] || [ ! -x "$LOCAL_NPM" ]; then
    echo "FEHLER: Isoliertes Node/npm nicht gefunden unter $HB_NODE_DIR/bin/"
    exit 1
fi

echo "Verwende isoliertes Node: $($LOCAL_NODE -v) / npm: $($LOCAL_NPM -v)"

echo ""
echo "============================================================"
echo "Schritt 4: Homebridge + Config UI X installieren (isoliert)"
echo "============================================================"

export PATH="$HB_NODE_DIR/bin:$PATH"

if ! "$LOCAL_NPM" install -g --unsafe-perm --prefix "$HB_NPM_GLOBAL" homebridge homebridge-config-ui-x; then
    echo "FEHLER: npm install homebridge/homebridge-config-ui-x fehlgeschlagen."
    exit 1
fi

echo "Homebridge-Installation erfolgreich."
"$HB_NPM_GLOBAL/bin/homebridge" -V 2>/dev/null || true

echo ""
echo "============================================================"
echo "Schritt 5: hb-service einrichten (Storage: $HB_STORAGE_DIR)"
echo "============================================================"

export PATH="$HB_NODE_DIR/bin:$HB_NPM_GLOBAL/bin:$PATH"
HB_SERVICE="$HB_NPM_GLOBAL/bin/hb-service"

if [ ! -x "$HB_SERVICE" ]; then
    echo "FEHLER: hb-service nicht gefunden unter $HB_SERVICE"
    exit 1
fi

SERVICE_UNIT="/etc/systemd/system/homebridge.service"

if systemctl list-unit-files 2>/dev/null | grep -q "^homebridge\.service"; then
    CONFIGURED_STORAGE=""
    if [ -f "$SERVICE_UNIT" ]; then
        CONFIGURED_STORAGE=$(grep -oP '(?<=-U )\S+' "$SERVICE_UNIT" | head -1)
    fi

    if [ -n "$CONFIGURED_STORAGE" ] && [ "$CONFIGURED_STORAGE" = "$HB_STORAGE_DIR" ]; then
        echo "hb-service-Dienst existiert bereits mit korrektem Storage-Pfad - Neustart."
        "$HB_SERVICE" restart || true
    else
        echo "hb-service-Dienst existiert mit abweichendem Storage-Pfad"
        echo "(gefunden: '${CONFIGURED_STORAGE:-unbekannt}', erwartet: '$HB_STORAGE_DIR') - wird neu eingerichtet."
        "$HB_SERVICE" uninstall || true
        "$HB_SERVICE" -U "$HB_STORAGE_DIR" --user loxberry --port 8082 install
    fi
else
    echo "Richte hb-service erstmalig ein (Storage: $HB_STORAGE_DIR) ..."
    "$HB_SERVICE" -U "$HB_STORAGE_DIR" --user loxberry --port 8082 install
fi

echo ""
echo "============================================================"
echo "Zusammenfassung"
echo "============================================================"
echo "System-Node:      $(node -v 2>/dev/null || echo 'n/a')"
echo "Homebridge-Node:   $($LOCAL_NODE -v)"
echo "Homebridge-Storage: $HB_STORAGE_DIR"
echo "Fertig."

exit 0