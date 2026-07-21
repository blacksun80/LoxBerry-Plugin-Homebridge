#!/bin/bash
# postroot.sh
#
# Laeuft als User "root", ganz am Ende der Installation/des Updates.
#
# Schritt 1: Homebridge-Config aus dem preroot.sh-Backup wiederherstellen.
# Schritt 2: Homebridge-/Node-Version ermitteln.
# Schritt 3: Isoliertes Node.js fuer Homebridge einrichten (persistent).
# Schritt 4: Homebridge + Config UI X installieren (isoliert).
# Schritt 5: hb-service einrichten/neu starten.
#
# Hinweis: Das System-Node des LoxBerry wird bewusst NICHT angefasst - Homebridge
# laeuft komplett im isolierten Node unter der persistenten Runtime.
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

# Config (Pairings): liegt in der Plugin-Config und wird bei Updates von LoxBerry
# geloescht; preroot.sh sichert sie, Schritt 1 stellt sie wieder her.
HB_STORAGE_DIR="$PCONFIG"

# Runtime (isoliertes Node.js + Homebridge): bewusst an einem PERSISTENTEN Ort
# ausserhalb der von LoxBerry bei Updates geloeschten Plugin-Ordner. So bleibt
# die Runtime ueber Updates erhalten und wird nur bei Bedarf neu aufgebaut.
HB_RUNTIME_DIR="$LBHOMEDIR/data/system/homebridge_runtime"
HB_NODE_DIR="$HB_RUNTIME_DIR/nodejs"
HB_NPM_GLOBAL="$HB_RUNTIME_DIR/npm-global"

set -e

mkdir -p "$HB_STORAGE_DIR"
mkdir -p "$HB_RUNTIME_DIR" "$HB_NPM_GLOBAL"

echo "============================================================"
echo "Schritt 1: Homebridge-Config wiederherstellen (falls Backup da)"
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
echo "Schritt 2: Homebridge-/Node-Version ermitteln"
echo "============================================================"

