#!/bin/bash
# postinstall.sh
#
# Laeuft als User "loxberry", nach dem Kopieren der Plugin-Dateien.
#
# Schritt 1: Config aus dem Backup zurueckholen (falls vorhanden).
# Schritt 2: Runtime aus dem Backup zurueckholen (falls vorhanden).
# Schritt 3: Benoetigte Node-Major-Version ermitteln.
# Schritt 4: Isoliertes Node.js einrichten (Download + Entpacken, falls noetig).
# Schritt 5: Homebridge + Config UI X installieren (npm, falls noetig).
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

BACKUP_ROOT="$LBHOMEDIR/data/system/tmp/homebridge_backup"
CONFIG_BACKUP="$BACKUP_ROOT/config"
RUNTIME_BACKUP="$BACKUP_ROOT/runtime"

mkdir -p "$HB_STORAGE_DIR" "$HB_RUNTIME_DIR" "$HB_NPM_GLOBAL"

echo "============================================================"
echo "Schritt 1: Config zurueckholen"
echo "============================================================"

if [ -d "$CONFIG_BACKUP" ] && [ -n "$(ls -A "$CONFIG_BACKUP" 2>/dev/null)" ]; then
    cp -a "$CONFIG_BACKUP"/. "$HB_STORAGE_DIR"/
    rm -rf "$CONFIG_BACKUP"
    echo "<OK> Config aus $CONFIG_BACKUP zurueckgeholt."
else
    echo "<INFO> Kein Config-Backup gefunden - Erstinstallation oder nichts zu sichern."
fi

echo ""
echo "============================================================"
echo "Schritt 2: Runtime zurueckholen"
echo "============================================================"

if [ -d "$RUNTIME_BACKUP" ] && [ -n "$(ls -A "$RUNTIME_BACKUP" 2>/dev/null)" ]; then
    rm -rf "$HB_RUNTIME_DIR"
    mv "$RUNTIME_BACKUP" "$HB_RUNTIME_DIR"
    echo "<OK> Runtime aus $RUNTIME_BACKUP zurueckgeholt."
else
    echo "<INFO> Kein Runtime-Backup gefunden - Erstinstallation oder Neuaufbau noetig."
fi

echo ""
echo "============================================================"
echo "Schritt 3: Benoetigte Node-Major-Version ermitteln"
echo "============================================================"

ARCH=$(uname -m)
case "$ARCH" in
    aarch64) NODE_ARCH="arm64" ;;
    armv7l)  NODE_ARCH="armv7l" ;;
    x86_64)  NODE_ARCH="x64" ;;
    *)
        echo "FEHLER: Unbekannte Architektur: $ARCH"
        exit 1
        ;;
esac

HB_UI_MANIFEST=$(curl -fsSL https://registry.npmjs.org/homebridge-config-ui-x/latest 2>/dev/null || echo "")
LATEST_HB_UI_VERSION=$(printf '%s' "$HB_UI_MANIFEST" | grep -oP '"version"\s*:\s*"\K[^"]+' | head -1)
INSTALLED_HB_UI_PKG="$HB_NPM_GLOBAL/lib/node_modules/homebridge-config-ui-x/package.json"
INSTALLED_HB_UI_VERSION=""
[ -f "$INSTALLED_HB_UI_PKG" ] && INSTALLED_HB_UI_VERSION=$(grep -oP '"version"\s*:\s*"\K[^"]+' "$INSTALLED_HB_UI_PKG" | head -1)

HB_MANIFEST=$(curl -fsSL https://registry.npmjs.org/homebridge/latest 2>/dev/null || echo "")
LATEST_HB_VERSION=$(printf '%s' "$HB_MANIFEST" | grep -oP '"version"\s*:\s*"\K[^"]+' | head -1)
INSTALLED_HB_PKG="$HB_NPM_GLOBAL/lib/node_modules/homebridge/package.json"
INSTALLED_HB_VERSION=""
[ -f "$INSTALLED_HB_PKG" ] && INSTALLED_HB_VERSION=$(grep -oP '"version"\s*:\s*"\K[^"]+' "$INSTALLED_HB_PKG" | head -1)

echo "homebridge: installiert=${INSTALLED_HB_VERSION:-keine}, aktuell=${LATEST_HB_VERSION:-unbekannt}"
echo "homebridge-config-ui-x: installiert=${INSTALLED_HB_UI_VERSION:-keine}, aktuell=${LATEST_HB_UI_VERSION:-unbekannt}"

REQUIRED_RANGE_UI=$(printf '%s' "$HB_UI_MANIFEST" | grep -oP '"engines"\s*:\s*\{[^}]*?"node"\s*:\s*"\K[^"]+' | head -1)
REQUIRED_RANGE_HB=$(printf '%s' "$HB_MANIFEST" | grep -oP '"engines"\s*:\s*\{[^}]*?"node"\s*:\s*"\K[^"]+' | head -1)

if [ -z "$REQUIRED_RANGE_UI" ] || [ -z "$REQUIRED_RANGE_HB" ]; then
    echo "Konnte engines.node nicht ermitteln - Fallback auf Node 22."
    CANDIDATE_MAJORS=22
else
    MAJORS_UI=$(echo "$REQUIRED_RANGE_UI" | grep -oP '\^\K[0-9]+' | sort -nu)
    MAJORS_HB=$(echo "$REQUIRED_RANGE_HB" | grep -oP '\^\K[0-9]+' | sort -nu)
    CANDIDATE_MAJORS=$(echo "$MAJORS_UI" | grep -Fxf <(echo "$MAJORS_HB") | sort -rn)
    if [ -z "$CANDIDATE_MAJORS" ]; then
        echo "Keine gemeinsame Major-Version gefunden - Fallback auf Node 22."
        CANDIDATE_MAJORS=22
    fi
fi

NODE_INDEX=$(curl -fsSL https://nodejs.org/dist/index.json 2>/dev/null || echo "")
TARGET_MAJOR=""
NODE_FULL_VERSION=""
for CANDIDATE in $CANDIDATE_MAJORS; do
    FULL=$(printf '%s' "$NODE_INDEX" | grep -oP "\"version\":\"v${CANDIDATE}\.[0-9]+\.[0-9]+\"" | head -1 | grep -oP 'v[0-9.]+')
    [ -z "$FULL" ] && continue
    DL_URL="https://nodejs.org/dist/${FULL}/node-${FULL}-linux-${NODE_ARCH}.tar.xz"
    if curl -fsSL --connect-timeout 15 -o /dev/null -I "$DL_URL" 2>/dev/null; then
        TARGET_MAJOR=$CANDIDATE
        NODE_FULL_VERSION=$FULL
        break
    fi
done

if [ -z "$TARGET_MAJOR" ]; then
    echo "FEHLER: Kein Node-Build fuer linux-${NODE_ARCH} gefunden."
    exit 1
fi

echo "Ziel-Node-Version: $NODE_FULL_VERSION"

echo ""
echo "============================================================"
echo "Schritt 4: Isoliertes Node.js einrichten"
echo "============================================================"

CURRENT_LOCAL_VERSION=""
[ -x "$HB_NODE_DIR/bin/node" ] && CURRENT_LOCAL_VERSION=$("$HB_NODE_DIR/bin/node" -v)

NODE_CHANGED=0
if [ "$CURRENT_LOCAL_VERSION" != "$NODE_FULL_VERSION" ]; then
    echo "Lade Node $NODE_FULL_VERSION nach $HB_NODE_DIR ..."
    TMP_TAR="$HB_RUNTIME_DIR/node-${NODE_FULL_VERSION}-linux-${NODE_ARCH}.tar.xz"
    NODE_DL_URL="https://nodejs.org/dist/${NODE_FULL_VERSION}/node-${NODE_FULL_VERSION}-linux-${NODE_ARCH}.tar.xz"

    curl -fsSL --connect-timeout 15 --speed-time 30 --speed-limit 1024 "$NODE_DL_URL" -o "$TMP_TAR" &
    CURL_PID=$!
    SECONDS=0
    while kill -0 "$CURL_PID" 2>/dev/null; do
        sleep 15
        MINS=$((SECONDS / 60)); SECS=$((SECONDS % 60))
        DL_SIZE=$(du -h "$TMP_TAR" 2>/dev/null | cut -f1)
        echo "... Download laeuft (${MINS}m ${SECS}s) - bisher: ${DL_SIZE:-0}"
    done
    wait "$CURL_PID"
    CURL_RC=$?
    if [ "$CURL_RC" -ne 0 ]; then
        echo "FEHLER: Node-Download fehlgeschlagen (Exit $CURL_RC)."
        rm -f "$TMP_TAR"
        exit 1
    fi

    rm -rf "$HB_NODE_DIR"
    mkdir -p "$HB_NODE_DIR"
    tar -xJf "$TMP_TAR" -C "$HB_NODE_DIR" --strip-components=1
    rm -f "$TMP_TAR"
    NODE_CHANGED=1
    echo "Node installiert: $("$HB_NODE_DIR/bin/node" -v)"
else
    echo "Node ist aktuell ($CURRENT_LOCAL_VERSION) - wird wiederverwendet."
fi

LOCAL_NODE="$HB_NODE_DIR/bin/node"
LOCAL_NPM="$HB_NODE_DIR/bin/npm"

if [ ! -x "$LOCAL_NODE" ] || [ ! -x "$LOCAL_NPM" ]; then
    echo "FEHLER: Node/npm nicht gefunden unter $HB_NODE_DIR/bin/"
    exit 1
fi

export PATH="$HB_NODE_DIR/bin:$PATH"
echo "Verwende Node: $($LOCAL_NODE -v) / npm: $($LOCAL_NPM -v)"

echo ""
echo "============================================================"
echo "Schritt 5: Homebridge + Config UI X installieren"
echo "============================================================"

if [ "$NODE_CHANGED" -eq 1 ]; then
    echo "Node-Version geaendert - npm-global wird neu aufgebaut."
    rm -rf "${HB_NPM_GLOBAL:?}"
    mkdir -p "$HB_NPM_GLOBAL"
fi

if [ "$NODE_CHANGED" -eq 0 ] \
   && [ -x "$HB_NPM_GLOBAL/bin/homebridge" ] && [ -x "$HB_NPM_GLOBAL/bin/hb-service" ] \
   && [ -n "$LATEST_HB_VERSION" ] && [ "$INSTALLED_HB_VERSION" = "$LATEST_HB_VERSION" ] \
   && [ -n "$LATEST_HB_UI_VERSION" ] && [ "$INSTALLED_HB_UI_VERSION" = "$LATEST_HB_UI_VERSION" ]; then
    echo "Runtime passt bereits - npm install wird uebersprungen."
else
    echo "Installiere/aktualisiere Homebridge + Config UI X ..."
    NPM_INSTALL_LOG="$HB_RUNTIME_DIR/npm-install.log"
    "$LOCAL_NPM" install -g --prefix "$HB_NPM_GLOBAL" \
        --no-audit --no-fund --loglevel=http \
        homebridge homebridge-config-ui-x > "$NPM_INSTALL_LOG" 2>&1 &
    NPM_PID=$!
    SECONDS=0
    while kill -0 "$NPM_PID" 2>/dev/null; do
        sleep 15
        MINS=$((SECONDS / 60)); SECS=$((SECONDS % 60))
        LAST_LINE=$(tail -n 1 "$NPM_INSTALL_LOG" 2>/dev/null)
        echo "... npm install laeuft (${MINS}m ${SECS}s) - zuletzt: ${LAST_LINE:-...}"
    done
    wait "$NPM_PID"
    NPM_RC=$?
    if [ "$NPM_RC" -ne 0 ]; then
        echo "FEHLER: npm install fehlgeschlagen (Exit $NPM_RC)."
        tail -n 30 "$NPM_INSTALL_LOG" 2>/dev/null
        exit 1
    fi
    echo "Homebridge-Installation erfolgreich."
fi

"$HB_NPM_GLOBAL/bin/homebridge" -V 2>/dev/null || true

exit 0