# Aktuelle Version + Node-Anforderung direkt aus der npm-Registry lesen
# (per curl statt 'npm view' - so entfaellt das riesige apt-npm-Paket komplett).
HB_UI_MANIFEST=$(curl -fsSL https://registry.npmjs.org/homebridge-config-ui-x/latest 2>/dev/null || echo "")
LATEST_HB_UI_VERSION=$(printf '%s' "$HB_UI_MANIFEST" | grep -oP '"version"\s*:\s*"\K[^"]+' | head -1)
INSTALLED_HB_UI_PKG="$HB_NPM_GLOBAL/lib/node_modules/homebridge-config-ui-x/package.json"
INSTALLED_HB_UI_VERSION=""
if [ -f "$INSTALLED_HB_UI_PKG" ]; then
    INSTALLED_HB_UI_VERSION=$(grep -oP '"version"\s*:\s*"\K[^"]+' "$INSTALLED_HB_UI_PKG" | head -1)
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

# Auch die Homebridge-Version selbst ermitteln (fuer die Reuse-Entscheidung in Schritt 4).
HB_MANIFEST=$(curl -fsSL https://registry.npmjs.org/homebridge/latest 2>/dev/null || echo "")
LATEST_HB_VERSION=$(printf '%s' "$HB_MANIFEST" | grep -oP '"version"\s*:\s*"\K[^"]+' | head -1)
INSTALLED_HB_PKG="$HB_NPM_GLOBAL/lib/node_modules/homebridge/package.json"
INSTALLED_HB_VERSION=""
if [ -f "$INSTALLED_HB_PKG" ]; then
    INSTALLED_HB_VERSION=$(grep -oP '"version"\s*:\s*"\K[^"]+' "$INSTALLED_HB_PKG" | head -1)
fi

# engines.node MUSS von BEIDEN Paketen passen - homebridge und config-ui-x
# koennen (und werden irgendwann) unterschiedliche Ranges deklarieren, z.B.
# wenn eines von beiden eine alte Major-Version fallen laesst. Deshalb aus
# beiden Manifesten getrennt lesen und nur die Schnittmenge der explizit
# unterstuetzten Majors verwenden - nie nur einem der beiden Pakete vertrauen.
REQUIRED_RANGE_UI=$(printf '%s' "$HB_UI_MANIFEST" | grep -oP '"engines"\s*:\s*\{[^}]*?"node"\s*:\s*"\K[^"]+' | head -1)
REQUIRED_RANGE_HB=$(printf '%s' "$HB_MANIFEST" | grep -oP '"engines"\s*:\s*\{[^}]*?"node"\s*:\s*"\K[^"]+' | head -1)

if [ -z "$REQUIRED_RANGE_UI" ] || [ -z "$REQUIRED_RANGE_HB" ]; then
    echo "Konnte engines.node nicht von beiden Paketen abfragen - Fallback auf Node 22."
    TARGET_MAJOR=22
else
    echo "engines.node von homebridge-config-ui-x: $REQUIRED_RANGE_UI"
    echo "engines.node von homebridge: $REQUIRED_RANGE_HB"
    MAJORS_UI=$(echo "$REQUIRED_RANGE_UI" | grep -oP '\^\K[0-9]+' | sort -nu)
    MAJORS_HB=$(echo "$REQUIRED_RANGE_HB" | grep -oP '\^\K[0-9]+' | sort -nu)
    # Schnittmenge (grep -Fxf statt "comm", damit die Sortierreihenfolge der
    # Eingaben keine Rolle spielt), davon die HOECHSTE gemeinsame Major-Version -
    # laengste Restlaufzeit bis zum Node-EOL unter den Versionen, die beide
    # Pakete tatsaechlich freigeben.
    TARGET_MAJOR=$(echo "$MAJORS_UI" | grep -Fxf <(echo "$MAJORS_HB") | sort -n | tail -1)
    if [ -z "$TARGET_MAJOR" ]; then
        echo "Keine gemeinsame Major-Version zwischen homebridge und config-ui-x gefunden - Fallback auf Node 22."
        TARGET_MAJOR=22
    fi
fi
echo "Gewaehlte Ziel-Major-Version fuer das isolierte Homebridge-Node: v${TARGET_MAJOR}"

echo ""
echo "============================================================"
echo "Schritt 3: Isoliertes Node.js einrichten (persistent, wird wiederverwendet)"
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

NODE_CHANGED=0
if [ "$CURRENT_LOCAL_VERSION" != "$NODE_FULL_VERSION" ]; then
    echo "Installiere isoliertes Node $NODE_FULL_VERSION nach $HB_NODE_DIR ..."
    TMP_TAR="$HB_RUNTIME_DIR/node-${NODE_FULL_VERSION}-linux-${NODE_ARCH}.tar.xz"
    NODE_DL_URL="https://nodejs.org/dist/${NODE_FULL_VERSION}/node-${NODE_FULL_VERSION}-linux-${NODE_ARCH}.tar.xz"

    # Download im Hintergrund + Heartbeat alle 15s (mit bisher geladener Groesse),
    # sonst gibt curl mit -s (unterdrueckt auch die Fortschrittsanzeige) ueber
    # Minuten hinweg keinerlei Lebenszeichen aus - das wirkt wie ein Haenger.
    # --speed-time/--speed-limit brechen ab, wenn der Transfer wirklich steht
    # (< 1 KB/s laenger als 30s), statt endlos lautlos zu warten.
    curl -fsSL --connect-timeout 15 --speed-time 30 --speed-limit 1024 \
        "$NODE_DL_URL" -o "$TMP_TAR" &
    CURL_PID=$!

    SECONDS=0
    while kill -0 "$CURL_PID" 2>/dev/null; do
        sleep 15
        MINS=$((SECONDS / 60)); SECS=$((SECONDS % 60))
        DL_SIZE=$(du -h "$TMP_TAR" 2>/dev/null | cut -f1)
        echo "... Node-Download laeuft noch (${MINS}m ${SECS}s) - bisher geladen: ${DL_SIZE:-0}"
    done

    CURL_RC=0
    wait "$CURL_PID" || CURL_RC=$?
    if [ "$CURL_RC" -ne 0 ]; then
        echo "FEHLER: Download von Node $NODE_FULL_VERSION fehlgeschlagen (curl Exit $CURL_RC)."
        rm -f "$TMP_TAR"
        exit 1
    fi

    rm -rf "$HB_NODE_DIR"
    mkdir -p "$HB_NODE_DIR"
    tar -xJf "$TMP_TAR" -C "$HB_NODE_DIR" --strip-components=1
    rm -f "$TMP_TAR"
    NODE_CHANGED=1
    echo "Isoliertes Node installiert: $("$HB_NODE_DIR/bin/node" -v)"
else
    echo "Isoliertes Node ist bereits aktuell ($CURRENT_LOCAL_VERSION) - wird wiederverwendet."
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

# Reuse-Entscheidung: Wenn das isolierte Node unveraendert ist UND Homebridge
# sowie Config UI X bereits in der neuesten Version vorliegen, sparen wir uns den
# kompletten Neu-Build (spart auf dem Pi mehrere Minuten). Bei geaendertem Node
# MUSS neu gebaut werden (native Module haengen an der Node-ABI). Konnten die
# Versionen nicht von npm abgefragt werden, wird sicherheitshalber gebaut.
# Node-Version geaendert (z.B. 22 -> 24): npm-global MUSS komplett neu
# aufgebaut werden. Ein einfaches "npm install -g homebridge ..." wuerde
# NICHTS tun, falls Homebridge/config-ui-x schon in der gewuenschten Version
# vorliegen (npm sieht die Anforderung als erfuellt an) - native Module wie
# node-pty (ABI-gebunden an die Node-Version) blieben dann als Binary fuer die
# ALTE Node-Version liegen und fuehren zum selben "Cannot find module
# .../pty.node"-Absturz, den wir schon einmal hatten (damals durch den
# fehlenden PATH-Fix ausgeloest, hier durch die Node-Version selbst).
if [ "$NODE_CHANGED" -eq 1 ]; then
    echo "Node-Version hat sich geaendert - npm-global wird komplett neu aufgebaut (native Module sind ABI-gebunden)."
    rm -rf "${HB_NPM_GLOBAL:?}"
    mkdir -p "$HB_NPM_GLOBAL"
fi

if [ "$NODE_CHANGED" -eq 0 ] \
   && [ -x "$HB_NPM_GLOBAL/bin/homebridge" ] && [ -x "$HB_NPM_GLOBAL/bin/hb-service" ] \
   && [ -n "$LATEST_HB_VERSION" ] && [ "$INSTALLED_HB_VERSION" = "$LATEST_HB_VERSION" ] \
   && [ -n "$LATEST_HB_UI_VERSION" ] && [ "$INSTALLED_HB_UI_VERSION" = "$LATEST_HB_UI_VERSION" ]; then
    echo "Runtime passt bereits: Homebridge v$INSTALLED_HB_VERSION + Config UI X v$INSTALLED_HB_UI_VERSION, Node $CURRENT_LOCAL_VERSION."
    echo "npm install wird uebersprungen (persistente Runtime wird wiederverwendet)."
else
    echo "Installiere/aktualisiere Homebridge + Config UI X (baut native Module - kann auf einem Pi mehrere Minuten dauern) ..."

    # npm laeuft im Hintergrund und schreibt in ein eigenes Logfile; parallel gibt
    # ein Heartbeat alle 15s ein Lebenszeichen aus, damit man im LoxBerry-Log sieht,
    # dass die Installation weiterlaeuft und nicht haengt.
    NPM_INSTALL_LOG="$HB_RUNTIME_DIR/npm-install.log"
    "$LOCAL_NPM" install -g --unsafe-perm --prefix "$HB_NPM_GLOBAL" \
        --no-audit --no-fund --loglevel=http \
        homebridge homebridge-config-ui-x > "$NPM_INSTALL_LOG" 2>&1 &
    NPM_PID=$!

    SECONDS=0
    while kill -0 "$NPM_PID" 2>/dev/null; do
        sleep 15
        MINS=$((SECONDS / 60)); SECS=$((SECONDS % 60))
        LAST_LINE=$(tail -n 1 "$NPM_INSTALL_LOG" 2>/dev/null)
        echo "... npm install laeuft noch (${MINS}m ${SECS}s) - zuletzt: ${LAST_LINE:-Pakete werden geladen/gebaut}"
    done

    NPM_RC=0
    wait "$NPM_PID" || NPM_RC=$?

    if [ "$NPM_RC" -ne 0 ]; then
        echo "FEHLER: npm install homebridge/homebridge-config-ui-x fehlgeschlagen (Exit $NPM_RC)."
        echo "Letzte 30 Zeilen des npm-Logs:"
        tail -n 30 "$NPM_INSTALL_LOG" 2>/dev/null
        exit 1
    fi

    echo "Homebridge-Installation erfolgreich (Details in $NPM_INSTALL_LOG)."
fi

"$HB_NPM_GLOBAL/bin/homebridge" -V 2>/dev/null || true

# Die komplette Runtime (Node + npm-global mit allen node_modules) wurde bis
# hierher komplett als root gebaut/installiert. Der Dienst laeuft aber als User
# "loxberry" (siehe Schritt 5). Zum reinen AUSFUEHREN reicht das (root-eigene
# Dateien sind fuer "andere" i.d.R. lesbar/ausfuehrbar), aber "loxberry" kann
# NICHT in die root-eigene npm-global-Baumstruktur SCHREIBEN. Das bricht das
# Installieren/Aktualisieren von Homebridge-Plugins ueber die Config-UI-
# Weboberflaeche, die intern npm install/update genau gegen diesen Pfad
# ausfuehrt. Deshalb hier auf loxberry umchownen - unabhaengig davon, ob oben
# neu gebaut oder die vorhandene Runtime wiederverwendet wurde.
echo "Setze Owner von $HB_RUNTIME_DIR auf loxberry:loxberry (fuer Plugin-Installation ueber die Config-UI) ..."
chown -R loxberry:loxberry "$HB_RUNTIME_DIR"

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

# Ein bereits vorhandenes homebridge.service-Unit stammt entweder vom alten
# Plugin (dessen ExecStart zeigt auf ein System-Node, nicht auf unsere isolierte
# Runtime) oder von einem frueheren Lauf dieses Skripts. In beiden Faellen: erst
# sauber deinstallieren, dann mit dem isolierten Node frisch registrieren, damit
# die Unit-ExecStart auf unser Node-Binary zeigt. Die Pairings/Config liegen im
# Storage-Verzeichnis ($HB_STORAGE_DIR) und werden von "hb-service uninstall"
# NICHT angetastet - ausserdem haben wir sie in preroot.sh gesichert.
if systemctl list-unit-files 2>/dev/null | grep -q "^homebridge\.service"; then
    # Der Storage-Pfad ($HB_STORAGE_DIR) ist durch die feste Installationsordner-
    # Konvention ($PDIR=homebridge) immer derselbe - eine Ermittlung des "alten"
    # Storage-Pfads ist daher unnoetig.
    echo "Vorhandenen homebridge-Dienst gefunden."
    echo "Wird deinstalliert und mit isoliertem Node neu registriert ..."
    "$HB_SERVICE" uninstall || true
    # Hart nachraeumen, falls das Unit doch noch da ist - sonst bricht das
    # folgende "install" mit "already installed" ab.
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

# hb-service generiert die systemd-Unit OHNE eigenes Environment=PATH=. Der darin
# verwendete "#!/usr/bin/env node"-Shebang loest "node" deshalb zur Laufzeit ueber
# systemds STANDARD-PATH auf - und findet dort ein evtl. vorhandenes System-Node
# (z.B. /usr/local/bin/node auf LoxBerry 4, oft eine viel neuere Version) VOR
# unserem isolierten Node. Folge: Die Config-UI laeuft mit falscher Node-Version,
# native Module wie node-pty (ABI-gebunden, beim npm install fuer UNSER Node
# gebaut) lassen sich nicht laden und die Weboberflaeche stuerzt in einer
# Restart-Schleife ab - waehrend die reine Homebridge-Bridge oft trotzdem
# weiterlaeuft, was im Log wie ein Erfolg aussieht. Deshalb unser isoliertes
# Node per Environment=PATH in der Unit erzwingen. Das muss NACH JEDEM Aufruf
# von "hb-service install" passieren, weil hb-service die Unit jedesmal neu
# schreibt (auch bei jedem Plugin-Update, s.o.) und ein reines PATH aus der
# vorherigen Installation dabei verloren ginge.
if [ -f "$SERVICE_UNIT" ]; then
    NODE_UNIT_PATH="${HB_NODE_DIR}/bin:${HB_NPM_GLOBAL}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    sed -i '/^Environment=PATH=/d' "$SERVICE_UNIT"
    sed -i "/^\[Service\]/a Environment=PATH=${NODE_UNIT_PATH}" "$SERVICE_UNIT"
    systemctl daemon-reload
    systemctl restart homebridge.service
    echo "Environment=PATH in $SERVICE_UNIT gesetzt (isoliertes Node zuerst) und Dienst neu gestartet."
else
    echo "FEHLER: $SERVICE_UNIT nach 'hb-service install' nicht gefunden - PATH-Fix konnte nicht angewendet werden."
    exit 1
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